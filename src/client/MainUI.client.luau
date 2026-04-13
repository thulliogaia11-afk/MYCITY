--[[
	MainUI — MY CITY
	Polished client HUD: top bar, bottom nav, modal panels, notifications.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig"))
print("[CLIENT] Remotes loaded successfully")

-- ——— Theme ———
local NAVY = Color3.fromHex("0f0f1a")
local ACCENT = Color3.fromHex("e94560")
local PANEL_BODY = Color3.fromHex("16213e")
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_MUTED = Color3.fromRGB(160, 165, 185)
local MONEY_GOLD = Color3.fromRGB(255, 214, 90)
local REP_BLUE = Color3.fromRGB(120, 200, 255)
local SUCCESS = Color3.fromRGB(60, 180, 110)
local DANGER = Color3.fromRGB(220, 70, 80)
local INFO = Color3.fromRGB(80, 160, 240)
local SILVER = Color3.fromRGB(195, 200, 210)
local GOLD_RANK = Color3.fromRGB(218, 180, 70)

local CORNER = UDim.new(0, 8)

local TIER_COLORS: { [string]: Color3 } = {
	Newcomer = Color3.fromRGB(120, 120, 125),
	Resident = Color3.fromRGB(60, 180, 90),
	Established = Color3.fromRGB(70, 130, 220),
	Respected = Color3.fromRGB(160, 90, 200),
	Influential = Color3.fromRGB(230, 140, 50),
	Elite = Color3.fromRGB(220, 60, 70),
	Legend = Color3.fromRGB(220, 180, 60),
}

local HOUSE_LEVEL_BORDER: { [number]: Color3 } = {
	[1] = Color3.fromRGB(120, 120, 125),
	[2] = Color3.fromRGB(70, 180, 110),
	[3] = Color3.fromRGB(70, 140, 230),
	[4] = GOLD_RANK,
}

local function tierFromReputation(score: number): string
	score = math.max(0, math.floor(score))
	if score < 50 then
		return "Newcomer"
	elseif score < 150 then
		return "Resident"
	elseif score < 300 then
		return "Established"
	elseif score < 500 then
		return "Respected"
	elseif score < 750 then
		return "Influential"
	elseif score < 1000 then
		return "Elite"
	else
		return "Legend"
	end
end

local isWorking = false

local function safeInvoke(rf: RemoteFunction, ...: any): any
	local ok, result = pcall(function(...)
		return rf:InvokeServer(...)
	end, ...)
	if ok then
		return result
	end
	warn("[MY CITY] Remote failed: ", result)
	return nil
end

-- ——— Root ———
-- Avoid duplicate HUDs (e.g. script re-run / hot reload) stacking nav buttons and click handlers.
local existingHud = PlayerGui:FindFirstChild("MyCityHUD")
if existingHud and existingHud:IsA("ScreenGui") then
	existingHud:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MyCityHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent = PlayerGui

-- Assigned after `showNotification` (needs toast). Forward-declared so housing buy handler can call safely.
local celebrateNewHome: ((string, number, number?) -> ())?

-- ——— Top bar (60px) ———
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.ZIndex = 10
topBar.Size = UDim2.new(1, 0, 0, 60)
topBar.BackgroundColor3 = NAVY
topBar.BorderSizePixel = 0
topBar.ClipsDescendants = false
topBar.Parent = screenGui

local topBarBorder = Instance.new("Frame")
topBarBorder.Name = "BottomAccent"
topBarBorder.ZIndex = 10
topBarBorder.Size = UDim2.new(1, 0, 0, 2)
topBarBorder.Position = UDim2.new(0, 0, 1, -2)
topBarBorder.BackgroundColor3 = ACCENT
topBarBorder.BorderSizePixel = 0
topBarBorder.Parent = topBar

-- Left: X=10, wide enough for avatar + name + tier badge in one row (no clipping)
local leftCluster = Instance.new("Frame")
leftCluster.Name = "LeftCluster"
leftCluster.ZIndex = 11
leftCluster.AnchorPoint = Vector2.new(0, 0)
leftCluster.Position = UDim2.new(0, 10, 0, 0)
leftCluster.Size = UDim2.new(0.44, -10, 1, 0)
leftCluster.BackgroundTransparency = 1
leftCluster.ClipsDescendants = false
leftCluster.Parent = topBar

local avatar = Instance.new("ImageLabel")
avatar.Name = "Avatar"
avatar.ZIndex = 11
avatar.Size = UDim2.new(0, 50, 0, 50)
avatar.AnchorPoint = Vector2.new(0, 0.5)
avatar.Position = UDim2.new(0, 0, 0.5, 0)
avatar.BackgroundColor3 = PANEL_BODY
avatar.BorderSizePixel = 0
avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150&", LocalPlayer.UserId)
avatar.Parent = leftCluster
local avc = Instance.new("UICorner")
avc.CornerRadius = UDim.new(1, 0)
avc.Parent = avatar
local avs = Instance.new("UIStroke")
avs.Color = ACCENT
avs.Thickness = 2
avs.Transparency = 0.3
avs.Parent = avatar

-- Name + tier badge side by side to the right of the avatar
local nameRow = Instance.new("Frame")
nameRow.Name = "NameRow"
nameRow.ZIndex = 11
nameRow.AnchorPoint = Vector2.new(0, 0.5)
nameRow.Position = UDim2.new(0, 58, 0.5, 0)
nameRow.Size = UDim2.new(1, -68, 0, 50)
nameRow.BackgroundTransparency = 1
nameRow.ClipsDescendants = false
nameRow.Parent = leftCluster

local nameRowLayout = Instance.new("UIListLayout")
nameRowLayout.FillDirection = Enum.FillDirection.Horizontal
nameRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
nameRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
nameRowLayout.Padding = UDim.new(0, 8)
nameRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
nameRowLayout.Parent = nameRow

-- Holds long names with ellipsis; scaled chunk of row leaves room for tier pill
local nameHolder = Instance.new("Frame")
nameHolder.Name = "NameHolder"
nameHolder.ZIndex = 11
nameHolder.BackgroundTransparency = 1
nameHolder.Size = UDim2.new(0.62, -8, 0, 24)
nameHolder.LayoutOrder = 1
nameHolder.ClipsDescendants = true
nameHolder.Parent = nameRow

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "PlayerName"
nameLabel.BackgroundTransparency = 1
nameLabel.Size = UDim2.new(1, 0, 1, 0)
nameLabel.Position = UDim2.new(0, 0, 0, 0)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 17
nameLabel.TextColor3 = TEXT_WHITE
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextYAlignment = Enum.TextYAlignment.Center
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.Text = LocalPlayer.DisplayName
nameLabel.Parent = nameHolder

local tierBadge = Instance.new("TextLabel")
tierBadge.Name = "TierBadge"
tierBadge.ZIndex = 11
tierBadge.Size = UDim2.new(0, 0, 0, 24)
tierBadge.AutomaticSize = Enum.AutomaticSize.X
tierBadge.BackgroundColor3 = TIER_COLORS.Newcomer
tierBadge.BorderSizePixel = 0
tierBadge.Font = Enum.Font.GothamBold
tierBadge.TextSize = 12
tierBadge.TextColor3 = TEXT_WHITE
tierBadge.TextXAlignment = Enum.TextXAlignment.Center
tierBadge.TextYAlignment = Enum.TextYAlignment.Center
tierBadge.Text = "Newcomer"
tierBadge.LayoutOrder = 2
tierBadge.Parent = nameRow
local tbPad = Instance.new("UIPadding")
tbPad.PaddingLeft = UDim.new(0, 10)
tbPad.PaddingRight = UDim.new(0, 10)
tbPad.PaddingTop = UDim.new(0, 4)
tbPad.PaddingBottom = UDim.new(0, 4)
tbPad.Parent = tierBadge
local tbc = Instance.new("UICorner")
tbc.CornerRadius = CORNER
tbc.Parent = tierBadge

-- Mayor ribbon (server sets PlayerData.MayorTitle when elected)
local mayorBadge = Instance.new("TextLabel")
mayorBadge.Name = "MayorBadge"
mayorBadge.ZIndex = 11
mayorBadge.AnchorPoint = Vector2.new(0, 1)
mayorBadge.Position = UDim2.new(0, 58, 1, -2)
mayorBadge.Size = UDim2.new(1, -68, 0, 16)
mayorBadge.BackgroundTransparency = 1
mayorBadge.Font = Enum.Font.GothamBold
mayorBadge.TextSize = 11
mayorBadge.TextColor3 = GOLD_RANK
mayorBadge.TextXAlignment = Enum.TextXAlignment.Left
mayorBadge.TextYAlignment = Enum.TextYAlignment.Bottom
mayorBadge.TextTruncate = Enum.TextTruncate.AtEnd
mayorBadge.Text = ""
mayorBadge.Visible = false
mayorBadge.Parent = leftCluster

local centerCluster = Instance.new("Frame")
centerCluster.Name = "CenterCluster"
centerCluster.ZIndex = 11
centerCluster.Size = UDim2.new(0.24, 0, 1, -8)
centerCluster.Position = UDim2.new(0.47, 0, 0, 4)
centerCluster.BackgroundTransparency = 1
centerCluster.ClipsDescendants = false
centerCluster.Parent = topBar

local cityTitle = Instance.new("TextLabel")
cityTitle.Name = "CityTitle"
cityTitle.ZIndex = 11
cityTitle.Size = UDim2.new(1, 0, 0, 28)
cityTitle.Position = UDim2.new(0, 0, 0, 6)
cityTitle.BackgroundTransparency = 1
cityTitle.Font = Enum.Font.GothamBold
cityTitle.TextSize = 22
cityTitle.TextColor3 = TEXT_WHITE
cityTitle.TextXAlignment = Enum.TextXAlignment.Center
cityTitle.Text = "🏙️ —"
cityTitle.Parent = centerCluster

local cityPop = Instance.new("TextLabel")
cityPop.Name = "CityPopulation"
cityPop.ZIndex = 11
cityPop.Size = UDim2.new(1, 0, 0, 18)
cityPop.Position = UDim2.new(0, 0, 0, 36)
cityPop.BackgroundTransparency = 1
cityPop.Font = Enum.Font.Gotham
cityPop.TextSize = 13
cityPop.TextColor3 = TEXT_MUTED
cityPop.TextXAlignment = Enum.TextXAlignment.Center
cityPop.Text = "Population —"
cityPop.Parent = centerCluster

local rightCluster = Instance.new("Frame")
rightCluster.Name = "RightCluster"
rightCluster.ZIndex = 11
rightCluster.Size = UDim2.new(0.28, -20, 1, 0)
rightCluster.Position = UDim2.new(1, -10, 0, 0)
rightCluster.AnchorPoint = Vector2.new(1, 0)
rightCluster.BackgroundTransparency = 1
rightCluster.ClipsDescendants = false
rightCluster.Parent = topBar

local moneyPill = Instance.new("TextLabel")
moneyPill.Name = "MoneyPill"
moneyPill.ZIndex = 12
moneyPill.Size = UDim2.new(0, 0, 0, 30)
moneyPill.Position = UDim2.new(1, 0, 0, 10)
moneyPill.AnchorPoint = Vector2.new(1, 0)
moneyPill.AutomaticSize = Enum.AutomaticSize.X
moneyPill.BackgroundColor3 = Color3.fromRGB(35, 32, 20)
moneyPill.BorderSizePixel = 0
moneyPill.Font = Enum.Font.GothamBold
moneyPill.TextSize = 15
moneyPill.TextColor3 = MONEY_GOLD
moneyPill.TextXAlignment = Enum.TextXAlignment.Center
moneyPill.Text = " 🪙 0 CC "
moneyPill.Parent = rightCluster
local mp = Instance.new("UIPadding")
mp.PaddingLeft = UDim.new(0, 12)
mp.PaddingRight = UDim.new(0, 12)
mp.Parent = moneyPill
local mpc = Instance.new("UICorner")
mpc.CornerRadius = CORNER
mpc.Parent = moneyPill

local repPill = Instance.new("TextLabel")
repPill.Name = "RepPill"
repPill.ZIndex = 12
repPill.Size = UDim2.new(0, 0, 0, 30)
repPill.AutomaticSize = Enum.AutomaticSize.X
repPill.BackgroundColor3 = Color3.fromRGB(22, 34, 52)
repPill.BorderSizePixel = 0
repPill.Font = Enum.Font.GothamBold
repPill.TextSize = 15
repPill.TextColor3 = REP_BLUE
repPill.TextXAlignment = Enum.TextXAlignment.Center
repPill.Text = " ⭐ 0 "
repPill.Parent = rightCluster
local rp = Instance.new("UIPadding")
rp.PaddingLeft = UDim.new(0, 12)
rp.PaddingRight = UDim.new(0, 12)
rp.Parent = repPill
local rpc = Instance.new("UICorner")
rpc.CornerRadius = CORNER
rpc.Parent = repPill

local function layoutRightPills()
	repPill.Position = UDim2.new(1, 0, 0, 10)
	repPill.AnchorPoint = Vector2.new(1, 0)
	moneyPill.Position = UDim2.new(1, -(repPill.AbsoluteSize.X + 10), 0, 10)
	moneyPill.AnchorPoint = Vector2.new(1, 0)
end

repPill:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRightPills)
moneyPill:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRightPills)

