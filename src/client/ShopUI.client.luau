--[[
	ShopUI — MY CITY
	Wires each shop Model under Workspace.CommercialZone (by Model name) to its door ProximityPrompt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig") :: ModuleScript)
local ShopAction = Remotes.ShopAction :: RemoteFunction
local ShowNotification = Remotes.ShowNotification :: RemoteEvent
local GetPlayerData = Remotes.GetPlayerData :: RemoteFunction
local GetInvestments = Remotes.GetInvestments :: RemoteFunction
local GetOwnedOutfits = Remotes.GetOwnedOutfits :: RemoteFunction
local OpenWardrobe = Remotes.OpenWardrobe :: RemoteEvent

-- ——— Theme (aligned with MainUI) ———
local BG_PANEL = Color3.fromRGB(15, 15, 30)
local NAVY = Color3.fromHex("0f0f1a")
local PANEL_BODY = Color3.fromHex("16213e")
local ACCENT = Color3.fromHex("e94560")
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_MUTED = Color3.fromRGB(160, 165, 185)
local MONEY_GOLD = Color3.fromRGB(255, 214, 90)
local REP_BLUE = Color3.fromRGB(120, 200, 255)
local SUCCESS = Color3.fromRGB(60, 180, 110)
local DANGER = Color3.fromRGB(220, 70, 80)
local CORNER = UDim.new(0, 8)
local DEFAULT_PANEL_SIZE = Vector2.new(500, 550)
local BANK_PANEL_SIZE = Vector2.new(480, 520)
local INVEST_DURATION_SEC = 3600

local SHOP_TITLES: { [string]: string } = {
	Bank = "🏦 Bank",
	Restaurant = "🍴 Restaurant",
	Clothing = "👔 Clothing Shop",
	Barbershop = "💈 Barbershop",
	Electronics = "🖥️ Electronics",
	Grocery = "🛒 Grocery",
	Pharmacy = "💊 Pharmacy",
}

local screenGui: ScreenGui
local rootPanel: Frame
local titleLabel: TextLabel
local moneyTopLabel: TextLabel
local scroll: ScrollingFrame
local closeBtn: TextButton
local wardrobePanel: Frame? = nil

-- Invalidates Bank UI background refresh loops when shop changes or closes
local bankLoopGen = 0

local function safeInvoke(rf: RemoteFunction, ...: any): any
	local ok, result = pcall(function(...)
		return rf:InvokeServer(...)
	end, ...)
	if ok then
		return result
	end
	warn("[ShopUI] Remote failed:", result)
	return nil
end

local function getPlayerMoneyAndBank(): (number, number)
	local data = safeInvoke(GetPlayerData)
	if typeof(data) ~= "table" then
		return 0, 0
	end
	local m = typeof(data.Money) == "number" and data.Money or 0
	local b = typeof(data.BankBalance) == "number" and data.BankBalance or 0
	return m, b
end

local function refreshMoneyTop()
	local wallet, _bank = getPlayerMoneyAndBank()
	moneyTopLabel.Text = string.format("🪙 Wallet: %d CC", wallet)
end

local function formatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

local function notify(message: string, success: boolean)
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.new(0, 380, 0, 40)
	toast.Position = UDim2.new(0.5, 0, 0, -50)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.BackgroundColor3 = if success then SUCCESS else DANGER
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = TEXT_WHITE
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 14
	toast.Text = tostring(message)
	toast.TextWrapped = true
	toast.ZIndex = 200
	toast.Parent = screenGui
	local c = Instance.new("UICorner")
	c.CornerRadius = CORNER
	c.Parent = toast
	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 12),
	}):Play()
	task.delay(2.8, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.2), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.wait(0.22)
			toast:Destroy()
		end
	end)
end

local function shopResult(result: any): (boolean, string)
	if typeof(result) == "table" and typeof(result.success) == "boolean" then
		local msg = typeof(result.message) == "string" and result.message or ""
		return result.success, msg
	end
	return false, "No response from server."
end

local function invokeShop(shopName: string, action: string, ...: any): (boolean, string)
	local raw = safeInvoke(ShopAction, shopName, action, ...)
	return shopResult(raw)
end

local function clearScroll()
	for _, c in scroll:GetChildren() do
		if c:IsA("UIListLayout") or c:IsA("UIPadding") then
			continue
		end
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function styleBuyButton(btn: TextButton)
	btn.Size = UDim2.new(1, -16, 0, 44)
	btn.BackgroundColor3 = PANEL_BODY
	btn.TextColor3 = TEXT_WHITE
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	local bc = Instance.new("UICorner")
	bc.CornerRadius = CORNER
	bc.Parent = btn
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = ACCENT:Lerp(PANEL_BODY, 0.35)
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = PANEL_BODY
	end)
end

local function addBuyRow(text: string, onClick: () -> ())
	local btn = Instance.new("TextButton")
	btn.Text = text
	styleBuyButton(btn)
	btn.Parent = scroll
	btn.MouseButton1Click:Connect(onClick)
end

local function addLabel(text: string, order: number, muted: boolean?)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -16, 0, 22)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 14
	lbl.TextColor3 = if muted then TEXT_MUTED else TEXT_WHITE
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.LayoutOrder = order
	lbl.Parent = scroll
end

