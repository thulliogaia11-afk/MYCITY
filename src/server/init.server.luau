-- MY CITY — Server Entry Point

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Step 1: Create remotes folder and all remotes immediately
local remotes = Instance.new("Folder")
remotes.Name = "MyCityRemotes"
remotes.Parent = ReplicatedStorage

local function makeEvent(name)
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = remotes
	return e
end

local function makeFunction(name)
	local f = Instance.new("RemoteFunction")
	f.Name = name
	f.Parent = remotes
	return f
end

local UpdatePlayerData = makeEvent("UpdatePlayerData")
local ShowNotification = makeEvent("ShowNotification")
local MissionAvailable = makeEvent("MissionAvailable")
local MissionCompleted = makeEvent("MissionCompleted")
local MissionExpired = makeEvent("MissionExpired")
local OpenWardrobe = makeEvent("OpenWardrobe")
local OpenClubDrinks = makeEvent("OpenClubDrinks")
local GetPlayerData = makeFunction("GetPlayerData")
local GetAvailableJobs = makeFunction("GetAvailableJobs")
local StartWork = makeFunction("StartWork")
local StopWork = makeFunction("StopWork")
local GetMissionProgress = makeFunction("GetMissionProgress")
local LeaveReview = makeFunction("LeaveReview")
local GetReviews = makeFunction("GetReviews")
local SubmitPlayerReview = makeFunction("SubmitPlayerReview")
local GetPlayerReviewSummary = makeFunction("GetPlayerReviewSummary")
local GetPlayerSocialTagSnapshot = makeFunction("GetPlayerSocialTagSnapshot")
local GetReviewCityEligibility = makeFunction("GetReviewCityEligibility")
local BuyHouse = makeFunction("BuyHouse")
local GetHouses = makeFunction("GetHouses")
local GetRanking = makeFunction("GetRanking")
local GetCities = makeFunction("GetCities")
local JoinCity = makeFunction("JoinCity")
local GetElectionData = makeFunction("GetElectionData")
local Nominate = makeFunction("Nominate")
local Vote = makeFunction("Vote")
local GetCurrentMayor = makeFunction("GetCurrentMayor")
local StartImpeachment = makeFunction("StartImpeachment")
local VoteImpeachment = makeFunction("VoteImpeachment")
local ProposeTrade = makeFunction("ProposeTrade")
local RespondTrade = makeFunction("RespondTrade")
local GetActiveTrades = makeFunction("GetActiveTrades")
local EnterHouse = makeFunction("EnterHouse")
local ExitHouse = makeFunction("ExitHouse")
local ShopAction = makeFunction("ShopAction")
local GetInvestments = makeFunction("GetInvestments")
local GetOwnedOutfits = makeFunction("GetOwnedOutfits")
local EquipOutfit = makeFunction("EquipOutfit")
local GetActiveMissions = makeFunction("GetActiveMissions")
local GetDailyProgress = makeFunction("GetDailyProgress")
local DebugSpawnMission = makeFunction("DebugSpawnMission")
local PurchaseClubDrink = makeFunction("PurchaseClubDrink")

print("[SERVER] All remotes created")

-- Step 2: Require all services
print("[SERVER] Loading PlayerDataService...")
local PlayerDataService = require(script.services.PlayerDataService)
print("[SERVER] Loading CityService...")
local CityService = require(script.services.CityService)
print("[SERVER] Loading ReputationService...")
local ReputationService = require(script.services.ReputationService)
print("[SERVER] Loading ElectionService...")
local ElectionService = require(script.services.ElectionService)
print("[SERVER] Loading JobService...")
local JobService = require(script.services.JobService)
print("[SERVER] Loading HouseService...")
local HouseService = require(script.services.HouseService)
print("[SERVER] Loading RankingService...")
local RankingService = require(script.services.RankingService)
print("[SERVER] Loading OutfitService...")
local OutfitService = require(script.services.OutfitService)
print("[SERVER] Loading ClubService...")
local ClubService = require(script.services.ClubService)
print("[SERVER] Loading ClubFacadeService...")
local ClubFacadeService = require(script.services.ClubFacadeService)
print("[SERVER] Loading ClubDoorService...")
local ClubDoorService = require(script.services.ClubDoorService)
print("[SERVER] Loading DrinkService...")
local DrinkService = require(script.services.DrinkService)
print("[SERVER] Loading SocialRatingService...")
local SocialRatingService = require(script.services.SocialRatingService)
print("[SERVER] Loading ReviewService...")
local ReviewService = require(script.services.ReviewService)
print("[SERVER] Loading HouseEntryService...")
local HouseEntryService = require(script.services.HouseEntryService)
print("[SERVER] Loading ShopService...")
local ShopService = require(script.services.ShopService)
print("[SERVER] Loading MissionService...")
local MissionService = require(script.services.MissionService)
ClubFacadeService.Start()
DrinkService.Start()
MissionService.Initialize()
print("[SERVER] All services loaded")