local function populationForCity(cityName: string): string
	if cityName == "—" or cityName == "None" then
		return "—"
	end
	local cities = safeInvoke(Remotes.GetCities)
	if typeof(cities) ~= "table" then
		return "—"
	end
	local info = cities[cityName]
	if typeof(info) == "table" then
		return tostring(info.Population or 0)
	end
	return "—"
end

local function refreshTopBar()
	local data = safeInvoke(Remotes.GetPlayerData)
	if typeof(data) ~= "table" then
		nameLabel.Text = LocalPlayer.DisplayName
		tierBadge.Text = "—"
		tierBadge.BackgroundColor3 = TIER_COLORS.Newcomer
		mayorBadge.Text = ""
		mayorBadge.Visible = false
		cityTitle.Text = "🏙️ —"
		cityPop.Text = "Population —"
		moneyPill.Text = " 🪙 — CC "
		repPill.Text = " ⭐ — "
		task.defer(layoutRightPills)
		return
	end

	local rep = data.Reputation or 0
	local mn = data.Money or 0
	local city = typeof(data.City) == "string" and data.City or "—"
	local tier = tierFromReputation(rep)
	local pop = populationForCity(city)

	nameLabel.Text = LocalPlayer.DisplayName
	tierBadge.Text = tier
	tierBadge.BackgroundColor3 = TIER_COLORS[tier] or TIER_COLORS.Newcomer

	local mtitle = typeof(data.MayorTitle) == "string" and data.MayorTitle or ""
	if #mtitle > 0 then
		mayorBadge.Text = mtitle
		mayorBadge.Visible = true
	else
		mayorBadge.Text = ""
		mayorBadge.Visible = false
	end

	cityTitle.Text = string.format("🏙️ %s", city)
	cityPop.Text = string.format("Population %s residents", pop)

	moneyPill.Text = string.format(" 🪙 %d CC ", mn)
	repPill.Text = string.format(" ⭐ %d ", rep)
	task.defer(layoutRightPills)
end

task.spawn(function()
	refreshTopBar()
	while screenGui.Parent do
		task.wait(5)
		refreshTopBar()
	end
end)

-- ——— Bottom nav (65px) ———
local bottomBar = Instance.new("Frame")
bottomBar.Name = "BottomBar"
bottomBar.Size = UDim2.new(1, 0, 0, 65)
bottomBar.Position = UDim2.new(0, 0, 1, -65)
bottomBar.BackgroundColor3 = NAVY
bottomBar.BorderSizePixel = 0
bottomBar.Parent = screenGui

local bottomTopBorder = Instance.new("Frame")
bottomTopBorder.Size = UDim2.new(1, 0, 0, 2)
bottomTopBorder.BackgroundColor3 = ACCENT
bottomTopBorder.BorderSizePixel = 0
bottomTopBorder.Parent = bottomBar

local navInner = Instance.new("Frame")
navInner.Name = "NavInner"
navInner.Size = UDim2.new(1, -24, 1, 0)
navInner.Position = UDim2.new(0, 12, 0, 0)
navInner.BackgroundTransparency = 1
navInner.Parent = bottomBar

local navLayout = Instance.new("UIListLayout")
navLayout.FillDirection = Enum.FillDirection.Horizontal
navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
navLayout.VerticalAlignment = Enum.VerticalAlignment.Center
navLayout.Padding = UDim.new(0, 8)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = navInner

local currentNavKey: string? = nil
local navButtons: { [string]: TextButton } = {}

local function updateNavVisual()
	for key, btn in navButtons do
		if key == currentNavKey then
			btn.BackgroundColor3 = ACCENT
		else
			btn.BackgroundColor3 = PANEL_BODY
		end
	end
end

local function styleNavButton(btn: TextButton, key: string)
	btn.Size = UDim2.new(0, 100, 0, 48)
	btn.BackgroundColor3 = PANEL_BODY
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.TextColor3 = TEXT_WHITE
	btn.AutoButtonColor = false
	btn.LayoutOrder = ({
		jobs = 1,
		housing = 2,
		city = 3,
		ranking = 4,
	})[key] or 0

	local c = Instance.new("UICorner")
	c.CornerRadius = CORNER
	c.Parent = btn

	local base = PANEL_BODY
	btn.MouseEnter:Connect(function()
		if currentNavKey ~= key then
			btn.BackgroundColor3 = ACCENT:Lerp(base, 0.65)
		end
	end)
	btn.MouseLeave:Connect(function()
		updateNavVisual()
	end)

	navButtons[key] = btn
end

-- ——— Panels layer & dimmer ———
local panelsLayer = Instance.new("Frame")
panelsLayer.Name = "Panels"
panelsLayer.Size = UDim2.new(1, 0, 1, 0)
panelsLayer.BackgroundTransparency = 1
panelsLayer.ZIndex = 5
panelsLayer.Parent = screenGui

local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.new(1, 0, 1, 0)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 1
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.Visible = false
dimmer.ZIndex = 5
dimmer.Parent = panelsLayer

local function applyCardShadow(frame: Frame)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.82
	stroke.Thickness = 1
	stroke.Parent = frame
end

local function tweenModalOpen(frame: Frame, uiScale: UIScale)
	frame.Visible = true
	uiScale.Scale = 0.92
	TweenService:Create(uiScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(dimmer, TweenInfo.new(0.2), { BackgroundTransparency = 0.55 }):Play()
	dimmer.Visible = true
end

local function tweenModalClose(frame: Frame, uiScale: UIScale, onDone: () -> ())
	TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.92 }):Play()
	local t = TweenService:Create(dimmer, TweenInfo.new(0.18), { BackgroundTransparency = 1 })
	t:Play()
	t.Completed:Connect(function()
		dimmer.Visible = false
		frame.Visible = false
		if onDone then
			onDone()
		end
	end)
end

type PanelBundle = {
	Frame: Frame,
	Close: TextButton,
	Scroll: ScrollingFrame,
	Scale: UIScale,
}

local function createModal(title: string, size: UDim2, headerEmoji: string): PanelBundle
	local panel = Instance.new("Frame")
	panel.Name = title:gsub("%s+", "")
	panel.Visible = false
	panel.Size = size
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = PANEL_BODY
	panel.BorderSizePixel = 0
	panel.ZIndex = 8
	panel.Parent = panelsLayer

	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local pc = Instance.new("UICorner")
	pc.CornerRadius = CORNER
	pc.Parent = panel

	local pst = Instance.new("UIStroke")
	pst.Color = ACCENT
	pst.Thickness = 1
	pst.Transparency = 0.4
	pst.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundColor3 = NAVY
	header.BorderSizePixel = 0
	header.ZIndex = 9
	header.Parent = panel
	local hc = Instance.new("UICorner")
	hc.CornerRadius = CORNER
	hc.Parent = header
	-- mask bottom corners of header by overlay body - use separate frame only top rounded
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 12)
	headerFix.Position = UDim2.new(0, 0, 1, -12)
	headerFix.BackgroundColor3 = NAVY
	headerFix.BorderSizePixel = 0
	headerFix.ZIndex = 9
	headerFix.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size = UDim2.new(1, -100, 1, 0)
	titleLbl.Position = UDim2.new(0, 16, 0, 0)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 20
	titleLbl.TextColor3 = TEXT_WHITE
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Text = headerEmoji .. " " .. title
	titleLbl.ZIndex = 10
	titleLbl.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 8)
	closeBtn.BackgroundColor3 = ACCENT
	closeBtn.TextColor3 = TEXT_WHITE
	closeBtn.Text = "✕"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 10
	closeBtn.Parent = header
	local closeC = Instance.new("UICorner")
	closeC.CornerRadius = CORNER
	closeC.Parent = closeBtn

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, -20, 1, -64)
	scroll.Position = UDim2.new(0, 10, 0, 58)
	scroll.BackgroundColor3 = Color3.fromRGB(18, 28, 48)
	scroll.BackgroundTransparency = 0.35
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = ACCENT
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 9
	scroll.Parent = panel
	local sc = Instance.new("UICorner")
	sc.CornerRadius = CORNER
	sc.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = scroll

	return { Frame = panel, Close = closeBtn, Scroll = scroll, Scale = scale }