local function addTextBoxRow(placeholder: string, buttonText: string, onSubmit: (number) -> ())
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -16, 0, 44)
	row.BackgroundTransparency = 1
	row.Parent = scroll

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -120, 1, 0)
	box.Position = UDim2.new(0, 0, 0, 0)
	box.BackgroundColor3 = NAVY
	box.TextColor3 = TEXT_WHITE
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = TEXT_MUTED
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.TextSize = 15
	box.Text = ""
	box.BorderSizePixel = 0
	box.Parent = row
	local bc = Instance.new("UICorner")
	bc.CornerRadius = CORNER
	bc.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = box

	local go = Instance.new("TextButton")
	go.Size = UDim2.new(0, 108, 1, 0)
	go.Position = UDim2.new(1, -108, 0, 0)
	go.BackgroundColor3 = ACCENT
	go.TextColor3 = TEXT_WHITE
	go.Font = Enum.Font.GothamBold
	go.TextSize = 14
	go.Text = buttonText
	go.AutoButtonColor = false
	go.Parent = row
	local gc = Instance.new("UICorner")
	gc.CornerRadius = CORNER
	gc.Parent = go

	go.MouseButton1Click:Connect(function()
		local n = tonumber(box.Text)
		if not n or n <= 0 or n ~= math.floor(n) then
			notify("Enter a positive whole number of CC.", false)
			return
		end
		onSubmit(n)
	end)
end

