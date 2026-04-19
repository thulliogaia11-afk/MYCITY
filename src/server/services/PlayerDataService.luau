--[[
	PlayerDataService — MY CITY
	Centralized profile/session persistence with one loaded profile per player,
	in-memory mutation, dirty tracking, autosave, save serialization, and BindToClose flushes.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DATASTORE_NAME = "MY_CITY_PlayerData_v1"
local GAME_LABEL = "MY CITY"
local PROFILE_SCHEMA_VERSION = 3
local AUTOSAVE_INTERVAL_SECONDS = 60
local BIND_TO_CLOSE_TIMEOUT_SECONDS = 25

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local VALID_KEYS = {
	SchemaVersion = true,
	Money = true,
	Reputation = true,
	Job = true,
	City = true,
	HouseLevel = true,
	HouseId = true,
	XP = true,
	JoinDate = true,
	MayorTitle = true,
	BankBalance = true,
	Investments = true,
	Outfit = true,
	OwnedOutfits = true,
	HairStyle = true,
	Phone = true,
	Watch = true,
	Laptop = true,
	Chain = true,
	Earrings = true,
	Sneakers = true,
	Shoes = true,
	Cap = true,
	Hat = true,
	Sunglasses = true,
	MissionProgress = true,
	DismissedFrom = true,
	DismissalTime = true,
	Reviews = true,
	AverageRating = true,
	TotalReviews = true,
	SocialScore = true,
}

type ProfileData = { [string]: any }
type ProfileSession = {
	Data: ProfileData,
	Dirty: boolean,
	Saving: boolean,
	PendingSave: boolean,
	PendingCritical: boolean,
	PendingReason: string?,
	Revision: number,
	SavedRevision: number,
	LastSaveAt: number,
	LastDirtyAt: number,
	LoadState: "loading" | "ready",
	ReleaseRequested: boolean,
	IsLeaving: boolean,
	LeaveStartedAt: number,
	FinalSaveStarted: boolean,
	Released: boolean,
	HooksCompleted: boolean,
}

type BeforeSaveHook = {
	serviceName: string,
	priority: number,
	callback: (player: Player) -> (),
}

local function getDefaultData(): ProfileData
	return {
		SchemaVersion = PROFILE_SCHEMA_VERSION,
		Money = 100,
		Reputation = 0,
		Job = "Unemployed",
		City = "None",
		HouseLevel = 0,
		HouseId = "",
		XP = 0,
		JoinDate = os.time(),
		MayorTitle = "",
		BankBalance = 0,
		Investments = {},
		Outfit = "Default",
		OwnedOutfits = {},
		HairStyle = "Default",
		Phone = false,
		Watch = false,
		Laptop = false,
		Chain = false,
		Earrings = false,
		Sneakers = "None",
		Shoes = "None",
		Cap = "None",
		Hat = "None",
		Sunglasses = false,
		MissionProgress = {},
		DismissedFrom = "",
		DismissalTime = 0,
		Reviews = {},
		AverageRating = 0,
		TotalReviews = 0,
		SocialScore = 0,
	}
end

local DEFAULT_DATA = getDefaultData()

local function log(message: string)
	print(string.format("[%s] ProfileService: %s", GAME_LABEL, message))
end

local function buildProfileSnapshot(session: ProfileSession): string
	local data = session.Data or DEFAULT_DATA
	return string.format(
		"SchemaVersion=%s Money=%s Job=%s City=%s HouseId=%s SocialScore=%s Reputation=%s AverageRating=%s",
		tostring(data.SchemaVersion),
		tostring(data.Money),
		tostring(data.Job),
		tostring(data.City),
		tostring(data.HouseId),
		tostring(data.SocialScore),
		tostring(data.Reputation),
		tostring(data.AverageRating)
	)
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[deepCopy(key)] = deepCopy(inner)
	end
	return out
end

local function valueTypeOk(key: string, value: any): boolean
	local expected = DEFAULT_DATA[key]
	if expected == nil then
		return false
	end
	return typeof(value) == typeof(expected)
end

local function buildProfileFromStoredData(saved: any): (ProfileData, boolean, number)
	local defaults = deepCopy(DEFAULT_DATA)
	if typeof(saved) ~= "table" then
		return defaults, true, 0
	end

	local fromVersion = if typeof(saved.SchemaVersion) == "number" then saved.SchemaVersion else 0
	local migrated = fromVersion ~= PROFILE_SCHEMA_VERSION

	for key, _ in VALID_KEYS do
		local savedValue = saved[key]
		if savedValue ~= nil and valueTypeOk(key, savedValue) then
			defaults[key] = deepCopy(savedValue)
		elseif savedValue ~= nil then
			migrated = true
		end
	end

	defaults.SchemaVersion = PROFILE_SCHEMA_VERSION
	return defaults, migrated, fromVersion
end

local sessions: { [Player]: ProfileSession } = {}
local dataLoadedCallbacks: { (player: Player) -> () } = {}
local outfitRestoreHandlers: { (player: Player) -> () } = {}
local beforeSaveHooks: { BeforeSaveHook } = {}
local shuttingDown = false

local function datastoreKeyForPlayer(player: Player): string
	return tostring(player.UserId)
end

local function markProfileDirty(session: ProfileSession)
	session.Revision += 1
	session.Dirty = session.Revision > session.SavedRevision
	session.LastDirtyAt = os.clock()
end

local function persistProfile(player: Player, session: ProfileSession, reason: string, critical: boolean?): boolean
	local modeLabel = critical and "critical save" or "autosave"
	if session.Saving then
		session.PendingSave = true
		session.PendingCritical = session.PendingCritical or (critical == true)
		session.PendingReason = reason
		log(string.format("%s queued for %s (%s already in flight)", modeLabel, player.Name, tostring(reason)))
		return false
	end

	if session.Revision <= session.SavedRevision and not critical then
		return true
	end

	local revisionToSave = session.Revision
	local payload = deepCopy(session.Data)
	payload.SchemaVersion = PROFILE_SCHEMA_VERSION

	session.Saving = true
	log(string.format("%s started for %s (%s)", modeLabel, player.Name, reason))

	local ok, err = pcall(function()
		dataStore:SetAsync(datastoreKeyForPlayer(player), payload)
	end)

	session.Saving = false

	if ok then
		session.SavedRevision = math.max(session.SavedRevision, revisionToSave)
		session.Dirty = session.Revision > session.SavedRevision
		session.LastSaveAt = os.clock()
		log(string.format("%s completed for %s", modeLabel, player.Name))
	else
		session.Dirty = true
		session.PendingSave = true
		session.PendingCritical = session.PendingCritical or (critical == true)
		session.PendingReason = session.PendingReason or reason
		warn(string.format("[%s] ProfileService: save failure for %s (%s): %s", GAME_LABEL, player.Name, reason, tostring(err)))
		log(string.format("save failure / retry scheduled for %s", player.Name))
	end

	if sessions[player] == session and session.PendingSave and not session.Saving then
		local nextReason = session.PendingReason or "queued follow-up"
		local nextCritical = session.PendingCritical
		session.PendingSave = false
		session.PendingCritical = false
		session.PendingReason = nil
		if session.Revision > session.SavedRevision or nextCritical then
			if session.IsLeaving then
				local current = sessions[player]
				if current == session then
					persistProfile(player, session, nextReason, nextCritical)
				end
			else
				task.defer(function()
					local current = sessions[player]
					if current == session then
						persistProfile(player, session, nextReason, nextCritical)
					end
				end)
			end
		end
	end

	if sessions[player] == session and session.ReleaseRequested and not session.IsLeaving and not session.Saving and not session.PendingSave then
		if session.Revision <= session.SavedRevision then
			sessions[player] = nil
			session.Released = true
			log(string.format("session released for %s after final save", player.Name))
		end
	end

	return ok
end

local function requestSave(player: Player, reason: string, critical: boolean?)
	local session = sessions[player]
	if not session or session.LoadState ~= "ready" then
		return false
	end
	if critical then
		return persistProfile(player, session, reason, true)
	end
	session.PendingSave = true
	session.PendingReason = reason
	task.defer(function()
		local current = sessions[player]
		if current == session and not current.Saving and current.Revision > current.SavedRevision then
			current.PendingSave = false
			current.PendingReason = nil
			persistProfile(player, current, reason, false)
		end
	end)
	return true
end

local function loadFromStore(player: Player): ProfileData
	local session: ProfileSession = {
		Data = deepCopy(DEFAULT_DATA),
		Dirty = false,
		Saving = false,
		PendingSave = false,
		PendingCritical = false,
		PendingReason = nil,
		Revision = 0,
		SavedRevision = 0,
		LastSaveAt = 0,
		LastDirtyAt = 0,
		LoadState = "loading",
		ReleaseRequested = false,
		IsLeaving = false,
		LeaveStartedAt = 0,
		FinalSaveStarted = false,
		Released = false,
		HooksCompleted = false,
	}
	sessions[player] = session

	local saved: any = nil
	local ok, result = pcall(function()
		return dataStore:GetAsync(datastoreKeyForPlayer(player))
	end)
	if ok then
		saved = result
	else
		warn(string.format("[%s] ProfileService: load failed for %s: %s", GAME_LABEL, player.Name, tostring(result)))
	end

	local data, migrated, fromVersion = buildProfileFromStoredData(saved)
	session.Data = data
	session.LoadState = "ready"

	if session.ReleaseRequested or player.Parent == nil then
		log(string.format("discarded loaded profile for %s because the player left during load", player.Name))
		sessions[player] = nil
		return data
	end

	log(string.format(
		"profile loaded for %s (%d) Money=%d Job=%s City=%s",
		player.Name,
		player.UserId,
		typeof(data.Money) == "number" and data.Money or 0,
		tostring(data.Job),
		tostring(data.City)
	))

	if migrated then
		log(string.format("profile migrated for %s from schema v%d to v%d", player.Name, fromVersion, PROFILE_SCHEMA_VERSION))
		markProfileDirty(session)
		requestSave(player, "post-load migration", false)
	end

	for _, callback in dataLoadedCallbacks do
		local callbackOk, callbackErr = pcall(callback, player)
		if not callbackOk then
			warn(string.format("[%s] ProfileService: OnDataLoaded callback error for %s: %s", GAME_LABEL, player.Name, tostring(callbackErr)))
		end
	end

	local okRestore, errRestore = pcall(function()
		local ShopService = require(script.Parent:WaitForChild("ShopService"))
		if ShopService and ShopService.RestoreOutfit then
			ShopService.RestoreOutfit(player)
		end
		if ShopService and ShopService.RestoreAllAccessories then
			ShopService.RestoreAllAccessories(player)
		end
	end)
	if not okRestore then
		warn(string.format("[%s] ProfileService: could not restore outfit/accessories for %s: %s", GAME_LABEL, player.Name, tostring(errRestore)))
	end

	return data
end

local function runBeforeSaveHooks(player: Player, session: ProfileSession)
	if session.HooksCompleted then
		return
	end

	for _, hook in ipairs(beforeSaveHooks) do
		log(string.format("before-save hook start %s for %s", hook.serviceName, player.Name))
		local ok, err = pcall(hook.callback, player)
		if ok then
			log(string.format("before-save hook finished %s for %s", hook.serviceName, player.Name))
		else
			warn(string.format(
				"[%s] ProfileService: before-save hook failed %s for %s: %s",
				GAME_LABEL,
				hook.serviceName,
				player.Name,
				tostring(err)
			))
		end
	end

	session.HooksCompleted = true
end

local function finalizePendingSaves(player: Player, session: ProfileSession, reason: string, deadline: number?): boolean
	while sessions[player] == session and not session.Released do
		if deadline and os.clock() >= deadline then
			warn(string.format("[%s] ProfileService: final leave save timed out for %s", GAME_LABEL, player.Name))
			return false
		end
		if session.Saving then
			task.wait(0.05)
		elseif session.PendingSave then
			local nextReason = session.PendingReason or reason
			local nextCritical = true
			session.PendingSave = false
			session.PendingCritical = false
			session.PendingReason = nil
			persistProfile(player, session, nextReason, nextCritical)
		else
			if session.Revision > session.SavedRevision or session.Dirty or not session.FinalSaveStarted then
				persistProfile(player, session, reason, true)
			end
			if not session.Saving and not session.PendingSave and session.Revision <= session.SavedRevision then
				return true
			end
			task.wait(0.05)
		end
	end
	return session.Revision <= session.SavedRevision
end

local function finalizeLeavePipeline(player: Player, deadline: number?)
	local session = sessions[player]
	if not session then
		return true
	end

	if session.Released then
		return true
	end

	session.ReleaseRequested = true
	if session.LoadState ~= "ready" then
		log(string.format("release queued for %s while profile is still loading", player.Name))
		return false
	end

	if session.IsLeaving then
		log(string.format("leave pipeline already in progress for %s", player.Name))
		while sessions[player] == session and not session.Released do
			if deadline and os.clock() >= deadline then
				return false
			end
			task.wait(0.05)
		end
		return session.Released
	end

	session.IsLeaving = true
	session.LeaveStartedAt = os.clock()
	log(string.format("leave pipeline started for %s", player.Name))

	runBeforeSaveHooks(player, session)

	session.FinalSaveStarted = true
	log(string.format(
		"final leave save summary before %s rev=%d saved=%d dirty=%s pending=%s critical=%s",
		player.Name,
		session.Revision,
		session.SavedRevision,
		tostring(session.Dirty),
		tostring(session.PendingSave),
		tostring(session.PendingCritical)
	))
	log(string.format("final snapshot before %s %s", player.Name, buildProfileSnapshot(session)))
	log(string.format("final leave save started for %s", player.Name))
	local saveCompleted = finalizePendingSaves(player, session, "player leaving", deadline)
	if not saveCompleted then
		return false
	end
	log(string.format("final snapshot after %s %s", player.Name, buildProfileSnapshot(session)))
	log(string.format("final leave save completed for %s", player.Name))

	if sessions[player] == session then
		sessions[player] = nil
	end
	session.Released = true
	log(string.format(
		"final leave save summary after %s rev=%d saved=%d dirty=%s released=%s",
		player.Name,
		session.Revision,
		session.SavedRevision,
		tostring(session.Dirty),
		tostring(session.Released)
	))
	log(string.format("session released for %s", player.Name))
	return true
end

local PlayerDataService = {}

function PlayerDataService.OnDataLoaded(callback: (player: Player) -> ())
	table.insert(dataLoadedCallbacks, callback)
end

function PlayerDataService.RegisterOutfitRestore(handler: (player: Player) -> ())
	table.insert(outfitRestoreHandlers, handler)
end

function PlayerDataService.RegisterBeforeSaveHook(serviceName: string, priority: number, callback: (player: Player) -> ())
	if typeof(serviceName) ~= "string" or serviceName == "" then
		error("RegisterBeforeSaveHook requires a serviceName")
	end
	if typeof(priority) ~= "number" then
		error("RegisterBeforeSaveHook requires a numeric priority")
	end
	if typeof(callback) ~= "function" then
		error("RegisterBeforeSaveHook requires a callback")
	end

	table.insert(beforeSaveHooks, {
		serviceName = serviceName,
		priority = priority,
		callback = callback,
	})
	table.sort(beforeSaveHooks, function(a, b)
		if a.priority == b.priority then
			return a.serviceName < b.serviceName
		end
		return a.priority < b.priority
	end)
end

function PlayerDataService.RestoreOutfit(player: Player)
	for _, handler in outfitRestoreHandlers do
		local ok, err = pcall(handler, player)
		if not ok then
			warn(string.format("[%s] ProfileService: RestoreOutfit handler error for %s: %s", GAME_LABEL, player.Name, tostring(err)))
		end
	end
end

function PlayerDataService.HasSession(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.LoadState == "ready"
end

function PlayerDataService.GetData(player: Player): ProfileData
	local session = sessions[player]
	if session and session.Data then
		return session.Data
	end
	return {}
end

function PlayerDataService.MarkDirty(player: Player, reason: string?): boolean
	local session = sessions[player]
	if not session or session.LoadState ~= "ready" then
		return false
	end
	markProfileDirty(session)
	if reason then
		log(string.format("%s marked dirty (%s)", player.Name, reason))
	end
	return true
end

function PlayerDataService.SetData(player: Player, key: string, value: any): boolean
	if not VALID_KEYS[key] then
		warn(string.format("[%s] ProfileService: invalid key %q", GAME_LABEL, key))
		return false
	end
	if key == "SchemaVersion" then
		warn(string.format("[%s] ProfileService: SchemaVersion is managed internally", GAME_LABEL))
		return false
	end
	if not valueTypeOk(key, value) then
		warn(string.format("[%s] ProfileService: wrong type for %q (expected %s)", GAME_LABEL, key, typeof(DEFAULT_DATA[key])))
		return false
	end

	local session = sessions[player]
	if not session or session.LoadState ~= "ready" then
		warn(string.format("[%s] ProfileService: no ready session for %s", GAME_LABEL, player.Name))
		return false
	end

	session.Data[key] = value
	markProfileDirty(session)
	return true
end

function PlayerDataService.SetDataBatch(player: Player, updates: { [string]: any }): boolean
	if typeof(updates) ~= "table" then
		warn(string.format("[%s] ProfileService: SetDataBatch requires a table", GAME_LABEL))
		return false
	end

	local session = sessions[player]
	if not session or session.LoadState ~= "ready" then
		warn(string.format("[%s] ProfileService: no ready session for %s", GAME_LABEL, player.Name))
		return false
	end

	local updateCount = 0
	for key, value in updates do
		if typeof(key) ~= "string" or not VALID_KEYS[key] then
			warn(string.format("[%s] ProfileService: invalid batch key %q", GAME_LABEL, tostring(key)))
			return false
		end
		if key == "SchemaVersion" then
			warn(string.format("[%s] ProfileService: SchemaVersion is managed internally", GAME_LABEL))
			return false
		end
		if not valueTypeOk(key, value) then
			warn(string.format("[%s] ProfileService: wrong type for %q (expected %s)", GAME_LABEL, key, typeof(DEFAULT_DATA[key])))
			return false
		end
		updateCount += 1
	end

	if updateCount == 0 then
		return true
	end

	for key, value in updates do
		session.Data[key] = value
	end
	markProfileDirty(session)
	return true
end

function PlayerDataService.AdjustMoney(player: Player, delta: number): boolean
	if typeof(delta) ~= "number" or delta ~= delta then
		return false
	end
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = PlayerDataService.GetData(player)
	local currentMoney = typeof(data.Money) == "number" and data.Money or 0
	local nextMoney = currentMoney + delta
	if nextMoney < 0 then
		return false
	end
	return PlayerDataService.SetData(player, "Money", nextMoney)
end

function PlayerDataService.AddMoney(player: Player, delta: number): boolean
	return PlayerDataService.AdjustMoney(player, delta)
end

function PlayerDataService.AddSocialScore(player: Player, delta: number): boolean
	if typeof(delta) ~= "number" or delta ~= delta then
		return false
	end
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = PlayerDataService.GetData(player)
	local currentScore = typeof(data.SocialScore) == "number" and data.SocialScore or 0
	local nextScore = math.max(0, currentScore + delta)
	return PlayerDataService.SetData(player, "SocialScore", nextScore)
end

function PlayerDataService.RequestSave(player: Player, reason: string): boolean
	return requestSave(player, reason, false)
end

function PlayerDataService.RequestImmediateSave(player: Player, reason: string): boolean
	return requestSave(player, reason, true)
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		loadFromStore(player)
	end)
end

local function onPlayerRemoving(player: Player)
	finalizeLeavePipeline(player)
end

local function autosaveLoop()
	while not shuttingDown do
		task.wait(AUTOSAVE_INTERVAL_SECONDS)
		log("autosave started")
		for player, session in pairs(sessions) do
			if session.LoadState == "ready" and session.Dirty then
				persistProfile(player, session, "autosave interval", false)
			end
		end
		log("autosave completed")
	end
end

local function bindToCloseHandler()
	shuttingDown = true
	log("bind-to-close saves started")
	local deadline = os.clock() + BIND_TO_CLOSE_TIMEOUT_SECONDS

	repeat
		local pendingWork = false
		for player, session in pairs(sessions) do
			if session.LoadState == "ready" and not session.Released then
				pendingWork = true
				finalizeLeavePipeline(player, deadline)
			elseif session.LoadState == "loading" and not session.Released then
				pendingWork = true
			end
		end
		if not pendingWork then
			break
		end
		task.wait(0.2)
	until os.clock() >= deadline

	log("bind-to-close saves completed")
end

local function start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(bindToCloseHandler)

	task.spawn(autosaveLoop)

	task.defer(function()
		for _, player in Players:GetPlayers() do
			onPlayerAdded(player)
		end
	end)
end

start()

return PlayerDataService
