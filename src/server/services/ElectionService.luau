--[[
	ElectionService — MY CITY
	Per-city mayor elections: 24h mandate, candidacy (last 2h), voting (last 30m), DataStore persistence,
	impeachment votes, and inter-city trade proposals between mayors.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GAME_LABEL = "MY CITY"
local ELECTIONS_DATASTORE = "MY_CITY_Elections_v1"

-- ——— Election cycle (real-time seconds) ———
local MANDATE_DURATION = 86400 -- 24 hours
local CANDIDACY_BEFORE_MANDATE_END = 7200 -- opens 2 hours before mandate ends
local VOTING_BEFORE_MANDATE_END = 1800 -- opens 30 minutes before mandate ends

-- ——— Reputation & nominations ———
local MIN_REPUTATION_TO_NOMINATE = 300
local WINNER_REPUTATION_BONUS = 100
local MAX_CAMPAIGN_MESSAGE_LEN = 280

-- ——— Impeachment ———
local MIN_REPUTATION_TO_IMPEACH = 150
local IMPEACHMENT_DURATION_SEC = 1800 -- 30 minutes
local IMPEACHMENT_YES_THRESHOLD = 0.6 -- 60%+ of city population must vote YES
local IMPEACHED_REPUTATION_PENALTY = 50

-- ——— Trade deals ———
local TRADE_RESPONSE_WINDOW_SEC = 3600 -- 1 hour to accept/reject
local TRADE_BONUS_DURATION_SEC = 86400 -- bonuses last 24 hours after acceptance

local FOOD_IMPORT_PAY_MULT = 1.05 -- +5% job pay (stacks multiplicatively per active deal)
local SECURITY_RANKING_BONUS = 15 -- crime/security represented as ranking score adjustment
local TOURISM_RANKING_BONUS = 20

-- ——— Tick ———
local PHASE_CHECK_INTERVAL_SEC = 60

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService") :: ModuleScript)
local CityService = require(script.Parent:WaitForChild("CityService") :: ModuleScript)
local ReputationService = require(script.Parent:WaitForChild("ReputationService") :: ModuleScript)

local electionsStore = DataStoreService:GetDataStore(ELECTIONS_DATASTORE)

export type ElectionPhase = "mandate" | "candidacy" | "voting" | "counting"

export type CandidateData = {
	name: string,
	votes: number,
	campaignMessage: string,
}

export type ActiveTradeDeal = {
	id: string,
	partnerCity: string,
	dealType: string,
	bonusUntil: number,
}

export type PendingOutgoingTrade = {
	id: string,
	toCity: string,
	dealType: string,
	proposedAt: number,
	expiresAt: number,
	proposerUserId: number,
}

export type PendingIncomingTrade = {
	id: string,
	fromCity: string,
	dealType: string,
	proposedAt: number,
	expiresAt: number,
	proposerUserId: number,
}

export type ImpeachmentState = {
	startedAt: number,
	endsAt: number,
	initiatorUserId: number,
	yesVoters: { [number]: boolean },
	noVoters: { [number]: boolean },
}

export type CityElectionState = {
	currentMayor: number?,
	currentMayorName: string,
	mandateEndTime: number,
	candidates: { [number]: CandidateData },
	voters: { [number]: boolean },
	phase: ElectionPhase,
	activeTrades: { ActiveTradeDeal },
	pendingOutgoing: { PendingOutgoingTrade },
	pendingIncoming: { PendingIncomingTrade },
	impeachment: ImpeachmentState?,
}

export type MayorInfo = {
	userId: number,
	name: string,
	mayorTitle: string?,
}

export type ElectionSnapshot = {
	cityName: string,
	phase: ElectionPhase,
	mandateEndTime: number,
	timeRemaining: number,
	currentMayor: number?,
	currentMayorName: string,
	candidates: { { userId: number, name: string, votes: number, campaignMessage: string } },
	voterCount: number,
	secondsUntilMandateEnds: number,
	hasVoted: boolean?,
	secondsUntilCurrentPhaseEnd: number,
	impeachment: {
		active: boolean,
		endsAt: number?,
		yesCount: number,
		noCount: number,
		votesNeeded: number,
	}?,
	activeTrades: { ActiveTradeDeal },
	pendingOutgoing: { PendingOutgoingTrade },
	pendingIncoming: { PendingIncomingTrade },
}

local TRADE_TYPES = {
	["Food Import"] = true,
	["Security Pact"] = true,
	["Tourism Agreement"] = true,
}

local MAYOR_JOB_PREFIX = "Mayor of "

local NO_MAYOR_LABEL = "Vacant"

--- Runtime per city (hydrated from DataStore).
local electionByCity: { [string]: CityElectionState } = {}

--- Last phase we announced (prevents spam on 60s tick).
local lastAnnouncedPhase: { [string]: ElectionPhase } = {}

--- Winners offline: grant reputation + title sync on join.
local pendingMayorReputation: { [number]: string } = {}

--- Impeached while offline: apply reputation penalty on next session.
local pendingImpeachmentRepLoss: { [number]: boolean } = {}

local function printTag(msg: string)
	print(string.format("[%s] %s", GAME_LABEL, msg))
end

local function warnTag(msg: string)
	warn(string.format("[%s] %s", GAME_LABEL, msg))
end

local function mayorJobForCity(cityName: string): string
	return MAYOR_JOB_PREFIX .. cityName
end

local function mayorTitleForCity(cityName: string): string
	return "🏛️ Mayor of " .. cityName
end

local function isValidCity(cityName: string): boolean
	return CityService.GetCity(cityName) ~= nil
end

local function getShowNotification(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("MyCityRemotes")
	if not folder then
		return nil
	end
	local ev = folder:FindFirstChild("ShowNotification")
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function notifyPlayer(player: Player, message: string, kind: string)
	local ev = getShowNotification()
	if ev then
		ev:FireClient(player, message, kind)
	end
end

local function notifyCityPlayers(cityName: string, message: string, kind: string)
	for _, plr in Players:GetPlayers() do
		local data = PlayerDataService.GetData(plr)
		if data and data.City == cityName then
			notifyPlayer(plr, message, kind)
		end
	end
end

local function countTableKeys(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function playerLivesInCity(player: Player, cityName: string): boolean
	if not PlayerDataService.HasSession(player) then
		return false
	end
	local data = PlayerDataService.GetData(player)
	return typeof(data.City) == "string" and data.City == cityName
end

--[[
	Phase from wall clock vs mandateEndTime (persisted). "counting" is transient until runElectionCounting runs.
]]
local function derivePhaseFromSchedule(mandateEndTime: number, now: number): ElectionPhase
	if now >= mandateEndTime then
		return "counting"
	end
	local remaining = mandateEndTime - now
	if remaining <= VOTING_BEFORE_MANDATE_END then
		return "voting"
	end
	if remaining <= CANDIDACY_BEFORE_MANDATE_END then
		return "candidacy"
	end
	return "mandate"
end

-- ——— Serialization (DataStore-safe string keys for user ids) ———

local function serializeCityState(st: CityElectionState): { [string]: any }
	local candOut: { [string]: any } = {}
	for uid, c in st.candidates do
		candOut[tostring(uid)] = {
			name = c.name,
			votes = c.votes,
			campaignMessage = c.campaignMessage,
		}
	end
	local votersOut: { [string]: boolean } = {}
	for uid, v in st.voters do
		votersOut[tostring(uid)] = v
	end
	local yesOut: { [string]: boolean } = {}
	local noOut: { [string]: boolean } = {}
	local impeachAny: any = nil
	if st.impeachment then
		for uid, y in st.impeachment.yesVoters do
			yesOut[tostring(uid)] = y
		end
		for uid, n in st.impeachment.noVoters do
			noOut[tostring(uid)] = n
		end
		impeachAny = {
			startedAt = st.impeachment.startedAt,
			endsAt = st.impeachment.endsAt,
			initiatorUserId = st.impeachment.initiatorUserId,
			yesVoters = yesOut,
			noVoters = noOut,
		}
	end

	return {
		currentMayorUserId = st.currentMayor,
		currentMayorName = st.currentMayorName,
		mandateEndTime = st.mandateEndTime,
		candidates = candOut,
		voters = votersOut,
		phase = st.phase,
		activeTrades = st.activeTrades,
		pendingOutgoing = st.pendingOutgoing,
		pendingIncoming = st.pendingIncoming,
		impeachment = impeachAny,
	}
end

local function deserializeCityState(cityName: string, blob: any): CityElectionState?
	if typeof(blob) ~= "table" then
		return nil
	end
	local mandateEndTime = blob.mandateEndTime
	if typeof(mandateEndTime) ~= "number" then
		return nil
	end

	local candidates: { [number]: CandidateData } = {}
	if typeof(blob.candidates) == "table" then
		for k, c in blob.candidates do
			local uid = tonumber(k)
			if uid and typeof(c) == "table" then
				candidates[uid] = {
					name = typeof(c.name) == "string" and c.name or "Unknown",
					votes = typeof(c.votes) == "number" and math.floor(c.votes) or 0,
					campaignMessage = typeof(c.campaignMessage) == "string" and c.campaignMessage or "",
				}
			end
		end
	end

	local voters: { [number]: boolean } = {}
	if typeof(blob.voters) == "table" then
		for k, v in blob.voters do
			local uid = tonumber(k)
			if uid then
				voters[uid] = v == true
			end
		end
	end

	local activeTrades: { ActiveTradeDeal } = {}
	if typeof(blob.activeTrades) == "table" then
		for _, t in blob.activeTrades do
			if typeof(t) == "table" and typeof(t.id) == "string" then
				table.insert(activeTrades, {
					id = t.id,
					partnerCity = typeof(t.partnerCity) == "string" and t.partnerCity or "",
					dealType = typeof(t.dealType) == "string" and t.dealType or "",
					bonusUntil = typeof(t.bonusUntil) == "number" and t.bonusUntil or 0,
				})
			end
		end
	end

	local pendingOutgoing: { PendingOutgoingTrade } = {}
	if typeof(blob.pendingOutgoing) == "table" then
		for _, t in blob.pendingOutgoing do
			if typeof(t) == "table" and typeof(t.id) == "string" then
				table.insert(pendingOutgoing, {
					id = t.id,
					toCity = typeof(t.toCity) == "string" and t.toCity or "",
					dealType = typeof(t.dealType) == "string" and t.dealType or "",
					proposedAt = typeof(t.proposedAt) == "number" and t.proposedAt or 0,
					expiresAt = typeof(t.expiresAt) == "number" and t.expiresAt or 0,
					proposerUserId = typeof(t.proposerUserId) == "number" and t.proposerUserId or 0,
				})
			end
		end
	end

	local pendingIncoming: { PendingIncomingTrade } = {}
	if typeof(blob.pendingIncoming) == "table" then
		for _, t in blob.pendingIncoming do
			if typeof(t) == "table" and typeof(t.id) == "string" then
				table.insert(pendingIncoming, {
					id = t.id,
					fromCity = typeof(t.fromCity) == "string" and t.fromCity or "",
					dealType = typeof(t.dealType) == "string" and t.dealType or "",
					proposedAt = typeof(t.proposedAt) == "number" and t.proposedAt or 0,
					expiresAt = typeof(t.expiresAt) == "number" and t.expiresAt or 0,
					proposerUserId = typeof(t.proposerUserId) == "number" and t.proposerUserId or 0,
				})
			end
		end
	end

	local impeachment: ImpeachmentState? = nil
	if typeof(blob.impeachment) == "table" then
		local imp = blob.impeachment
		local yesV: { [number]: boolean } = {}
		local noV: { [number]: boolean } = {}
		if typeof(imp.yesVoters) == "table" then
			for k, v in imp.yesVoters do
				local uid = tonumber(k)
				if uid then
					yesV[uid] = v == true
				end
			end
		end
		if typeof(imp.noVoters) == "table" then
			for k, v in imp.noVoters do
				local uid = tonumber(k)
				if uid then
					noV[uid] = v == true
				end
			end
		end
		impeachment = {
			startedAt = typeof(imp.startedAt) == "number" and imp.startedAt or 0,
			endsAt = typeof(imp.endsAt) == "number" and imp.endsAt or 0,
			initiatorUserId = typeof(imp.initiatorUserId) == "number" and imp.initiatorUserId or 0,
			yesVoters = yesV,
			noVoters = noV,
		}
	end

	local mayorUid = blob.currentMayorUserId
	local currentMayor: number? = nil
	if typeof(mayorUid) == "number" then
		currentMayor = mayorUid
	end

	local st: CityElectionState = {
		currentMayor = currentMayor,
		currentMayorName = typeof(blob.currentMayorName) == "string" and blob.currentMayorName or NO_MAYOR_LABEL,
		mandateEndTime = mandateEndTime,
		candidates = candidates,
		voters = voters,
		phase = "mandate",
		activeTrades = activeTrades,
		pendingOutgoing = pendingOutgoing,
		pendingIncoming = pendingIncoming,
		impeachment = impeachment,
	}

	local now = os.time()
	st.phase = derivePhaseFromSchedule(st.mandateEndTime, now)
	return st
end

local function saveCityElectionState(cityName: string)
	local st = electionByCity[cityName]
	if not st then
		return
	end
	local payload = serializeCityState(st)
	local ok, err = pcall(function()
		electionsStore:SetAsync(cityName, payload)
	end)
	if ok then
		printTag(string.format("ElectionService: saved state for %q", cityName))
	else
		warnTag(string.format("ElectionService: SetAsync failed for %q: %s", cityName, tostring(err)))
	end
end

local function loadCityElectionState(cityName: string): CityElectionState?
	local saved: any = nil
	local ok, result = pcall(function()
		return electionsStore:GetAsync(cityName)
	end)
	if ok then
		saved = result
	else
		warnTag(string.format("ElectionService: GetAsync failed for %q: %s", cityName, tostring(result)))
	end
	if saved == nil then
		return nil
	end
	return deserializeCityState(cityName, saved)
end

local function defaultCityElectionState(_cityName: string): CityElectionState
	local now = os.time()
	return {
		currentMayor = nil,
		currentMayorName = NO_MAYOR_LABEL,
		mandateEndTime = now + MANDATE_DURATION,
		candidates = {},
		voters = {},
		phase = "mandate",
		activeTrades = {},
		pendingOutgoing = {},
		pendingIncoming = {},
		impeachment = nil,
	}
end

local function ensureCityElectionState(cityName: string): CityElectionState
	local existing = electionByCity[cityName]
	if existing then
		return existing
	end
	local loaded = loadCityElectionState(cityName)
	if loaded then
		electionByCity[cityName] = loaded
		printTag(string.format("ElectionService: loaded persisted state for %q (mandate ends %d)", cityName, loaded.mandateEndTime))
		return loaded
	end
	local st = defaultCityElectionState(cityName)
	electionByCity[cityName] = st
	printTag(string.format("ElectionService: started first cycle for %q (mandate ends %d)", cityName, st.mandateEndTime))
	saveCityElectionState(cityName)
	return st
end

local function initAllCities()
	for cityName, _ in CityService.GetCities() do
		ensureCityElectionState(cityName)
	end
	-- Avoid re-firing candidacy/voting notifications after every server restart.
	local now = os.time()
	for cityName, st in electionByCity do
		lastAnnouncedPhase[cityName] = derivePhaseFromSchedule(st.mandateEndTime, now)
	end
end

-- ——— Mayor title / job sync ———

local function stripMayorFromPlayer(userId: number, cityName: string): boolean
	local plr = Players:GetPlayerByUserId(userId)
	if not plr then
		return false
	end
	if not PlayerDataService.HasSession(plr) then
		return false
	end
	local data = PlayerDataService.GetData(plr)
	local expected = mayorJobForCity(cityName)
	local removed = false
	if data.Job == expected then
		PlayerDataService.SetData(plr, "Job", "Unemployed")
		removed = true
	end
	if typeof(data.MayorTitle) == "string" and #data.MayorTitle > 0 then
		PlayerDataService.SetData(plr, "MayorTitle", "")
		removed = true
	end
	if removed then
		printTag(string.format("ElectionService: removed mayor role from %s (%d) for %s", plr.Name, userId, cityName))
	end
	return removed
end

local function grantMayorRoleAndBonus(userId: number, cityName: string, reason: string)
	local plr = Players:GetPlayerByUserId(userId)
	local title = mayorTitleForCity(cityName)
	if plr then
		PlayerDataService.SetData(plr, "Job", mayorJobForCity(cityName))
		PlayerDataService.SetData(plr, "MayorTitle", title)
		ReputationService.AddReputation(plr, WINNER_REPUTATION_BONUS, reason)
		printTag(
			string.format(
				"ElectionService: %s (%d) is %s — +%d reputation",
				plr.Name,
				userId,
				title,
				WINNER_REPUTATION_BONUS
			)
		)
	else
		pendingMayorReputation[userId] = cityName
		printTag(string.format("ElectionService: Mayor-elect userId=%d for %s offline — sync on join", userId, cityName))
	end
end

-- ——— Trades: prune expired ———

local function pruneExpiredTrades(st: CityElectionState, now: number)
	local active: { ActiveTradeDeal } = {}
	for _, t in st.activeTrades do
		if t.bonusUntil > now then
			table.insert(active, t)
		end
	end
	st.activeTrades = active

	local out: { PendingOutgoingTrade } = {}
	for _, t in st.pendingOutgoing do
		if t.expiresAt > now then
			table.insert(out, t)
		end
	end
	st.pendingOutgoing = out

	local inc: { PendingIncomingTrade } = {}
	for _, t in st.pendingIncoming do
		if t.expiresAt > now then
			table.insert(inc, t)
		end
	end
	st.pendingIncoming = inc
end

local function removePendingTradeBothSides(dealId: string, fromCity: string, toCity: string)
	local a = electionByCity[fromCity]
	local b = electionByCity[toCity]
	if a then
		local nextOut: { PendingOutgoingTrade } = {}
		for _, t in a.pendingOutgoing do
			if t.id ~= dealId then
				table.insert(nextOut, t)
			end
		end
		a.pendingOutgoing = nextOut
		local nextIn: { PendingIncomingTrade } = {}
		for _, t in a.pendingIncoming do
			if t.id ~= dealId then
				table.insert(nextIn, t)
			end
		end
		a.pendingIncoming = nextIn
	end
	if b then
		local nextOut: { PendingOutgoingTrade } = {}
		for _, t in b.pendingOutgoing do
			if t.id ~= dealId then
				table.insert(nextOut, t)
			end
		end
		b.pendingOutgoing = nextOut
		local nextIn: { PendingIncomingTrade } = {}
		for _, t in b.pendingIncoming do
			if t.id ~= dealId then
				table.insert(nextIn, t)
			end
		end
		b.pendingIncoming = nextIn
	end
end

local function appendActiveDeal(cityName: string, deal: ActiveTradeDeal)
	local st = ensureCityElectionState(cityName)
	table.insert(st.activeTrades, deal)
end

-- ——— Impeachment resolution ———

local function impeachmentYesVotesNeeded(cityName: string): number
	local pop = math.max(1, CityService.GetPopulation(cityName))
	return math.max(1, math.ceil(pop * IMPEACHMENT_YES_THRESHOLD))
end

local function finalizeImpeachment(cityName: string, success: boolean, mayorUserId: number?, mayorName: string)
	local st = electionByCity[cityName]
	if not st then
		return
	end
	st.impeachment = nil

	if success and mayorUserId then
		stripMayorFromPlayer(mayorUserId, cityName)
		local plr = Players:GetPlayerByUserId(mayorUserId)
		if plr then
			ReputationService.RemoveReputation(plr, IMPEACHED_REPUTATION_PENALTY, string.format("Impeached as Mayor of %s", cityName))
		else
			pendingImpeachmentRepLoss[mayorUserId] = true
			printTag(string.format("ElectionService: queued -%d rep for impeached offline mayor userId=%d", IMPEACHED_REPUTATION_PENALTY, mayorUserId))
		end

		st.currentMayor = nil
		st.currentMayorName = NO_MAYOR_LABEL
		local now = os.time()
		st.mandateEndTime = now + MANDATE_DURATION
		st.candidates = {}
		st.voters = {}
		st.phase = "mandate"
		lastAnnouncedPhase[cityName] = "mandate"

		notifyCityPlayers(
			cityName,
			string.format("⚖️ Impeachment passed — %s removed. A new election cycle has begun.", mayorName),
			"info"
		)
		printTag(string.format("ElectionService: IMPEACHMENT SUCCEEDED in %s — mayor %s removed", cityName, mayorName))
	else
		notifyCityPlayers(cityName, "⚖️ Impeachment vote failed — the Mayor remains in office.", "info")
		printTag(string.format("ElectionService: IMPEACHMENT FAILED in %s", cityName))
	end

	saveCityElectionState(cityName)
end

local function tickImpeachment(cityName: string)
	local st = electionByCity[cityName]
	if not st or not st.impeachment then
		return
	end
	local imp = st.impeachment
	local now = os.time()
	local yesCount = countTableKeys(imp.yesVoters)
	local needed = impeachmentYesVotesNeeded(cityName)

	if yesCount >= needed then
		local mid = st.currentMayor
		local mname = st.currentMayorName
		finalizeImpeachment(cityName, true, mid, mname)
		return
	end

	if now >= imp.endsAt then
		finalizeImpeachment(cityName, false, st.currentMayor, st.currentMayorName)
	end
end

-- ——— Election counting ———

local function runElectionCounting(cityName: string)
	local state = electionByCity[cityName]
	if not state then
		return
	end

	local now = os.time()
	state.phase = "counting"

	local rows: { { userId: number, name: string, votes: number } } = {}
	for userId, c in state.candidates do
		table.insert(rows, {
			userId = userId,
			name = c.name,
			votes = c.votes,
		})
	end

	if #rows == 0 then
		printTag(string.format("ElectionService: ===== RESULT — %s ===== NO CANDIDATES — mandate extended", cityName))
		if state.currentMayor then
			stripMayorFromPlayer(state.currentMayor, cityName)
		end
		state.currentMayor = nil
		state.currentMayorName = NO_MAYOR_LABEL
		state.mandateEndTime = now + MANDATE_DURATION
		state.candidates = {}
		state.voters = {}
		state.phase = "mandate"
		lastAnnouncedPhase[cityName] = "mandate"
		saveCityElectionState(cityName)
		return
	end

	table.sort(rows, function(a, b)
		if a.votes ~= b.votes then
			return a.votes > b.votes
		end
		return a.userId < b.userId
	end)

	local winner = rows[1]
	local oldMayor = state.currentMayor

	printTag(string.format("ElectionService: ===== ELECTION RESULT — %s =====", cityName))
	for rank, row in ipairs(rows) do
		printTag(string.format("ElectionService:   #%d — %s (%d) — %d votes", rank, row.name, row.userId, row.votes))
	end

	if oldMayor and oldMayor ~= winner.userId then
		stripMayorFromPlayer(oldMayor, cityName)
	end

	state.currentMayor = winner.userId
	state.currentMayorName = winner.name
	grantMayorRoleAndBonus(winner.userId, cityName, string.format("Elected Mayor of %s", cityName))

	state.mandateEndTime = now + MANDATE_DURATION
	state.candidates = {}
	state.voters = {}
	state.phase = "mandate"
	lastAnnouncedPhase[cityName] = "mandate"

	notifyCityPlayers(
		cityName,
		string.format("👑 %s has been elected Mayor of %s!", winner.name, cityName),
		"success"
	)

	printTag(string.format("ElectionService: New mandate for %s ends at %d", cityName, state.mandateEndTime))
	saveCityElectionState(cityName)
end

local function announcePhaseIfChanged(cityName: string, state: CityElectionState, now: number)
	local desired = derivePhaseFromSchedule(state.mandateEndTime, now)
	if desired == "counting" then
		return
	end
	local prev = lastAnnouncedPhase[cityName]
	if prev == desired then
		return
	end
	lastAnnouncedPhase[cityName] = desired

	if desired == "candidacy" then
		printTag(string.format("ElectionService: PHASE → CANDIDACY for %s (%d s until mandate end)", cityName, state.mandateEndTime - now))
		notifyCityPlayers(cityName, string.format("🗳️ Candidacy is now open for Mayor of %s!", cityName), "info")
	elseif desired == "voting" then
		printTag(string.format("ElectionService: PHASE → VOTING for %s", cityName))
		notifyCityPlayers(cityName, "⚡ Voting is now open! Choose your Mayor!", "info")
	end
end

local function syncPhaseTransitions(cityName: string)
	local state = electionByCity[cityName]
	if not state then
		return
	end
	local now = os.time()

	pruneExpiredTrades(state, now)
	tickImpeachment(cityName)

	if now >= state.mandateEndTime then
		runElectionCounting(cityName)
		return
	end

	local desired = derivePhaseFromSchedule(state.mandateEndTime, now)
	announcePhaseIfChanged(cityName, state, now)

	if desired ~= state.phase and desired ~= "counting" then
		local prev = state.phase
		state.phase = desired
		printTag(
			string.format(
				"ElectionService: %s phase %s → %s (%d s left in mandate)",
				cityName,
				prev,
				desired,
				state.mandateEndTime - now
			)
		)
	end
end

local function tickAllCities()
	for cityName in electionByCity do
		syncPhaseTransitions(cityName)
	end
end

local function syncMayorJobWithElectionState(player: Player)
	if pendingImpeachmentRepLoss[player.UserId] then
		pendingImpeachmentRepLoss[player.UserId] = nil
		ReputationService.RemoveReputation(player, IMPEACHED_REPUTATION_PENALTY, "Impeached as Mayor (offline)")
	end

	local data = PlayerDataService.GetData(player)
	if not data or typeof(data.City) ~= "string" or data.City == "None" then
		return
	end
	local cityName = data.City
	if not isValidCity(cityName) then
		return
	end
	ensureCityElectionState(cityName)
	local state = electionByCity[cityName]
	local expectedJob = mayorJobForCity(cityName)
	local title = mayorTitleForCity(cityName)

	local pendingCity = pendingMayorReputation[player.UserId]
	if pendingCity == cityName then
		PlayerDataService.SetData(player, "Job", expectedJob)
		PlayerDataService.SetData(player, "MayorTitle", title)
		ReputationService.AddReputation(player, WINNER_REPUTATION_BONUS, string.format("Elected Mayor of %s (late join)", cityName))
		pendingMayorReputation[player.UserId] = nil
		printTag(string.format("ElectionService: granted pending mayor package to %s for %s", player.Name, cityName))
		return
	end

	if data.Job == expectedJob or (typeof(data.MayorTitle) == "string" and data.MayorTitle == title) then
		if not state.currentMayor or state.currentMayor ~= player.UserId then
			PlayerDataService.SetData(player, "Job", "Unemployed")
			PlayerDataService.SetData(player, "MayorTitle", "")
			printTag(string.format("ElectionService: cleared stale mayor for %s in %s", player.Name, cityName))
		end
		return
	end

	if state.currentMayor == player.UserId then
		PlayerDataService.SetData(player, "Job", expectedJob)
		PlayerDataService.SetData(player, "MayorTitle", title)
		printTag(string.format("ElectionService: restored mayor for %s in %s", player.Name, cityName))
	end
end

local function secondsUntilCurrentPhaseEnd(cityName: string): number
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local T = st.mandateEndTime
	if st.phase == "mandate" then
		return math.max(0, T - CANDIDACY_BEFORE_MANDATE_END - now)
	elseif st.phase == "candidacy" then
		return math.max(0, T - VOTING_BEFORE_MANDATE_END - now)
	elseif st.phase == "voting" then
		return math.max(0, T - now)
	end
	return 0
end

-- ——— Public module ———

local ElectionService = {}

function ElectionService.GetPhase(cityName: string): ElectionPhase?
	if not isValidCity(cityName) then
		return nil
	end
	ensureCityElectionState(cityName)
	return electionByCity[cityName].phase
end

function ElectionService.GetCurrentMayor(cityName: string): MayorInfo?
	if not isValidCity(cityName) then
		return nil
	end
	ensureCityElectionState(cityName)
	local st = electionByCity[cityName]
	if not st.currentMayor then
		return nil
	end
	return {
		userId = st.currentMayor,
		name = st.currentMayorName,
		mayorTitle = mayorTitleForCity(cityName),
	}
end

function ElectionService.IsMayor(player: Player, cityName: string): boolean
	if not isValidCity(cityName) then
		return false
	end
	if not playerLivesInCity(player, cityName) then
		return false
	end
	ensureCityElectionState(cityName)
	local st = electionByCity[cityName]
	return st.currentMayor == player.UserId
end

function ElectionService.CityHasActiveMayor(cityName: string): boolean
	if not isValidCity(cityName) then
		return false
	end
	ensureCityElectionState(cityName)
	return electionByCity[cityName].currentMayor ~= nil
end

--[[
	Extra pay multiplier from active "Food Import" deals (1.05 each, multiplicative).
	JobService stacks this with the +10% mayor bonus.
]]
function ElectionService.GetTradeEconomyPayMultiplier(cityName: string): number
	if not isValidCity(cityName) then
		return 1
	end
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local m = 1
	for _, t in st.activeTrades do
		if t.bonusUntil > now and t.dealType == "Food Import" then
			m *= FOOD_IMPORT_PAY_MULT
		end
	end
	return m
end

--[[
	Ranking score bonus from "Tourism Agreement" (RankingService adds this).
]]
function ElectionService.GetTourismRankingBonus(cityName: string): number
	if not isValidCity(cityName) then
		return 0
	end
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local bonus = 0
	for _, t in st.activeTrades do
		if t.bonusUntil > now and t.dealType == "Tourism Agreement" then
			bonus += TOURISM_RANKING_BONUS
		end
	end
	return bonus
end

--[[
	Positive score adjustment from "Security Pact" (interpreted as lower crime / higher civic order).
	RankingService can add this to the city score.
]]
function ElectionService.GetSecurityRankingBonus(cityName: string): number
	if not isValidCity(cityName) then
		return 0
	end
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local bonus = 0
	for _, t in st.activeTrades do
		if t.bonusUntil > now and t.dealType == "Security Pact" then
			bonus += SECURITY_RANKING_BONUS
		end
	end
	return bonus
end

function ElectionService.GetElectionData(cityName: string, forPlayer: Player?): ElectionSnapshot?
	if not isValidCity(cityName) then
		return nil
	end
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local timeRemaining = math.max(0, st.mandateEndTime - now)
	local list: { { userId: number, name: string, votes: number, campaignMessage: string } } = {}
	for uid, c in st.candidates do
		table.insert(list, {
			userId = uid,
			name = c.name,
			votes = c.votes,
			campaignMessage = c.campaignMessage,
		})
	end

	local impSnap: {
		active: boolean,
		endsAt: number?,
		yesCount: number,
		noCount: number,
		votesNeeded: number,
	}? = nil
	if st.impeachment then
		local yesC = countTableKeys(st.impeachment.yesVoters)
		local noC = countTableKeys(st.impeachment.noVoters)
		impSnap = {
			active = true,
			endsAt = st.impeachment.endsAt,
			yesCount = yesC,
			noCount = noC,
			votesNeeded = impeachmentYesVotesNeeded(cityName),
		}
	end

	local snap: ElectionSnapshot = {
		cityName = cityName,
		phase = st.phase,
		mandateEndTime = st.mandateEndTime,
		timeRemaining = timeRemaining,
		currentMayor = st.currentMayor,
		currentMayorName = st.currentMayorName,
		candidates = list,
		voterCount = countTableKeys(st.voters),
		secondsUntilMandateEnds = timeRemaining,
		hasVoted = nil,
		secondsUntilCurrentPhaseEnd = secondsUntilCurrentPhaseEnd(cityName),
		impeachment = impSnap,
		activeTrades = table.clone(st.activeTrades),
		pendingOutgoing = table.clone(st.pendingOutgoing),
		pendingIncoming = table.clone(st.pendingIncoming),
	}
	if forPlayer then
		snap.hasVoted = st.voters[forPlayer.UserId] == true
	end
	return snap
end

function ElectionService.Nominate(player: Player, cityName: string, campaignMessage: string): (boolean, string)
	if not isValidCity(cityName) then
		return false, "Cidade inválida."
	end
	local state = ensureCityElectionState(cityName)
	if state.phase ~= "candidacy" then
		return false, "Candidaturas só na fase de candidatura (últimas 2 horas do mandato)."
	end
	if not playerLivesInCity(player, cityName) then
		return false, "Você precisa morar nesta cidade para se candidatar."
	end
	local rep = ReputationService.GetReputation(player)
	if rep < MIN_REPUTATION_TO_NOMINATE then
		return false, string.format("É necessário %d+ de reputação para se candidatar.", MIN_REPUTATION_TO_NOMINATE)
	end
	if state.candidates[player.UserId] then
		return false, "Você já é candidato nesta eleição."
	end

	local msg = typeof(campaignMessage) == "string" and campaignMessage or ""
	if #msg > MAX_CAMPAIGN_MESSAGE_LEN then
		msg = string.sub(msg, 1, MAX_CAMPAIGN_MESSAGE_LEN)
	end

	state.candidates[player.UserId] = {
		name = player.Name,
		votes = 0,
		campaignMessage = msg,
	}
	printTag(string.format("ElectionService: %s nominated for Mayor of %s", player.Name, cityName))
	saveCityElectionState(cityName)
	return true, "Candidatura registrada."
end

function ElectionService.Vote(player: Player, cityName: string, candidateUserId: number): (boolean, string)
	if not isValidCity(cityName) then
		return false, "Cidade inválida."
	end
	local state = ensureCityElectionState(cityName)
	if state.phase ~= "voting" then
		return false, "Votação só na fase de votação (últimos 30 minutos do mandato)."
	end
	if not playerLivesInCity(player, cityName) then
		return false, "Você precisa morar nesta cidade para votar."
	end
	if state.voters[player.UserId] then
		return false, "Você já votou nesta eleição."
	end
	if not state.candidates[candidateUserId] then
		return false, "Candidato inválido."
	end

	state.voters[player.UserId] = true
	state.candidates[candidateUserId].votes += 1
	printTag(string.format("ElectionService: %s voted in %s", player.Name, cityName))
	saveCityElectionState(cityName)
	return true, "Voto registrado."
end

function ElectionService.StartImpeachment(player: Player, cityName: string): (boolean, string)
	if not isValidCity(cityName) then
		return false, "Cidade inválida."
	end
	local st = ensureCityElectionState(cityName)
	if not st.currentMayor then
		return false, "Não há prefeito para impeach."
	end
	if st.impeachment then
		return false, "Já existe um processo de impeachment em andamento."
	end
	if not playerLivesInCity(player, cityName) then
		return false, "Você precisa morar nesta cidade."
	end
	if ReputationService.GetReputation(player) < MIN_REPUTATION_TO_IMPEACH then
		return false, string.format("São necessários %d+ de reputação para iniciar impeachment.", MIN_REPUTATION_TO_IMPEACH)
	end

	local now = os.time()
	st.impeachment = {
		startedAt = now,
		endsAt = now + IMPEACHMENT_DURATION_SEC,
		initiatorUserId = player.UserId,
		yesVoters = {},
		noVoters = {},
	}

	notifyCityPlayers(
		cityName,
		string.format("⚖️ %s iniciou um voto de impeachment contra o Prefeito! Você tem 30 minutos para votar.", player.Name),
		"info"
	)
	printTag(string.format("ElectionService: IMPEACHMENT STARTED in %s by %s", cityName, player.Name))
	saveCityElectionState(cityName)
	return true, "Votação de impeachment iniciada."
end

function ElectionService.VoteImpeachment(player: Player, cityName: string, voteYes: boolean): (boolean, string)
	if not isValidCity(cityName) then
		return false, "Cidade inválida."
	end
	local st = ensureCityElectionState(cityName)
	if not st.impeachment then
		return false, "Não há impeachment ativo."
	end
	local now = os.time()
	if now >= st.impeachment.endsAt then
		return false, "O período de impeachment encerrou."
	end
	if not playerLivesInCity(player, cityName) then
		return false, "Você precisa morar nesta cidade para votar."
	end
	if st.impeachment.yesVoters[player.UserId] or st.impeachment.noVoters[player.UserId] then
		return false, "Você já votou neste impeachment."
	end

	if voteYes then
		st.impeachment.yesVoters[player.UserId] = true
	else
		st.impeachment.noVoters[player.UserId] = true
	end

	saveCityElectionState(cityName)
	tickImpeachment(cityName)
	return true, "Voto registrado."
end

function ElectionService.ProposeTrade(mayorPlayer: Player, targetCityName: string, dealType: string): (boolean, string, string?)
	if not isValidCity(targetCityName) then
		return false, "Cidade alvo inválida.", nil
	end
	local data = PlayerDataService.GetData(mayorPlayer)
	if not data or typeof(data.City) ~= "string" then
		return false, "Dados indisponíveis.", nil
	end
	local fromCity = data.City
	if not isValidCity(fromCity) then
		return false, "Você precisa ser prefeito de uma cidade.", nil
	end
	if fromCity == targetCityName then
		return false, "Não é possível negociar com a própria cidade.", nil
	end
	if not ElectionService.IsMayor(mayorPlayer, fromCity) then
		return false, "Apenas o prefeito pode propor acordos.", nil
	end
	if not TRADE_TYPES[dealType] then
		return false, "Tipo de acordo inválido.", nil
	end

	local stFrom = ensureCityElectionState(fromCity)
	local stTo = ensureCityElectionState(targetCityName)

	local now = os.time()
	local id = HttpService:GenerateGUID(false)
	local expiresAt = now + TRADE_RESPONSE_WINDOW_SEC

	table.insert(stFrom.pendingOutgoing, {
		id = id,
		toCity = targetCityName,
		dealType = dealType,
		proposedAt = now,
		expiresAt = expiresAt,
		proposerUserId = mayorPlayer.UserId,
	})
	table.insert(stTo.pendingIncoming, {
		id = id,
		fromCity = fromCity,
		dealType = dealType,
		proposedAt = now,
		expiresAt = expiresAt,
		proposerUserId = mayorPlayer.UserId,
	})

	local targetMayor = ElectionService.GetCurrentMayor(targetCityName)
	if targetMayor then
		local plr = Players:GetPlayerByUserId(targetMayor.userId)
		if plr then
			notifyPlayer(
				plr,
				string.format("🤝 Nova proposta de %s: %s (responda em 1 hora).", fromCity, dealType),
				"info"
			)
		end
	end

	printTag(string.format("ElectionService: Trade proposed %s → %s (%s) id=%s", fromCity, targetCityName, dealType, id))
	saveCityElectionState(fromCity)
	saveCityElectionState(targetCityName)
	return true, "Proposta enviada.", id
end

function ElectionService.RespondTrade(mayorPlayer: Player, dealId: string, accept: boolean): (boolean, string)
	if typeof(dealId) ~= "string" or #dealId == 0 then
		return false, "ID inválido."
	end
	local data = PlayerDataService.GetData(mayorPlayer)
	if not data or typeof(data.City) ~= "string" then
		return false, "Dados indisponíveis."
	end
	local myCity = data.City
	if not isValidCity(myCity) then
		return false, "Cidade inválida."
	end
	if not ElectionService.IsMayor(mayorPlayer, myCity) then
		return false, "Apenas o prefeito pode responder."
	end

	local st = ensureCityElectionState(myCity)
	local found: PendingIncomingTrade? = nil
	for _, p in st.pendingIncoming do
		if p.id == dealId then
			found = p
			break
		end
	end
	if not found then
		return false, "Proposta não encontrada ou expirada."
	end

	local fromCity = found.fromCity
	if not isValidCity(fromCity) then
		return false, "Cidade de origem inválida."
	end

	removePendingTradeBothSides(dealId, fromCity, myCity)

	if not accept then
		local proposer = Players:GetPlayerByUserId(found.proposerUserId)
		if proposer then
			notifyPlayer(proposer, string.format("❌ %s recusou o acordo (%s).", myCity, found.dealType), "info")
		end
		printTag(string.format("ElectionService: Trade REJECTED id=%s", dealId))
		saveCityElectionState(fromCity)
		saveCityElectionState(myCity)
		return true, "Proposta recusada."
	end

	local now = os.time()
	local bonusUntil = now + TRADE_BONUS_DURATION_SEC
	local dealA: ActiveTradeDeal = {
		id = dealId,
		partnerCity = myCity,
		dealType = found.dealType,
		bonusUntil = bonusUntil,
	}
	local dealB: ActiveTradeDeal = {
		id = dealId,
		partnerCity = fromCity,
		dealType = found.dealType,
		bonusUntil = bonusUntil,
	}
	appendActiveDeal(fromCity, dealB)
	appendActiveDeal(myCity, dealA)

	notifyCityPlayers(fromCity, string.format("🤝 Acordo aceito com %s: %s (bônus por 24h).", myCity, found.dealType), "success")
	notifyCityPlayers(myCity, string.format("🤝 Acordo aceito com %s: %s (bônus por 24h).", fromCity, found.dealType), "success")

	printTag(string.format("ElectionService: Trade ACCEPTED id=%s (%s ↔ %s)", dealId, fromCity, myCity))
	saveCityElectionState(fromCity)
	saveCityElectionState(myCity)
	return true, "Acordo aceito."
end

function ElectionService.GetActiveTrades(cityName: string): { ActiveTradeDeal }
	if not isValidCity(cityName) then
		return {}
	end
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local out: { ActiveTradeDeal } = {}
	for _, t in st.activeTrades do
		if t.bonusUntil > now then
			table.insert(out, table.clone(t))
		end
	end
	return out
end

function ElectionService.PlayerHasVoted(player: Player, cityName: string): boolean
	if not isValidCity(cityName) then
		return false
	end
	local st = ensureCityElectionState(cityName)
	return st.voters[player.UserId] == true
end

function ElectionService.SecondsUntilCurrentPhaseEnd(cityName: string): number
	return secondsUntilCurrentPhaseEnd(cityName)
end

--[[
	Studio / tests: align mandateEndTime with a phase without immediate overwrite.
]]
function ElectionService.ForceTestPhase(cityName: string, phase: string): boolean
	if not isValidCity(cityName) then
		return false
	end
	if phase ~= "mandate" and phase ~= "candidacy" and phase ~= "voting" and phase ~= "counting" then
		return false
	end
	local st = ensureCityElectionState(cityName)
	local now = os.time()
	local typedPhase = phase :: ElectionPhase
	if typedPhase == "mandate" then
		st.mandateEndTime = now + CANDIDACY_BEFORE_MANDATE_END + 120
	elseif typedPhase == "candidacy" then
		st.mandateEndTime = now + VOTING_BEFORE_MANDATE_END + 120
	elseif typedPhase == "voting" then
		st.mandateEndTime = now + 120
	elseif typedPhase == "counting" then
		st.mandateEndTime = now
	end
	st.phase = typedPhase
	saveCityElectionState(cityName)
	printTag(string.format("TEST ForceTestPhase: %q -> %s end=%d", cityName, phase, st.mandateEndTime))
	return true
end

local function start()
	initAllCities()

	CityService.OnCityAssignmentChanged(function(player: Player, oldCity: string?, _newCity: string)
		if oldCity and isValidCity(oldCity) then
			local st = electionByCity[oldCity]
			local vacatedSeat = false
			if st and st.currentMayor == player.UserId then
				st.currentMayor = nil
				st.currentMayorName = NO_MAYOR_LABEL
				saveCityElectionState(oldCity)
				vacatedSeat = true
			end
			local removedMayorRole = stripMayorFromPlayer(player.UserId, oldCity)
			if vacatedSeat then
				printTag(string.format("ElectionService: %s vacated Mayor seat in %s (moved city)", player.Name, oldCity))
			elseif removedMayorRole then
				printTag(string.format("ElectionService: cleared stale mayor state for %s in %s after city change", player.Name, oldCity))
			else
				printTag(string.format("ElectionService: no mayor cleanup needed for %s in %s after city change", player.Name, oldCity))
			end
		end
	end)

	PlayerDataService.OnDataLoaded(function(player: Player)
		syncMayorJobWithElectionState(player)
	end)

	task.spawn(function()
		while true do
			task.wait(PHASE_CHECK_INTERVAL_SEC)
			tickAllCities()
		end
	end)

	printTag("ElectionService initialized (persisted; phase check every " .. tostring(PHASE_CHECK_INTERVAL_SEC) .. "s)")
end

start()

return ElectionService
