--[[
	OutfitService — MY CITY
	Applies simple BodyColors + optional prop “hard hat” parts based on active job.
	Driven by JobService (StartWork / StopWork). Uses Humanoid:ApplyDescription to restore defaults.
]]

local Players = game:GetService("Players")

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)

export type HatSpec = {
	color: Color3,
	size: Vector3,
	offsetY: number,
}

export type OutfitConfig = {
	shirt: Color3?, -- torso + arms
	pants: Color3?, -- legs
	hat: HatSpec?, -- cosmetic Part (cylinder), welded to Head
}

local OUTFITS: { [string]: OutfitConfig } = {
	["Unemployed"] = {},
	["Street Cleaner"] = {
		shirt = Color3.fromRGB(255, 165, 0),
		pants = Color3.fromRGB(100, 100, 100),
	},
	["Factory Worker"] = {
		shirt = Color3.fromRGB(50, 50, 50),
		pants = Color3.fromRGB(60, 40, 20),
		hat = {
			color = Color3.fromRGB(255, 220, 60),
			size = Vector3.new(1.15, 0.42, 1.15),
			offsetY = 1.02,
		},
	},
	["Police Officer"] = {
		shirt = Color3.fromRGB(20, 20, 80),
		pants = Color3.fromRGB(20, 20, 80),
		hat = {
			color = Color3.fromRGB(25, 25, 25),
			size = Vector3.new(1.05, 0.32, 1.05),
			offsetY = 0.98,
		},
	},
	["Tour Guide"] = {
		shirt = Color3.fromRGB(255, 220, 50),
		pants = Color3.fromRGB(50, 150, 50),
	},
	["Firefighter"] = {
		shirt = Color3.fromRGB(180, 30, 30),
		pants = Color3.fromRGB(40, 40, 40),
		hat = {
			color = Color3.fromRGB(200, 40, 40),
			size = Vector3.new(1.12, 0.38, 1.12),
			offsetY = 1.0,
		},
	},
	["Doctor"] = {
		shirt = Color3.fromRGB(245, 245, 250),
		pants = Color3.fromRGB(245, 245, 250),
	},
	["Nurse"] = {
		shirt = Color3.fromRGB(90, 140, 220),
		pants = Color3.fromRGB(240, 240, 245),
	},
	["Teacher"] = {
		shirt = Color3.fromRGB(60, 90, 140),
		pants = Color3.fromRGB(80, 70, 55),
	},
	["Security"] = {
		shirt = Color3.fromRGB(35, 35, 45),
		pants = Color3.fromRGB(30, 30, 38),
		hat = {
			color = Color3.fromRGB(25, 25, 30),
			size = Vector3.new(1.08, 0.28, 1.08),
			offsetY = 0.98,
		},
	},
	["Electrician"] = {
		shirt = Color3.fromRGB(255, 210, 40),
		pants = Color3.fromRGB(45, 45, 50),
		hat = {
			color = Color3.fromRGB(255, 220, 60),
			size = Vector3.new(1.1, 0.34, 1.1),
			offsetY = 1.0,
		},
	},
}

local HAT_FOLDER_NAME = "MY_CITY_JobOutfit"

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildWhichIsA("Humanoid")
end

-- Shirt/Pants instances block or override body tint; remove while a solid-color uniform is active.
local function stripClassicClothing(character: Model)
	for _, inst in character:GetChildren() do
		if inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic") then
			inst:Destroy()
		end
	end
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

-- Classic R6-style BodyColors (still drives many R15 look presets).
local function applyBodyColors(character: Model, shirt: Color3, pants: Color3)
	local bc = getOrCreateBodyColors(character)
	bc.TorsoColor3 = shirt
	bc.LeftArmColor3 = shirt
	bc.RightArmColor3 = shirt
	bc.LeftLegColor3 = pants
	bc.RightLegColor3 = pants
	-- Keep face/skins: do not change HeadColor3
end

local function destroyHatFolder(character: Model)
	local folder = character:FindFirstChild(HAT_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

local function createHatPart(character: Model, spec: HatSpec)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	destroyHatFolder(character)
	local folder = Instance.new("Folder")
	folder.Name = HAT_FOLDER_NAME
	folder.Parent = character

	local hat = Instance.new("Part")
	hat.Name = "Hat"
	hat.Shape = Enum.PartType.Cylinder
	hat.Size = spec.size
	hat.Color = spec.color
	hat.Material = Enum.Material.SmoothPlastic
	hat.CastShadow = true
	hat.CanCollide = false
	hat.CanQuery = false
	hat.CanTouch = false
	hat.Massless = true
	hat.Parent = folder

	-- Cylinder length is along local X; rotate so height runs up (Y) on the head.
	hat.CFrame = head.CFrame * CFrame.new(0, spec.offsetY, 0) * CFrame.Angles(0, 0, math.rad(90))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = hat
	weld.Parent = hat
end

local OutfitService = {}

function OutfitService.RemoveOutfit(player: Player)
	local character = player.Character
	if character then
		destroyHatFolder(character)
		stripClassicClothing(character)
		local hum = getHumanoid(character)
		if hum then
			local ok, err = pcall(function()
				local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
				hum:ApplyDescription(desc)
			end)
			if not ok then
				warn(string.format("[%s] RemoveOutfit: ApplyDescription failed for %s: %s", GAME_LABEL, player.Name, tostring(err)))
			end
		end
	end

	print(string.format("[%s] Outfit reset to default for %s", GAME_LABEL, player.Name))
end

function OutfitService.ApplyOutfit(player: Player, jobName: string)
	if jobName == "Unemployed" or jobName == "" then
		OutfitService.RemoveOutfit(player)
		return
	end

	local config = OUTFITS[jobName]
	if not config or (not config.shirt and not config.pants) then
		print(string.format("[%s] ApplyOutfit: no config for job %q (%s)", GAME_LABEL, jobName, player.Name))
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local hum = getHumanoid(character)
	if not hum then
		return
	end

	stripClassicClothing(character)
	destroyHatFolder(character)

	local shirt = config.shirt or Color3.fromRGB(200, 200, 200)
	local pants = config.pants or Color3.fromRGB(100, 100, 100)
	applyBodyColors(character, shirt, pants)

	if config.hat then
		createHatPart(character, config.hat)
	end

	print(string.format("[%s] Applied job outfit %q for %s", GAME_LABEL, jobName, player.Name))
end

return OutfitService
