--[[
	HouseService — MY CITY
	House tiers, purchases via PlayerDataService, and passive income every real minute (60s).
]]

local Players = game:GetService("Players")

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local HouseEntryService = require(script.Parent:WaitForChild("HouseEntryService"))

export type HouseDefinition = {
	Name: string,
	Description: string,
	Price: number,
	DailyIncome: number,
	RequiredReputation: number,
	Level: number,
}

local HOUSES: { [number]: HouseDefinition } = {
	[1] = {
		Name = "Shared Room",
		Description = "Starter housing — a modest shared space until you upgrade.",
		Price = 0,
		DailyIncome = 0,
		RequiredReputation = 0,
		Level = 1,
	},
	[2] = {
		Name = "Studio Apartment",
		Description = "Compact city living with room to grow.",
		Price = 500,
		DailyIncome = 2,
		RequiredReputation = 50,
		Level = 2,
	},
	[3] = {
		Name = "Family House",
		Description = "Spacious home for a growing household.",
		Price = 2000,
		DailyIncome = 8,
		RequiredReputation = 150,
		Level = 3,
	},
	[4] = {
		Name = "Luxury Villa",
		Description = "Premium estate with maximum comfort and status.",
		Price = 8000,
		DailyIncome = 25,
		RequiredReputation = 400,
		Level = 4,
	},
}

local LEVEL_ORDER = { 1, 2, 3, 4 }

local PASSIVE_INTERVAL = 60 -- seconds (one payout of DailyIncome per tick)

local function houseForLevel(level: number): HouseDefinition?
	return HOUSES[level]
end

-- Source of truth for ownership is PlayerDataService.Data.HouseLevel (1–4).
local function getHouseLevel(player: Player): number
	if not PlayerDataService.HasSession(player) then
		return 1
	end
	local data = PlayerDataService.GetData(player)
	local lvl = data.HouseLevel
	if typeof(lvl) ~= "number" or lvl < 1 or lvl > 4 then
		return 1
	end
	return lvl
end

local HouseService = {}

function HouseService.GetHouses(): { HouseDefinition }
	local list: { HouseDefinition } = {}
	for _, level in LEVEL_ORDER do
		table.insert(list, table.clone(HOUSES[level] :: HouseDefinition))
	end
	return list
end

function HouseService.GetPlayerHouse(player: Player): HouseDefinition
	local level = getHouseLevel(player)
	local def = houseForLevel(level)
	if def then
		return table.clone(def)
	end
	return table.clone(HOUSES[1] :: HouseDefinition)
end

function HouseService.GetPassiveIncome(player: Player): number
	return HouseService.GetPlayerHouse(player).DailyIncome
end

function HouseService.CanAfford(player: Player, level: number): boolean
	local house = houseForLevel(level)
	if not house then
		return false
	end

	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = PlayerDataService.GetData(player)

	if data.HouseLevel >= level then
		return false
	end

	return data.Money >= house.Price and data.Reputation >= house.RequiredReputation
end

function HouseService.BuyHouse(player: Player, level: number): boolean
	local house = houseForLevel(level)
	if not house then
		print(string.format("[%s] BuyHouse: invalid level %s for %s", GAME_LABEL, tostring(level), player.Name))
		return false
	end

	if not PlayerDataService.HasSession(player) then
		print(string.format("[%s] BuyHouse: no data for %s", GAME_LABEL, player.Name))
		return false
	end
	local data = PlayerDataService.GetData(player)

	if data.HouseLevel >= level then
		print(string.format("[%s] BuyHouse: %s already owns tier %d or better", GAME_LABEL, player.Name, level))
		return false
	end

	if data.Money < house.Price then
		print(
			string.format(
				"[%s] BuyHouse: %s cannot afford %s (need %d CC, have %d)",
				GAME_LABEL,
				player.Name,
				house.Name,
				house.Price,
				data.Money
			)
		)
		return false
	end

	if data.Reputation < house.RequiredReputation then
		print(
			string.format(
				"[%s] BuyHouse: %s needs %d reputation for %s (have %d)",
				GAME_LABEL,
				player.Name,
				house.RequiredReputation,
				house.Name,
				data.Reputation
			)
		)
		return false
	end

	local oldMoney = data.Money
	local newMoney = oldMoney - house.Price
	if not PlayerDataService.SetData(player, "Money", newMoney) then
		print(string.format("[%s] BuyHouse: failed to deduct money for %s", GAME_LABEL, player.Name))
		return false
	end

	if not PlayerDataService.SetData(player, "HouseLevel", level) then
		PlayerDataService.SetData(player, "Money", oldMoney)
		print(string.format("[%s] BuyHouse: failed to set HouseLevel for %s (refunded)", GAME_LABEL, player.Name))
		return false
	end

	-- Release old house if player had one
	HouseEntryService.ReleaseHouse(player)
	-- Assign new physical house
	local assignedId = HouseEntryService.AssignHouse(player, level)
	if assignedId ~= "" then
		print("[MY CITY] HouseService: assigned physical house", assignedId, "to", player.Name)
	else
		print("[MY CITY] HouseService: no available houses of level", level)
	end

	print(
		string.format(
			"[%s] %s purchased %s (level %d) for %d CC",
			GAME_LABEL,
			player.Name,
			house.Name,
			level,
			house.Price
		)
	)
	return true
end

local function grantStarterHouseIfNeeded(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = PlayerDataService.GetData(player)

	if data.HouseLevel ~= 0 then
		return
	end

	if not PlayerDataService.SetData(player, "HouseLevel", 1) then
		print(string.format("[%s] Starter house: failed to assign Shared Room for %s", GAME_LABEL, player.Name))
		return
	end

	local hid = HouseEntryService.AssignHouse(player, 1)
	print(
		string.format(
			"[%s] %s was assigned starter housing: Shared Room (level 1) — HouseId=%s",
			GAME_LABEL,
			player.Name,
			hid ~= "" and hid or "(none — check map)"
		)
	)
end

local function passiveIncomeLoop()
	while true do
		task.wait(PASSIVE_INTERVAL)

		for _, player in Players:GetPlayers() do
			if not PlayerDataService.HasSession(player) then
				continue
			end
			local data = PlayerDataService.GetData(player)

			-- Shared Room (level 1) / unstored edge: no passive payout.
			if data.HouseLevel <= 1 then
				continue
			end

			local house = houseForLevel(data.HouseLevel)
			if not house or house.DailyIncome <= 0 then
				continue
			end

			local income = house.DailyIncome
			local newMoney = data.Money + income
			if not PlayerDataService.SetData(player, "Money", newMoney) then
				warn(string.format("[%s] Passive income save failed for %s", GAME_LABEL, player.Name))
				continue
			end

			print(
				string.format(
					"[%s] %s earned %d CC passive income from %s",
					GAME_LABEL,
					player.Name,
					income,
					house.Name
				)
			)
		end
	end
end

local function start()
	PlayerDataService.OnDataLoaded(grantStarterHouseIfNeeded)
	task.spawn(passiveIncomeLoop)
end

start()

return HouseService
