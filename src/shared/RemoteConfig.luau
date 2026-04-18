--[[
	RemoteConfig — MY CITY
	Client passthrough to ReplicatedStorage.MyCityRemotes (created by server init).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local folder = ReplicatedStorage:WaitForChild("MyCityRemotes", 30)

return {
	UpdatePlayerData = folder:WaitForChild("UpdatePlayerData", 10),
	ShowNotification = folder:WaitForChild("ShowNotification", 10),
	SocialIdentityChanged = folder:WaitForChild("SocialIdentityChanged", 10),
	MissionAvailable = folder:WaitForChild("MissionAvailable", 10),
	MissionCompleted = folder:WaitForChild("MissionCompleted", 10),
	MissionExpired = folder:WaitForChild("MissionExpired", 10),
	OpenWardrobe = folder:WaitForChild("OpenWardrobe", 10),
	OpenClubDrinks = folder:WaitForChild("OpenClubDrinks", 10),
	GetPlayerData = folder:WaitForChild("GetPlayerData", 10),
	GetAvailableJobs = folder:WaitForChild("GetAvailableJobs", 10),
	StartWork = folder:WaitForChild("StartWork", 10),
	StopWork = folder:WaitForChild("StopWork", 10),
	GetMissionProgress = folder:WaitForChild("GetMissionProgress", 10),
	LeaveReview = folder:WaitForChild("LeaveReview", 10),
	GetReviews = folder:WaitForChild("GetReviews", 10),
	SubmitPlayerReview = folder:WaitForChild("SubmitPlayerReview", 10),
	GetPlayerReviewSummary = folder:WaitForChild("GetPlayerReviewSummary", 10),
	GetPlayerSocialTagSnapshot = folder:WaitForChild("GetPlayerSocialTagSnapshot", 10),
	GetReviewCityEligibility = folder:WaitForChild("GetReviewCityEligibility", 10),
	BuyHouse = folder:WaitForChild("BuyHouse", 10),
	GetHouses = folder:WaitForChild("GetHouses", 10),
	GetRanking = folder:WaitForChild("GetRanking", 10),
	GetCities = folder:WaitForChild("GetCities", 10),
	JoinCity = folder:WaitForChild("JoinCity", 10),
	GetElectionData = folder:WaitForChild("GetElectionData", 10),
	Nominate = folder:WaitForChild("Nominate", 10),
	Vote = folder:WaitForChild("Vote", 10),
	GetCurrentMayor = folder:WaitForChild("GetCurrentMayor", 10),
	StartImpeachment = folder:WaitForChild("StartImpeachment", 10),
	VoteImpeachment = folder:WaitForChild("VoteImpeachment", 10),
	ProposeTrade = folder:WaitForChild("ProposeTrade", 10),
	RespondTrade = folder:WaitForChild("RespondTrade", 10),
	GetActiveTrades = folder:WaitForChild("GetActiveTrades", 10),
	EnterHouse = folder:WaitForChild("EnterHouse", 10),
	ExitHouse = folder:WaitForChild("ExitHouse", 10),
	ShopAction = folder:WaitForChild("ShopAction", 10),
	GetInvestments = folder:WaitForChild("GetInvestments", 10),
	GetOwnedOutfits = folder:WaitForChild("GetOwnedOutfits", 10),
	EquipOutfit = folder:WaitForChild("EquipOutfit", 10),
	GetActiveMissions = folder:WaitForChild("GetActiveMissions", 10),
	GetDailyProgress = folder:WaitForChild("GetDailyProgress", 10),
	DebugSpawnMission = folder:WaitForChild("DebugSpawnMission", 10),
	PurchaseClubDrink = folder:WaitForChild("PurchaseClubDrink", 10),
}
