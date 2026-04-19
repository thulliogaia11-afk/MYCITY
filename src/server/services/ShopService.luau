--[[
	ShopService — MY CITY (Ironholm)
	Bank, restaurant, clothing, barber, electronics, grocery, pharmacy.
	All purchases debit Money via PlayerDataService; reputation via ReputationService.
]]

local Players = game:GetService("Players")

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)
local JobService = require((script.Parent :: Folder):WaitForChild("JobService") :: ModuleScript)

export type ShopResult = {
	success: boolean,
	message: string,
}

export type InvestmentRow = {
	originalAmount: number,
	currentValue: number,
	timeRemaining: number,
	projectedReturn: number,
}

local DEFAULT_INVEST_DURATION_SECONDS = 3600
local DEFAULT_INVEST_INTEREST_RATE = 0.05

-- ——— Helpers ———

local function ok(message: string): ShopResult
	return { success = true, message = message }
end

local function fail(message: string): ShopResult
	return { success = false, message = message }
end

local function logPurchase(player: Player, itemName: string, shopName: string, costCC: number)
	print(string.format("[%s] %s bought %s at %s shop for %d CC", GAME_LABEL, player.Name, itemName, shopName, costCC))
end

local function getData(player: Player): { [string]: any }
	return PlayerDataService.GetData(player)
end

local function spendMoney(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = getData(player)
	local money = data.Money
	if typeof(money) ~= "number" or money < amount then
		return false
	end
	return PlayerDataService.SetData(player, "Money", money - amount)
end

local function addMoney(player: Player, amount: number): boolean
	if amount < 0 then
		return false
	end
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = getData(player)
	local money = typeof(data.Money) == "number" and data.Money or 0
	return PlayerDataService.SetData(player, "Money", money + amount)
end

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildWhichIsA("Humanoid")
end

local function getOrCreateBodyColors(character: Model): BodyColors
	local bc = character:FindFirstChildOfClass("BodyColors")
	if bc then
		return bc
	end
	local n = Instance.new("BodyColors")
	n.Name = "BodyColors"
	n.Parent = character
	return n
end

-- Strip shirt/pants instances so BodyColors tints show (same idea as OutfitService).
local function stripClassicClothing(character: Model)
	for _, inst in character:GetChildren() do
		if inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic") then
			inst:Destroy()
		end
	end
end

export type ClothingOutfitColors = {
	HeadColor: Color3,
	UpperTorsoColor: Color3,
	LowerTorsoColor: Color3,
	LeftArmColor: Color3,
	RightArmColor: Color3,
	LeftLegColor: Color3,
	RightLegColor: Color3,
}

local function applyClothingOutfitToCharacter(character: Model, colors: ClothingOutfitColors)
	stripClassicClothing(character)
	local bc = getOrCreateBodyColors(character)
	bc.HeadColor3 = colors.HeadColor
	bc.LeftArmColor3 = colors.LeftArmColor
	bc.RightArmColor3 = colors.RightArmColor
	bc.LeftLegColor3 = colors.LeftLegColor
	bc.RightLegColor3 = colors.RightLegColor
	bc.TorsoColor3 = colors.UpperTorsoColor
	local anyBc = bc :: any
	pcall(function()
		anyBc.UpperTorsoColor3 = colors.UpperTorsoColor
		anyBc.LowerTorsoColor3 = colors.LowerTorsoColor
	end)
end

local function applyDefaultAvatarBody(player: Player, character: Model)
	local hum = getHumanoid(character)
	if not hum then
		return
	end
	local ok, err = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		hum:ApplyDescription(desc)
	end)
	if not ok then
		warn(string.format("[%s] applyDefaultAvatarBody failed for %s: %s", GAME_LABEL, player.Name, tostring(err)))
	end
end

local function tryApplyCharacter(player: Player, apply: (Model) -> ())
	local char = player.Character
	if char then
		apply(char)
	end
end

-- Pharmacy / misc session flags (not persisted).
local pharmacySessionNote: { [Player]: string } = {}

local ShopService = {}

function ShopService.GetPharmacySessionNote(player: Player): string
	return pharmacySessionNote[player] or ""
end

-- ——— BANK ———

function ShopService.GetBankBalance(player: Player): ShopResult
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = PlayerDataService.GetData(player)
	local bankBal = typeof(data.BankBalance) == "number" and math.floor(data.BankBalance) or 0
	return ok(string.format("Bank balance: %d CC", bankBal))
end

function ShopService.DepositMoney(player: Player, amount: number): ShopResult
	if typeof(amount) ~= "number" or amount <= 0 or amount ~= math.floor(amount) then
		return fail("Invalid amount.")
	end
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = PlayerDataService.GetData(player)

	print("[MY CITY] ShopService.DepositMoney:", player.Name, "amount:", amount)

	local wallet = typeof(data.Money) == "number" and math.floor(data.Money) or 0
	local bank = typeof(data.BankBalance) == "number" and math.floor(data.BankBalance) or 0
	print("[MY CITY] Before deposit - Money:", wallet, "Bank:", bank)

	if wallet < amount then
		return fail("Not enough CC in wallet.")
	end

	local newMoney = wallet - amount
	local newBank = bank + amount

	if not PlayerDataService.SetData(player, "Money", newMoney) then
		return fail("Could not update wallet.")
	end
	if not PlayerDataService.SetData(player, "BankBalance", newBank) then
		PlayerDataService.SetData(player, "Money", wallet)
		return fail("Could not update bank (wallet rolled back).")
	end

	print("[MY CITY] After deposit - Money:", newMoney, "Bank:", newBank)

	logPurchase(player, string.format("deposit %d CC", amount), "Bank", amount)
	return ok("Deposited " .. tostring(amount) .. " CC to bank. Balance: " .. tostring(newBank))
