--[[
	ReviewService - MY CITY
	Server-authoritative player reviews foundation backed by PlayerDataService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GAME_LABEL = "MY CITY"
local MAX_COMMENT_LENGTH = 160
local REVIEW_COOLDOWN_SECONDS = 30
local MAX_STORED_REVIEWS = 100

-- Recent interaction: must dwell near each other (same city) before reviews unlock both ways.
local MAX_INTERACTION_DISTANCE_STUDS = 18
local MIN_INTERACTION_SECONDS = 8
local REVIEW_ELIGIBILITY_WINDOW_SECONDS = 600

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local SocialRatingService = require(script.Parent:WaitForChild("SocialRatingService") :: ModuleScript)

-- pairKey -> consecutive seconds in range (reset when out of range).
local proximityPairDwellSec: { [string]: number } = {}
-- reviewerUserId -> targetUserId -> expiry unix time for review permission.
local reviewEligibleUntil: { [number]: { [number]: number } } = {}

type ReviewEntry = {
	reviewerUserId: number,
	reviewerName: string,
	rating: number,
	comment: string,
	createdAt: number,
}

type ReviewSummary = {
	success: boolean,
	averageRating: number,
	totalReviews: number,
	reviews: { ReviewEntry },
	message: string?,
	socialTier: string?,
	socialScore: number?,
}

local reviewCooldownByUserId: { [number]: number } = {}

local ReviewService = {}

type ReviewEligibilityResult = {
	eligible: boolean,
	reason: ("city" | "interaction" | "unavailable")?,
}

local PROXIMITY_TICK_SEC = 0.5

local function pairKeySorted(uidA: number, uidB: number): string
	if uidA < uidB then
		return tostring(uidA) .. "_" .. tostring(uidB)
	end
	return tostring(uidB) .. "_" .. tostring(uidA)
end

local function getHumanoidRoot(player: Player): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local r = char:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	if char.PrimaryPart and char.PrimaryPart:IsA("BasePart") then
		return char.PrimaryPart
	end
	return nil
end

local function pruneExpiredInteractionGrants(now: number)
	for reviewerUid, targets in pairs(reviewEligibleUntil) do
		for targetUid, exp in pairs(targets) do
			if now > exp then
				targets[targetUid] = nil
			end
		end
		if next(targets) == nil then
			reviewEligibleUntil[reviewerUid] = nil
		end
	end
end

local function clearInteractionStateForUser(userId: number)
	local sud = tostring(userId)
	for k in pairs(proximityPairDwellSec) do
		if string.match(k, "^" .. sud .. "_") ~= nil or string.match(k, "_" .. sud .. "$") ~= nil then
			proximityPairDwellSec[k] = nil
		end
	end
	reviewEligibleUntil[userId] = nil
	for _, targets in pairs(reviewEligibleUntil) do
		targets[userId] = nil
	end
end

local function hasRecentInteractionGrant(reviewerUserId: number, targetUserId: number): boolean
	local now = os.time()
	local byTarget = reviewEligibleUntil[reviewerUserId]
	if not byTarget then
		return false
	end
	local exp = byTarget[targetUserId]
	if typeof(exp) ~= "number" or now > exp then
		if typeof(exp) == "number" and now > exp then
			byTarget[targetUserId] = nil
			if next(byTarget) == nil then
				reviewEligibleUntil[reviewerUserId] = nil
			end
		end
		return false
	end
	return true
end

local function log(message: string)
	print(string.format("[%s] ReviewService: %s", GAME_LABEL, message))
end

local function getShowNotification(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
	if not folder then
		return nil
	end
	local remote = folder:FindFirstChild("ShowNotification")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function notify(player: Player, message: string, level: string)
	local remote = getShowNotification()
	if remote then
		remote:FireClient(player, message, level)
	end
end

local function trimComment(raw: any): string
	if typeof(raw) ~= "string" then
		return ""
	end
	local sanitized = raw:gsub("[%c]", " ")
	sanitized = sanitized:gsub("^%s+", ""):gsub("%s+$", "")
	if #sanitized > MAX_COMMENT_LENGTH then
		sanitized = string.sub(sanitized, 1, MAX_COMMENT_LENGTH)
	end
	return sanitized
end

local function normalizeStoredReview(raw: any): ReviewEntry?
	if typeof(raw) ~= "table" then
		return nil
	end

	local source = raw :: { [string]: any }
	local reviewerUserId = source.reviewerUserId
	local reviewerName = source.reviewerName
	local rating = source.rating
	local comment = source.comment
	local createdAt = source.createdAt

	if typeof(rating) ~= "number" and typeof(source.stars) == "number" then
		rating = source.stars
	end
	if typeof(createdAt) ~= "number" and typeof(source.timestamp) == "number" then
		createdAt = source.timestamp
	end

	if typeof(reviewerUserId) ~= "number" or reviewerUserId <= 0 then
		return nil
	end
	if typeof(reviewerName) ~= "string" then
		reviewerName = "Unknown"
	end
	if typeof(rating) ~= "number" then
		return nil
	end
	rating = math.clamp(math.floor(rating + 0.5), 1, 5)
	if typeof(comment) ~= "string" then
		comment = ""
	end
	if typeof(createdAt) ~= "number" or createdAt <= 0 then
		createdAt = os.time()
	end

	return {
		reviewerUserId = reviewerUserId,
		reviewerName = reviewerName,
		rating = rating,
		comment = trimComment(comment),
		createdAt = createdAt,
	}
end

local function collectNormalizedReviews(rawReviews: any): { ReviewEntry }
	local byReviewer: { [number]: ReviewEntry } = {}
	if typeof(rawReviews) == "table" then
		for _, raw in ipairs(rawReviews :: { any }) do
			local entry = normalizeStoredReview(raw)
			if entry then
				local existing = byReviewer[entry.reviewerUserId]
				if not existing or entry.createdAt >= existing.createdAt then
					byReviewer[entry.reviewerUserId] = entry
				end
			end
		end
	end

	local normalized: { ReviewEntry } = {}
	for _, entry in byReviewer do
		table.insert(normalized, entry)
	end

	table.sort(normalized, function(a, b)
		return a.createdAt > b.createdAt
	end)

	while #normalized > MAX_STORED_REVIEWS do
		table.remove(normalized)
	end

	return normalized
end

local function roundAverage(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

local function recalculateAggregates(reviews: { ReviewEntry }): (number, number)
	if #reviews == 0 then
		return 0, 0
	end

	local total = 0
	for _, review in ipairs(reviews) do
		total += review.rating
	end
	return roundAverage(total / #reviews), #reviews
end

local function getTargetPlayer(targetUserId: number): Player?
	if typeof(targetUserId) ~= "number" or targetUserId <= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(targetUserId)
end

local function getCityNameFromData(data: any): string
	if typeof(data) ~= "table" then
		return "None"
	end
	local c = (data :: { [string]: any }).City
	if typeof(c) ~= "string" or c == "" then
		return "None"
	end
	return c
end

local function reviewerSharesEligibleCity(reviewer: Player, target: Player): boolean
	if not PlayerDataService.HasSession(reviewer) or not PlayerDataService.HasSession(target) then
		return false
	end
	local ca = getCityNameFromData(PlayerDataService.GetData(reviewer))
	local cb = getCityNameFromData(PlayerDataService.GetData(target))
	if ca == "None" or cb == "None" then
		return false
	end
	return ca == cb
end

local function stepProximityInteractionLoop()
	task.spawn(function()
		while true do
			task.wait(PROXIMITY_TICK_SEC)
			local now = os.time()
			pruneExpiredInteractionGrants(now)

			local plist = Players:GetPlayers()
			for i = 1, #plist do
				for j = i + 1, #plist do
					local pa, pb = plist[i], plist[j]
					local key = pairKeySorted(pa.UserId, pb.UserId)

					if not reviewerSharesEligibleCity(pa, pb) then
						proximityPairDwellSec[key] = 0
						continue
					end

					local ra = getHumanoidRoot(pa)
					local rb = getHumanoidRoot(pb)
					if
						ra
						and rb
						and (ra.Position - rb.Position).Magnitude <= MAX_INTERACTION_DISTANCE_STUDS
					then
						local prev = proximityPairDwellSec[key] or 0
						local dwell = prev + PROXIMITY_TICK_SEC
						proximityPairDwellSec[key] = dwell
						if dwell >= MIN_INTERACTION_SECONDS then
							local untilT = now + REVIEW_ELIGIBILITY_WINDOW_SECONDS
							if not reviewEligibleUntil[pa.UserId] then
								reviewEligibleUntil[pa.UserId] = {}
							end
							if not reviewEligibleUntil[pb.UserId] then
								reviewEligibleUntil[pb.UserId] = {}
							end
							reviewEligibleUntil[pa.UserId][pb.UserId] = untilT
							reviewEligibleUntil[pb.UserId][pa.UserId] = untilT
							proximityPairDwellSec[key] = 0
							log(string.format("interaction grant %s <-> %s (until t=%d)", pa.Name, pb.Name, untilT))
						end
					else
						proximityPairDwellSec[key] = 0
					end
				end
			end
		end
	end)
end

stepProximityInteractionLoop()

function ReviewService.GetReviewEligibility(reviewer: Player, targetUserId: number): ReviewEligibilityResult
	local target = getTargetPlayer(targetUserId)
	if not target then
		return { eligible = false, reason = "unavailable" }
	end
	if not reviewerSharesEligibleCity(reviewer, target) then
		return { eligible = false, reason = "city" }
	end
	if not hasRecentInteractionGrant(reviewer.UserId, targetUserId) then
		return { eligible = false, reason = "interaction" }
	end
	return { eligible = true }
end

function ReviewService.CanReviewTargetForCity(reviewer: Player, targetUserId: number): boolean
	return ReviewService.GetReviewEligibility(reviewer, targetUserId).eligible
end

function ReviewService.SubmitReview(reviewerPlayer: Player, targetUserId: number, rating: number, comment: any)
	if not PlayerDataService.HasSession(reviewerPlayer) then
		log(string.format("review rejected: %s has no session", reviewerPlayer.Name))
		return { success = false, message = "Your data is not ready yet." }
	end

	if typeof(targetUserId) ~= "number" or targetUserId <= 0 then
		log(string.format("review rejected: %s invalid target %s", reviewerPlayer.Name, tostring(targetUserId)))
		return { success = false, message = "Invalid review target." }
	end

	if targetUserId == reviewerPlayer.UserId then
		log(string.format("review rejected: %s attempted self-review", reviewerPlayer.Name))
		return { success = false, message = "You cannot review yourself." }
	end

	if typeof(rating) ~= "number" or rating % 1 ~= 0 or rating < 1 or rating > 5 then
		log(string.format("review rejected: %s invalid rating %s", reviewerPlayer.Name, tostring(rating)))
		return { success = false, message = "Rating must be an integer from 1 to 5." }
	end

	local nowTs = os.time()
	local lastSubmittedAt = reviewCooldownByUserId[reviewerPlayer.UserId] or 0
	if nowTs - lastSubmittedAt < REVIEW_COOLDOWN_SECONDS then
		local waitSeconds = REVIEW_COOLDOWN_SECONDS - (nowTs - lastSubmittedAt)
		log(string.format("review rejected: %s cooldown %ds", reviewerPlayer.Name, waitSeconds))
		return { success = false, message = string.format("Please wait %d seconds before reviewing again.", waitSeconds) }
	end

	local targetPlayer = getTargetPlayer(targetUserId)
	if not targetPlayer or not PlayerDataService.HasSession(targetPlayer) then
		log(string.format("review rejected: %s target offline/unavailable %d", reviewerPlayer.Name, targetUserId))
		return { success = false, message = "Target player is not available." }
	end

	if not reviewerSharesEligibleCity(reviewerPlayer, targetPlayer) then
		log(string.format("review rejected: %s not same city as target %s", reviewerPlayer.Name, targetPlayer.Name))
		return { success = false, message = "You can only review players in your city." }
	end

	if not hasRecentInteractionGrant(reviewerPlayer.UserId, targetUserId) then
		log(string.format("review rejected: %s no recent interaction with %s", reviewerPlayer.Name, targetPlayer.Name))
		return { success = false, message = "You can only review players you've recently interacted with." }
	end

	local cleanComment = trimComment(comment)
	local targetData = PlayerDataService.GetData(targetPlayer)
	local reviews = collectNormalizedReviews(targetData.Reviews)
	local existingIndex: number? = nil

	for index, review in ipairs(reviews) do
		if review.reviewerUserId == reviewerPlayer.UserId then
			existingIndex = index
			break
		end
	end

	local nextEntry: ReviewEntry = {
		reviewerUserId = reviewerPlayer.UserId,
		reviewerName = reviewerPlayer.DisplayName ~= "" and reviewerPlayer.DisplayName or reviewerPlayer.Name,
		rating = rating,
		comment = cleanComment,
		createdAt = nowTs,
	}

	local actionLabel = "accepted"
	if existingIndex then
		reviews[existingIndex] = nextEntry
		actionLabel = "updated"
	else
		table.insert(reviews, nextEntry)
	end

	table.sort(reviews, function(a, b)
		return a.createdAt > b.createdAt
	end)
	while #reviews > MAX_STORED_REVIEWS do
		table.remove(reviews)
	end

	local averageRating, totalReviews = recalculateAggregates(reviews)
	if not PlayerDataService.SetDataBatch(targetPlayer, {
		Reviews = reviews,
		AverageRating = averageRating,
		TotalReviews = totalReviews,
	}) then
		log(string.format("review rejected: failed to save review batch reviewer=%s target=%s", reviewerPlayer.Name, targetPlayer.Name))
		return { success = false, message = "Could not save review." }
	end

	reviewCooldownByUserId[reviewerPlayer.UserId] = nowTs
	log(string.format(
		"aggregate recalculated target=%s average=%.1f total=%d",
		targetPlayer.Name,
		averageRating,
		totalReviews
	))
	log(string.format(
		"review %s reviewer=%s target=%s rating=%d",
		actionLabel,
		reviewerPlayer.Name,
		targetPlayer.Name,
		rating
	))

	notify(reviewerPlayer, if actionLabel == "updated" then "Review updated." else "Review submitted.", "success")
	return {
		success = true,
		message = if actionLabel == "updated" then "Review updated." else "Review submitted.",
		averageRating = averageRating,
		totalReviews = totalReviews,
		updated = existingIndex ~= nil,
	}
end

function ReviewService.GetPlayerReviewSummary(_requestingPlayer: Player, targetUserId: number): ReviewSummary
	local targetPlayer = getTargetPlayer(targetUserId)
	if not targetPlayer or not PlayerDataService.HasSession(targetPlayer) then
		return {
			success = false,
			averageRating = 0,
			totalReviews = 0,
			reviews = {},
			message = "Target player is not available.",
		}
	end

	local targetData = PlayerDataService.GetData(targetPlayer)
	local reviews = collectNormalizedReviews(targetData.Reviews)
	local averageRating, totalReviews = recalculateAggregates(reviews)
	local socialScore = typeof(targetData.SocialScore) == "number" and targetData.SocialScore or 0
	local socialTier = SocialRatingService.GetTierForScore(socialScore)
	log(string.format(
		"review summary fetched target=%s average=%.1f total=%d social=%d tier=%s",
		targetPlayer.Name,
		averageRating,
		totalReviews,
		socialScore,
		socialTier
	))
	return {
		success = true,
		averageRating = averageRating,
		totalReviews = totalReviews,
		reviews = reviews,
		socialTier = socialTier,
		socialScore = socialScore,
	}
end

Players.PlayerRemoving:Connect(function(player: Player)
	reviewCooldownByUserId[player.UserId] = nil
	clearInteractionStateForUser(player.UserId)
end)

return ReviewService