-- Step 3: Register remote handlers
GetAvailableJobs.OnServerInvoke = function(player)
	print("[SERVER] GetAvailableJobs by", player.Name)
	local ok, result = pcall(function()
		return JobService.GetAvailableJobs(player)
	end)
	if not ok then
		warn("[SERVER] GetAvailableJobs error:", result)
		return {}
	end
	print("[SERVER] GetAvailableJobs returning", type(result), result and #result or 0)
	return result or {}
end

GetPlayerData.OnServerInvoke = function(player)
	if not PlayerDataService.HasSession(player) then
		return nil
	end
	return PlayerDataService.GetData(player)
end

GetInvestments.OnServerInvoke = function(player)
	return ShopService.GetInvestments(player)
end

GetOwnedOutfits.OnServerInvoke = function(player)
	return ShopService.GetOwnedOutfits(player)
end

EquipOutfit.OnServerInvoke = function(player, outfitName)
	return ShopService.EquipOutfit(player, outfitName)
end

GetRanking.OnServerInvoke = function()
	return RankingService.GetRanking()
end

StartWork.OnServerInvoke = function(player, jobName)
	return JobService.StartWork(player, jobName)
end

StopWork.OnServerInvoke = function(player)
	JobService.StopWork(player)
	return true
end

GetMissionProgress.OnServerInvoke = function(player)
	return JobService.GetMissionProgress(player)
end

LeaveReview.OnServerInvoke = function(player, targetUserId, stars, comment)
	return ReviewService.SubmitReview(player, targetUserId, stars, comment)
end

GetReviews.OnServerInvoke = function(player, targetUserId)
	return ReviewService.GetPlayerReviewSummary(player, targetUserId)
end

SubmitPlayerReview.OnServerInvoke = function(player, targetUserId, rating, comment)
	return ReviewService.SubmitReview(player, targetUserId, rating, comment)
end

GetPlayerReviewSummary.OnServerInvoke = function(player, targetUserId)
	return ReviewService.GetPlayerReviewSummary(player, targetUserId)
end

GetPlayerSocialTagSnapshot.OnServerInvoke = function(player, targetUserId)
	return ReviewService.GetPlayerSocialTagSnapshot(player, targetUserId)
end

GetReviewCityEligibility.OnServerInvoke = function(player, targetUserId)
	return ReviewService.GetReviewEligibility(player, targetUserId)
end

BuyHouse.OnServerInvoke = function(player, level)
	return HouseService.BuyHouse(player, level)
end

GetHouses.OnServerInvoke = function()
	return HouseService.GetHouses()
end

GetCities.OnServerInvoke = function()
	return CityService.GetCities()
end

JoinCity.OnServerInvoke = function(player, cityName)
	return CityService.JoinCity(player, cityName)
end

GetElectionData.OnServerInvoke = function(player)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return nil
	end
	local cityName = data.City
	local snap = ElectionService.GetElectionData(cityName, player)
	if not snap then
		return nil
	end
	local hasVoted = snap.hasVoted == true
	return {
		cityName = snap.cityName,
		phase = snap.phase,
		timeRemaining = snap.timeRemaining,
		mandateEndTime = snap.mandateEndTime,
		currentMayor = snap.currentMayor,
		currentMayorName = snap.currentMayorName,
		candidates = snap.candidates,
		voterCount = snap.voterCount,
		secondsUntilMandateEnds = snap.secondsUntilMandateEnds,
		hasVoted = hasVoted,
		hasPlayerVoted = hasVoted,
		secondsUntilCurrentPhaseEnds = ElectionService.SecondsUntilCurrentPhaseEnd(cityName),
		impeachment = snap.impeachment,
		activeTrades = snap.activeTrades,
		pendingOutgoing = snap.pendingOutgoing,
		pendingIncoming = snap.pendingIncoming,
	}
end

GetCurrentMayor.OnServerInvoke = function(player)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return nil
	end
	return ElectionService.GetCurrentMayor(data.City)
end

Nominate.OnServerInvoke = function(player, campaignMessage)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return false, "Join a city first."
	end
	local msg = typeof(campaignMessage) == "string" and campaignMessage or ""
	return ElectionService.Nominate(player, data.City, msg)
end

Vote.OnServerInvoke = function(player, candidateUserId)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return false, "Join a city first."
	end
	if typeof(candidateUserId) ~= "number" then
		return false, "Invalid candidate."
	end
	return ElectionService.Vote(player, data.City, candidateUserId)
end

StartImpeachment.OnServerInvoke = function(player)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return false, "Join a city first."
	end
	return ElectionService.StartImpeachment(player, data.City)
end

VoteImpeachment.OnServerInvoke = function(player, voteYes: boolean)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return false, "Join a city first."
	end
	if typeof(voteYes) ~= "boolean" then
		return false, "Invalid vote."
	end
	return ElectionService.VoteImpeachment(player, data.City, voteYes)
end

ProposeTrade.OnServerInvoke = function(player, targetCityName: string, dealType: string)
	if typeof(targetCityName) ~= "string" or typeof(dealType) ~= "string" then
		return false, "Invalid request.", nil
	end
	return ElectionService.ProposeTrade(player, targetCityName, dealType)
end

RespondTrade.OnServerInvoke = function(player, dealId: string, accept: boolean)
	if typeof(dealId) ~= "string" then
		return false, "Invalid deal."
	end
	if typeof(accept) ~= "boolean" then
		return false, "Invalid response."
	end
	return ElectionService.RespondTrade(player, dealId, accept)
end

GetActiveTrades.OnServerInvoke = function(player)
	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return {}
	end
	return ElectionService.GetActiveTrades(data.City)
end

EnterHouse.OnServerInvoke = function(player)
	return HouseEntryService.EnterHouse(player)
end

ExitHouse.OnServerInvoke = function(player)
	return HouseEntryService.ExitHouse(player)
end

ShopAction.OnServerInvoke = function(player, shopName, action, ...)
	print("[SERVER] ShopAction:", player.Name, shopName, action)
	if shopName == "Bank" then
		if action == "Deposit" then
			return ShopService.DepositMoney(player, ...)
		end
		if action == "Withdraw" then
			return ShopService.WithdrawMoney(player, ...)
		end
		if action == "GetBalance" then
			return ShopService.GetBankBalance(player)
		end
		if action == "Invest" then
			return ShopService.Invest(player, ...)
		end
	elseif shopName == "Restaurant" then
		if action == "Buy" then
			return ShopService.BuyMeal(player, ...)
		end
	elseif shopName == "Clothing" then
		if action == "Buy" then
			return ShopService.BuyOutfit(player, ...)
		end
		if action == "Equip" then
			return ShopService.EquipOutfit(player, ...)
		end
		if action == "BuyAccessory" then
			return ShopService.BuyAccessory(player, ...)
		end
	elseif shopName == "Barbershop" then
		if action == "Buy" then
			return ShopService.BuyHairStyle(player, ...)
		end
	elseif shopName == "Electronics" then
		if action == "Buy" then
			return ShopService.BuyElectronics(player, ...)
		end
	elseif shopName == "Grocery" then
		if action == "Buy" then
			return ShopService.BuyFood(player, ...)
		end
	elseif shopName == "Pharmacy" then
		if action == "Buy" then
			return ShopService.BuyMedicine(player)
		end
	end
	return { success = false, message = "Unknown shop action" }
end

GetActiveMissions.OnServerInvoke = function(player)
	return MissionService.GetActiveMissions(player)
end

GetDailyProgress.OnServerInvoke = function(player)
	return MissionService.GetDailyProgress(player)
end

PurchaseClubDrink.OnServerInvoke = function(player, clubName, drinkId)
	return DrinkService.PurchaseDrink(player, clubName, drinkId)
end

-- Temporary admin debug: remove when no longer needed.
DebugSpawnMission.OnServerInvoke = function(player, jobName)
	if player.UserId ~= 9849956140 then
		return { success = false }
	end
	local id = MissionService.SpawnMission(jobName or "Firefighter")
	return { success = true, missionId = id }
end

print("[SERVER] All handlers registered")