end

function ShopService.WithdrawMoney(player: Player, amount: number): ShopResult
	if typeof(amount) ~= "number" or amount <= 0 or amount ~= math.floor(amount) then
		return fail("Invalid amount.")
	end
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)
	local bank = typeof(data.BankBalance) == "number" and data.BankBalance or 0
	if bank < amount then
		return fail("Not enough CC in bank.")
	end
	local credit = math.floor(amount * 0.9)
	local fee = amount - credit
	local wallet = typeof(data.Money) == "number" and data.Money or 0
	if not PlayerDataService.SetData(player, "BankBalance", bank - amount) then
		return fail("Could not update bank.")
	end
	if not PlayerDataService.SetData(player, "Money", wallet + credit) then
		PlayerDataService.SetData(player, "BankBalance", bank)
		return fail("Could not credit wallet (rolled back).")
	end
	logPurchase(player, string.format("withdraw %d CC (fee %d CC)", amount, fee), "Bank", fee)
	return ok(string.format("Withdrew %d CC from bank; %d CC added to wallet (10%% fee: %d CC).", amount, credit, fee))
end

local function normalizeInvestmentEntry(entry: any): { amount: number, startTime: number, durationSeconds: number, interestRate: number }?
	if typeof(entry) ~= "table" then
		return nil
	end
	if typeof(entry.amount) == "number" and typeof(entry.startTime) == "number" then
		return {
			amount = entry.amount,
			startTime = entry.startTime,
			durationSeconds = if typeof(entry.durationSeconds) == "number"
				then entry.durationSeconds
				else DEFAULT_INVEST_DURATION_SECONDS,
			interestRate = if typeof(entry.interestRate) == "number" then entry.interestRate else DEFAULT_INVEST_INTEREST_RATE,
		}
	end
	if typeof(entry.principal) == "number" and typeof(entry.maturesAt) == "number" and entry.paid == false then
		return {
			amount = entry.principal,
			startTime = entry.maturesAt - DEFAULT_INVEST_DURATION_SECONDS,
			durationSeconds = DEFAULT_INVEST_DURATION_SECONDS,
			interestRate = DEFAULT_INVEST_INTEREST_RATE,
		}
	end
	return nil
end

function ShopService.Invest(player: Player, amount: number): ShopResult
	if typeof(amount) ~= "number" or amount <= 0 or amount ~= math.floor(amount) then
		return fail("Invalid amount.")
	end
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = PlayerDataService.GetData(player)
	local wallet = typeof(data.Money) == "number" and math.floor(data.Money) or 0
	if wallet < amount then
		return fail("Not enough CC to invest.")
	end

	print(string.format("[%s] ShopService.Invest: %s amount=%d", GAME_LABEL, player.Name, amount))

	if not spendMoney(player, amount) then
		return fail("Payment failed.")
	end

	local inv = data.Investments
	if typeof(inv) ~= "table" then
		inv = {}
	end
	local list = table.clone(inv :: { any })
	table.insert(list, {
		amount = amount,
		startTime = os.time(),
		durationSeconds = DEFAULT_INVEST_DURATION_SECONDS,
		interestRate = DEFAULT_INVEST_INTEREST_RATE,
	})

	if not PlayerDataService.SetData(player, "Investments", list) then
		addMoney(player, amount)
		print(string.format("[%s] ShopService.Invest: save failed, refunded %s", GAME_LABEL, player.Name))
		return fail("Could not record investment (refunded).")
	end

	logPurchase(player, string.format("investment %d CC", amount), "Bank", amount)
	print(string.format("[%s] ShopService.Invest: %s recorded new investment slot", GAME_LABEL, player.Name))
	return ok("Invested " .. tostring(amount) .. " CC at 5% per hour")
end

function ShopService.GetInvestments(player: Player): { InvestmentRow }
	if not PlayerDataService.HasSession(player) then
		return {}
	end
	local data = PlayerDataService.GetData(player)
	if typeof(data.Investments) ~= "table" then
		return {}
	end
	local out: { InvestmentRow } = {}
	local now = os.time()
	for _, entry in data.Investments :: { any } do
		local n = normalizeInvestmentEntry(entry)
		if not n then
			continue
		end
		local elapsed = math.max(0, now - n.startTime)
		local cappedElapsed = math.min(elapsed, n.durationSeconds)
		local earned = n.amount * n.interestRate * (cappedElapsed / n.durationSeconds)
		local currentValue = math.floor(n.amount + earned)
		local timeRemaining = math.max(0, n.durationSeconds - elapsed)
		local projectedReturn = math.floor(n.amount * (1 + n.interestRate))
		table.insert(out, {
			originalAmount = n.amount,
			currentValue = currentValue,
			timeRemaining = timeRemaining,
			projectedReturn = projectedReturn,
		})
	end
	return out
