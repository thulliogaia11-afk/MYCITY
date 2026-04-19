local Workspace = game:GetService("Workspace")

local GAME_LABEL = "MY CITY"
local CLUB_MODEL_FIND_TIMEOUT = 10

local ClubFacadeService = {}

type FacadeTheme = {
	signText: string,
	baseColor: Color3,
	panelColor: Color3,
	trimColor: Color3,
	lightColor: Color3,
	glassColor: Color3,
	platformColor: Color3,
	stepColor: Color3,
	signPlateColor: Color3,
	signTextColor: Color3,
	baseMaterial: Enum.Material,
	panelMaterial: Enum.Material,
	trimMaterial: Enum.Material,
	platformMaterial: Enum.Material,
}

local CLUB_THEMES: { [string]: FacadeTheme } = {
	Club_Gold = {
		signText = "CLUB GOLD",
		baseColor = Color3.fromRGB(16, 16, 18),
		panelColor = Color3.fromRGB(28, 28, 32),
		trimColor = Color3.fromRGB(214, 173, 68),
		lightColor = Color3.fromRGB(255, 194, 92),
		glassColor = Color3.fromRGB(84, 62, 26),
		platformColor = Color3.fromRGB(34, 30, 26),
		stepColor = Color3.fromRGB(124, 92, 34),
		signPlateColor = Color3.fromRGB(10, 10, 12),
		signTextColor = Color3.fromRGB(255, 224, 137),
		baseMaterial = Enum.Material.Metal,
		panelMaterial = Enum.Material.SmoothPlastic,
		trimMaterial = Enum.Material.Metal,
		platformMaterial = Enum.Material.Slate,
	},
	Club_Diamond = {
		signText = "CLUB DIAMOND",
		baseColor = Color3.fromRGB(236, 239, 245),
		panelColor = Color3.fromRGB(214, 220, 231),
		trimColor = Color3.fromRGB(188, 198, 214),
		lightColor = Color3.fromRGB(112, 223, 255),
		glassColor = Color3.fromRGB(170, 231, 255),
		platformColor = Color3.fromRGB(230, 235, 244),
		stepColor = Color3.fromRGB(145, 235, 255),
		signPlateColor = Color3.fromRGB(246, 248, 252),
		signTextColor = Color3.fromRGB(255, 255, 255),
		baseMaterial = Enum.Material.SmoothPlastic,
		panelMaterial = Enum.Material.Marble,
		trimMaterial = Enum.Material.SmoothPlastic,
		platformMaterial = Enum.Material.Marble,
	},
}

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

local function rebuildVisualFolder(clubModel: Model): Folder
	local existing = clubModel:FindFirstChild("FacadeVisuals")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "FacadeVisuals"
	folder.Parent = clubModel
	return folder
