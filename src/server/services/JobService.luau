--[[
	JobService — MY CITY
	Starter jobs, work sessions, payouts via PlayerDataService (Money / XP), city bonuses,
	daily missions, dismissal cooldown, and peer reviews.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local GAME_LABEL = "MY CITY"
local DATASTORE_NAME = "MY_CITY_PlayerData_v1"
local MAYOR_JOB_PREFIX = "Mayor of "
local DISMISSAL_COOLDOWN = 6 * 86400

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local CityService = require(script.Parent:WaitForChild("CityService") :: ModuleScript)
local ElectionService = require(script.Parent:WaitForChild("ElectionService") :: ModuleScript)
local OutfitService = require(script.Parent:WaitForChild("OutfitService"))
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)

local reviewDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

export type DailyMissionReward = {
	money: number,
	rep: number,
}

export type DailyMission = {
	task: string,
	goal: number,
	reward: DailyMissionReward,
}

export type JobDefinition = {
	Name: string,
	Description: string,
	BasePay: number,
	WorkDuration: number,
	RequiredReputation: number,
	City: string,
	Tier: number,
	DailyMission: DailyMission?,
}

-- Ordered list of job names for stable GetJobs() / validation.
local JOB_ORDER = {
	"Street Cleaner",
	"Factory Worker",
	"Tour Guide",
	"Police Officer",
	"Firefighter",
	"Doctor",
	"Nurse",
	"Teacher",
	"Security",
	"Electrician",
}

local JOBS: { [string]: JobDefinition } = {
	["Street Cleaner"] = {
		Name = "Street Cleaner",
		Description = "Keep streets tidy; a reliable entry job for new residents.",
		BasePay = 10,
		WorkDuration = 15,
		RequiredReputation = 0,
		City = "Any",
		Tier = 1,
	},
	["Factory Worker"] = {
		Name = "Factory Worker",
		Description = "Assembly and machine work on the industrial floor.",
		BasePay = 20,
		WorkDuration = 20,
		RequiredReputation = 0,
		City = "Ironholm",
		Tier = 1,
	},
	["Tour Guide"] = {
		Name = "Tour Guide",
		Description = "Show visitors the best spots and local stories.",
		BasePay = 20,
		WorkDuration = 20,
		RequiredReputation = 0,
		City = "Solara",
		Tier = 1,
	},
	["Police Officer"] = {
		Name = "Police Officer",
		Description = "Patrol and keep public order across the city.",
		BasePay = 25,
		WorkDuration = 25,
		RequiredReputation = 10,
		City = "Any",
		Tier = 1,
	},
	["Firefighter"] = {
		Name = "Firefighter",
		Description = "Protect the city from fires",
		BasePay = 30,
		WorkDuration = 25,
		RequiredReputation = 20,
		City = "Any",
		Tier = 2,
		DailyMission = {
			task = "Respond to 3 fire calls",
			goal = 3,
			reward = { money = 150, rep = 20 },
		},
	},
	["Doctor"] = {
		Name = "Doctor",
		Description = "Heal citizens and save lives",
		BasePay = 50,
		WorkDuration = 30,
		RequiredReputation = 100,
		City = "Any",
		Tier = 3,
		DailyMission = {
			task = "Treat 5 patients",
			goal = 5,
			reward = { money = 300, rep = 40 },
		},
	},
	["Nurse"] = {
		Name = "Nurse",
		Description = "Assist doctors and care for patients",
		BasePay = 35,
		WorkDuration = 25,
		RequiredReputation = 50,
		City = "Any",
		Tier = 2,
		DailyMission = {
			task = "Assist 4 patients",
			goal = 4,
			reward = { money = 180, rep = 25 },
		},
	},
	["Teacher"] = {
		Name = "Teacher",
		Description = "Educate the next generation",
		BasePay = 30,
		WorkDuration = 20,
		RequiredReputation = 30,
		City = "Ironholm",
		Tier = 2,
		DailyMission = {
			task = "Complete 4 lessons",
			goal = 4,
			reward = { money = 150, rep = 30 },
		},
	},
	["Security"] = {
		Name = "Security",
		Description = "Security guard — keep buildings and people safe",
		BasePay = 25,
		WorkDuration = 20,
		RequiredReputation = 10,
		City = "Any",
		Tier = 1,
		DailyMission = {
			task = "Complete 3 patrol rounds",
			goal = 3,
			reward = { money = 120, rep = 15 },
		},
	},
	["Electrician"] = {
		Name = "Electrician",
		Description = "Maintain the city's power grid",
		BasePay = 40,
		WorkDuration = 25,
		RequiredReputation = 15,
		City = "Ironholm",
		Tier = 2,
		DailyMission = {
			task = "Fix 3 electrical faults",
			goal = 3,
			reward = { money = 200, rep = 20 },
		},
	},
}

-- Active work: player -> { jobName, startedAt }
local workSessions: { [Player]: { jobName: string, startedAt: number } } = {}

local function jobExists(jobName: string): boolean
	return JOBS[jobName] ~= nil
end

local function isMayorJob(jobTitle: string): boolean
	return typeof(jobTitle) == "string" and string.sub(jobTitle, 1, #MAYOR_JOB_PREFIX) == MAYOR_JOB_PREFIX
end

local function calendarDayKey(fromUnix: number?): number
	local t = os.date("*t", fromUnix or os.time()) :: { year: number, month: number, day: number }
	return t.year * 10000 + t.month * 100 + t.day
end

local function yesterdayCalendarKey(): number
	return calendarDayKey(os.time() - 86400)
end

local function getShowNotification(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
	if not folder then
		return nil
	end
	local ev = folder:FindFirstChild("ShowNotification")
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function notifyPlayer(player: Player, message: string)
	local ev = getShowNotification()
	if ev then
		ev:FireClient(player, message, "info")
	end
end

local function cloneMissionProgress(raw: any): { [string]: any }
	local out: { [string]: any } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for k, v in raw :: { [any]: any } do
		if typeof(k) == "string" and typeof(v) == "table" then
			out[k] = table.clone(v :: { [string]: any })
		end
	end
	return out
end

local function defaultMissionEntry(): { [string]: any }
	local dk = calendarDayKey()
	return {
		completedToday = 0,
		lastReset = dk,
		streakDays = 0,
		missedDays = 0,
		lastRewardDay = 0,
		lastStreakCheckDay = 0,
		firstEmployDay = dk,
	}
end

local function ensureMissionEntry(mp: { [string]: any }, jobName: string): { [string]: any }
	local e = mp[jobName]
	if typeof(e) ~= "table" then
		e = defaultMissionEntry()
		mp[jobName] = e
	end
	return e :: { [string]: any }
end

local function resetMissionEntryAtMidnight(e: { [string]: any })
	local dk = calendarDayKey()
	local lastReset = typeof(e.lastReset) == "number" and e.lastReset or 0
	if lastReset ~= dk then
		e.completedToday = 0
		e.lastReset = dk
	end
end

local function canApplyForJob(player: Player, jobName: string): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded."
	end
	local dismissedFrom = typeof(data.DismissedFrom) == "string" and data.DismissedFrom or ""
	local dismissalTime = typeof(data.DismissalTime) == "number" and data.DismissalTime or 0
	if dismissedFrom == "" or dismissalTime == 0 then
		return true
	end
	local elapsed = os.time() - dismissalTime
	if dismissedFrom == jobName and elapsed < DISMISSAL_COOLDOWN then
		local remain = DISMISSAL_COOLDOWN - elapsed
		local days = math.max(1, math.ceil(remain / 86400))
		return false, string.format("You must wait %d days before returning to this job.", days)
	end
	local oldJob = JOBS[dismissedFrom]
	local newJob = JOBS[jobName]
	local oldTier = (oldJob and oldJob.Tier) or 1
	local newTier = (newJob and newJob.Tier) or 1
	if elapsed < DISMISSAL_COOLDOWN and newTier >= oldTier then
		return false, "Work a lower-tier job first after dismissal."
	end
	return true
end

local function playerQualifiesForJob(player: Player, jobName: string): boolean
	local job = JOBS[jobName]
	if not job then
		return false
	end

	local data = PlayerDataService.GetData(player)
	if not data then
		return false
	end

	if data.Reputation < job.RequiredReputation then
		return false
	end

	if job.City ~= "Any" and data.City ~= job.City then
		return false
	end

	local okApply, _ = canApplyForJob(player, jobName)
	return okApply
end

-- Ironholm + Factory Worker / Solara + Tour Guide / Ironholm city jobs: +20% pay where configured.
local function computePayout(player: Player, jobName: string, job: JobDefinition): number
	local pay = job.BasePay
	local data = PlayerDataService.GetData(player)
	if not data then
		return math.floor(pay + 0.5)
	end

	local city = data.City
	if city == "Ironholm" and jobName == "Factory Worker" then
		pay = pay * 1.2
	elseif city == "Solara" and jobName == "Tour Guide" then
		pay = pay * 1.2
	elseif city == "Ironholm" and (jobName == "Teacher" or jobName == "Electrician") then
		pay = pay * 1.2
	end

	if typeof(city) == "string" and city ~= "None" and ElectionService.CityHasActiveMayor(city) then
		pay = pay * 1.1
	end

	if typeof(city) == "string" and city ~= "None" then
		pay = pay * ElectionService.GetTradeEconomyPayMultiplier(city)
	end

	return math.floor(pay + 0.5)
end

local function runWorkLoop(player: Player, jobName: string)
	while workSessions[player] and workSessions[player].jobName == jobName do
		local job = JOBS[jobName]
		if not job then
			break
		end

		task.wait(job.WorkDuration)

		if not workSessions[player] or workSessions[player].jobName ~= jobName then
			break
		end

		local data = PlayerDataService.GetData(player)
		if not data then
			workSessions[player] = nil
			break
		end

		local earned = computePayout(player, jobName, job)
		local newMoney = data.Money + earned
		local newXP = data.XP + 1

		if not PlayerDataService.SetData(player, "Money", newMoney) then
			warn(string.format("[%s] Work payout: failed to save Money for %s", GAME_LABEL, player.Name))
			break
		end

		if not PlayerDataService.SetData(player, "XP", newXP) then
			warn(string.format("[%s] Work payout: failed to save XP for %s", GAME_LABEL, player.Name))
			break
		end

		print(
			string.format(
				"[%s] %s completed a work cycle as %s — earned %d CC",
				GAME_LABEL,
				player.Name,
				jobName,
				earned
			)
		)
	end
end

local JobService = {}

function JobService.GetJobs(): { JobDefinition }
	local list: { JobDefinition } = {}
	for _, name in JOB_ORDER do
		table.insert(list, table.clone(JOBS[name]))
	end
	return list
end

function JobService.GetAvailableJobs(player: Player): { JobDefinition }
	local available: { JobDefinition } = {}
	for _, name in JOB_ORDER do
		if playerQualifiesForJob(player, name) then
			table.insert(available, table.clone(JOBS[name]))
		end
	end
	return available
end

function JobService.IsWorking(player: Player): boolean
	return workSessions[player] ~= nil
end

function JobService.CanApplyForJob(player: Player, jobName: string): (boolean, string?)
	if not jobExists(jobName) then
		return false, "Unknown job."
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded."
	end
	if data.Reputation < (JOBS[jobName].RequiredReputation or 0) then
		return false, "Not enough reputation."
	end
	local job = JOBS[jobName]
	if job.City ~= "Any" and data.City ~= job.City then
		return false, "Wrong city for this job."
	end
	return canApplyForJob(player, jobName)
end

function JobService.StartWork(player: Player, jobName: string): boolean
	if workSessions[player] then
		print(string.format("[%s] StartWork: %s is already working", GAME_LABEL, player.Name))
		return false
	end

	if not jobExists(jobName) then
		print(string.format("[%s] StartWork: unknown job %q for %s", GAME_LABEL, jobName, player.Name))
		return false
	end

	local pdata = PlayerDataService.GetData(player)
	if pdata and typeof(pdata.Job) == "string" and isMayorJob(pdata.Job) then
		print(string.format("[%s] StartWork: %s is mayor and cannot take a regular job shift", GAME_LABEL, player.Name))
		return false
	end

	if not playerQualifiesForJob(player, jobName) then
		print(string.format("[%s] StartWork: %s does not qualify for %q", GAME_LABEL, player.Name, jobName))
		return false
	end

	workSessions[player] = {
		jobName = jobName,
		startedAt = os.time(),
	}

	local data = PlayerDataService.GetData(player)
	if data and typeof(data.Job) == "string" and not isMayorJob(data.Job) then
		PlayerDataService.SetData(player, "Job", jobName)
	end

	local jobDef = JOBS[jobName]
	if jobDef and jobDef.DailyMission then
		local fresh = PlayerDataService.GetData(player)
		local mp = cloneMissionProgress(fresh and fresh.MissionProgress or {})
		local e = ensureMissionEntry(mp, jobName)
		local dk = calendarDayKey()
		if typeof(e.firstEmployDay) ~= "number" or e.firstEmployDay == 0 then
			e.firstEmployDay = dk
		end
		PlayerDataService.SetData(player, "MissionProgress", mp)
	end

	task.spawn(runWorkLoop, player, jobName)

	OutfitService.ApplyOutfit(player, jobName)

	print(string.format("[%s] %s started work as %s", GAME_LABEL, player.Name, jobName))

	pcall(function()
		local MissionService = require(script.Parent:WaitForChild("MissionService"))
		if MissionService.NotifyPlayerJobUpdated then
			MissionService.NotifyPlayerJobUpdated(player)
		end
	end)

	return true
end

function JobService.StopWork(player: Player)
	if not workSessions[player] then
		return
	end

	local jobName = workSessions[player].jobName
	workSessions[player] = nil

	local data = PlayerDataService.GetData(player)
	if data and typeof(data.Job) == "string" and data.Job == jobName and not isMayorJob(data.Job) then
		PlayerDataService.SetData(player, "Job", "Unemployed")
	end

	OutfitService.RemoveOutfit(player)

	print(string.format("[%s] %s stopped work (%s)", GAME_LABEL, player.Name, jobName))

	pcall(function()
		local MissionService = require(script.Parent:WaitForChild("MissionService"))
		if MissionService.NotifyPlayerJobUpdated then
			MissionService.NotifyPlayerJobUpdated(player)
		end
	end)
end

function JobService.DismissPlayer(player: Player, jobName: string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	local currentTitle = typeof(data.Job) == "string" and data.Job or ""
	if isMayorJob(currentTitle) then
		return
	end
	local jName = jobName or currentTitle
	if jName == "Unemployed" or jName == "Unknown" or isMayorJob(jName) then
		return
	end

	JobService.StopWork(player)

	if not PlayerDataService.SetData(player, "Job", "Unemployed") then
		return
	end
	PlayerDataService.SetData(player, "DismissedFrom", jName)
	PlayerDataService.SetData(player, "DismissalTime", os.time())

	local mp = cloneMissionProgress(data.MissionProgress)
	mp[jName] = nil
	PlayerDataService.SetData(player, "MissionProgress", mp)

	local msg = string.format("You have been dismissed from %s for missing 2 days of missions!", jName)
	notifyPlayer(player, msg)
	print(string.format("[%s] %s dismissed from %s", GAME_LABEL, player.Name, jName))

	pcall(function()
		local MissionService = require(script.Parent:WaitForChild("MissionService"))
		if MissionService.NotifyPlayerJobUpdated then
			MissionService.NotifyPlayerJobUpdated(player)
		end
	end)
end

function JobService.CheckMissionStreak(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	local jobTitle = typeof(data.Job) == "string" and data.Job or "Unemployed"
	if jobTitle == "Unemployed" or isMayorJob(jobTitle) then
		return
	end
	local jobDef = JOBS[jobTitle]
	if not jobDef or not jobDef.DailyMission then
		return
	end

	local todayK = calendarDayKey()
	local yestK = yesterdayCalendarKey()
	local mp = cloneMissionProgress(data.MissionProgress)
	local e = ensureMissionEntry(mp, jobTitle)
	if typeof(e.firstEmployDay) ~= "number" or e.firstEmployDay == 0 then
		e.firstEmployDay = todayK
		e.lastStreakCheckDay = todayK
		PlayerDataService.SetData(player, "MissionProgress", mp)
		return
	end
	local firstDay = e.firstEmployDay :: number
	if yestK < firstDay then
		e.lastStreakCheckDay = todayK
		PlayerDataService.SetData(player, "MissionProgress", mp)
		return
	end

	if typeof(e.lastStreakCheckDay) == "number" and e.lastStreakCheckDay == todayK then
		return
	end

	local lastReward = typeof(e.lastRewardDay) == "number" and e.lastRewardDay or 0
	if lastReward < yestK then
		e.missedDays = (typeof(e.missedDays) == "number" and e.missedDays or 0) + 1
	end
	e.lastStreakCheckDay = todayK

	if not PlayerDataService.SetData(player, "MissionProgress", mp) then
		return
	end

	if (e.missedDays :: number) >= 2 then
		JobService.DismissPlayer(player, jobTitle)
	end
end

function JobService.CompleteMission(player: Player, jobName: string): { success: boolean, message: string }
	if typeof(jobName) ~= "string" or jobName == "" then
		return { success = false, message = "Invalid job." }
	end
	local jobDef = JOBS[jobName]
	if not jobDef or not jobDef.DailyMission then
		return { success = false, message = "No daily mission for this job." }
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return { success = false, message = "Data not loaded." }
	end

	local active = workSessions[player] and workSessions[player].jobName or nil
	local storedJob = typeof(data.Job) == "string" and data.Job or "Unemployed"
	if active ~= jobName and storedJob ~= jobName then
		return { success = false, message = "You are not working this job." }
	end

	local mp = cloneMissionProgress(data.MissionProgress)
	local e = ensureMissionEntry(mp, jobName)
	resetMissionEntryAtMidnight(e)

	local todayK = calendarDayKey()
	local lastReward = typeof(e.lastRewardDay) == "number" and e.lastRewardDay or 0
	if lastReward == todayK then
		return { success = false, message = "Daily mission already completed today." }
	end

	e.completedToday = (typeof(e.completedToday) == "number" and e.completedToday or 0) + 1
	local goal = jobDef.DailyMission.goal
	if e.completedToday < goal then
		PlayerDataService.SetData(player, "MissionProgress", mp)
		return { success = true, message = string.format("Progress: %d / %d", e.completedToday, goal) }
	end

	local reward = jobDef.DailyMission.reward
	local money = typeof(reward.money) == "number" and reward.money or 0
	local rep = typeof(reward.rep) == "number" and reward.rep or 0
	local newMoney = (typeof(data.Money) == "number" and data.Money or 0) + money
	if not PlayerDataService.SetData(player, "Money", newMoney) then
		return { success = false, message = "Could not save reward." }
	end
	if rep > 0 then
		ReputationService.AddReputation(player, rep, "Daily mission: " .. jobName)
	end

	e.completedToday = 0
	e.lastRewardDay = todayK
	e.streakDays = (typeof(e.streakDays) == "number" and e.streakDays or 0) + 1
	e.missedDays = 0

	if not PlayerDataService.SetData(player, "MissionProgress", mp) then
		return { success = false, message = "Could not save mission progress." }
	end

	print(string.format("[%s] %s completed daily mission for %s", GAME_LABEL, player.Name, jobName))
	return { success = true, message = "Daily mission complete!" }
end

function JobService.GetMissionProgress(player: Player): { success: boolean, message: string?, data: any? }
	local d = PlayerDataService.GetData(player)
	if not d then
		return { success = false, message = "Data not loaded." }
	end
	local jobTitle = typeof(d.Job) == "string" and d.Job or "Unemployed"
	local mp = cloneMissionProgress(d.MissionProgress)
	local payload: { [string]: any } = {
		job = jobTitle,
		missions = mp,
		todayKey = calendarDayKey(),
		dismissedFrom = typeof(d.DismissedFrom) == "string" and d.DismissedFrom or "",
		dismissalTime = typeof(d.DismissalTime) == "number" and d.DismissalTime or 0,
		dismissalCooldownSec = DISMISSAL_COOLDOWN,
	}
	local def = JOBS[jobTitle]
	if def and def.DailyMission then
		local e = ensureMissionEntry(mp, jobTitle)
		local dk = calendarDayKey()
		local lastReset = typeof(e.lastReset) == "number" and e.lastReset or 0
		local completedShow = if lastReset == dk then (typeof(e.completedToday) == "number" and e.completedToday or 0) else 0
		payload.goal = def.DailyMission.goal
		payload.task = def.DailyMission.task
		payload.completedToday = completedShow
		payload.lastRewardDay = e.lastRewardDay
		payload.streakDays = e.streakDays
		payload.missedDays = e.missedDays
		payload.rewardMoney = def.DailyMission.reward.money
		payload.rewardRep = def.DailyMission.reward.rep
	end
	return { success = true, data = payload }
end

local function recalcAverageRating(reviews: { any }): number
	if typeof(reviews) ~= "table" or #reviews == 0 then
		return 0
	end
	local sum = 0
	local n = 0
	for _, r in reviews do
		if typeof(r) == "table" and typeof((r :: any).stars) == "number" then
			sum += (r :: any).stars
			n += 1
		end
	end
	if n == 0 then
		return 0
	end
	return math.floor((sum / n) * 10 + 0.5) / 10
end

function JobService.LeaveReview(
	reviewerPlayer: Player,
	targetUserId: number,
	stars: number,
	comment: string
): { success: boolean, message: string }
	if typeof(targetUserId) ~= "number" or targetUserId <= 0 then
		return { success = false, message = "Invalid target." }
	end
	if typeof(stars) ~= "number" or stars < 1 or stars > 5 or stars ~= math.floor(stars) then
		return { success = false, message = "Stars must be 1–5." }
	end
	if typeof(comment) ~= "string" then
		comment = ""
	end
	if #comment > 280 then
		return { success = false, message = "Comment too long." }
	end
	if reviewerPlayer.UserId == targetUserId then
		return { success = false, message = "Cannot review yourself." }
	end

	local rData = PlayerDataService.GetData(reviewerPlayer)
	if not rData then
		return { success = false, message = "Data not loaded." }
	end
	local rCity = typeof(rData.City) == "string" and rData.City or "None"
	if rCity == "None" then
		return { success = false, message = "Join a city to leave reviews." }
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return { success = false, message = "Target player must be online." }
	end
	local tData = PlayerDataService.GetData(targetPlayer)
	if not tData then
		return { success = false, message = "Target data not loaded." }
	end
	local tCity = typeof(tData.City) == "string" and tData.City or "None"
	if tCity ~= rCity then
		return { success = false, message = "You can only review players in your city." }
	end

	local reviews = if typeof(tData.Reviews) == "table" then table.clone(tData.Reviews :: { any }) else {}
	local todayK = calendarDayKey()
	for _, rev in reviews do
		if typeof(rev) == "table" then
			local rid = (rev :: any).reviewerUserId
			local dayK = (rev :: any).reviewDay
			if rid == reviewerPlayer.UserId and dayK == todayK then
				return { success = false, message = "You already reviewed this player today." }
			end
		end
	end

	local jobName = typeof(rData.Job) == "string" and rData.Job or "Unemployed"
	table.insert(reviews, {
		reviewerName = reviewerPlayer.DisplayName,
		reviewerUserId = reviewerPlayer.UserId,
		stars = stars,
		comment = comment,
		timestamp = os.time(),
		jobName = jobName,
		reviewDay = todayK,
	})
	local avg = recalcAverageRating(reviews)
	if not PlayerDataService.SetData(targetPlayer, "Reviews", reviews) then
		return { success = false, message = "Could not save review." }
	end
	PlayerDataService.SetData(targetPlayer, "AverageRating", avg)

	print(
		string.format(
			"[%s] %s left %d stars for %s: %s",
			GAME_LABEL,
			reviewerPlayer.Name,
			stars,
			targetPlayer.Name,
			comment
		)
	)
	return { success = true, message = "Review saved." }
end

function JobService.GetReviews(_player: Player, targetUserId: number): { success: boolean, reviews: any, averageRating: number, message: string? }
	if typeof(targetUserId) ~= "number" or targetUserId <= 0 then
		return { success = false, reviews = {}, averageRating = 0, message = "Invalid user." }
	end
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer then
		local tData = PlayerDataService.GetData(targetPlayer)
		if not tData then
			return { success = false, reviews = {}, averageRating = 0, message = "No data." }
		end
		local rev = if typeof(tData.Reviews) == "table" then tData.Reviews :: { any } else {}
		local lastN: { any } = {}
		local start = math.max(1, #rev - 9)
		for i = start, #rev do
			table.insert(lastN, rev[i])
		end
		local avg = typeof(tData.AverageRating) == "number" and tData.AverageRating or recalcAverageRating(rev)
		return { success = true, reviews = lastN, averageRating = avg }
	end

	local ok, saved = pcall(function()
		return reviewDataStore:GetAsync(tostring(targetUserId))
	end)
	if not ok or typeof(saved) ~= "table" then
		return { success = true, reviews = {}, averageRating = 0 }
	end
	local rev = saved.Reviews
	if typeof(rev) ~= "table" then
		return { success = true, reviews = {}, averageRating = 0 }
	end
	local lastN: { any } = {}
	local rlist = rev :: { any }
	local start = math.max(1, #rlist - 9)
	for i = start, #rlist do
		table.insert(lastN, rlist[i])
	end
	local avg = typeof(saved.AverageRating) == "number" and saved.AverageRating or recalcAverageRating(rlist)
	return { success = true, reviews = lastN, averageRating = avg }
end

local function onPlayerRemoving(player: Player)
	JobService.StopWork(player)
end

local function validateJobCities()
	for _, name in JOB_ORDER do
		local job = JOBS[name]
		if job.City ~= "Any" and not CityService.GetCity(job.City) then
			warn(string.format("[%s] Job %q references unknown city %q", GAME_LABEL, job.Name, job.City))
		end
	end
end

local function onCharacterAdded(player: Player)
	local session = workSessions[player]
	if session and player.Character then
		OutfitService.ApplyOutfit(player, session.jobName)
	end
end

local function streakLoop(player: Player)
	task.spawn(function()
		while player.Parent do
			task.wait(3600)
			if player.Parent then
				JobService.CheckMissionStreak(player)
			end
		end
	end)
end

local function start()
	validateJobCities()
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	PlayerDataService.OnDataLoaded(function(player: Player)
		task.defer(function()
			JobService.CheckMissionStreak(player)
		end)
		streakLoop(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
	end)

	for _, plr in Players:GetPlayers() do
		plr.CharacterAdded:Connect(function()
			onCharacterAdded(plr)
		end)
	end
end

start()

return JobService