end

function ShopService.ProcessInvestmentsForPlayer(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = PlayerDataService.GetData(player)
	if typeof(data.Investments) ~= "table" then
		return
	end

	local list = data.Investments :: { any }
	local oldSnapshot = table.clone(list)
	local now = os.time()
	local newList: { any } = {}
	local totalPayout = 0
	local dirty = false

	for _, entry in list do
		local n = normalizeInvestmentEntry(entry)
		if not n then
			dirty = true
			print(string.format("[%s] ShopService.ProcessInvestments: dropped invalid entry for %s", GAME_LABEL, player.Name))
			continue
		end

		local elapsed = math.max(0, now - n.startTime)
		local cappedElapsed = math.min(elapsed, n.durationSeconds)
		local earned = n.amount * n.interestRate * (cappedElapsed / n.durationSeconds)
		local currentValue = math.floor(n.amount + earned)

		if elapsed >= n.durationSeconds then
			local payout = math.floor(n.amount * (1 + n.interestRate))
			totalPayout += payout
			dirty = true
			print(
				string.format(
					"[%s] Investment matured: %s +%d CC (principal %d, rate %.2f)",
					GAME_LABEL,
					player.Name,
					payout,
					n.amount,
					n.interestRate
				)
			)
		else
			local stored: { [string]: any } = {
				amount = n.amount,
				startTime = n.startTime,
				durationSeconds = n.durationSeconds,
				interestRate = n.interestRate,
				currentValue = currentValue,
			}
			table.insert(newList, stored)
			if typeof(entry.currentValue) ~= "number" or entry.currentValue ~= currentValue then
				dirty = true
			end
		end
	end

	if not (dirty or totalPayout > 0) then
		return
	end

	if not PlayerDataService.SetData(player, "Investments", newList) then
		warn(string.format("[%s] ShopService.ProcessInvestments: failed to save Investments for %s", GAME_LABEL, player.Name))
		return
	end

	if totalPayout > 0 then
		if not addMoney(player, totalPayout) then
			PlayerDataService.SetData(player, "Investments", oldSnapshot)
			warn(string.format("[%s] ShopService.ProcessInvestments: payout failed, restored Investments for %s", GAME_LABEL, player.Name))
			return
		end
		print(string.format("[%s] ShopService.ProcessInvestments: %s credited %d CC from investments", GAME_LABEL, player.Name, totalPayout))
	end

	print(string.format("[%s] ShopService.ProcessInvestments: %s now has %d active investment(s)", GAME_LABEL, player.Name, #newList))
end

local function investmentHeartbeat()
	while true do
		task.wait(60)
		for _, plr in Players:GetPlayers() do
			task.spawn(ShopService.ProcessInvestmentsForPlayer, plr)
		end
	end
end

-- ——— RESTAURANT ———

local MEALS: { [string]: { price: number, rep: number, xp: number } } = {
	Sandwich = { price = 50, rep = 5, xp = 10 },
	["Full Meal"] = { price = 150, rep = 15, xp = 30 },
	Premium = { price = 300, rep = 30, xp = 60 },
}

function ShopService.BuyMeal(player: Player, mealType: string): ShopResult
	local m = MEALS[mealType]
	if not m then
		return fail("Unknown meal.")
	end
	if not spendMoney(player, m.price) then
		return fail("Not enough CC.")
	end
	ReputationService.AddReputation(player, m.rep, "Restaurant: " .. mealType)
	local data = getData(player)
	if data then
		local xp = (typeof(data.XP) == "number" and data.XP or 0) + m.xp
		PlayerDataService.SetData(player, "XP", xp)
	end
	logPurchase(player, mealType, "Restaurant", m.price)
	return ok(string.format("Enjoy your %s! +%d rep, +%d XP.", mealType, m.rep, m.xp))
end

-- ——— CLOTHING (BodyColors; prices separate) ———

local CLOTHING_OUTFITS: { [string]: ClothingOutfitColors } = {
	Casual = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(100, 150, 255),
		LowerTorsoColor = Color3.fromRGB(50, 80, 200),
		LeftArmColor = Color3.fromRGB(255, 220, 185),
		RightArmColor = Color3.fromRGB(255, 220, 185),
		LeftLegColor = Color3.fromRGB(30, 50, 150),
		RightLegColor = Color3.fromRGB(30, 50, 150),
	},
	Business = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(30, 30, 30),
		LowerTorsoColor = Color3.fromRGB(30, 30, 50),
		LeftArmColor = Color3.fromRGB(255, 220, 185),
		RightArmColor = Color3.fromRGB(255, 220, 185),
		LeftLegColor = Color3.fromRGB(20, 20, 40),
		RightLegColor = Color3.fromRGB(20, 20, 40),
	},
	Luxury = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(180, 140, 20),
		LowerTorsoColor = Color3.fromRGB(150, 110, 10),
		LeftArmColor = Color3.fromRGB(255, 220, 185),
		RightArmColor = Color3.fromRGB(255, 220, 185),
		LeftLegColor = Color3.fromRGB(120, 80, 5),
		RightLegColor = Color3.fromRGB(120, 80, 5),
	},
	Summer = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(255, 200, 50),
		LowerTorsoColor = Color3.fromRGB(50, 150, 255),
		LeftArmColor = Color3.fromRGB(255, 220, 185),
		RightArmColor = Color3.fromRGB(255, 220, 185),
		LeftLegColor = Color3.fromRGB(30, 100, 200),
		RightLegColor = Color3.fromRGB(30, 100, 200),
	},
	Winter = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(120, 30, 30),
		LowerTorsoColor = Color3.fromRGB(20, 20, 20),
		LeftArmColor = Color3.fromRGB(100, 25, 25),
		RightArmColor = Color3.fromRGB(100, 25, 25),
		LeftLegColor = Color3.fromRGB(15, 15, 15),
		RightLegColor = Color3.fromRGB(15, 15, 15),
	},
	Suit = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(40, 40, 50),
		LowerTorsoColor = Color3.fromRGB(35, 35, 45),
		LeftArmColor = Color3.fromRGB(255, 220, 185),
		RightArmColor = Color3.fromRGB(255, 220, 185),
		LeftLegColor = Color3.fromRGB(30, 30, 40),
		RightLegColor = Color3.fromRGB(30, 30, 40),
	},
	Animal_Leopard = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(200, 120, 20),
		LowerTorsoColor = Color3.fromRGB(180, 100, 10),
		LeftArmColor = Color3.fromRGB(200, 120, 20),
		RightArmColor = Color3.fromRGB(200, 120, 20),
		LeftLegColor = Color3.fromRGB(160, 80, 5),
		RightLegColor = Color3.fromRGB(160, 80, 5),
	},
	Striped_Blue = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(50, 100, 200),
		LowerTorsoColor = Color3.fromRGB(200, 200, 220),
		LeftArmColor = Color3.fromRGB(50, 100, 200),
		RightArmColor = Color3.fromRGB(50, 100, 200),
		LeftLegColor = Color3.fromRGB(40, 80, 180),
		RightLegColor = Color3.fromRGB(40, 80, 180),
	},
	Striped_Red = {
		HeadColor = Color3.fromRGB(255, 220, 185),
		UpperTorsoColor = Color3.fromRGB(200, 50, 50),
		LowerTorsoColor = Color3.fromRGB(220, 200, 200),
		LeftArmColor = Color3.fromRGB(200, 50, 50),
		RightArmColor = Color3.fromRGB(200, 50, 50),
		LeftLegColor = Color3.fromRGB(180, 40, 40),
		RightLegColor = Color3.fromRGB(180, 40, 40),
	},
}