local function openShop(shopName: string)
	bankLoopGen += 1
	local myBankGen = bankLoopGen

	clearScroll()

	if shopName == "Bank" then
		rootPanel.Size = UDim2.fromOffset(BANK_PANEL_SIZE.X, BANK_PANEL_SIZE.Y)
	else
		rootPanel.Size = UDim2.fromOffset(DEFAULT_PANEL_SIZE.X, DEFAULT_PANEL_SIZE.Y)
	end

	local title = SHOP_TITLES[shopName] or ("🛍️ " .. shopName)
	titleLabel.Text = title
	titleLabel.TextSize = if shopName == "Bank" then 16 else 20
	moneyTopLabel.TextSize = if shopName == "Bank" then 14 else 16
	screenGui.Enabled = true
	rootPanel.Visible = true
	rootPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
	rootPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	refreshMoneyTop()

	if shopName == "Bank" then
		local function styleDarkTextBox(box: TextBox)
			box.BackgroundColor3 = NAVY
			box.TextColor3 = TEXT_WHITE
			box.PlaceholderColor3 = TEXT_MUTED
			box.ClearTextOnFocus = false
			box.Font = Enum.Font.Gotham
			box.TextSize = 13
			box.BorderSizePixel = 0
			local bc = Instance.new("UICorner")
			bc.CornerRadius = CORNER
			bc.Parent = box
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 10)
			pad.PaddingRight = UDim.new(0, 10)
			pad.Parent = box
		end

		local function sectionTitle(text: string): TextLabel
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, -16, 0, 22)
			t.Font = Enum.Font.GothamBold
			t.TextSize = 16
			t.TextColor3 = ACCENT
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.Text = text
			t.LayoutOrder = 0
			t.Parent = scroll
			return t
		end

		local function addDivider()
			local d = Instance.new("Frame")
			d.Size = UDim2.new(1, -16, 0, 1)
			d.BackgroundColor3 = TEXT_MUTED
			d.BackgroundTransparency = 0.7
			d.BorderSizePixel = 0
			d.Parent = scroll
		end

		-- —— Section 1: Balances ——
		sectionTitle("Balances")
		local walletBalanceLbl = Instance.new("TextLabel")
		walletBalanceLbl.BackgroundTransparency = 1
		walletBalanceLbl.Size = UDim2.new(1, -16, 0, 22)
		walletBalanceLbl.Font = Enum.Font.GothamBold
		walletBalanceLbl.TextSize = 13
		walletBalanceLbl.TextColor3 = MONEY_GOLD
		walletBalanceLbl.TextXAlignment = Enum.TextXAlignment.Left
		walletBalanceLbl.Text = "💰 Wallet: — CC"
		walletBalanceLbl.Parent = scroll

		local bankBalanceLbl = Instance.new("TextLabel")
		bankBalanceLbl.BackgroundTransparency = 1
		bankBalanceLbl.Size = UDim2.new(1, -16, 0, 22)
		bankBalanceLbl.Font = Enum.Font.GothamBold
		bankBalanceLbl.TextSize = 13
		bankBalanceLbl.TextColor3 = REP_BLUE
		bankBalanceLbl.TextXAlignment = Enum.TextXAlignment.Left
		bankBalanceLbl.Text = "🏦 Bank Balance: — CC"
		bankBalanceLbl.Parent = scroll

		addDivider()

		local function refreshBalancesOnly()
			if myBankGen ~= bankLoopGen then
				return
			end
			if not walletBalanceLbl.Parent then
				return
			end
			local w, b = getPlayerMoneyAndBank()
			walletBalanceLbl.Text = string.format("💰 Wallet: %d CC", w)
			bankBalanceLbl.Text = string.format("🏦 Bank Balance: %d CC", b)
			refreshMoneyTop()
		end

		-- —— Section 2: Deposit / Withdraw ——
		sectionTitle("Deposit / Withdraw")
		local dwAmountBox = Instance.new("TextBox")
		dwAmountBox.Size = UDim2.new(1, -16, 0, 36)
		dwAmountBox.PlaceholderText = "Amount (CC)"
		dwAmountBox.Text = ""
		styleDarkTextBox(dwAmountBox)
		dwAmountBox.Parent = scroll

		local dwRow = Instance.new("Frame")
		dwRow.Size = UDim2.new(1, -16, 0, 40)
		dwRow.BackgroundTransparency = 1
		dwRow.Parent = scroll

		local function styleActionBtn(btn: TextButton, bg: Color3)
			btn.Size = UDim2.new(0.5, -6, 1, 0)
			btn.BackgroundColor3 = bg
			btn.TextColor3 = TEXT_WHITE
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 13
			btn.AutoButtonColor = false
			btn.BorderSizePixel = 0
			local c = Instance.new("UICorner")
			c.CornerRadius = CORNER
			c.Parent = btn
		end

		local depositBtn = Instance.new("TextButton")
		depositBtn.Text = "Deposit"
		depositBtn.Position = UDim2.new(0, 0, 0, 0)
		styleActionBtn(depositBtn, PANEL_BODY)
		depositBtn.Parent = dwRow

		local withdrawBtn = Instance.new("TextButton")
		withdrawBtn.Text = "Withdraw"
		withdrawBtn.Position = UDim2.new(0.5, 6, 0, 0)
		styleActionBtn(withdrawBtn, PANEL_BODY)
		withdrawBtn.Parent = dwRow

		local dwResultLbl = Instance.new("TextLabel")
		dwResultLbl.BackgroundTransparency = 1
		dwResultLbl.Size = UDim2.new(1, -16, 0, 36)
		dwResultLbl.Font = Enum.Font.Gotham
		dwResultLbl.TextSize = 12
		dwResultLbl.TextColor3 = TEXT_MUTED
		dwResultLbl.TextWrapped = true
		dwResultLbl.TextXAlignment = Enum.TextXAlignment.Left
		dwResultLbl.TextYAlignment = Enum.TextYAlignment.Top
		dwResultLbl.Text = ""
		dwResultLbl.Parent = scroll

		local function readDwAmount(): number?
			local n = tonumber(dwAmountBox.Text)
			if not n or n <= 0 or n ~= math.floor(n) then
				return nil
			end
			return n
		end

		addDivider()

		-- —— Section 3: Investments ——
		sectionTitle("📈 My Investments")
		local investScrollH = math.clamp(math.floor(BANK_PANEL_SIZE.Y * 0.36), 96, 188)
		local investmentsScroll = Instance.new("ScrollingFrame")
		investmentsScroll.Name = "BankInvestmentsScroll"
		investmentsScroll.Size = UDim2.new(1, -16, 0, investScrollH)
		investmentsScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 24)
		investmentsScroll.BackgroundTransparency = 0.4
		investmentsScroll.BorderSizePixel = 0
		investmentsScroll.ScrollBarThickness = 5
		investmentsScroll.ScrollBarImageColor3 = ACCENT
		investmentsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		investmentsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		investmentsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		investmentsScroll.ClipsDescendants = true
		investmentsScroll.Parent = scroll
		local invSc = Instance.new("UICorner")
		invSc.CornerRadius = CORNER
		invSc.Parent = investmentsScroll
		local invPad = Instance.new("UIPadding")
		invPad.PaddingTop = UDim.new(0, 6)
		invPad.PaddingBottom = UDim.new(0, 6)
		invPad.PaddingLeft = UDim.new(0, 6)
		invPad.PaddingRight = UDim.new(0, 10)
		invPad.Parent = investmentsScroll

		local investmentsListHost = Instance.new("Frame")
		investmentsListHost.BackgroundTransparency = 1
		investmentsListHost.Size = UDim2.new(1, 0, 0, 0)
		investmentsListHost.AutomaticSize = Enum.AutomaticSize.Y
		investmentsListHost.Parent = investmentsScroll

		local investListLayout = Instance.new("UIListLayout")
		investListLayout.Padding = UDim.new(0, 8)
		investListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		investListLayout.Parent = investmentsListHost

		addDivider()

		-- —— Section 4: New investment ——
		sectionTitle("New investment")
		local investAmtBox = Instance.new("TextBox")
		investAmtBox.Size = UDim2.new(1, -16, 0, 36)
		investAmtBox.PlaceholderText = "Investment amount (CC)"
		investAmtBox.Text = ""
		styleDarkTextBox(investAmtBox)
		investAmtBox.Parent = scroll

		local investProjectLbl = Instance.new("TextLabel")
		investProjectLbl.BackgroundTransparency = 1
		investProjectLbl.Size = UDim2.new(1, -16, 0, 32)
		investProjectLbl.Font = Enum.Font.Gotham
		investProjectLbl.TextSize = 12
		investProjectLbl.TextColor3 = TEXT_MUTED
		investProjectLbl.TextWrapped = true
		investProjectLbl.TextXAlignment = Enum.TextXAlignment.Left
		investProjectLbl.Text = "Enter an amount to see projected return."
		investProjectLbl.Parent = scroll

		local investBtn = Instance.new("TextButton")
		investBtn.Text = "Invest (5% in 1hr)"
		investBtn.Size = UDim2.new(1, -16, 0, 40)
		styleBuyButton(investBtn)
		investBtn.TextSize = 13
		investBtn.Parent = scroll

		local function parseInvestmentRows(raw: any): { { originalAmount: number, currentValue: number, timeRemaining: number, projectedReturn: number } }
			local out: { { originalAmount: number, currentValue: number, timeRemaining: number, projectedReturn: number } } = {}
			if typeof(raw) ~= "table" then
				return out
			end
			for _, row in raw :: { any } do
				if typeof(row) == "table" then
					local oa = typeof(row.originalAmount) == "number" and row.originalAmount or 0
					local cv = typeof(row.currentValue) == "number" and row.currentValue or 0
					local tr = typeof(row.timeRemaining) == "number" and row.timeRemaining or 0
					local pr = typeof(row.projectedReturn) == "number" and row.projectedReturn or 0
					table.insert(out, {
						originalAmount = oa,
						currentValue = cv,
						timeRemaining = tr,
						projectedReturn = pr,
					})
				end
			end
			return out
		end

		local function rebuildInvestmentCards(rows: { { originalAmount: number, currentValue: number, timeRemaining: number, projectedReturn: number } })
			if myBankGen ~= bankLoopGen or not investmentsListHost.Parent or not investmentsScroll.Parent then
				return
			end
			for _, c in investmentsListHost:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			if #rows == 0 then
				local empty = Instance.new("TextLabel")
				empty.BackgroundTransparency = 1
				empty.Size = UDim2.new(1, 0, 0, 28)
				empty.Font = Enum.Font.Gotham
				empty.TextSize = 12
				empty.TextColor3 = TEXT_MUTED
				empty.TextXAlignment = Enum.TextXAlignment.Left
				empty.Text = "No active investments."
				empty.Parent = investmentsListHost
				return
			end
			for i, row in rows do
				local card = Instance.new("Frame")
				card.Size = UDim2.new(1, 0, 0, 0)
				card.AutomaticSize = Enum.AutomaticSize.Y
				card.BackgroundColor3 = PANEL_BODY
				card.BorderSizePixel = 0
				card.LayoutOrder = i
				card.Parent = investmentsListHost
				local cc = Instance.new("UICorner")
				cc.CornerRadius = CORNER
				cc.Parent = card
				local cp = Instance.new("UIPadding")
				cp.PaddingTop = UDim.new(0, 8)
				cp.PaddingBottom = UDim.new(0, 8)
				cp.PaddingLeft = UDim.new(0, 10)
				cp.PaddingRight = UDim.new(0, 10)
				cp.Parent = card

				local cl = Instance.new("UIListLayout")
				cl.Padding = UDim.new(0, 4)
				cl.SortOrder = Enum.SortOrder.LayoutOrder
				cl.Parent = card

				local pctGain = 0
				if row.originalAmount > 0 then
					pctGain = math.floor((row.projectedReturn - row.originalAmount) / row.originalAmount * 100 + 0.5)
				end
				local elapsedFrac = math.clamp(1 - (row.timeRemaining / INVEST_DURATION_SEC), 0, 1)

				local line1 = Instance.new("TextLabel")
				line1.BackgroundTransparency = 1
				line1.Size = UDim2.new(1, 0, 0, 16)
				line1.Font = Enum.Font.Gotham
				line1.TextSize = 12
				line1.TextColor3 = TEXT_WHITE
				line1.TextXAlignment = Enum.TextXAlignment.Left
				line1.Text = string.format("💵 Invested: %d CC", row.originalAmount)
				line1.Parent = card

				local line2 = Instance.new("TextLabel")
				line2.BackgroundTransparency = 1
				line2.Size = UDim2.new(1, 0, 0, 16)
				line2.Font = Enum.Font.Gotham
				line2.TextSize = 12
				line2.TextColor3 = MONEY_GOLD
				line2.TextXAlignment = Enum.TextXAlignment.Left
				line2.Text = string.format("📊 Current Value: %.2f CC", row.currentValue)
				line2.Parent = card

				local line3 = Instance.new("TextLabel")
				line3.BackgroundTransparency = 1
				line3.Size = UDim2.new(1, 0, 0, 16)
				line3.Font = Enum.Font.Gotham
				line3.TextSize = 12
				line3.TextColor3 = TEXT_MUTED
				line3.TextXAlignment = Enum.TextXAlignment.Left
				line3.Text = string.format("⏱ Time remaining: %s", formatDuration(row.timeRemaining))
				line3.Parent = card

				local line4 = Instance.new("TextLabel")
				line4.BackgroundTransparency = 1
				line4.Size = UDim2.new(1, 0, 0, 16)
				line4.Font = Enum.Font.Gotham
				line4.TextSize = 12
				line4.TextColor3 = SUCCESS
				line4.TextXAlignment = Enum.TextXAlignment.Left
				line4.Text = string.format("🎯 Final return: %d CC (+%d%%)", row.projectedReturn, pctGain)
				line4.Parent = card

				local barBg = Instance.new("Frame")
				barBg.Size = UDim2.new(1, 0, 0, 8)
				barBg.BackgroundColor3 = NAVY
				barBg.BorderSizePixel = 0
				barBg.LayoutOrder = 10
				barBg.Parent = card
				local barCorner = Instance.new("UICorner")
				barCorner.CornerRadius = UDim.new(0, 4)
				barCorner.Parent = barBg

				local barFill = Instance.new("Frame")
				barFill.Size = UDim2.new(elapsedFrac, 0, 1, 0)
				barFill.BackgroundColor3 = ACCENT
				barFill.BorderSizePixel = 0
				barFill.Parent = barBg
				local barFillC = Instance.new("UICorner")
				barFillC.CornerRadius = UDim.new(0, 4)
				barFillC.Parent = barFill
			end
		end

		local function refreshInvestmentsFromServer()
			if myBankGen ~= bankLoopGen then
				return
			end
			local raw = safeInvoke(GetInvestments)
			rebuildInvestmentCards(parseInvestmentRows(raw))
		end

		local function refreshAllBankDisplays(actionMsg: string?, actionOk: boolean?)
			refreshBalancesOnly()
			refreshInvestmentsFromServer()
			if actionMsg ~= nil and dwResultLbl.Parent then
				dwResultLbl.Text = actionMsg
				dwResultLbl.TextColor3 = if actionOk then SUCCESS else DANGER
			end
			if investProjectLbl.Parent then
				local n = tonumber(investAmtBox.Text)
				if n and n > 0 and n == math.floor(n) then
					local y = math.floor(n * 1.05 + 0.5)
					investProjectLbl.Text = string.format("%d CC will become %d CC in 1 hour", n, y)
				else
					investProjectLbl.Text = "Enter an amount to see projected return."
				end
			end
		end

		depositBtn.MouseButton1Click:Connect(function()
			local amt = readDwAmount()
			if not amt then
				dwResultLbl.Text = "Enter a positive whole number of CC."
				dwResultLbl.TextColor3 = DANGER
				return
			end
			local ok, msg = invokeShop("Bank", "Deposit", amt)
			notify(msg, ok)
			dwResultLbl.Text = msg
			dwResultLbl.TextColor3 = if ok then SUCCESS else DANGER
			refreshAllBankDisplays()
		end)

		withdrawBtn.MouseButton1Click:Connect(function()
			local amt = readDwAmount()
			if not amt then
				dwResultLbl.Text = "Enter a positive whole number of CC."
				dwResultLbl.TextColor3 = DANGER
				return
			end
			local ok, msg = invokeShop("Bank", "Withdraw", amt)
			notify(msg, ok)
			dwResultLbl.Text = msg
			dwResultLbl.TextColor3 = if ok then SUCCESS else DANGER
			refreshAllBankDisplays()
		end)

		investAmtBox:GetPropertyChangedSignal("Text"):Connect(function()
			if myBankGen ~= bankLoopGen or not investProjectLbl.Parent then
				return
			end
			local n = tonumber(investAmtBox.Text)
			if n and n > 0 and n == math.floor(n) then
				local y = math.floor(n * 1.05 + 0.5)
				investProjectLbl.Text = string.format("%d CC will become %d CC in 1 hour", n, y)
			else
				investProjectLbl.Text = "Enter an amount to see projected return."
			end
		end)

		investBtn.MouseButton1Click:Connect(function()
			local n = tonumber(investAmtBox.Text)
			if not n or n <= 0 or n ~= math.floor(n) then
				notify("Enter a positive whole number of CC.", false)
				return
			end
			local ok, msg = invokeShop("Bank", "Invest", n)
			notify(msg, ok)
			if ok then
				investAmtBox.Text = ""
				investProjectLbl.Text = "Enter an amount to see projected return."
			end
			refreshAllBankDisplays()
		end)

		refreshAllBankDisplays()

		task.spawn(function()
			while myBankGen == bankLoopGen do
				task.wait(5)
				if myBankGen ~= bankLoopGen then
					break
				end
				refreshBalancesOnly()
			end
		end)

		task.spawn(function()
			while myBankGen == bankLoopGen do
				task.wait(10)
				if myBankGen ~= bankLoopGen then
					break
				end
				refreshInvestmentsFromServer()
			end
		end)
	elseif shopName == "Restaurant" then
		addBuyRow("🥪 Sandwich - 50 CC (+5 rep, +10 xp)", function()
			local ok, msg = invokeShop("Restaurant", "Buy", "Sandwich")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🍽️ Full Meal - 150 CC (+15 rep, +30 xp)", function()
			local ok, msg = invokeShop("Restaurant", "Buy", "Full Meal")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("⭐ Premium Dinner - 300 CC (+30 rep, +60 xp)", function()
			local ok, msg = invokeShop("Restaurant", "Buy", "Premium")
			notify(msg, ok)
			refreshMoneyTop()
		end)
	elseif shopName == "Clothing" then
		addBuyRow("👕 Casual Outfit - 100 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Casual")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("💼 Business Outfit - 300 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Business")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("💎 Luxury Outfit - 500 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Luxury")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("☀️ Summer Outfit - 150 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Summer")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("❄️ Winter Outfit - 200 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Winter")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🤵 Suit - 400 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Suit")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🐆 Animal (Leopard) - 250 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Animal_Leopard")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🔵 Striped Blue - 180 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Striped_Blue")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🔴 Striped Red - 180 CC", function()
			local ok, msg = invokeShop("Clothing", "Buy", "Striped_Red")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("⛓️ Gold Chain - 200 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Chain")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("💎 Earrings - 150 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Earrings")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🕶️ Sunglasses - 200 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Sunglasses")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("👟 Sneakers - 200 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Sneakers")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("👞 Formal Shoes - 300 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Shoes")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🧢 Baseball Cap - 150 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Cap")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🎩 Hat - 250 CC", function()
			local ok, msg = invokeShop("Clothing", "BuyAccessory", "Hat")
			notify(msg, ok)
			refreshMoneyTop()
		end)
	elseif shopName == "Barbershop" then
		addBuyRow("✂️ Classic Cut - 100 CC", function()
			local ok, msg = invokeShop("Barbershop", "Buy", "Classic")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("💈 Modern Style - 200 CC", function()
			local ok, msg = invokeShop("Barbershop", "Buy", "Modern")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("👑 Luxury Style - 350 CC", function()
			local ok, msg = invokeShop("Barbershop", "Buy", "Luxury")
			notify(msg, ok)
			refreshMoneyTop()
		end)
	elseif shopName == "Electronics" then
		addBuyRow("📱 Smartphone - 300 CC", function()
			local ok, msg = invokeShop("Electronics", "Buy", "Phone")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("⌚ Smart Watch - 500 CC", function()
			local ok, msg = invokeShop("Electronics", "Buy", "Watch")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("💻 Laptop - 800 CC", function()
			local ok, msg = invokeShop("Electronics", "Buy", "Laptop")
			notify(msg, ok)
			refreshMoneyTop()
		end)
	elseif shopName == "Grocery" then
		addBuyRow("🍞 Bread - 20 CC (+2 rep)", function()
			local ok, msg = invokeShop("Grocery", "Buy", "Bread")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🍎 Fruits - 40 CC (+5 rep)", function()
			local ok, msg = invokeShop("Grocery", "Buy", "Fruits")
			notify(msg, ok)
			refreshMoneyTop()
		end)
		addBuyRow("🥦 Vegetables - 60 CC (+8 rep)", function()
			local ok, msg = invokeShop("Grocery", "Buy", "Vegetables")
			notify(msg, ok)
			refreshMoneyTop()
		end)
	elseif shopName == "Pharmacy" then
		addBuyRow("💊 Medicine - 100 CC (30min immunity)", function()
			local ok, msg = invokeShop("Pharmacy", "Buy")
			notify(msg, ok)
			refreshMoneyTop()
		end)
	else
		addLabel("Unknown shop type.", 0, false)
	end
end

local function closeShop()
	bankLoopGen += 1
	rootPanel.Size = UDim2.fromOffset(DEFAULT_PANEL_SIZE.X, DEFAULT_PANEL_SIZE.Y)
	rootPanel.Visible = false
	clearScroll()
	if wardrobePanel == nil or not wardrobePanel.Visible then
		screenGui.Enabled = false
	end
end

-- Wire shops after UI exists; handles streaming via DescendantAdded (GetDescendants may be empty early).
local function wireAllShops()
	local commercial = Workspace:WaitForChild("CommercialZone", 15)
	if not commercial then
		warn("[CLIENT] ShopUI: CommercialZone not found")
		return
	end

	local shopMap: { [string]: string } = {
		Grocery = "Grocery",
		Clothing = "Clothing",
		Pharmacy = "Pharmacy",
		Restaurant = "Restaurant",
		Electronics = "Electronics",
		Bank = "Bank",
		Barbershop = "Barbershop",
	}

	local wired: { [string]: boolean } = {}

	local function tryWirePrompt(desc: Instance)
		if not desc:IsA("ProximityPrompt") then
			return
		end
		local ancestor: Instance? = desc.Parent
		while ancestor and ancestor ~= commercial do
			local mapped = shopMap[ancestor.Name]
			if mapped and not wired[mapped] then
				local shopName = mapped
				wired[shopName] = true
				desc.Triggered:Connect(function()
					print("[CLIENT] ShopUI triggered:", shopName)
					openShop(shopName)
				end)
				print("[CLIENT] ShopUI wired:", shopName)
				return
			end
			ancestor = ancestor.Parent
		end
	end

	for _, desc in commercial:GetDescendants() do
		tryWirePrompt(desc)
	end

	commercial.DescendantAdded:Connect(tryWirePrompt)

	print("[CLIENT] ShopUI watching for shops")
end

-- ——— Build UI ———
screenGui = Instance.new("ScreenGui")
screenGui.Name = "MyCityShopUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = PlayerGui

rootPanel = Instance.new("Frame")
rootPanel.Name = "ShopPanel"
rootPanel.Size = UDim2.fromOffset(500, 550)
rootPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
rootPanel.AnchorPoint = Vector2.new(0.5, 0.5)
rootPanel.BackgroundColor3 = BG_PANEL
rootPanel.BorderSizePixel = 0
rootPanel.Visible = false
rootPanel.ZIndex = 50
rootPanel.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Parent = rootPanel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = CORNER
panelCorner.Parent = rootPanel

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = NAVY
header.BorderSizePixel = 0
header.Parent = rootPanel
local hc = Instance.new("UICorner")
hc.CornerRadius = CORNER
hc.Parent = header

titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.Size = UDim2.new(1, -100, 1, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 20
titleLabel.TextColor3 = TEXT_WHITE
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Shop"
titleLabel.Parent = header

moneyTopLabel = Instance.new("TextLabel")
moneyTopLabel.BackgroundTransparency = 1
moneyTopLabel.Position = UDim2.new(0, 14, 0, 58)
moneyTopLabel.Size = UDim2.new(1, -28, 0, 26)
moneyTopLabel.Font = Enum.Font.GothamBold
moneyTopLabel.TextSize = 16
moneyTopLabel.TextColor3 = MONEY_GOLD
moneyTopLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyTopLabel.Text = "🪙 Wallet: —"
moneyTopLabel.Parent = rootPanel

scroll = Instance.new("ScrollingFrame")
scroll.Name = "ItemList"
scroll.Position = UDim2.new(0, 8, 0, 92)
scroll.Size = UDim2.new(1, -16, 1, -100)
scroll.BackgroundColor3 = Color3.fromRGB(12, 12, 24)
scroll.BackgroundTransparency = 0.35
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = ACCENT
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = rootPanel
local sc = Instance.new("UICorner")
sc.CornerRadius = CORNER
sc.Parent = scroll

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local padScroll = Instance.new("UIPadding")
padScroll.PaddingTop = UDim.new(0, 8)
padScroll.PaddingBottom = UDim.new(0, 12)
padScroll.PaddingLeft = UDim.new(0, 8)
padScroll.PaddingRight = UDim.new(0, 8)
padScroll.Parent = scroll

closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.Position = UDim2.new(1, -35, 0, 10)
closeBtn.AnchorPoint = Vector2.new(0, 0)
closeBtn.ZIndex = 10
closeBtn.BackgroundColor3 = ACCENT
closeBtn.TextColor3 = TEXT_WHITE
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.AutoButtonColor = false
closeBtn.Parent = rootPanel
local closeC = Instance.new("UICorner")
closeC.CornerRadius = CORNER
closeC.Parent = closeBtn
closeBtn.MouseButton1Click:Connect(closeShop)

-- ——— Wardrobe UI (house) ———
local WARDROBE_W, WARDROBE_H = 550, 600
local CORE_OUTFITS: { { id: string, label: string } } = {
	{ id = "Default", label = "Default" },
	{ id = "Casual", label = "Casual" },
	{ id = "Business", label = "Business" },
	{ id = "Luxury", label = "Luxury" },
	{ id = "Summer", label = "Summer" },
	{ id = "Winter", label = "Winter" },
	{ id = "Suit", label = "Suit" },
	{ id = "Animal_Leopard", label = "Animal (Leopard)" },
	{ id = "Striped_Blue", label = "Striped Blue" },
	{ id = "Striped_Red", label = "Striped Red" },
}

local function listHasString(list: { string }, name: string): boolean
	for _, s in list do
		if s == name then
			return true
		end
	end
	return false
end

wardrobePanel = Instance.new("Frame")
wardrobePanel.Name = "WardrobePanel"
wardrobePanel.Size = UDim2.fromOffset(WARDROBE_W, WARDROBE_H)
wardrobePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
wardrobePanel.AnchorPoint = Vector2.new(0.5, 0.5)
wardrobePanel.BackgroundColor3 = BG_PANEL
wardrobePanel.BorderSizePixel = 0
wardrobePanel.Visible = false
wardrobePanel.ZIndex = 60
wardrobePanel.Parent = screenGui

local wStroke = Instance.new("UIStroke")
wStroke.Color = ACCENT
wStroke.Thickness = 1
wStroke.Transparency = 0.5
wStroke.Parent = wardrobePanel

local wCorner = Instance.new("UICorner")
wCorner.CornerRadius = CORNER
wCorner.Parent = wardrobePanel

local wHeader = Instance.new("Frame")
wHeader.Size = UDim2.new(1, 0, 0, 52)
wHeader.BackgroundColor3 = NAVY
wHeader.BorderSizePixel = 0
wHeader.Parent = wardrobePanel
local wHc = Instance.new("UICorner")
wHc.CornerRadius = CORNER
wHc.Parent = wHeader

local wTitle = Instance.new("TextLabel")
wTitle.BackgroundTransparency = 1
wTitle.Position = UDim2.new(0, 14, 0, 0)
wTitle.Size = UDim2.new(1, -100, 1, 0)
wTitle.Font = Enum.Font.GothamBold
wTitle.TextSize = 20
wTitle.TextColor3 = TEXT_WHITE
wTitle.TextXAlignment = Enum.TextXAlignment.Left
wTitle.Text = "👗 My Wardrobe"
wTitle.Parent = wHeader

local wClose = Instance.new("TextButton")
wClose.Name = "CloseWardrobe"
wClose.Size = UDim2.fromOffset(36, 36)
wClose.Position = UDim2.new(1, -35, 0, 10)
wClose.ZIndex = 11
wClose.BackgroundColor3 = ACCENT
wClose.TextColor3 = TEXT_WHITE
wClose.Text = "✕"
wClose.Font = Enum.Font.GothamBold
wClose.TextSize = 15
wClose.AutoButtonColor = false
wClose.Parent = wardrobePanel
local wCloseC = Instance.new("UICorner")
wCloseC.CornerRadius = CORNER
wCloseC.Parent = wClose

local wScroll = Instance.new("ScrollingFrame")
wScroll.Name = "WardrobeScroll"
wScroll.Position = UDim2.new(0, 8, 0, 60)
wScroll.Size = UDim2.new(1, -16, 1, -68)
wScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 24)
wScroll.BackgroundTransparency = 0.35
wScroll.BorderSizePixel = 0
wScroll.ScrollBarThickness = 6
wScroll.ScrollBarImageColor3 = ACCENT
wScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
wScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
wScroll.Parent = wardrobePanel
local wSc = Instance.new("UICorner")
wSc.CornerRadius = CORNER
wSc.Parent = wScroll

local wList = Instance.new("UIListLayout")
wList.Padding = UDim.new(0, 10)
wList.SortOrder = Enum.SortOrder.LayoutOrder
wList.Parent = wScroll

local wPad = Instance.new("UIPadding")
wPad.PaddingTop = UDim.new(0, 8)
wPad.PaddingBottom = UDim.new(0, 12)
wPad.PaddingLeft = UDim.new(0, 8)
wPad.PaddingRight = UDim.new(0, 8)
wPad.Parent = wScroll

local function clearWardrobeScroll()
	for _, c in wScroll:GetChildren() do
		if c:IsA("UIListLayout") or c:IsA("UIPadding") then
			continue
		end
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function wSectionTitle(text: string)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -8, 0, 24)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 16
	t.TextColor3 = ACCENT
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = text
	t.Parent = wScroll
end

local function wDivider()
	local d = Instance.new("Frame")
	d.Size = UDim2.new(1, -8, 0, 1)
	d.BackgroundColor3 = TEXT_MUTED
	d.BackgroundTransparency = 0.65
	d.BorderSizePixel = 0
	d.Parent = wScroll
end

local function refreshWardrobeUI()
	clearWardrobeScroll()
	local ownedRaw = safeInvoke(GetOwnedOutfits)
	local owned: { string } = {}
	local accPayload: any = nil
	if typeof(ownedRaw) == "table" and typeof((ownedRaw :: any).outfits) == "table" then
		for _, n in (ownedRaw :: any).outfits :: { any } do
			if typeof(n) == "string" then
				table.insert(owned, n)
			end
		end
		accPayload = (ownedRaw :: any).accessories
	elseif typeof(ownedRaw) == "table" then
		for _, n in ownedRaw :: { any } do
			if typeof(n) == "string" then
				table.insert(owned, n)
			end
		end
	end
	local data = safeInvoke(GetPlayerData)
	local currentOutfit = "Default"
	if typeof(data) == "table" and typeof(data.Outfit) == "string" then
		currentOutfit = data.Outfit
	end

	wSectionTitle("🧥 Outfits")
	for _, def in CORE_OUTFITS do
		local id = def.id
		local isDefault = id == "Default"
		local isOwned = isDefault or listHasString(owned, id)
		local isEquipped = currentOutfit == id

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 44)
		row.BackgroundColor3 = PANEL_BODY
		row.BorderSizePixel = 0
		row.Parent = wScroll
		local rc = Instance.new("UICorner")
		rc.CornerRadius = CORNER
		rc.Parent = row
		local rp = Instance.new("UIPadding")
		rp.PaddingLeft = UDim.new(0, 10)
		rp.PaddingRight = UDim.new(0, 10)
		rp.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Position = UDim2.new(0, 0, 0, 0)
		nameLbl.Size = UDim2.new(1, -120, 1, 0)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 15
		nameLbl.TextColor3 = if isOwned then TEXT_WHITE else TEXT_MUTED
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = (if isEquipped then "✅ " else "") .. def.label
		nameLbl.Parent = row

		if isOwned then
			local eq = Instance.new("TextButton")
			eq.Size = UDim2.new(0, 100, 0, 32)
			eq.Position = UDim2.new(1, -100, 0.5, -16)
			eq.BackgroundColor3 = ACCENT
			eq.TextColor3 = TEXT_WHITE
			eq.Font = Enum.Font.GothamBold
			eq.TextSize = 13
			eq.Text = "Equip"
			eq.AutoButtonColor = false
			eq.Parent = row
			local ec = Instance.new("UICorner")
			ec.CornerRadius = CORNER
			ec.Parent = eq
			eq.MouseButton1Click:Connect(function()
				local ok, msg = invokeShop("Clothing", "Equip", id)
				if ok then
					notify("Outfit equipped!", true)
					refreshWardrobeUI()
				else
					notify(msg, false)
				end
			end)
		else
			local hint = Instance.new("TextLabel")
			hint.BackgroundTransparency = 1
			hint.Position = UDim2.new(1, -200, 0, 0)
			hint.Size = UDim2.new(0, 190, 1, 0)
			hint.Font = Enum.Font.Gotham
			hint.TextSize = 12
			hint.TextColor3 = TEXT_MUTED
			hint.TextXAlignment = Enum.TextXAlignment.Right
			hint.Text = "Buy at Clothing Shop"
			hint.Parent = row
		end
	end

	wDivider()
	wSectionTitle("💍 Accessories")

	local function accField(key: string): any
		if typeof(accPayload) == "table" then
			local v = (accPayload :: any)[key]
			if v ~= nil then
				return v
			end
		end
		if typeof(data) == "table" then
			return (data :: any)[key]
		end
		return nil
	end

	local function accessoryRowBool(icon: string, label: string, key: string)
		local v = accField(key)
		local owned = v == true
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 40)
		row.BackgroundTransparency = 1
		row.Parent = wScroll
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 14
		lbl.TextColor3 = TEXT_WHITE
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		local status = if owned then "Owned" else "Not owned"
		lbl.Text = string.format("%s %s — %s", icon, label, status)
		lbl.Parent = row
	end

	local function accessoryRowString(icon: string, label: string, key: string)
		local v = accField(key)
		local status = "Not owned"
		if typeof(v) == "string" and v ~= "" and v ~= "None" then
			status = v
		end
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 40)
		row.BackgroundTransparency = 1
		row.Parent = wScroll
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 14
		lbl.TextColor3 = TEXT_WHITE
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = string.format("%s %s — %s", icon, label, status)
		lbl.Parent = row
	end

	accessoryRowBool("⛓️", "Chain", "Chain")
	accessoryRowBool("✨", "Earrings", "Earrings")
	accessoryRowBool("🕶️", "Sunglasses", "Sunglasses")
	accessoryRowBool("📱", "Phone", "Phone")
	accessoryRowBool("⌚", "Watch", "Watch")
	accessoryRowBool("💻", "Laptop", "Laptop")
	accessoryRowString("👟", "Sneakers", "Sneakers")
	accessoryRowString("👞", "Shoes", "Shoes")
	accessoryRowString("🧢", "Cap", "Cap")
	accessoryRowString("🎩", "Hat", "Hat")

	wDivider()
	local goShop = Instance.new("TextButton")
	goShop.Text = "🏪 Go to Clothing Shop"
	goShop.Size = UDim2.new(1, -8, 0, 44)
	goShop.BackgroundColor3 = PANEL_BODY
	goShop.TextColor3 = TEXT_WHITE
	goShop.Font = Enum.Font.GothamBold
	goShop.TextSize = 14
	goShop.AutoButtonColor = false
	goShop.Parent = wScroll
	local gc = Instance.new("UICorner")
	gc.CornerRadius = CORNER
	gc.Parent = goShop
	goShop.MouseButton1Click:Connect(function()
		if wardrobePanel then
			wardrobePanel.Visible = false
		end
		if not rootPanel.Visible then
			screenGui.Enabled = false
		end
		notify("Visit the Clothing Shop in the Commercial Zone!", true)
	end)
end

local function closeWardrobe()
	if wardrobePanel then
		wardrobePanel.Visible = false
	end
	if not rootPanel.Visible then
		screenGui.Enabled = false
	end
end

local function openWardrobe()
	if not wardrobePanel then
		return
	end
	refreshWardrobeUI()
	wardrobePanel.Visible = true
	screenGui.Enabled = true
end

wClose.MouseButton1Click:Connect(closeWardrobe)

OpenWardrobe.OnClientEvent:Connect(function()
	openWardrobe()
end)

assert(ShowNotification ~= nil, "[ShopUI] ShowNotification missing from RemoteConfig")
assert(OpenWardrobe ~= nil, "[ShopUI] OpenWardrobe missing from RemoteConfig")

task.spawn(wireAllShops)

print("[CLIENT] ShopUI ready")
