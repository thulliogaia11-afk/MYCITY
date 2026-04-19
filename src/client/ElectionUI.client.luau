--[[
	ElectionUI — MY CITY
	Election panel: status, candidates, nominate (RemoteFunctions + dark theme).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local BG = Color3.fromRGB(15, 15, 30)
local ACCENT = Color3.fromRGB(232, 69, 96)
local GOLD = Color3.fromRGB(255, 215, 0)
local TEXT = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(160, 165, 185)
local BUTTON_NAVY = Color3.fromRGB(30, 30, 60)
local CARD_BG = Color3.fromRGB(25, 25, 45)
-- Match server TESTING value (ElectionService MIN_REPUTATION_TO_NOMINATE).
local MIN_REP_NOMINATE = 0
local MAX_CAMPAIGN_CHARS = 100
local REFRESH_SECONDS = 10

local remotesFolder = ReplicatedStorage:WaitForChild("MyCityRemotes", 30)
assert(remotesFolder, "[ElectionUI] MyCityRemotes missing")

local GetPlayerData = remotesFolder:WaitForChild("GetPlayerData") :: RemoteFunction
local GetElectionData = remotesFolder:WaitForChild("GetElectionData") :: RemoteFunction
local Nominate = remotesFolder:WaitForChild("Nominate") :: RemoteFunction
local Vote = remotesFolder:WaitForChild("Vote") :: RemoteFunction
local ShowNotification = remotesFolder:WaitForChild("ShowNotification") :: RemoteEvent

local playerGui = localPlayer:WaitForChild("PlayerGui")

local electionGui = Instance.new("ScreenGui")
electionGui.Name = "ElectionGui"
electionGui.ResetOnSpawn = false
electionGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
electionGui.DisplayOrder = 8
electionGui.IgnoreGuiInset = true
electionGui.Parent = playerGui

-- ——— lightweight toast (matches MainUI notification style) ———
local function showToast(message: string, kind: string)
	local notifHost = electionGui:FindFirstChild("__ToastHost")
	if not notifHost then
		notifHost = Instance.new("Frame")
		notifHost.Name = "__ToastHost"
		notifHost.BackgroundTransparency = 1
		notifHost.Size = UDim2.fromScale(1, 1)
		notifHost.ZIndex = 50
		notifHost.Parent = electionGui
	end

	local accent = if kind == "error" then Color3.fromRGB(200, 60, 70) elseif kind == "success" then Color3.fromRGB(60, 160, 90) else ACCENT

	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.Position = UDim2.new(0.5, 0, 0, -48)
	lbl.Size = UDim2.new(0, 360, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.BackgroundColor3 = accent
	lbl.BackgroundTransparency = 0.12
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 15
	lbl.TextColor3 = TEXT
	lbl.Text = message
	lbl.TextWrapped = true
	lbl.ZIndex = 51
	lbl.Parent = notifHost

	local lblC = Instance.new("UICorner")
	lblC.CornerRadius = UDim.new(0, 10)
	lblC.Parent = lbl

	TweenService:Create(
		lbl,
		TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 12) }
	):Play()

	task.delay(3, function()
		if not lbl.Parent then
			return
		end
		TweenService:Create(lbl, TweenInfo.new(0.35), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
		task.wait(0.35)
		lbl:Destroy()
	end)
end

-- ——— helpers ———
local function formatDuration(totalSec: number): string
	totalSec = math.max(0, math.floor(totalSec))
	local h = math.floor(totalSec / 3600)
	local m = math.floor((totalSec % 3600) / 60)
	local s = totalSec % 60
	return string.format("%dh %02dm %02ds", h, m, s)
end

local function formatCountdownRemaining(totalSec: number): string
	totalSec = math.max(0, math.floor(totalSec))
	local h = math.floor(totalSec / 3600)
	local m = math.floor((totalSec % 3600) / 60)
	local s = totalSec % 60
	return string.format("%d:%02d:%02d remaining", h, m, s)
end

local function formatPhaseLabel(phase: string): string
	if phase == "mandate" then
		return "Mandate"
	elseif phase == "candidacy" then
		return "Candidacy Open"
	elseif phase == "voting" then
		return "Voting Open"
	elseif phase == "counting" then
		return "Counting votes"
	end
	return tostring(phase)
end

local function formatMandateEnd(unix: number): string
	local ok, dt = pcall(function()
		return DateTime.fromUnixTimestamp(unix)
	end)
	if ok and dt then
		return dt:FormatUniversalTime("%Y-%m-%d %H:%M UTC", "en-us")
	end
	return tostring(unix)
end

-- ——— top bar button ———
local openButton = Instance.new("TextButton")
openButton.Name = "ElectionOpenButton"
openButton.Size = UDim2.fromOffset(120, 35)
openButton.Position = UDim2.new(0, 10, 0, 70)
openButton.BackgroundColor3 = BUTTON_NAVY
openButton.BorderSizePixel = 0
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 14
openButton.TextColor3 = TEXT
openButton.Text = "🏛️ Election"
openButton.AutoButtonColor = true
openButton.Visible = true
openButton.Parent = electionGui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 8)
openCorner.Parent = openButton

local openStroke = Instance.new("UIStroke")
openStroke.Color = ACCENT
openStroke.Transparency = 0.7
openStroke.Thickness = 1
openStroke.Parent = openButton

-- ——— modal panel ———
local panel = Instance.new("Frame")
panel.Name = "ElectionPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(500, 550)
panel.BackgroundColor3 = BG
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 10
panel.Parent = electionGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = ACCENT
panelStroke.Transparency = 0.65
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 12)
title.Size = UDim2.new(1, -120, 0, 28)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = GOLD
title.Text = "🏛️ City Elections"
title.ZIndex = 11
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 10)
closeBtn.Size = UDim2.fromOffset(36, 32)
closeBtn.BackgroundColor3 = ACCENT
closeBtn.BackgroundTransparency = 0.2
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = TEXT
closeBtn.Text = "✕"
closeBtn.ZIndex = 11
closeBtn.Parent = panel

