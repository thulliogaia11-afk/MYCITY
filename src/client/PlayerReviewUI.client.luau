--[[
	PlayerReviewUI — opens only when clicking/tapping another player's character.
	Target is locked via selectedTargetUserId for all remote calls until close or switch.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig"))

local LOG_PREFIX = "[CLIENT][PlayerReview]"

local function log(fmt: string, ...: any)
	print(string.format(LOG_PREFIX .. " " .. fmt, ...))
end

-- ——— Theme ———
local NAVY = Color3.fromHex("16213e")
local ACCENT = Color3.fromHex("e94560")
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_MUTED = Color3.fromRGB(160, 165, 185)
local SUCCESS = Color3.fromRGB(60, 180, 110)
local DANGER = Color3.fromRGB(220, 70, 80)
local CORNER = UDim.new(0, 8)

-- ——— Locked selection (never infer target from text input) ———
local selectedTargetPlayer: Player? = nil
local selectedTargetUserId: number? = nil
local selectedRating: number? = nil

local summaryFetchToken = 0

-- ——— UI (single build) ———
local existing = PlayerGui:FindFirstChild("PlayerReviewUI")
if existing and existing:IsA("ScreenGui") then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerReviewUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 40
screenGui.IgnoreGuiInset = false
screenGui.Enabled = true
screenGui.Parent = PlayerGui

local root = Instance.new("Frame")
root.Name = "Panel"
root.AnchorPoint = Vector2.new(1, 1)
root.Position = UDim2.new(1, -20, 1, -88)
root.Size = UDim2.fromOffset(320, 418)
root.BackgroundColor3 = NAVY
root.BorderSizePixel = 0
root.Visible = false
root.Active = false
root.Parent = screenGui

local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = CORNER
rootCorner.Parent = root

local rootStroke = Instance.new("UIStroke")
rootStroke.Color = ACCENT
rootStroke.Thickness = 1
rootStroke.Transparency = 0.5
rootStroke.Parent = root

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = root

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = root

local titleRow = Instance.new("Frame")
titleRow.BackgroundTransparency = 1
titleRow.Size = UDim2.new(1, 0, 0, 26)
titleRow.LayoutOrder = 1
titleRow.Parent = root

local titleLbl = Instance.new("TextLabel")
titleLbl.BackgroundTransparency = 1
titleLbl.Size = UDim2.new(1, -36, 1, 0)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 17
titleLbl.TextColor3 = TEXT_WHITE
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "Rate player"
titleLbl.Parent = titleRow

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, 0, 0, 0)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.BackgroundColor3 = ACCENT
closeBtn.TextColor3 = TEXT_WHITE
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleRow
local closeC = Instance.new("UICorner")
closeC.CornerRadius = UDim.new(0, 6)
closeC.Parent = closeBtn

local targetDisplayLbl = Instance.new("TextLabel")
targetDisplayLbl.BackgroundTransparency = 1
targetDisplayLbl.Size = UDim2.new(1, 0, 0, 20)
targetDisplayLbl.LayoutOrder = 2
targetDisplayLbl.Font = Enum.Font.GothamBold
targetDisplayLbl.TextSize = 15
targetDisplayLbl.TextColor3 = TEXT_WHITE
targetDisplayLbl.TextXAlignment = Enum.TextXAlignment.Left
targetDisplayLbl.Text = ""
targetDisplayLbl.Parent = root

local targetUserLbl = Instance.new("TextLabel")
targetUserLbl.BackgroundTransparency = 1
targetUserLbl.Size = UDim2.new(1, 0, 0, 16)
targetUserLbl.LayoutOrder = 3
targetUserLbl.Font = Enum.Font.Gotham
targetUserLbl.TextSize = 12
targetUserLbl.TextColor3 = TEXT_MUTED
targetUserLbl.TextXAlignment = Enum.TextXAlignment.Left
targetUserLbl.Text = ""
targetUserLbl.Parent = root

local summaryLbl = Instance.new("TextLabel")
summaryLbl.BackgroundTransparency = 1
summaryLbl.Size = UDim2.new(1, 0, 0, 56)
summaryLbl.LayoutOrder = 4
summaryLbl.Font = Enum.Font.Gotham
summaryLbl.TextSize = 13
summaryLbl.TextColor3 = TEXT_MUTED
summaryLbl.TextXAlignment = Enum.TextXAlignment.Left
summaryLbl.TextYAlignment = Enum.TextYAlignment.Top
summaryLbl.TextWrapped = true
summaryLbl.Text = ""
summaryLbl.Parent = root

local ratingSectionTitle = Instance.new("TextLabel")
ratingSectionTitle.BackgroundTransparency = 1
ratingSectionTitle.Size = UDim2.new(1, 0, 0, 16)
ratingSectionTitle.LayoutOrder = 5
ratingSectionTitle.Font = Enum.Font.GothamBold
ratingSectionTitle.TextSize = 12
ratingSectionTitle.TextColor3 = TEXT_WHITE
ratingSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
ratingSectionTitle.Text = "Rating (required)"
ratingSectionTitle.Parent = root

local ratingRow = Instance.new("Frame")
ratingRow.BackgroundTransparency = 1
ratingRow.Size = UDim2.new(1, 0, 0, 36)
ratingRow.LayoutOrder = 6
ratingRow.Parent = root

local ratingLayout = Instance.new("UIListLayout")
ratingLayout.FillDirection = Enum.FillDirection.Horizontal
ratingLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
ratingLayout.Padding = UDim.new(0, 6)
ratingLayout.Parent = ratingRow

local ratingButtons: { TextButton } = {}
local defaultRatingBg = Color3.fromRGB(40, 44, 62)
for i = 1, 5 do
	local b = Instance.new("TextButton")
	b.Name = "Rate" .. i
	b.Size = UDim2.new(0, 46, 0, 34)
	b.BackgroundColor3 = defaultRatingBg
	b.TextColor3 = TEXT_WHITE
	b.Text = tostring(i)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.AutoButtonColor = false
	b.Parent = ratingRow
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = b
	table.insert(ratingButtons, b)
end

local ratingHintLbl = Instance.new("TextLabel")
ratingHintLbl.BackgroundTransparency = 1
ratingHintLbl.Size = UDim2.new(1, 0, 0, 14)
ratingHintLbl.LayoutOrder = 7
ratingHintLbl.Font = Enum.Font.Gotham
ratingHintLbl.TextSize = 11
ratingHintLbl.TextColor3 = TEXT_MUTED
ratingHintLbl.TextXAlignment = Enum.TextXAlignment.Left
ratingHintLbl.Text = "Tap a number (1 = low, 5 = high)"
ratingHintLbl.Parent = root

local commentTitle = Instance.new("TextLabel")
commentTitle.BackgroundTransparency = 1
commentTitle.Size = UDim2.new(1, 0, 0, 16)
commentTitle.LayoutOrder = 8
commentTitle.Font = Enum.Font.GothamBold
commentTitle.TextSize = 12
commentTitle.TextColor3 = TEXT_WHITE
commentTitle.TextXAlignment = Enum.TextXAlignment.Left
commentTitle.Text = "Comment (optional)"
commentTitle.Parent = root

local commentBox = Instance.new("TextBox")
commentBox.Size = UDim2.new(1, 0, 0, 64)
commentBox.LayoutOrder = 9
commentBox.BackgroundColor3 = Color3.fromRGB(22, 28, 45)
commentBox.TextColor3 = TEXT_WHITE
commentBox.PlaceholderColor3 = TEXT_MUTED
commentBox.PlaceholderText = "Optional (max 160 chars)"
commentBox.ClearTextOnFocus = false
commentBox.Text = ""
commentBox.TextSize = 13
commentBox.Font = Enum.Font.Gotham
commentBox.TextXAlignment = Enum.TextXAlignment.Left
commentBox.TextYAlignment = Enum.TextYAlignment.Top
commentBox.TextWrapped = true
commentBox.MultiLine = true
commentBox.Parent = root
local cbC = Instance.new("UICorner")
cbC.CornerRadius = UDim.new(0, 6)
cbC.Parent = commentBox
local cbPad = Instance.new("UIPadding")
cbPad.PaddingLeft = UDim.new(0, 8)
cbPad.PaddingRight = UDim.new(0, 8)
cbPad.PaddingTop = UDim.new(0, 6)
cbPad.PaddingBottom = UDim.new(0, 6)
cbPad.Parent = commentBox

local statusLbl = Instance.new("TextLabel")
statusLbl.BackgroundTransparency = 1
statusLbl.Size = UDim2.new(1, 0, 0, 32)
statusLbl.LayoutOrder = 10
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextColor3 = TEXT_MUTED
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextYAlignment = Enum.TextYAlignment.Top
statusLbl.TextWrapped = true
statusLbl.Text = ""
statusLbl.Visible = false
statusLbl.Parent = root

local submitBtn = Instance.new("TextButton")
submitBtn.Size = UDim2.new(1, 0, 0, 36)
submitBtn.LayoutOrder = 11
submitBtn.BackgroundColor3 = SUCCESS
submitBtn.TextColor3 = TEXT_WHITE
submitBtn.Font = Enum.Font.GothamBold
submitBtn.TextSize = 14
submitBtn.Text = "Submit review"
submitBtn.AutoButtonColor = false
submitBtn.Active = false
submitBtn.Parent = root
local sbc = Instance.new("UICorner")
sbc.CornerRadius = CORNER
sbc.Parent = submitBtn

local function targetLogName(player: Player?, userId: number?): string
	if player and player.Parent then
		return player.Name
	end
	if userId then
		return "#" .. tostring(userId)
	end
	return "?"
end

local function updateRatingButtonsVisual()
	for i, b in ratingButtons do
		b.BackgroundColor3 = (selectedRating == i) and ACCENT or defaultRatingBg
	end
	local canSubmit = selectedRating ~= nil
	submitBtn.Active = canSubmit
	submitBtn.BackgroundColor3 = canSubmit and SUCCESS or Color3.fromRGB(48, 56, 52)
	ratingHintLbl.Text = if selectedRating
		then string.format("Selected: %d / 5 stars", selectedRating)
		else "Tap a number (1 = low, 5 = high)"
end

local function clearFeedback()
	statusLbl.Visible = false
	statusLbl.Text = ""
end

local function showFeedback(text: string, isError: boolean?)
	statusLbl.Visible = true
	statusLbl.TextColor3 = if isError then DANGER else TEXT_MUTED
	statusLbl.Text = text
end

local function getCharacterModelFromPart(inst: Instance?): Model?
	local current: Instance? = inst
	while current do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isScreenPointOverScreenGui(screenPos: Vector2): boolean
	return #GuiService:GetGuiObjectsAtPosition(screenPos.X, screenPos.Y) > 0
end

-- Resolve another Player from a world click, or nil (self, NPC, empty sky, HUD click).
local function resolveOtherPlayerFromScreenPoint(screenPos: Vector2): Player?
	if isScreenPointOverScreenGui(screenPos) then
		return nil
	end

	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end

	local ray = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if LocalPlayer.Character then
		table.insert(exclude, LocalPlayer.Character)
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 800, params)
	if not result then
		return nil
	end

	local char = getCharacterModelFromPart(result.Instance)
	if not char then
		return nil
	end

	local plr = Players:GetPlayerFromCharacter(char)
	if not plr or plr == LocalPlayer then
		return nil
	end

	return plr
