local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GAME_LABEL = "MY CITY"

local ClubService = require(script.Parent:WaitForChild("ClubService") :: ModuleScript)
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)
local RemoteConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteConfig") :: ModuleScript
)

local ClubDoorService = {}

local CLUB_NAMES = {
	"Club_Bronze",
	"Club_Silver",
	"Club_Gold",
	"Club_Diamond",
}

local CLUB_MODEL_FIND_TIMEOUT = 10
-- Studs above InteriorFloor top surface (tune if ceiling is low).
local INTERIOR_TELEPORT_CLEARANCE = 2.5

local function fireNotification(player: Player, message: string, kind: string)
	if RemoteConfig and RemoteConfig.ShowNotification then
		RemoteConfig.ShowNotification:FireClient(player, message, kind)
	end
end

local function findPrompt(clubModel: Model): ProximityPrompt?
	local prompt = clubModel:FindFirstChild("ClubPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	for _, descendant in ipairs(clubModel:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	return nil
end

local function getDeniedMessage(player: Player, clubName: string): string
	local info = ClubService.GetClubInfo(clubName)
	if not info then
		return "Você ainda não pode entrar nesta boate."
	end

	local requiredRep = info.MinimumReputation or 0
	local currentRep = ReputationService.GetReputation(player)

	local missing = math.max(0, requiredRep - currentRep)

	if missing > 0 then
		return string.format(
			"Você precisa de mais %d de reputação para entrar em %s. Continue evoluindo!",
			missing,
			clubName
		)
	end

	return string.format("Você ainda não pode entrar em %s.", clubName)
end

--[[
	Models sometimes accumulate multiple ClubSpawn parts (e.g. old tooling). Keep the highest by Y, destroy the rest.
	Returns the surviving ClubSpawn, or nil if none.
]]
local function dedupeClubSpawns(clubModel: Model, clubName: string): BasePart?
	local spawns: { BasePart } = {}
	for _, d in clubModel:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ClubSpawn" then
			table.insert(spawns, d)
		end
	end
	if #spawns == 0 then
		return nil
	end
	table.sort(spawns, function(a, b)
		return a.Position.Y > b.Position.Y
	end)
	for i = 2, #spawns do
		warn(
			string.format(
				"[%s] ClubDoorService: removing duplicate ClubSpawn in %s — %s",
				GAME_LABEL,
				clubModel.Name,
				spawns[i]:GetFullName()
			)
		)
		spawns[i]:Destroy()
	end
	local keptSpawn = spawns[1]
	warn(string.format("[%s] Keeping ClubSpawn for %s: %s", GAME_LABEL, clubName, keptSpawn:GetFullName()))
	return keptSpawn
end

--[[
	Single ENTRY prompt only. Never touch ExitPrompt (nightclub exit is separate).
]]
local function isDrinkPrompt(prompt: ProximityPrompt): boolean
	local parent = prompt.Parent
	return prompt.Name == "DrinkPrompt"
		or prompt:GetAttribute("MY_CITY_DrinkPrompt") == true
		or (parent ~= nil and parent.Name == "DrinkPromptAttachment")
end

local function shouldPreserveNonEntryPrompt(prompt: ProximityPrompt): boolean
	return isDrinkPrompt(prompt) or prompt:GetAttribute("MY_CITY_IgnorePromptDedupe") == true
end

local function dedupeEntryProximityPrompts(clubModel: Model)
	local prompts: { ProximityPrompt } = {}
	local preservedDrinkPrompt = false
	for _, d in clubModel:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name ~= "ExitPrompt" then
			if shouldPreserveNonEntryPrompt(d) then
				preservedDrinkPrompt = true
			else
				table.insert(prompts, d)
			end
		end
	end
	if preservedDrinkPrompt then
		print(string.format("[%s] ClubDoorService preserved drink prompt for %s", GAME_LABEL, clubModel.Name))
	end
	if #prompts == 0 then
		return
	end
	if #prompts == 1 then
		prompts[1].Name = "ClubPrompt"
		return
	end
	table.sort(prompts, function(a, b)
		local rank = function(p: ProximityPrompt)
			return p.Name == "ClubPrompt" and 1 or 0
		end
		return rank(a) > rank(b)
	end)
	for i = 2, #prompts do
		warn(
			string.format(
				"[%s] ClubDoorService: removing duplicate ENTRY ProximityPrompt in %s — %s",
				GAME_LABEL,
				clubModel.Name,
				prompts[i]:GetFullName()
			)
		)
		prompts[i]:Destroy()
	end
	prompts[1].Name = "ClubPrompt"
	print(string.format("[%s] ClubDoorService: deduped entry ProximityPrompt in %s", GAME_LABEL, clubModel.Name))
end

local function findClubModel(modelName: string, timeout: number): Model?
	local deadline = os.clock() + timeout
	repeat
		local club = Workspace:FindFirstChild(modelName, true)
		if club and club:IsA("Model") then
			return club
		end
		task.wait(0.2)
	until os.clock() >= deadline

	return nil
end

local function getSpawnPart(clubModel: Model): BasePart?
	local spawn = clubModel:FindFirstChild("ClubSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	return nil
end

local function getSafeTeleportPosition(clubModel: Model): Vector3?
	local interiorFloor = clubModel:FindFirstChild("InteriorFloor", true)
	if interiorFloor and interiorFloor:IsA("BasePart") then
		local safePos = Vector3.new(
			interiorFloor.Position.X,
			interiorFloor.Position.Y + (interiorFloor.Size.Y / 2) + INTERIOR_TELEPORT_CLEARANCE,
			interiorFloor.Position.Z
		)

		print(
			string.format(
				"[%s] ClubDoorService: using InteriorFloor for %s at %s",
				GAME_LABEL,
				clubModel.Name,
				tostring(safePos)
			)
		)

		return safePos
	end

	local spawnPart = clubModel:FindFirstChild("ClubSpawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		local safePos = spawnPart.Position + Vector3.new(0, 2, 0)

		print(
			string.format(
				"[%s] ClubDoorService: using ClubSpawn fallback for %s at %s",
				GAME_LABEL,
				clubModel.Name,
				tostring(safePos)
			)
		)

		return safePos
	end

	warn(string.format("[%s] ClubDoorService: no InteriorFloor or ClubSpawn found in %s", GAME_LABEL, clubModel.Name))
	return nil
end

local function getClubExitCFrame(clubModel: Model): (CFrame, string)
	local frontExitPoint = clubModel:FindFirstChild("FrontExitPoint", true)
	if frontExitPoint and frontExitPoint:IsA("BasePart") then
		return frontExitPoint.CFrame, "FrontExitPoint"
	end

	local exitPoint = clubModel:FindFirstChild("ExitPoint", true)
	if exitPoint and exitPoint:IsA("BasePart") then
		return exitPoint.CFrame, "ExitPoint"
	end

	local entranceDoor = clubModel:FindFirstChild("EntranceDoor", true)
	if entranceDoor and entranceDoor:IsA("BasePart") then
		local forward = entranceDoor.CFrame.LookVector
		local exitPos = entranceDoor.Position + (forward * 8) + Vector3.new(0, 1.5, 0)
		local exitLookAt = exitPos + forward
		return CFrame.lookAt(exitPos, exitLookAt), "EntranceDoor"
	end

	error(string.format("[%s] ClubDoorService: no exit reference found in %s", GAME_LABEL, clubModel.Name))
end

local function safeTeleportPlayerToWorld(player: Player, target: Vector3 | CFrame, logLabel: string): boolean
	local character = player.Character
	if not character then
		warn(string.format("[%s] ClubDoorService: no character for %s", GAME_LABEL, player.Name))
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not hrp then
		warn(string.format("[%s] ClubDoorService: humanoid/root missing for %s", GAME_LABEL, player.Name))
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

	print(
		string.format(
			"[%s] ClubDoorService: teleported %s — %s — at %s",
			GAME_LABEL,
			player.Name,
			logLabel,
			tostring(targetPosition)
		)
	)

	return true
end

local function safeTeleportIntoClub(player: Player, clubModel: Model): boolean
	local targetPosition = getSafeTeleportPosition(clubModel)
	if not targetPosition then
		return false
	end
	return safeTeleportPlayerToWorld(player, targetPosition, "into " .. clubModel.Name)
end

local function handlePromptTriggered(player: Player, clubName: string, clubModel: Model)
	local okCanEnter, canEnter = pcall(function()
		return ClubService.CanEnterClub(player, clubName)
	end)

	if not okCanEnter then
		fireNotification(player, "Erro ao verificar acesso da boate.", "error")
		warn(string.format("[%s] ClubDoorService: CanEnterClub crashed for %s", GAME_LABEL, clubName))
		return
	end

	if not canEnter then
		local deniedMessage = getDeniedMessage(player, clubName)
		fireNotification(player, deniedMessage, "error")
		print(string.format("[%s] ClubDoorService: access denied for %s -> %s", GAME_LABEL, player.Name, clubName))
		return
	end

	local okTeleport = safeTeleportIntoClub(player, clubModel)

	if okTeleport then
		local welcomeMessage = ClubService.GetWelcomeMessage(clubName) or "Bem-vindo!"

		fireNotification(player, welcomeMessage, "success")
		print(string.format("[%s] ClubDoorService: %s entered %s", GAME_LABEL, player.Name, clubName))
	else
		fireNotification(player, "Falha ao entrar na boate. Tente novamente.", "error")
	end
end

local function wireClub(clubName: string)
	local clubModel = findClubModel(clubName, CLUB_MODEL_FIND_TIMEOUT)
	if not clubModel then
		warn(
			string.format(
				"[%s] ClubDoorService: club model %q not found after %.1fs — skip wiring (map still loading?)",
				GAME_LABEL,
				clubName,
				CLUB_MODEL_FIND_TIMEOUT
			)
		)
		return
	end

	local keptSpawn = dedupeClubSpawns(clubModel, clubName)
	if not keptSpawn then
		warn(string.format("[%s] ClubDoorService: no ClubSpawn in %q — skip wiring", GAME_LABEL, clubName))
		return
	end

	dedupeEntryProximityPrompts(clubModel)

	local prompt = findPrompt(clubModel)
	if not prompt then
		warn(string.format("[%s] ClubPrompt / ProximityPrompt not found in %s", GAME_LABEL, clubName))
		return
	end

	print(
		string.format(
			"[%s] ClubDoorService: using ClubPrompt %s for %s",
			GAME_LABEL,
			prompt:GetFullName(),
			clubName
		)
	)

	prompt.Triggered:Connect(function(player: Player)
		handlePromptTriggered(player, clubName, clubModel)
	end)

	print(string.format("[%s] ClubDoorService: wired prompt for %s", GAME_LABEL, clubName))

	local exitDoor = clubModel:FindFirstChild("ExitDoor", true)
	if exitDoor then
		local exitPrompt = exitDoor:FindFirstChild("ExitPrompt")
		if not exitPrompt or not exitPrompt:IsA("ProximityPrompt") then
			exitPrompt = exitDoor:FindFirstChild("ExitPrompt", true)
		end
		if exitPrompt and exitPrompt:IsA("ProximityPrompt") then
			exitPrompt.Triggered:Connect(function(player: Player)
				local okExit, exitCFrame, exitSource = pcall(getClubExitCFrame, clubModel)
				if okExit then
					if safeTeleportPlayerToWorld(player, exitCFrame, "nightclub exit — " .. clubName) then
						fireNotification(player, "You left the nightclub.", "success")
						local exitPosition = exitCFrame.Position
						print(string.format(
							"[%s] ClubExit: %s exited %s via %s to %.2f,%.2f,%.2f",
							GAME_LABEL,
							player.Name,
							clubName,
							exitSource,
							exitPosition.X,
							exitPosition.Y,
							exitPosition.Z
						))
					end
				else
					warn(string.format("[%s] ClubDoorService: %s", GAME_LABEL, tostring(exitCFrame)))
					fireNotification(player, "Could not leave the club (missing exit data).", "error")
				end
			end)
			print("[MY CITY] ExitPrompt wired for:", clubName)
		else
			warn("[MY CITY] ExitPrompt NOT FOUND in ExitDoor for:", clubName)
		end
	else
		warn("[MY CITY] ExitDoor NOT FOUND in:", clubName)
	end
end

function ClubDoorService.Start()
	task.defer(function()
		task.wait(1)

		print(string.format("[%s] ClubDoorService: wiring club doors (models retry up to %ds)", GAME_LABEL, CLUB_MODEL_FIND_TIMEOUT))

		for _, clubName in ipairs(CLUB_NAMES) do
			wireClub(clubName)
		end

		print(string.format("[%s] ClubDoorService initialized", GAME_LABEL))
	end)
end

ClubDoorService.Start()

return ClubDoorService

