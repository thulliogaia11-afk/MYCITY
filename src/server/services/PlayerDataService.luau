--[[
	PlayerDataService — MY CITY
	Session-style player data (ProfileService-like): one in-memory profile per player,
	DataStore persistence with pcall-wrapped API calls, save on leave and on SetData.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

-- Bump suffix if you ever need a fresh store (cannot reset published keys easily).
local DATASTORE_NAME = "MY_CITY_PlayerData_v1"
local GAME_LABEL = "MY CITY"

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

-- Keys we persist; used for merge and SetData validation.
local VALID_KEYS = {
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
}

local function getDefaultData(): { [string]: any }
	return {
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
	}
end

-- Merge saved table onto defaults so new fields get default values.
local function mergeWithTemplate(saved: any): { [string]: any }
	local defaults = getDefaultData()
	if typeof(saved) ~= "table" then
		return defaults
	end
	local merged = table.clone(defaults)
	for key, _ in VALID_KEYS do
		if saved[key] ~= nil then
			merged[key] = saved[key]
		end
	end
	return merged
end

local function valueTypeOk(key: string, value: any): boolean
	local template = getDefaultData()
	local expected = template[key]
	local expectedType = typeof(expected)
	return typeof(value) == expectedType
end

-- Active sessions: [Player] = { Data = table }
local sessions: { [Player]: { Data: { [string]: any } } } = {}

-- Fired once per player after loadFromStore finishes and the session exists (see OnDataLoaded).
local dataLoadedCallbacks: { (player: Player) -> () } = {}

-- Clothing / saved BodyColors (registered by ShopService to avoid require cycles).
local outfitRestoreHandlers: { (player: Player) -> () } = {}

local function datastoreKeyForPlayer(player: Player): string
	return tostring(player.UserId)
end

-- Save full profile; returns success, errMessage
local function saveToStore(player: Player, data: { [string]: any }): (boolean, string?)
	local key = datastoreKeyForPlayer(player)
	local payload = table.clone(data)

	local ok, err = pcall(function()
		dataStore:SetAsync(key, payload)
	end)

	if ok then
		print(string.format("[%s] Saved data for %s (%d)", GAME_LABEL, player.Name, player.UserId))
		return true, nil
	else
		warn(string.format("[%s] Save failed for %s: %s", GAME_LABEL, player.Name, tostring(err)))
		return false, tostring(err)
	end
end

local function loadFromStore(player: Player): { [string]: any }
	local key = datastoreKeyForPlayer(player)
	local saved: any = nil

	local ok, result = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if ok then
		saved = result
	else
		warn(string.format("[%s] GetAsync failed for %s: %s", GAME_LABEL, player.Name, tostring(result)))
	end

	local data = mergeWithTemplate(saved)
	sessions[player] = { Data = data }

	print(
		string.format(
			"[%s] Loaded data for %s (%d) — Money=%d Job=%s City=%s",
			GAME_LABEL,
			player.Name,
			player.UserId,
			data.Money,
			tostring(data.Job),
			tostring(data.City)
		)
	)

	for _, callback in dataLoadedCallbacks do
		local ok, err = pcall(callback, player)
		if not ok then
			warn(string.format("[%s] OnDataLoaded callback error for %s: %s", GAME_LABEL, player.Name, tostring(err)))
		end
	end

	-- Lazy-require ShopService: loadFromStore can run before init.server has required ShopService,
	-- and PlayerDataService is not the ShopService module (do not call PlayerDataService.RestoreOutfit here).
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
		warn(string.format("[%s] PlayerDataService: could not restore outfit/accessories: %s", GAME_LABEL, tostring(errRestore)))
	end

	return data
end

local function releaseSession(player: Player)
	local session = sessions[player]
	if not session then
		return
	end

	saveToStore(player, session.Data)
	sessions[player] = nil
end

local PlayerDataService = {}

function PlayerDataService.OnDataLoaded(callback: (player: Player) -> ())
	table.insert(dataLoadedCallbacks, callback)
end

function PlayerDataService.RegisterOutfitRestore(handler: (player: Player) -> ())
	table.insert(outfitRestoreHandlers, handler)
end

function PlayerDataService.RestoreOutfit(player: Player)
	for _, handler in outfitRestoreHandlers do
		local ok, err = pcall(handler, player)
		if not ok then
			warn(string.format("[%s] RestoreOutfit handler error for %s: %s", GAME_LABEL, player.Name, tostring(err)))
		end
	end
end

function PlayerDataService.GetData(player: Player): { [string]: any }?
	local session = sessions[player]
	if not session then
		warn(string.format("[%s] GetData: no session for %s", GAME_LABEL, player.Name))
		return nil
	end
	return session.Data
end

function PlayerDataService.SetData(player: Player, key: string, value: any): boolean
	if not VALID_KEYS[key] then
		warn(string.format("[%s] SetData: invalid key %q", GAME_LABEL, key))
		return false
	end

	if not valueTypeOk(key, value) then
		warn(
			string.format(
				"[%s] SetData: wrong type for %q (expected %s)",
				GAME_LABEL,
				key,
				typeof(getDefaultData()[key])
			)
		)
		return false
	end

	local session = sessions[player]
	if not session then
		warn(string.format("[%s] SetData: no session for %s", GAME_LABEL, player.Name))
		return false
	end

	session.Data[key] = value

	local ok = saveToStore(player, session.Data)
	return ok
end

-- Add currency (world missions, etc.). Validates session and persists.
function PlayerDataService.AddMoney(player: Player, delta: number): boolean
	if typeof(delta) ~= "number" or delta ~= delta then
		return false
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false
	end
	local m = typeof(data.Money) == "number" and data.Money or 0
	return PlayerDataService.SetData(player, "Money", m + delta)
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		loadFromStore(player)
	end)
end

local function onPlayerRemoving(player: Player)
	-- Defer so other services (e.g. CityService) can update profile before final save.
	task.defer(function()
		releaseSession(player)
	end)
end

local function start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players already in game (e.g. during a live reload)
	task.defer(function()
		for _, player in Players:GetPlayers() do
			onPlayerAdded(player)
		end
	end)
end

start()

return PlayerDataService
