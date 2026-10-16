local addonName, addon = ...
local ns = addon.SchiffeVersenken
local Comm = addon.Box.Comm
local Board = ns.Board

-- One game against another player, played over addon whispers. Each side only knows its own
-- ships and answers the other side's shots; at the end both fleets are revealed so a player
-- who lied about a shot gets caught.
--
-- Messages (space separated):
--   INV <protocol>   challenge                ACC / DEC / BUSY / VER <protocol>   answers to it
--   RDY 0|1          all ships placed (1: and got yours)   QUIT                  gave up / cancelled / no such game
--   SHOT x y         fire at x, y             RES x y M|H|S [sx sy length h width]  miss / hit / sunk (with the ship)
--   REV 0|1 <fleet>  whole fleet, sent by both sides when the game is over (1: and got yours)
--
-- Whispers get lost while a player reloads or sits in a loading screen, so RDY and SHOT are
-- resent until answered (REV for a while after the game), and getting the same message twice
-- changes nothing.
--
-- A test game (Game.test) is played the same way against the Training Dummy in TestGame.lua;
-- its messages go straight to the dummy instead of being whispered.
local Game = {}
ns.Game = Game

-- state: "idle", "inviting" (waiting for an answer), "placing", "playing" or "over"
Game.state = "idle"

local function SameName(a, b)
	return a and b and Ambiguate(a, "none"):lower() == Ambiguate(b, "none"):lower()
end

-- Through the box's message queue (Box/Comm.lua): moves in our game go first, answers to
-- anyone else wait their turn
local function Send(msg, target)
	local toOpponent = not target or SameName(target, Game.opponent)
	if Game.test and toOpponent then
		ns.Bot.Receive(msg)
		return
	end
	Comm.Send(ns.PREFIX, msg, target or Game.opponent, toOpponent and "high" or "normal")
end

local function Changed()
	if ns.Refresh then
		ns.Refresh()
	end
end

local function TurnStarted()
	if ns.OnTurnStart then
		ns.OnTurnStart()
	end
end

local function Reset(opponent)
	Game.opponent = opponent
	Game.myBoard = Board.New()
	Game.marks = {} -- my shots at the opponent: index -> "miss", "hit", "sunk" or "ship" (revealed)
	Game.enemySunk = 0
	Game.myReady, Game.theirReady = false, false
	Game.iStart = false -- whoever challenged fires first
	Game.myTurn = false
	Game.waiting = false -- { x, y } of a shot sent but not answered yet
	Game.result = nil -- "won", "lost" or "quit"
	Game.revealed = false
	Game.lastShotAtMe = nil -- cell index
	Game.log = nil -- what just happened, for the status line
	Game.offline = false -- our last whisper bounced
	Game.overAt = nil -- GetTime() when the game ended
	Game.test = false
	Game.fleet = ns.FLEET -- ship lengths to place
	Game.shipWidth = 1 -- of the ships to place; the test game's ship is 2 wide
	Game.enemyFleet = ns.FLEET -- what the opponent places; differs in a test game
end
Reset()

-- What gets saved over a /reload or logout to resume a running game
local SAVED_FIELDS = {
	"state", "opponent", "myBoard", "marks", "enemySunk", "myReady", "theirReady",
	"iStart", "myTurn", "waiting", "lastShotAtMe", "log",
}

function Game.InGame()
	return Game.state == "placing" or Game.state == "playing"
end

local function StartPlacing()
	Game.state = "placing"
	ns.ShowWindow()
	ns.Sound("READY_CHECK")
	Changed()
end

local function CheckStart()
	if Game.myReady and Game.theirReady then
		Game.state = "playing"
		Game.myTurn = Game.iStart
		Game.log = Game.iStart and "You fire first." or (ns.ShortName(Game.opponent) .. " fires first.")
		ns.Sound(ns.MyFaction() == ns.FACTIONS.Horde and "PVP_WARNING_HORDE" or "PVP_WARNING_ALLIANCE")
		if Game.myTurn then
			TurnStarted()
		end
	end
end

local function Finish(result)
	Game.state = "over"
	Game.result = result
	Game.myTurn = false
	Game.waiting = false
	Game.overAt = GetTime()
	if ns.OnGameOver then
		ns.OnGameOver(result)
	end
	if Game.test then
		ns.Print(result == "won" and "Test game won." or "Test game lost.")
		Send("REV 0 " .. Board.Encode(Game.myBoard))
		return
	end
	local stats = ns.stats
	if result == "won" then
		stats.wins = stats.wins + 1
		local faction = ns.MyFaction()
		ns.Print(ns.FactionText(faction, faction.victory) .. " You won against " .. ns.ShortName(Game.opponent) .. "!")
		pcall(PlaySound, faction.victorySound)
	else
		stats.losses = stats.losses + 1
		ns.Print("You lost against " .. ns.ShortName(Game.opponent) .. ".")
	end
	local versus = stats.opponents[ns.ShortName(Game.opponent)] or { wins = 0, losses = 0 }
	stats.opponents[ns.ShortName(Game.opponent)] = versus
	if result == "won" then
		versus.wins = versus.wins + 1
	else
		versus.losses = versus.losses + 1
	end
	Send("REV 0 " .. Board.Encode(Game.myBoard))