end

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addLight(part: BasePart, color: Color3, brightness: number, range: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Brightness = brightness
	pointLight.Range = range
	pointLight.Shadows = false
	pointLight.Parent = part
end

local function addSurfaceSign(signPart: BasePart, text: string, textColor: Color3)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "SignGui"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.AlwaysOnTop = true
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 42
	surfaceGui.Parent = signPart

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.GothamBlack
	title.Text = text
	title.TextScaled = true
	title.TextColor3 = textColor
	title.TextStrokeTransparency = 0.45
	title.Parent = surfaceGui
end

local function createWallSconce(
	parent: Instance,
	name: string,
	cframe: CFrame,
	trimColor: Color3,
	lightColor: Color3
)
	local base = createPart(parent, name, Vector3.new(0.7, 1.6, 0.45), cframe, trimColor, Enum.Material.Metal)
	local glow = createPart(
		parent,
		name .. "_Glow",
		Vector3.new(0.35, 1, 0.2),
		cframe * CFrame.new(0, 0, 0.24),
		lightColor,
		Enum.Material.Neon
	)
	addLight(glow, lightColor, 0.85, 10)
	return base, glow
end

local function createSignAssembly(
	parent: Instance,
	baseCFrame: CFrame,
	y: number,
	z: number,
	width: number,
	height: number,
	theme: FacadeTheme
)
	local backPlate = createPart(
		parent,
		"SignBackPlate",
		Vector3.new(width + 1.4, height + 0.8, 0.45),
		baseCFrame * CFrame.new(0, y, z - 0.08),
		theme.trimColor,
		theme.trimMaterial
	)
	local signPlate = createPart(
		parent,
		"FacadeSign",
		Vector3.new(width, height, 0.3),
		baseCFrame * CFrame.new(0, y, z),
		theme.signPlateColor,
		Enum.Material.SmoothPlastic
	)
	addSurfaceSign(signPlate, theme.signText, theme.signTextColor)
	addLight(signPlate, theme.lightColor, 0.75, 16)
	return backPlate, signPlate
end

local function createNeonColumn(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	range: number
)
	local column = createPart(parent, name, size, cframe, color, Enum.Material.Neon)
	addLight(column, color, 1.2, range)
	return column
end

local function createGlassPanel(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	transparency: number
)
	return createPart(parent, name, size, cframe, color, Enum.Material.Glass, transparency)
end

local function buildGoldFacade(clubModel: Model, entranceDoor: BasePart)
	local folder = rebuildVisualFolder(clubModel)
	local cf = entranceDoor.CFrame
	local theme = CLUB_THEMES.Club_Gold
	local baseZ = 1.05

	createPart(
		folder,
		"FacadeBase",
		Vector3.new(32, 20, 1.3),
		cf * CFrame.new(0, 5.5, baseZ),
		theme.baseColor,
		theme.baseMaterial
	)
	createPart(
		folder,
		"FacadePanel",
		Vector3.new(25, 15.5, 0.8),
		cf * CFrame.new(0, 5.2, baseZ + 0.18),
		theme.panelColor,
		theme.panelMaterial
	)
	createPart(
		folder,
		"HeaderBand",
		Vector3.new(26, 3.6, 0.7),
		cf * CFrame.new(0, 12.1, baseZ + 0.28),
		Color3.fromRGB(22, 20, 18),
		Enum.Material.Metal
	)

	createPart(
		folder,
		"DoorPortalBack",
		Vector3.new(15.5, 11.5, 0.75),
		cf * CFrame.new(0, 3.7, baseZ + 0.34),
		Color3.fromRGB(10, 10, 12),
		Enum.Material.SmoothPlastic
	)
	createPart(
		folder,
		"DoorPortalTop",
		Vector3.new(14.6, 0.95, 0.9),
		cf * CFrame.new(0, 8.55, baseZ + 0.5),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"DoorPortalLeft",
		Vector3.new(1.05, 10.8, 0.9),
		cf * CFrame.new(-6.75, 3.55, baseZ + 0.5),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"DoorPortalRight",
		Vector3.new(1.05, 10.8, 0.9),
		cf * CFrame.new(6.75, 3.55, baseZ + 0.5),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"DoorPortalInsetTop",
		Vector3.new(12.4, 0.3, 0.95),
		cf * CFrame.new(0, 7.8, baseZ + 0.58),
		Color3.fromRGB(255, 229, 146),
		Enum.Material.Neon
	)

	createNeonColumn(
		folder,
		"LeftLightStrip",
		cf * CFrame.new(-9.4, 4.2, baseZ + 0.56),
		Vector3.new(0.45, 13, 0.3),
		theme.lightColor,
		18
	)
	createNeonColumn(
		folder,
		"RightLightStrip",
		cf * CFrame.new(9.4, 4.2, baseZ + 0.56),
		Vector3.new(0.45, 13, 0.3),
		theme.lightColor,
		18
	)

	createPart(
		folder,
		"LeftWallPanelOuter",
		Vector3.new(7.5, 12.5, 0.65),
		cf * CFrame.new(-11.4, 4.6, baseZ + 0.08),
		Color3.fromRGB(21, 21, 24),
		theme.panelMaterial
	)
	createPart(
		folder,
		"RightWallPanelOuter",
		Vector3.new(7.5, 12.5, 0.65),
		cf * CFrame.new(11.4, 4.6, baseZ + 0.08),
		Color3.fromRGB(21, 21, 24),
		theme.panelMaterial
	)
	createPart(
		folder,
		"LeftWallPanelInner",
		Vector3.new(5.6, 9.8, 0.25),
		cf * CFrame.new(-11.4, 4.25, baseZ + 0.42),
		Color3.fromRGB(39, 33, 27),
		Enum.Material.SmoothPlastic
	)
	createPart(
		folder,
		"RightWallPanelInner",
		Vector3.new(5.6, 9.8, 0.25),
		cf * CFrame.new(11.4, 4.25, baseZ + 0.42),
		Color3.fromRGB(39, 33, 27),
		Enum.Material.SmoothPlastic
	)
	createPart(
		folder,
		"LeftWallTrimTop",
		Vector3.new(7.5, 0.3, 0.85),
		cf * CFrame.new(-11.4, 9.95, baseZ + 0.2),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"RightWallTrimTop",
		Vector3.new(7.5, 0.3, 0.85),
		cf * CFrame.new(11.4, 9.95, baseZ + 0.2),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"LeftWallTrimBottom",
		Vector3.new(7.5, 0.22, 0.75),
		cf * CFrame.new(-11.4, -0.4, baseZ + 0.2),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"RightWallTrimBottom",
		Vector3.new(7.5, 0.22, 0.75),
		cf * CFrame.new(11.4, -0.4, baseZ + 0.2),
		theme.trimColor,
		theme.trimMaterial
	)

	createGlassPanel(
		folder,
		"LeftGlassPanel",
		cf * CFrame.new(-4.65, 3.45, baseZ + 0.68),
		Vector3.new(2.8, 6.8, 0.22),
		theme.glassColor,
		0.42
	)
	createGlassPanel(
		folder,
		"RightGlassPanel",
		cf * CFrame.new(4.65, 3.45, baseZ + 0.68),
		Vector3.new(2.8, 6.8, 0.22),
		theme.glassColor,
		0.42
	)
	createPart(
		folder,
		"LeftGlassTrim",
		Vector3.new(2.95, 0.15, 0.3),
		cf * CFrame.new(-4.65, 6.95, baseZ + 0.74),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"RightGlassTrim",
		Vector3.new(2.95, 0.15, 0.3),
		cf * CFrame.new(4.65, 6.95, baseZ + 0.74),
		theme.trimColor,
		theme.trimMaterial
	)

	createPart(
		folder,
		"EntryPlatform",
		Vector3.new(12.5, 0.7, 4.8),
		cf * CFrame.new(0, -2.7, 3.1),
		theme.platformColor,
		theme.platformMaterial
	)
	createPart(
		folder,
		"EntryStep",
		Vector3.new(10.6, 0.26, 1.85),
		cf * CFrame.new(0, -2.12, 5.2),
		theme.stepColor,
		Enum.Material.Metal
	)

	createWallSconce(folder, "LeftWallSconce", cf * CFrame.new(-6.1, 1.8, baseZ + 0.75), theme.trimColor, theme.lightColor)
	createWallSconce(folder, "RightWallSconce", cf * CFrame.new(6.1, 1.8, baseZ + 0.75), theme.trimColor, theme.lightColor)

	createSignAssembly(folder, cf, 11.85, baseZ + 0.78, 13.4, 2.5, theme)
end

local function buildDiamondAccent(parent: Instance, name: string, cframe: CFrame, color: Color3, transparency: number)
	local diamond = createPart(
		parent,
		name,
		Vector3.new(2.2, 2.2, 0.24),
		cframe * CFrame.Angles(0, 0, math.rad(45)),
		color,
		Enum.Material.Glass,
		transparency
	)
	addLight(diamond, color, 0.45, 9)
	return diamond
end

local function buildDiamondFacade(clubModel: Model, entranceDoor: BasePart)
	local folder = rebuildVisualFolder(clubModel)
	local cf = entranceDoor.CFrame
	local theme = CLUB_THEMES.Club_Diamond
	local baseZ = 1.05

	createPart(
		folder,
		"FacadeBase",
		Vector3.new(33, 20, 1.3),
		cf * CFrame.new(0, 5.6, baseZ),
		theme.baseColor,
		theme.baseMaterial
	)
	createPart(
		folder,
		"FacadeInnerLayer",
		Vector3.new(26, 16.2, 0.78),
		cf * CFrame.new(0, 5.3, baseZ + 0.16),
		theme.panelColor,
		theme.panelMaterial
	)
	createPart(
		folder,
		"HeaderBand",
		Vector3.new(27, 3.4, 0.65),
		cf * CFrame.new(0, 12.2, baseZ + 0.28),
		Color3.fromRGB(225, 230, 240),
		Enum.Material.SmoothPlastic
	)

	createPart(
		folder,
		"PortalBack",
		Vector3.new(15.8, 11.6, 0.72),
		cf * CFrame.new(0, 3.75, baseZ + 0.33),
		Color3.fromRGB(246, 248, 252),
		Enum.Material.SmoothPlastic
	)
	createPart(
		folder,
		"PortalFrameTop",
		Vector3.new(14.6, 0.7, 0.92),
		cf * CFrame.new(0, 8.55, baseZ + 0.5),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"PortalFrameLeft",
		Vector3.new(0.75, 10.8, 0.92),
		cf * CFrame.new(-6.7, 3.55, baseZ + 0.5),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"PortalFrameRight",
		Vector3.new(0.75, 10.8, 0.92),
		cf * CFrame.new(6.7, 3.55, baseZ + 0.5),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"PortalLightInset",
		Vector3.new(12.8, 0.22, 0.95),
		cf * CFrame.new(0, 7.78, baseZ + 0.58),
		theme.lightColor,
		Enum.Material.Neon
	)

	createNeonColumn(
		folder,
		"LeftLightColumn",
		cf * CFrame.new(-9.75, 4.5, baseZ + 0.55),
		Vector3.new(0.38, 13.4, 0.24),
		theme.lightColor,
		20
	)
	createNeonColumn(
		folder,
		"RightLightColumn",
		cf * CFrame.new(9.75, 4.5, baseZ + 0.55),
		Vector3.new(0.38, 13.4, 0.24),
		theme.lightColor,
		20
	)

	createPart(
		folder,
		"LeftWingPanel",
		Vector3.new(8.2, 12.6, 0.6),
		cf * CFrame.new(-11.35, 4.6, baseZ + 0.08),
		Color3.fromRGB(228, 233, 241),
		Enum.Material.Marble
	)
	createPart(
		folder,
		"RightWingPanel",
		Vector3.new(8.2, 12.6, 0.6),
		cf * CFrame.new(11.35, 4.6, baseZ + 0.08),
		Color3.fromRGB(228, 233, 241),
		Enum.Material.Marble
	)
	createGlassPanel(
		folder,
		"LeftGlassWing",
		cf * CFrame.new(-5.35, 3.75, baseZ + 0.66),
		Vector3.new(3.9, 7.2, 0.22),
		theme.glassColor,
		0.28
	)
	createGlassPanel(
		folder,
		"RightGlassWing",
		cf * CFrame.new(5.35, 3.75, baseZ + 0.66),
		Vector3.new(3.9, 7.2, 0.22),
		theme.glassColor,
		0.28
	)
	createPart(
		folder,
		"LeftGlassTrim",
		Vector3.new(4.15, 0.16, 0.28),
		cf * CFrame.new(-5.35, 7.45, baseZ + 0.7),
		theme.trimColor,
		theme.trimMaterial
	)
	createPart(
		folder,
		"RightGlassTrim",
		Vector3.new(4.15, 0.16, 0.28),
		cf * CFrame.new(5.35, 7.45, baseZ + 0.7),
		theme.trimColor,
		theme.trimMaterial
	)

	buildDiamondAccent(folder, "DiamondLeft", cf * CFrame.new(-11, 8.55, baseZ + 0.58), theme.lightColor, 0.12)
	buildDiamondAccent(folder, "DiamondRight", cf * CFrame.new(11, 8.55, baseZ + 0.58), theme.lightColor, 0.12)
	buildDiamondAccent(folder, "DiamondCenter", cf * CFrame.new(0, 12.15, baseZ + 0.58), theme.trimColor, 0.08)

	createPart(
		folder,
		"EntryPlatform",
		Vector3.new(12.8, 0.68, 5.2),
		cf * CFrame.new(0, -2.72, 3.25),
		theme.platformColor,
		theme.platformMaterial
	)
	createPart(
		folder,
		"EntryStep",
		Vector3.new(10.8, 0.22, 2.1),
		cf * CFrame.new(0, -2.12, 5.35),
		theme.stepColor,
		Enum.Material.Neon
	)

	createWallSconce(folder, "LeftWallSconce", cf * CFrame.new(-6.2, 1.95, baseZ + 0.73), theme.trimColor, theme.lightColor)
	createWallSconce(folder, "RightWallSconce", cf * CFrame.new(6.2, 1.95, baseZ + 0.73), theme.trimColor, theme.lightColor)

	createSignAssembly(folder, cf, 11.92, baseZ + 0.8, 15, 2.6, theme)
end

local function decorateClub(clubName: string)
	local clubModel = findClubModel(clubName, CLUB_MODEL_FIND_TIMEOUT)
	if not clubModel then
		warn(string.format("[%s] ClubFacadeService: club model %q not found", GAME_LABEL, clubName))
		return
	end

	local entranceDoor = clubModel:FindFirstChild("EntranceDoor", true)
	if not entranceDoor or not entranceDoor:IsA("BasePart") then
		warn(string.format("[%s] ClubFacadeService: EntranceDoor not found in %s", GAME_LABEL, clubName))
		return
	end

	if clubName == "Club_Gold" then
		buildGoldFacade(clubModel, entranceDoor)
	elseif clubName == "Club_Diamond" then
		buildDiamondFacade(clubModel, entranceDoor)
	end

	print(string.format("[%s] ClubFacadeService: decorated %s front facade", GAME_LABEL, clubName))
end

function ClubFacadeService.Start()
	task.defer(function()
		task.wait(1)
		decorateClub("Club_Gold")
		decorateClub("Club_Diamond")
	end)
end

return ClubFacadeService
