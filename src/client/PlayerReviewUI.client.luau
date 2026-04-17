--[[
	PlayerReviewUI — click another eligible player once to arm a pending review, then click
	the same player again within a short window (or confirm) to open the full panel.
	Target is locked via selectedTargetUserId for all remote calls once opened.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig"))

local LOG_PREFIX = "[CLIENT][PlayerReview]"

-- Max distance (studs) from local character to target to open or submit a review.
local MAX_REVIEW_DISTANCE_STUDS = 18

-- Seconds to confirm a pending review target with a second click before it expires.
local PENDING_CONFIRM_SECONDS = 2.75

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

-- Cancels periodic eligibility refresh when the panel closes or target changes.
local eligibilityRefreshSeq = 0

-- Pending confirmation (panel not open yet): first click selects, second click opens.
local pendingReviewTarget: Player? = nil
local pendingReviewSeq = 0
local pendingEligibilityPollNext = 0

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
root.Size = UDim2.fromOffset(320, 492)
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

local eligibilityLbl = Instance.new("TextLabel")
eligibilityLbl.Name = "EligibilityStatus"
eligibilityLbl.BackgroundTransparency = 1
eligibilityLbl.Size = UDim2.new(1, 0, 0, 32)
eligibilityLbl.LayoutOrder = 4
eligibilityLbl.Font = Enum.Font.GothamMedium
eligibilityLbl.TextSize = 12
eligibilityLbl.TextColor3 = TEXT_MUTED
eligibilityLbl.TextXAlignment = Enum.TextXAlignment.Left
eligibilityLbl.TextYAlignment = Enum.TextYAlignment.Top
eligibilityLbl.TextWrapped = true
eligibilityLbl.Text = ""
eligibilityLbl.Parent = root

local summaryLbl = Instance.new("TextLabel")
summaryLbl.BackgroundTransparency = 1
summaryLbl.Size = UDim2.new(1, 0, 0, 34)
summaryLbl.LayoutOrder = 5
summaryLbl.Font = Enum.Font.Gotham
summaryLbl.TextSize = 13
summaryLbl.TextColor3 = TEXT_MUTED
summaryLbl.TextXAlignment = Enum.TextXAlignment.Left
summaryLbl.TextYAlignment = Enum.TextYAlignment.Top
summaryLbl.TextWrapped = true
summaryLbl.Text = ""
summaryLbl.Parent = root

local recentReviewsScroll = Instance.new("ScrollingFrame")
recentReviewsScroll.Name = "RecentReviews"
recentReviewsScroll.BackgroundTransparency = 0.25
recentReviewsScroll.BackgroundColor3 = Color3.fromRGB(18, 22, 38)
recentReviewsScroll.BorderSizePixel = 0
recentReviewsScroll.Size = UDim2.new(1, 0, 0, 96)
recentReviewsScroll.LayoutOrder = 6
recentReviewsScroll.ScrollBarThickness = 4
recentReviewsScroll.ScrollBarImageColor3 = ACCENT
recentReviewsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
recentReviewsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
recentReviewsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
recentReviewsScroll.ClipsDescendants = true
recentReviewsScroll.Parent = root
local rrCorner = Instance.new("UICorner")
rrCorner.CornerRadius = UDim.new(0, 6)
rrCorner.Parent = recentReviewsScroll
local rrPad = Instance.new("UIPadding")
rrPad.PaddingTop = UDim.new(0, 6)
rrPad.PaddingBottom = UDim.new(0, 6)
rrPad.PaddingLeft = UDim.new(0, 8)
rrPad.PaddingRight = UDim.new(0, 10)
rrPad.Parent = recentReviewsScroll

local recentReviewsList = Instance.new("Frame")
recentReviewsList.Name = "RecentReviewsList"
recentReviewsList.BackgroundTransparency = 1
recentReviewsList.Size = UDim2.new(1, 0, 0, 0)
recentReviewsList.AutomaticSize = Enum.AutomaticSize.Y
recentReviewsList.Parent = recentReviewsScroll

local recentReviewsLayout = Instance.new("UIListLayout")
recentReviewsLayout.SortOrder = Enum.SortOrder.LayoutOrder
recentReviewsLayout.Padding = UDim.new(0, 6)
recentReviewsLayout.Parent = recentReviewsList

local ratingSectionTitle = Instance.new("TextLabel")
ratingSectionTitle.BackgroundTransparency = 1
ratingSectionTitle.Size = UDim2.new(1, 0, 0, 16)
ratingSectionTitle.LayoutOrder = 7
ratingSectionTitle.Font = Enum.Font.GothamBold
ratingSectionTitle.TextSize = 12
ratingSectionTitle.TextColor3 = TEXT_WHITE
ratingSectionTitle.TextXAlignment = Enum.TextXAlignment.Left
ratingSectionTitle.Text = "Rating (required)"
ratingSectionTitle.Parent = root

local ratingRow = Instance.new("Frame")
ratingRow.BackgroundTransparency = 1
ratingRow.Size = UDim2.new(1, 0, 0, 36)
ratingRow.LayoutOrder = 8
ratingRow.Parent = root

local ratingLayout = Instance.new("UIListLayout")
ratingLayout.FillDirection = Enum.FillDirection.Horizontal
ratingLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
ratingLayout.Padding = UDim.new(0, 6)
ratingLayout.Parent = ratingRow

local ratingButtons: { TextButton } = {}
local ratingButtonStrokes: { UIStroke } = {}
local defaultRatingBg = Color3.fromRGB(40, 44, 62)
local ratingStrokeIdle = Color3.fromRGB(75, 80, 105)
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
	local st = Instance.new("UIStroke")
	st.Color = ratingStrokeIdle
	st.Thickness = 1
	st.Transparency = 0.45
	st.Parent = b
	table.insert(ratingButtons, b)
	table.insert(ratingButtonStrokes, st)
end

local ratingHintLbl = Instance.new("TextLabel")
ratingHintLbl.BackgroundTransparency = 1
ratingHintLbl.Size = UDim2.new(1, 0, 0, 14)
ratingHintLbl.LayoutOrder = 9
ratingHintLbl.Font = Enum.Font.Gotham
ratingHintLbl.TextSize = 11
ratingHintLbl.TextColor3 = TEXT_MUTED
ratingHintLbl.TextXAlignment = Enum.TextXAlignment.Left
ratingHintLbl.Text = "Tap a number (1 = low, 5 = high)"
ratingHintLbl.Parent = root

local commentTitle = Instance.new("TextLabel")
commentTitle.BackgroundTransparency = 1
commentTitle.Size = UDim2.new(1, 0, 0, 16)
commentTitle.LayoutOrder = 10
commentTitle.Font = Enum.Font.GothamBold
commentTitle.TextSize = 12
commentTitle.TextColor3 = TEXT_WHITE
commentTitle.TextXAlignment = Enum.TextXAlignment.Left
commentTitle.Text = "Comment (optional)"
commentTitle.Parent = root

local commentBox = Instance.new("TextBox")
commentBox.Size = UDim2.new(1, 0, 0, 64)
commentBox.LayoutOrder = 11
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
statusLbl.Size = UDim2.new(1, 0, 0, 30)
statusLbl.LayoutOrder = 12
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
submitBtn.LayoutOrder = 13
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

-- Compact hint when a player is selected but panel not opened yet (local player only).
local pendingHint = Instance.new("Frame")
pendingHint.Name = "PendingConfirmHint"
pendingHint.AnchorPoint = Vector2.new(0.5, 1)
pendingHint.Position = UDim2.new(0.5, 0, 1, -100)
pendingHint.Size = UDim2.fromOffset(360, 34)
pendingHint.BackgroundColor3 = NAVY
pendingHint.BorderSizePixel = 0
pendingHint.Visible = false
pendingHint.ZIndex = 5
pendingHint.Parent = screenGui
local phc = Instance.new("UICorner")
phc.CornerRadius = UDim.new(0, 6)
phc.Parent = pendingHint
local phs = Instance.new("UIStroke")
phs.Color = ACCENT
phs.Thickness = 1
phs.Transparency = 0.35
phs.Parent = pendingHint
local pendingHintLbl = Instance.new("TextLabel")
pendingHintLbl.BackgroundTransparency = 1
pendingHintLbl.Size = UDim2.new(1, -16, 1, 0)
pendingHintLbl.Position = UDim2.new(0, 8, 0, 0)
pendingHintLbl.Font = Enum.Font.GothamMedium
pendingHintLbl.TextSize = 13
pendingHintLbl.TextColor3 = TEXT_WHITE
pendingHintLbl.TextXAlignment = Enum.TextXAlignment.Center
pendingHintLbl.Text = ""
pendingHintLbl.Parent = pendingHint

-- Follows mouse when an eligible review target is hovered (desktop only).
local hoverPromptWrap = Instance.new("Frame")
hoverPromptWrap.Name = "HoverReviewPrompt"
hoverPromptWrap.AnchorPoint = Vector2.new(0.5, 0)
hoverPromptWrap.Size = UDim2.fromOffset(268, 28)
hoverPromptWrap.BackgroundColor3 = NAVY
hoverPromptWrap.BackgroundTransparency = 0.18
hoverPromptWrap.BorderSizePixel = 0
hoverPromptWrap.Visible = false
hoverPromptWrap.ZIndex = 15
hoverPromptWrap.Parent = screenGui
local hoverPromptCorner = Instance.new("UICorner")
hoverPromptCorner.CornerRadius = UDim.new(0, 6)
hoverPromptCorner.Parent = hoverPromptWrap
local hoverPromptStroke = Instance.new("UIStroke")
hoverPromptStroke.Color = ACCENT
hoverPromptStroke.Thickness = 1
hoverPromptStroke.Transparency = 0.6
hoverPromptStroke.Parent = hoverPromptWrap
local hoverPromptLbl = Instance.new("TextLabel")
hoverPromptLbl.BackgroundTransparency = 1
hoverPromptLbl.Size = UDim2.new(1, -14, 1, 0)
hoverPromptLbl.Position = UDim2.new(0, 7, 0, 0)
hoverPromptLbl.Font = Enum.Font.GothamMedium
hoverPromptLbl.TextSize = 13
hoverPromptLbl.TextColor3 = TEXT_WHITE
hoverPromptLbl.TextXAlignment = Enum.TextXAlignment.Center
hoverPromptLbl.TextTruncate = Enum.TextTruncate.AtEnd
hoverPromptLbl.Text = ""
hoverPromptLbl.Parent = hoverPromptWrap

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
		local sel = selectedRating == i
		local stroke = ratingButtonStrokes[i]
		b.BackgroundColor3 = sel and ACCENT or defaultRatingBg
		if stroke then
			stroke.Thickness = sel and 2.5 or 1
			stroke.Color = sel and TEXT_WHITE or ratingStrokeIdle
			stroke.Transparency = sel and 0.1 or 0.45
		end
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

local function getRootPart(char: Model): BasePart?
	local r = char:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	if char.PrimaryPart and char.PrimaryPart:IsA("BasePart") then
		return char.PrimaryPart
	end
	return nil
end

-- True if both characters exist and HRPs are within MAX_REVIEW_DISTANCE_STUDS.
local function withinReviewDistanceTo(other: Player): boolean
	local myChar = LocalPlayer.Character
	local theirChar = other.Character
	if not myChar or not theirChar then
		return false
	end
	local a = getRootPart(myChar)
	local b = getRootPart(theirChar)
	if not a or not b then
		return false
	end
	return (a.Position - b.Position).Magnitude <= MAX_REVIEW_DISTANCE_STUDS
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

-- Server returns { eligible = bool, reason = optional } or legacy boolean.
local function parseReviewEligibilityResponse(res: any): (boolean, string)
	if res == true then
		return true, ""
	end
	if typeof(res) ~= "table" then
		return false, "unknown"
	end
	local t = res :: { eligible: any?, reason: any? }
	if t.eligible == true then
		return true, ""
	end
	if t.reason == "interaction" then
		return false, "interaction"
	end
	if t.reason == "city" then
		return false, "city"
	end
	if t.reason == "unavailable" then
		return false, "unavailable"
	end
	return false, "unknown"
end

-- ——— Eligible-target hover (desktop pointer; same gates as opening a review) ———
local HOVER_ELIGIBILITY_POLL = 2
local hoverTrackSeq = 0
local hoverPlayer: Player? = nil
local hoverDisplayActive = false
local hoverNextPollTime = 0
local hoverHighlight: Highlight? = nil

local function displayNameForHover(p: Player): string
	return p.DisplayName ~= "" and p.DisplayName or p.Name
end

local function layoutHoverPromptScreenPos(screenPos: Vector2)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local guiTop = GuiService:GetGuiInset().Y
	local x = math.clamp(screenPos.X, 64, math.max(64, vp.X - 64))
	local y = math.clamp(screenPos.Y + 32, guiTop + 4, math.max(guiTop + 4, vp.Y - 6))
	hoverPromptWrap.Position = UDim2.fromOffset(x, y)
end

local function detachHoverHighlight()
	if hoverHighlight then
		hoverHighlight.Enabled = false
		hoverHighlight.Parent = nil
	end
end

local function ensureHoverHighlightOn(char: Model)
	if not hoverHighlight then
		hoverHighlight = Instance.new("Highlight")
		hoverHighlight.Name = "ReviewHoverFx"
		hoverHighlight.FillColor = ACCENT
		hoverHighlight.OutlineColor = ACCENT
		hoverHighlight.FillTransparency = 0.92
		hoverHighlight.OutlineTransparency = 0.78
		hoverHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	end
	if hoverHighlight.Parent ~= char then
		hoverHighlight.Parent = char
	end
	hoverHighlight.Enabled = true
end

local function clearEligibleHover()
	hoverTrackSeq += 1
	hoverPlayer = nil
	hoverDisplayActive = false
	hoverNextPollTime = 0
	detachHoverHighlight()
	hoverPromptWrap.Visible = false
end

RunService.RenderStepped:Connect(function()
	-- Pending review confirmation: cancel early if gates fail (same checks as confirm click).
	if pendingReviewTarget and not root.Visible then
		local p = pendingReviewTarget
		if not p.Parent then
			invalidatePending("target_left")
		elseif not p.Character then
			invalidatePending("invalid_target")
		elseif not withinReviewDistanceTo(p) then
			invalidatePending("distance")
		elseif GuiService.MenuIsOpen then
			invalidatePending("invalid_target")
		elseif UserInputService:GetFocusedTextBox() ~= nil then
			invalidatePending("invalid_target")
		else
			local nowPc = os.clock()
			if nowPc >= pendingEligibilityPollNext then
				pendingEligibilityPollNext = nowPc + HOVER_ELIGIBILITY_POLL
				local seqCap = pendingReviewSeq
				local pt = p
				task.spawn(function()
					local ok, raw = pcall(function()
						return Remotes.GetReviewCityEligibility:InvokeServer(pt.UserId)
					end)
					if seqCap ~= pendingReviewSeq then
						return
					end
					if pendingReviewTarget ~= pt then
						return
					end
					local eligible = select(1, parseReviewEligibilityResponse(ok and raw or false))
					if not eligible then
						invalidatePending("eligibility")
					end
				end)
			end
		end
	end

	if root.Visible then
		if hoverPlayer ~= nil then
			clearEligibleHover()
		end
		return
	end

	if not UserInputService.MouseEnabled then
		if hoverPlayer ~= nil then
			clearEligibleHover()
		end
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local other = resolveOtherPlayerFromScreenPoint(mousePos)
	if not other or not withinReviewDistanceTo(other) then
		clearEligibleHover()
		return
	end

	local nowClock = os.clock()

	if hoverPlayer ~= other then
		hoverTrackSeq += 1
		hoverPlayer = other
		hoverDisplayActive = false
		hoverNextPollTime = 0
		detachHoverHighlight()
		hoverPromptWrap.Visible = false
	end

	local pollDue = nowClock >= hoverNextPollTime
	if pollDue then
		hoverNextPollTime = nowClock + HOVER_ELIGIBILITY_POLL
	end

	local seqAtStart = hoverTrackSeq
	local targetForPoll = other

	if pollDue then
		task.spawn(function()
			local ok, raw = pcall(function()
				return Remotes.GetReviewCityEligibility:InvokeServer(targetForPoll.UserId)
			end)
			if seqAtStart ~= hoverTrackSeq then
				return
			end
			if hoverPlayer ~= targetForPoll then
				return
			end
			local eligible = select(1, parseReviewEligibilityResponse(ok and raw or false))
			if not eligible then
				hoverDisplayActive = false
				detachHoverHighlight()
				hoverPromptWrap.Visible = false
				return
			end
			if hoverPlayer ~= targetForPoll then
				return
			end
			hoverDisplayActive = true
			local char = targetForPoll.Character
			if char then
				ensureHoverHighlightOn(char)
			end
			hoverPromptLbl.Text = string.format("Click to review %s", displayNameForHover(targetForPoll))
			hoverPromptWrap.Visible = true
			layoutHoverPromptScreenPos(UserInputService:GetMouseLocation())
		end)
	end

	if hoverDisplayActive and hoverPlayer == other then
		layoutHoverPromptScreenPos(mousePos)
		local char = other.Character
		if char then
			ensureHoverHighlightOn(char)
		else
			detachHoverHighlight()
		end
	end
end)

local function eligibilityFailMessage(kind: string): string
	if kind == "interaction" then
		return "You can only review players you've recently interacted with."
	end
	if kind == "unavailable" then
		return "Target is not available."
	end
	return "Reviews are only for players in your city."
end

local WARN_AMBER = Color3.fromRGB(230, 175, 85)

local function refreshPanelEligibilityStatus()
	if not root.Visible or not selectedTargetUserId then
		return
	end
	local plr = selectedTargetPlayer
	if not plr or not plr.Parent then
		eligibilityLbl.TextColor3 = DANGER
		eligibilityLbl.Text = "This player is unavailable."
		return
	end
	if not withinReviewDistanceTo(plr) then
		eligibilityLbl.TextColor3 = WARN_AMBER
		eligibilityLbl.Text = "Too far away — move closer."
		return
	end
	local ok, raw = pcall(function()
		return Remotes.GetReviewCityEligibility:InvokeServer(selectedTargetUserId)
	end)
	local eligible, kind = parseReviewEligibilityResponse(ok and raw or false)
	if eligible then
		eligibilityLbl.TextColor3 = SUCCESS
		eligibilityLbl.Text = "Eligible to review."
		return
	end
	if kind == "interaction" then
		eligibilityLbl.TextColor3 = WARN_AMBER
		eligibilityLbl.Text = "Interact a little longer before reviewing."
	elseif kind == "city" then
		eligibilityLbl.TextColor3 = DANGER
		eligibilityLbl.Text = "You must be in the same city."
	elseif kind == "unavailable" then
		eligibilityLbl.TextColor3 = DANGER
		eligibilityLbl.Text = "This player is unavailable."
	else
		eligibilityLbl.TextColor3 = DANGER
		eligibilityLbl.Text = "You cannot review this player right now."
	end
end

local function startEligibilityRefreshWhilePanelOpen()
	eligibilityRefreshSeq += 1
	local seq = eligibilityRefreshSeq
	refreshPanelEligibilityStatus()
	task.spawn(function()
		while seq == eligibilityRefreshSeq and root.Visible do
			task.wait(2)
			if seq ~= eligibilityRefreshSeq or not root.Visible then
				break
			end
			refreshPanelEligibilityStatus()
		end
	end)
end

local function mapSubmitRejectMessage(serverMsg: string): string
	local s = string.lower(serverMsg)
	if string.find(s, "recently interacted") or string.find(s, "interacted with") then
		return "Spend more time nearby, then try again."
	end
	if string.find(s, "in your city") or string.find(s, "same city") then
		return "You must be in the same city."
	end
	if string.find(s, "move closer") or string.find(s, "too far") then
		return "Too far away — move closer."
	end
	if string.find(s, "not available") then
		return "This player is unavailable."
	end
	if string.find(s, "please wait") then
		return serverMsg
	end
	if string.find(s, "not ready") then
		return "Your data isn't ready yet."
	end
	if string.find(s, "invalid review") then
		return "Invalid review target."
	end
	if string.find(s, "yourself") then
		return "You can't review yourself."
	end
	if string.find(s, "could not save") or string.find(s, "couldn't save") then
		return "Couldn't save review. Try again."
	end
	return serverMsg
end

local function shortSubmitSuccessMessage(serverMsg: string?): string
	local s = typeof(serverMsg) == "string" and serverMsg or ""
	if string.find(string.lower(s), "updated") then
		return "Review updated."
	end
	return "Review submitted."
end

local STAR_FILL = Color3.fromRGB(255, 215, 120)

local function ratingStarsGlyphs(rating: number): string
	local r = math.clamp(math.floor(rating + 0.5), 1, 5)
	return string.rep("★", r) .. string.rep("☆", 5 - r)
end

local function truncateForCard(s: string, maxLen: number): string
	if #s <= maxLen then
		return s
	end
	return string.sub(s, 1, maxLen - 3) .. "..."
end

-- Short relative label; uses calendar day for "yesterday" / "Nd ago".
local function formatRelativeShort(createdAt: number): string
	local now = os.time()
	local diff = math.max(0, now - createdAt)
	if diff < 50 then
		return "just now"
	end
	if diff < 3600 then
		local m = math.max(1, math.floor(diff / 60))
		return string.format("%dm ago", m)
	end

	local tNow = os.date("*t", now)
	local tTs = os.date("*t", createdAt)
	local startToday =
		os.time({ year = tNow.year, month = tNow.month, day = tNow.day, hour = 12, min = 0, sec = 0 })
	local startCreated =
		os.time({ year = tTs.year, month = tTs.month, day = tTs.day, hour = 12, min = 0, sec = 0 })
	local daysBehind = math.floor((startToday - startCreated) / 86400 + 0.5)

	if daysBehind <= 0 then
		local h = math.max(1, math.floor(diff / 3600))
		return string.format("%dh ago", h)
	end
	if daysBehind == 1 then
		return "yesterday"
	end
	return string.format("%dd ago", daysBehind)
end

local function clearRecentReviewRows()
	for _, ch in ipairs(recentReviewsList:GetChildren()) do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	recentReviewsScroll.CanvasPosition = Vector2.zero
end

local function appendRecentReviewRow(entry: any, layoutOrder: number)
	if typeof(entry) ~= "table" then
		return
	end
	local nameStr = typeof((entry :: any).reviewerName) == "string" and (entry :: any).reviewerName or "Player"
	local rating = tonumber((entry :: any).rating) or 0
	local comment = typeof((entry :: any).comment) == "string" and (entry :: any).comment or ""
	local createdAt = tonumber((entry :: any).createdAt) or 0

	local card = Instance.new("Frame")
	card.BackgroundTransparency = 1
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = layoutOrder

	local v = Instance.new("UIListLayout")
	v.SortOrder = Enum.SortOrder.LayoutOrder
	v.Padding = UDim.new(0, 3)
	v.FillDirection = Enum.FillDirection.Vertical
	v.Parent = card

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 17)
	top.LayoutOrder = 1

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Padding = UDim.new(0, 6)
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	topLayout.Parent = top

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Size = UDim2.new(1, -132, 0, 17)
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 12
	nameLbl.TextColor3 = TEXT_WHITE
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = nameStr
	nameLbl.Parent = top

	local starsLbl = Instance.new("TextLabel")
	starsLbl.BackgroundTransparency = 1
	starsLbl.Size = UDim2.new(0, 76, 0, 17)
	starsLbl.Font = Enum.Font.GothamBold
	starsLbl.TextSize = 11
	starsLbl.TextColor3 = STAR_FILL
	starsLbl.TextXAlignment = Enum.TextXAlignment.Center
	starsLbl.Text = ratingStarsGlyphs(rating)
	starsLbl.Parent = top

	local timeLbl = Instance.new("TextLabel")
	timeLbl.BackgroundTransparency = 1
	timeLbl.Size = UDim2.new(0, 50, 0, 17)
	timeLbl.Font = Enum.Font.Gotham
	timeLbl.TextSize = 11
	timeLbl.TextColor3 = TEXT_MUTED
	timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.Text = formatRelativeShort(createdAt)
	timeLbl.Parent = top

	if comment ~= "" then
		local cl = Instance.new("TextLabel")
		cl.BackgroundTransparency = 1
		cl.Size = UDim2.new(1, 0, 0, 0)
		cl.AutomaticSize = Enum.AutomaticSize.Y
		cl.Font = Enum.Font.Gotham
		cl.TextSize = 11
		cl.TextColor3 = TEXT_MUTED
		cl.TextXAlignment = Enum.TextXAlignment.Left
		cl.TextWrapped = true
		cl.Text = truncateForCard(comment, 110)
		cl.LayoutOrder = 2
		cl.Parent = card
	end

	card.Parent = recentReviewsList
end

local function hidePendingHint()
	pendingHint.Visible = false
	pendingHintLbl.Text = ""
end

local function invalidatePending(reason: string?)
	local had = pendingReviewTarget
	pendingReviewSeq += 1
	pendingReviewTarget = nil
	hidePendingHint()

	if reason == "timeout" and had then
		log("pending expired target=%s", had.Name)
		return
	end

	if reason == nil then
		return
	end

	local messages: { [string]: string } = {
		distance = "pending cancelled (distance)",
		eligibility = "pending cancelled (eligibility)",
		target_left = "pending cancelled (target_left)",
		local_respawn = "pending cancelled (local_respawn)",
		invalid_target = "pending cancelled (invalid_target)",
	}
	local msg = messages[reason]
	if msg and had then
		log(msg)
	end
end

local function armPendingReviewTarget(target: Player)
	local display = target.DisplayName ~= "" and target.DisplayName or target.Name
	pendingReviewSeq += 1
	local armSeq = pendingReviewSeq
	pendingReviewTarget = target
	pendingEligibilityPollNext = 0
	pendingHintLbl.Text = string.format("Review %s — click again (%.1fs)", display, PENDING_CONFIRM_SECONDS)
	pendingHint.Visible = true
	log("pending target=%s (%d)", target.Name, target.UserId)
	task.delay(PENDING_CONFIRM_SECONDS, function()
		if armSeq == pendingReviewSeq and pendingReviewTarget == target then
			invalidatePending("timeout")
		end
	end)
end

local function renderSummary(summary: any, expectedToken: number)
	if expectedToken ~= summaryFetchToken or not root.Visible then
		return
	end
	if typeof(summary) ~= "table" then
		summaryLbl.TextColor3 = DANGER
		summaryLbl.Text = "Could not load summary."
		clearRecentReviewRows()
		return
	end

	if summary.success ~= true then
		summaryLbl.TextColor3 = DANGER
		summaryLbl.Text = tostring(summary.message or "Summary unavailable.")
		clearRecentReviewRows()
		return
	end

	local avg = tonumber(summary.averageRating) or 0
	local total = math.max(0, math.floor(tonumber(summary.totalReviews) or 0))
	summaryLbl.TextColor3 = TEXT_MUTED
	summaryLbl.Text = string.format("Average %.1f / 5   ·   %d reviews", avg, total)

	clearRecentReviewRows()

	if expectedToken ~= summaryFetchToken or not root.Visible then
		return
	end

	if total == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 20)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.TextColor3 = TEXT_MUTED
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Text = "No reviews yet."
		empty.LayoutOrder = 1
		empty.Parent = recentReviewsList
		return
	end

	local revs = typeof(summary.reviews) == "table" and (summary.reviews :: { any }) or {}
	local n = math.min(3, #revs)
	for i = 1, n do
		if expectedToken ~= summaryFetchToken or not root.Visible then
			return
		end
		appendRecentReviewRow(revs[i], i)
	end
end

local function fetchSummaryForLockedTarget(): ()
	local token = summaryFetchToken
	local uid = selectedTargetUserId
	if not uid then
		return
	end

	clearRecentReviewRows()
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
			clearRecentReviewRows()
			log("summary fetch failed userId=%s (%s)", tostring(uid), tostring(result))
			return
		end

		renderSummary(result, token)
		if token == summaryFetchToken and root.Visible then
			refreshPanelEligibilityStatus()
		end
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

	local targetPlr = selectedTargetPlayer
	if not targetPlr or not targetPlr.Parent then
		showFeedback("Target is no longer available.", true)
		return
	end

	if not withinReviewDistanceTo(targetPlr) then
		showFeedback("Move closer to submit a review.", true)
		return
	end

	local okElig, rawElig = pcall(function()
		return Remotes.GetReviewCityEligibility:InvokeServer(uid)
	end)
	local eligible, failKind = parseReviewEligibilityResponse(if okElig then rawElig else false)
	if not eligible then
		showFeedback(eligibilityFailMessage(failKind), true)
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
			local sm = typeof((result :: any).message) == "string" and (result :: any).message or ""
			showFeedback(shortSubmitSuccessMessage(sm), false)
			log(
				"review submitted for %s (avg=%.1f total=%d)",
				nameForLog,
				tonumber(result.averageRating) or 0,
				tonumber(result.totalReviews) or 0
			)
			fetchSummaryForLockedTarget()
			return
		end

		local rawMsg = typeof(result) == "table" and tostring((result :: any).message or "Rejected.") or "Rejected."
		showFeedback(mapSubmitRejectMessage(rawMsg), true)
		log("review rejected for %s: %s", nameForLog, rawMsg)
	end)