end

local jobsBundle = createModal("Available Jobs", UDim2.new(0, 440, 0, 640), "💼")
local housingBundle = createModal("Housing Market", UDim2.new(0, 420, 0, 520), "🏠")
local rankingBundle = createModal("City Ranking", UDim2.new(0, 380, 0, 320), "🏆")
local cityBundle = createModal("Cities", UDim2.new(0, 420, 0, 520), "🏙️")

local jobsPanel, jobsClose, jobsScroll, jobsScale = jobsBundle.Frame, jobsBundle.Close, jobsBundle.Scroll, jobsBundle.Scale

-- Daily mission styling + job reviews overlay (inside Jobs modal)
local MISSION_BG = Color3.fromRGB(15, 15, 30)
local MISSION_BORDER = Color3.fromRGB(45, 50, 85)
local DISMISSAL_COOLDOWN_SEC = 518400

local JOB_ICONS: { [string]: string } = {
	["Street Cleaner"] = "🧹",
	["Factory Worker"] = "🏭",
	["Tour Guide"] = "🎟️",
	["Police Officer"] = "👮",
	["Firefighter"] = "🚒",
	["Doctor"] = "⚕️",
	["Nurse"] = "💉",
	["Teacher"] = "📚",
	["Security"] = "🛡️",
	["Electrician"] = "⚡",
}

local function isMayorJobTitle(job: string): boolean
	return string.sub(job, 1, 8) == "Mayor of"
end

local function secondsUntilMidnight(): number
	return 86400 - (os.time() % 86400)
end

local function formatCountdown(sec: number): string
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	return string.format("%dh %dm", h, m)
end

local jobsMissionHolder: Frame? = nil

local reviewsOverlay = Instance.new("Frame")
reviewsOverlay.Name = "JobReviewsOverlay"
reviewsOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
reviewsOverlay.BackgroundTransparency = 0.5
reviewsOverlay.Size = UDim2.new(1, 0, 1, 0)
reviewsOverlay.Visible = false
reviewsOverlay.ZIndex = 40
reviewsOverlay.Parent = jobsPanel

local reviewsCard = Instance.new("Frame")
reviewsCard.Name = "JobReviewsCard"
reviewsCard.AnchorPoint = Vector2.new(0.5, 0.5)
reviewsCard.Position = UDim2.new(0.5, 0, 0.5, 0)
reviewsCard.Size = UDim2.new(0, 360, 0, 300)
reviewsCard.BackgroundColor3 = MISSION_BG
reviewsCard.BorderSizePixel = 0
reviewsCard.ZIndex = 41
reviewsCard.Parent = reviewsOverlay
local reviewsCardCorner = Instance.new("UICorner")
reviewsCardCorner.CornerRadius = CORNER
reviewsCardCorner.Parent = reviewsCard
local reviewsCardStroke = Instance.new("UIStroke")
reviewsCardStroke.Color = MISSION_BORDER
reviewsCardStroke.Thickness = 1
reviewsCardStroke.Transparency = 0.35
reviewsCardStroke.Parent = reviewsCard

local reviewsTitleLbl = Instance.new("TextLabel")
reviewsTitleLbl.BackgroundTransparency = 1
reviewsTitleLbl.Position = UDim2.new(0, 14, 0, 10)
reviewsTitleLbl.Size = UDim2.new(1, -52, 0, 24)
reviewsTitleLbl.Font = Enum.Font.GothamBold
reviewsTitleLbl.TextSize = 16
reviewsTitleLbl.TextColor3 = TEXT_WHITE
reviewsTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
reviewsTitleLbl.Text = "⭐ Reviews"
reviewsTitleLbl.ZIndex = 42
reviewsTitleLbl.Parent = reviewsCard

local reviewsCloseBtn = Instance.new("TextButton")
reviewsCloseBtn.Size = UDim2.new(0, 32, 0, 32)
reviewsCloseBtn.Position = UDim2.new(1, -40, 0, 8)
reviewsCloseBtn.BackgroundColor3 = ACCENT
reviewsCloseBtn.TextColor3 = TEXT_WHITE
reviewsCloseBtn.Text = "✕"
reviewsCloseBtn.Font = Enum.Font.GothamBold
reviewsCloseBtn.TextSize = 15
reviewsCloseBtn.AutoButtonColor = false
reviewsCloseBtn.ZIndex = 42
reviewsCloseBtn.Parent = reviewsCard
local reviewsCloseCorner = Instance.new("UICorner")
reviewsCloseCorner.CornerRadius = CORNER
reviewsCloseCorner.Parent = reviewsCloseBtn

local reviewsScrollFrame = Instance.new("ScrollingFrame")
reviewsScrollFrame.Name = "ReviewsScroll"
reviewsScrollFrame.Position = UDim2.new(0, 10, 0, 44)
reviewsScrollFrame.Size = UDim2.new(1, -20, 1, -54)
reviewsScrollFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 26)
reviewsScrollFrame.BackgroundTransparency = 0.2
reviewsScrollFrame.BorderSizePixel = 0
reviewsScrollFrame.ScrollBarThickness = 5
reviewsScrollFrame.ScrollBarImageColor3 = ACCENT
reviewsScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
reviewsScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
reviewsScrollFrame.ZIndex = 42
reviewsScrollFrame.Parent = reviewsCard
local reviewsScrollCorner = Instance.new("UICorner")
reviewsScrollCorner.CornerRadius = CORNER
reviewsScrollCorner.Parent = reviewsScrollFrame
local reviewsPad = Instance.new("UIPadding")
reviewsPad.PaddingTop = UDim.new(0, 8)
reviewsPad.PaddingBottom = UDim.new(0, 8)
reviewsPad.PaddingLeft = UDim.new(0, 8)
reviewsPad.PaddingRight = UDim.new(0, 8)
reviewsPad.Parent = reviewsScrollFrame
local reviewsList = Instance.new("UIListLayout")
reviewsList.SortOrder = Enum.SortOrder.LayoutOrder
reviewsList.Padding = UDim.new(0, 8)
reviewsList.Parent = reviewsScrollFrame

local function closeJobsReviewsOverlay()
	reviewsOverlay.Visible = false
end

reviewsCloseBtn.MouseButton1Click:Connect(closeJobsReviewsOverlay)

local function populateJobsReviewsOverlay(targetUserId: number, displayName: string)
	for _, c in reviewsScrollFrame:GetChildren() do
		if c:IsA("GuiObject") and not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	reviewsTitleLbl.Text = "⭐ Reviews — " .. displayName

	local res = safeInvoke(Remotes.GetReviews, targetUserId)
	if typeof(res) ~= "table" or res.success ~= true then
		local err = Instance.new("TextLabel")
		err.BackgroundTransparency = 1
		err.Size = UDim2.new(1, 0, 0, 40)
		err.LayoutOrder = 0
		err.Font = Enum.Font.Gotham
		err.TextSize = 14
		err.TextColor3 = TEXT_MUTED
		err.TextWrapped = true
		err.Text = "Could not load reviews."
		err.ZIndex = 43
		err.Parent = reviewsScrollFrame
		reviewsOverlay.Visible = true
		return
	end

	local avg = typeof(res.averageRating) == "number" and res.averageRating or 0
	local avgLbl = Instance.new("TextLabel")
	avgLbl.BackgroundTransparency = 1
	avgLbl.Size = UDim2.new(1, 0, 0, 28)
	avgLbl.LayoutOrder = 0
	avgLbl.Font = Enum.Font.GothamBold
	avgLbl.TextSize = 18
	avgLbl.TextColor3 = GOLD_RANK
	avgLbl.TextXAlignment = Enum.TextXAlignment.Left
	avgLbl.Text = string.format("Average: %.1f ★", avg)
	avgLbl.ZIndex = 43
	avgLbl.Parent = reviewsScrollFrame

	local revList = if typeof(res.reviews) == "table" then res.reviews else {}
	local n = #revList
	local startIdx = math.max(1, n - 4)
	local lo = 1
	for i = startIdx, n do
		local r = revList[i]
		if typeof(r) ~= "table" then
			continue
		end
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundColor3 = Color3.fromRGB(22, 22, 42)
		row.BorderSizePixel = 0
		row.LayoutOrder = lo
		lo += 1
		row.ZIndex = 43
		row.Parent = reviewsScrollFrame
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 6)
		rc.Parent = row
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = row

		local nm = typeof((r :: any).reviewerName) == "string" and (r :: any).reviewerName or "Player"
		local st = typeof((r :: any).stars) == "number" and (r :: any).stars or 0
		local com = typeof((r :: any).comment) == "string" and (r :: any).comment or ""

		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1
		head.Size = UDim2.new(1, 0, 0, 20)
		head.Font = Enum.Font.GothamBold
		head.TextSize = 14
		head.TextColor3 = TEXT_WHITE
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.Text = string.format("%s · %d★", nm, st)
		head.Parent = row

		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Position = UDim2.new(0, 0, 0, 24)
		body.Size = UDim2.new(1, 0, 0, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Font = Enum.Font.Gotham
		body.TextSize = 13
		body.TextColor3 = TEXT_MUTED
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.Text = com ~= "" and com or "(no comment)"
		body.Parent = row
	end

	if n == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 32)
		empty.LayoutOrder = 2
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.TextColor3 = TEXT_MUTED
		empty.Text = "No reviews yet."
		empty.ZIndex = 43
		empty.Parent = reviewsScrollFrame
	end

	reviewsOverlay.Visible = true
end