end

local function renderSummary(summary: any)
	if typeof(summary) ~= "table" then
		summaryLbl.TextColor3 = DANGER
		summaryLbl.Text = "Could not load summary."
		return
	end

	if summary.success ~= true then
		summaryLbl.TextColor3 = DANGER
		summaryLbl.Text = tostring(summary.message or "Summary unavailable.")
		return
	end

	local avg = tonumber(summary.averageRating) or 0
	local total = tonumber(summary.totalReviews) or 0
	summaryLbl.TextColor3 = TEXT_MUTED

	local lines = {
		string.format("Average rating: %.1f / 5", avg),
		string.format("Total reviews: %d", total),
	}

	local snippet = ""
	if typeof(summary.reviews) == "table" and #(summary.reviews :: { any }) > 0 then
		local first = (summary.reviews :: { any })[1]
		if typeof(first) == "table" then
			local c = typeof((first :: any).comment) == "string" and (first :: any).comment or ""
			if #c > 72 then
				c = string.sub(c, 1, 69) .. "..."
			end
			if c ~= "" then
				snippet = "\nLatest: " .. c
			end
		end
	end

	summaryLbl.Text = table.concat(lines, "\n") .. snippet
end

local function fetchSummaryForLockedTarget(): ()
	local token = summaryFetchToken
	local uid = selectedTargetUserId
	if not uid then
		return
	end

	summaryLbl.TextColor3 = TEXT_MUTED
	summaryLbl.Text = "Loading summary..."

	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.GetPlayerReviewSummary:InvokeServer(uid)
		end)
		if token ~= summaryFetchToken or not root.Visible then
			return
		end
		if not ok then
			summaryLbl.TextColor3 = DANGER
			summaryLbl.Text = "Summary request failed."
			log("summary fetch failed userId=%s (%s)", tostring(uid), tostring(result))
			return
		end

		renderSummary(result)
		local nameForLog = targetLogName(selectedTargetPlayer, uid)
		if typeof(result) == "table" and result.success == true then
			log(
				"summary fetched for %s (avg=%.1f total=%d)",
				nameForLog,
				tonumber(result.averageRating) or 0,
				tonumber(result.totalReviews) or 0
			)
		else
			log(
				"summary rejected for %s: %s",
				nameForLog,
				typeof(result) == "table" and tostring(result.message) or "?"
			)
		end
	end)