local OUTFIT_PRICE: { [string]: number } = {
	Casual = 100,
	Business = 300,
	Luxury = 500,
	Summer = 150,
	Winter = 200,
	Suit = 400,
	Animal_Leopard = 250,
	Striped_Blue = 180,
	Striped_Red = 180,
}

local ACCESSORY_COSTS: { [string]: number } = {
	Chain = 200,
	Earrings = 150,
	Sneakers = 200,
	Shoes = 300,
	Cap = 150,
	Hat = 250,
	Watch = 500,
	Phone = 300,
	Laptop = 800,
	Sunglasses = 200,
}

local ACCESSORY_BOOL_KEYS: { [string]: boolean } = {
	Chain = true,
	Earrings = true,
	Watch = true,
	Phone = true,
	Laptop = true,
	Sunglasses = true,
}

local ACCESSORY_STRING_KEYS: { [string]: boolean } = {
	Sneakers = true,
	Shoes = true,
	Cap = true,
	Hat = true,
}

local ACCESSORY_STRING_PURCHASE_VALUE: { [string]: string } = {
	Sneakers = "White",
	Shoes = "Formal",
	Cap = "Baseball",
	Hat = "Classic",
}

export type AccessorySnapshot = {
	Chain: boolean,
	Earrings: boolean,
	Sunglasses: boolean,
	Phone: boolean,
	Watch: boolean,
	Laptop: boolean,
	Sneakers: string,
	Shoes: string,
	Cap: string,
	Hat: string,
}

export type WardrobeSnapshot = {
	outfits: { string },
	accessories: AccessorySnapshot,
}

local function getOwnedOutfitsList(data: { [string]: any }): { string }
	local list = data.OwnedOutfits
	if typeof(list) ~= "table" then
		return {}
	end
	local out: { string } = {}
	for _, name in list do
		if typeof(name) == "string" then
			table.insert(out, name)
		end
	end
	return out
end

local function playerOwnsOutfit(data: { [string]: any }, outfitName: string): boolean
	for _, n in getOwnedOutfitsList(data) do
		if n == outfitName then
			return true
		end
	end
	return false
end

local function withOutfitAdded(owned: { string }, outfitName: string): { string }
	local nextList = table.clone(owned)
	for _, n in nextList do
		if n == outfitName then
			return nextList
		end
	end
	table.insert(nextList, outfitName)
	return nextList
end

