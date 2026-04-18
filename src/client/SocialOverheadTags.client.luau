--[[
	Subtle in-world social identity above other players.
	Event-driven only (CharacterAdded / PlayerAdded / PlayerRemoving / SocialIdentityChanged)
	— no polling or per-frame scans.
]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Remotes = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig"))

local TAG_NAME = "SocialOverheadTag"

local BG = Color3.fromRGB(14, 18, 34)
local ACCENT = Color3.fromHex("e94560")
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_DIM = Color3.fromRGB(165, 170, 188)

local tagsByPlayer: { [Player]: BillboardGui } = {}

local function displayNameOf(plr: Player): string
	return plr.DisplayName ~= "" and plr.DisplayName or plr.Name
end

local function cleanupTag(plr: Player)
	local existing = tagsByPlayer[plr]
	tagsByPlayer[plr] = nil
	if existing and existing.Parent then
		existing:Destroy()
	end
	local char = plr.Character
	local head = char and char:FindFirstChild("Head")
	if head then
		local stray = head:FindFirstChild(TAG_NAME)
		if stray and stray:IsA("BillboardGui") then
			stray:Destroy()
		end
	end
end

local function buildTagGui(head: BasePart, plr: Player, snap: any?): BillboardGui
	local tierText = "Unknown"
	local showAvg = false
	local avgText = ""

	if typeof(snap) == "table" and snap.success == true then
		local t = typeof(snap.socialTier) == "string" and snap.socialTier or ""
		tierText = (t ~= "") and t or "Unknown"
		local avg = tonumber(snap.averageRating) or 0
		local tr = tonumber(snap.totalReviews) or 0
		if tr > 0 and avg > 0 then
			showAvg = true
			avgText = string.format("%.1f ★ avg", avg)
		end
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = TAG_NAME
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 55
	bb.Size = UDim2.fromOffset(188, if showAvg then 48 else 34)
	bb.StudsOffset = Vector3.new(0, 2.45, 0)
	bb.Parent = head

	local root = Instance.new("Frame")
	root.BackgroundColor3 = BG
	root.BackgroundTransparency = 0.14
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 1
	stroke.Transparency = 0.72
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = root

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Size = UDim2.new(1, 0, 0, 14)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 12
	nameLbl.TextColor3 = TEXT_WHITE
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = displayNameOf(plr)
	nameLbl.LayoutOrder = 1
	nameLbl.Parent = root

	local tierLbl = Instance.new("TextLabel")
	tierLbl.BackgroundTransparency = 1
	tierLbl.Size = UDim2.new(1, 0, 0, 12)
	tierLbl.Font = Enum.Font.Gotham
	tierLbl.TextSize = 10
	tierLbl.TextColor3 = TEXT_DIM
	tierLbl.TextXAlignment = Enum.TextXAlignment.Left
	tierLbl.TextTruncate = Enum.TextTruncate.AtEnd
	tierLbl.Text = tierText
	tierLbl.LayoutOrder = 2
	tierLbl.Parent = root

	if showAvg then
		local avgLbl = Instance.new("TextLabel")
		avgLbl.BackgroundTransparency = 1
		avgLbl.Size = UDim2.new(1, 0, 0, 11)
		avgLbl.Font = Enum.Font.Gotham
		avgLbl.TextSize = 10
		avgLbl.TextColor3 = TEXT_DIM
		avgLbl.TextTransparency = 0.12
		avgLbl.TextXAlignment = Enum.TextXAlignment.Left
		avgLbl.Text = avgText
		avgLbl.LayoutOrder = 3
		avgLbl.Parent = root
	end

	return bb
end

local function scheduleTagBuild(plr: Player, charToken: Model, head: BasePart)
	task.spawn(function()
		cleanupTag(plr)

		local ok, snap = pcall(function()
			return Remotes.GetPlayerSocialTagSnapshot:InvokeServer(plr.UserId)
		end)

		if not plr.Parent then
			return
		end
		if plr.Character ~= charToken then
			return
		end
		local currentHead = charToken:FindFirstChild("Head")
		if currentHead ~= head or not head:IsA("BasePart") or not head.Parent then
			return
		end

		local gui = buildTagGui(head, plr, if ok then snap else nil)
		tagsByPlayer[plr] = gui
	end)
end

local function attachForCharacter(plr: Player, char: Model)
	local head = char:WaitForChild("Head", 12)
	if not head or not head:IsA("BasePart") then
		return
	end

	scheduleTagBuild(plr, char, head)
end

local function refreshTagForUserId(userId: number)
	local plr = Players:GetPlayerByUserId(userId)
	if not plr or plr == LocalPlayer or not plr.Parent then
		return
	end
	local char = plr.Character
	if not char then
		return
	end
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	scheduleTagBuild(plr, char, head)
end

if Remotes.SocialIdentityChanged and Remotes.SocialIdentityChanged:IsA("RemoteEvent") then
	(Remotes.SocialIdentityChanged :: RemoteEvent).OnClientEvent:Connect(function(userId: any)
		if typeof(userId) ~= "number" then
			return
		end
		refreshTagForUserId(userId)
	end)
end

local function hookPlayer(plr: Player)
	if plr == LocalPlayer then
		return
	end

	plr.CharacterAdded:Connect(function(char)
		attachForCharacter(plr, char)
	end)

	if plr.Character then
		attachForCharacter(plr, plr.Character)
	end
end

for _, plr in Players:GetPlayers() do
	hookPlayer(plr)
end

Players.PlayerAdded:Connect(hookPlayer)

Players.PlayerRemoving:Connect(function(plr)
	cleanupTag(plr)
end)