end

local function submitReviewForLockedTarget(): ()
	local uid = selectedTargetUserId
	local rating = selectedRating
	if not uid or not rating then
		showFeedback("Choose a rating (1-5).", true)
		return
	end

	clearFeedback()
	submitBtn.Active = false

	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.SubmitPlayerReview:InvokeServer(uid, rating, commentBox.Text)
		end)

		submitBtn.Active = selectedRating ~= nil

		local nameForLog = targetLogName(selectedTargetPlayer, uid)

		if not ok then
			showFeedback("Submit failed.", true)
			log("review rejected for %s: invoke error %s", nameForLog, tostring(result))
			return
		end

		if typeof(result) == "table" and result.success == true then
			showFeedback(tostring(result.message or "Saved."), false)
			log(
				"review submitted for %s (avg=%.1f total=%d)",
				nameForLog,
				tonumber(result.averageRating) or 0,
				tonumber(result.totalReviews) or 0
			)
			fetchSummaryForLockedTarget()
			return
		end

		local msg = typeof(result) == "table" and tostring(result.message or "Rejected.") or "Rejected."
		showFeedback(msg, true)
		log("review rejected for %s: %s", nameForLog, msg)
	end)
end

local function closeReviewPanel(reason: string?)
	local uid = selectedTargetUserId
	local plr = selectedTargetPlayer
	local nm = targetLogName(plr, uid)

	summaryFetchToken += 1

	selectedTargetPlayer = nil
	selectedTargetUserId = nil
	selectedRating = nil
	updateRatingButtonsVisual()

	commentBox.Text = ""
	root.Visible = false
	clearFeedback()

	targetDisplayLbl.Text = ""
	targetUserLbl.Text = ""
	summaryLbl.TextColor3 = TEXT_MUTED
	summaryLbl.Text = ""

	if reason and nm ~= "?" then
		log("panel closed (%s) target=%s", reason, nm)
	end
