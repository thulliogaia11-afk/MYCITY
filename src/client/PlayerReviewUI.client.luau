--[[
	PlayerReviewUI — click another player in the world to open a compact review panel.
	Target is fixed at open time (UserId); server validation unchanged.
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

-- ——— Theme (aligned with MainUI mood, compact panel) ———
local NAVY = Color3.fromHex("16213e")
local ACCENT = Color3.fromHex("e94560")
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_MUTED = Color3.fromRGB(160, 165, 185)
local SUCCESS = Color3.fromRGB(60, 180, 110)
local DANGER = Color3.fromRGB(220, 70, 80)
local CORNER = UDim.new(0, 8)

-- ——— State ———
local selectedTargetPlayer: Player? = nil
local selectedTargetUserId: number? = nil
local selectedRating: number? = nil

local summaryFetchToken = 0

-- ——— UI (built once) ———
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
root.Size = UDim2.fromOffset(340, 400)
root.BackgroundColor3 = NAVY
root.BorderSizePixel = 0
root.Visible = false
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
layout.Padding = UDim.new(0, 8)
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
titleLbl.TextSize = 18
titleLbl.TextColor3 = TEXT_WHITE
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "Review player"
titleLbl.Parent = titleRow

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, 0, 0, 0)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.BackgroundColor3 = ACCENT
closeBtn.TextColor3 = TEXT_WHITE
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleRow
local closeC = Instance.new("UICorner")
closeC.CornerRadius = UDim.new(0, 6)
closeC.Parent = closeBtn

local targetLbl = Instance.new("TextLabel")
targetLbl.BackgroundTransparency = 1
targetLbl.Size = UDim2.new(1, 0, 0, 22)
targetLbl.LayoutOrder = 2
targetLbl.Font = Enum.Font.Gotham
targetLbl.TextSize = 15
targetLbl.TextColor3 = ACCENT
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.Text = "Target: —"
targetLbl.Parent = root

local summaryLbl = Instance.new("TextLabel")
summaryLbl.BackgroundTransparency = 1
summaryLbl.Size = UDim2.new(1, 0, 0, 52)
summaryLbl.LayoutOrder = 3
summaryLbl.Font = Enum.Font.Gotham
summaryLbl.TextSize = 13
summaryLbl.TextColor3 = TEXT_MUTED
summaryLbl.TextXAlignment = Enum.TextXAlignment.Left
summaryLbl.TextYAlignment = Enum.TextYAlignment.Top
summaryLbl.TextWrapped = true
summaryLbl.Text = "Loading summary…"
summaryLbl.Parent = root

local ratingLabel = Instance.new("TextLabel")
ratingLabel.BackgroundTransparency = 1
ratingLabel.Size = UDim2.new(1, 0, 0, 18)
ratingLabel.LayoutOrder = 4
ratingLabel.Font = Enum.Font.GothamBold
ratingLabel.TextSize = 13
ratingLabel.TextColor3 = TEXT_WHITE
ratingLabel.TextXAlignment = Enum.TextXAlignment.Left
ratingLabel.Text = "Rating (choose 1–5)"
ratingLabel.Parent = root

local ratingRow = Instance.new("Frame")
ratingRow.BackgroundTransparency = 1
ratingRow.Size = UDim2.new(1, 0, 0, 36)
ratingRow.LayoutOrder = 5
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
	b.Size = UDim2.new(0, 48, 0, 34)
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

local commentBox = Instance.new("TextBox")
commentBox.Size = UDim2.new(1, 0, 0, 72)
commentBox.LayoutOrder = 6
commentBox.BackgroundColor3 = Color3.fromRGB(22, 28, 45)
commentBox.TextColor3 = TEXT_WHITE
commentBox.PlaceholderColor3 = TEXT_MUTED
commentBox.PlaceholderText = "Optional comment (max 160 chars)"
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
statusLbl.Size = UDim2.new(1, 0, 0, 36)
statusLbl.LayoutOrder = 7
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
submitBtn.Size = UDim2.new(1, 0, 0, 38)
submitBtn.LayoutOrder = 8
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

local function updateRatingButtonsVisual()
	for i, b in ratingButtons do
		b.BackgroundColor3 = (selectedRating == i) and ACCENT or defaultRatingBg
	end
	submitBtn.Active = selectedRating ~= nil
	submitBtn.BackgroundColor3 = (selectedRating ~= nil) and SUCCESS or Color3.fromRGB(55, 65, 55)
end

local function clearTransientStatus()
	statusLbl.Visible = false
	statusLbl.Text = ""
end

local function showTransientStatus(text: string, isError: boolean?)
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

local function screenPointBlocksGui(screenPos: Vector2): boolean
	-- GetGuiObjectsAtPosition accounts for GuiInset per Roblox API.
	local at = GuiService:GetGuiObjectsAtPosition(screenPos.X, screenPos.Y)
	return #at > 0
end

local function resolveClickedPlayer(screenPos: Vector2): Player?
	if screenPointBlocksGui(screenPos) then
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

local function renderSummaryInPanel(summary: any)
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

	local snippet = ""
	if typeof(summary.reviews) == "table" and #(summary.reviews :: { any }) > 0 then
		local first = (summary.reviews :: { any })[1]
		if typeof(first) == "table" then
			local c = typeof((first :: any).comment) == "string" and (first :: any).comment or ""
			if #c > 80 then
				c = string.sub(c, 1, 77) .. "…"
			end
			if c ~= "" then
				snippet = "\nLatest: " .. c
			end
		end
	end

	summaryLbl.Text = string.format("Average %.1f · %d review(s)%s", avg, total, snippet)
end

local function fetchSummaryForTarget(): ()
	local token = summaryFetchToken
	local uid = selectedTargetUserId
	if not uid then
		return
	end

	summaryLbl.TextColor3 = TEXT_MUTED
	summaryLbl.Text = "Loading summary…"

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
			log("review summary fetch failed for userId=%d (%s)", uid, tostring(result))
			return
		end

		renderSummaryInPanel(result)
		if typeof(result) == "table" and result.success == true then
			local nm = selectedTargetPlayer and selectedTargetPlayer.Name or ("userId " .. tostring(uid))
			log(
				"review summary fetched for %s (avg=%.1f total=%d)",
				nm,
				tonumber(result.averageRating) or 0,
				tonumber(result.totalReviews) or 0
			)
		else
			local nm = selectedTargetPlayer and selectedTargetPlayer.Name or ("userId " .. tostring(uid))
			log("review summary rejected for %s: %s", nm, typeof(result) == "table" and tostring(result.message) or "?")
		end
	end)