local function accessorySnapshotFromData(data: { [string]: any }): AccessorySnapshot
	local anyData = data :: any
	return {
		Chain = anyData.Chain == true,
		Earrings = anyData.Earrings == true,
		Sunglasses = anyData.Sunglasses == true,
		Phone = anyData.Phone == true,
		Watch = anyData.Watch == true,
		Laptop = anyData.Laptop == true,
		Sneakers = if typeof(anyData.Sneakers) == "string" then anyData.Sneakers else "None",
		Shoes = if typeof(anyData.Shoes) == "string" then anyData.Shoes else "None",
		Cap = if typeof(anyData.Cap) == "string" then anyData.Cap else "None",
		Hat = if typeof(anyData.Hat) == "string" then anyData.Hat else "None",
	}
end

local function accessoryOwnedForVisual(data: { [string]: any }, accessoryName: string): boolean
	local anyData = data :: any
	if ACCESSORY_BOOL_KEYS[accessoryName] then
		return anyData[accessoryName] == true
	end
	if ACCESSORY_STRING_KEYS[accessoryName] then
		local v = anyData[accessoryName]
		return typeof(v) == "string" and v ~= "None" and v ~= ""
	end
	return false
end

-- Visual clothing accessories: welded Parts on the character (not HumanoidDescription).
local ACCESSORY_PART_ORDER = { "Hat", "Cap", "Sunglasses", "Earrings", "Chain", "Watch", "Shoes", "Sneakers" }

