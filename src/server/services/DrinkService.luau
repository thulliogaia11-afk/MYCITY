local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GAME_LABEL = "MY CITY"
local CLUB_MODEL_FIND_TIMEOUT = 10
local PROMPT_SESSION_TIMEOUT = 20
local PURCHASE_DISTANCE_LIMIT = 18

local DrinkCatalog = require(Shared:WaitForChild("DrinkCatalog") :: ModuleScript)
local ClubService = require(script.Parent:WaitForChild("ClubService") :: ModuleScript)
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local SocialRatingService = require(script.Parent:WaitForChild("SocialRatingService") :: ModuleScript)

local remotes = ReplicatedStorage:WaitForChild("MyCityRemotes")
local openClubDrinksEvent = remotes:WaitForChild("OpenClubDrinks") :: RemoteEvent

local DrinkService = {}

type PromptSession = {
	clubName: string,
	promptPart: BasePart,
	expiresAt: number,
}

local activePromptSessions: { [Player]: PromptSession } = {}
local DRINK_PROMPT_ATTACHMENT_NAME = "DrinkPromptAttachment"
local DRINK_PROMPT_NAME = "DrinkPrompt"
local LEGACY_ORDER_PROMPT_NAME = "OrderPrompt"

local BAR_PART_PRIORITY = {
	"BarTop",
	"BarCounter",
	"CounterTop",
	"Counter",
	"Bar",
}

local function fireNotification(player: Player, message: string, kind: string)
	local showNotification = remotes:FindFirstChild("ShowNotification")
	if showNotification and showNotification:IsA("RemoteEvent") then
		showNotification:FireClient(player, message, kind)
	end
end

local function log(message: string)
	print(string.format("[%s] %s", GAME_LABEL, message))
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

local function getClubDisplayName(clubName: string): string
	local info = ClubService.GetClubInfo(clubName)
	if info and typeof(info.Name) == "string" then
		return info.Name
	end
	return clubName
end

local function getPromptPart(prompt: ProximityPrompt): BasePart?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	if parent and parent:IsA("Attachment") then
		local attachmentParent = parent.Parent
		if attachmentParent and attachmentParent:IsA("BasePart") then
			return attachmentParent
		end
	end
	return nil
end

local function findExitPrompt(clubModel: Model): ProximityPrompt?
	local exitDoor = clubModel:FindFirstChild("ExitDoor", true)
	if exitDoor then
		local exitPrompt = exitDoor:FindFirstChild("ExitPrompt")
		if exitPrompt and exitPrompt:IsA("ProximityPrompt") then
			return exitPrompt
		end
		local nestedExitPrompt = exitDoor:FindFirstChild("ExitPrompt", true)
		if nestedExitPrompt and nestedExitPrompt:IsA("ProximityPrompt") then
			return nestedExitPrompt
		end
	end
	return nil
end

local function scoreBarPart(part: BasePart): number
	local name = string.lower(part.Name)
	if name == "bartop" then
		return 100
	elseif name == "barcounter" then
		return 90
	elseif name == "countertop" then
		return 80
	elseif name == "counter" then
		return 70
	elseif name == "bar" then
		return 60
	elseif string.find(name, "bar", 1, true) then
		return 50
	elseif string.find(name, "counter", 1, true) then
		return 40
	end
	return 0
end

local function findBarAnchor(clubModel: Model): BasePart?
	for _, preferredName in ipairs(BAR_PART_PRIORITY) do
		local inst = clubModel:FindFirstChild(preferredName, true)
		if inst and inst:IsA("BasePart") then
			return inst
		end
	end

	local bestPart: BasePart? = nil
	local bestScore = 0
	for _, descendant in clubModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			local score = scoreBarPart(descendant)
			if score > bestScore then
				bestScore = score
				bestPart = descendant
			end
		end
	end
	return bestPart
end

