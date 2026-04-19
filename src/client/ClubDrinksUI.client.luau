local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig"))

local existingGui = PlayerGui:FindFirstChild("ClubDrinksHUD")
if existingGui and existingGui:IsA("ScreenGui") then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ClubDrinksHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = PlayerGui

local activePanel: Frame? = nil
local activeScale: UIScale? = nil
local drinksList: ScrollingFrame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil

local function roundFrame(frame: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
end

local function makeStroke(frame: GuiObject, color: Color3, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = 1.2
	stroke.Parent = frame
end

local function ensureUI()
	if activePanel and activePanel.Parent and activeScale and drinksList and titleLabel and subtitleLabel then
		return
	end

	local panel = Instance.new("Frame")
	panel.Name = "ClubDrinksPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	panel.Size = UDim2.fromOffset(420, 430)
	panel.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
	panel.Visible = false
	panel.Parent = screenGui
	roundFrame(panel, 18)
	makeStroke(panel, Color3.fromRGB(115, 155, 235), 0.35)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 27, 38)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 18)),
	})
	gradient.Rotation = 90
	gradient.Parent = panel

	local scale = Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -28, 0, 76)
	header.Position = UDim2.fromOffset(14, 14)
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -48, 0, 36)
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Nightclub Bar"
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 38)
	subtitle.Size = UDim2.new(1, -48, 0, 28)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = Color3.fromRGB(180, 190, 210)
	subtitle.TextSize = 15
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Escolha um drink"
	subtitle.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.TextSize = 18
	close.Parent = header
	roundFrame(close, 12)

	local list = Instance.new("ScrollingFrame")
	list.Name = "DrinksList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(14, 100)
	list.Size = UDim2.new(1, -28, 1, -114)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Color3.fromRGB(110, 150, 230)
	list.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 2)
	padding.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list

	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	activePanel = panel
	activeScale = scale
	drinksList = list
	titleLabel = title
	subtitleLabel = subtitle
end

local function clearList()
	if not drinksList then
		return
	end
	for _, child in drinksList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function openPanel()
	ensureUI()
	if not activePanel or not activeScale then
		return
	end
	activePanel.Visible = true
	activeScale.Scale = 0.92
	TweenService:Create(activeScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function closePanel()
	if activePanel then
		activePanel.Visible = false
	end
end

local function styleButton(btn: TextButton)
	roundFrame(btn, 10)
	makeStroke(btn, Color3.fromRGB(255, 255, 255), 0.82)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = btn.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.08) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(70, 110, 205) }):Play()
	end)
end

local function buildDrinkRow(clubName: string, row: { id: string, name: string, price: number }, layoutOrder: number)
	if not drinksList then
		return
	end

	local card = Instance.new("Frame")
	card.Name = row.id
	card.Size = UDim2.new(1, -4, 0, 72)
	card.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
	card.LayoutOrder = layoutOrder
	card.Parent = drinksList
	roundFrame(card, 14)
	makeStroke(card, Color3.fromRGB(255, 255, 255), 0.9)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(16, 10)
	nameLabel.Size = UDim2.new(1, -140, 0, 24)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextSize = 19
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = row.name
	nameLabel.Parent = card

	local priceLabel = Instance.new("TextLabel")
	priceLabel.BackgroundTransparency = 1
	priceLabel.Position = UDim2.fromOffset(16, 38)
	priceLabel.Size = UDim2.new(1, -160, 0, 20)
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.TextColor3 = Color3.fromRGB(245, 214, 110)
	priceLabel.TextSize = 15
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Text = string.format("$%d", row.price)
	priceLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -14, 0.5, 0)
	buyButton.Size = UDim2.fromOffset(96, 38)
	buyButton.BackgroundColor3 = Color3.fromRGB(70, 110, 205)
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Text = "Comprar"
	buyButton.TextColor3 = Color3.new(1, 1, 1)
	buyButton.TextSize = 16
	buyButton.Parent = card
	styleButton(buyButton)

	buyButton.MouseButton1Click:Connect(function()
		buyButton.Active = false
		buyButton.AutoButtonColor = false
		buyButton.Text = "..."

		local ok, message = pcall(function()
			return Remotes.PurchaseClubDrink:InvokeServer(clubName, row.id)
		end)

		buyButton.Active = true
		buyButton.AutoButtonColor = true
		buyButton.Text = "Comprar"

		if ok and message == true then
			closePanel()
		end
	end)
end

Remotes.OpenClubDrinks.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	ensureUI()
	if not titleLabel or not subtitleLabel then
		return
	end

	local clubName = typeof(payload.clubName) == "string" and payload.clubName or ""
	local clubDisplayName = typeof(payload.clubDisplayName) == "string" and payload.clubDisplayName or clubName
	local drinks = typeof(payload.drinks) == "table" and payload.drinks or {}

	titleLabel.Text = clubDisplayName
	subtitleLabel.Text = "Escolha um drink do cardápio"
	clearList()

	for index, row in ipairs(drinks) do
		if typeof(row) == "table" and typeof(row.id) == "string" and typeof(row.name) == "string" and typeof(row.price) == "number" then
			buildDrinkRow(clubName, row, index)
		end
	end

	openPanel()
end)