end

local function openReviewPanel(target: Player)
	if not target or target == LocalPlayer then
		return
	end

	summaryFetchToken += 1

	selectedTargetPlayer = target
	selectedTargetUserId = target.UserId
	selectedRating = nil
	updateRatingButtonsVisual()
	clearFeedback()

	commentBox.Text = ""

	local display = target.DisplayName ~= "" and target.DisplayName or target.Name
	targetDisplayLbl.Text = display
	targetUserLbl.Text = "@" .. target.Name

	root.Visible = true

	log("panel opened for %s (%d)", target.Name, target.UserId)

	fetchSummaryForLockedTarget()
end

closeBtn.MouseButton1Click:Connect(function()
	closeReviewPanel("close_button")
end)

submitBtn.MouseButton1Click:Connect(submitReviewForLockedTarget)

for i, b in ratingButtons do
	b.MouseButton1Click:Connect(function()
		selectedRating = i
		updateRatingButtonsVisual()
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed: boolean)
	-- Close on Escape whenever the panel is open (even if a TextBox would eat the key).
	if input.KeyCode == Enum.KeyCode.Escape and root.Visible then
		closeReviewPanel("escape")
		return
	end

	if gameProcessed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local pos = if input.UserInputType == Enum.UserInputType.Touch
		then Vector2.new(input.Position.X, input.Position.Y)
		else UserInputService:GetMouseLocation()

	local other = resolveOtherPlayerFromScreenPoint(pos)
	if not other then
		return
	end

	openReviewPanel(other)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if not root.Visible then
		return
	end
	if selectedTargetUserId ~= player.UserId then
		return
	end

	summaryLbl.TextColor3 = DANGER
	summaryLbl.Text = "This player left the game."
	local leftId = player.UserId
	task.delay(1.2, function()
		if selectedTargetUserId == leftId then
			closeReviewPanel("target_left")
		end
	end)
end)
