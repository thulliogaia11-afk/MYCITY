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

local LOG_PREFIX = "[MY CITY] MissionService"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)
local JobService = require(script.Parent:WaitForChild("JobService") :: ModuleScript)

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

-- ——— Runtime state ———
-- Each entry: { def, jobName, part, startTime, assignedPlayer?, locationName, timeoutThread? }
local activeMissions: { [string]: any } = {}
-- Player may only have one active world mission at a time.
local playerMissionId: { [Player]: string } = {}

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
	local data = PlayerDataService.GetData(player)
	if not data then
		return false
	end
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

local function ensureMissionEntry(mp: { [string]: any }, jobName: string): { [string]: any }
	local e = mp[jobName]
	if typeof(e) ~= "table" then
		e = {}
		mp[jobName] = e
	end
	return e :: { [string]: any }
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
	part.Parent = Workspace

	part:SetAttribute("RequiredJob", jobName)
	part:SetAttribute("MissionId", missionId)
	part:SetAttribute("MissionTitle", typeof(missionDef.title) == "string" and missionDef.title or "Mission")

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

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Adornee = part
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = typeof(missionDef.title) == "string" and missionDef.title or "Mission"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AcceptMission"
	prompt.ActionText = "Accept Mission"
	prompt.ObjectText = typeof(missionDef.title) == "string" and missionDef.title or "Mission"
	prompt.MaxActivationDistance = 15
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		local data = PlayerDataService.GetData(player)
		if not data then
			return
		end
		local pj = typeof(data.Job) == "string" and data.Job or "Unemployed"
		if pj ~= jobName or isMayorJob(pj) then
			local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
			local notif = folder and folder:FindFirstChild("ShowNotification")
			if notif and notif:IsA("RemoteEvent") then
				(notif :: RemoteEvent):FireClient(player, "⚠️ Esta missão é para " .. jobName, "warning")
			end
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
			if part.Parent then
				part:Destroy()
			end
			activeMissions[missionId] = nil
			print(LOG_PREFIX .. " Despawned mission " .. missionId .. " (offer expired)")
		end
	end)

	broadcastMissionAvailable(missionId, rec)
	print(LOG_PREFIX .. " Mission spawned:", missionDef.title, "at", missionDef.location)
	return missionId
end

function MissionService.NotifyPlayerJobUpdated(player: Player)
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

	local data = PlayerDataService.GetData(player)
	if not data then
		print(LOG_PREFIX .. " AcceptMission - no PlayerData")
		return
	end
	local job = typeof(data.Job) == "string" and data.Job or "Unemployed"
	if job ~= mission.jobName or isMayorJob(job) then
		print(LOG_PREFIX .. " AcceptMission - job mismatch:", job, "vs", mission.jobName)
		notifyPlayer(player, "⚠️ This mission is not for your job!", "warning")
		return
	end

	mission.assignedPlayer = player
	mission.acceptedAt = os.time()
	playerMissionId[player] = missionId

	if mission.part and mission.part.Parent then
		mission.part.Color = Color3.fromRGB(255, 165, 0)
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
	completePrompt.Triggered:Connect(function(trigPlayer: Player)
		print(LOG_PREFIX .. " CompleteMission prompt triggered by:", trigPlayer.Name, "for missionId:", capturedMissionId)
		if trigPlayer ~= player then
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
			if m.part and m.part.Parent then
				m.part:Destroy()
			end
			activeMissions[missionId] = nil
			playerMissionId[player] = nil
			local expiredEv = getMissionRemote("MissionExpired")
			if expiredEv then
				expiredEv:FireClient(player, { missionId = missionId, title = titleStr })
			end
			local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
			local notif = folder and folder:FindFirstChild("ShowNotification")
			if notif and notif:IsA("RemoteEvent") then
				(notif :: RemoteEvent):FireClient(player, "⏰ Missão expirada: " .. titleStr, "warning")
			end
			print(LOG_PREFIX .. " Despawned mission " .. missionId .. " (timer expired)")
		end
	end)

	print(LOG_PREFIX .. ":", player.Name, "accepted:", mission.def.title)
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

	if mission.part then
		if mission.part.Parent then
			mission.part:Destroy()
			print(LOG_PREFIX .. " part destroyed")
		else
			print(LOG_PREFIX .. " part already has no Parent (destroyed?)")
		end
	else
		print(LOG_PREFIX .. " part is nil")
	end

	activeMissions[missionId] = nil
	playerMissionId[player] = nil
	print(LOG_PREFIX .. " removed from activeMissions + cleared playerMissionId")

	local def = mission.def
	local reward = typeof(def.reward) == "table" and def.reward or {}
	local rewardMoney = typeof(reward.money) == "number" and reward.money or 0
	local rewardRep = typeof(reward.rep) == "number" and reward.rep or 0
	local titleStr = typeof(def.title) == "string" and def.title or "Mission"
	local jobName = mission.jobName

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
	return { available = list, assigned = assigned }
end

function MissionService.GetDailyProgress(player: Player): any
	local data = PlayerDataService.GetData(player)
	if not data then
		return { completed = 0, goal = WORLD_DAILY_GOAL, streak = 0, missedDays = 0, missionDone = false }
	end
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

-- ——— Maintenance loops ———

local function resetWorldProgressForNewDay()
	local newDay = calendarDayKey()
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.GetData(player)
		if not data or typeof(data.MissionProgress) ~= "table" then
			-- skip
		else
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
end

local RunService = game:GetService("RunService")

local runtimeStarted = false

local function start()
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
				if countActiveForJob(jobName) < 2 then
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

-- Only start loops when the DataModel is actually simulating (Play / live server).
-- We do not `return {}` at file top — that would skip all API definitions; init.server needs MissionService.
if RunService:IsRunning() then
	start()
else
	warn(LOG_PREFIX .. " loaded before simulation run; will start when RunService.Running becomes true")
	RunService:GetPropertyChangedSignal("Running"):Connect(function()
		if RunService:IsRunning() then
			start()
		end
	end)
end

return MissionService