local function fillDailyMissionSection(missionOuter: Frame, pdata: any, mpRes: any)
	for _, c in missionOuter:GetChildren() do
		c:Destroy()
	end

	local card = Instance.new("Frame")
	card.Name = "MissionCard"
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = MISSION_BG
	card.BorderSizePixel = 0
	card.Parent = missionOuter
	local cc = Instance.new("UICorner")
	cc.CornerRadius = CORNER
	cc.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = MISSION_BORDER
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = card

	local vlist = Instance.new("UIListLayout")
	vlist.SortOrder = Enum.SortOrder.LayoutOrder
	vlist.Padding = UDim.new(0, 8)
	vlist.Parent = card

	local sectionTitle = Instance.new("TextLabel")
	sectionTitle.BackgroundTransparency = 1
	sectionTitle.Size = UDim2.new(1, 0, 0, 22)
	sectionTitle.Font = Enum.Font.GothamBold
	sectionTitle.TextSize = 16
	sectionTitle.TextColor3 = TEXT_WHITE
	sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	sectionTitle.Text = "📋 My Mission"
	sectionTitle.LayoutOrder = 0
	sectionTitle.Parent = card

	local lo = 1
	local function pushLabel(text: string, color: Color3, size: number, bold: boolean)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, 0, 0, 0)
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		lbl.TextSize = size
		lbl.TextColor3 = color
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextWrapped = true
		lbl.Text = text
		lbl.LayoutOrder = lo
		lo += 1
		lbl.Parent = card
		return lbl
	end

	if typeof(mpRes) ~= "table" or mpRes.success ~= true then
		pushLabel("Could not load mission progress.", TEXT_MUTED, 14, false)
		return
	end

	local d = mpRes.data
	if typeof(d) ~= "table" then
		pushLabel("Could not load mission progress.", TEXT_MUTED, 14, false)
		return
	end

	local dismissedFrom = typeof(pdata) == "table" and typeof((pdata :: any).DismissedFrom) == "string" and (pdata :: any).DismissedFrom
		or ""
	local dismissalTime = if typeof(pdata) == "table" and typeof((pdata :: any).DismissalTime) == "number" then (pdata :: any).DismissalTime else 0
	local cooldownSec = typeof(d.dismissalCooldownSec) == "number" and d.dismissalCooldownSec or DISMISSAL_COOLDOWN_SEC

	if dismissedFrom ~= "" and dismissalTime > 0 then
		local elapsed = os.time() - dismissalTime
		if elapsed < cooldownSec then
			local days = math.max(1, math.ceil((cooldownSec - elapsed) / 86400))
			pushLabel("⛔ Dismissed from " .. dismissedFrom, DANGER, 15, true)
			pushLabel(string.format("Cooldown: %d day(s) remaining before you can return.", days), TEXT_MUTED, 13, false)
			return
		end
	end

	local jobKey = typeof(d.job) == "string" and d.job or "Unemployed"
	if jobKey == "Unemployed" or jobKey == "" then
		pushLabel("Get a job to receive daily missions!", TEXT_MUTED, 14, false)
		return
	end

	if isMayorJobTitle(jobKey) then
		pushLabel("Mayors do not have daily work missions here.", TEXT_MUTED, 14, false)
		return
	end

	local goal = typeof(d.goal) == "number" and d.goal or nil
	local task = typeof(d.task) == "string" and d.task or nil
	if not goal or not task then
		pushLabel("No daily mission for your current job.", TEXT_MUTED, 14, false)
		return
	end

	local todayKey = typeof(d.todayKey) == "number" and d.todayKey or 0
	local lastRewardDay = typeof(d.lastRewardDay) == "number" and d.lastRewardDay or 0
	local completed = typeof(d.completedToday) == "number" and d.completedToday or 0
	local streak = typeof(d.streakDays) == "number" and d.streakDays or 0
	local rewardMoney = typeof(d.rewardMoney) == "number" and d.rewardMoney or 0
	local rewardRep = typeof(d.rewardRep) == "number" and d.rewardRep or 0

	local icon = JOB_ICONS[jobKey] or "💼"
	pushLabel(string.format("%s %s", icon, jobKey), TEXT_WHITE, 17, true)
	pushLabel(task, TEXT_MUTED, 14, false)

	if lastRewardDay == todayKey and todayKey > 0 then
		local done = Instance.new("TextLabel")
		done.BackgroundTransparency = 1
		done.Size = UDim2.new(1, 0, 0, 26)
		done.Font = Enum.Font.GothamBold
		done.TextSize = 16
		done.TextColor3 = SUCCESS
		done.TextXAlignment = Enum.TextXAlignment.Left
		done.Text = "✅ Mission Complete!"
		done.LayoutOrder = lo
		lo += 1
		done.Parent = card

		pushLabel(string.format("🔥 %d day streak", streak), Color3.fromRGB(255, 140, 60), 15, true)

		local resetSec = secondsUntilMidnight()
		pushLabel("Resets in " .. formatCountdown(resetSec), TEXT_MUTED, 12, false)
		return
	end

	pushLabel(string.format("Reward: +%d CC +%d Rep on completion", rewardMoney, rewardRep), SUCCESS, 13, false)

	local barBg = Instance.new("Frame")
	barBg.Name = "MissionProgressBarBg"
	barBg.Size = UDim2.new(1, 0, 0, 14)
	barBg.BackgroundColor3 = Color3.fromRGB(30, 32, 55)
	barBg.BorderSizePixel = 0
	barBg.LayoutOrder = lo
	lo += 1
	barBg.Parent = card
	local barBgC = Instance.new("UICorner")
	barBgC.CornerRadius = UDim.new(0, 7)
	barBgC.Parent = barBg

	local fillW = if goal > 0 then math.clamp(completed / goal, 0, 1) else 0
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(fillW, 0, 1, 0)
	barFill.BackgroundColor3 = SUCCESS
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	local barFillC = Instance.new("UICorner")
	barFillC.CornerRadius = UDim.new(0, 7)
	barFillC.Parent = barFill

	pushLabel(string.format("%d / %d completed", completed, goal), TEXT_WHITE, 13, true)

	local resetSec = secondsUntilMidnight()
	pushLabel("Resets in " .. formatCountdown(resetSec), TEXT_MUTED, 12, false)

	local completeBtn = Instance.new("TextButton")
	completeBtn.Size = UDim2.new(1, 0, 0, 40)
	completeBtn.BackgroundColor3 = SUCCESS
	completeBtn.TextColor3 = TEXT_WHITE
	completeBtn.Font = Enum.Font.GothamBold
	completeBtn.TextSize = 15
	completeBtn.Text = "✅ Complete Mission"
	completeBtn.AutoButtonColor = false
	completeBtn.LayoutOrder = lo
	lo += 1
	completeBtn.Parent = card
	local cbc = Instance.new("UICorner")
	cbc.CornerRadius = CORNER
	cbc.Parent = completeBtn

	completeBtn.MouseButton1Click:Connect(function()
		safeInvoke(Remotes.CompleteMission, jobKey)
		local p2 = safeInvoke(Remotes.GetPlayerData)
		local m2 = safeInvoke(Remotes.GetMissionProgress)
		if jobsMissionHolder then
			fillDailyMissionSection(jobsMissionHolder :: Frame, p2, m2)
		end
	end)
end
local housingPanel, housingClose, housingScroll, housingScale =
	housingBundle.Frame, housingBundle.Close, housingBundle.Scroll, housingBundle.Scale
local rankingPanel, rankingClose, rankingScroll, rankingScale =
	rankingBundle.Frame, rankingBundle.Close, rankingBundle.Scroll, rankingBundle.Scale
local cityPanel, cityClose, cityScroll, cityScale = cityBundle.Frame, cityBundle.Close, cityBundle.Scroll, cityBundle.Scale

local allBundles = { jobsBundle, housingBundle, rankingBundle, cityBundle }

local function hideAllPanelsAnimated()
	closeJobsReviewsOverlay()
	for _, b in allBundles do
		if b.Frame.Visible then
			tweenModalClose(b.Frame, b.Scale, function() end)
		end
	end
	currentNavKey = nil
	updateNavVisual()
end

local function showPanelAnimated(bundle: PanelBundle, navKey: string)
	for _, b in allBundles do
		if b.Frame ~= bundle.Frame and b.Frame.Visible then
			tweenModalClose(b.Frame, b.Scale, function() end)
		end
	end
	currentNavKey = navKey
	updateNavVisual()
	task.defer(function()
		tweenModalOpen(bundle.Frame, bundle.Scale)
	end)
end

dimmer.MouseButton1Click:Connect(function()
	hideAllPanelsAnimated()
end)

local MY_HOUSE_TYPE_NAMES: { [number]: string } = {
	[1] = "Shared Room",
	[2] = "Studio Apartment",
	[3] = "Family House",
	[4] = "Luxury Villa",
}

local function findHouseModelFromPromptInstance(inst: Instance): Model?
	local current: Instance? = inst
	while current do
		if current:IsA("Model") then
			local hid = current:GetAttribute("HouseId")
			if typeof(hid) == "string" and hid ~= "" then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Name ~= "HousePrompt" then
		return
	end
	local model = findHouseModelFromPromptInstance(prompt)
	if not model then
		return
	end
	local oidRaw = model:GetAttribute("OwnerId")
	local oid = if typeof(oidRaw) == "number" then math.floor(oidRaw) elseif typeof(oidRaw) == "string" then tonumber(oidRaw) or 0 else 0
	if oid == LocalPlayer.UserId then
		prompt.ActionText = "Enter"
		prompt.ObjectText = "Your home"
	elseif oid == 0 then
		prompt.ActionText = "View"
		prompt.ObjectText = "Available home"
	else
		prompt.ActionText = "Private"
		prompt.ObjectText = "Someone else's home"
	end
end)

local function clearScroll(scroll: ScrollingFrame)
	for _, c in scroll:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not scroll:FindFirstChildOfClass("UIPadding") then
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = scroll
	end
	if not scroll:FindFirstChildOfClass("UIListLayout") then
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 10)
		list.Parent = scroll
	end
end

local function addHoverLift(card: Frame)
	card.Active = true
	local default = card.BackgroundColor3
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = default:Lerp(Color3.new(1, 1, 1), 0.06) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = default }):Play()
	end)
end

