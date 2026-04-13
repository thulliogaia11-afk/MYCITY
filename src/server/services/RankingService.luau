--[[
	RankingService — MY CITY
	Periodic city scores from population, treasury, and player averages (reputation & money).
]]

local Players = game:GetService("Players")

local GAME_LABEL = "MY CITY"
local RANK_INTERVAL_SEC = 60

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local CityService = require(script.Parent:WaitForChild("CityService") :: ModuleScript)
local ElectionService = require(script.Parent:WaitForChild("ElectionService") :: ModuleScript)

export type RankRow = {
	Position: number,
	CityName: string,
	Score: number,
}

-- Last snapshot after a full recalculation.
local lastScores: { [string]: number } = {}
local lastRanking: { RankRow } = {}

local function averagesForCity(cityName: string): (number, number)
	local sumRep = 0
	local sumMoney = 0
	local count = 0

	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.GetData(player)
		if data and data.City == cityName then
			sumRep += data.Reputation
			sumMoney += data.Money
			count += 1
		end
	end

	if count == 0 then
		return 0, 0
	end

	return sumRep / count, sumMoney / count
end

-- Points: pop * 10; treasury / 100; avgRep * 2; avgMoney / 50 (floored where noted).
local function calculateCityScore(cityName: string): number
	local city = CityService.GetCity(cityName)
	if not city then
		return 0
	end

	local population = city.Population
	local treasury = city.Treasury
	local avgRep, avgMoney = averagesForCity(cityName)

	local popPts = population * 10
	local treasuryPts = math.floor(treasury / 100)
	local repPts = math.floor(avgRep * 2 + 1e-6)
	local moneyPts = math.floor(avgMoney / 50 + 1e-6)

	local diplomacyPts = ElectionService.GetTourismRankingBonus(cityName) + ElectionService.GetSecurityRankingBonus(cityName)

	return popPts + treasuryPts + repPts + moneyPts + diplomacyPts
end

local function recalculateScores()
	table.clear(lastScores)

	local rows: { { CityName: string, Score: number } } = {}

	for cityName, _ in CityService.GetCities() do
		local score = calculateCityScore(cityName)
		lastScores[cityName] = score
		table.insert(rows, { CityName = cityName, Score = score })
	end

	table.sort(rows, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.CityName < b.CityName
	end)

	table.clear(lastRanking)
	for i, row in rows do
		table.insert(lastRanking, {
			Position = i,
			CityName = row.CityName,
			Score = row.Score,
		})
	end
end

local RankingService = {}

function RankingService.GetRanking(): { RankRow }
	local copy: { RankRow } = {}
	for _, row in lastRanking do
		table.insert(copy, table.clone(row))
	end
	return copy
end

function RankingService.GetCityScore(cityName: string): number
	return lastScores[cityName] or 0
end

function RankingService.GetLeader(): RankRow?
	local top = lastRanking[1]
	if not top then
		return nil
	end
	return table.clone(top)
end

function RankingService.PrintRanking()
	if #lastRanking == 0 then
		print(string.format("[%s] (Ranking) No data yet — waiting for first calculation.", GAME_LABEL))
		return
	end

	print(string.format("[%s] ========== CITY RANKING ==========", GAME_LABEL))
	for _, row in lastRanking do
		print(
			string.format(
				"[%s] #%d  %-12s  —  %d pts",
				GAME_LABEL,
				row.Position,
				row.CityName,
				row.Score
			)
		)
	end
	print(string.format("[%s] ==================================", GAME_LABEL))
end

local function tick()
	recalculateScores()
	RankingService.PrintRanking()

	local leader = RankingService.GetLeader()
	if leader then
		print(
			string.format(
				"[%s] Leading city: %s (#%d, %d pts)",
				GAME_LABEL,
				leader.CityName,
				leader.Position,
				leader.Score
			)
		)
	end
end

local function start()
	task.spawn(function()
		tick()
		while true do
			task.wait(RANK_INTERVAL_SEC)
			tick()
		end
	end)
end

start()

return RankingService