local function stripAccessoryParts(character: Model, accessoryName: string)
	local prefix = accessoryName .. "_Accessory"
	for _, obj in character:GetChildren() do
		if obj:IsA("BasePart") then
			local n = obj.Name
			if string.sub(n, 1, #prefix) == prefix then
				obj:Destroy()
			elseif accessoryName == "Sneakers" and n == "Sneaker_Accessory" then
				obj:Destroy()
			end
		end
	end
end

local function attachPart(part: BasePart, targetPart: BasePart, offsetCFrame: CFrame)
	local parentModel = targetPart.Parent
	if not parentModel then
		return
	end
	part.Anchored = false
	part.CanCollide = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = parentModel
	local weld = Instance.new("Weld")
	weld.Name = "AccessoryWeld"
	weld.Part0 = targetPart
	weld.Part1 = part
	weld.C0 = offsetCFrame
	weld.Parent = part
end

local ACCESSORY_PARTS: { [string]: (Model) -> () } = {
	Chain = function(character: Model)
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if not torso or not torso:IsA("BasePart") then
			return
		end
		local chain = Instance.new("Part")
		chain.Name = "Chain_Accessory"
		chain.Size = Vector3.new(0.9, 0.15, 0.9)
		chain.Color = Color3.fromRGB(255, 215, 0)
		chain.Material = Enum.Material.Metal
		attachPart(chain, torso, CFrame.new(0, 0.2, 0.35))
	end,

	Watch = function(character: Model)
		local arm = character:FindFirstChild("LeftLowerArm") or character:FindFirstChild("Left Arm")
		if not arm or not arm:IsA("BasePart") then
			return
		end
		local watch = Instance.new("Part")
		watch.Name = "Watch_Accessory"
		watch.Size = Vector3.new(0.4, 0.15, 0.4)
		watch.Color = Color3.fromRGB(200, 160, 20)
		watch.Material = Enum.Material.Metal
		attachPart(watch, arm, CFrame.new(0, 0, 0))
	end,

	Earrings = function(character: Model)
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return
		end
		for i, side in ipairs({ -0.55, 0.55 }) do
			local earring = Instance.new("Part")
			earring.Name = "Earrings_Accessory_" .. (if i == 1 then "L" else "R")
			earring.Shape = Enum.PartType.Ball
			earring.Size = Vector3.new(0.15, 0.15, 0.15)
			earring.Color = Color3.fromRGB(255, 215, 0)
			earring.Material = Enum.Material.Metal
			attachPart(earring, head, CFrame.new(side, -0.2, 0))
		end
	end,

	Sneakers = function(character: Model)
		for _, footName in ipairs({ "LeftFoot", "RightFoot" }) do
			local foot = character:FindFirstChild(footName)
			if foot and foot:IsA("BasePart") then
				local shoe = Instance.new("Part")
				shoe.Name = "Sneaker_Accessory"
				shoe.Size = Vector3.new(0.9, 0.35, 1.2)
				shoe.Color = Color3.fromRGB(240, 240, 240)
				shoe.Material = Enum.Material.SmoothPlastic
				shoe.CanCollide = false
				attachPart(shoe, foot, CFrame.new(0, -0.15, 0.1))
			end
		end
	end,

	Sunglasses = function(character: Model)
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return
		end
		local glasses = Instance.new("Part")
		glasses.Name = "Sunglasses_Accessory"
		glasses.Size = Vector3.new(1.0, 0.25, 0.2)
		glasses.Color = Color3.fromRGB(10, 10, 10)
		glasses.Material = Enum.Material.SmoothPlastic
		attachPart(glasses, head, CFrame.new(0, 0.1, 0.55))
	end,

	Shoes = function(character: Model)
		for _, footName in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
			local limb = character:FindFirstChild(footName)
			if limb and limb:IsA("BasePart") then
				local shoe = Instance.new("Part")
				shoe.Name = "Shoes_Accessory_" .. string.gsub(footName, "%s+", "")
				shoe.Size = Vector3.new(0.75, 0.25, 1.05)
				shoe.Color = Color3.fromRGB(35, 35, 40)
				shoe.Material = Enum.Material.Leather
				attachPart(shoe, limb, CFrame.new(0, -0.12, 0.08))
			end
		end
	end,

	Cap = function(character: Model)
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return
		end
		local cap = Instance.new("Part")
		cap.Name = "Cap_Accessory"
		cap.Size = Vector3.new(1.05, 0.2, 1.1)
		cap.Color = Color3.fromRGB(220, 50, 50)
		cap.Material = Enum.Material.Fabric
		attachPart(cap, head, CFrame.new(0, 0.45, 0))
	end,

	Hat = function(character: Model)
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return
		end
		local brim = Instance.new("Part")
		brim.Name = "Hat_Accessory_Brim"
		brim.Size = Vector3.new(1.25, 0.08, 1.25)
		brim.Color = Color3.fromRGB(40, 40, 40)
		brim.Material = Enum.Material.Fabric
		attachPart(brim, head, CFrame.new(0, 0.35, 0.05))
		local top = Instance.new("Part")
		top.Name = "Hat_Accessory_Top"
		top.Size = Vector3.new(0.55, 0.55, 0.55)
		top.Color = Color3.fromRGB(40, 40, 40)
		top.Material = Enum.Material.Fabric
		attachPart(top, head, CFrame.new(0, 0.75, 0.05))
	end,
}

function ShopService.ApplyAccessoryPart(player: Player, accessoryName: string)
	local character = player.Character
	if not character then
		return
	end
	stripAccessoryParts(character, accessoryName)
	local applyFn = ACCESSORY_PARTS[accessoryName]
	if applyFn then
		applyFn(character)
		print("[MY CITY] Applied accessory part:", accessoryName, "to", player.Name)
	end
end

function ShopService.RestoreAllAccessories(player: Player)
	if JobService.IsWorking(player) then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = getData(player)

	for _, name in ACCESSORY_PART_ORDER do
		stripAccessoryParts(character, name)
	end

	if accessoryOwnedForVisual(data, "Hat") then
		ShopService.ApplyAccessoryPart(player, "Hat")
	elseif accessoryOwnedForVisual(data, "Cap") then
		ShopService.ApplyAccessoryPart(player, "Cap")
	end

	for _, name in { "Sunglasses", "Earrings", "Chain", "Watch" } do
		if accessoryOwnedForVisual(data, name) then
			ShopService.ApplyAccessoryPart(player, name)
		end
	end
	if accessoryOwnedForVisual(data, "Shoes") then
		ShopService.ApplyAccessoryPart(player, "Shoes")
	elseif accessoryOwnedForVisual(data, "Sneakers") then
		ShopService.ApplyAccessoryPart(player, "Sneakers")
	end
end

function ShopService.ApplyAccessory(player: Player, accessoryName: string)
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = getData(player)
	if not accessoryOwnedForVisual(data, accessoryName) then
		return
	end
	if not ACCESSORY_PARTS[accessoryName] then
		return
	end
	ShopService.ApplyAccessoryPart(player, accessoryName)
end

function ShopService.RemoveAccessory(player: Player, accessoryName: string)
	local character = player.Character
	if not character then
		return
	end
	stripAccessoryParts(character, accessoryName)
end

function ShopService.GetOwnedOutfits(player: Player): WardrobeSnapshot
	if not PlayerDataService.HasSession(player) then
		return { outfits = {}, accessories = accessorySnapshotFromData({}) }
	end
	local data = getData(player)
	return {
		outfits = getOwnedOutfitsList(data),
		accessories = accessorySnapshotFromData(data),
	}
end

function ShopService.BuyAccessory(player: Player, accessoryName: string): ShopResult
	if typeof(accessoryName) ~= "string" or accessoryName == "" then
		return fail("Invalid accessory.")
	end
	local cost = ACCESSORY_COSTS[accessoryName]
	if not cost then
		return fail("Unknown accessory.")
	end
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)
	local anyData = data :: any

	if ACCESSORY_BOOL_KEYS[accessoryName] then
		if anyData[accessoryName] == true then
			return fail("You already own this.")
		end
		if not spendMoney(player, cost) then
			return fail("Not enough CC.")
		end
		if not PlayerDataService.SetData(player, accessoryName, true) then
			addMoney(player, cost)
			return fail("Save failed.")
		end
		logPurchase(player, accessoryName, "Accessory", cost)
		task.defer(function()
			if ACCESSORY_PARTS[accessoryName] then
				ShopService.ApplyAccessoryPart(player, accessoryName)
			end
		end)
		return ok(string.format("%s purchased!", accessoryName))
	end

	if ACCESSORY_STRING_KEYS[accessoryName] then
		local cur = anyData[accessoryName]
		if typeof(cur) == "string" and cur ~= "None" and cur ~= "" then
			return fail("You already own this.")
		end
		if not spendMoney(player, cost) then
			return fail("Not enough CC.")
		end
		local newVal = ACCESSORY_STRING_PURCHASE_VALUE[accessoryName] or "Owned"
		if not PlayerDataService.SetData(player, accessoryName, newVal) then
			addMoney(player, cost)
			return fail("Save failed.")
		end
		logPurchase(player, accessoryName, "Accessory", cost)
		task.defer(function()
			if ACCESSORY_PARTS[accessoryName] then
				ShopService.ApplyAccessoryPart(player, accessoryName)
			end
		end)
		return ok(string.format("%s purchased!", accessoryName))
	end

	return fail("Unknown accessory.")
