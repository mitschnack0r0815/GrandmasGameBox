local _, ns = ...

-- A board is one player's own sea: where their ships are and where the other player has shot.
-- Cells are numbered 1..SIZE*SIZE row by row (see Board.Index).
local Board = {}
ns.Board = Board

local SIZE = ns.SIZE

function Board.Index(x, y)
	return (y - 1) * SIZE + x
end

function Board.InBounds(x, y)
	return x >= 1 and x <= SIZE and y >= 1 and y <= SIZE
end

function Board.New()
	return {
		ships = {}, -- { x, y, length, horizontal, width, hits }; x, y is the top/left corner
		cells = {}, -- index -> ship index
		shots = {}, -- index -> true once the opponent fired there
	}
end

-- The cells a ship covers, as a list of { x, y }. Ships are one cell wide unless width says
-- otherwise (the test game's 2x2 block).
function Board.ShipCells(x, y, length, horizontal, width)
	local cells = {}
	for i = 0, length - 1 do
		for j = 0, (width or 1) - 1 do
			if horizontal then
				cells[#cells + 1] = { x + i, y + j }
			else
				cells[#cells + 1] = { x + j, y + i }
			end
		end
	end
	return cells
end

-- A ship fits if it stays on the board and doesn't overlap another ship. Ships may touch.
function Board.CanPlace(board, x, y, length, horizontal, width)
	if length < 1 or length > SIZE then
		return false
	end
	for _, cell in ipairs(Board.ShipCells(x, y, length, horizontal, width)) do
		if not Board.InBounds(cell[1], cell[2]) or board.cells[Board.Index(cell[1], cell[2])] then
			return false
		end
	end
	return true
end

local function Rebuild(board)
	wipe(board.cells)
	for i, ship in ipairs(board.ships) do
		for _, cell in ipairs(Board.ShipCells(ship.x, ship.y, ship.length, ship.horizontal, ship.width)) do
			board.cells[Board.Index(cell[1], cell[2])] = i
		end
	end
end

function Board.Place(board, x, y, length, horizontal, width)
	tinsert(board.ships, { x = x, y = y, length = length, horizontal = horizontal, width = width or 1, hits = 0 })
	Rebuild(board)
end

function Board.Remove(board, shipIndex)
	local ship = tremove(board.ships, shipIndex)
	Rebuild(board)
	return ship
end

function Board.Clear(board)
	wipe(board.ships)
	wipe(board.cells)
end

-- Ship lengths of the fleet (a list of lengths, longest first) not on the board yet
function Board.Unplaced(board, fleet)
	local placed = {}
	for _, ship in ipairs(board.ships) do
		placed[ship.length] = (placed[ship.length] or 0) + 1
	end
	local missing = {}
	for _, length in ipairs(fleet) do
		if (placed[length] or 0) > 0 then
			placed[length] = placed[length] - 1
		else
			missing[#missing + 1] = length
		end
	end
	return missing
end

-- Throws the whole fleet on the board at random; starts over if a ship doesn't fit anywhere
function Board.Randomize(board, fleet, width)
	local done
	repeat
		Board.Clear(board)
		done = true
		for _, length in ipairs(fleet) do
			local placed = false
			for _ = 1, 200 do
				local x, y, horizontal = math.random(SIZE), math.random(SIZE), math.random(2) == 1
				if Board.CanPlace(board, x, y, length, horizontal, width) then
					Board.Place(board, x, y, length, horizontal, width)
					placed = true
					break
				end
			end
			if not placed then
				done = false
				break
			end
		end
	until done
end

function Board.IsSunk(ship)
	return ship.hits >= ship.length * (ship.width or 1)
end

-- The opponent fires at x, y. Returns "miss", "hit" or "sunk" plus the ship.
-- Firing at the same cell twice answers the same again without counting another hit.
function Board.Shoot(board, x, y)
	local index = Board.Index(x, y)
	local ship = board.ships[board.cells[index] or 0]
	if not board.shots[index] then
		board.shots[index] = true
		if ship then
			ship.hits = ship.hits + 1
		end
	end
	if not ship then
		return "miss"
	end
	return Board.IsSunk(ship) and "sunk" or "hit", ship
end

function Board.ShipsLeft(board)
	local left = 0
	for _, ship in ipairs(board.ships) do
		if not Board.IsSunk(ship) then
			left = left + 1
		end
	end
	return left
end

-- "x,y,length,h,width;..." to show the opponent the whole fleet once the game is over
function Board.Encode(board)
	local parts = {}
	for _, ship in ipairs(board.ships) do
		parts[#parts + 1] = ("%d,%d,%d,%d,%d"):format(ship.x, ship.y, ship.length, ship.horizontal and 1 or 0, ship.width or 1)
	end
	return table.concat(parts, ";")
end

-- Builds a board from Board.Encode's text. The second result is false if it isn't the
-- expected fleet or ships overlap.
function Board.Decode(text, fleet)
	local board = Board.New()
	local valid = true
	for xText, yText, lengthText, h, widthText in (text or ""):gmatch("(%d+),(%d+),(%d+),([01]),(%d+)") do
		local x, y, length, width = tonumber(xText), tonumber(yText), tonumber(lengthText), tonumber(widthText)
		if Board.CanPlace(board, x, y, length, h == "1", width) then
			Board.Place(board, x, y, length, h == "1", width)
		else
			valid = false
		end
	end
	if #board.ships ~= #fleet or #Board.Unplaced(board, fleet) > 0 then
		valid = false
	end
	return board, valid
end