end

function Game.Invite(name)
	name = strtrim(name or ""):gsub("%s+", " ") -- names can have two parts, like "Ricarda Lang"
	if Game.InGame() then
		ns.Print("Finish or quit your current game first.")
		return
	elseif name == "" then
		ns.Print("Type a player name or target a player to challenge them.")
		return
	elseif SameName(name, UnitName("player")) then
		ns.Print("You can't challenge yourself.")
		return
	end
	Reset(name)
	Game.iStart = true
	Game.state = "inviting"
	Send("INV " .. ns.PROTOCOL)
	ns.Print("Challenge sent to " .. name .. ".")

	local token = {}
	Game.inviteToken = token
	C_Timer.After(ns.INVITE_TIMEOUT, function()
		if Game.state == "inviting" and Game.inviteToken == token then
			ns.Print(name .. " didn't answer.")
			Game.state = "idle"
			Changed()
		end
	end)
	Changed()
end

function Game.AcceptInvite(sender)
	if Game.InGame() then
		Send("BUSY", sender)
		return
	end
	Reset(sender)
	Send("ACC")
	StartPlacing()
end

function Game.DeclineInvite(sender)
	Send("DEC", sender)
end

function Game.SetReady()
	if Game.state ~= "placing" or Game.myReady then
		return
	elseif #Board.Unplaced(Game.myBoard, Game.fleet) > 0 then
		ns.Print("Place all your ships first.")
		return
	end
	Game.myReady = true
	Send("RDY 0")
	CheckStart()
	Changed()
end

-- Solo game against the Training Dummy, to try things out: each side has one 2x2 ship. You
-- place yours, the dummy's is always in the middle. Doesn't count for stats and isn't saved
-- over a reload.
function Game.StartTest()
	if Game.InGame() then
		ns.Print("Finish or quit your current game first.")
		return
	end
	Reset(ns.TEST_OPPONENT)
	Game.test = true
	Game.fleet = { ns.TEST_SHIP.length }
	Game.shipWidth = ns.TEST_SHIP.width
	Game.enemyFleet = { ns.TEST_SHIP.length }
	Game.iStart = true
	Game.theirReady = true -- the dummy is always ready
	ns.Bot.Start()
	Game.log = "Test game against the " .. ns.TEST_OPPONENT .. "."
	StartPlacing()
end

function Game.Shoot(x, y)
	if Game.state ~= "playing" or not Game.myTurn or Game.waiting or Game.marks[Board.Index(x, y)] then
		return
	end
	Game.waiting = { x, y }
	Send(("SHOT %d %d"):format(x, y))
	Changed()
end

function Game.Quit()
	if Game.state == "playing" then
		Send("QUIT")
		ns.Print("You gave up.")
		Finish("quit")
	elseif Game.state == "inviting" or Game.state == "placing" then
		Send("QUIT")
		Game.state = "idle"
	end
	Changed()
end

-- Incoming messages, by command. Each gets the sender and the message's words.
local handlers = {}

function handlers.INV(sender, protocol)
	if Game.InGame() then
		Send("BUSY", sender)
	elseif tonumber(protocol) ~= ns.PROTOCOL then
		Send("VER " .. ns.PROTOCOL, sender)
		ns.Print(ns.ShortName(sender) .. " challenged you, but one of you has an outdated version of the addon.")
	else
		ns.ShowInvite(sender)
	end
end

function handlers.ACC(sender)
	if Game.state == "inviting" and SameName(sender, Game.opponent) then
		Game.opponent = sender -- with realm, as the game sees it
		StartPlacing()
	elseif not (Game.InGame() and SameName(sender, Game.opponent)) then
		Send("QUIT", sender) -- the challenge expired or was cancelled
	end
end

local function InviteFailed(sender, text)
	if Game.state == "inviting" and SameName(sender, Game.opponent) then
		ns.Print(ns.ShortName(sender) .. " " .. text)
		Game.state = "idle"
		Changed()
	end
end

function handlers.DEC(sender)
	InviteFailed(sender, "declined.")
end

function handlers.BUSY(sender)
	InviteFailed(sender, "is already playing.")