function populateJobs()
	closeJobsReviewsOverlay()
	clearScroll(jobsScroll)

	local missionHolder = Instance.new("Frame")
	missionHolder.Name = "DailyMissionSection"
	missionHolder.Size = UDim2.new(1, 0, 0, 0)
	missionHolder.AutomaticSize = Enum.AutomaticSize.Y
	missionHolder.BackgroundTransparency = 1
	missionHolder.LayoutOrder = 0
	missionHolder.Parent = jobsScroll
	jobsMissionHolder = missionHolder

	local missWait = Instance.new("TextLabel")
	missWait.BackgroundTransparency = 1
	missWait.Size = UDim2.new(1, 0, 0, 32)
	missWait.Font = Enum.Font.Gotham
	missWait.TextSize = 13
	missWait.TextColor3 = TEXT_MUTED
	missWait.TextXAlignment = Enum.TextXAlignment.Left
	missWait.Text = "Loading mission..."
	missWait.Parent = missionHolder

	local nextLayout = 1
	if isWorking then
		local banner = Instance.new("Frame")
		banner.Size = UDim2.new(1, 0, 0, 56)
		banner.BackgroundColor3 = Color3.fromRGB(50, 28, 32)
		banner.BorderSizePixel = 0
		banner.LayoutOrder = nextLayout
		nextLayout += 1
		banner.Parent = jobsScroll
		local bc = Instance.new("UICorner")
		bc.CornerRadius = CORNER
		bc.Parent = banner
		applyCardShadow(banner)
		local bs = Instance.new("UIStroke")
		bs.Color = DANGER
		bs.Transparency = 0.5
		bs.Parent = banner

		local stopBtn = Instance.new("TextButton")
		stopBtn.Size = UDim2.new(0, 138, 0, 38)
		stopBtn.Position = UDim2.new(1, -148, 0.5, 0)
		stopBtn.AnchorPoint = Vector2.new(0, 0.5)
		stopBtn.BackgroundColor3 = DANGER
		stopBtn.TextColor3 = TEXT_WHITE
		stopBtn.Font = Enum.Font.GothamBold
		stopBtn.TextSize = 14
		stopBtn.Text = "⏹ Stop Work"
		stopBtn.AutoButtonColor = false
		stopBtn.Parent = banner
		local sbc = Instance.new("UICorner")
		sbc.CornerRadius = CORNER
		sbc.Parent = stopBtn
		stopBtn.MouseButton1Click:Connect(function()
			safeInvoke(Remotes.StopWork)
			isWorking = false
			populateJobs()
		end)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -160, 1, 0)
		lbl.Position = UDim2.new(0, 14, 0, 0)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 15
		lbl.TextColor3 = TEXT_WHITE
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = "On shift — stop to switch jobs."
		lbl.Parent = banner
	end

	local loadingLbl = Instance.new("TextLabel")
	loadingLbl.Name = "PanelLoadingLabel"
	loadingLbl.BackgroundTransparency = 1
	loadingLbl.Size = UDim2.new(1, 0, 0, 36)
	loadingLbl.LayoutOrder = nextLayout
	loadingLbl.Font = Enum.Font.Gotham
	loadingLbl.TextSize = 14
	loadingLbl.TextColor3 = TEXT_MUTED
	loadingLbl.Text = "Loading jobs..."
	loadingLbl.Parent = jobsScroll

	task.spawn(function()
		local pdata = safeInvoke(Remotes.GetPlayerData)
		local mpRes = safeInvoke(Remotes.GetMissionProgress)
		if missWait.Parent then
			missWait:Destroy()
		end
		fillDailyMissionSection(missionHolder, pdata, mpRes)

		local ok, result = pcall(function()
			return Remotes.GetAvailableJobs:InvokeServer()
		end)

		if loadingLbl.Parent then
			loadingLbl:Destroy()
		end

		if not ok then
			print("[MY CITY CLIENT] GetAvailableJobs failed:", result)
			local msg = Instance.new("TextLabel")
			msg.BackgroundTransparency = 1
			msg.Size = UDim2.new(1, 0, 0, 28)
			msg.LayoutOrder = nextLayout
			msg.Text = "Could not load jobs."
			msg.Font = Enum.Font.Gotham
			msg.TextSize = 14
			msg.TextColor3 = TEXT_WHITE
			msg.Parent = jobsScroll
			return
		end

		print("[MY CITY CLIENT] Jobs received:", result and #result or "nil")

		if typeof(result) ~= "table" or result == nil then
			local bad = Instance.new("TextLabel")
			bad.BackgroundTransparency = 1
			bad.Size = UDim2.new(1, 0, 0, 28)
			bad.LayoutOrder = nextLayout
			bad.Text = "Could not load jobs."
			bad.Font = Enum.Font.Gotham
			bad.TextSize = 14
			bad.TextColor3 = TEXT_WHITE
			bad.Parent = jobsScroll
			return
		end

		if #result == 0 then
			local emptyMsg = Instance.new("TextLabel")
			emptyMsg.BackgroundTransparency = 1
			emptyMsg.Size = UDim2.new(1, 0, 0, 28)
			emptyMsg.LayoutOrder = nextLayout
			emptyMsg.Text = "No jobs available for you yet."
			emptyMsg.Font = Enum.Font.Gotham
			emptyMsg.TextSize = 14
			emptyMsg.TextColor3 = TEXT_MUTED
			emptyMsg.Parent = jobsScroll
			return
		end

		local layoutOrder = nextLayout
		for _, job in result do
			if typeof(job) ~= "table" then
				continue
			end

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 118)
			row.BackgroundColor3 = NAVY
			row.BorderSizePixel = 0
			row.LayoutOrder = layoutOrder
			layoutOrder += 1
			row.Parent = jobsScroll
			local rc = Instance.new("UICorner")
			rc.CornerRadius = CORNER
			rc.Parent = row
			applyCardShadow(row)
			addHoverLift(row)

			local jName = typeof(job.Name) == "string" and job.Name or "Job"
			local pay = job.BasePay or 0
			local dur = job.WorkDuration or 0
			local reqR = job.RequiredReputation or 0
			local curJob = typeof(pdata) == "table" and typeof((pdata :: any).Job) == "string" and (pdata :: any).Job or ""
			local titleRightPad = if curJob == jName and not isMayorJobTitle(curJob) then -230 else -150

			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, titleRightPad, 0, 22)
			t.Position = UDim2.new(0, 14, 0, 10)
			t.Font = Enum.Font.GothamBold
			t.TextSize = 17
			t.TextColor3 = TEXT_WHITE
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.Text = jName
			t.Parent = row

			local payLbl = Instance.new("TextLabel")
			payLbl.BackgroundTransparency = 1
			payLbl.Size = UDim2.new(1, titleRightPad, 0, 18)
			payLbl.Position = UDim2.new(0, 14, 0, 36)
			payLbl.Font = Enum.Font.GothamBold
			payLbl.TextSize = 14
			payLbl.TextColor3 = SUCCESS
			payLbl.TextXAlignment = Enum.TextXAlignment.Left
			payLbl.Text = string.format("💰 +%d CC / cycle", pay)
			payLbl.Parent = row

			local durLbl = Instance.new("TextLabel")
			durLbl.BackgroundTransparency = 1
			durLbl.Size = UDim2.new(1, titleRightPad, 0, 18)
			durLbl.Position = UDim2.new(0, 14, 0, 56)
			durLbl.Font = Enum.Font.Gotham
			durLbl.TextSize = 13
			durLbl.TextColor3 = TEXT_MUTED
			durLbl.TextXAlignment = Enum.TextXAlignment.Left
			durLbl.Text = string.format("⏱ %ds · ⭐ Req %d rep", dur, reqR)
			durLbl.Parent = row

			if curJob == jName and not isMayorJobTitle(curJob) then
				local revBtn = Instance.new("TextButton")
				revBtn.Size = UDim2.new(0, 108, 0, 30)
				revBtn.Position = UDim2.new(1, -118, 0, 8)
				revBtn.AnchorPoint = Vector2.new(0, 0)
				revBtn.BackgroundColor3 = Color3.fromRGB(55, 50, 90)
				revBtn.TextColor3 = TEXT_WHITE
				revBtn.Font = Enum.Font.GothamBold
				revBtn.TextSize = 12
				revBtn.Text = "⭐ Reviews"
				revBtn.AutoButtonColor = false
				revBtn.Parent = row
				local rbc = Instance.new("UICorner")
				rbc.CornerRadius = CORNER
				rbc.Parent = revBtn
				revBtn.MouseButton1Click:Connect(function()
					populateJobsReviewsOverlay(LocalPlayer.UserId, LocalPlayer.DisplayName)
				end)
			end

			if not isWorking then
				local action = Instance.new("TextButton")
				action.Size = UDim2.new(0, 128, 0, 38)
				action.Position = UDim2.new(1, -138, 1, -44)
				action.AnchorPoint = Vector2.new(0, 1)
				action.BackgroundColor3 = SUCCESS
				action.TextColor3 = TEXT_WHITE
				action.Font = Enum.Font.GothamBold
				action.TextSize = 14
				action.Text = "▶ Start Work"
				action.AutoButtonColor = false
				action.Parent = row
				local ac = Instance.new("UICorner")
				ac.CornerRadius = CORNER
				ac.Parent = action
				action.MouseButton1Click:Connect(function()
					local startOk = safeInvoke(Remotes.StartWork, jName)
					if startOk == true then
						isWorking = true
						populateJobs()
					end
				end)
			end
		end
	end)

end

local function addMyHouseSection(scroll: ScrollingFrame, pdata: any)
	local houseId = ""
	local hl = 0
	if typeof(pdata) == "table" then
		if typeof(pdata.HouseId) == "string" then
			houseId = pdata.HouseId
		end
		if typeof(pdata.HouseLevel) == "number" then
			hl = pdata.HouseLevel
		end
	end

	local card = Instance.new("Frame")
	card.Name = "MyHouseSection"
	card.LayoutOrder = 0
	card.Size = UDim2.new(1, 0, 0, 132)
	card.BackgroundColor3 = PANEL_BODY
	card.BorderSizePixel = 0
	card.Parent = scroll
	local cc = Instance.new("UICorner")
	cc.CornerRadius = CORNER
	cc.Parent = card
	applyCardShadow(card)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 10)
	title.Size = UDim2.new(1, -28, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = TEXT_WHITE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "My House"
	title.Parent = card

	local hasHome = hl >= 1 and hl <= 4 and houseId ~= ""
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 14, 0, 36)
	sub.Size = UDim2.new(1, -28, 0, 44)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 14
	sub.TextColor3 = TEXT_MUTED
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.TextWrapped = true
	if hasHome then
		local tierName = MY_HOUSE_TYPE_NAMES[hl] or ("Tier " .. tostring(hl))
		sub.Text = string.format("%s · %s", tierName, houseId)
	else
		sub.Text = "You don't own a house yet"
	end
	sub.Parent = card

	local goBtn = Instance.new("TextButton")
	goBtn.Name = "GoToMyHouse"
	goBtn.Size = UDim2.new(0, 160, 0, 36)
	goBtn.Position = UDim2.new(1, -174, 1, -46)
	goBtn.AnchorPoint = Vector2.new(0, 0)
	goBtn.BackgroundColor3 = hasHome and ACCENT or Color3.fromRGB(55, 55, 68)
	goBtn.TextColor3 = TEXT_WHITE
	goBtn.Font = Enum.Font.GothamBold
	goBtn.TextSize = 14
	goBtn.Text = "Go to my house"
	goBtn.AutoButtonColor = hasHome
	goBtn.Active = hasHome
	if not hasHome then
		goBtn.TextTransparency = 0.4
		goBtn.BackgroundTransparency = 0.35
	end
	goBtn.Parent = card
	local gbc = Instance.new("UICorner")
	gbc.CornerRadius = CORNER
	gbc.Parent = goBtn

	if hasHome then
		goBtn.MouseButton1Click:Connect(function()
			local okInvoke, a, b = pcall(function()
				return Remotes.EnterHouse:InvokeServer()
			end)
			if not okInvoke then
				warn("[MY CITY] EnterHouse invoke failed:", a)
				return
			end
			local success = a == true
			local msg = typeof(b) == "string" and b or nil
			if success then
				-- Server may fire ShowNotification; optional local feedback
			elseif msg then
				warn("[MY CITY] EnterHouse:", msg)
			end
		end)
	end