local closeC = Instance.new("UICorner")
closeC.CornerRadius = UDim.new(0, 8)
closeC.Parent = closeBtn

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.BackgroundTransparency = 1
tabBar.Position = UDim2.new(0, 12, 0, 48)
tabBar.Size = UDim2.new(1, -24, 0, 36)
tabBar.ZIndex = 11
tabBar.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Parent = tabBar

local function makeTabButton(text: string): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 0, 1, 0)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BackgroundColor3 = CARD_BG
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.TextColor3 = TEXT
	b.Text = "  " .. text .. "  "
	b.ZIndex = 11
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	return b
end

local tabStatusBtn = makeTabButton("Status")
local tabCandidatesBtn = makeTabButton("Candidates")
local tabNominateBtn = makeTabButton("Nominate")
tabStatusBtn.Parent = tabBar
tabCandidatesBtn.Parent = tabBar
tabNominateBtn.Parent = tabBar

local content = Instance.new("Frame")
content.Name = "Content"
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, 12, 0, 92)
content.Size = UDim2.new(1, -24, 1, -130)
content.ZIndex = 11
content.ClipsDescendants = true
content.Parent = panel

local errLabel = Instance.new("TextLabel")
errLabel.Name = "ErrorLine"
errLabel.BackgroundTransparency = 1
errLabel.Position = UDim2.new(0, 12, 1, -32)
errLabel.Size = UDim2.new(1, -24, 0, 24)
errLabel.Font = Enum.Font.Gotham
errLabel.TextSize = 13
errLabel.TextColor3 = ACCENT
errLabel.TextXAlignment = Enum.TextXAlignment.Left
errLabel.Text = ""
errLabel.TextWrapped = true
errLabel.ZIndex = 11
errLabel.Parent = panel

-- Tab frames
local frameStatus = Instance.new("ScrollingFrame")
frameStatus.Name = "StatusTab"
frameStatus.BackgroundTransparency = 1
frameStatus.BorderSizePixel = 0
frameStatus.Size = UDim2.fromScale(1, 1)
frameStatus.CanvasSize = UDim2.new(0, 0, 0, 0)
frameStatus.AutomaticCanvasSize = Enum.AutomaticSize.Y
frameStatus.ScrollBarThickness = 4
frameStatus.Visible = true
frameStatus.ZIndex = 11
frameStatus.Parent = content