end

function handlers.VER(sender)
	InviteFailed(sender, "has a different version of the addon. Both of you need the same one.")
end

function handlers.RDY(sender, gotMine)
	if Game.state == "inviting" then
		-- They accepted, but their ACC got lost
		Game.opponent = sender
		StartPlacing()
	end
	if Game.state == "placing" then
		if not Game.theirReady then
			Game.theirReady = true
			Game.log = ns.ShortName(sender) .. " is ready."
		end
		if Game.myReady and gotMine ~= "1" then
			Send("RDY 1")
		end
		CheckStart()
	elseif Game.state == "playing" and gotMine ~= "1" then
		Send("RDY 1") -- we started, they missed our RDY
	elseif Game.state == "idle" then
		Send("QUIT")
	end
	Changed()
end

function handlers.QUIT(sender)
	ns.HideInvite(sender)
	if not SameName(sender, Game.opponent) then
		return
	elseif Game.state == "playing" then
		ns.Print(ns.ShortName(sender) .. " gave up.")
		Finish("won")
	elseif Game.state == "inviting" or Game.state == "placing" then
		ns.Print(ns.ShortName(sender) .. " left the game.")
		Game.state = "idle"
	end
	Changed()
end

local function Answer(x, y, result, ship)
	if result == "miss" then
		Send(("RES %d %d M"):format(x, y))
	elseif result == "hit" then
		Send(("RES %d %d H"):format(x, y))
	else
		Send(("RES %d %d S %d %d %d %d %d"):format(x, y, ship.x, ship.y, ship.length, ship.horizontal and 1 or 0, ship.width))
	end
end

function handlers.SHOT(_, x, y)
	x, y = tonumber(x), tonumber(y)
	if not x or not y or not Board.InBounds(x, y) then
		return
	end
	local state = Game.state
	if (state == "playing" or state == "over") and Game.myBoard.shots[Board.Index(x, y)] then
		-- They're asking again, so our answer got lost. Answer the same, nothing else changes.
		Answer(x, y, Board.Shoot(Game.myBoard, x, y))
		if state == "over" and not Game.revealed then
			Send("REV 0 " .. Board.Encode(Game.myBoard))
		end
		return
	elseif state == "idle" or state == "over" then
		Send("QUIT") -- they still think the game is on
		return
	elseif state ~= "playing" or Game.myTurn then
		return
	end

	local result, ship = Board.Shoot(Game.myBoard, x, y)
	local cell = ns.CellName(x, y)
	local name = ns.ShortName(Game.opponent)
	Game.lastShotAtMe = Board.Index(x, y)
	Answer(x, y, result, ship)
	if result == "miss" then
		Game.log = name .. " fired at " .. cell .. " and missed."
		Game.myTurn = true
		TurnStarted()
	elseif result == "hit" then
		Game.log = name .. " hit your " .. ns.ShipName(ship.length, false, ship.width) .. " at " .. cell .. "."
		ns.Sound("IG_QUEST_LOG_ABANDON_QUEST")
	else
		Game.log = name .. " sank your " .. ns.ShipName(ship.length, false, ship.width) .. " at " .. cell .. "!"
		ns.Sound("IG_QUEST_LOG_ABANDON_QUEST")
		if Board.ShipsLeft(Game.myBoard) == 0 then
			Finish("lost")
		end
	end
	Changed()
end

function handlers.RES(_, x, y, code, sx, sy, length, horizontal, width)
	x, y = tonumber(x), tonumber(y)
	-- Only the answer to the shot we're waiting for; resent answers to older shots come in late
	local waiting = Game.waiting
	if Game.state ~= "playing" or not waiting or x ~= waiting[1] or y ~= waiting[2] then
		return
	end
	Game.waiting = false
	local cell = ns.CellName(x, y)
	if code == "M" then
		Game.marks[Board.Index(x, y)] = "miss"
		Game.myTurn = false
		Game.log = cell .. ": miss."
	elseif code == "H" then
		Game.marks[Board.Index(x, y)] = "hit"
		Game.log = cell .. ": hit! Fire again."
	elseif code == "S" then
		sx, sy, length, width = tonumber(sx), tonumber(sy), tonumber(length), tonumber(width) or 1
		if not sx or not sy or not length then
			return
		end
		horizontal = horizontal == "1"
		for _, shipCell in ipairs(Board.ShipCells(sx, sy, length, horizontal, width)) do
			if Board.InBounds(shipCell[1], shipCell[2]) then
				Game.marks[Board.Index(shipCell[1], shipCell[2])] = "sunk"
			end
		end
		Game.enemySunk = Game.enemySunk + 1
		Game.log = cell .. ": you sank their " .. ns.ShipName(length, true, width) .. "!"
		ns.Sound("RAID_WARNING")
		if Game.enemySunk >= #Game.enemyFleet then
			Finish("won")
		else
			Game.log = Game.log .. " Fire again."
		end
	end
	Changed()
