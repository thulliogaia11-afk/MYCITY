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

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)

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
}

local reviewCooldownByUserId: { [number]: number } = {}

local ReviewService = {}

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

function ReviewService.CanReviewTargetForCity(reviewer: Player, targetUserId: number): boolean
	local target = getTargetPlayer(targetUserId)
	if not target then
		return false
	end
	return reviewerSharesEligibleCity(reviewer, target)
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
	log(string.format("review summary fetched target=%s average=%.1f total=%d", targetPlayer.Name, averageRating, totalReviews))
	return {
		success = true,
		averageRating = averageRating,
		totalReviews = totalReviews,
		reviews = reviews,
	}
end

Players.PlayerRemoving:Connect(function(player: Player)
	reviewCooldownByUserId[player.UserId] = nil
end)

return ReviewService
