local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local SocialRatingConfig = require(Shared:WaitForChild("SocialRatingConfig") :: ModuleScript)

local remotes = ReplicatedStorage:WaitForChild("MyCityRemotes")
local showNotification = remotes:WaitForChild("ShowNotification") :: RemoteEvent

local SocialRatingService = {}

type SocialGainEntry = {
	at: number,
	points: number,
}

local recentDrinkSocial: { [Player]: { SocialGainEntry } } = {}
local tierRanks: { [string]: number } = {}

for index, tier in ipairs(SocialRatingConfig.TIERS) do
	tierRanks[tier.name] = index
end

local function log(message: string)
	print(string.format("[%s] SocialRating: %s", GAME_LABEL, message))
end

local function fireSocialIdentityChanged(userId: number)
	local ev = remotes:FindFirstChild("SocialIdentityChanged")
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireAllClients(userId)
	end
end

local function pruneOldEntries(player: Player, nowTs: number): { SocialGainEntry }
	local entries = recentDrinkSocial[player] or {}
	local kept = {}
	for _, entry in ipairs(entries) do
		if nowTs - entry.at <= SocialRatingConfig.DRINK_WINDOW_SECONDS then
			table.insert(kept, entry)
		end
	end
	recentDrinkSocial[player] = kept
	return kept
end

local function currentWindowPoints(entries: { SocialGainEntry }): number
	local total = 0
	for _, entry in ipairs(entries) do
		total += entry.points
	end
	return total
end

function SocialRatingService.GetTierForScore(score: number): string
	local resolvedTier = SocialRatingConfig.TIERS[1].name
	for _, tier in ipairs(SocialRatingConfig.TIERS) do
		if score >= tier.minScore then
			resolvedTier = tier.name
		else
			break
		end
	end
	return resolvedTier
end

function SocialRatingService.GetTier(player: Player): string
	local data = PlayerDataService.GetData(player)
	local score = typeof(data.SocialScore) == "number" and data.SocialScore or 0
	return SocialRatingService.GetTierForScore(score)
end

function SocialRatingService.ApplyDrinkSocial(player: Player, drinkId: string): number
	if typeof(drinkId) ~= "string" or drinkId == "" then
		log(string.format("ignored invalid drink id for %s", player.Name))
		return 0
	end
	if not PlayerDataService.HasSession(player) then
		log(string.format("no player session for %s", player.Name))
		return 0
	end

	local basePoints = SocialRatingConfig.DRINK_SOCIAL_POINTS[drinkId] or 0
	if basePoints <= 0 then
		log(string.format("%s has no social points configured", drinkId))
		return 0
	end

	local nowTs = os.clock()
	local entries = pruneOldEntries(player, nowTs)
	local usedPoints = currentWindowPoints(entries)
	local remainingCap = math.max(0, SocialRatingConfig.DRINK_WINDOW_CAP - usedPoints)
	local awardedPoints = math.min(basePoints, remainingCap)

	if awardedPoints <= 0 then
		log(string.format("%s hit drink cap: used=%d cap=%d", player.Name, usedPoints, SocialRatingConfig.DRINK_WINDOW_CAP))
		return 0
	end

	local data = PlayerDataService.GetData(player)
	local oldScore = typeof(data.SocialScore) == "number" and data.SocialScore or 0
	local oldTier = SocialRatingService.GetTierForScore(oldScore)
	local newScore = oldScore + awardedPoints

	if not PlayerDataService.AddSocialScore(player, awardedPoints) then
		log(string.format("failed to persist SocialScore for %s", player.Name))
		return 0
	end

	table.insert(entries, {
		at = nowTs,
		points = awardedPoints,
	})
	recentDrinkSocial[player] = entries

	local newTier = SocialRatingService.GetTierForScore(newScore)
	log(string.format(
		"%s gained %d social from %s (score=%d tier=%s window=%d/%d)",
		player.Name,
		awardedPoints,
		drinkId,
		newScore,
		newTier,
		usedPoints + awardedPoints,
		SocialRatingConfig.DRINK_WINDOW_CAP
	))

	if (tierRanks[newTier] or 0) > (tierRanks[oldTier] or 0) then
		showNotification:FireClient(player, string.format("New social tier: %s", newTier), "success")
		log(string.format("%s reached new tier %s", player.Name, newTier))
	end

	fireSocialIdentityChanged(player.UserId)

	return awardedPoints
end

Players.PlayerRemoving:Connect(function(player: Player)
	recentDrinkSocial[player] = nil
end)

return SocialRatingService
