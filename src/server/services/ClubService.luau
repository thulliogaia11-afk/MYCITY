--[[
	ClubService — MY CITY
	Nightclub access gated by reputation score and tier (ReputationService).
]]

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)

-- Must match ReputationService tier ordering (higher index = higher tier).
local TIER_RANK: { [string]: number } = {
	Newcomer = 1,
	Resident = 2,
	Established = 3,
	Respected = 4,
	Influential = 5,
	Elite = 6,
	Legend = 7,
}

-- Minimum reputation score needed to *reach* each tier (aligned with ReputationService.tierFromScore).
local MIN_REP_FOR_TIER: { [string]: number } = {
	Newcomer = 0,
	Resident = 50,
	Established = 150,
	Respected = 300,
	Influential = 500,
	Elite = 750,
	Legend = 1000,
}

export type ClubDefinition = {
	id: string,
	displayName: string,
	minReputation: number,
	minTier: string,
	vipOnly: boolean,
	description: string, -- UI / catalog blurb
	atmosphereWelcome: string, -- printed on successful entry
}

-- Public info shape for UI / remotes (name, requirement, description).
export type ClubInfo = {
	Id: string,
	Name: string,
	Requirement: string,
	Description: string,
	VipOnly: boolean,
}

-- Stable order for iteration and GetAccessibleClubs.
local CLUB_ORDER = {
	"Club_Bronze",
	"Club_Silver",
	"Club_Gold",
	"Club_Diamond",
}

local CLUBS: { [string]: ClubDefinition } = {
	["Club_Bronze"] = {
		id = "Club_Bronze",
		displayName = "Bronze Club",
		minReputation = 0,
		minTier = "Newcomer",
		vipOnly = false,
		description = "The door is open — drinks, music, and a relaxed crowd.",
		atmosphereWelcome = "Welcome to Bronze Club! Basic drinks and good vibes.",
	},
	["Club_Silver"] = {
		id = "Club_Silver",
		displayName = "Silver Lounge",
		minReputation = 50,
		minTier = "Resident",
		vipOnly = false,
		description = "Step up to premium drinks and a live DJ rotation.",
		atmosphereWelcome = "Welcome to Silver Lounge! Premium drinks and live DJ.",
	},
	["Club_Gold"] = {
		id = "Club_Gold",
		displayName = "Gold VIP",
		minReputation = 300,
		minTier = "Respected",
		vipOnly = true,
		description = "VIP-only — exclusive cocktails and private tables.",
		atmosphereWelcome = "Welcome to Gold VIP! Exclusive cocktails and private tables.",
	},
	["Club_Diamond"] = {
		id = "Club_Diamond",
		displayName = "Diamond Elite",
		minReputation = 500,
		minTier = "Influential",
		vipOnly = true,
		description = "The top room in Ironholm for legends and influencers.",
		atmosphereWelcome = "Welcome to Diamond Elite! The finest experience in Ironholm.",
	},
}

local ClubService = {}

-- Reputation floor implied by the required tier (both gates must pass).
local function effectiveMinReputation(club: ClubDefinition): number
	local floorForTier = MIN_REP_FOR_TIER[club.minTier] or 0
	return math.max(club.minReputation, floorForTier)
end

local function formatRequirement(club: ClubDefinition): string
	local tierNote = club.vipOnly and " (VIP only)" or ""
	return string.format(
		"Reputation ≥ %d, tier %s or higher%s",
		club.minReputation,
		club.minTier,
		tierNote
	)
end

local function toClubInfo(club: ClubDefinition): ClubInfo
	return {
		Id = club.id,
		Name = club.displayName,
		Requirement = formatRequirement(club),
		Description = club.description,
		VipOnly = club.vipOnly,
	}
end

function ClubService.CanEnterClub(player: Player, clubName: string, quiet: boolean?): boolean
	local data = PlayerDataService.GetData(player)
	if not data then
		if not quiet then
			print(string.format("[%s] CanEnterClub: no profile yet for %s", GAME_LABEL, player.Name))
		end
		return false
	end

	local club = CLUBS[clubName]
	if not club then
		if not quiet then
			print(string.format("[%s] CanEnterClub: unknown club %q", GAME_LABEL, clubName))
		end
		return false
	end

	local rep = ReputationService.GetReputation(player)
	local tier = ReputationService.GetTier(player)
	local tierRank = TIER_RANK[tier] or 0
	local needRank = TIER_RANK[club.minTier] or 999

	if rep < club.minReputation or tierRank < needRank then
		return false
	end

	return true
end

function ClubService.GetClubInfo(clubName: string): ClubInfo?
	local club = CLUBS[clubName]
	if not club then
		print(string.format("[%s] GetClubInfo: unknown club %q", GAME_LABEL, clubName))
		return nil
	end

	print(string.format("[%s] GetClubInfo: %s", GAME_LABEL, clubName))
	return toClubInfo(club)
end

function ClubService.GetAccessibleClubs(player: Player): { ClubInfo }
	local data = PlayerDataService.GetData(player)
	if not data then
		print(string.format("[%s] GetAccessibleClubs: no profile yet for %s", GAME_LABEL, player.Name))
		return {}
	end

	local list: { ClubInfo } = {}
	for _, id in CLUB_ORDER do
		if ClubService.CanEnterClub(player, id) then
			local def = CLUBS[id]
			table.insert(list, toClubInfo(def))
		end
	end

	print(
		string.format(
			"[%s] GetAccessibleClubs: %s may enter %d venue(s)",
			GAME_LABEL,
			player.Name,
			#list
		)
	)
	return list
end

-- Client/UI line (same as atmosphere print in AttemptEnter); nil if unknown club.
function ClubService.GetWelcomeMessage(clubName: string): string?
	local club = CLUBS[clubName]
	return club and club.atmosphereWelcome or nil
end

-- Motivating denial line for notifications; nil if player may enter or club unknown.
function ClubService.GetDeniedClientMessage(player: Player, clubName: string): string?
	if not PlayerDataService.GetData(player) then
		return "Your profile is still loading. Try again in a moment."
	end

	local club = CLUBS[clubName]
	if not club then
		return nil
	end

	if ClubService.CanEnterClub(player, clubName, true) then
		return nil
	end

	local rep = ReputationService.GetReputation(player)
	local need = effectiveMinReputation(club)
	local shortfall = math.max(0, need - rep)

	return string.format(
		"You need %d more reputation to enter %s. Keep grinding!",
		shortfall,
		club.displayName
	)
end

function ClubService.AttemptEnter(player: Player, clubName: string)
	local data = PlayerDataService.GetData(player)
	if not data then
		print(
			string.format(
				"[%s] AttemptEnter: no profile for %s — cannot enter %q",
				GAME_LABEL,
				player.Name,
				clubName
			)
		)
		return
	end

	local club = CLUBS[clubName]
	if not club then
		print(string.format("[%s] AttemptEnter: unknown club %q for %s", GAME_LABEL, clubName, player.Name))
		return
	end

	if ClubService.CanEnterClub(player, clubName) then
		print(
			string.format(
				"[%s] %s enters %s — %s",
				GAME_LABEL,
				player.Name,
				club.displayName,
				club.atmosphereWelcome
			)
		)
		return
	end

	local rep = ReputationService.GetReputation(player)
	local need = effectiveMinReputation(club)
	local shortfall = math.max(0, need - rep)
	local display = club.displayName

	print(
		string.format(
			"[%s] %s denied at %s — You need %d more reputation to enter %s. Keep grinding!",
			GAME_LABEL,
			player.Name,
			display,
			shortfall,
			display
		)
	)
end

return ClubService