end

function ShopService.ApplyOutfitColors(player: Player, outfitName: string): ShopResult
	if outfitName == "Default" then
		tryApplyCharacter(player, function(char)
			applyDefaultAvatarBody(player, char)
		end)
		return ok("")
	end
	local colors = CLOTHING_OUTFITS[outfitName]
	if not colors then
		return fail("Unknown outfit.")
	end
	tryApplyCharacter(player, function(char)
		applyClothingOutfitToCharacter(char, colors)
	end)
	return ok("")
end

function ShopService.EquipOutfit(player: Player, outfitName: string): ShopResult
	if typeof(outfitName) ~= "string" or outfitName == "" then
		return fail("Invalid outfit.")
	end
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)

	if outfitName ~= "Default" then
		local hasOutfit = false
		local owned = (data :: any).OwnedOutfits
		if typeof(owned) == "table" then
			for _, o in ipairs(owned :: { any }) do
				if o == outfitName then
					hasOutfit = true
					break
				end
			end
			if not hasOutfit then
				for _, o in pairs(owned :: { any }) do
					if o == outfitName then
						hasOutfit = true
						break
					end
				end
			end
		end
		if not hasOutfit then
			return fail("You don't own this outfit.")
		end
	end

	local applyResult = ShopService.ApplyOutfitColors(player, outfitName)
	if not applyResult.success then
		return applyResult
	end

	if not PlayerDataService.SetData(player, "Outfit", outfitName) then
		return fail("Could not save outfit.")
	end
	task.defer(function()
		ShopService.RestoreAllAccessories(player)
	end)
	print(string.format("[MY CITY] %s equipped outfit: %s", player.Name, outfitName))
	return ok("Equipped: " .. outfitName)
end

function ShopService.RestoreOutfit(player: Player)
	if JobService.IsWorking(player) then
		return
	end
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = getData(player)
	if not player.Character then
		return
	end
	local outfitName = typeof(data.Outfit) == "string" and data.Outfit or "Default"
	local r = ShopService.ApplyOutfitColors(player, outfitName)
	if not r.success then
		return
	end
	task.defer(function()
		ShopService.RestoreAllAccessories(player)
	end)
end

function ShopService.BuyOutfit(player: Player, outfitName: string): ShopResult
	if typeof(outfitName) ~= "string" or outfitName == "" then
		return fail("Invalid outfit.")
	end
	local colors = CLOTHING_OUTFITS[outfitName]
	local price = OUTFIT_PRICE[outfitName]
	if not colors or not price then
		return fail("Unknown outfit.")
	end
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)
	if playerOwnsOutfit(data, outfitName) then
		return fail("You already own this outfit.")
	end
	if not spendMoney(player, price) then
		return fail("Not enough CC.")
	end

	local prevOutfit = typeof(data.Outfit) == "string" and data.Outfit or "Default"
	local prevOwned = getOwnedOutfitsList(data)
	local newOwned = withOutfitAdded(prevOwned, outfitName)
	if not PlayerDataService.SetData(player, "OwnedOutfits", newOwned) then
		addMoney(player, price)
		return fail("Could not save owned outfits.")
	end
	if not PlayerDataService.SetData(player, "Outfit", outfitName) then
		PlayerDataService.SetData(player, "OwnedOutfits", prevOwned)
		addMoney(player, price)
		return fail("Could not save outfit.")
	end

	local colorResult = ShopService.ApplyOutfitColors(player, outfitName)
	if not colorResult.success then
		PlayerDataService.SetData(player, "OwnedOutfits", prevOwned)
		PlayerDataService.SetData(player, "Outfit", prevOutfit)
		addMoney(player, price)
		return fail(colorResult.message)
	end
	task.defer(function()
		ShopService.RestoreAllAccessories(player)
	end)
	logPurchase(player, outfitName, "Clothing", price)
	print(string.format("[MY CITY] %s equipped outfit: %s", player.Name, outfitName))
	return ok("Outfit equipped!")
end

-- ——— BARBERSHOP ———
-- Tint hair mesh only: Accessory.Handle.Color (no HumanoidDescription, no BodyColors / HeadColor3).

local HAIR_STYLE: { [string]: { price: number, color: Color3 } } = {
	Classic = { price = 100, color = Color3.fromRGB(89, 51, 18) },
	Modern = { price = 200, color = Color3.fromRGB(15, 15, 15) },
	Luxury = { price = 350, color = Color3.fromRGB(255, 200, 50) },
}

local function tintAccessoryHairHandles(character: Model, color: Color3)
	for _, acc in character:GetChildren() do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.Color = color
			end
		end
	end
end

