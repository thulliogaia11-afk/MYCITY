--[[
	Run in Roblox Studio Command Bar when MCP is unavailable.
	Creates Workspace.PoorDistrict with House_Poor_1 .. House_Poor_6.
]]

local ws = game.Workspace
local ex = ws:FindFirstChild("PoorDistrict")
if ex then
	ex:Destroy()
end

local district = Instance.new("Model")
district.Name = "PoorDistrict"
district.Parent = ws

local xs = { -50, -30, -10, 10, 30, 50 }

for hi, hx in ipairs(xs) do
	local hm = Instance.new("Model")
	hm.Name = "House_Poor_" .. hi
	hm.Parent = district

	local z0 = 50

	local function mk(name, sz, pos, rgb, mat)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = sz
		p.Position = pos
		p.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		p.Anchored = true
		p.CanCollide = true
		if mat then
			p.Material = mat
		end
		p.Parent = hm
		return p
	end

	local frontZ = z0 + 6 - 0.15

	mk("Walls", Vector3.new(12, 8, 12), Vector3.new(hx, 4, z0), { 180, 160, 130 }, Enum.Material.SmoothPlastic)
	mk("Roof", Vector3.new(14, 2, 14), Vector3.new(hx, 9, z0), { 100, 70, 50 }, Enum.Material.SmoothPlastic)
	local door = mk("Door", Vector3.new(2, 4, 0.3), Vector3.new(hx, 2, frontZ), { 80, 50, 30 }, nil)
	mk("Window_Left", Vector3.new(2, 2, 0.3), Vector3.new(hx - 3.5, 3, frontZ), { 150, 200, 220 }, Enum.Material.Glass)
	mk("Window_Right", Vector3.new(2, 2, 0.3), Vector3.new(hx + 3.5, 3, frontZ), { 150, 200, 220 }, Enum.Material.Glass)
	mk("Floor_Interior", Vector3.new(11, 0.3, 11), Vector3.new(hx, 0.15, z0), { 150, 120, 80 }, nil)
	mk("Bed", Vector3.new(4, 1.5, 6), Vector3.new(hx - 2, 0.9, z0 - 2.5), { 150, 150, 180 }, nil)
	mk("Table", Vector3.new(3, 2, 2), Vector3.new(hx, 1.15, z0), { 120, 80, 40 }, nil)
	mk("Chair", Vector3.new(1.5, 2, 1.5), Vector3.new(hx + 2.25, 1.15, z0 + 1.25), { 100, 60, 30 }, nil)

	local pp = Instance.new("ProximityPrompt")
	pp.Name = "HousePrompt"
	pp.ActionText = "Enter Home"
	pp.ObjectText = "Shared Room"
	pp.MaxActivationDistance = 8
	pp.HoldDuration = 0
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.Parent = door
end

print("[CreatePoorDistrict] OK " .. district:GetFullName())
