--[[
	HouseEntryService — MY CITY
	Dynamic enter/exit: map house Models use HouseId, HouseLevel, OwnerId.
	Entry uses OwnerId (world source of truth). AssignHouse creates OwnerBeacon; ReleaseHouse removes it.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GAME_LABEL = "MY CITY"

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local RemoteConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig") :: ModuleScript
)

-- Direct children of Workspace (per map layout).
local DISTRICT_ROOT_NAMES: { [number]: string } = {
	[1] = "PoorDistrict",
	[2] = "MiddleDistrict",
	[3] = "RichDistrict",
	[4] = "LuxuryDistrict",
}

local HOUSE_NAMES: { [number]: string } = {
	[1] = "Shared Room",
	[2] = "Studio Apartment",
	[3] = "Family House",
	[4] = "Luxury Villa",
}

-- Full access for testing / moderation (HousePrompt + EnterHouse remote).
local ADMINS: { number } = {
	9849956140, -- TFGAMES888
}

local function isHouseEntryAdmin(player: Player): boolean
	for _, uid in ADMINS do
		if uid == player.UserId then
			return true
		end
	end
	return false
end

--- Session: house instance + optional server-spawned exit trigger (destroyed on leave).
export type InsideHouseSession = {
	houseId: string,
	exitTrigger: Part?,
	wardrobePrompt: ProximityPrompt?,
}

local insideSession: { [Player]: InsideHouseSession } = {}

local entryPromptWired: { [ProximityPrompt]: boolean } = {}
local exitPromptWired: { [ProximityPrompt]: boolean } = {}

local HouseEntryService = {}

local function printLog(msg: string)
	print(string.format("[%s] %s", GAME_LABEL, msg))
end

local function fireNotification(player: Player, message: string, kind: string)
	if RemoteConfig and RemoteConfig.ShowNotification then
		RemoteConfig.ShowNotification:FireClient(player, message, kind)
	end
end

--[[
	Walk up from a prompt to the nearest Model that carries HouseId.
]]
local function findHouseModelFromDescendant(inst: Instance): Model?
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

--[[
	World-space center and size from model AABB (for depth along Z).
]]
local function getHouseBounds(model: Model): (Vector3, Vector3)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and cf and size then
		return cf.Position, size
	end
	return model:GetPivot().Position, Vector3.new(10, 10, 10)
end

local function getOwnerIdNumber(model: Model): number
	local v = model:GetAttribute("OwnerId")
	if typeof(v) == "number" then
		return math.floor(v + 0)
	end
	if typeof(v) == "string" then
		return tonumber(v) or 0
	end
	return 0
end

local function destroyOwnerBeacon(model: Model)
	local existing = model:FindFirstChild("OwnerBeacon")
	if existing then
		existing:Destroy()
		printLog(string.format("HouseEntryService: destroyed OwnerBeacon on %s", model:GetFullName()))
	end
end

--[[
	Interior spawn: on Floor use floor.Position.Y + 3; else bottom of house bounds + 3.
]]
local function getInteriorTeleportPosition(model: Model, houseCenter: Vector3, houseSize: Vector3): Vector3
	local floor = model:FindFirstChild("Floor", true)
	if floor and floor:IsA("BasePart") then
		return Vector3.new(houseCenter.X, floor.Position.Y + 3, houseCenter.Z)
	end
	local y = houseCenter.Y - (houseSize.Y / 2) + 3
	return Vector3.new(houseCenter.X, y, houseCenter.Z)
end

--[[
	Glowing neon cylinder + billboard for the assigned owner (5 studs above roof).
]]
local function createOwnerBeacon(model: Model)
	destroyOwnerBeacon(model)

	local center, size = getHouseBounds(model)
	local roofY = center.Y + size.Y / 2
	local cylinderHeight = 8
	local gapAboveRoof = 5
	local beaconCenterY = roofY + gapAboveRoof + cylinderHeight / 2

	local beacon = Instance.new("Part")
	beacon.Name = "OwnerBeacon"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(2, 8, 2)
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(0, 255, 100)
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CastShadow = false
	beacon.CFrame = CFrame.new(center.X, beaconCenterY, center.Z)
	beacon.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerBeaconLabel"
	billboard.Size = UDim2.new(0, 120, 0, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
	billboard.Adornee = beacon
	billboard.Parent = beacon

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.Font = Enum.Font.GothamBold
	tl.TextSize = 16
	tl.TextColor3 = Color3.fromRGB(0, 255, 100)
	tl.TextStrokeTransparency = 0.4
	tl.Text = "🏠 YOUR HOME"
	tl.Parent = billboard

	printLog(string.format("HouseEntryService: created OwnerBeacon on %s", model:GetFullName()))
end

local function findHouseModelByHouseId(houseId: string): Model?
	if houseId == "" then
		return nil
	end
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") then
			local hid = d:GetAttribute("HouseId")
			if hid == houseId then
				return d
			end
		end
	end
	return nil
end

local function getDistrictRootForLevel(houseLevel: number): Instance?
	local name = DISTRICT_ROOT_NAMES[houseLevel]
	if not name then
		return nil
	end
	local inst = Workspace:FindFirstChild(name)
	if inst and (inst:IsA("Folder") or inst:IsA("Model")) then
		return inst
	end
	return nil
end

--[[
	AssignHouse / placement: only the canonical district folder for that tier (direct child of Workspace).
]]
local function findDistrictSearchRoot(houseLevel: number): Instance
	local root = getDistrictRootForLevel(houseLevel)
	if root then
		printLog(string.format("HouseEntryService: using district folder %q for level %d", root.Name, houseLevel))
		return root
	end
	warn(
		string.format(
			"[%s] HouseEntryService: missing Workspace child %q for level %d — falling back to full Workspace scan",
			GAME_LABEL,
			tostring(DISTRICT_ROOT_NAMES[houseLevel]),
			houseLevel
		)
	)
	return Workspace
end

--[[
	All district roots that exist (for ownership restore after server restart).
]]
local function getDistrictRootsForSearch(): { Instance }
	local roots: { Instance } = {}
	for level = 1, 4 do
		local r = getDistrictRootForLevel(level)
		if r then
			table.insert(roots, r)
		end
	end
	return roots
end

--[[
	Find a house Model by HouseId only under Poor/Middle/Rich/Luxury district folders.
]]
local function findHouseModelInDistrictFolders(houseId: string): Model?
	if houseId == "" then
		return nil
	end
	for _, root in getDistrictRootsForSearch() do
		for _, d in root:GetDescendants() do
			if d:IsA("Model") then
				local hid = d:GetAttribute("HouseId")
				if hid == houseId then
					return d
				end
			end
		end
	end
	return nil
end

--[[
	Safe teleport: briefly zero movement, CFrame to target, restore humanoid stats.
]]
local function safeTeleportPlayer(player: Player, target: Vector3 | CFrame, logLabel: string): boolean
	local character = player.Character
	if not character then
		warn(string.format("[%s] HouseEntryService: no character for %s", GAME_LABEL, player.Name))
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not hrp then
		warn(string.format("[%s] HouseEntryService: humanoid/root missing for %s", GAME_LABEL, player.Name))
		return false
	end

	local oldWalkSpeed = humanoid.WalkSpeed
	local oldJumpPower = humanoid.JumpPower
	local oldAutoRotate = humanoid.AutoRotate

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	task.wait(0.1)

	local targetCFrame = if typeof(target) == "CFrame" then target else CFrame.new(target)
	local targetPosition = targetCFrame.Position

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hrp.CFrame = targetCFrame

	task.wait(0.2)

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	humanoid.WalkSpeed = oldWalkSpeed > 0 and oldWalkSpeed or 16
	humanoid.JumpPower = oldJumpPower > 0 and oldJumpPower or 50
	humanoid.AutoRotate = oldAutoRotate
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	printLog(string.format("HouseEntryService: teleported %s — %s — at %s", player.Name, logLabel, tostring(targetPosition)))

	return true
end

local function getExteriorTeleportPosition(center: Vector3, size: Vector3): Vector3
	return Vector3.new(center.X, 3, center.Z - (size.Z / 2 + 8))
end

local function getHouseExitCFrame(houseModel: Model): (CFrame, string)
	local frontExitPoint = houseModel:FindFirstChild("FrontExitPoint", true)
	if frontExitPoint and frontExitPoint:IsA("BasePart") then
		return frontExitPoint.CFrame, "FrontExitPoint"
	end

	local exitPoint = houseModel:FindFirstChild("ExitPoint", true)
	if exitPoint and exitPoint:IsA("BasePart") then
		return exitPoint.CFrame, "ExitPoint"
	end

	local door = houseModel:FindFirstChild("Door", true)
	if door and door:IsA("BasePart") then
		local forward = door.CFrame.LookVector
		local exitPos = door.Position + (forward * 6) + Vector3.new(0, 1.5, 0)
		local exitLookAt = exitPos + forward
		return CFrame.lookAt(exitPos, exitLookAt), "Door"
	end

	local center, size = getHouseBounds(houseModel)
	return CFrame.new(getExteriorTeleportPosition(center, size)), "BoundsFallback"
end

--[[
	Remove temporary exit part and clear inside session for this player.
]]
local function cleanupInsideSession(player: Player)
	local session = insideSession[player]
	if session then
		if session.exitTrigger and session.exitTrigger.Parent then
			session.exitTrigger:Destroy()
			printLog(string.format("HouseEntryService: destroyed HouseExitTrigger for %s", player.Name))
		end
		if session.wardrobePrompt and session.wardrobePrompt.Parent then
			session.wardrobePrompt:Destroy()
			printLog(string.format("HouseEntryService: destroyed WardrobePrompt for %s", player.Name))
		end
	end
	insideSession[player] = nil
end

--[[
	Temporary exit volume: same X/Y as post-teleport position, slightly -Z toward door; large prompt range.
]]
local function createHouseExitSessionTrigger(player: Player, houseModel: Model, teleportPos: Vector3): Part
	local triggerPos = Vector3.new(teleportPos.X, teleportPos.Y, teleportPos.Z - 2)

	local part = Instance.new("Part")
	part.Name = "HouseExitTrigger"
	part.Size = Vector3.new(6, 8, 2)
	part.Transparency = 0.8
	part.CanCollide = false
	part.CanQuery = true
	part.Anchored = true
	part.CFrame = CFrame.new(triggerPos)
	part.Parent = houseModel

	local pp = Instance.new("ProximityPrompt")
	pp.Name = "HouseExitPrompt"
	pp.ActionText = "🚪 Leave Home"
	pp.ObjectText = "Exit"
	pp.KeyboardKeyCode = Enum.KeyCode.F
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 15
	pp.RequiresLineOfSight = false
	pp.Enabled = true
	exitPromptWired[pp] = true
	pp.Triggered:Connect(function(plr: Player)
		HouseEntryService.ExitHouse(plr)
	end)
	pp.Parent = part

	printLog(string.format("HouseEntryService: created HouseExitTrigger for %s at %s", player.Name, tostring(triggerPos)))
	return part
end

local function findWardrobeAttachPart(houseModel: Model): BasePart?
	local w2f = houseModel:FindFirstChild("Wardrobe2F", true)
	local w = houseModel:FindFirstChild("Wardrobe", true)
	local inst: Instance? = w2f or w
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart
		end
		return inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

--[[
	ProximityPrompt on map wardrobe part; opens client wardrobe UI.
]]
local function createWardrobeProximityPrompt(player: Player, houseModel: Model): ProximityPrompt?
	local attach = findWardrobeAttachPart(houseModel)
	if not attach then
		printLog(string.format("HouseEntryService: no Wardrobe2F/Wardrobe in %s for %s", houseModel.Name, player.Name))
		return nil
	end
	local old = attach:FindFirstChild("WardrobePrompt")
	if old and old:IsA("ProximityPrompt") then
		old:Destroy()
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "WardrobePrompt"
	pp.ActionText = "Open Wardrobe"
	pp.ObjectText = "👗 Wardrobe"
	pp.MaxActivationDistance = 8
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = attach
	pp.Triggered:Connect(function(plr: Player)
		if plr ~= player and not isHouseEntryAdmin(plr) then
			return
		end
		local ev = RemoteConfig.OpenWardrobe
		if ev then
			(ev :: RemoteEvent):FireClient(plr)
		end
	end)
	printLog(string.format("HouseEntryService: WardrobePrompt on %s for %s", attach:GetFullName(), player.Name))
	return pp
end

function HouseEntryService.CanEnterHouse(player: Player, houseLevel: number): boolean
	if houseLevel < 1 or houseLevel > 4 then
		return false
	end
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = PlayerDataService.GetData(player)
	local pl = data.HouseLevel
	if typeof(pl) ~= "number" then
		return false
	end
	return pl >= houseLevel
end

function HouseEntryService.IsInsideHouse(player: Player): boolean
	return insideSession[player] ~= nil
end

function HouseEntryService.GetHouseInfo(player: Player): { level: number, name: string }
	local data = PlayerDataService.GetData(player)
	local lvl = 0
	if data and typeof(data.HouseLevel) == "number" then
		lvl = data.HouseLevel
	end
	local name = "No house"
	if lvl >= 1 and lvl <= 4 then
		name = HOUSE_NAMES[lvl]
	end
	return { level = lvl, name = name }
end

--[[
	After server restart, attributes are not persisted — re-apply OwnerId + beacon from saved HouseId.
]]
function HouseEntryService.RestoreOwnership(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = PlayerDataService.GetData(player)
	local houseId = data.HouseId
	if typeof(houseId) ~= "string" or houseId == "" then
		return
	end

	local model = findHouseModelInDistrictFolders(houseId)
	if not model then
		warn(
			string.format(
				"[%s] HouseEntryService.RestoreOwnership: no house with HouseId=%q under district folders for %s",
				GAME_LABEL,
				houseId,
				player.Name
			)
		)
		return
	end

	model:SetAttribute("OwnerId", player.UserId)
	createOwnerBeacon(model)
	print(
		string.format(
			"[%s] HouseEntryService: restored ownership of %s for %s",
			GAME_LABEL,
			houseId,
			player.Name
		)
	)
end

--[[
	Assign first free plot: OwnerId == 0, HouseLevel == houseLevel, under district folder (or Workspace).
	Returns assigned HouseId string, or "" if none found.
]]
function HouseEntryService.AssignHouse(player: Player, houseLevel: number): string
	if houseLevel < 1 or houseLevel > 4 then
		warn(string.format("[%s] HouseEntryService.AssignHouse: invalid level %d", GAME_LABEL, houseLevel))
		return ""
	end

	local root = findDistrictSearchRoot(houseLevel)
	for _, d in root:GetDescendants() do
		if d:IsA("Model") then
			local hid = d:GetAttribute("HouseId")
			local hlRaw = d:GetAttribute("HouseLevel")
			local hlNum = if typeof(hlRaw) == "number"
				then math.floor(hlRaw + 0)
				elseif typeof(hlRaw) == "string" then tonumber(hlRaw)
				else nil
			local oid = d:GetAttribute("OwnerId")
			if typeof(hid) == "string" and hid ~= "" and hlNum == houseLevel then
				local ownerNum = if typeof(oid) == "number" then oid elseif oid == nil then 0 else nil
				if ownerNum ~= nil and ownerNum == 0 then
					d:SetAttribute("OwnerId", player.UserId)
					if not PlayerDataService.SetData(player, "HouseId", hid) then
						d:SetAttribute("OwnerId", 0)
						warn(string.format("[%s] HouseEntryService.AssignHouse: failed to save HouseId for %s", GAME_LABEL, player.Name))
						return ""
					end
					PlayerDataService.RequestImmediateSave(player, "house assignment")
					createOwnerBeacon(d)
					printLog(
						string.format(
							"HouseEntryService.AssignHouse: %s assigned %s (level %d) OwnerId=%d",
							player.Name,
							hid,
							houseLevel,
							player.UserId
						)
					)
					return hid
				end
			end
		end
	end

	warn(
		string.format(
			"[%s] HouseEntryService.AssignHouse: no free house for level %d (check map Models: HouseId, HouseLevel, OwnerId)",
			GAME_LABEL,
			houseLevel
		)
	)
	return ""
end

--[[
	Clear workspace claim and player HouseId (does not change HouseLevel).
]]
function HouseEntryService.ReleaseHouse(player: Player)
	if not PlayerDataService.HasSession(player) then
		return
	end
	local data = PlayerDataService.GetData(player)
	local hid = data.HouseId
	if typeof(hid) ~= "string" or hid == "" then
		return
	end

	local model = findHouseModelByHouseId(hid)
	if model then
		destroyOwnerBeacon(model)
		model:SetAttribute("OwnerId", 0)
		printLog(string.format("HouseEntryService.ReleaseHouse: cleared OwnerId on %s (%s)", model:GetFullName(), hid))
	else
		printLog(string.format("HouseEntryService.ReleaseHouse: no Model found for HouseId %q — clearing profile only", hid))
	end

	if not PlayerDataService.SetData(player, "HouseId", "") then
		warn(string.format("[%s] HouseEntryService.ReleaseHouse: failed to clear HouseId for %s", GAME_LABEL, player.Name))
	else
		PlayerDataService.RequestImmediateSave(player, "house release")
	end
	printLog(string.format("HouseEntryService.ReleaseHouse: %s released house slot", player.Name))
end

--[[
	Enter from a specific map house (prompt). Uses OwnerId on the model as source of truth.
]]
function HouseEntryService.EnterHouseAtModel(player: Player, houseModel: Model): (boolean, string?)
	if HouseEntryService.IsInsideHouse(player) then
		return false, "You are already inside a home."
	end

	if not PlayerDataService.HasSession(player) then
		return false, "Data not loaded yet."
	end
	local data = PlayerDataService.GetData(player)

	local mapHouseId = houseModel:GetAttribute("HouseId")
	if typeof(mapHouseId) ~= "string" or mapHouseId == "" then
		printLog(string.format("HouseEntryService: house model %s has no HouseId attribute", houseModel:GetFullName()))
		return false, "Invalid house."
	end

	local ownerNum = getOwnerIdNumber(houseModel)
	local admin = isHouseEntryAdmin(player)

	if not admin then
		if ownerNum == 0 then
			fireNotification(player, "This house is available. Buy it in the Housing menu!", "info")
			printLog(string.format("HouseEntryService: %s tried unowned house %s", player.Name, mapHouseId))
			return false, "Available house."
		end

		if ownerNum ~= player.UserId then
			fireNotification(player, "This house belongs to someone else.", "error")
			printLog(
				string.format(
					"HouseEntryService: %s enter blocked — OwnerId=%d != player %d (%s)",
					player.Name,
					ownerNum,
					player.UserId,
					mapHouseId
				)
			)
			return false, "Not owner."
		end
	else
		print(string.format("[%s] ADMIN entering house: %s", GAME_LABEL, houseModel.Name))
	end

	local center, size = getHouseBounds(houseModel)
	local interiorPos = getInteriorTeleportPosition(houseModel, center, size)

	if not safeTeleportPlayer(player, interiorPos, string.format("enter house %s", mapHouseId)) then
		return false, "Teleport failed."
	end

	local exitPart = createHouseExitSessionTrigger(player, houseModel, interiorPos)
	local wardrobePrompt = createWardrobeProximityPrompt(player, houseModel)
	insideSession[player] = { houseId = mapHouseId, exitTrigger = exitPart, wardrobePrompt = wardrobePrompt }
	if not admin then
		printLog(string.format("HouseEntryService: %s entered %s (OwnerId match)", player.Name, mapHouseId))
	end
	return true
end

--[[
	Exit in front of house: Y=3, Z offset by half depth + 8 studs.
]]
function HouseEntryService.ExitHouseAtModel(player: Player, houseModel: Model): (boolean, string?)
	local session = insideSession[player]
	local mapHouseId = houseModel:GetAttribute("HouseId")
	if typeof(mapHouseId) ~= "string" then
		return false, "Invalid exit."
	end

	if not session or session.houseId ~= mapHouseId then
		fireNotification(player, "You can't exit from here.", "error")
		return false, "Wrong house exit."
	end

	local exitCFrame, exitSource = getHouseExitCFrame(houseModel)

	if not safeTeleportPlayer(player, exitCFrame, string.format("exit house %s", mapHouseId)) then
		return false, "Teleport failed."
	end

	cleanupInsideSession(player)
	local exitPosition = exitCFrame.Position
	printLog(string.format(
		"HouseExit: %s exited %s via %s to %.2f,%.2f,%.2f",
		player.Name,
		mapHouseId,
		exitSource,
		exitPosition.X,
		exitPosition.Y,
		exitPosition.Z
	))
	return true
end

--[[
	Remote/UI: enter player's assigned house by finding its Model in the world.
]]
function HouseEntryService.EnterHouse(player: Player): (boolean, string?)
	if HouseEntryService.IsInsideHouse(player) then
		return false, "You are already inside a home."
	end
	if not PlayerDataService.HasSession(player) then
		return false, "Data not loaded yet."
	end
	local data = PlayerDataService.GetData(player)
	local hid = typeof(data.HouseId) == "string" and data.HouseId or ""
	if hid == "" then
		fireNotification(player, "You don't own a house yet. Buy one in the Housing menu!", "error")
		return false, "No house owned."
	end
	local model = findHouseModelByHouseId(hid)
	if not model then
		fireNotification(player, "Your house could not be found on the map.", "error")
		printLog(string.format("HouseEntryService.EnterHouse: no Model for HouseId %q", hid))
		return false, "House not found."
	end
	if getOwnerIdNumber(model) ~= player.UserId and not isHouseEntryAdmin(player) then
		fireNotification(player, "Your house data does not match the map. Try rejoining.", "error")
		printLog(string.format("HouseEntryService.EnterHouse: OwnerId mismatch for HouseId %q", hid))
		return false, "Owner mismatch."
	end
	return HouseEntryService.EnterHouseAtModel(player, model)
end

function HouseEntryService.ExitHouse(player: Player): (boolean, string?)
	local session = insideSession[player]
	if not session then
		return false, "You are not inside your home."
	end
	local model = findHouseModelByHouseId(session.houseId)
	if not model then
		cleanupInsideSession(player)
		return false, "Could not find house to exit."
	end
	return HouseEntryService.ExitHouseAtModel(player, model)
end

local function wireEntryPrompt(prompt: ProximityPrompt)
	if entryPromptWired[prompt] then
		return
	end
	entryPromptWired[prompt] = true
	prompt.Enabled = true
	prompt.HoldDuration = 0
	prompt.ActionText = "Enter"
	prompt.ObjectText = "House"
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 10)
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(plr: Player)
		local model = findHouseModelFromDescendant(prompt)
		if not model then
			warn(string.format("[%s] HouseEntryService: HousePrompt %s has no HouseId Model ancestor", GAME_LABEL, prompt:GetFullName()))
			return
		end
		HouseEntryService.EnterHouseAtModel(plr, model)
	end)
	printLog(string.format("HouseEntryService: wired HousePrompt %s", prompt:GetFullName()))
end

local function wireExitPrompt(prompt: ProximityPrompt)
	if exitPromptWired[prompt] then
		return
	end
	exitPromptWired[prompt] = true
	prompt.Triggered:Connect(function(plr: Player)
		local model = findHouseModelFromDescendant(prompt)
		if not model then
			warn(string.format("[%s] HouseEntryService: HouseExitPrompt %s has no HouseId Model ancestor", GAME_LABEL, prompt:GetFullName()))
			return
		end
		HouseEntryService.ExitHouseAtModel(plr, model)
	end)
	printLog(string.format("HouseEntryService: wired HouseExitPrompt %s", prompt:GetFullName()))
end

local function scanWorldPrompts()
	for _, d in Workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			if d.Name == "HousePrompt" then
				wireEntryPrompt(d)
			elseif d.Name == "HouseExitPrompt" then
				wireExitPrompt(d)
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	if insideSession[player] then
		cleanupInsideSession(player)
		printLog(string.format("HouseEntryService: cleared inside session for leaving player %s", player.Name))
	end
end

local function hookPlayerChatted(player: Player)
	player.Chatted:Connect(function(message: string)
		local trimmed = (message:gsub("^%s+", ""):gsub("%s+$", ""))
		if string.lower(trimmed) == "/exit" then
			HouseEntryService.ExitHouse(player)
		end
	end)
end

local function start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	Players.PlayerAdded:Connect(hookPlayerChatted)
	for _, plr in Players:GetPlayers() do
		task.spawn(hookPlayerChatted, plr)
	end

	PlayerDataService.OnDataLoaded(function(player: Player)
		local ok, err = pcall(function()
			HouseEntryService.RestoreOwnership(player)
		end)
		if not ok then
			warn(string.format("[%s] HouseEntryService.RestoreOwnership error for %s: %s", GAME_LABEL, player.Name, tostring(err)))
		end
	end)

	task.defer(function()
		task.wait(1)
		scanWorldPrompts()
		Workspace.DescendantAdded:Connect(function(child)
			if child:IsA("ProximityPrompt") then
				if child.Name == "HousePrompt" then
					wireEntryPrompt(child)
				elseif child.Name == "HouseExitPrompt" then
					wireExitPrompt(child)
				end
			end
		end)
		printLog("HouseEntryService initialized (dynamic HouseId / HouseExitPrompt)")
	end)
end

start()

return HouseEntryService
