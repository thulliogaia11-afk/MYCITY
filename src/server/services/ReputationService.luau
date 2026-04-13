--[[
	ReputationService — MY CITY
	Tiers, add/remove reputation via PlayerDataService; Solara grants +20% on gains.
]]

local Players = game:GetService("Players")

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
require(script.Parent:WaitForChild("CityService") :: ModuleScript)

-- Tier order for detecting upgrades (higher index = higher tier).
local TIER_RANK: { [string]: number } = {
	Newcomer = 1,
	Resident = 2,
	Established = 3,
	Respected = 4,
	Influential = 5,
	Elite = 6,
	Legend = 7,
}

-- Last tier we announced / synced per player (used by CheckTierUp).
local lastKnownTier: { [Player]: string } = {}

-- Unix time until which reputation *loss* is ignored (e.g. pharmacy).
local reputationLossImmuneUntil: { [Player]: number } = {}

local function tierFromScore(score: number): string
	score = math.max(0, math.floor(score))
	if score < 50 then
		return "Newcomer"
	elseif score < 150 then
		return "Resident"
	elseif score < 300 then
		return "Established"
	elseif score < 500 then
		return "Respected"
	elseif score < 750 then
		return "Influential"
	elseif score < 1000 then
		return "Elite"
	else
		return "Legend"
	end
end

local function syncLastTierFromData(player: Player)
	local data = PlayerDataService.GetData(player)
	if data then
		lastKnownTier[player] = tierFromScore(data.Reputation)
	end
end

local ReputationService = {}

function ReputationService.GetReputation(player: Player): number
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	return data.Reputation
end

function ReputationService.GetTier(player: Player): string
	return tierFromScore(ReputationService.GetReputation(player))
end

-- If the player’s tier increased since lastKnownTier, print congratulations and refresh cache.
function ReputationService.CheckTierUp(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end

	local newTier = tierFromScore(data.Reputation)
	local previous = lastKnownTier[player]
	lastKnownTier[player] = newTier

	if not previous then
		return
	end

	local prevRank = TIER_RANK[previous]
	local newRank = TIER_RANK[newTier]
	if prevRank and newRank and newRank > prevRank then
		print(
			string.format(
				"[%s] Congratulations, %s — you reached tier %s! (Reputation: %d)",
				GAME_LABEL,
				player.Name,
				newTier,
				data.Reputation
			)
		)
	end
end

function ReputationService.AddReputation(player: Player, amount: number, reason: string)
	if typeof(amount) ~= "number" or amount <= 0 then
		warn(string.format("[%s] AddReputation: invalid amount for %s", GAME_LABEL, player.Name))
		return
	end

	local data = PlayerDataService.GetData(player)
	if not data then
		print(string.format("[%s] AddReputation failed: no data for %s (%s)", GAME_LABEL, player.Name, reason))
		return
	end

	local gain = amount
	if data.City == "Solara" then
		gain = math.floor(amount * 1.2 + 0.5)
	end

	local newRep = data.Reputation + gain
	if not PlayerDataService.SetData(player, "Reputation", newRep) then
		print(string.format("[%s] AddReputation failed to save for %s (%s)", GAME_LABEL, player.Name, reason))
		return
	end

	print(
		string.format(
			"[%s] +%d reputation for %s (base %d%s) — %s",
			GAME_LABEL,
			gain,
			player.Name,
			amount,
			data.City == "Solara" and ", Solara +20% bonus" or "",
			reason
		)
	)

	ReputationService.CheckTierUp(player)
end

function ReputationService.GrantReputationLossImmunity(player: Player, durationSeconds: number)
	if typeof(durationSeconds) ~= "number" or durationSeconds <= 0 then
		return
	end
	local untilT = os.time() + math.floor(durationSeconds)
	local prev = reputationLossImmuneUntil[player] or 0
	reputationLossImmuneUntil[player] = math.max(prev, untilT)
	print(
		string.format(
			"[%s] Reputation loss immunity granted to %s until %d",
			GAME_LABEL,
			player.Name,
			reputationLossImmuneUntil[player]
		)
	)
end

function ReputationService.IsReputationLossImmune(player: Player): boolean
	return (reputationLossImmuneUntil[player] or 0) > os.time()
end

function ReputationService.RemoveReputation(player: Player, amount: number, reason: string)
	if typeof(amount) ~= "number" or amount <= 0 then
		warn(string.format("[%s] RemoveReputation: invalid amount for %s", GAME_LABEL, player.Name))
		return
	end

	if ReputationService.IsReputationLossImmune(player) then
		print(
			string.format(
				"[%s] Reputation loss blocked (immunity) for %s — %s",
				GAME_LABEL,
				player.Name,
				reason
			)
		)
		return
	end

	local data = PlayerDataService.GetData(player)
	if not data then
		print(string.format("[%s] RemoveReputation failed: no data for %s (%s)", GAME_LABEL, player.Name, reason))
		return
	end

	local newRep = math.max(0, data.Reputation - amount)
	if not PlayerDataService.SetData(player, "Reputation", newRep) then
		print(string.format("[%s] RemoveReputation failed to save for %s (%s)", GAME_LABEL, player.Name, reason))
		return
	end

	print(string.format("[%s] -%d reputation for %s (now %d) — %s", GAME_LABEL, amount, player.Name, newRep, reason))

	ReputationService.CheckTierUp(player)
end

local function onPlayerDataLoaded(player: Player)
	syncLastTierFromData(player)
end

local function onPlayerRemoving(player: Player)
	lastKnownTier[player] = nil
	reputationLossImmuneUntil[player] = nil
end

local function start()
	PlayerDataService.OnDataLoaded(onPlayerDataLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

start()

return ReputationService