local slayout = Instance.new("UIListLayout")
slayout.Padding = UDim.new(0, 10)
slayout.SortOrder = Enum.SortOrder.LayoutOrder
slayout.Parent = frameStatus

local frameCandidates = Instance.new("ScrollingFrame")
frameCandidates.Name = "CandidatesTab"
frameCandidates.BackgroundTransparency = 1
frameCandidates.BorderSizePixel = 0
frameCandidates.Size = UDim2.fromScale(1, 1)
frameCandidates.CanvasSize = UDim2.new(0, 0, 0, 0)
frameCandidates.AutomaticCanvasSize = Enum.AutomaticSize.Y
frameCandidates.ScrollBarThickness = 4
frameCandidates.Visible = false
frameCandidates.ZIndex = 11
frameCandidates.Parent = content

local clayout = Instance.new("UIListLayout")
clayout.Padding = UDim.new(0, 10)
clayout.SortOrder = Enum.SortOrder.LayoutOrder
clayout.Parent = frameCandidates

local frameNominate = Instance.new("Frame")
frameNominate.Name = "NominateTab"
frameNominate.BackgroundTransparency = 1
frameNominate.Size = UDim2.fromScale(1, 1)
frameNominate.Visible = false
frameNominate.ZIndex = 11
frameNominate.Parent = content

-- ——— state ———
local currentTab = "status"
local lastElectionData: any = nil
local lastPlayerData: any = nil
local mandateCountdownValueLabel: TextLabel? = nil
local lastMandateEndTimeForTick: number? = nil

-- Forward declaration: fetchAndRedraw is defined later but referenced inside
-- refreshUI (via Vote/Nominate button handlers). Without this forward declare,
-- Luau resolves fetchAndRedraw as a global inside refreshUI — which is nil,
-- causing task.defer(nil) to silently fail and the UI to only update on the
-- next 10s refresh tick. Declaring it here ensures the handlers capture the
-- local upvalue; the later 'function fetchAndRedraw()' assigns to this same var.
local fetchAndRedraw: (() -> ())?

local function setTab(name: string)
	currentTab = name
	frameStatus.Visible = name == "status"
	frameCandidates.Visible = name == "candidates"
	frameNominate.Visible = name == "nominate"
	local active = CARD_BG
	local inactive = Color3.fromRGB(35, 35, 55)
	tabStatusBtn.BackgroundColor3 = if name == "status" then active else inactive
	tabCandidatesBtn.BackgroundColor3 = if name == "candidates" then active else inactive
	tabNominateBtn.BackgroundColor3 = if name == "nominate" then active else inactive
end

local function clearChildrenExceptLayout(f: Instance)
	for _, ch in f:GetChildren() do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
end

local function clearAllChildren(f: Instance)
	for _, ch in f:GetChildren() do
		ch:Destroy()
	end
end

local function addStatusRow(parent: Instance, order: number, label: string, value: string)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = CARD_BG
	row.BackgroundTransparency = 0.2
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.ZIndex = 12
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = row
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = row

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 18)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.TextColor3 = MUTED
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = label
	l.ZIndex = 12
	l.Parent = row

	local v = Instance.new("TextLabel")
	v.BackgroundTransparency = 1
	v.Position = UDim2.new(0, 0, 0, 22)
	v.Size = UDim2.new(1, 0, 0, 0)
	v.AutomaticSize = Enum.AutomaticSize.Y
	v.Font = Enum.Font.Gotham
	v.TextSize = 15
	v.TextColor3 = TEXT
	v.TextXAlignment = Enum.TextXAlignment.Left
	v.TextWrapped = true
	v.Text = value
	v.ZIndex = 12
	v.Parent = row

	row.Parent = parent
end