end

local function closeReviewPanel(reason: string?)
	local uid = selectedTargetUserId
	local plr = selectedTargetPlayer
	local nm = targetLogName(plr, uid)

	summaryFetchToken += 1
	eligibilityRefreshSeq += 1
	invalidatePending(nil)

	selectedTargetPlayer = nil
	selectedTargetUserId = nil
	selectedRating = nil
	updateRatingButtonsVisual()

	commentBox.Text = ""
	root.Visible = false
	clearFeedback()

	targetDisplayLbl.Text = ""
	targetUserLbl.Text = ""
	eligibilityLbl.Text = ""
	eligibilityLbl.TextColor3 = TEXT_MUTED
	summaryLbl.TextColor3 = TEXT_MUTED
	summaryLbl.Text = ""
	clearRecentReviewRows()

	if reason and nm ~= "?" then
		log("panel closed (%s) target=%s", reason, nm)
	end
end

local function openReviewPanel(target: Player, fromPendingConfirm: boolean?)
	if not target or target == LocalPlayer then
		return
	end

	invalidatePending(nil)

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
	eligibilityLbl.Text = ""
	eligibilityLbl.TextColor3 = TEXT_MUTED

	root.Visible = true

	if fromPendingConfirm then
		log("panel opened for confirmed target %s (%d)", target.Name, target.UserId)
	else
		log("panel opened for %s (%d)", target.Name, target.UserId)
	end

	fetchSummaryForLockedTarget()
	startEligibilityRefreshWhilePanelOpen()
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
	if input.KeyCode == Enum.KeyCode.Escape then
		if root.Visible then
			closeReviewPanel("escape")
			return
		end
		if pendingReviewTarget then
			invalidatePending(nil)
			return
		end
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

	if not withinReviewDistanceTo(other) then
		return
	end

	local okElig, rawElig = pcall(function()
		return Remotes.GetReviewCityEligibility:InvokeServer(other.UserId)
	end)
	local eligible, failKind = parseReviewEligibilityResponse(if okElig then rawElig else false)
	if not eligible then
		if root.Visible then
			showFeedback(eligibilityFailMessage(failKind), true)
		end
		return
	end

	if root.Visible then
		openReviewPanel(other, false)
		return
	end

	if pendingReviewTarget == other then
		openReviewPanel(other, true)
		return
	end

	armPendingReviewTarget(other)
end)

LocalPlayer.CharacterAdded:Connect(function()
	clearEligibleHover()
	if pendingReviewTarget then
		invalidatePending("local_respawn")
	end
	if root.Visible then
		closeReviewPanel("local_respawn")
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if hoverPlayer == player then
		clearEligibleHover()
	end

	if pendingReviewTarget == player then
		invalidatePending("target_left")
	end

	if not root.Visible then
		return
	end
	if selectedTargetUserId ~= player.UserId then
		return
	end

	summaryLbl.TextColor3 = DANGER
	summaryLbl.Text = "This player left the game."
	clearRecentReviewRows()
	eligibilityLbl.TextColor3 = DANGER
	eligibilityLbl.Text = "This player is unavailable."
	local leftId = player.UserId
	task.delay(1.2, function()
		if selectedTargetUserId == leftId then
			closeReviewPanel("target_left")
		end
	end)
end)