end

function populateHousing()
	clearScroll(housingScroll)

	local pdataEarly = safeInvoke(Remotes.GetPlayerData)
	addMyHouseSection(housingScroll, pdataEarly)

	local loadingLbl = Instance.new("TextLabel")
	loadingLbl.Name = "PanelLoadingLabel"
	loadingLbl.BackgroundTransparency = 1
	loadingLbl.Size = UDim2.new(1, 0, 0, 36)
	loadingLbl.LayoutOrder = 5
	loadingLbl.Font = Enum.Font.Gotham
	loadingLbl.TextSize = 14
	loadingLbl.TextColor3 = TEXT_MUTED
	loadingLbl.Text = "Loading housing..."
	loadingLbl.Parent = housingScroll

	task.spawn(function()
		local okHouses, houses = pcall(function()
			return Remotes.GetHouses:InvokeServer()
		end)

		if loadingLbl.Parent then
			loadingLbl:Destroy()
		end

		if not okHouses then
			print("[MY CITY CLIENT] GetHouses failed:", houses)
			local err = Instance.new("TextLabel")
			err.BackgroundTransparency = 1
			err.Size = UDim2.new(1, 0, 0, 28)
			err.LayoutOrder = 10
			err.Text = "Could not load housing."
			err.Font = Enum.Font.Gotham
			err.TextSize = 14
			err.TextColor3 = TEXT_WHITE
			err.Parent = housingScroll
			return
		end

		print("[MY CITY CLIENT] Houses received:", typeof(houses) == "table" and #houses or "nil")

		local pdata = safeInvoke(Remotes.GetPlayerData)
		local money = 0
		local rep = 0
		local currentLevel = 1
		if typeof(pdata) == "table" then
			money = pdata.Money or 0
			rep = pdata.Reputation or 0
			if typeof(pdata.HouseLevel) == "number" then
				currentLevel = pdata.HouseLevel
			end
		end

		if typeof(houses) ~= "table" or houses == nil then
			local err2 = Instance.new("TextLabel")
			err2.BackgroundTransparency = 1
			err2.Size = UDim2.new(1, 0, 0, 28)
			err2.LayoutOrder = 10
			err2.Text = "Could not load housing."
			err2.Font = Enum.Font.Gotham
			err2.TextSize = 14
			err2.TextColor3 = TEXT_WHITE
			err2.Parent = housingScroll
			return
		end

		if #houses == 0 then
			local emptyMsg = Instance.new("TextLabel")
			emptyMsg.BackgroundTransparency = 1
			emptyMsg.Size = UDim2.new(1, 0, 0, 28)
			emptyMsg.LayoutOrder = 10
			emptyMsg.Text = "No properties listed."
			emptyMsg.Font = Enum.Font.Gotham
			emptyMsg.TextSize = 14
			emptyMsg.TextColor3 = TEXT_MUTED
			emptyMsg.Parent = housingScroll
			return
		end

		local order = 1
		for _, house in houses do
			if typeof(house) ~= "table" then
				continue
			end

			local lvl = house.Level or 0
			local isCurrent = currentLevel == lvl
			local price = house.Price or 0
			local reqR = house.RequiredReputation or 0
			local canAfford = not isCurrent and money >= price and rep >= reqR and currentLevel < lvl

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 126)
			row.BackgroundColor3 = NAVY
			row.BorderSizePixel = 0
			row.LayoutOrder = order
			order += 1
			row.Parent = housingScroll
		local rc = Instance.new("UICorner")
		rc.CornerRadius = CORNER
		rc.Parent = row
		applyCardShadow(row)
		addHoverLift(row)

		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 4, 1, 0)
		strip.BackgroundColor3 = HOUSE_LEVEL_BORDER[lvl] or HOUSE_LEVEL_BORDER[1]
		strip.BorderSizePixel = 0
		strip.Parent = row
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(1, 0)
		sc.Parent = strip

		local nm = typeof(house.Name) == "string" and house.Name or "House"
		local inc = house.DailyIncome or 0

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, -160, 0, 24)
		t.Position = UDim2.new(0, 18, 0, 10)
		t.Font = Enum.Font.GothamBold
		t.TextSize = 17
		t.TextColor3 = TEXT_WHITE
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = nm
		t.Parent = row

		if isCurrent then
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(0, 0, 0, 22)
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.Position = UDim2.new(0, 18, 0, 38)
			badge.BackgroundColor3 = SUCCESS
			badge.BackgroundTransparency = 0.15
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 12
			badge.TextColor3 = TEXT_WHITE
			badge.Text = " ✓ Current "
			badge.Parent = row
			local bp = Instance.new("UIPadding")
			bp.PaddingLeft = UDim.new(0, 8)
			bp.PaddingRight = UDim.new(0, 8)
			bp.Parent = badge
			local bc = Instance.new("UICorner")
			bc.CornerRadius = CORNER
			bc.Parent = badge
		end

		local priceLbl = Instance.new("TextLabel")
		priceLbl.BackgroundTransparency = 1
		priceLbl.Size = UDim2.new(1, -160, 0, 18)
		priceLbl.Position = UDim2.new(0, 18, 0, isCurrent and 66 or 40)
		priceLbl.Font = Enum.Font.GothamBold
		priceLbl.TextSize = 14
		priceLbl.TextColor3 = MONEY_GOLD
		priceLbl.TextXAlignment = Enum.TextXAlignment.Left
		priceLbl.Text = string.format("Price %d CC", price)
		priceLbl.Parent = row

		local incLbl = Instance.new("TextLabel")
		incLbl.BackgroundTransparency = 1
		incLbl.Size = UDim2.new(1, -160, 0, 18)
		incLbl.Position = UDim2.new(0, 18, 0, isCurrent and 86 or 60)
		incLbl.Font = Enum.Font.Gotham
		incLbl.TextSize = 13
		incLbl.TextColor3 = SUCCESS
		incLbl.TextXAlignment = Enum.TextXAlignment.Left
		incLbl.Text = string.format("+%d CC / min passive", inc)
		incLbl.Parent = row

		local reqLbl = Instance.new("TextLabel")
		reqLbl.BackgroundTransparency = 1
		reqLbl.Size = UDim2.new(1, -160, 0, 18)
		reqLbl.Position = UDim2.new(0, 18, 0, isCurrent and 106 or 80)
		reqLbl.Font = Enum.Font.Gotham
		reqLbl.TextSize = 13
		reqLbl.TextColor3 = REP_BLUE
		reqLbl.TextXAlignment = Enum.TextXAlignment.Left
		reqLbl.Text = string.format("⭐ Requires %d reputation", reqR)
		reqLbl.Parent = row

		local buy = Instance.new("TextButton")
		buy.Size = UDim2.new(0, 96, 0, 38)
		buy.Position = UDim2.new(1, -106, 0.5, 0)
		buy.AnchorPoint = Vector2.new(0, 0.5)
		buy.BackgroundColor3 = isCurrent and PANEL_BODY or (canAfford and ACCENT or Color3.fromRGB(60, 60, 70))
		buy.TextColor3 = isCurrent and TEXT_MUTED or TEXT_WHITE
		buy.Font = Enum.Font.GothamBold
		buy.TextSize = 14
		buy.AutoButtonColor = false
		buy.Text = isCurrent and "Owned" or "Buy"
		buy.Active = canAfford and not isCurrent
		if not canAfford and not isCurrent then
			buy.TextTransparency = 0.35
			buy.BackgroundTransparency = 0.45
		end
		buy.Parent = row
		local bc2 = Instance.new("UICorner")
		bc2.CornerRadius = CORNER
		bc2.Parent = buy

		if canAfford then
			buy.MouseButton1Click:Connect(function()
				local ok = safeInvoke(Remotes.BuyHouse, lvl)
				if ok == true then
					local houseName = typeof(house.Name) == "string" and house.Name or "House"
					if celebrateNewHome then
						celebrateNewHome(houseName, lvl, inc)
					end
					populateHousing()
					refreshTopBar()
				end
			end)
		end
	end
	end)

end

function populateRanking()
	clearScroll(rankingScroll)

	local rows = safeInvoke(Remotes.GetRanking)
	local cities = safeInvoke(Remotes.GetCities)
	if typeof(rows) ~= "table" then
		return
	end

	local order = 0
	for _, row in rows do
		if typeof(row) ~= "table" then
			continue
		end

		local pos = row.Position or 0
		local cname = typeof(row.CityName) == "string" and row.CityName or "?"
		local sc = row.Score or 0
		local isFirst = pos == 1
		local isSecond = pos == 2

		local popStr = "—"
		if typeof(cities) == "table" then
			local inf = cities[cname]
			if typeof(inf) == "table" then
				popStr = tostring(inf.Population or 0)
			end
		end

		local fr = Instance.new("Frame")
		fr.Size = UDim2.new(1, 0, 0, 96)
		fr.BorderSizePixel = 0
		fr.LayoutOrder = order
		order += 1
		fr.ClipsDescendants = true

		if isFirst then
			fr.BackgroundColor3 = GOLD_RANK
			fr.BackgroundTransparency = 0.55
		elseif isSecond then
			fr.BackgroundColor3 = SILVER
			fr.BackgroundTransparency = 0.65
		else
			fr.BackgroundColor3 = NAVY
		end

		fr.Parent = rankingScroll
		local uic = Instance.new("UICorner")
		uic.CornerRadius = CORNER
		uic.Parent = fr
		applyCardShadow(fr)

		local crown = isFirst and "👑 " or ""
		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -24, 0, 26)
		nameLbl.Position = UDim2.new(0, 14, 0, 10)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 18
		nameLbl.TextColor3 = isFirst and TEXT_WHITE or TEXT_WHITE
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = string.format("%s#%d  %s%s", crown, pos, cname, isFirst and "  Leader" or "")
		nameLbl.Parent = fr

		local scoreLbl = Instance.new("TextLabel")
		scoreLbl.BackgroundTransparency = 1
		scoreLbl.Size = UDim2.new(1, -24, 0, 34)
		scoreLbl.Position = UDim2.new(0, 14, 0, 38)
		scoreLbl.Font = Enum.Font.GothamBold
		scoreLbl.TextSize = 28
		scoreLbl.TextColor3 = isFirst and MONEY_GOLD or TEXT_WHITE
		scoreLbl.TextXAlignment = Enum.TextXAlignment.Left
		scoreLbl.Text = tostring(sc) .. " pts"
		scoreLbl.Parent = fr

		local popLbl = Instance.new("TextLabel")
		popLbl.BackgroundTransparency = 1
		popLbl.Size = UDim2.new(1, -24, 0, 18)
		popLbl.Position = UDim2.new(0, 14, 0, 74)
		popLbl.Font = Enum.Font.Gotham
		popLbl.TextSize = 13
		popLbl.TextColor3 = TEXT_MUTED
		popLbl.TextXAlignment = Enum.TextXAlignment.Left
		popLbl.Text = string.format("Population %s", popStr)
		popLbl.Parent = fr
	end