end

function handlers.REV(sender, gotMine, fleet)
	if Game.state ~= "over" then
		return
	elseif gotMine ~= "1" then
		Send("REV 1 " .. Board.Encode(Game.myBoard))
	end
	if Game.revealed then
		return
	end
	Game.revealed = true
	local enemy, valid = Board.Decode(fleet, Game.enemyFleet)
	-- Every answer we got has to match where their ships really were
	for index, mark in pairs(Game.marks) do
		local onShip = enemy.cells[index] ~= nil
		if (mark == "miss") == onShip then
			valid = false
		end
	end
	for index in pairs(enemy.cells) do
		Game.marks[index] = Game.marks[index] or "ship"
	end
	if not valid then
		ns.Print("|cffff4040" .. ns.ShortName(sender) .. "'s fleet doesn't match their answers. They cheated!|r")
	end
	Changed()
end

-- Resend whatever the other side hasn't answered yet; only once a minute while they seem offline
local function Resend()
	if Game.opponent and not Game.test and not Comm.CanRetry(Game.opponent, ns.OFFLINE_RETRY) then
		return
	end
	if Game.state == "placing" and Game.myReady and not Game.theirReady then
		Send("RDY 0")
	elseif Game.state == "playing" and Game.waiting then
		Send(("SHOT %d %d"):format(Game.waiting[1], Game.waiting[2]))
	elseif Game.state == "over" and not Game.revealed and GetTime() - Game.overAt < ns.REVEAL_RESEND_TIME then
		Send("REV 0 " .. Board.Encode(Game.myBoard))
	end
end
C_Timer.NewTicker(ns.RESEND_INTERVAL, Resend)

-- The box notices when whispers to the opponent bounce (and hides the game's "No player named"
-- message); show it in the window instead
local function OnStatus(name, offline)
	if not Game.InGame() or not SameName(name, Game.opponent) or Game.offline == offline then
		return
	end
	Game.offline = offline
	if offline then
		Game.log = ns.ShortName(Game.opponent) .. " seems to be offline. The game goes on when they're back."
	else
		Game.log = ns.ShortName(Game.opponent) .. " is back."
	end
	Changed()
end

local function SaveGame()
	if not Game.InGame() or Game.test then
		SchiffeVersenkenGame = nil
		return
	end
	local saved = { time = time() }
	for _, field in ipairs(SAVED_FIELDS) do
		saved[field] = Game[field]
	end
	SchiffeVersenkenGame = saved
end

local function LoadGame()
	local saved = SchiffeVersenkenGame
	SchiffeVersenkenGame = nil
	if not saved or (saved.state ~= "placing" and saved.state ~= "playing")
		or time() - (saved.time or 0) > ns.RESUME_MINUTES * 60 then
		return false
	end
	Reset(saved.opponent)
	for _, field in ipairs(SAVED_FIELDS) do
		Game[field] = saved[field]
	end
	Resend()
	return true
end

-- Messages from someone we aren't playing against: challenges, and anyone who still thinks we are
local FROM_ANYONE = { INV = true, ACC = true, QUIT = true }
local NOT_PLAYING = { SHOT = true, RDY = true }

local resumed
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			SchiffeVersenkenStats = SchiffeVersenkenStats or {}
			ns.stats = SchiffeVersenkenStats
			ns.stats.wins = ns.stats.wins or 0
			ns.stats.losses = ns.stats.losses or 0
			ns.stats.opponents = ns.stats.opponents or {}
			resumed = LoadGame()
			events:UnregisterEvent("ADDON_LOADED")
		end
		return
	elseif event == "PLAYER_LOGOUT" then -- also fires on /reload
		SaveGame()
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Wait until here to show the window, so it knows our faction
		if resumed then
			resumed = false
			ns.Print("Resumed your game against " .. ns.ShortName(Game.opponent) .. ".")
			ns.ShowWindow()
		end
	end
end)

-- Handles one message from another player (or the Training Dummy)
function Game.Receive(msg, sender)
	local words = { strsplit(" ", msg) }
	local command = words[1]
	local handler = handlers[command]
	if not handler then
		return
	elseif SameName(sender, Game.opponent) then
		handler(sender, unpack(words, 2))
	elseif FROM_ANYONE[command] then
		handler(sender, unpack(words, 2))
	elseif NOT_PLAYING[command] then
		Send("QUIT", sender)
	end
end

Comm.Register(ns.PREFIX, Game.Receive, OnStatus)
