--[[
	CityService - MY CITY
	Tracks two cities, live population, and ties assignments to PlayerDataService (City field).
]]

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(
	(script.Parent.Parent :: Instance):WaitForChild("services"):WaitForChild("PlayerDataService") :: ModuleScript
)

export type CityInfo = {
	Name: string,
	Description: string,
	Bonus: string,
	Population: number,
	Level: number,
	Treasury: number,
}

local function buildCityState(
	name: string,
	description: string,
	bonus: string,
	population: number,
	level: number,
	treasury: number
): CityInfo
	return {
		Name = name,
		Description = description,
		Bonus = bonus,
		Population = population,
		Level = level,
		Treasury = treasury,
	}
end

local cities: { [string]: CityInfo } = {
	Ironholm = buildCityState(
		"Ironholm",
		"Industrial powerhouse with factories and supply chains. Workers earn more here.",
		"+20% City Coins from jobs",
		0,
		1,
		0
	),
	Solara = buildCityState(
		"Solara",
		"Sun-soaked tourism hub known for events, beaches, and visitors.",
		"+20% reputation from activities",
		0,
		1,
		0
	),
}

local playerCity: { [Player]: string } = {}
local cityAssignmentListeners: { (player: Player, oldCity: string?, newCity: string) -> () } = {}

local function fireCityAssignmentChanged(player: Player, oldCity: string?, newCity: string)
	for _, cb in cityAssignmentListeners do
		task.spawn(function()
			pcall(cb, player, oldCity, newCity)
		end)
	end
end

local function isValidCityName(cityName: string): boolean
	return cities[cityName] ~= nil
end

local function getPopulationCount(cityName: string): number
	local city = cities[cityName]
	return city and city.Population or 0
end

local function addPopulation(cityName: string, delta: number)
	local city = cities[cityName]
	if not city then
		return
	end
	city.Population = math.max(0, city.Population + delta)
end

local function log(message: string)
	print(string.format("[%s] CityService: %s", GAME_LABEL, message))
end

local function rosterAssign(player: Player, cityName: string)
	if not isValidCityName(cityName) then
		return
	end
	local previous = playerCity[player]
	if previous == cityName then
		return
	end
	if previous and isValidCityName(previous) then
		addPopulation(previous, -1)
	end
	playerCity[player] = cityName
	addPopulation(cityName, 1)
end

local function rosterClear(player: Player)
	local previous = playerCity[player]
	if previous and isValidCityName(previous) then
		addPopulation(previous, -1)
	end
	playerCity[player] = nil
end

local CityService = {}

function CityService.OnCityAssignmentChanged(callback: (player: Player, oldCity: string?, newCity: string) -> ())
	table.insert(cityAssignmentListeners, callback)
end

function CityService.GetCities(): { [string]: CityInfo }
	local snapshot: { [string]: CityInfo } = {}
	for name, city in cities do
		snapshot[name] = table.clone(city)
	end
	return snapshot
end

function CityService.GetCity(cityName: string): CityInfo?
	if not isValidCityName(cityName) then
		return nil
	end
	return table.clone(cities[cityName])
end

function CityService.GetPopulation(cityName: string): number
	if not isValidCityName(cityName) then
		warn(string.format("[%s] GetPopulation: unknown city %q", GAME_LABEL, cityName))
		return 0
	end
	return getPopulationCount(cityName)
end

function CityService.JoinCity(player: Player, cityName: string): boolean
	if not isValidCityName(cityName) then
		print(string.format("[%s] JoinCity failed: %s - invalid city %q", GAME_LABEL, player.Name, cityName))
		return false
	end

	local current = playerCity[player]
	if current == cityName then
		log(string.format("%s already in %s, skipping join", player.Name, cityName))
		return true
	end

	local oldCityForListeners: string? = if current and isValidCityName(current) then current else nil
	rosterAssign(player, cityName)

	local ok = PlayerDataService.SetData(player, "City", cityName)
	if not ok then
		if oldCityForListeners then
			rosterAssign(player, oldCityForListeners)
		else
			rosterClear(player)
		end
		print(string.format("[%s] JoinCity failed: could not save city for %s", GAME_LABEL, player.Name))
		return false
	end

	fireCityAssignmentChanged(player, oldCityForListeners, cityName)

	if oldCityForListeners then
		log(string.format("%s switched city %s -> %s", player.Name, oldCityForListeners, cityName))
	else
		log(string.format("%s joined %s", player.Name, cityName))
	end
	return true
end

local function onPlayerDataLoaded(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = PlayerDataService.GetData(player)
	local savedCity = data.City

	if typeof(savedCity) == "string" and savedCity == "None" then
		CityService.JoinCity(player, "Ironholm")
	elseif typeof(savedCity) == "string" and savedCity ~= "None" and isValidCityName(savedCity) then
		rosterAssign(player, savedCity)
		print(string.format(
			"[%s] Restored city assignment for %s -> %s (population %d)",
			GAME_LABEL,
			player.Name,
			savedCity,
			getPopulationCount(savedCity)
		))
	end
end

function CityService.LeaveCity(player: Player)
	local cityName = playerCity[player]
	if not cityName or not isValidCityName(cityName) then
		playerCity[player] = nil
		log(string.format("%s not assigned to any city, skipping leave", player.Name))
		return
	end

	rosterClear(player)

	local data = PlayerDataService.GetData(player)
	if data then
		local ok = PlayerDataService.SetData(player, "City", "None")
		if ok then
			fireCityAssignmentChanged(player, cityName, "None")
			log(string.format("%s left %s", player.Name, cityName))
		else
			print(string.format("[%s] LeaveCity: roster updated but save failed for %s", GAME_LABEL, player.Name))
		end
	else
		log(string.format("%s left %s", player.Name, cityName))
	end
end

local function onBeforeSaveLeave(player: Player)
	print(string.format("[%s] BeforeSaveLeave -> LeaveCity for %s", GAME_LABEL, player.Name))
	CityService.LeaveCity(player)
end

local function start()
	PlayerDataService.OnDataLoaded(onPlayerDataLoaded)
	PlayerDataService.RegisterBeforeSaveHook("CityService", 30, onBeforeSaveLeave)
end

start()

return CityService