end

function populateCities()
	clearScroll(cityScroll)

	local pdata = safeInvoke(Remotes.GetPlayerData)
	local myCity = "None"
	if typeof(pdata) == "table" and typeof(pdata.City) == "string" then
		myCity = pdata.City
	end

	local cities = safeInvoke(Remotes.GetCities)
	if typeof(cities) ~= "table" then
		return
	end

	local order = 0
	for cityName, info in cities do
		if typeof(info) ~= "table" then
			continue
		end

		local isHere = myCity == cityName
		local pop = info.Population or 0
		local desc = typeof(info.Description) == "string" and info.Description or ""

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 104)
		row.BackgroundColor3 = NAVY
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		order += 1
		row.Parent = cityScroll
		local rc = Instance.new("UICorner")
		rc.CornerRadius = CORNER
		rc.Parent = row
		applyCardShadow(row)
		if isHere then
			local hl = Instance.new("UIStroke")
			hl.Color = SUCCESS
			hl.Thickness = 2
			hl.Parent = row
		end
		addHoverLift(row)

		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, -130, 0, 24)
		t.Position = UDim2.new(0, 14, 0, 10)
		t.Font = Enum.Font.GothamBold
		t.TextSize = 17
		t.TextColor3 = TEXT_WHITE
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = (typeof(cityName) == "string" and cityName or "?")
			.. (isHere and "  · You are here" or "")
		t.Parent = row

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(1, -130, 0, 52)
		sub.Position = UDim2.new(0, 14, 0, 36)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 12
		sub.TextColor3 = TEXT_MUTED
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextWrapped = true
		sub.Text = string.format("Population %d · %s", pop, desc)
		sub.Parent = row

		local join = Instance.new("TextButton")
		join.Size = UDim2.new(0, 92, 0, 36)
		join.Position = UDim2.new(1, -102, 0.5, 0)
		join.AnchorPoint = Vector2.new(0, 0.5)
		join.BackgroundColor3 = isHere and PANEL_BODY or ACCENT
		join.TextColor3 = TEXT_WHITE
		join.Font = Enum.Font.GothamBold
		join.TextSize = 13
		join.AutoButtonColor = false
		join.Text = isHere and "Here" or "Join"
		join.Parent = row
		local jc = Instance.new("UICorner")
		jc.CornerRadius = CORNER
		jc.Parent = join

		if not isHere then
			local nameStr = typeof(cityName) == "string" and cityName or ""
			join.MouseButton1Click:Connect(function()
				local ok = safeInvoke(Remotes.JoinCity, nameStr)
				if ok == true then
					refreshTopBar()
					populateCities()
				end
			end)
		end
	end
end

-- ——— Nav wiring ———
local function addNavButton(key: string, label: string, open: () -> ())
	-- Each key must map to exactly one nav button; destroy stale instance before re-wiring.
	local prev = navButtons[key]
	if prev then
		prev:Destroy()
	end
	navButtons[key] = nil

	local b = Instance.new("TextButton")
	b.Name = "Nav_" .. key
	b.Text = label
	styleNavButton(b, key)
	b.Activated:Connect(function()
		open()
	end)
	b.Parent = navInner
end

addNavButton("jobs", "💼 Jobs", function()
	print("[CLIENT] Opening jobs panel")
	local ok, result = pcall(function()
		return Remotes.GetAvailableJobs:InvokeServer()
	end)
	print("[CLIENT] GetAvailableJobs result:", ok, result)
	showPanelAnimated(jobsBundle, "jobs")
	populateJobs()
end)
addNavButton("housing", "🏠 Housing", function()
	showPanelAnimated(housingBundle, "housing")
	populateHousing()
end)
addNavButton("city", "🏙️ City", function()
	showPanelAnimated(cityBundle, "city")
	populateCities()
end)
addNavButton("ranking", "🏆 Ranking", function()
	showPanelAnimated(rankingBundle, "ranking")
	populateRanking()
end)

local function layoutNavButtons()
	local w = math.max(0, navInner.AbsoluteSize.X)
	local count = 4
	local pad = 8
	local each = math.floor((w - pad * (count - 1)) / count)
	for _, child in navInner:GetChildren() do
		if child:IsA("TextButton") then
			child.Size = UDim2.new(0, math.max(72, each), 0, 48)
		end
	end
end
navInner:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutNavButtons)
task.defer(layoutNavButtons)

local function closeBundle(bundle: PanelBundle)
	tweenModalClose(bundle.Frame, bundle.Scale, function()
		currentNavKey = nil
		updateNavVisual()
	end)
end

jobsClose.MouseButton1Click:Connect(function()
	closeJobsReviewsOverlay()
	closeBundle(jobsBundle)
end)
housingClose.MouseButton1Click:Connect(function()
	closeBundle(housingBundle)
end)
rankingClose.MouseButton1Click:Connect(function()
	closeBundle(rankingBundle)
end)
cityClose.MouseButton1Click:Connect(function()
	closeBundle(cityBundle)
end)

-- ——— Notifications ———
local notifHost = Instance.new("Frame")
notifHost.Name = "Notifications"
notifHost.Size = UDim2.new(1, 0, 0, 100)
notifHost.Position = UDim2.new(0, 0, 0, 68)
notifHost.BackgroundTransparency = 1
notifHost.ZIndex = 20
notifHost.Parent = screenGui

local activeNotifCleanup: (() -> ())? = nil

local function showNotification(message: string, kind: string?)
	local k = (kind and string.lower(kind)) or "info"
	local s = tostring(message)
	if k == "info" then
		if string.sub(s, 1, 7) == "[ERROR]" then
			k = "error"
			s = string.gsub(s, "^%[ERROR%]%s*", "")
		elseif string.sub(s, 1, 9) == "[SUCCESS]" then
			k = "success"
			s = string.gsub(s, "^%[SUCCESS%]%s*", "")
		elseif string.sub(s, 1, 6) == "[INFO]" then
			s = string.gsub(s, "^%[INFO%]%s*", "")
		end
	end

	if activeNotifCleanup then
		activeNotifCleanup()
		activeNotifCleanup = nil
	end

	for _, c in notifHost:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end

	local bgCol = INFO
	if k == "success" then
		bgCol = SUCCESS
	elseif k == "error" then
		bgCol = DANGER
	end

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 440, 0, 44)
	lbl.Position = UDim2.new(0.5, 0, 0, -80)
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.BackgroundColor3 = bgCol
	lbl.BackgroundTransparency = 0.12
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 15
	lbl.TextColor3 = TEXT_WHITE
	lbl.Text = s
	lbl.TextWrapped = true
	lbl.ZIndex = 21
	lbl.Parent = notifHost

	local lblC = Instance.new("UICorner")
	lblC.CornerRadius = UDim.new(1, 0)
	lblC.Parent = lbl
	local lst = Instance.new("UIStroke")
	lst.Color = Color3.new(1, 1, 1)
	lst.Transparency = 0.85
	lst.Parent = lbl

	lbl.TextTransparency = 0
	lbl.BackgroundTransparency = 0.12

	local slide = TweenService:Create(
		lbl,
		TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 0) }
	)
	slide:Play()

	task.wait(3)

	local fade = TweenService:Create(
		lbl,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, BackgroundTransparency = 1 }
	)
	local fadeStroke = TweenService:Create(lst, TweenInfo.new(0.35), { Transparency = 1 })
	local slideUp = TweenService:Create(
		lbl,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0, -64) }
	)

	activeNotifCleanup = function()
		fade:Cancel()
		fadeStroke:Cancel()
		slideUp:Cancel()
	end

	fade:Play()
	fadeStroke:Play()
	slideUp:Play()
	fade.Completed:Connect(function()
		if lbl.Parent then
			lbl:Destroy()
		end
		activeNotifCleanup = nil
	end)
end

local CELEBRATION_HOUSE_LINE: { [number]: { display: string, color: Color3 } } = {
	[1] = { display = "Shared Room", color = Color3.fromRGB(150, 152, 160) },
	[2] = { display = "Studio Apartment", color = Color3.fromRGB(70, 190, 115) },
	[3] = { display = "Family House", color = Color3.fromRGB(85, 165, 255) },
	[4] = { display = "💎 Luxury Villa", color = MONEY_GOLD },
}