function ShopService.BuyHairStyle(player: Player, style: string): ShopResult
	local def = HAIR_STYLE[style]
	if not def then
		return fail("Unknown hair style.")
	end

	local character = player.Character
	if not character then
		return fail("No character")
	end

	if not spendMoney(player, def.price) then
		return fail("Not enough CC.")
	end

	tintAccessoryHairHandles(character, def.color)

	if not PlayerDataService.SetData(player, "HairStyle", style) then
		addMoney(player, def.price)
		return fail("Could not save hair style.")
	end

	logPurchase(player, style, "Barbershop", def.price)
	return ok("Hair color updated: " .. style)
end

-- ——— ELECTRONICS ———

function ShopService.BuyPhone(player: Player): ShopResult
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)
	if data.Phone == true then
		return fail("You already own a phone.")
	end
	if not spendMoney(player, 300) then
		return fail("Not enough CC.")
	end
	if not PlayerDataService.SetData(player, "Phone", true) then
		addMoney(player, 300)
		return fail("Save failed.")
	end
	logPurchase(player, "Phone", "Electronics", 300)
	return ok("Phone purchased — stat displays unlocked where supported.")
end

function ShopService.BuyWatch(player: Player): ShopResult
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)
	if data.Watch == true then
		return fail("You already own a watch.")
	end
	if not spendMoney(player, 500) then
		return fail("Not enough CC.")
	end
	if not PlayerDataService.SetData(player, "Watch", true) then
		addMoney(player, 500)
		return fail("Save failed.")
	end
	logPurchase(player, "Watch", "Electronics", 500)
	task.defer(function()
		ShopService.ApplyAccessoryPart(player, "Watch")
	end)
	return ok("Watch purchased — in-game time UI where supported.")
end

function ShopService.BuyLaptop(player: Player): ShopResult
	if not PlayerDataService.HasSession(player) then
		return fail("Data not loaded.")
	end
	local data = getData(player)
	if data.Laptop == true then
		return fail("You already own a laptop.")
	end
	if not spendMoney(player, 800) then
		return fail("Not enough CC.")
	end
	if not PlayerDataService.SetData(player, "Laptop", true) then
		addMoney(player, 800)
		return fail("Save failed.")
	end
	logPurchase(player, "Laptop", "Electronics", 800)
	return ok("Laptop purchased — advanced job features where supported.")
end

-- Single entry for remotes: product is "Phone" | "Watch" | "Laptop".
function ShopService.BuyElectronics(player: Player, product: string): ShopResult
	if product == "Phone" then
		return ShopService.BuyPhone(player)
	elseif product == "Watch" then
		return ShopService.BuyWatch(player)
	elseif product == "Laptop" then
		return ShopService.BuyLaptop(player)
	end
	return fail("Unknown electronics product.")
end

-- ——— GROCERY ———

local FOODS: { [string]: { price: number, rep: number } } = {
	Bread = { price = 20, rep = 2 },
	Fruits = { price = 40, rep = 5 },
	Vegetables = { price = 60, rep = 8 },
}

function ShopService.BuyFood(player: Player, foodType: string): ShopResult
	local f = FOODS[foodType]
	if not f then
		return fail("Unknown food.")
	end
	if not spendMoney(player, f.price) then
		return fail("Not enough CC.")
	end
	ReputationService.AddReputation(player, f.rep, "Grocery: " .. foodType)
	logPurchase(player, foodType, "Grocery", f.price)
	return ok(string.format("Fresh %s! +%d reputation.", foodType, f.rep))
end

-- ——— PHARMACY ———

local PHARMACY_PRICE = 100
local PHARMACY_IMMUNITY_SECONDS = 30 * 60

function ShopService.BuyMedicine(player: Player): ShopResult
	if not spendMoney(player, PHARMACY_PRICE) then
		return fail("Not enough CC.")
	end
	ReputationService.GrantReputationLossImmunity(player, PHARMACY_IMMUNITY_SECONDS)
	pharmacySessionNote[player] = string.format("Reputation loss immunity until %d", os.time() + PHARMACY_IMMUNITY_SECONDS)
	logPurchase(player, "Medicine", "Pharmacy", PHARMACY_PRICE)
	return ok("Medicine taken — reputation loss immunity for 30 minutes.")
end

local function onPlayerRemoving(player: Player)
	pharmacySessionNote[player] = nil
end

local function wireClothingRestore(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			PlayerDataService.RestoreOutfit(player)
		end)
	end)
	if player.Character then
		task.defer(function()
			PlayerDataService.RestoreOutfit(player)
		end)
	end
end

local function start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	PlayerDataService.RegisterOutfitRestore(function(player: Player)
		ShopService.RestoreOutfit(player)
	end)
	Players.PlayerAdded:Connect(wireClothingRestore)
	task.defer(function()
		for _, plr in Players:GetPlayers() do
			wireClothingRestore(plr)
		end
	end)

	PlayerDataService.OnDataLoaded(function(player: Player)
		task.defer(function()
			ShopService.ProcessInvestmentsForPlayer(player)
			if player.Character then
				ShopService.RestoreAllAccessories(player)
			end
		end)
	end)
	task.defer(function()
		for _, plr in Players:GetPlayers() do
			ShopService.ProcessInvestmentsForPlayer(plr)
		end
	end)
	task.spawn(investmentHeartbeat)
end

start()

return ShopService