end

local function submitReview(): ()
	local uid = selectedTargetUserId
	if not uid or not selectedRating then
		showTransientStatus("Choose a rating from 1 to 5.", true)
		return
	end

	clearTransientStatus()
	submitBtn.Active = false

	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.SubmitPlayerReview:InvokeServer(uid, selectedRating, commentBox.Text)
		end)

		submitBtn.Active = selectedRating ~= nil

		if not ok then
			local nm = selectedTargetPlayer and selectedTargetPlayer.Name or ("#" .. tostring(uid))
			showTransientStatus("Submit failed: " .. tostring(result), true)
			log("review submit rejected for %s: invoke error %s", nm, tostring(result))
			return
		end

		if typeof(result) == "table" and result.success == true then
			local nm = selectedTargetPlayer and selectedTargetPlayer.Name or ("#" .. tostring(uid))
			showTransientStatus(tostring(result.message or "Saved."), false)
			log(
				"review submit succeeded for %s (avg=%.1f total=%d)",
				nm,
				tonumber(result.averageRating) or 0,
				tonumber(result.totalReviews) or 0
			)
			fetchSummaryForTarget()
		else
			local msg = typeof(result) == "table" and tostring(result.message or "Rejected.") or "Rejected."
			local nm = selectedTargetPlayer and selectedTargetPlayer.Name or ("#" .. tostring(uid))
			showTransientStatus(msg, true)
			log("review submit rejected for %s: %s", nm, msg)
		end
	end)
end

local function closeReviewPanel(reason: string?)
	local uid = selectedTargetUserId
	local nm = selectedTargetPlayer and selectedTargetPlayer.Name or (uid and ("#" .. tostring(uid)) or "?")

	summaryFetchToken += 1

	selectedTargetPlayer = nil
	selectedTargetUserId = nil
	selectedRating = nil
	updateRatingButtonsVisual()

	commentBox.Text = ""
	root.Visible = false
	clearTransientStatus()

	targetLbl.Text = "Target: —"
	summaryLbl.TextColor3 = TEXT_MUTED
	summaryLbl.Text = ""

	if reason and nm ~= "?" then
		log("review panel closed for %s (%s)", nm, reason)
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
	clearTransientStatus()

	commentBox.Text = ""

	targetLbl.Text = string.format("Target: %s", target.DisplayName ~= "" and target.DisplayName or target.Name)
	root.Visible = true

	log("review panel opened for %s (%d)", target.Name, target.UserId)

	fetchSummaryForTarget()
end

closeBtn.MouseButton1Click:Connect(function()
	closeReviewPanel("close_button")
end)

submitBtn.MouseButton1Click:Connect(submitReview)

for i, b in ratingButtons do
	b.MouseButton1Click:Connect(function()
		selectedRating = i
		updateRatingButtonsVisual()
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode ~= Enum.KeyCode.Escape then
		return
	end
	if root.Visible then
		closeReviewPanel("escape")
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
	local isTouch = input.UserInputType == Enum.UserInputType.Touch
	if not isClick and not isTouch then
		return
	end

	local pos = if isTouch then Vector2.new(input.Position.X, input.Position.Y) else UserInputService:GetMouseLocation()

	local plr = resolveClickedPlayer(pos)
	if not plr then
		return
	end

	openReviewPanel(plr)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if not root.Visible then
		return
	end
	if selectedTargetUserId == player.UserId then
		summaryLbl.TextColor3 = DANGER
		summaryLbl.Text = "This player left the game."
		local leftId = player.UserId
		task.delay(1.25, function()
			if selectedTargetUserId == leftId then
				closeReviewPanel("target_left")
			end
		end)
	end
end)