celebrateNewHome = function(houseName: string, houseLevel: number, passiveIncomePerMin: number?)
	print("[CLIENT] Showing celebration for:", houseName)

	local existing = screenGui:FindFirstChild("PropertyPurchaseCelebration")
	if existing then
		existing:Destroy()
	end

	task.spawn(showNotification, "🎉 Property purchased!", "success")

	local passive = passiveIncomePerMin or 0
	local houseLine = CELEBRATION_HOUSE_LINE[houseLevel]
		or { display = MY_HOUSE_TYPE_NAMES[houseLevel] or ("Tier " .. tostring(houseLevel)), color = TEXT_WHITE }

	local overlay = Instance.new("Frame")
	overlay.Name = "PropertyPurchaseCelebration"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.new()
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 100
	overlay.Active = true
	overlay.Parent = screenGui

	TweenService:Create(overlay, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.5,
	}):Play()

	local panel = Instance.new("Frame")
	panel.Name = "CelebrationPanel"
	panel.Size = UDim2.fromOffset(500, 400)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 1.22, 0)
	panel.BackgroundColor3 = PANEL_BODY
	panel.BorderSizePixel = 0
	panel.ZIndex = 101
	panel.Parent = overlay

	local pc = Instance.new("UICorner")
	pc.CornerRadius = CORNER
	pc.Parent = panel

	local pst = Instance.new("UIStroke")
	pst.Color = MONEY_GOLD
	pst.Thickness = 2
	pst.Transparency = 0.35
	pst.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 20)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 22)
	pad.PaddingRight = UDim.new(0, 22)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	local emoji = Instance.new("TextLabel")
	emoji.BackgroundTransparency = 1
	emoji.Size = UDim2.new(1, 0, 0, 56)
	emoji.Font = Enum.Font.GothamBold
	emoji.TextSize = 48
	emoji.Text = "🎉"
	emoji.LayoutOrder = 1
	emoji.Parent = panel

	local congrats = Instance.new("TextLabel")
	congrats.BackgroundTransparency = 1
	congrats.Size = UDim2.new(1, 0, 0, 32)
	congrats.Font = Enum.Font.GothamBold
	congrats.TextSize = 26
	congrats.TextColor3 = MONEY_GOLD
	congrats.Text = "CONGRATULATIONS!"
	congrats.LayoutOrder = 2
	congrats.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 15
	subtitle.TextColor3 = TEXT_WHITE
	subtitle.Text = "You are now the proud owner of:"
	subtitle.LayoutOrder = 3
	subtitle.Parent = panel

	local houseTitleLbl = Instance.new("TextLabel")
	houseTitleLbl.BackgroundTransparency = 1
	houseTitleLbl.Size = UDim2.new(1, 0, 0, 44)
	houseTitleLbl.Font = Enum.Font.GothamBold
	houseTitleLbl.TextSize = 28
	houseTitleLbl.TextColor3 = houseLine.color
	houseTitleLbl.Text = houseName
	houseTitleLbl.LayoutOrder = 4
	houseTitleLbl.Parent = panel

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, 0, 0, 88)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 14
	desc.TextColor3 = TEXT_MUTED
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextXAlignment = Enum.TextXAlignment.Center
	desc.Text = string.format(
		"Your property earns passive income: +%d CC per minute while you play. Reputation grows with city life — upgrade again when you meet the next tier's requirements. Use Housing or your door prompt anytime to go home.",
		passive
	)
	desc.LayoutOrder = 5
	desc.Parent = panel

	local spacer = Instance.new("Frame")
	spacer.Size = UDim2.new(1, 0, 0, 4)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 6
	spacer.Parent = panel

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Size = UDim2.new(1, 0, 0, 44)
	btnRow.LayoutOrder = 7
	btnRow.Parent = panel

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	btnLayout.Padding = UDim.new(0, 12)
	btnLayout.Parent = btnRow

	local visitBtn = Instance.new("TextButton")
	visitBtn.Size = UDim2.fromOffset(220, 40)
	visitBtn.BackgroundColor3 = ACCENT
	visitBtn.TextColor3 = TEXT_WHITE
	visitBtn.Font = Enum.Font.GothamBold
	visitBtn.TextSize = 14
	visitBtn.Text = "🏠 Visit My New Home"
	visitBtn.AutoButtonColor = false
	visitBtn.ZIndex = 102
	visitBtn.Parent = btnRow
	local vbc = Instance.new("UICorner")
	vbc.CornerRadius = CORNER
	vbc.Parent = visitBtn

	local continueBtn = Instance.new("TextButton")
	continueBtn.Size = UDim2.fromOffset(120, 40)
	continueBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 80)
	continueBtn.TextColor3 = TEXT_WHITE
	continueBtn.Font = Enum.Font.GothamBold
	continueBtn.TextSize = 14
	continueBtn.Text = "Continue"
	continueBtn.AutoButtonColor = false
	continueBtn.ZIndex = 102
	continueBtn.Parent = btnRow
	local cbc = Instance.new("UICorner")
	cbc.CornerRadius = CORNER
	cbc.Parent = continueBtn

	local closed = false
	local function finishClose()
		if closed then
			return
		end
		closed = true
		TweenService:Create(
			panel,
			TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 1.22, 0) }
		):Play()
		local fo = TweenService:Create(
			overlay,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		fo:Play()
		fo.Completed:Connect(function()
			if overlay.Parent then
				overlay:Destroy()
			end
		end)
	end

	TweenService:Create(
		panel,
		TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.5, 0) }
	):Play()

	visitBtn.MouseButton1Click:Connect(function()
		if closed then
			return
		end
		pcall(function()
			Remotes.EnterHouse:InvokeServer()
		end)
		finishClose()
	end)
	continueBtn.MouseButton1Click:Connect(finishClose)

	task.delay(10, function()
		if overlay.Parent and not closed then
			finishClose()
		end
	end)
end

Remotes.ShowNotification.OnClientEvent:Connect(function(msg, kind)
	task.spawn(showNotification, msg, kind)
end)

-- ——— World missions (server pushes to matching job only) ———
local activeWorldMissionPanel: Frame? = nil

local function dismissWorldMissionPanel()
	if activeWorldMissionPanel and activeWorldMissionPanel.Parent then
		activeWorldMissionPanel:Destroy()
	end
	activeWorldMissionPanel = nil
end

local function showMissionResultPanel(titleText: string, subText: string, bgColor: Color3, durationSec: number)
	local existing = screenGui:FindFirstChild("WorldMissionResultPanel")
	if existing then
		existing:Destroy()
	end

	local panel = Instance.new("Frame")
	panel.Name = "WorldMissionResultPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -100)
	panel.Size = UDim2.fromOffset(420, 120)
	panel.BackgroundColor3 = bgColor
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.ZIndex = 45
	panel.Parent = screenGui

	local pc = Instance.new("UICorner")
	pc.CornerRadius = CORNER
	pc.Parent = panel

	local pst = Instance.new("UIStroke")
	pst.Color = Color3.new(1, 1, 1)
	pst.Transparency = 0.75
	pst.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size = UDim2.new(1, 0, 0, 36)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 20
	titleLbl.TextColor3 = TEXT_WHITE
	titleLbl.Text = titleText
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = panel

	local subLbl = Instance.new("TextLabel")
	subLbl.BackgroundTransparency = 1
	subLbl.Position = UDim2.fromOffset(0, 40)
	subLbl.Size = UDim2.new(1, 0, 0, 56)
	subLbl.Font = Enum.Font.GothamMedium
	subLbl.TextSize = 16
	subLbl.TextColor3 = TEXT_WHITE
	subLbl.TextWrapped = true
	subLbl.Text = subText
	subLbl.TextXAlignment = Enum.TextXAlignment.Left
	subLbl.TextYAlignment = Enum.TextYAlignment.Top
	subLbl.Parent = panel

	panel.Size = UDim2.fromOffset(420, 40)
	TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(420, 120),
	}):Play()

	task.delay(durationSec, function()
		if panel.Parent then
			TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(titleLbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			TweenService:Create(subLbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.32)
			if panel.Parent then
				panel:Destroy()
			end
		end
	end)
end

Remotes.MissionAvailable.OnClientEvent:Connect(function(missionData: any)
	if typeof(missionData) ~= "table" then
		return
	end
	local title = typeof(missionData.title) == "string" and missionData.title or "Mission"
	local loc = typeof(missionData.locationName) == "string" and missionData.locationName or "?"
	local desc = typeof(missionData.description) == "string" and missionData.description or ""
	local rw = typeof(missionData.reward) == "table" and missionData.reward or {}
	local money = typeof(rw.money) == "number" and rw.money or 0
	local rep = typeof(rw.rep) == "number" and rw.rep or 0

	task.spawn(showNotification, "🚨 New Mission Available: " .. title .. " at " .. loc, "info")

	dismissWorldMissionPanel()

	local panel = Instance.new("Frame")
	panel.Name = "WorldMissionOfferPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -20)
	panel.Size = UDim2.fromOffset(300, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL_BODY
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.ZIndex = 40
	panel.Parent = screenGui

	local pc = Instance.new("UICorner")
	pc.CornerRadius = CORNER
	pc.Parent = panel

	local pst = Instance.new("UIStroke")
	pst.Color = ACCENT
	pst.Transparency = 0.5
	pst.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local h = Instance.new("TextLabel")
	h.BackgroundTransparency = 1
	h.Size = UDim2.new(1, 0, 0, 22)
	h.Font = Enum.Font.GothamBold
	h.TextSize = 15
	h.TextColor3 = ACCENT
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Text = "New mission"
	h.LayoutOrder = 1
	h.Parent = panel

	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 40)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 16
	t.TextColor3 = TEXT_WHITE
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = title
	t.LayoutOrder = 2
	t.Parent = panel

	local d = Instance.new("TextLabel")
	d.BackgroundTransparency = 1
	d.Size = UDim2.new(1, 0, 0, 48)
	d.Font = Enum.Font.GothamMedium
	d.TextSize = 13
	d.TextColor3 = TEXT_MUTED
	d.TextWrapped = true
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.Text = desc
	d.LayoutOrder = 3
	d.Parent = panel

	local r = Instance.new("TextLabel")
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, 20)
	r.Font = Enum.Font.GothamMedium
	r.TextSize = 13
	r.TextColor3 = MONEY_GOLD
	r.TextXAlignment = Enum.TextXAlignment.Left
	r.Text = string.format("Reward: %d CC · %d Rep", money, rep)
	r.LayoutOrder = 4
	r.Parent = panel

	local go = Instance.new("TextLabel")
	go.BackgroundTransparency = 1
	go.Size = UDim2.new(1, 0, 0, 18)
	go.Font = Enum.Font.GothamMedium
	go.TextSize = 12
	go.TextColor3 = REP_BLUE
	go.TextXAlignment = Enum.TextXAlignment.Left
	go.Text = "Go to the glowing marker on the map"
	go.LayoutOrder = 5
	go.Parent = panel

	activeWorldMissionPanel = panel
	panel.Position = UDim2.new(1, -16, 1, 40)
	TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -16, 1, -20),
	}):Play()

	task.delay(30, function()
		if activeWorldMissionPanel == panel and panel.Parent then
			TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(1, 300, 1, -20),
				BackgroundTransparency = 1,
			}):Play()
			task.wait(0.36)
			dismissWorldMissionPanel()
		end
	end)
end)

Remotes.MissionCompleted.OnClientEvent:Connect(function(missionData: any)
	if typeof(missionData) ~= "table" then
		return
	end
	local title = typeof(missionData.title) == "string" and missionData.title or "Mission"
	local money = typeof(missionData.money) == "number" and missionData.money or 0
	local rep = typeof(missionData.rep) == "number" and missionData.rep or 0
	dismissWorldMissionPanel()
	showMissionResultPanel(
		"✅ MISSION COMPLETE!",
		string.format("%s\n+%d CC  +%d Rep", title, money, rep),
		SUCCESS,
		3
	)
end)

Remotes.MissionExpired.OnClientEvent:Connect(function(missionData: any)
	if typeof(missionData) ~= "table" then
		return
	end
	local title = typeof(missionData.title) == "string" and missionData.title or "Mission"
	dismissWorldMissionPanel()
	showMissionResultPanel("⏰ Mission expired", title, DANGER, 3)
end)

task.defer(layoutRightPills)
refreshTopBar()