local function addMandateCountdownRow(parent: Instance, order: number, mandateEndUnix: number)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = CARD_BG
	row.BackgroundTransparency = 0.2
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.ZIndex = 12
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = row
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = row

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 18)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.TextColor3 = MUTED
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = "Time until mandate ends"
	l.ZIndex = 12
	l.Parent = row

	local v = Instance.new("TextLabel")
	v.BackgroundTransparency = 1
	v.Position = UDim2.new(0, 0, 0, 22)
	v.Size = UDim2.new(1, 0, 0, 0)
	v.AutomaticSize = Enum.AutomaticSize.Y
	v.Font = Enum.Font.GothamBold
	v.TextSize = 16
	v.TextColor3 = GOLD
	v.TextXAlignment = Enum.TextXAlignment.Left
	v.TextWrapped = true
	v.ZIndex = 12
	lastMandateEndTimeForTick = mandateEndUnix
	v.Text = formatCountdownRemaining(math.max(0, mandateEndUnix - os.time()))
	mandateCountdownValueLabel = v
	v.Parent = row

	row.Parent = parent
end

local function refreshUI()
	errLabel.Text = ""
	mandateCountdownValueLabel = nil
	lastMandateEndTimeForTick = nil
	clearChildrenExceptLayout(frameStatus)
	clearChildrenExceptLayout(frameCandidates)

	local pdata = lastPlayerData
	local edata = lastElectionData

	if not pdata or typeof(pdata.City) ~= "string" or pdata.City == "None" then
		addStatusRow(frameStatus, 1, "City", "Join a city to participate in elections.")
		addStatusRow(frameStatus, 2, "Hint", "Use the city menu in the main HUD.")
		local hint = Instance.new("TextLabel")
		hint.BackgroundTransparency = 1
		hint.Size = UDim2.new(1, 0, 0, 40)
		hint.Font = Enum.Font.Gotham
		hint.TextSize = 14
		hint.TextColor3 = MUTED
		hint.TextWrapped = true
		hint.Text = "Candidates and voting unlock after you are assigned to Ironholm or Solara."
		hint.LayoutOrder = 3
		hint.Parent = frameStatus

		clearAllChildren(frameNominate)
		local np = Instance.new("UIPadding")
		np.PaddingTop = UDim.new(0, 8)
		np.Parent = frameNominate
		return
	end

	if not edata then
		addStatusRow(frameStatus, 1, "Status", "Could not load election data. Try again later.")
		clearAllChildren(frameNominate)
		return
	end

	local phaseLabel = formatPhaseLabel(edata.phase)
	local mayorLine = if edata.currentMayor and edata.currentMayorName and edata.currentMayorName ~= "Vacant"
		then "👑 " .. tostring(edata.currentMayorName)
		else "No Mayor"

	local secPhase = math.floor(tonumber(edata.secondsUntilCurrentPhaseEnds) or 0)
	local mandateEndUnix = tonumber(edata.mandateEndTime) or 0

	addStatusRow(frameStatus, 1, "Phase", phaseLabel)
	addStatusRow(frameStatus, 2, "Mayor", mayorLine)
	if mandateEndUnix > 0 then
		addMandateCountdownRow(frameStatus, 3, mandateEndUnix)
	end
	addStatusRow(frameStatus, 4, "Time left in phase", formatDuration(secPhase))
	addStatusRow(frameStatus, 5, "Mandate ends (UTC)", formatMandateEnd(edata.mandateEndTime))
	addStatusRow(frameStatus, 6, "Your city", tostring(pdata.City))

	-- Candidates tab
	local phase = edata.phase
	-- Single source of truth: server sends 'hasVoted'. Old fallback to 'hasPlayerVoted'
	-- was a symptom of broken contract — removed alongside the duplicate field in init.server.luau.
	local hasVoted = edata.hasVoted == true
	local myId = localPlayer.UserId
	local rep = tonumber(pdata.Reputation) or 0

	if hasVoted then
		local badge = Instance.new("TextLabel")
		badge.BackgroundTransparency = 1
		badge.Size = UDim2.new(1, 0, 0, 28)
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 16
		badge.TextColor3 = GOLD
		badge.Text = "✓ Voted — thanks for participating!"
		badge.LayoutOrder = 0
		badge.ZIndex = 12
		badge.Parent = frameCandidates
	end

	local candidates = edata.candidates
	if typeof(candidates) == "table" then
		for idx, cand in ipairs(candidates :: { any }) do
			local card = Instance.new("Frame")
			card.BackgroundColor3 = CARD_BG
			card.Size = UDim2.new(1, 0, 0, 0)
			card.AutomaticSize = Enum.AutomaticSize.Y
			card.LayoutOrder = idx
			card.ZIndex = 12
			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(0, 8)
			cc.Parent = card
			local cardLayout = Instance.new("UIListLayout")
			cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
			cardLayout.Padding = UDim.new(0, 8)
			cardLayout.Parent = card
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 12)
			pad.PaddingRight = UDim.new(0, 12)
			pad.PaddingTop = UDim.new(0, 10)
			pad.PaddingBottom = UDim.new(0, 10)
			pad.Parent = card

			local nameLbl = Instance.new("TextLabel")
			nameLbl.BackgroundTransparency = 1
			nameLbl.Size = UDim2.new(1, 0, 0, 22)
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 16
			nameLbl.TextColor3 = TEXT
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Text = tostring(cand.name) .. "  •  Votes: " .. tostring(cand.votes or 0)
			nameLbl.ZIndex = 12
			nameLbl.LayoutOrder = 1
			nameLbl.Parent = card

			local msgLbl = Instance.new("TextLabel")
			msgLbl.BackgroundTransparency = 1
			msgLbl.Size = UDim2.new(1, 0, 0, 0)
			msgLbl.AutomaticSize = Enum.AutomaticSize.Y
			msgLbl.Font = Enum.Font.Gotham
			msgLbl.TextSize = 13
			msgLbl.TextColor3 = MUTED
			msgLbl.TextXAlignment = Enum.TextXAlignment.Left
			msgLbl.TextWrapped = true
			msgLbl.Text = tostring(cand.campaignMessage or "")
			msgLbl.ZIndex = 12
			msgLbl.LayoutOrder = 2
			msgLbl.Parent = card

			local rowH = Instance.new("Frame")
			rowH.BackgroundTransparency = 1
			rowH.Size = UDim2.new(1, 0, 0, 34)
			rowH.ZIndex = 12
			rowH.LayoutOrder = 3
			rowH.Parent = card

			if phase == "voting" and not hasVoted then
				local voteBtn = Instance.new("TextButton")
				voteBtn.Size = UDim2.fromOffset(100, 30)
				voteBtn.Position = UDim2.new(1, 0, 0, 0)
				voteBtn.AnchorPoint = Vector2.new(1, 0)
				voteBtn.BackgroundColor3 = ACCENT
				voteBtn.BorderSizePixel = 0
				voteBtn.Font = Enum.Font.GothamBold
				voteBtn.TextSize = 14
				voteBtn.TextColor3 = TEXT
				voteBtn.Text = "Vote"
				voteBtn.ZIndex = 12
				local vc = Instance.new("UICorner")
				vc.CornerRadius = UDim.new(0, 6)
				vc.Parent = voteBtn
				voteBtn.Parent = rowH

				local candUid = tonumber(cand.userId)
				voteBtn.MouseButton1Click:Connect(function()
					if not candUid then
						return
					end
					local callOk, success, message = pcall(function()
						return Vote:InvokeServer(candUid)
					end)
					if not callOk then
						errLabel.Text = "Vote failed (connection)."
						showToast("Vote failed.", "error")
						return
					end
					if success then
						local m = if typeof(message) == "string" then message else "Vote recorded!"
						showToast(m, "success")
						if fetchAndRedraw then
							task.defer(fetchAndRedraw)
						end
					else
						errLabel.Text = tostring(message or "Could not vote.")
						showToast(tostring(message or "Error"), "error")
					end
				end)
			elseif phase == "voting" and hasVoted then
				local votedLbl = Instance.new("TextLabel")
				votedLbl.BackgroundTransparency = 1
				votedLbl.Size = UDim2.fromScale(1, 1)
				votedLbl.Font = Enum.Font.GothamBold
				votedLbl.TextSize = 13
				votedLbl.TextColor3 = MUTED
				votedLbl.TextXAlignment = Enum.TextXAlignment.Right
				votedLbl.Text = "✓ Voted"
				votedLbl.ZIndex = 12
				votedLbl.Parent = rowH
			end

			if phase == "candidacy" then
				local isSelf = tonumber(cand.userId) == myId
				if not isSelf and rep >= MIN_REP_NOMINATE then
					local runBtn = Instance.new("TextButton")
					runBtn.Size = UDim2.fromOffset(130, 30)
					runBtn.Position = UDim2.new(1, 0, 0, 0)
					runBtn.AnchorPoint = Vector2.new(1, 0)
					runBtn.BackgroundColor3 = GOLD
					runBtn.BackgroundTransparency = 0.35
					runBtn.BorderSizePixel = 0
					runBtn.Font = Enum.Font.GothamBold
					runBtn.TextSize = 13
					runBtn.TextColor3 = BG
					runBtn.Text = "Run for Mayor"
					runBtn.ZIndex = 12
					local rc = Instance.new("UICorner")
					rc.CornerRadius = UDim.new(0, 6)
					rc.Parent = runBtn
					runBtn.Parent = rowH
					runBtn.MouseButton1Click:Connect(function()
						setTab("nominate")
					end)
				end
			end

			card.Parent = frameCandidates
		end
	end

	if phase == "candidacy" and rep >= MIN_REP_NOMINATE then
		local already = false
		if typeof(candidates) == "table" then
			for _, cand in ipairs(candidates :: { any }) do
				if tonumber(cand.userId) == myId then
					already = true
					break
				end
			end
		end
		if not already then
			local runRow = Instance.new("Frame")
			runRow.BackgroundTransparency = 1
			runRow.Size = UDim2.new(1, 0, 0, 40)
			runRow.LayoutOrder = 990
			runRow.ZIndex = 12
			local runMain = Instance.new("TextButton")
			runMain.Size = UDim2.new(1, 0, 0, 36)
			runMain.BackgroundColor3 = ACCENT
			runMain.BorderSizePixel = 0
			runMain.Font = Enum.Font.GothamBold
			runMain.TextSize = 15
			runMain.TextColor3 = TEXT
			runMain.Text = "Run for Mayor — open Nominate tab"
			local rmc = Instance.new("UICorner")
			rmc.CornerRadius = UDim.new(0, 8)
			rmc.Parent = runMain
			runMain.Parent = runRow
			runRow.Parent = frameCandidates
			runMain.MouseButton1Click:Connect(function()
				setTab("nominate")
			end)
		end
	end

	-- Nominate tab
	clearAllChildren(frameNominate)
	local nLayout = Instance.new("UIListLayout")
	nLayout.Padding = UDim.new(0, 10)
	nLayout.SortOrder = Enum.SortOrder.LayoutOrder
	nLayout.Parent = frameNominate

	local repLbl = Instance.new("TextLabel")
	repLbl.BackgroundTransparency = 1
	repLbl.Size = UDim2.new(1, 0, 0, 22)
	repLbl.Font = Enum.Font.Gotham
	repLbl.TextSize = 14
	repLbl.TextColor3 = TEXT
	repLbl.TextXAlignment = Enum.TextXAlignment.Left
	repLbl.Text = "Your reputation: " .. tostring(rep)
	repLbl.LayoutOrder = 1
	repLbl.Parent = frameNominate

	local reqLbl = Instance.new("TextLabel")
	reqLbl.BackgroundTransparency = 1
	reqLbl.Size = UDim2.new(1, 0, 0, 36)
	reqLbl.Font = Enum.Font.Gotham
	reqLbl.TextSize = 13
	reqLbl.TextColor3 = MUTED
	reqLbl.TextWrapped = true
	reqLbl.TextXAlignment = Enum.TextXAlignment.Left
	reqLbl.Text = "Testing: 0 reputation required. Live in this city to nominate."
	reqLbl.LayoutOrder = 2
	reqLbl.Parent = frameNominate

	local msgBox = Instance.new("TextBox")
	msgBox.Name = "CampaignBox"
	msgBox.Size = UDim2.new(1, 0, 0, 120)
	msgBox.BackgroundColor3 = CARD_BG
	msgBox.TextColor3 = TEXT
	msgBox.Font = Enum.Font.Gotham
	msgBox.TextSize = 14
	msgBox.Text = ""
	msgBox.TextXAlignment = Enum.TextXAlignment.Left
	msgBox.TextYAlignment = Enum.TextYAlignment.Top
	msgBox.TextWrapped = true
	msgBox.ClearTextOnFocus = false
	msgBox.PlaceholderText = "Campaign message (max " .. tostring(MAX_CAMPAIGN_CHARS) .. " characters)..."
	msgBox.LayoutOrder = 3
	msgBox.Parent = frameNominate
	local msgC = Instance.new("UICorner")
	msgC.CornerRadius = UDim.new(0, 8)
	msgC.Parent = msgBox
	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingLeft = UDim.new(0, 10)
	msgPad.PaddingRight = UDim.new(0, 10)
	msgPad.PaddingTop = UDim.new(0, 8)
	msgPad.Parent = msgBox

	msgBox:GetPropertyChangedSignal("Text"):Connect(function()
		if utf8.len(msgBox.Text) > MAX_CAMPAIGN_CHARS then
			msgBox.Text = utf8.sub(msgBox.Text, 1, MAX_CAMPAIGN_CHARS)
		end
	end)

	local declareBtn = Instance.new("TextButton")
	declareBtn.Size = UDim2.new(1, 0, 0, 40)
	declareBtn.BackgroundColor3 = ACCENT
	declareBtn.BorderSizePixel = 0
	declareBtn.Font = Enum.Font.GothamBold
	declareBtn.TextSize = 15
	declareBtn.TextColor3 = TEXT
	declareBtn.Text = "Declare Candidacy"
	declareBtn.LayoutOrder = 4
	declareBtn.AutoButtonColor = true
	local dbc = Instance.new("UICorner")
	dbc.CornerRadius = UDim.new(0, 8)
	dbc.Parent = declareBtn
	declareBtn.Parent = frameNominate

	declareBtn.MouseButton1Click:Connect(function()
		local text = msgBox.Text
		if utf8.len(text) > MAX_CAMPAIGN_CHARS then
			text = utf8.sub(text, 1, MAX_CAMPAIGN_CHARS)
		end
		local callOk, success, response = pcall(function()
			return Nominate:InvokeServer(text)
		end)
		if not callOk then
			errLabel.Text = "Nomination failed (connection)."
			showToast("Could not nominate.", "error")
			return
		end
		if success then
			showToast(if typeof(response) == "string" then response else "Candidacy registered!", "success")
			if fetchAndRedraw then
				task.defer(fetchAndRedraw)
			end
		else
			errLabel.Text = tostring(response or "Nomination rejected.")
			showToast(tostring(response or "Error"), "error")
		end
	end)
