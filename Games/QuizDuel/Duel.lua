local addonName, addon = ...
local ns = addon.QuizDuel

-- Duels: 6 rounds of 3 questions. Each round one player picks the category and answers first;
-- the other answers the same questions afterwards. The challenger picks the odd rounds. A turn
-- is everything one player does before it's the other's go: answer the opponent's round, then
-- pick and answer the next one.
--
-- Turns don't need both players online. A finished turn is whispered to the opponent and resent
-- until they confirm it; when either player logs in, both sides compare how many turns they
-- have and fill in what's missing. Duels are saved per character (QuizDuelDuels).
--
-- Messages (space separated), all about one duel <id>:
--   TURN id k protocol rounds   turn number k: "r:category:q1,q2,q3:answers;..." where
--                               category and questions are only there for a round the sender
--                               picked; answers are a digit per question, 1-4 the answer picked
--                               in Questions.lua order (1 is right), 0 out of time
--   SYNC id n                   I have n turns (sent on login and to confirm a TURN)
--   QUIT id / QOK id            gave up / got it
--   VER id protocol             we can't play: different protocol or questions
--
-- A test duel (duel.test) is played against the Training Dummy at the bottom of this file:
-- its messages go to the dummy instead of being whispered, and it doesn't count for stats.
local Duel = {}
ns.Duel = Duel

local SendAddonMessage = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
local RegisterPrefix = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
RegisterPrefix(ns.PREFIX)

local duels = {} -- id -> duel, replaced by the saved ones on load
local lastSent = {} -- lowercase short name -> GetTime() of our last whisper, for the offline filter

local function Changed()
	if ns.Refresh then
		ns.Refresh()
	end
end

local BotReceive -- the Training Dummy, at the bottom

local function Send(duel, msg)
	if duel.test then
		BotReceive(duel, msg)
		return
	end
	lastSent[ns.ShortName(duel.opponent):lower()] = GetTime()
	SendAddonMessage(ns.PREFIX, msg, "WHISPER", duel.opponent)
end

-- Picks the odd rounds if you challenged, the even ones otherwise
function Duel.IPick(duel, r)
	return (r % 2 == 1) == duel.iStarted
end

-- What the duel waits for: "pick" or "answer" (you, round r), "wait" (the opponent) or "over"
function Duel.NextAction(duel)
	if duel.result then
		return "over"
	end
	for r = 1, ns.ROUNDS do
		local round = duel.rounds[r]
		if not round then
			return Duel.IPick(duel, r) and "pick" or "wait", r
		elseif not round.mine then
			return "answer", r
		elseif not round.theirs then
			return "wait", r
		end
	end
	return "over"
end

function Duel.MyTurn(duel)
	local action = Duel.NextAction(duel)
	return action == "pick" or action == "answer"
end

local function Correct(answers)
	local count = 0
	for digit in (answers or ""):gmatch("1") do
		count = count + 1
	end
	return count
end

-- Points so far. The opponent's answers only count once you've played that round yourself.
function Duel.Score(duel)
	local mine, theirs = 0, 0
	for r = 1, ns.ROUNDS do
		local round = duel.rounds[r]
		if round and round.mine then
			mine = mine + Correct(round.mine)
			theirs = theirs + Correct(round.theirs)
		end
	end
	return mine, theirs
end