local function getOrCreateDrinkPromptAttachment(barAnchor: BasePart): Attachment
	local existing = barAnchor:FindFirstChild(DRINK_PROMPT_ATTACHMENT_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = DRINK_PROMPT_ATTACHMENT_NAME
	attachment.Parent = barAnchor
	log(string.format("DrinkService created attachment: %s", attachment:GetFullName()))
	return attachment
end

local function getOrCreateDrinkPrompt(barAnchor: BasePart, clubName: string): ProximityPrompt
	local attachment = getOrCreateDrinkPromptAttachment(barAnchor)
	local existing = attachment:FindFirstChild(DRINK_PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing.ActionText = "Order Drink"
		existing.ObjectText = getClubDisplayName(clubName)
		existing.HoldDuration = 0
		existing.MaxActivationDistance = 10
		existing.RequiresLineOfSight = false
		existing:SetAttribute("MY_CITY_DrinkPrompt", true)
		existing:SetAttribute("MY_CITY_DrinkPromptWired", true)
		existing.Enabled = true
		log(string.format("DrinkService reused existing prompt: %s", existing:GetFullName()))
		return existing
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = DRINK_PROMPT_NAME
	prompt.ActionText = "Order Drink"
	prompt.ObjectText = getClubDisplayName(clubName)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("MY_CITY_DrinkPrompt", true)
	prompt:SetAttribute("MY_CITY_DrinkPromptWired", true)
	prompt.Enabled = true
	prompt.Parent = attachment
	log(string.format("DrinkService created prompt: %s", prompt:GetFullName()))
	return prompt
end

local function disableLegacyOrderPrompts(clubModel: Model)
	for _, descendant in clubModel:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == LEGACY_ORDER_PROMPT_NAME then
			local parent = descendant.Parent
			local isDedicatedDrinkPrompt =
				parent ~= nil and parent.Name == DRINK_PROMPT_ATTACHMENT_NAME and descendant:GetAttribute("MY_CITY_DrinkPrompt") == true
			if not isDedicatedDrinkPrompt then
				descendant.Enabled = false
				descendant:SetAttribute("MY_CITY_IgnorePromptDedupe", true)
			end
		end
	end
end

local function buildMenuPayload(clubName: string): { [string]: any }
	return {
		clubName = clubName,
		clubDisplayName = getClubDisplayName(clubName),
		drinks = DrinkCatalog.BuildMenuRows(clubName),
	}
end

local function clearPromptSession(player: Player)
	activePromptSessions[player] = nil
end

local function wireDrinkPrompt(clubName: string, clubModel: Model, prompt: ProximityPrompt)
	if prompt:GetAttribute("MY_CITY_DrinkPromptConnected") == true then
		log(string.format("DrinkService active prompt: %s", prompt:GetFullName()))
		return
	end

	prompt:SetAttribute("MY_CITY_DrinkPrompt", true)
	prompt:SetAttribute("MY_CITY_DrinkPromptWired", true)
	prompt:SetAttribute("MY_CITY_DrinkPromptConnected", true)
	prompt.Name = "DrinkPrompt"
	prompt.ActionText = "Order Drink"
	prompt.ObjectText = getClubDisplayName(clubName)
	prompt.Enabled = true

	prompt.Triggered:Connect(function(player: Player)
		local promptPart = getPromptPart(prompt)
		if not promptPart then
			fireNotification(player, "Bar unavailable right now.", "error")
			return
		end

		activePromptSessions[player] = {
			clubName = clubName,
			promptPart = promptPart,
			expiresAt = os.clock() + PROMPT_SESSION_TIMEOUT,
		}

		openClubDrinksEvent:FireClient(player, buildMenuPayload(clubName))
	end)

	log(string.format("DrinkService wired %s bar prompt for %s", prompt:GetFullName(), clubName))
	log(string.format("DrinkService active prompt: %s", prompt:GetFullName()))
end

local function logClubPromptPaths(clubModel: Model)
	local clubPrompt = clubModel:FindFirstChild("ClubPrompt", true)
	local drinkPromptAttachment = clubModel:FindFirstChild(DRINK_PROMPT_ATTACHMENT_NAME, true)
	local drinkPrompt = if drinkPromptAttachment then drinkPromptAttachment:FindFirstChild(DRINK_PROMPT_NAME) else nil
	local exitPrompt = findExitPrompt(clubModel)

	log(string.format(
		"DrinkService prompt audit: club=%s ClubPrompt=%s DrinkPrompt=%s ExitPrompt=%s",
		clubModel.Name,
		clubPrompt and clubPrompt:GetFullName() or "missing",
		drinkPrompt and drinkPrompt:GetFullName() or "missing",
		exitPrompt and exitPrompt:GetFullName() or "missing"
	))
end

local function wireClub(clubName: string)
	local clubModel = findClubModel(clubName, CLUB_MODEL_FIND_TIMEOUT)
	if not clubModel then
		warn(string.format("[%s] DrinkService: club model %q not found", GAME_LABEL, clubName))
		return
	end

	local barAnchor = findBarAnchor(clubModel)
	if not barAnchor then
		warn(string.format("[%s] DrinkService: no bar interaction point found in %s", GAME_LABEL, clubName))
		return
	end

	disableLegacyOrderPrompts(clubModel)
	local prompt = getOrCreateDrinkPrompt(barAnchor, clubName)
	wireDrinkPrompt(clubName, clubModel, prompt)
	logClubPromptPaths(clubModel)
end

local function deny(player: Player, reason: string, clientMessage: string?): (boolean, string)
	log(string.format("Drink purchase denied: %s", reason))
	if clientMessage then
		fireNotification(player, clientMessage, "error")
	end
	return false, clientMessage or reason
end

function DrinkService.PurchaseDrink(player: Player, clubName: string, drinkId: string): (boolean, string)
	log(string.format("Drink purchase attempt: %s club=%s drink=%s", player.Name, tostring(clubName), tostring(drinkId)))

	if typeof(clubName) ~= "string" or clubName == "" then
		return deny(player, "invalid club name", "Club inválido.")
	end
	if typeof(drinkId) ~= "string" or drinkId == "" then
		return deny(player, "invalid drink id", "Drink inválido.")
	end

	local session = activePromptSessions[player]
	if not session or session.clubName ~= clubName then
		return deny(player, "no active drink session", "Aproxime-se do bar para pedir.")
	end
	if os.clock() > session.expiresAt then
		clearPromptSession(player)
		return deny(player, "drink session expired", "Pedido expirou. Abra o menu novamente.")
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return deny(player, "missing humanoid root part", "Não foi possível confirmar sua posição.")
	end
	if (hrp.Position - session.promptPart.Position).Magnitude > PURCHASE_DISTANCE_LIMIT then
		clearPromptSession(player)
		return deny(player, "player moved away from bar", "Você está longe demais do bar.")
	end

	local allowedIds = DrinkCatalog.GetAllowedDrinkIds(clubName)
	if #allowedIds == 0 then
		return deny(player, string.format("unknown club catalog %s", clubName), "Esse clube não possui cardápio disponível.")
	end

	if not DrinkCatalog.IsDrinkAllowed(clubName, drinkId) then
		return deny(player, string.format("drink %s not allowed in %s", drinkId, clubName), "Esse drink não pertence a este clube.")
	end

	local def = DrinkCatalog.GetDrinkDefinition(drinkId)
	if not def then
		return deny(player, string.format("unknown drink definition %s", drinkId), "Drink inválido.")
	end

	if not PlayerDataService.HasSession(player) then
		return deny(player, "player has no data session", "Seus dados ainda estão carregando.")
	end

	local data = PlayerDataService.GetData(player)
	local money = typeof(data.Money) == "number" and data.Money or 0
	if money < def.price then
		return deny(player, string.format("insufficient funds for %s", player.Name), "Dinheiro insuficiente.")
	end

	if not PlayerDataService.SetData(player, "Money", money - def.price) then
		return deny(player, string.format("failed to persist money for %s", player.Name), "Falha ao processar a compra.")
	end

	clearPromptSession(player)
	fireNotification(player, string.format("%s comprado por $%d.", def.displayName, def.price), "success")
	SocialRatingService.ApplyDrinkSocial(player, drinkId)
	log(string.format("Drink purchase success: %s club=%s drink=%s price=%d", player.Name, clubName, drinkId, def.price))
	return true, "ok"
end

function DrinkService.Start()
	for _, clubName in ipairs({ "Club_Bronze", "Club_Silver", "Club_Gold", "Club_Diamond" }) do
		task.defer(wireClub, clubName)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		clearPromptSession(player)
	end)
end

return DrinkService
