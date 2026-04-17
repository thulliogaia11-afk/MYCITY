--[[
	Review test harness: name-based target + always-visible panel. Not for live gameplay.
	Set DEBUG_REVIEW_TEST_UI to true in Studio when you need this tool.
]]
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local DEBUG_REVIEW_TEST_UI = false

if not RunService:IsStudio() or not DEBUG_REVIEW_TEST_UI then
	return
end

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig"))

local existingGui = PlayerGui:FindFirstChild("ReviewTestHUD")
if existingGui and existingGui:IsA("ScreenGui") then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReviewTestHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local function log(message: string)
	print(string.format("[CLIENT][ReviewTest] %s", message))
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(320, 280)
panel.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
panel.BorderSizePixel = 0
panel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Parent = panel

local function makeLabel(text: string, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.Parent = panel
	return label
end

local function makeBox(placeholder: string, height: number): TextBox
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, height)
	box.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderColor3 = Color3.fromRGB(170, 170, 170)
	box.PlaceholderText = placeholder
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.TextSize = 14
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.TextWrapped = true
	box.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = box
	return box
end

local function makeButton(text: string): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 32)
	button.BackgroundColor3 = Color3.fromRGB(74, 124, 255)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = button
	return button
end

makeLabel("Review Test (Studio only)", 24)
local targetBox = makeBox("Target player name", 32)
local ratingBox = makeBox("Rating 1-5", 32)
local commentBox = makeBox("Optional comment", 70)
local submitButton = makeButton("Submit Review")
local fetchButton = makeButton("Fetch Summary")
local outputLabel = makeLabel("No review activity yet.", 70)

local function findTargetUserIdByName(inputName: string): number?
	local trimmed = inputName:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			if string.lower(player.Name) == string.lower(trimmed) or string.lower(player.DisplayName) == string.lower(trimmed) then
				return player.UserId
			end
		end
	end
	return nil
end

local function renderSummary(summary)
	if typeof(summary) ~= "table" then
		outputLabel.Text = "Invalid summary response."
		return
	end
	if summary.success ~= true then
		outputLabel.Text = tostring(summary.message or "Summary failed.")
		return
	end

	local latest = ""
	if typeof(summary.reviews) == "table" and #summary.reviews > 0 then
		local first = summary.reviews[1]
		if typeof(first) == "table" then
			latest = string.format(
				"Latest: %s rated %s%s",
				tostring(first.reviewerName or "Unknown"),
				tostring(first.rating or "?"),
				(first.comment and first.comment ~= "") and (" - " .. tostring(first.comment)) or ""
			)
		end
	end

	outputLabel.Text = string.format(
		"Average: %.1f | Total: %d\n%s",
		tonumber(summary.averageRating or 0) or 0,
		tonumber(summary.totalReviews or 0) or 0,
		latest ~= "" and latest or "No reviews yet."
	)
end

submitButton.MouseButton1Click:Connect(function()
	local targetUserId = findTargetUserIdByName(targetBox.Text)
	local rating = tonumber(ratingBox.Text)
	if not targetUserId then
		outputLabel.Text = "Target player not found."
		log("test submit rejected: target player not found")
		return
	end

	local ok, result = pcall(function()
		return Remotes.SubmitPlayerReview:InvokeServer(targetUserId, rating, commentBox.Text)
	end)
	if not ok then
		outputLabel.Text = "Submit failed."
		log(string.format("test submit rejected: invoke error %s", tostring(result)))
		return
	end

	if typeof(result) == "table" and result.success == true then
		outputLabel.Text = string.format(
			"%s Avg %.1f Total %d",
			tostring(result.message or "Review submitted."),
			tonumber(result.averageRating or 0) or 0,
			tonumber(result.totalReviews or 0) or 0
		)
		log(string.format("test submit succeeded: avg=%.1f total=%d", tonumber(result.averageRating or 0) or 0, tonumber(result.totalReviews or 0) or 0))
	else
		outputLabel.Text = typeof(result) == "table" and tostring(result.message or "Review rejected.") or "Review rejected."
		log(string.format("test submit rejected: %s", typeof(result) == "table" and tostring(result.message or "unknown") or "invalid response"))
	end
end)

fetchButton.MouseButton1Click:Connect(function()
	local targetUserId = findTargetUserIdByName(targetBox.Text)
	if not targetUserId then
		outputLabel.Text = "Target player not found."
		log("review summary fetched: target player not found")
		return
	end

	local ok, result = pcall(function()
		return Remotes.GetPlayerReviewSummary:InvokeServer(targetUserId)
	end)
	if not ok then
		outputLabel.Text = "Summary fetch failed."
		log(string.format("review summary fetched: invoke error %s", tostring(result)))
		return
	end

	renderSummary(result)
	if typeof(result) == "table" and result.success == true then
		log(string.format("review summary fetched: avg=%.1f total=%d", tonumber(result.averageRating or 0) or 0, tonumber(result.totalReviews or 0) or 0))
	else
		log(string.format("review summary fetched: rejected %s", typeof(result) == "table" and tostring(result.message or "unknown") or "invalid response"))
	end
end)
