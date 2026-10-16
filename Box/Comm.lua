local _, ns = ...
local Box = ns.Box

-- Every addon message of the box goes through here. Games only whisper single players, and
-- this keeps that cheap and safe:
--   * One queue for all games, sent at a steady pace (a small burst, then RATE per second),
--     so bursts like syncing every quiz duel on login never hit the game's addon message
--     throttle. "high" messages (moves in a running game) go ahead of "normal" ones.
--   * The same message to the same player is only queued once, and only PER_TARGET messages
--     per player wait at a time, so resends can't pile up and nobody can make us flood
--     replies by spamming us.
--   * If the game still says we're sending too much, the message goes back in front and the
--     queue pauses.
--   * Whispers to an offline player bounce with "No player named ... is currently playing."
--     That message is hidden, the player counts as offline, and what's still queued for them
--     is dropped. Games ask CanRetry before resending, so offline players are only tried every
--     now and then. A player counts as back once they message us or a whisper doesn't bounce.
local Comm = {}
Box.Comm = Comm

local SendAddonMessage = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
local RegisterPrefix = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle

local BURST = 4 -- messages that can go out at once
local RATE = 1 -- messages per second after that, for all games together
local PER_TARGET = 6 -- messages waiting per player at most; more are dropped
local THROTTLE_PAUSE = 3 -- seconds to wait when the game throttles us anyway
local BOUNCE_TIME = 10 -- seconds after a whisper in which "No player named" counts as its bounce
local PROBE_TIME = 5 -- seconds without a bounce after which an offline player counts as back
local MAX_LENGTH = 255 -- the game's limit for an addon message

local games = {} -- prefix -> { receive = function(msg, sender), status = function(name, offline) }
local queues = { high = {}, normal = {} }
local tokens = BURST
local pausedUntil = 0
local lastSent = {} -- player key -> GetTime() of our last whisper to them
local offlineAt = {} -- player key -> GetTime() of their last bounce

local function Key(name)
	return Ambiguate(name, "none"):lower()
end

-- Tells every game a player went offline or came back
local function Status(name, offline)
	for _, game in pairs(games) do
		if game.status then
			game.status(name, offline)
		end
	end
end

local function SetOnline(key, name)
	if offlineAt[key] then
		offlineAt[key] = nil
		Status(name, false)
	end
end

local function Queued(key)
	local count = 0
	for _, queue in pairs(queues) do
		for _, entry in ipairs(queue) do
			if entry.key == key then
				count = count + 1
			end
		end
	end
	return count
end

local function DropQueued(key)
	for _, queue in pairs(queues) do
		for i = #queue, 1, -1 do
			if queue[i].key == key then
				tremove(queue, i)
			end
		end
	end
end

local pump = CreateFrame("Frame")
pump:Hide() -- only runs while something waits

local function Transmit(entry)
	local result = SendAddonMessage(entry.prefix, entry.msg, "WHISPER", entry.target)
	if THROTTLED and result == THROTTLED then
		return false
	end
	local now = GetTime()
	lastSent[entry.key] = now
	if offlineAt[entry.key] then
		-- Trying an offline player again: if this doesn't bounce, they're back
		C_Timer.After(PROBE_TIME, function()
			if offlineAt[entry.key] and offlineAt[entry.key] < now then
				SetOnline(entry.key, entry.target)
			end
		end)
	end
	return true
end

pump:SetScript("OnUpdate", function(self, elapsed)
	tokens = math.min(BURST, tokens + elapsed * RATE)
	if GetTime() < pausedUntil then
		return
	end
	while tokens >= 1 do
		local queue = #queues.high > 0 and queues.high or queues.normal
		local entry = queue[1]
		if not entry then
			self:Hide()
			return
		end
		if not Transmit(entry) then
			pausedUntil = GetTime() + THROTTLE_PAUSE
			return -- stays first in line
		end
		tremove(queue, 1)
		tokens = tokens - 1
	end
end)

-- Starts listening for a game's messages. receive(msg, sender) gets whispers with this
-- prefix; status(name, offline), if given, hears when a player goes offline or comes back.
function Comm.Register(prefix, receive, status)
	RegisterPrefix(prefix)
	games[prefix] = { receive = receive, status = status }
end

-- Whispers msg to target as soon as the pace allows. priority: "high" for moves in a running
-- game, otherwise "normal".
function Comm.Send(prefix, msg, target, priority)
	if not target or target == "" or #msg > MAX_LENGTH then
		return
	end
	local key = Key(target)
	local queue = priority == "high" and queues.high or queues.normal
	for _, other in pairs(queues) do
		for _, entry in ipairs(other) do
			if entry.key == key and entry.prefix == prefix and entry.msg == msg then
				return -- already waiting
			end
		end
	end
	if Queued(key) >= PER_TARGET then
		return
	end
	queue[#queue + 1] = { prefix = prefix, msg = msg, target = target, key = key }
	pump:Show()
end

function Comm.IsOffline(name)
	return name and offlineAt[Key(name)] ~= nil
end

-- Whether to resend to this player now: always while they're online, but only every
-- offlineInterval seconds while they seem offline
function Comm.CanRetry(name, offlineInterval)
	local key = Key(name)
	return not offlineAt[key] or GetTime() - (lastSent[key] or 0) >= offlineInterval
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
	local game = games[prefix]
	if not game or channel ~= "WHISPER" or not sender or #msg > MAX_LENGTH then
		return
	end
	SetOnline(Key(sender), sender) -- anything from them means they're online
	game.receive(msg, sender)
end)

local notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%.%-%(%)%[%]%+%*%?%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
	local name = msg:match(notFoundPattern)
	if not name then
		return
	end
	name = name:gsub("^'(.*)'$", "%1")
	local key = Key(name)
	if not lastSent[key] or GetTime() - lastSent[key] > BOUNCE_TIME then
		return -- not about one of our whispers
	end
	DropQueued(key) -- they'd bounce too
	local wasOffline = offlineAt[key]
	offlineAt[key] = GetTime()
	if not wasOffline then
		Status(name, true)
	end
	return true
end)
