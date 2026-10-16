local _, addon = ...
local ns = addon.SchiffeVersenken
local Board = ns.Board
local Game = ns.Game

-- The Training Dummy, opponent of the test game. It speaks the same messages as a real player,
-- so a test game runs through the real game code; only the whispers are skipped. Its ship is
-- always the 2x2 block from ns.TEST_SHIP. It fires at random, and around its hits.
local Bot = {}
ns.Bot = Bot

local ANSWER_DELAY = 0.4 -- seconds before it answers your shot
local SHOT_DELAY = 1 -- seconds before it fires

local board -- the dummy's own sea
local fired -- cells it has fired at: index -> "miss", "hit" or "sunk"
local session -- changes with every test game, so replies from an old one are dropped

local function Reply(msg, delay)
	local current = session
	C_Timer.After(delay, function()
		if session == current and Game.test then
			Game.Receive(msg, ns.TEST_OPPONENT)
		end
	end)
end

-- Next cell to fire at: next to an earlier hit if there is one, otherwise anywhere new
local function PickTarget()
	local near, anywhere = {}, {}
	for y = 1, ns.SIZE do
		for x = 1, ns.SIZE do
			local index = Board.Index(x, y)
			if not fired[index] then
				anywhere[#anywhere + 1] = { x, y }
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local nx, ny = x + d[1], y + d[2]
					if Board.InBounds(nx, ny) and fired[Board.Index(nx, ny)] == "hit" then
						near[#near + 1] = { x, y }
						break
					end
				end
			end
		end
	end
	local options = #near > 0 and near or anywhere
	return options[math.random(#options)]
end

local function Fire()
	if Game.state ~= "playing" then
		return
	end
	local target = PickTarget()
	if target then
		fired[Board.Index(target[1], target[2])] = "pending"
		Reply(("SHOT %d %d"):format(target[1], target[2]), SHOT_DELAY)
	end
end

local handlers = {}

-- You fired at the dummy
function handlers.SHOT(x, y)
	x, y = tonumber(x), tonumber(y)
	if not x or not y or not Board.InBounds(x, y) then
		return
	end
	local repeated = board.shots[Board.Index(x, y)]
	local result, ship = Board.Shoot(board, x, y)
	if result == "miss" then
		Reply(("RES %d %d M"):format(x, y), ANSWER_DELAY)
		if not repeated then
			Fire() -- your miss, its turn
		end
	elseif result == "hit" then
		Reply(("RES %d %d H"):format(x, y), ANSWER_DELAY)
	else
		Reply(("RES %d %d S %d %d %d %d %d"):format(x, y, ship.x, ship.y, ship.length,
			ship.horizontal and 1 or 0, ship.width), ANSWER_DELAY)
	end
end

-- Your answer to the dummy's shot
function handlers.RES(x, y, code, sx, sy, length, horizontal, width)
	x, y = tonumber(x), tonumber(y)
	if not x or not y or fired[Board.Index(x, y)] ~= "pending" then
		return
	end
	if code == "M" then
		fired[Board.Index(x, y)] = "miss"
		return -- your turn
	elseif code == "H" then
		fired[Board.Index(x, y)] = "hit"
	elseif code == "S" then
		-- Stop aiming around a ship that's gone
		for _, cell in ipairs(Board.ShipCells(tonumber(sx), tonumber(sy), tonumber(length), horizontal == "1", tonumber(width))) do
			fired[Board.Index(cell[1], cell[2])] = "sunk"
		end
	end
	Fire() -- hit, fire again (does nothing once the game is over)
end

-- Game over: show its ship when asked
function handlers.REV(gotMine)
	if gotMine ~= "1" then
		Reply("REV 1 " .. Board.Encode(board), ANSWER_DELAY)
	end
end

function Bot.Start()
	session = {}
	fired = {}
	board = Board.New()
	local ship = ns.TEST_SHIP
	Board.Place(board, ship.x, ship.y, ship.length, ship.horizontal, ship.width)
end

-- Gets every message the game sends to the dummy
function Bot.Receive(msg)
	local words = { strsplit(" ", msg) }
	local handler = handlers[words[1]]
	if handler and board then
		handler(unpack(words, 2))
	end
end