function Duel.List()
	local list = {}
	for _, duel in pairs(duels) do
		list[#list + 1] = duel
	end
	return list
end

function Duel.Get(id)
	return duels[id]
end

function Duel.ActiveAgainst(name)
	for _, duel in pairs(duels) do
		if not duel.result and ns.SameName(duel.opponent, name) then
			return duel
		end
	end
end

-- Stats and the finished duels list

local function Count(result, versus)
	local key = result == "won" and "wins" or result == "draw" and "draws" or "losses"
	versus[key] = (versus[key] or 0) + 1
end

local function Prune()
	local finished = {}
	for _, duel in pairs(duels) do
		if duel.result and not duel.quitPending then
			finished[#finished + 1] = duel
		end
	end
	table.sort(finished, function(a, b)
		return a.updated > b.updated
	end)
	for i = ns.KEEP_FINISHED + 1, #finished do
		duels[finished[i].id] = nil
	end
end

local function Finish(duel, result, how)
	duel.result = result
	duel.endedBy = how -- nil (all rounds played), "quit" (you gave up) or "theyQuit"
	duel.updated = time()
	local name = ns.ShortName(duel.opponent)
	if not duel.test then
		local stats = ns.stats
		Count(result, stats)
		stats.opponents[name] = stats.opponents[name] or {}
		Count(result, stats.opponents[name])
	end
	if result == "won" then
		ns.Print("You won the duel against " .. name .. "!")
	elseif result == "draw" then
		ns.Print("Your duel against " .. name .. " ended in a draw.")
	else
		ns.Print("You lost the duel against " .. name .. ".")
	end
	if ns.OnDuelOver then
		ns.OnDuelOver(duel)
	end
	Prune()
end

local function CheckFinished(duel)
	if not duel.result and Duel.NextAction(duel) == "over" then
		local mine, theirs = Duel.Score(duel)
		Finish(duel, mine > theirs and "won" or mine < theirs and "lost" or "draw")
	end
end

-- Sending turns

local function SendTurn(duel, k)
	local entry = duel.log[k]
	if entry and entry.mine then
		Send(duel, ("TURN %s %d %d %s"):format(duel.id, k, ns.PROTOCOL, entry.payload))
	end
end

local function SendPending(duel)
	if duel.offlineAt and GetTime() - duel.offlineAt < ns.OFFLINE_RETRY then
		return
	end
	if duel.quitPending then
		Send(duel, "QUIT " .. duel.id)
	end
	for k = (duel.peerTurns or 0) + 1, #duel.log do
		SendTurn(duel, k)
	end
end

-- Your turn is over: everything you answered since your last turn goes out as one turn
local function EndTurn(duel)
	local parts = {}
	for r = 1, ns.ROUNDS do
		local round = duel.rounds[r]
		if round and round.mine and not round.sent then
			round.sent = true
			if round.mine and round.picker == "me" then
				parts[#parts + 1] = ("%d:%s:%s:%s"):format(r, round.category, table.concat(round.questions, ","), round.mine)
			else
				parts[#parts + 1] = ("%d:::%s"):format(r, round.mine)
			end
		end
	end
	if #parts == 0 then
		return
	end
	duel.log[#duel.log + 1] = { mine = true, payload = table.concat(parts, ";") }
	duel.updated = time()
	duel.offlineAt = nil
	SendTurn(duel, #duel.log)
	CheckFinished(duel)
end

-- Your moves

function Duel.Challenge(name)
	name = strtrim(name or ""):gsub("%s+", " ")
	if name == "" then
		ns.Print("Type a player name or target a player to challenge them.")
		return
	elseif ns.SameName(name, UnitName("player")) then
		ns.Print("You can't challenge yourself.")
		return
	end
	local active = Duel.ActiveAgainst(name)
	if active then
		ns.Print("You already have a duel running against " .. ns.ShortName(name) .. ".")
		return active
	end
	local id = ("%x%04x"):format(time(), math.random(0, 65535))
	local duel = {
		id = id, opponent = name, iStarted = true, created = time(), updated = time(),
		rounds = {}, log = {}, offers = {}, peerTurns = 0,
		test = name == ns.TEST_OPPONENT or nil, -- no real player has a space in their name
	}
	duels[id] = duel
	Changed()
	return duel
end

-- The categories offered for round r; the same ones until you pick, even after a reload
function Duel.Offer(duel, r)
	if not duel.offers[r] then
		local keys = {}
		for _, category in ipairs(ns.CATEGORIES) do
			keys[#keys + 1] = category.key
		end
		local offer = {}
		for _ = 1, math.min(ns.CATEGORY_CHOICES, #keys) do
			offer[#offer + 1] = tremove(keys, math.random(#keys))
		end
		duel.offers[r] = offer
	end
	return duel.offers[r]
end

-- Question ids for a new round: ones not had in this duel yet; repeats only if the category
-- runs out
local function ChooseQuestions(duel, categoryKey)
	local used = {}
	for _, other in pairs(duel.rounds) do
		for _, id in ipairs(other.questions) do
			used[id] = true
		end
	end
	local fresh, all = {}, {}
	for _, question in ipairs(ns.CATEGORY[categoryKey].questions) do
		all[#all + 1] = question.id
		if not used[question.id] then
			fresh[#fresh + 1] = question.id
		end
	end
	local pool = #fresh >= ns.QUESTIONS_PER_ROUND and fresh or all
	local questions = {}
	for _ = 1, ns.QUESTIONS_PER_ROUND do
		questions[#questions + 1] = tremove(pool, math.random(#pool))
	end
	return questions
end

function Duel.Pick(duel, r, categoryKey)
	local action, round = Duel.NextAction(duel)
	if action ~= "pick" or round ~= r then
		return
	end
	duel.rounds[r] = { category = categoryKey, questions = ChooseQuestions(duel, categoryKey), picker = "me" }
	duel.offers[r] = nil
	duel.updated = time()
	Changed()
end

-- Your answer to the next question of round r: 1-4 in Questions.lua order (1 is right), 0 if
-- time ran out. Returns true if it was right.
function Duel.Answer(duel, r, choice)
	local action, round = Duel.NextAction(duel)
	if action ~= "answer" or round ~= r then
		return
	end
	local current = duel.rounds[r]
	current.progress = (current.progress or "") .. choice
	if #current.progress >= #current.questions then
		current.mine = current.progress
		current.progress = nil
		local next = Duel.NextAction(duel)
		if next == "wait" or next == "over" then
			EndTurn(duel)
		end
	end
	duel.updated = time()
	Changed()
	return choice == 1
end

function Duel.GiveUp(duel)
	if duel.result then
		return
	end
	if #duel.log == 0 and duel.iStarted then
		duels[duel.id] = nil -- nothing sent yet, so the opponent doesn't know about it
		Changed()
		return
	end
	duel.quitPending = true
	Finish(duel, "lost", "quit")
	SendPending(duel)
	Changed()
end

-- Removes a finished duel from the list
function Duel.Remove(duel)
	if duel.result and not duel.quitPending then
		duels[duel.id] = nil
		Changed()
	end
end

-- Incoming messages

local handlers = {}

local function Sync(duel)
	Send(duel, ("SYNC %s %d"):format(duel.id, #duel.log))
end

-- Unpacks "r:category:q1,q2,q3:answers;...". Returns nil if anything is off, like question
-- ids we don't know (the other side has different questions).
local function ParseRounds(payload)
	local rounds = {}
	for part in (payload or ""):gmatch("[^;]+") do
		local r, category, questions, answers = part:match("^(%d+):([^:]*):([^:]*):([0-4]+)$")
		r = tonumber(r)
		if not r or r < 1 or r > ns.ROUNDS then
			return
		end
		local round = { r = r, answers = answers }
		if category ~= "" then
			if not ns.CATEGORY[category] then
				return
			end
			round.category = category
			round.questions = {}
			for id in questions:gmatch("[^,]+") do
				if not ns.QUESTION[id] then
					return
				end
				round.questions[#round.questions + 1] = id
			end
			if #round.questions ~= #answers then
				return
			end
		end
		rounds[#rounds + 1] = round
	end
	return #rounds > 0 and rounds or nil
end

local function VersionMismatch(sender, id)
	SendAddonMessage(ns.PREFIX, ("VER %s %d"):format(id, ns.PROTOCOL), "WHISPER", sender)
	ns.Print(ns.ShortName(sender) .. " sent a duel, but one of you has an outdated version of the addon.")
end

function handlers.TURN(sender, id, k, protocol, payload)
	k = tonumber(k)
	if not id or not k then
		return
	elseif tonumber(protocol) ~= ns.PROTOCOL then
		VersionMismatch(sender, id)
		return
	end
	local duel = duels[id]
	if not duel then
		if k ~= 1 then
			SendAddonMessage(ns.PREFIX, "QUIT " .. id, "WHISPER", sender) -- we don't have it any more
			return
		end
		duel = {
			id = id, opponent = sender, iStarted = false, created = time(), updated = time(),
			rounds = {}, log = {}, offers = {}, peerTurns = 0, new = true,
		}
	elseif not ns.SameName(sender, duel.opponent) then
		return
	end
	if k ~= #duel.log + 1 then
		Sync(duel) -- a turn we have already, or one after a turn we missed
		return
	end
	local rounds = ParseRounds(payload)
	if not rounds then
		VersionMismatch(sender, id)
		return
	end
	for _, received in ipairs(rounds) do
		local round = duel.rounds[received.r]
		if not round then
			if not received.category then
				return -- answers to a round we never picked; ignore the whole turn
			end
			round = { category = received.category, questions = received.questions, picker = "them" }
			duel.rounds[received.r] = round
		end
		round.theirs = received.answers
	end
	duels[id] = duel
	duel.opponent = sender -- with realm, as the game sees it
	duel.log[k] = { payload = payload }
	duel.peerTurns = k
	duel.updated = time()
	Sync(duel)
	CheckFinished(duel)
	if not duel.result then
		if duel.new then
			duel.new = nil
			ns.Print(ns.ShortName(sender) .. " challenged you to a duel! Open it with /quiz.")
		else
			ns.Print(ns.ShortName(sender) .. " played their turn. Your turn!")
		end
		ns.Sound("READY_CHECK")
		if FlashClientIcon then
			FlashClientIcon()
		end
	end
	Changed()
end

function handlers.SYNC(sender, id, n)
	n = tonumber(n)
	local duel = duels[id]
	if not n then
		return
	elseif not duel then
		if n > 0 then
			SendAddonMessage(ns.PREFIX, "QUIT " .. id, "WHISPER", sender)
		end
		return
	elseif not ns.SameName(sender, duel.opponent) then
		return
	end
	duel.peerTurns = math.max(duel.peerTurns or 0, math.min(n, #duel.log))
	if n < #duel.log then
		SendPending(duel)
	elseif n > #duel.log then
		Sync(duel) -- they have a turn we missed; this makes them resend it
	end
	if duel.quitPending then
		SendPending(duel)
	end
end

function handlers.QUIT(sender, id)
	local duel = duels[id]
	SendAddonMessage(ns.PREFIX, "QOK " .. (id or ""), "WHISPER", sender)
	if duel and not duel.result and ns.SameName(sender, duel.opponent) then
		ns.Print(ns.ShortName(sender) .. " gave up.")
		Finish(duel, "won", "theyQuit")
		Changed()
	end
end

function handlers.QOK(sender, id)
	local duel = duels[id]
	if duel and ns.SameName(sender, duel.opponent) then
		duel.quitPending = nil
		Prune()
	end
end

function handlers.VER(sender, id)
	local duel = duels[id]
	if duel and not duel.versionWarned then
		duel.versionWarned = true
		ns.Print(ns.ShortName(sender) .. " has a different version of the addon. Both of you need the same one to play.")
	end
end

-- Resend what the opponent hasn't confirmed; less often while they seem offline
C_Timer.NewTicker(ns.RESEND_INTERVAL, function()
	for _, duel in pairs(duels) do
		SendPending(duel)
	end
end)

-- Whispering a player who is offline makes the game print "No player named ... is currently
-- playing." Hide that for our own messages and wait a while before trying them again.
local notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%.%-%(%)%[%]%+%*%?%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
	local name = msg:match(notFoundPattern)
	if not name then
		return
	end
	name = ns.ShortName(name:gsub("^'(.*)'$", "%1")):lower()
	if lastSent[name] and GetTime() - lastSent[name] < 10 then
		for _, duel in pairs(duels) do
			if ns.ShortName(duel.opponent):lower() == name then
				duel.offlineAt = GetTime()
			end
		end
		return true
	end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			QuizDuelStats = QuizDuelStats or {}
			ns.stats = QuizDuelStats
			ns.stats.wins = ns.stats.wins or 0
			ns.stats.losses = ns.stats.losses or 0
			ns.stats.draws = ns.stats.draws or 0
			ns.stats.opponents = ns.stats.opponents or {}
			QuizDuelDuels = QuizDuelDuels or {}
			duels = QuizDuelDuels
			for _, duel in pairs(duels) do
				duel.offlineAt = nil -- a GetTime() from an earlier session
			end
			events:UnregisterEvent("ADDON_LOADED")
		end
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Once per session: tell every opponent how far we are, so missed turns get filled in
		events:UnregisterEvent("PLAYER_ENTERING_WORLD")
		Duel.ResumeBots()
		C_Timer.After(5, function()
			for _, duel in pairs(duels) do
				if (not duel.result or duel.quitPending or (duel.peerTurns or 0) < #duel.log) and #duel.log > 0 then
					Sync(duel)
				end
			end
			Changed()
		end)
		return
	end

	local prefix, msg, channel, sender = ...
	if prefix ~= ns.PREFIX or channel ~= "WHISPER" then
		return
	end
	local words = { strsplit(" ", msg) }
	local handler = handlers[words[1]]
	if handler then
		-- Anything from them means they're online
		for _, duel in pairs(duels) do
			if ns.SameName(duel.opponent, sender) then
				duel.offlineAt = nil
			end
		end
		handler(sender, unpack(words, 2))
	end
end)

-- The Training Dummy ---------------------------------------------------------------------------

-- Plays its turn like a player would: answers your last round, then picks a category and
-- answers the next one. It gets about half its answers right.
local BOT_DELAY = 2 -- seconds it "thinks" before its turn arrives

local function BotAnswers(count)
	local answers = ""
	for _ = 1, count do
		local roll = math.random()
		answers = answers .. (roll < 0.5 and 1 or roll < 0.95 and math.random(2, 4) or 0)
	end
	return answers
end

local function BotTurn(duel)
	if duels[duel.id] ~= duel or duel.result or Duel.NextAction(duel) ~= "wait" then
		return
	end
	local parts = {}
	for r = 1, ns.ROUNDS do
		local round = duel.rounds[r]
		if round and round.mine and not round.theirs then
			parts[#parts + 1] = ("%d:::%s"):format(r, BotAnswers(#round.questions))
		elseif not round then
			if not Duel.IPick(duel, r) then
				local categories = ns.CATEGORIES
				local key = categories[math.random(#categories)].key
				local questions = ChooseQuestions(duel, key)
				parts[#parts + 1] = ("%d:%s:%s:%s"):format(r, key, table.concat(questions, ","), BotAnswers(#questions))
			end
			break
		end
	end
	if #parts > 0 then
		handlers.TURN(ns.TEST_OPPONENT, duel.id, #duel.log + 1, ns.PROTOCOL, table.concat(parts, ";"))
	end
end

function BotReceive(duel, msg)
	local command = msg:match("^(%S+)")
	if command == "TURN" then
		duel.peerTurns = #duel.log -- the dummy always gets it
		C_Timer.After(BOT_DELAY, function()
			BotTurn(duel)
		end)
	elseif command == "QUIT" then
		duel.quitPending = nil
		Prune()
	end
end

-- After a reload, a turn the dummy owed you is still to come
function Duel.ResumeBots()
	for _, duel in pairs(duels) do
		if duel.test and not duel.result and Duel.NextAction(duel) == "wait" then
			C_Timer.After(BOT_DELAY, function()
				BotTurn(duel)
			end)
		end
	end
end