end

-- Assigns to the forward-declared 'fetchAndRedraw' above (no 'local' keyword).
function fetchAndRedraw()
	local okP, pdata = pcall(function()
		return GetPlayerData:InvokeServer()
	end)
	if okP and pdata then
		lastPlayerData = pdata
	else
		lastPlayerData = nil
	end

	local okE, edata = pcall(function()
		return GetElectionData:InvokeServer()
	end)
	if okE then
		lastElectionData = edata
	else
		lastElectionData = nil
	end

	refreshUI()
end

tabStatusBtn.MouseButton1Click:Connect(function()
	setTab("status")
end)
tabCandidatesBtn.MouseButton1Click:Connect(function()
	setTab("candidates")
end)
tabNominateBtn.MouseButton1Click:Connect(function()
	setTab("nominate")
end)

openButton.MouseButton1Click:Connect(function()
	panel.Visible = true
	setTab("status")
	if fetchAndRedraw then
		fetchAndRedraw()
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

ShowNotification.OnClientEvent:Connect(function(msg: unknown, kind: unknown)
	if typeof(msg) == "string" then
		local k = if typeof(kind) == "string" then kind else "info"
		task.spawn(showToast, msg :: string, k)
	end
end)

task.spawn(function()
	while task.wait(REFRESH_SECONDS) do
		if panel.Visible and fetchAndRedraw then
			fetchAndRedraw()
		end
	end
end)

-- Smooth mandate countdown (1s) while panel is open; uses mandateEndTime from last fetch.
task.spawn(function()
	while true do
		task.wait(1)
		if panel.Visible and mandateCountdownValueLabel and mandateCountdownValueLabel.Parent and lastMandateEndTimeForTick then
			local rem = math.max(0, lastMandateEndTimeForTick - os.time())
			mandateCountdownValueLabel.Text = formatCountdownRemaining(rem)
		end
	end
end)

setTab("status")
print("[MY CITY] ElectionUI loaded")
