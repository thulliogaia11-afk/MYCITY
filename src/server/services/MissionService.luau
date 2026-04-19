--[[
	MissionService — MY CITY
	Spawns physical world missions (Neon parts + ProximityPrompts) per profession,
	tracks acceptance / completion timers, ties into PlayerData MissionProgress,
	and runs spawn + daily / dismissal maintenance loops.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LOG_PREFIX = "[MY CITY] MissionService"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)
local JobService = require(script.Parent:WaitForChild("JobService") :: ModuleScript)
local CityService = require(script.Parent:WaitForChild("CityService") :: ModuleScript)
local IronholmSliceConfig = require(Shared:WaitForChild("IronholmSliceConfig") :: ModuleScript)

-- ——— World anchor positions (game-specific coordinates) ———
local LOCATIONS: { [string]: Vector3 } = {
	Hospital = Vector3.new(499, 5, -142),
	School = Vector3.new(617, 5, -27),
	PoliceStation = Vector3.new(323, 5, 29),
	CityHall = Vector3.new(-140, 5, 137),
	Downtown = Vector3.new(0, 5, 0),
	ResidentialA = Vector3.new(-120, 5, 500),
	ResidentialB = Vector3.new(47, 5, -430),
	Commercial = Vector3.new(-60, 5, 160),
	Industrial = Vector3.new(-350, 5, -100),
	Park = Vector3.new(100, 5, 200),
}

-- Job-keyed gameplay mission pools (id must be unique per mission def).
local MISSIONS: { [string]: { any } } = {
	["Street Cleaner"] = {
		{ id = "trash_park", title = "🗑️ Lixo no Parque", location = "Park", desc = "Limpa o lixo no parque", time = 180, reward = { money = 30, rep = 5 } },
		{ id = "trash_street", title = "🗑️ Lixo na Rua", location = "Downtown", desc = "Limpa o lixo na rua principal", time = 180, reward = { money = 25, rep = 4 } },
		{ id = "trash_market", title = "🗑️ Lixo no Mercado", location = "Commercial", desc = "Limpa o lixo na zona comercial", time = 180, reward = { money = 28, rep = 4 } },
	},
	["Factory Worker"] = {
		{ id = "factory_fix", title = "⚙️ Máquina Avariada", location = "Industrial", desc = "Repara a máquina da fábrica", time = 240, reward = { money = 50, rep = 8 } },
		{ id = "factory_prod", title = "📦 Produção Urgente", location = "Industrial", desc = "Completa o pedido urgente", time = 240, reward = { money = 45, rep = 7 } },
	},
	["Police Officer"] = {
		{ id = "fight_street", title = "🚨 Briga de Rua", location = "Downtown", desc = "Intervm numa briga de rua", time = 300, reward = { money = 80, rep = 15 } },
		{ id = "tax_evader", title = "💸 Evasão Fiscal", location = "Commercial", desc = "Detém suspeito de evasão fiscal", time = 300, reward = { money = 90, rep = 18 } },
		{ id = "patrol", title = "🚓 Patrulha Noturna", location = "PoliceStation", desc = "Completa ronda de patrulha", time = 240, reward = { money = 70, rep = 12 } },
	},
	["Firefighter"] = {
		{ id = "fire_house", title = "🔥 Fogo numa Casa", location = "ResidentialA", desc = "Apaga o fogo na habitação", time = 300, reward = { money = 100, rep = 20 } },
		{ id = "cat_tree", title = "🐱 Gato na Árvore", location = "Park", desc = "Resgata o gato da árvore", time = 180, reward = { money = 60, rep = 10 } },
		{ id = "fire_factory", title = "🔥 Fogo na Fábrica", location = "Industrial", desc = "Combate incêndio industrial", time = 360, reward = { money = 120, rep = 25 } },
	},
	["Doctor"] = {
		{ id = "patient_treat", title = "🏥 Paciente Ferido", location = "Hospital", desc = "Trata paciente com ferimentos", time = 300, reward = { money = 120, rep = 25 } },
		{ id = "surgery", title = "💉 Cirurgia de Emergência", location = "Hospital", desc = "Realiza cirurgia de emergência", time = 420, reward = { money = 200, rep = 40 } },
		{ id = "sick_citizen", title = "🤒 Cidadão Doente", location = "Downtown", desc = "Atende cidadão doente na rua", time = 240, reward = { money = 100, rep = 20 } },
	},
	["Nurse"] = {
		{ id = "assist_doctor", title = "💉 Assistir Médico", location = "Hospital", desc = "Assiste o médico na cirurgia", time = 300, reward = { money = 80, rep = 15 } },
		{ id = "patient_care", title = "🏥 Cuidar Paciente", location = "Hospital", desc = "Cuida de 3 pacientes", time = 240, reward = { money = 70, rep = 12 } },
	},
	["Teacher"] = {
		{ id = "math_class", title = "📐 Aula de Matemática", location = "School", desc = "Dá a aula de matemática", time = 300, reward = { money = 70, rep = 15 } },
		{ id = "history_class", title = "📚 Aula de História", location = "School", desc = "Dá a aula de história", time = 300, reward = { money = 70, rep = 15 } },
		{ id = "science_class", title = "🔬 Aula de Ciências", location = "School", desc = "Dá a aula de ciências", time = 300, reward = { money = 80, rep = 18 } },
	},
	["Security"] = {
		{ id = "patrol_commercial", title = "🛡️ Patrulha Comercial", location = "Commercial", desc = "Patrulha a zona comercial", time = 240, reward = { money = 60, rep = 10 } },
		{ id = "suspicious", title = "👁️ Suspeito na Área", location = "Downtown", desc = "Investiga actividade suspeita", time = 300, reward = { money = 70, rep = 12 } },
	},
	["Electrician"] = {
		{ id = "house_fault", title = "⚡ Avaria Eléctrica", location = "ResidentialB", desc = "Repara avaria numa habitação", time = 300, reward = { money = 90, rep = 15 } },
		{ id = "power_grid", title = "🔌 Falha na Rede", location = "Industrial", desc = "Restaura energia na fábrica", time = 360, reward = { money = 110, rep = 20 } },
	},
}

local WORLD_DAILY_GOAL = 3
local WORLD_DAILY_BONUS = { money = 100, rep = 20 }
local OFFER_DURATION_SEC = 300 -- 5 minutes to accept spawned mission
local MAYOR_PREFIX = "Mayor of "
local MISSION_RUNTIME_FOLDER = "MissionRuntime"
local LEGACY_MISSION_FOLDER = "MY_CITY_Missions"
local IRONHOLM_SLICE_STATE_KEY = "ironholmSlice"
local STARTER_SLICE_ASSIGNED_OBJECTIVE = "Ironholm rewards motion. Pick up the parcel at the commerce desk to start your first courier run."
local STARTER_SLICE_DELIVERY_OBJECTIVE = "Deliver the parcel to the Riverside client."
local STARTER_SLICE_CLAIM_OBJECTIVE = "Return to the mission panel and claim your courier payout."
local STARTER_SLICE_NEXT_OBJECTIVE = "Courier run secured. Keep moving: complete 2 Ironholm jobs and keep stacking cash for your first apartment."

-- ——— Runtime state ———
-- Each entry: { def, jobName, part, startTime, assignedPlayer?, locationName, timeoutThread? }
local activeMissions: { [string]: any } = {}
-- Player may only have one active world mission at a time.
local playerMissionId: { [Player]: string } = {}
local starterRuntimeByUserId: { [number]: { [string]: BasePart } } = {}

-- Created early so ProximityPrompt closures always reference this table.
local MissionService = {} :: any

local function log(msg: string)
	print(LOG_PREFIX .. " " .. msg)
end

local function isMayorJob(job: string): boolean
	return typeof(job) == "string" and string.sub(job, 1, #MAYOR_PREFIX) == MAYOR_PREFIX
end

-- Job must match mission pool (mayors / missing data cannot take world missions).
local function playerWorldMissionJobOk(player: Player, requiredJob: string): boolean
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = PlayerDataService.GetData(player)
	local job = typeof(data.Job) == "string" and data.Job or "Unemployed"
	return job == requiredJob and not isMayorJob(job)
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

local function notifyPlayer(player: Player, message: string, kind: string?)
	local ev = getShowNotification()
	if ev then
		ev:FireClient(player, message, kind or "info")
	end
end

local function getMissionRemote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
	if not folder then
		return nil
	end
	local ev = folder:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function packMissionClientPayload(missionId: string, m: any): any
	local def = m.def
	local rw = typeof(def.reward) == "table" and def.reward or {}
	local locName = m.locationName or (typeof(def.location) == "string" and def.location or "")
	return {
		missionId = missionId,
		title = typeof(def.title) == "string" and def.title or "Mission",
		requiredJob = m.jobName,
		assignedUserId = m.assignedPlayer and m.assignedPlayer.UserId or 0,
		description = typeof(def.desc) == "string" and def.desc or "",
		locationName = locName,
		position = m.part and m.part.Position or Vector3.new(0, 0, 0),
		reward = {
			money = typeof(rw.money) == "number" and rw.money or 0,
			rep = typeof(rw.rep) == "number" and rw.rep or 0,
		},
		timeLimit = typeof(def.time) == "number" and def.time or 300,
	}
end

local function broadcastMissionAvailable(missionId: string, m: any)
	local ev = getMissionRemote("MissionAvailable")
	if not ev then
		return
	end
	local payload = packMissionClientPayload(missionId, m)
	for _, plr in Players:GetPlayers() do
		if playerWorldMissionJobOk(plr, m.jobName) then
			ev:FireClient(plr, payload)
		end
	end
end

local function calendarDayKey(): number
	local t = os.date("*t", os.time()) :: { year: number, month: number, day: number }
	return t.year * 10000 + t.month * 100 + t.day
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

local function cloneStringArray(raw: any): { string }
	local out: { string } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for _, value in ipairs(raw) do
		if typeof(value) == "string" then
			table.insert(out, value)
		end
	end
	return out
end

local function ensureMissionEntry(mp: { [string]: any }, jobName: string): { [string]: any }
	local e = mp[jobName]
	if typeof(e) ~= "table" then
		e = {}
		mp[jobName] = e
	end
	return e :: { [string]: any }
end

local function getSliceState(mp: { [string]: any }): { [string]: any }?
	local state = mp[IRONHOLM_SLICE_STATE_KEY]
	if typeof(state) == "table" then
		return state :: { [string]: any }
	end
	return nil
end

local function ensureSliceState(mp: { [string]: any }): { [string]: any }
	local state = getSliceState(mp)
	if state then
		return state
	end

	local created = {}
	mp[IRONHOLM_SLICE_STATE_KEY] = created
	return created
end

local function getSliceStateFromData(data: { [string]: any }): { [string]: any }?
	if typeof(data.MissionProgress) ~= "table" then
		return nil
	end
	return getSliceState(data.MissionProgress :: { [string]: any })
end

local function getSliceMissionDefinition(missionId: string): { [string]: any }?
	local mission = IronholmSliceConfig.Missions[missionId]
	if typeof(mission) == "table" then
		return mission :: { [string]: any }
	end
	return nil
end

local function getSliceDailyDefinition(dailyId: string): { [string]: any }?
	for _, daily in ipairs(IronholmSliceConfig.Dailies) do
		if typeof(daily) == "table" and daily.id == dailyId then
			return daily :: { [string]: any }
		end
	end
	return nil
end

local function getSliceJobDefinition(jobId: string): { [string]: any }?
	local job = IronholmSliceConfig.Jobs[jobId]
	if typeof(job) == "table" then
		return job :: { [string]: any }
	end
	return nil
end

local function getSliceJobDisplayName(jobId: string): string?
	local job = getSliceJobDefinition(jobId)
	if job and typeof(job.displayName) == "string" then
		return job.displayName
	end
	return nil
end

local function buildStarterDailyEntries(dailyIds: { string }, dailyProgress: { [string]: number }?): { any }
	local entries = {}
	local progressMap = if typeof(dailyProgress) == "table" then dailyProgress else {}
	for _, dailyId in ipairs(dailyIds) do
		local def = getSliceDailyDefinition(dailyId)
		if def then
			local trackedStat = typeof(def.trackedStat) == "string" and def.trackedStat or ""
			local progressValue = typeof(progressMap[trackedStat]) == "number" and progressMap[trackedStat] or 0
			local goal = typeof(def.goal) == "number" and def.goal or 0
			table.insert(entries, {
				id = def.id,
				title = def.title,
				shortDescription = def.shortDescription,
				objectiveText = def.objectiveText,
				rewardMoney = def.rewardMoney,
				rewardLabel = def.rewardLabel,
				trackedStat = trackedStat,
				goal = goal,
				progressValue = math.max(0, progressValue),
				remainingValue = math.max(0, goal - progressValue),
				isCompleted = goal > 0 and progressValue >= goal,
				order = def.order,
			})
		end
	end
	return entries
end

local function normalizeStarterSliceState(state: { [string]: any })
	local defaultMissionId = IronholmSliceConfig.StarterFlow.starterMissionId
	local missionId = typeof(state.activeMissionId) == "string" and state.activeMissionId or defaultMissionId
	local missionDef = getSliceMissionDefinition(missionId) or getSliceMissionDefinition(defaultMissionId)
	if missionDef and typeof(missionDef.id) == "string" then
		missionId = missionDef.id
	end

	local defaultJobId = IronholmSliceConfig.StarterFlow.starterJobId
	local jobId = missionDef and typeof(missionDef.jobId) == "string" and missionDef.jobId or nil
	if not jobId and typeof(state.jobId) == "string" then
		jobId = state.jobId
	end
	if typeof(jobId) ~= "string" or jobId == "" then
		jobId = defaultJobId
	end

	state.cityId = IronholmSliceConfig.Slice.cityId
	state.jobId = jobId
	state.activeMissionId = missionId
	state.dailyIds = cloneStringArray(state.dailyIds)
	if #state.dailyIds == 0 then
		state.dailyIds = cloneStringArray(IronholmSliceConfig.StarterFlow.starterDailyIds)
	end
	local todayKey = calendarDayKey()
	if typeof(state.dailyProgressDayKey) ~= "number" or state.dailyProgressDayKey ~= todayKey then
		state.dailyProgress = {}
		state.dailyProgressDayKey = todayKey
	end
	local normalizedDailyProgress: { [string]: number } = {}
	if typeof(state.dailyProgress) == "table" then
		for statId, value in state.dailyProgress do
			if typeof(statId) == "string" and typeof(value) == "number" then
				normalizedDailyProgress[statId] = math.max(0, value)
			end
		end
	end
	state.dailyProgress = normalizedDailyProgress
	state.aspirationId = typeof(state.aspirationId) == "string" and state.aspirationId or IronholmSliceConfig.Aspiration.id
	state.objectiveFallbackText = typeof(state.objectiveFallbackText) == "string" and state.objectiveFallbackText ~= ""
			and state.objectiveFallbackText
		or IronholmSliceConfig.StarterFlow.defaultObjectiveText

	local validStatuses = {
		assigned = true,
		in_progress = true,
		completed = true,
		claimed = true,
	}
	if typeof(state.missionStatus) ~= "string" or not validStatuses[state.missionStatus] then
		state.missionStatus = "assigned"
	end

	if typeof(state.missionProgressGoal) ~= "number" or state.missionProgressGoal <= 0 then
		state.missionProgressGoal = 1
	end

	if typeof(state.missionProgressValue) ~= "number" then
		state.missionProgressValue = if state.missionStatus == "completed" or state.missionStatus == "claimed"
			then state.missionProgressGoal
			else 0
	end
	state.missionProgressValue = math.clamp(state.missionProgressValue, 0, state.missionProgressGoal)
	if state.missionStatus == "completed" or state.missionStatus == "claimed" then
		state.missionProgressValue = state.missionProgressGoal
	end

	if state.missionStatus ~= "claimed" then
		state.missionClaimedAt = nil
	elseif typeof(state.missionClaimedAt) ~= "number" then
		state.missionClaimedAt = nil
	end

	if typeof(state.activatedAt) ~= "number" then
		state.activatedAt = os.time()
	end

	local missionObjectiveText = missionDef and typeof(missionDef.objectiveText) == "string" and missionDef.objectiveText or nil
	state.objectiveText = typeof(state.objectiveText) == "string" and state.objectiveText ~= ""
			and state.objectiveText
		or missionObjectiveText
		or state.objectiveFallbackText
end

local function updateStarterSliceStateForPlayer(
	player: Player,
	mutator: ({ [string]: any }, { [string]: any }) -> boolean?
): boolean
	if not PlayerDataService.HasSession(player) then
		return false
	end

	local data = PlayerDataService.GetData(player)
	local mp = cloneMissionProgress(data.MissionProgress)
	local state = ensureSliceState(mp)
	normalizeStarterSliceState(state)

	local changed = mutator(state, data)
	if changed == false then
		return false
	end

	return PlayerDataService.SetData(player, "MissionProgress", mp)
end

local function buildStarterSliceAspirationPayload(data: { [string]: any }): { [string]: any }
	local currentMoney = if typeof(data.Money) == "number" then data.Money else 0
	local targetCost = IronholmSliceConfig.Aspiration.targetCost
	local remainingCost = math.max(0, targetCost - currentMoney)
	local ratio = if targetCost > 0 then math.clamp(currentMoney / targetCost, 0, 1) else 1
	return {
		id = IronholmSliceConfig.Aspiration.id,
		title = IronholmSliceConfig.Aspiration.title,
		targetCost = targetCost,
		description = IronholmSliceConfig.Aspiration.description,
		progressCopy = IronholmSliceConfig.Aspiration.progressCopy,
		completionCopy = IronholmSliceConfig.Aspiration.completionCopy,
		currentMoney = currentMoney,
		remainingCost = remainingCost,
		progressRatio = ratio,
		isAffordable = currentMoney >= targetCost,
	}
end

local function buildStarterSliceMissionView(sliceState: { [string]: any }): { [string]: any }?
	normalizeStarterSliceState(sliceState)

	local missionId = sliceState.activeMissionId
	if typeof(missionId) ~= "string" or missionId == "" then
		return nil
	end

	local missionDef = getSliceMissionDefinition(missionId)
	if not missionDef then
		return nil
	end

	return {
		id = missionDef.id,
		title = missionDef.title,
		shortDescription = missionDef.shortDescription,
		objectiveText = sliceState.objectiveText,
		rewardMoney = missionDef.rewardMoney,
		rewardLabel = missionDef.rewardLabel,
		missionType = missionDef.missionType,
		jobId = missionDef.jobId,
		status = sliceState.missionStatus,
		progressValue = sliceState.missionProgressValue,
		progressGoal = sliceState.missionProgressGoal,
		claimedAt = sliceState.missionClaimedAt,
		canClaim = sliceState.missionStatus == "completed",
	}
end

local function buildStarterSliceViewData(data: { [string]: any }): { [string]: any }?
	local sliceState = getSliceStateFromData(data)
	if not sliceState then
		return nil
	end

	normalizeStarterSliceState(sliceState)
	local mission = buildStarterSliceMissionView(sliceState)
	local objectiveText = mission and mission.objectiveText or sliceState.objectiveText

	return {
		state = sliceState,
		job = getSliceJobDefinition(sliceState.jobId),
		mission = mission,
		dailies = buildStarterDailyEntries(sliceState.dailyIds, sliceState.dailyProgress),
		aspiration = buildStarterSliceAspirationPayload(data),
		objectiveText = objectiveText,
		objectiveFallbackText = sliceState.objectiveFallbackText,
	}
end

local function buildStarterSliceAssignedMission(viewData: { [string]: any }): { [string]: any }?
	local mission = viewData.mission
	if typeof(mission) ~= "table" then
		return nil
	end

	local sliceState = viewData.state
	return {
		id = mission.id,
		title = mission.title,
		description = mission.shortDescription,
		objectiveText = viewData.objectiveText,
		rewardMoney = mission.rewardMoney,
		rewardLabel = mission.rewardLabel,
		jobId = mission.jobId,
		cityId = sliceState.cityId,
		missionStatus = mission.status,
		missionProgressValue = mission.progressValue,
		missionProgressGoal = mission.progressGoal,
		missionClaimedAt = mission.claimedAt,
		sliceStarter = true,
	}
end

local function isStarterSliceMissionRelevant(sliceState: { [string]: any }, missionJobName: string): boolean
	if sliceState.activeMissionId ~= IronholmSliceConfig.StarterFlow.starterMissionId then
		return false
	end
	if sliceState.cityId ~= IronholmSliceConfig.Slice.cityId then
		return false
	end

	local starterJobName = getSliceJobDisplayName(sliceState.jobId)
	return starterJobName ~= nil and starterJobName == missionJobName
end

local function applyStarterSliceMissionStatus(
	sliceState: { [string]: any },
	missionJobName: string,
	nextStatus: string
): boolean
	if not isStarterSliceMissionRelevant(sliceState, missionJobName) then
		return false
	end

	local missionDef = getSliceMissionDefinition(sliceState.activeMissionId)
	if nextStatus == "in_progress" then
		sliceState.missionStatus = "in_progress"
		if sliceState.activeMissionId == IronholmSliceConfig.StarterFlow.starterMissionId then
			sliceState.missionProgressGoal = 2
			sliceState.missionProgressValue = 1
		else
			sliceState.missionProgressGoal = 1
			sliceState.missionProgressValue = 0
		end
		sliceState.missionClaimedAt = nil
		sliceState.objectiveText = if sliceState.activeMissionId == IronholmSliceConfig.StarterFlow.starterMissionId
			then STARTER_SLICE_DELIVERY_OBJECTIVE
			else missionDef and typeof(missionDef.objectiveText) == "string"
				and missionDef.objectiveText
				or sliceState.objectiveFallbackText
		return true
	end
	if nextStatus == "completed" then
		sliceState.missionStatus = "completed"
		if sliceState.activeMissionId == IronholmSliceConfig.StarterFlow.starterMissionId then
			sliceState.missionProgressGoal = 2
		else
			sliceState.missionProgressGoal = if typeof(sliceState.missionProgressGoal) == "number"
					and sliceState.missionProgressGoal > 0
				then sliceState.missionProgressGoal
				else 1
		end
		sliceState.missionProgressValue = sliceState.missionProgressGoal
		sliceState.missionClaimedAt = nil
		sliceState.objectiveText = STARTER_SLICE_CLAIM_OBJECTIVE
		return true
	end

	return false
end

local function updateStarterSliceMissionRuntime(
	player: Player,
	missionJobName: string,
	nextStatus: string
): boolean
	return updateStarterSliceStateForPlayer(player, function(state)
		return applyStarterSliceMissionStatus(state, missionJobName, nextStatus)
	end)
end

local function markStarterSliceMissionClaimed(player: Player): boolean
	return updateStarterSliceStateForPlayer(player, function(state)
		local starterJobName = getSliceJobDisplayName(state.jobId)
		if not starterJobName or not isStarterSliceMissionRelevant(state, starterJobName) then
			return false
		end
		if state.missionStatus ~= "completed" then
			return false
		end

		state.missionStatus = "claimed"
		state.missionClaimedAt = os.time()
		state.objectiveText = STARTER_SLICE_NEXT_OBJECTIVE
		return true
	end)
end

local function shouldAssignIronholmStarterSlice(data: { [string]: any }): boolean
	local city = typeof(data.City) == "string" and data.City or "None"
	local job = typeof(data.Job) == "string" and data.Job or "Unemployed"
	local mp = data.MissionProgress
	if typeof(mp) == "table" and getSliceState(mp :: { [string]: any }) then
		return false
	end
	local noExistingMissionProgress = typeof(mp) ~= "table" or next(mp :: { [any]: any }) == nil
	return (city == "Ironholm" or city == "None") and job == "Unemployed" and noExistingMissionProgress
end

local function ensureIronholmStarterSlice(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end

	local data = PlayerDataService.GetData(player)
	if not shouldAssignIronholmStarterSlice(data) then
		return
	end

	local currentCity = typeof(data.City) == "string" and data.City or "None"
	if currentCity == "None" then
		CityService.JoinCity(player, "Ironholm")
		data = PlayerDataService.GetData(player)
		currentCity = typeof(data.City) == "string" and data.City or "None"
	end
	if currentCity ~= "Ironholm" then
		return
	end

	local starterJobId = IronholmSliceConfig.StarterFlow.starterJobId
	local starterMissionId = IronholmSliceConfig.StarterFlow.starterMissionId
	local starterJob = IronholmSliceConfig.Jobs[starterJobId]
	local starterMission = getSliceMissionDefinition(starterMissionId)
	if typeof(starterJob) ~= "table" or not starterMission then
		warn(LOG_PREFIX .. " starter slice config is incomplete")
		return
	end

	local mp = cloneMissionProgress(data.MissionProgress)
	local state = ensureSliceState(mp)
	state.cityId = IronholmSliceConfig.Slice.cityId
	state.jobId = starterJobId
	state.activeMissionId = starterMissionId
	state.dailyIds = cloneStringArray(IronholmSliceConfig.StarterFlow.starterDailyIds)
	state.dailyProgress = {}
	state.aspirationId = IronholmSliceConfig.Aspiration.id
	state.objectiveFallbackText = IronholmSliceConfig.StarterFlow.defaultObjectiveText
	state.objectiveText = STARTER_SLICE_ASSIGNED_OBJECTIVE
	state.missionStatus = "assigned"
	state.missionProgressValue = 0
	state.missionProgressGoal = 1
	state.missionClaimedAt = nil
	state.activatedAt = os.time()
	normalizeStarterSliceState(state)

	PlayerDataService.SetDataBatch(player, {
		Job = starterJob.displayName,
		MissionProgress = mp,
	})
	log(string.format(
		"starter slice assigned player=%s city=%s job=%s mission=%s",
		player.Name,
		currentCity,
		starterJobId,
		starterMissionId
	))
end

local function clearStarterRuntimeForUserId(userId: number)
	local runtime = starterRuntimeByUserId[userId]
	if runtime then
		for _, inst in runtime do
			if inst and inst.Parent then
				inst:Destroy()
			end
		end
		starterRuntimeByUserId[userId] = nil
	end

	local runtimeFolder = Workspace:FindFirstChild(MISSION_RUNTIME_FOLDER)
	if runtimeFolder and runtimeFolder:IsA("Folder") then
		for _, child in runtimeFolder:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("StarterSliceUserId") == userId then
				child:Destroy()
			end
		end
	end
end

local function clearStarterRuntimeForPlayer(player: Player)
	clearStarterRuntimeForUserId(player.UserId)
end

local function createStarterRuntimePoint(
	player: Player,
	stageId: string,
	title: string,
	actionText: string,
	objectText: string,
	position: Vector3,
	color: Color3,
	onTriggered: (Player) -> ()
): BasePart
	local part = Instance.new("Part")
	part.Name = "Starter_" .. stageId
	part.Size = Vector3.new(4, 4, 4)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Ball
	part.Color = color
	part.Parent = getMissionRuntimeFolder()

	part:SetAttribute("RequiredJob", getSliceJobDisplayName(IronholmSliceConfig.StarterFlow.starterJobId) or "Courier")
	part:SetAttribute("MissionId", IronholmSliceConfig.StarterFlow.starterMissionId)
	part:SetAttribute("MissionTitle", title)
	part:SetAttribute("AssignedUserId", player.UserId)
	part:SetAttribute("MissionState", stageId)
	part:SetAttribute("StarterSliceUserId", player.UserId)

	local titleGui = Instance.new("BillboardGui")
	titleGui.Name = "Title"
	titleGui.AlwaysOnTop = true
	titleGui.StudsOffset = Vector3.new(0, 5, 0)
	titleGui.Size = UDim2.fromOffset(240, 60)
	titleGui.MaxDistance = 200
	titleGui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Text"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 1)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextStrokeTransparency = 0.35
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = title
	titleLabel.Parent = titleGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StarterSlicePrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = 15
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.Parent = part

	prompt.Triggered:Connect(function(trigPlayer: Player)
		if trigPlayer.UserId ~= player.UserId then
			return
		end
		onTriggered(trigPlayer)
	end)

	return part
end

local function syncStarterRuntimeForPlayer(player: Player)
	clearStarterRuntimeForPlayer(player)
	if not PlayerDataService.HasSession(player) then
		return
	end

	local data = PlayerDataService.GetData(player)
	local viewData = buildStarterSliceViewData(data)
	if not viewData then
		return
	end

	local mission = viewData.mission
	local sliceState = viewData.state
	if typeof(mission) ~= "table" then
		return
	end
	if mission.id ~= IronholmSliceConfig.StarterFlow.starterMissionId then
		return
	end
	if sliceState.cityId ~= IronholmSliceConfig.Slice.cityId then
		return
	end
	local currentJobName = typeof(data.Job) == "string" and data.Job or "Unemployed"
	if currentJobName ~= (getSliceJobDisplayName(IronholmSliceConfig.StarterFlow.starterJobId) or "Courier") then
		return
	end

	local status = typeof(mission.status) == "string" and mission.status or "assigned"
	local missionTitle = typeof(mission.title) == "string" and mission.title or "Courier Run"
	local runtime: { [string]: BasePart } = {}

	if status == "assigned" then
		runtime.pickup = createStarterRuntimePoint(
			player,
			"StarterAssigned",
			"Commerce Desk",
			"Pick Up Parcel",
			missionTitle,
			LOCATIONS.Commercial + Vector3.new(14, 2, 0),
			Color3.fromRGB(90, 180, 255),
			function(trigPlayer: Player)
				local jobName = getSliceJobDisplayName(IronholmSliceConfig.StarterFlow.starterJobId) or "Courier"
				if not updateStarterSliceMissionRuntime(trigPlayer, jobName, "in_progress") then
					notifyPlayer(trigPlayer, "Starter mission is not ready to begin.", "warning")
					return
				end
				syncStarterRuntimeForPlayer(trigPlayer)
				notifyPlayer(trigPlayer, "Parcel secured. Deliver it to the Riverside client.", "success")
			end
		)
	elseif status == "in_progress" then
		runtime.delivery = createStarterRuntimePoint(
			player,
			"StarterInProgress",
			"Riverside Client",
			"Deliver Parcel",
			missionTitle,
			LOCATIONS.ResidentialB + Vector3.new(12, 2, 8),
			Color3.fromRGB(120, 255, 170),
			function(trigPlayer: Player)
				MissionService.CompleteStarterCourierMission(trigPlayer)
			end
		)
	end

	if next(runtime) ~= nil then
		starterRuntimeByUserId[player.UserId] = runtime
	end
end

local function countActiveForJob(jobName: string): number
	local n = 0
	for _, rec in activeMissions do
		if typeof(rec) == "table" and rec.jobName == jobName and rec.part and rec.part.Parent then
			n += 1
		end
	end
	return n
end

local function getMissionRuntimeFolder(): Folder
	local folder = Workspace:FindFirstChild(MISSION_RUNTIME_FOLDER)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = MISSION_RUNTIME_FOLDER
	created.Parent = Workspace
	return created
end

local function ensureMissionRuntimeReady()
	getMissionRuntimeFolder()
	log("MissionRuntime ready")
end

local function removeLegacyMissionFolder()
	local legacyFolder = Workspace:FindFirstChild(LEGACY_MISSION_FOLDER)
	if not legacyFolder then
		return
	end

	for _, child in legacyFolder:GetChildren() do
		child:Destroy()
	end
	legacyFolder:Destroy()
	log("MissionService removed legacy MY_CITY_Missions folder")
end

local function hasEligibleWorkerForJob(jobName: string): boolean
	if typeof(jobName) ~= "string" or jobName == "" or jobName == "Unemployed" or isMayorJob(jobName) then
		return false
	end
	if not MISSIONS[jobName] then
		return false
	end

	for _, player in Players:GetPlayers() do
		if playerWorldMissionJobOk(player, jobName) then
			return true
		end
	end

	return false
end

local function isMissionRuntimeInstance(inst: Instance): boolean
	if inst.Parent == getMissionRuntimeFolder() then
		return true
	end
	if inst:GetAttribute("MissionId") ~= nil then
		return true
	end
	if string.sub(inst.Name, 1, 8) == "Mission_" then
		return true
	end

	return false
end

local function resetMissionRuntime()
	local runtimeFolder = getMissionRuntimeFolder()
	local destroyedCount = 0

	for missionId, rec in activeMissions do
		if typeof(rec) == "table" then
			if rec.timeoutThread then
				pcall(task.cancel, rec.timeoutThread)
			end
			local acceptPulseTween = (rec :: any).acceptPulseTween
			if acceptPulseTween then
				pcall(function()
					acceptPulseTween:Cancel()
				end)
			end
		end
		activeMissions[missionId] = nil
	end

	table.clear(playerMissionId)
	table.clear(starterRuntimeByUserId)

	for _, child in runtimeFolder:GetChildren() do
		destroyedCount += 1
		child:Destroy()
	end

	for _, child in Workspace:GetChildren() do
		if child ~= runtimeFolder and isMissionRuntimeInstance(child) then
			destroyedCount += 1
			child:Destroy()
		end
	end

	log(string.format("mission runtime cleaned (destroyed=%d, active=0)", destroyedCount))
end

local function despawnMissionRecord(id: string, reason: string?)
	local m = activeMissions[id]
	if not m then
		return
	end
	if m.timeoutThread then
		pcall(task.cancel, m.timeoutThread)
		m.timeoutThread = nil
	end
	activeMissions[id] = nil
	if m.assignedPlayer then
		playerMissionId[m.assignedPlayer] = nil
	end
	if m.part and m.part.Parent then
		m.part:Destroy()
	end
	if reason then
		log(string.format("Despawned mission %s (%s)", id, reason))
	end
end

-- ——— Public API ———

function MissionService.SpawnMission(jobName: string): string?
	local missions = MISSIONS[jobName]
	if not missions or #missions == 0 then
		warn(LOG_PREFIX .. " no missions defined for job: " .. tostring(jobName))
		return nil :: any
	end

	if not hasEligibleWorkerForJob(jobName) then
		log(string.format("mission spawn skipped for %s (no active workers)", tostring(jobName)))
		return nil :: any
	end

	if countActiveForJob(jobName) >= 2 then
		return nil :: any
	end

	local missionDef = missions[math.random(1, #missions)]
	local locationPos = LOCATIONS[missionDef.location]
	if not locationPos then
		warn(LOG_PREFIX .. " location not found: " .. tostring(missionDef.location))
		return nil :: any
	end

	local missionId = HttpService:GenerateGUID(false)

	local part = Instance.new("Part")
	part.Name = "Mission_" .. missionId
	part.Size = Vector3.new(5, 5, 5)
	part.Position = locationPos + Vector3.new(0, 5, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Ball
	part.Parent = getMissionRuntimeFolder()

	part:SetAttribute("RequiredJob", jobName)
	part:SetAttribute("MissionId", missionId)
	part:SetAttribute("MissionTitle", typeof(missionDef.title) == "string" and missionDef.title or "Mission")
	part:SetAttribute("AssignedUserId", 0)
	part:SetAttribute("MissionState", "Available")

	local jobColors: { [string]: Color3 } = {
		["Firefighter"] = Color3.fromRGB(255, 50, 0),
		["Police Officer"] = Color3.fromRGB(0, 100, 255),
		["Doctor"] = Color3.fromRGB(255, 255, 255),
		["Nurse"] = Color3.fromRGB(255, 150, 200),
		["Teacher"] = Color3.fromRGB(255, 200, 0),
		["Security"] = Color3.fromRGB(255, 140, 0),
		["Electrician"] = Color3.fromRGB(255, 255, 0),
		["Street Cleaner"] = Color3.fromRGB(0, 200, 50),
		["Factory Worker"] = Color3.fromRGB(150, 150, 150),
	}
	part.Color = jobColors[jobName] or Color3.fromRGB(255, 255, 255)

	local titleGui = Instance.new("BillboardGui")
	titleGui.Name = "Title"
	titleGui.AlwaysOnTop = true
	titleGui.StudsOffset = Vector3.new(0, 5, 0)
	titleGui.Size = UDim2.fromOffset(220, 60)
	titleGui.MaxDistance = 200
	titleGui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Text"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 1)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextStrokeTransparency = 0.35
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = typeof(missionDef.title) == "string" and missionDef.title or "Mission"
	titleLabel.Parent = titleGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AcceptMission"
	prompt.ActionText = "Accept Mission"
	prompt.ObjectText = typeof(missionDef.title) == "string" and missionDef.title or "Mission"
	prompt.MaxActivationDistance = 15
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		print(LOG_PREFIX .. " AcceptMission prompt triggered by:", player.Name, "missionId:", missionId)
		if not PlayerDataService.HasSession(player) then
			print(LOG_PREFIX .. " no player data")
			return
		end
		local data = PlayerDataService.GetData(player)
		local pj = typeof(data.Job) == "string" and data.Job or "Unemployed"
		print(LOG_PREFIX .. " player job:", pj, "required:", jobName)
		if pj ~= jobName or isMayorJob(pj) then
			notifyPlayer(player, "⚠️ Esta missão é para " .. jobName, "warning")
			return
		end
		MissionService.AcceptMission(player, missionId)
	end)

	local rec: any = {
		def = missionDef,
		jobName = jobName,
		part = part,
		startTime = os.time(),
		assignedPlayer = nil,
		locationName = typeof(missionDef.location) == "string" and missionDef.location or "",
		timeoutThread = nil,
	}
	activeMissions[missionId] = rec

	task.delay(OFFER_DURATION_SEC, function()
		local m = activeMissions[missionId]
		if m and not m.assignedPlayer then
			despawnMissionRecord(missionId, "offer expired")
			log(string.format("mission expired: %s (unassigned offer expired)", missionId))
		end
	end)

	broadcastMissionAvailable(missionId, rec)
	log(string.format("mission spawned: id=%s job=%s title=%s location=%s", missionId, jobName, tostring(missionDef.title), tostring(missionDef.location)))
	return missionId
end

function MissionService.NotifyPlayerJobUpdated(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end

	local data = PlayerDataService.GetData(player)
	local job = typeof(data.Job) == "string" and data.Job or "Unemployed"
	if hasEligibleWorkerForJob(job) and countActiveForJob(job) < 1 then
		MissionService.SpawnMission(job)
	end
	syncStarterRuntimeForPlayer(player)

	local ev = getMissionRemote("MissionAvailable")
	if not ev then
		return
	end
	for mid, rec in activeMissions do
		if typeof(mid) == "string" and typeof(rec) == "table" then
			if not rec.assignedPlayer and rec.part and rec.part.Parent and playerWorldMissionJobOk(player, rec.jobName) then
				ev:FireClient(player, packMissionClientPayload(mid, rec))
			end
		end
	end
end

function MissionService.AcceptMission(player: Player, missionId: string)
	print(LOG_PREFIX .. " AcceptMission called:", player.Name, missionId)

	local mission = activeMissions[missionId]
	if not mission then
		print(LOG_PREFIX .. " AcceptMission - mission not found:", missionId)
		return
	end
	if mission.assignedPlayer then
		print(LOG_PREFIX .. " already assigned to:", mission.assignedPlayer.Name)
		return
	end
	if not mission.part or not mission.part.Parent then
		print(LOG_PREFIX .. " AcceptMission - part missing or destroyed")
		return
	end

	if playerMissionId[player] then
		print(LOG_PREFIX .. " AcceptMission - player already has active mission")
		notifyPlayer(player, "You already have an active mission.", "info")
		return
	end

	if not PlayerDataService.HasSession(player) then
		print(LOG_PREFIX .. " AcceptMission - no PlayerData")
		return
	end
	local data = PlayerDataService.GetData(player)
	local job = typeof(data.Job) == "string" and data.Job or "Unemployed"
	if job ~= mission.jobName or isMayorJob(job) then
		print(LOG_PREFIX .. " AcceptMission - job mismatch:", job, "vs", mission.jobName)
		notifyPlayer(player, "⚠️ This mission is not for your job!", "warning")
		return
	end

	mission.assignedPlayer = player
	mission.acceptedAt = os.time()
	playerMissionId[player] = missionId
	updateStarterSliceMissionRuntime(player, mission.jobName, "in_progress")

	if mission.part and mission.part.Parent then
		local p = mission.part
		p.Color = Color3.fromRGB(255, 165, 0)
		p:SetAttribute("AssignedUserId", player.UserId)
		p:SetAttribute("MissionState", "InProgress")
		local titleGui = p:FindFirstChild("Title")
		if titleGui and titleGui:IsA("BillboardGui") then
			local titleLabel = titleGui:FindFirstChild("Text")
			if titleLabel and titleLabel:IsA("TextLabel") then
				titleLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
				titleLabel.Text = string.format(
					"%s\n[In Progress]",
					typeof(mission.def.title) == "string" and mission.def.title or "Mission"
				)
			end
		end
		local baseSize = p.Size
		local pulseTarget = baseSize * 1.24
		local pulseTween = TweenService:Create(
			p,
			TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = pulseTarget }
		)
		;(mission :: any).acceptPulseTween = pulseTween
		pulseTween:Play()
	end

	local oldPrompt = mission.part:FindFirstChild("AcceptMission")
	if oldPrompt then
		oldPrompt:Destroy()
		print(LOG_PREFIX .. " removed AcceptMission prompt")
	end

	local completePrompt = Instance.new("ProximityPrompt")
	completePrompt.Name = "CompleteMission"
	completePrompt.ActionText = "Complete Mission"
	completePrompt.ObjectText = "✅ " .. (typeof(mission.def.title) == "string" and mission.def.title or "Mission")
	completePrompt.MaxActivationDistance = 15
	completePrompt.RequiresLineOfSight = false
	completePrompt.HoldDuration = 2
	completePrompt.Parent = mission.part

	local capturedMissionId = missionId
	local assigneeUserId = player.UserId
	completePrompt.Triggered:Connect(function(trigPlayer: Player)
		print(
			LOG_PREFIX .. " CompleteMission prompt triggered by:",
			trigPlayer.Name,
			"userId:",
			trigPlayer.UserId,
			"expected:",
			assigneeUserId
		)
		if trigPlayer.UserId ~= assigneeUserId then
			print(LOG_PREFIX .. " wrong player, ignoring")
			return
		end
		MissionService.CompleteMission(trigPlayer, capturedMissionId)
	end)

	local duration = typeof(mission.def.time) == "number" and mission.def.time or 300
	mission.timeoutThread = task.delay(duration, function()
		local m = activeMissions[missionId]
		if m and m.assignedPlayer == player then
			local titleStr = typeof(m.def.title) == "string" and m.def.title or "Mission"
			despawnMissionRecord(missionId, "timer expired")
			local expiredEv = getMissionRemote("MissionExpired")
			if expiredEv then
				expiredEv:FireClient(player, { missionId = missionId, title = titleStr })
			end
			local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
			local notif = folder and folder:FindFirstChild("ShowNotification")
			if notif and notif:IsA("RemoteEvent") then
				(notif :: RemoteEvent):FireClient(player, "⏰ Missão expirada: " .. titleStr, "warning")
			end
			log(string.format("mission expired: id=%s player=%s", missionId, player.Name))
		end
	end)

	print(LOG_PREFIX .. ":", player.Name, "accepted:", mission.def.title)
	log(string.format("mission accepted: id=%s player=%s job=%s", missionId, player.Name, mission.jobName))
end

function MissionService.CompleteMission(player: Player, missionId: string)
	print(LOG_PREFIX .. " CompleteMission called:", player.Name, missionId)

	local mission = activeMissions[missionId]
	if not mission then
		print(LOG_PREFIX .. " mission NOT FOUND in activeMissions:", missionId)
		local ac = 0
		for k in activeMissions do
			ac += 1
			print(LOG_PREFIX .. " active mission key:", k)
		end
		print(LOG_PREFIX .. " Active missions count (pairs):", ac, "(#table is unreliable for string keys)")
		return
	end

	if mission.assignedPlayer ~= player then
		print(LOG_PREFIX .. " CompleteMission - wrong assignee (expected", player.Name, "got", mission.assignedPlayer and mission.assignedPlayer.Name or "nil", ")")
		return
	end

	print(LOG_PREFIX .. " found mission:", mission.def and mission.def.title or "?")

	if mission.timeoutThread then
		pcall(task.cancel, mission.timeoutThread)
		mission.timeoutThread = nil
		print(LOG_PREFIX .. " cancelled mission timeout thread")
	end

	local acceptPulseTween = (mission :: any).acceptPulseTween
	if acceptPulseTween then
		pcall(function()
			acceptPulseTween:Cancel()
		end)
		;(mission :: any).acceptPulseTween = nil
	end

	local def = mission.def
	local reward = typeof(def.reward) == "table" and def.reward or {}
	local rewardMoney = typeof(reward.money) == "number" and reward.money or 0
	local rewardRep = typeof(reward.rep) == "number" and reward.rep or 0
	local titleStr = typeof(def.title) == "string" and def.title or "Mission"
	local jobName = mission.jobName

	local missionPos: Vector3? = nil
	if mission.part and mission.part.Parent then
		missionPos = mission.part.Position
	end

	local pdata = PlayerDataService.GetData(player)
	if pdata then
		local newMoney = (typeof(pdata.Money) == "number" and pdata.Money or 0) + rewardMoney
		PlayerDataService.SetData(player, "Money", newMoney)
		print(LOG_PREFIX .. " awarded", rewardMoney, "CC")
	end
	if rewardRep > 0 then
		ReputationService.AddReputation(player, rewardRep, "mission_complete")
		print(LOG_PREFIX .. " awarded", rewardRep, "rep")
	end

	-- Daily world-mission progress (3/day) + bonus
	local fresh = PlayerDataService.GetData(player)
	if fresh then
		local mp = cloneMissionProgress(fresh.MissionProgress)
		local e = ensureMissionEntry(mp, jobName)
		local dk = calendarDayKey()
		if typeof(e.worldDayKey) ~= "number" or e.worldDayKey ~= dk then
			e.worldCompletionsToday = 0
			e.worldDayKey = dk
		end
		e.worldCompletionsToday = (typeof(e.worldCompletionsToday) == "number" and e.worldCompletionsToday or 0) + 1
		if e.worldCompletionsToday >= WORLD_DAILY_GOAL then
			if typeof(e.worldDailyBonusDayKey) ~= "number" or e.worldDailyBonusDayKey ~= dk then
				e.worldDailyBonusDayKey = dk
				local bm = WORLD_DAILY_BONUS.money
				local br = WORLD_DAILY_BONUS.rep
				local nm = (PlayerDataService.GetData(player) :: any).Money
				if typeof(nm) == "number" and PlayerDataService.SetData(player, "Money", nm + bm) then
					ReputationService.AddReputation(player, br, "mission daily bonus")
				end
				e.streakDays = (typeof(e.streakDays) == "number" and e.streakDays or 0) + 1
				e.worldMissedDays = 0
			end
		end
		PlayerDataService.SetData(player, "MissionProgress", mp)
	end
	updateStarterSliceMissionRuntime(player, mission.jobName, "completed")

	-- Destroy the mission part immediately so the marker disappears before client feedback.
	despawnMissionRecord(missionId, "completed")
	log(string.format("mission completed: id=%s player=%s money=%d rep=%d", missionId, player.Name, rewardMoney, rewardRep))

	if missionPos then
		local explosion = Instance.new("Part")
		explosion.Name = "MissionCompleteBurst"
		explosion.Size = Vector3.new(8, 8, 8)
		explosion.Position = missionPos
		explosion.Material = Enum.Material.Neon
		explosion.Color = Color3.fromRGB(0, 255, 100)
		explosion.Anchored = true
		explosion.CanCollide = false
		explosion.Shape = Enum.PartType.Ball
		explosion.Parent = getMissionRuntimeFolder()
		task.delay(2, function()
			if explosion.Parent then
				explosion:Destroy()
			end
		end)
	end

	local remotes = ReplicatedStorage:FindFirstChild("MyCityRemotes")
	if remotes then
		local notif = remotes:FindFirstChild("ShowNotification")
		if notif and notif:IsA("RemoteEvent") then
			(notif :: RemoteEvent):FireClient(
				player,
				"✅ Missão Concluída! " .. titleStr .. " | +" .. tostring(rewardMoney) .. " CC +" .. tostring(rewardRep) .. " Rep",
				"success"
			)
			print(LOG_PREFIX .. " notification sent (ShowNotification)")
		else
			print(LOG_PREFIX .. " ShowNotification NOT FOUND")
		end
		local missionCompleted = remotes:FindFirstChild("MissionCompleted")
		if missionCompleted and missionCompleted:IsA("RemoteEvent") then
			(missionCompleted :: RemoteEvent):FireClient(player, {
				missionId = missionId,
				title = titleStr,
				money = rewardMoney,
				rep = rewardRep,
			})
			print(LOG_PREFIX .. " MissionCompleted fired")
		end
	else
		print(LOG_PREFIX .. " MyCityRemotes folder NOT FOUND")
	end

	print(LOG_PREFIX .. ":", player.Name, "completed:", titleStr)
end

function MissionService.GetActiveMissions(player: Player): any
	if not PlayerDataService.HasSession(player) then
		return { available = {}, assigned = nil }
	end

	local data = PlayerDataService.GetData(player)
	local job = if data and typeof(data.Job) == "string" then data.Job else "Unemployed"
	local list: { any } = {}
	for mid, rec in activeMissions do
		if typeof(mid) == "string" and typeof(rec) == "table" then
			if rec.jobName == job and not rec.assignedPlayer and rec.part and rec.part.Parent then
				local d = rec.def
				table.insert(list, {
					id = mid,
					title = d and d.title or "Mission",
					desc = d and d.desc or "",
					location = rec.locationName or (d and d.location) or "",
				})
			end
		end
	end
	local assigned: any = nil
	local mid = playerMissionId[player]
	if mid then
		local r = activeMissions[mid]
		if r and typeof(r) == "table" and r.def then
			local dur = typeof(r.def.time) == "number" and r.def.time or 300
			local t0 = typeof(r.acceptedAt) == "number" and r.acceptedAt or r.startTime
			assigned = {
				id = mid,
				title = r.def.title,
				deadline = typeof(t0) == "number" and (t0 + dur) or nil,
			}
		end
	end
	if not assigned then
		local starterSliceView = buildStarterSliceViewData(data)
		if starterSliceView then
			assigned = buildStarterSliceAssignedMission(starterSliceView)
		end
	end
	return { available = list, assigned = assigned }
end

function MissionService.GetDailyProgress(player: Player): any
	if not PlayerDataService.HasSession(player) then
		return { completed = 0, goal = WORLD_DAILY_GOAL, streak = 0, missedDays = 0, missionDone = false }
	end
	local data = PlayerDataService.GetData(player)
	local job = typeof(data.Job) == "string" and data.Job or "Unemployed"
	local mp = data.MissionProgress
	local e: any = {}
	if typeof(mp) == "table" and typeof((mp :: any)[job]) == "table" then
		e = (mp :: any)[job]
	end
	local dk = calendarDayKey()
	local rawToday = 0
	if typeof(e.worldDayKey) == "number" and e.worldDayKey == dk and typeof(e.worldCompletionsToday) == "number" then
		rawToday = e.worldCompletionsToday
	end
	local completed = math.min(rawToday, WORLD_DAILY_GOAL)
	local streak = typeof(e.streakDays) == "number" and e.streakDays or 0
	local missed = typeof(e.worldMissedDays) == "number" and e.worldMissedDays or 0
	local missionDone = rawToday >= WORLD_DAILY_GOAL
	return {
		completed = completed,
		goal = WORLD_DAILY_GOAL,
		streak = streak,
		missedDays = missed,
		missionDone = missionDone,
	}
end

function MissionService.GetStarterSliceView(player: Player): any
	if not PlayerDataService.HasSession(player) then
		return nil
	end

	local data = PlayerDataService.GetData(player)
	local starterSliceView = buildStarterSliceViewData(data)
	if not starterSliceView then
		return nil
	end

	return {
		slice = IronholmSliceConfig.Slice,
		jobOrder = IronholmSliceConfig.JobOrder,
		job = starterSliceView.job,
		mission = starterSliceView.mission,
		dailies = starterSliceView.dailies,
		aspiration = starterSliceView.aspiration,
		objectiveText = starterSliceView.objectiveText,
		objectiveFallbackText = starterSliceView.objectiveFallbackText,
	}
end

function MissionService.MarkStarterSliceMissionClaimed(player: Player): boolean
	local claimed = markStarterSliceMissionClaimed(player)
	if claimed then
		syncStarterRuntimeForPlayer(player)
	end
	return claimed
end

function MissionService.CompleteStarterCourierMission(player: Player): boolean
	if not PlayerDataService.HasSession(player) then
		return false
	end

	local data = PlayerDataService.GetData(player)
	local mp = cloneMissionProgress(data.MissionProgress)
	local sliceState = ensureSliceState(mp)
	normalizeStarterSliceState(sliceState)
	local courierJobName = getSliceJobDisplayName(IronholmSliceConfig.StarterFlow.starterJobId) or "Courier"
	if not isStarterSliceMissionRelevant(sliceState, courierJobName) then
		return false
	end
	if sliceState.missionStatus ~= "in_progress" then
		return false
	end

	local missionDef = getSliceMissionDefinition(sliceState.activeMissionId)
	if not missionDef then
		return false
	end

	local rewardMoney = typeof(missionDef.rewardMoney) == "number" and missionDef.rewardMoney or 0
	if not applyStarterSliceMissionStatus(sliceState, courierJobName, "completed") then
		return false
	end

	local dailyProgress = sliceState.dailyProgress :: { [string]: number }
	dailyProgress.jobs_completed = (typeof(dailyProgress.jobs_completed) == "number" and dailyProgress.jobs_completed or 0) + 1
	dailyProgress.money_earned = (typeof(dailyProgress.money_earned) == "number" and dailyProgress.money_earned or 0) + rewardMoney
	dailyProgress.clean_missions_completed =
		(typeof(dailyProgress.clean_missions_completed) == "number" and dailyProgress.clean_missions_completed or 0) + 1
	sliceState.dailyProgress = dailyProgress

	local currentMoney = typeof(data.Money) == "number" and data.Money or 0
	if not PlayerDataService.SetDataBatch(player, {
		Money = currentMoney + rewardMoney,
		MissionProgress = mp,
	}) then
		return false
	end

	syncStarterRuntimeForPlayer(player)
	notifyPlayer(player, string.format("✅ Courier run complete: +%d CC", rewardMoney), "success")

	local missionCompleted = getMissionRemote("MissionCompleted")
	if missionCompleted then
		missionCompleted:FireClient(player, {
			missionId = missionDef.id,
			title = typeof(missionDef.title) == "string" and missionDef.title or "Courier Run",
			money = rewardMoney,
			rep = 0,
		})
	end

	return true
end

-- ——— Maintenance loops ———

local function resetWorldProgressForNewDay()
	local newDay = calendarDayKey()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.HasSession(player) then
			local data = PlayerDataService.GetData(player)
			if typeof(data.MissionProgress) == "table" then
				local job = typeof(data.Job) == "string" and data.Job or ""
				if MISSIONS[job] and not isMayorJob(job) then
					local mp = cloneMissionProgress(data.MissionProgress)
					local e = ensureMissionEntry(mp, job)
					local wdk = typeof(e.worldDayKey) == "number" and e.worldDayKey or 0
					if wdk > 0 and wdk < newDay then
						local done = (typeof(e.worldCompletionsToday) == "number" and e.worldCompletionsToday or 0) >= WORLD_DAILY_GOAL
						if not done then
							e.worldMissedDays = (typeof(e.worldMissedDays) == "number" and e.worldMissedDays or 0) + 1
							local md = e.worldMissedDays :: number
							if md == 2 then
								notifyPlayer(
									player,
									"⚠️ Warning: complete your mission or you will be dismissed",
									"info"
								)
							elseif md >= 3 then
								JobService.DismissPlayer(player, job)
								e.worldMissedDays = 0
							end
						else
							e.worldMissedDays = 0
						end
						e.worldCompletionsToday = 0
						e.worldDayKey = newDay
						PlayerDataService.SetData(player, "MissionProgress", mp)
					elseif wdk == 0 then
						e.worldDayKey = newDay
						e.worldCompletionsToday = 0
						PlayerDataService.SetData(player, "MissionProgress", mp)
					end
				end
			end
		end
	end
end

local lastMaintenanceDay: number = 0

local function hourlyLoop()
	while true do
		task.wait(3600)
		local today = calendarDayKey()
		if lastMaintenanceDay == 0 then
			lastMaintenanceDay = today
		elseif today ~= lastMaintenanceDay then
			lastMaintenanceDay = today
			resetWorldProgressForNewDay()
			log("Daily world-mission reset (day changed).")
		end
	end
end

local function onPlayerRemoving(player: Player)
	local mid = playerMissionId[player]
	if mid then
		local rec = activeMissions[mid]
		if rec and rec.assignedPlayer == player then
			despawnMissionRecord(mid, "player left")
		end
		playerMissionId[player] = nil
	end
	clearStarterRuntimeForPlayer(player)
end

local runtimeStarted = false

-- Called from init.server after require; no task.spawn / task.wait at module top level.
function MissionService.Initialize()
	ensureMissionRuntimeReady()
	removeLegacyMissionFolder()
	resetMissionRuntime()

	task.defer(function()
		local function startRuntime()
			if runtimeStarted then
				return
			end
			if not RunService:IsRunning() then
				return
			end
			runtimeStarted = true

			if not game:IsLoaded() then
				game.Loaded:Wait()
			end

			PlayerDataService.OnDataLoaded(function(player: Player)
				task.defer(function()
					ensureIronholmStarterSlice(player)
					MissionService.NotifyPlayerJobUpdated(player)
				end)
			end)

			task.spawn(function()
				if not game:IsLoaded() then
					game.Loaded:Wait()
				end
				if RunService:IsStudio() and not RunService:IsRunning() then
					warn(LOG_PREFIX .. " not running in Play mode, skipping spawn loop")
					return
				end
				print(LOG_PREFIX .. " spawn loop starting...")
				while true do
					task.wait(180)
					for jobName in MISSIONS do
						if hasEligibleWorkerForJob(jobName) and countActiveForJob(jobName) < 2 then
							MissionService.SpawnMission(jobName)
						end
					end
				end
			end)

			task.spawn(function()
				if not game:IsLoaded() then
					game.Loaded:Wait()
				end
				if RunService:IsStudio() and not RunService:IsRunning() then
					warn(LOG_PREFIX .. " not running in Play mode, skipping hourly loop")
					return
				end
				hourlyLoop()
			end)

			Players.PlayerRemoving:Connect(onPlayerRemoving)
			log("started (spawn every 180s per job cap 2, hourly day check)")
		end

		if RunService:IsRunning() then
			startRuntime()
		else
			warn(LOG_PREFIX .. " loaded before simulation run; will start when RunService.Running becomes true")
			RunService:GetPropertyChangedSignal("Running"):Connect(function()
				if RunService:IsRunning() then
					startRuntime()
				end
			end)
		end
	end)
	print("[MY CITY] MissionService started")
end

return MissionService
