--[[
	Run in Roblox Studio: View → Command Bar, paste this entire file and press Enter.
	Creates or repairs ExitDoor + ExitPrompt ("ExitPrompt") near each club's interior exit.
	ClubDoorService still wires gameplay on server start; this fixes missing instances in the map.
]]

local Workspace = game:GetService("Workspace")

local CLUB_NAMES = { "Club_Bronze", "Club_Silver", "Club_Gold", "Club_Diamond" }

local EXIT_INWARD_STUDS = 6
local EXIT_DOOR_SIZE = Vector3.new(6, 8, 1)

local function getSpawnPart(clubModel: Model): BasePart?
	local spawn = clubModel:FindFirstChild("ClubSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	return nil
end

local function getEntranceReferencePart(clubModel: Model): BasePart?
	local entrance = clubModel:FindFirstChild("EntranceDoor", true)
	if entrance and entrance:IsA("BasePart") then
		return entrance
	end
	local entryPrompt = clubModel:FindFirstChild("ClubPrompt", true)
	if entryPrompt and entryPrompt:IsA("ProximityPrompt") then
		local parent = entryPrompt.Parent
		if parent and parent:IsA("BasePart") then
			return parent
		end
	end
	return getSpawnPart(clubModel)
end

local function configureExitPrompt(prompt: ProximityPrompt)
	prompt.Name = "ExitPrompt"
	prompt.ActionText = "Exit Club"
	prompt.ObjectText = "Leave"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
end

for _, clubName in ipairs(CLUB_NAMES) do
	local clubModel = Workspace:FindFirstChild(clubName, true)
	if not clubModel or not clubModel:IsA("Model") then
		warn("[CreateClubExitPrompts] Model not found: " .. clubName)
	else
		local entrance = getEntranceReferencePart(clubModel)
		if not entrance then
			warn("[CreateClubExitPrompts] No EntranceDoor / ClubPrompt parent / ClubSpawn for " .. clubName)
		else
			local inward = entrance.CFrame.LookVector
			local doorCenter = entrance.Position
			local insidePos = doorCenter + inward * EXIT_INWARD_STUDS + Vector3.new(0, 1, 0)

			local exitDoor = clubModel:FindFirstChild("ExitDoor", true)
			if not exitDoor or not exitDoor:IsA("BasePart") then
				exitDoor = Instance.new("Part")
				exitDoor.Name = "ExitDoor"
				exitDoor.Parent = clubModel
			end
			exitDoor.Size = EXIT_DOOR_SIZE
			exitDoor.CFrame = CFrame.new(insidePos, insidePos + inward)
			exitDoor.Anchored = true
			exitDoor.CanCollide = false
			exitDoor.Transparency = 1

			local existing = exitDoor:FindFirstChild("ExitPrompt")
			if existing and not existing:IsA("ProximityPrompt") then
				existing:Destroy()
				existing = nil
			end
			local exitPrompt: ProximityPrompt
			if existing and existing:IsA("ProximityPrompt") then
				exitPrompt = existing
			else
				exitPrompt = Instance.new("ProximityPrompt")
				exitPrompt.Parent = exitDoor
			end
			configureExitPrompt(exitPrompt)
			-- Remove stale flag from older ClubDoorService versions (Attributes save with the place).
			exitPrompt:SetAttribute("MY_CITY_ClubExitWired", nil)

			print("[CreateClubExitPrompts] OK " .. exitPrompt:GetFullName())
		end
	end
end

print("[CreateClubExitPrompts] Done.")
