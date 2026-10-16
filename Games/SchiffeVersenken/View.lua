local _, addon = ...
local ns = addon.SchiffeVersenken
local Box = addon.Box
local Board = ns.Board
local Game = ns.Game

-- The game's page in the box: your fleet on the left, the enemy waters you fire at on the right.
-- Compact layout (for small screens) is narrow and vertical: your fleet as a small map at the
-- top with the game status next to it, the enemy waters full size below. While placing ships
-- your fleet is the big grid and the placing buttons take the small map's spot.
local SIZE = ns.SIZE
local CELL = 24
local SMALL_CELL = 12
local GAP = 2

-- Squares look like empty action bar slots. Clients with the newer action bar art have atlases
-- for the slot (dark, with the faint wing pattern), its frame and mouseover; older ones get the
-- classic slot textures, drawn 66px around a 36px button, which SLOT_SCALE keeps.
local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
local MODERN_SLOTS = HasAtlas("UI-HUD-ActionBar-IconFrame-Slot")
local SLOT_SCALE = MODERN_SLOTS and 1 or 66 / 36

local function SetSlotTextures(background, border, highlight)
	if MODERN_SLOTS then
		background:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
		border:SetAtlas("UI-HUD-ActionBar-IconFrame")
		highlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
	else
		background:SetTexture("Interface\\Buttons\\UI-Quickslot")
		border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		highlight:SetBlendMode("ADD")
	end
end

local function GridSize(cellSize)
	return SIZE * (cellSize + GAP) + GAP
end

local GRID = GridSize(CELL)
local SMALL_GRID = GridSize(SMALL_CELL)

-- Margins leave room for each grid's frame, glow and labels (see FRAMING)
local GRID_TOP = -114
local LEFT_GRID_X = 44
local RIGHT_GRID_X = LEFT_GRID_X + GRID + 80
local FULL_WIDTH = RIGHT_GRID_X + GRID + 32
local FULL_HEIGHT = 486

local SMALL_GRID_X = 40
local SMALL_GRID_TOP = -104
local SIDE_X = SMALL_GRID_X + SMALL_GRID + 24 -- status text next to the small map
local BIG_GRID_X = 44
local COMPACT_WIDTH = BIG_GRID_X + GRID + 32
local BIG_GRID_TOP = SMALL_GRID_TOP - SMALL_GRID - 74
local COMPACT_HEIGHT = -BIG_GRID_TOP + GRID + 66

-- Fills inside a slot; water is an empty slot
local COLORS = {
	miss = { 0.15, 0.45, 0.9, 0.85 }, -- placeholder until there's a fitting water icon
	hit = { 0.85, 0.2, 0.15, 0.9 },
	sunk = { 0.38, 0.08, 0.06, 0.95 },
	fits = { 0.2, 0.85, 0.3, 0.55 },
	blocked = { 0.95, 0.2, 0.2, 0.55 },
	lastShot = { 1, 0.85, 0.1, 0.35 },
}

local function GameLine()
	local name = ns.ShortName(Game.opponent)
	local state = Game.state
	if state == "inviting" then
		return "Waiting for " .. name .. " to accept"
	elseif state == "placing" then
		return "Placing ships vs " .. name
	elseif state == "playing" then
		return Game.myTurn and ("|cff40ff40Your turn|r vs " .. name) or (name .. "'s turn")
	elseif state == "over" then
		return "Game over vs " .. name
	end
	return "No game running"
end

-- The page covers the whole box window, so everything below is placed as on a window of its own
local panel = Box.AddGame({
	key = ns.KEY,
	name = "Schiffe versenken",
	description = "Battleship against another player, Horde vs Alliance.",
	icon = function()
		return ns.MyFaction().banner
	end,
	width = FULL_WIDTH,
	height = FULL_HEIGHT,
	Status = GameLine,
	Record = function()
		return ns.stats and ("Won %d  ·  Lost %d"):format(ns.stats.wins, ns.stats.losses)
	end,
	NeedsAttention = function()
		return Game.state == "playing" and Game.myTurn
	end,
	menu = {
		{ text = "Open", func = function() ns.ShowWindow() end },
		{ text = "Test game vs Training Dummy", func = function() Game.StartTest() end },
		{ text = "Give up / cancel game", func = function() Game.Quit() end },
		{ text = "Compact / full size window", func = function() ns.ToggleCompact() end },
	},
})
local panelWidth = FULL_WIDTH


-- Placing ships: the next ship goes on the hovered cell as its top/left end
local horizontal = true
local holding -- length of a ship picked back up from the board
local hovered -- cell under the mouse on your own grid

local function NextShip()
	local unplaced = Board.Unplaced(Game.myBoard, Game.fleet)
	if holding and tContains(unplaced, holding) then
		return holding
	end
	return unplaced[1]
end

local function CanEditFleet()
	return Game.state == "placing" and not Game.myReady
end

local function SetColor(texture, color)
	texture:SetColorTexture(unpack(color))
end

-- background: key into COLORS or a color; mark: nil or "cross" (hit)
local function Paint(cell, background, mark)
	if background == "water" then
		cell.fill:Hide()
	else
		local r, g, b, a = unpack(COLORS[background] or background)
		cell.fill:SetColorTexture(r, g, b, a or 0.85)
		cell.fill:Show()
	end
	cell.cross:SetShown(mark == "cross")
	cell.overlay:Hide()
end

-- Each side of the page (left/right, or top/bottom when compact) is tinted in its grid's
-- faction color (see ApplyTheme and Layout)
local firstTint = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
local secondTint = panel:CreateTexture(nil, "BACKGROUND", nil, 2)

local versus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
versus:SetText("VS")

-- Room around a grid, from the cells outward: a dark gap, the faction-colored line, the turn
-- glow (solid, then soft), then the A-J / 1-10 labels and the header
local FRAMING = {
	big = { pad = 3, line = 2, glow = { 3, 7 }, labels = 14, header = 32, banner = 26 },
	small = { pad = 2, line = 1, glow = { 2, 4 }, labels = 9, header = 23, banner = 18 },
}
local GLOW_ALPHA = { 1, 0.3 }

local function CreateGlow(grid)
	local glow = CreateFrame("Frame", nil, panel)
	glow:SetFrameLevel(grid:GetFrameLevel() + 2)
	glow.layers = {}
	for i, alpha in ipairs(GLOW_ALPHA) do
		local layer = {}
		for side = 1, 4 do
			local edge = glow:CreateTexture(nil, "ARTWORK")
			edge.alpha = alpha
			layer[side] = edge
		end
		glow.layers[i] = layer
	end

	glow.pulse = glow:CreateAnimationGroup()
	glow.pulse:SetLooping("BOUNCE")
	local fade = glow.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.2)
	fade:SetDuration(0.7)
	fade:SetSmoothing("IN_OUT")
	glow:Hide()
	return glow
end

-- The glow hugs the faction line; each layer grows outward from there
local function SizeGlow(glow, grid, outset, widths)
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", grid, -outset, outset)
	glow:SetPoint("BOTTOMRIGHT", grid, outset, -outset)
	for i, w in ipairs(widths) do
		local top, bottom, left, right = unpack(glow.layers[i])
		for _, edge in ipairs(glow.layers[i]) do
			edge:ClearAllPoints()
		end
		top:SetHeight(w)
		top:SetPoint("BOTTOMLEFT", glow, "TOPLEFT", -w, 0)
		top:SetPoint("BOTTOMRIGHT", glow, "TOPRIGHT", w, 0)
		bottom:SetHeight(w)
		bottom:SetPoint("TOPLEFT", glow, "BOTTOMLEFT", -w, 0)
		bottom:SetPoint("TOPRIGHT", glow, "BOTTOMRIGHT", w, 0)
		left:SetWidth(w)
		left:SetPoint("TOPRIGHT", glow, "TOPLEFT")
		left:SetPoint("BOTTOMRIGHT", glow, "BOTTOMLEFT")
		right:SetWidth(w)
		right:SetPoint("TOPLEFT", glow, "TOPRIGHT")
		right:SetPoint("BOTTOMLEFT", glow, "BOTTOMRIGHT")
	end
end

local function CreateGrid(onClick)
	local grid = CreateFrame("Frame", nil, panel)

	-- Faction-colored line, with a dark gap between it and the cells (sized in PlaceGrid)
	grid.border = grid:CreateTexture(nil, "BACKGROUND")
	grid.gaps = grid:CreateTexture(nil, "BACKGROUND", nil, 1)
	grid.gaps:SetColorTexture(0, 0, 0, 0.85)

	grid.header = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

	grid.banner = grid:CreateTexture(nil, "OVERLAY")
	grid.banner:SetPoint("RIGHT", grid.header, "LEFT", -6, 0)
	grid.banner:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	grid.columns, grid.rows = {}, {}
	for i = 1, SIZE do
		local column = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		column:SetText(ns.COLUMNS[i])
		grid.columns[i] = column
		local row = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row:SetText(i)
		grid.rows[i] = row
	end

	grid.cells = {}
	for y = 1, SIZE do
		for x = 1, SIZE do
			local cell = CreateFrame("Button", nil, grid)
			cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			cell.x, cell.y = x, y

			-- Empty action slot: dark background, color fill (ship, hit) inside the bevel, bevel on top
			cell.bg = cell:CreateTexture(nil, "BACKGROUND")
			cell.bg:SetPoint("CENTER")
			cell.fill = cell:CreateTexture(nil, "BORDER")
			cell.border = cell:CreateTexture(nil, "ARTWORK")
			cell.cross = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
			cell.cross:SetPoint("CENTER", 1, 0)
			cell.cross:SetText("X")
			cell.overlay = cell:CreateTexture(nil, "OVERLAY")
			cell.overlay:SetAllPoints()
			local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			SetSlotTextures(cell.bg, cell.border, highlight)

			cell:SetScript("OnClick", onClick)
			grid.cells[Board.Index(x, y)] = cell
		end
	end
	grid.glow = CreateGlow(grid)
	return grid
end

-- Puts a grid at x, y with the given cell size, labels and header to match
local function PlaceGrid(grid, x, y, cellSize)
	local step = cellSize + GAP
	local small = cellSize < CELL
	grid:SetSize(GridSize(cellSize), GridSize(cellSize))
	grid:ClearAllPoints()
	grid:SetPoint("TOPLEFT", x, y)

	local framing = small and FRAMING.small or FRAMING.big
	local pad, outset = framing.pad, framing.pad + framing.line
	grid.gaps:ClearAllPoints()
	grid.gaps:SetPoint("TOPLEFT", -pad, pad)
	grid.gaps:SetPoint("BOTTOMRIGHT", pad, -pad)
	grid.border:ClearAllPoints()
	grid.border:SetPoint("TOPLEFT", -outset, outset)
	grid.border:SetPoint("BOTTOMRIGHT", outset, -outset)
	SizeGlow(grid.glow, grid, outset, framing.glow)

	grid.header:SetFontObject(small and GameFontNormal or GameFontNormalLarge)
	grid.header:ClearAllPoints()
	grid.header:SetPoint("BOTTOM", grid, "TOP", framing.banner / 2, framing.header)
	grid.banner:SetSize(framing.banner, framing.banner)

	for i = 1, SIZE do
		local offset = GAP + (i - 1) * step + cellSize / 2
		grid.columns[i]:ClearAllPoints()
		grid.columns[i]:SetPoint("BOTTOM", grid, "TOPLEFT", offset, framing.labels)
		grid.rows[i]:ClearAllPoints()
		grid.rows[i]:SetPoint("RIGHT", grid, "TOPLEFT", -framing.labels, -offset)
	end

	for _, cell in pairs(grid.cells) do
		cell:SetSize(cellSize, cellSize)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", GAP + (cell.x - 1) * step, -(GAP + (cell.y - 1) * step))
		local slotSize = cellSize * SLOT_SCALE
		cell.bg:SetSize(slotSize, slotSize)
		cell.border:SetSize(slotSize, slotSize)
		cell.border:ClearAllPoints()
		cell.border:SetPoint("CENTER", 0, (small or MODERN_SLOTS) and 0 or -1)
		local inset = small and 1 or 2 -- keeps the fill inside the bevel
		cell.fill:ClearAllPoints()
		cell.fill:SetPoint("TOPLEFT", inset, -inset)
		cell.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
		cell.cross:SetFontObject(small and GameFontHighlightSmall or GameFontHighlightLarge)
	end
end

local ownGrid = CreateGrid(function(cell, button)
	if not CanEditFleet() then
		return
	end
	if button == "RightButton" then
		horizontal = not horizontal
	else
		local board = Game.myBoard
		local shipIndex = board.cells[Board.Index(cell.x, cell.y)]
		if shipIndex then
			local ship = Board.Remove(board, shipIndex)
			holding, horizontal = ship.length, ship.horizontal
		else
			local length = NextShip()
			if length and Board.CanPlace(board, cell.x, cell.y, length, horizontal, Game.shipWidth) then
				Board.Place(board, cell.x, cell.y, length, horizontal, Game.shipWidth)
				holding = nil
				ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			end
		end
	end
	ns.Refresh()
end)

for _, cell in pairs(ownGrid.cells) do
	cell:SetScript("OnEnter", function(self)
		hovered = self
		ns.Refresh()
	end)
	cell:SetScript("OnLeave", function(self)
		if hovered == self then
			hovered = nil
			ns.Refresh()
		end
	end)
end

local enemyGrid = CreateGrid(function(cell, button)
	if button == "LeftButton" then
		Game.Shoot(cell.x, cell.y)
	end
end)

-- Whose turn it is: a pulsing frame around the grid in play, and the enemy waters dimmed while
-- you can't fire
local function SetGlow(glow, shown, color)
	if not shown then
		glow.pulse:Stop()
		glow:Hide()
		return
	end
	local r, g, b = unpack(color)
	for _, layer in ipairs(glow.layers) do
		for _, edge in ipairs(layer) do
			edge:SetColorTexture(r, g, b, edge.alpha)
		end
	end
	if not glow:IsShown() then
		glow:Show()
		glow.pulse:Play()
	end
end

local ownGlow, enemyGlow = ownGrid.glow, enemyGrid.glow
local TURN_COLOR = { 1, 0.82, 0 }

-- Above the cells but doesn't take the mouse, so clicks still reach them
local dimmer = CreateFrame("Frame", nil, enemyGrid)
dimmer:SetAllPoints()
dimmer:SetFrameLevel(enemyGrid:GetFrameLevel() + 5)
local dimTexture = dimmer:CreateTexture(nil, "OVERLAY")
dimTexture:SetAllPoints()
dimTexture:SetColorTexture(0, 0, 0, 0.35)
dimmer:Hide()

-- "YOUR TURN!" pops up over the enemy waters and fades out again
local splash = CreateFrame("Frame", nil, enemyGrid)
splash:SetAllPoints()
splash:SetFrameLevel(enemyGrid:GetFrameLevel() + 10)
splash:Hide()
local splashText = splash:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
splashText:SetPoint("CENTER")
splashText:SetFont(splashText:GetFont(), 34, "THICKOUTLINE")
splashText:SetTextColor(unpack(TURN_COLOR))
splashText:SetText("YOUR TURN!")

local splashAnimation = splash:CreateAnimationGroup()
local fadeIn = splashAnimation:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.2)
fadeIn:SetOrder(1)
local fadeOut = splashAnimation:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(0.6)
fadeOut:SetStartDelay(0.9)
fadeOut:SetOrder(2)
splashAnimation:SetScript("OnFinished", function()
	splash:Hide()
end)

function ns.OnTurnStart()
	ns.Sound("ALARM_CLOCK_WARNING_3", "RAID_WARNING")
	if FlashClientIcon then
		FlashClientIcon() -- taskbar, if WoW is in the background
	end
	if panel:IsVisible() then
		splash:Show()
		splashAnimation:Stop()
		splashAnimation:Play()
	end
end

-- "VICTORY!" or "DEFEAT" across the grids when the game ends: a dark band with the winner's
-- banners and the faction cry below, held for a few seconds before it fades. If the game ends
-- while the page is hidden, it plays the next time the page opens. Placed in Layout.
local endSplash = CreateFrame("Frame", nil, panel)
endSplash:SetSize(FULL_WIDTH, 120)
endSplash:SetFrameLevel(enemyGrid:GetFrameLevel() + 20)
endSplash:Hide()

local endBand = endSplash:CreateTexture(nil, "BACKGROUND")
endBand:SetAllPoints()
endBand:SetColorTexture(0, 0, 0, 0.75)
local endLines = {}
for i, point in ipairs({ "TOP", "BOTTOM" }) do
	local line = endSplash:CreateTexture(nil, "BORDER")
	line:SetHeight(2)
	line:SetPoint(point .. "LEFT")
	line:SetPoint(point .. "RIGHT")
	endLines[i] = line
end

local endTitle = endSplash:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
endTitle:SetPoint("CENTER", 0, 14)
endTitle:SetFont(endTitle:GetFont(), 48, "THICKOUTLINE")

local endCry = endSplash:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
endCry:SetPoint("TOP", endTitle, "BOTTOM", 0, -6)
endCry:SetFont(endCry:GetFont(), 20, "OUTLINE")

local endBanners = {}
for i, side in ipairs({ { "RIGHT", "LEFT", -14 }, { "LEFT", "RIGHT", 14 } }) do
	local banner = endSplash:CreateTexture(nil, "ARTWORK")
	banner:SetSize(44, 44)
	banner:SetPoint(side[1], endTitle, side[2], side[3], 0)
	banner:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	endBanners[i] = banner
end

local endAnimation = endSplash:CreateAnimationGroup()
local endIn = endAnimation:CreateAnimation("Alpha")
endIn:SetFromAlpha(0)
endIn:SetToAlpha(1)
endIn:SetDuration(0.3)
endIn:SetOrder(1)
local endOut = endAnimation:CreateAnimation("Alpha")
endOut:SetFromAlpha(1)
endOut:SetToAlpha(0)
endOut:SetDuration(1)
endOut:SetStartDelay(3.5)
endOut:SetOrder(2)
endAnimation:SetScript("OnFinished", function()
	endSplash:Hide()
end)

local endPending -- result of a game that ended while the page was hidden

local function PlayEndSplash(result)
	local mine, enemy = ns.MyFaction(), ns.EnemyFaction()
	local won = result == "won"
	local winner = won and mine or enemy
	endTitle:SetText(won and "VICTORY!" or "DEFEAT")
	if won then
		endTitle:SetTextColor(unpack(TURN_COLOR))
	else
		endTitle:SetTextColor(0.9, 0.15, 0.1)
	end
	if result == "quit" then
		endCry:SetText("You gave up.")
		endCry:SetTextColor(0.8, 0.8, 0.8)
	else
		endCry:SetText(won and mine.victory or mine.defeat)
		endCry:SetTextColor(unpack(winner.color))
	end
	local r, g, b = unpack(winner.color)
	for _, line in ipairs(endLines) do
		line:SetColorTexture(r, g, b, 0.9)
	end
	for _, banner in ipairs(endBanners) do
		banner:SetTexture(winner.banner)
	end
	splash:Hide() -- no "YOUR TURN!" on top of it
	endSplash:Show()
	endAnimation:Stop()
	endAnimation:Play()
end

function ns.OnGameOver(result)
	if result ~= "won" then
		ns.Sound("IG_QUEST_FAILED")
	end
	if panel:IsVisible() then
		endPending = nil
		PlayEndSplash(result)
	else
		endPending = result
	end
end

-- Top row: who to challenge, and the layout switch
local nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
nameBox:SetSize(150, 20)
nameBox:SetAutoFocus(false)

local challengeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
challengeButton:SetSize(100, 22)
challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
challengeButton:SetText("Challenge")

local function Challenge()
	nameBox:ClearFocus()
	local name = strtrim(nameBox:GetText())
	if Game.test and Game.state == "over" and name == "" then
		Game.StartTest() -- rematch against the dummy
		return
	end
	if name == "" and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		name = GetUnitName("target", true)
		nameBox:SetText(name)
	end
	Game.Invite(name)
end
challengeButton:SetScript("OnClick", Challenge)
nameBox:SetScript("OnEnterPressed", Challenge)
nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

local versusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

local layoutButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
layoutButton:SetScript("OnClick", function()
	ns.ToggleCompact()
end)

-- Your record: top right in the full layout, under the game status in the compact one. Against
-- the current opponent next to their name, or below the record when compact (see Layout).
local recordText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
local versusRecordText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

local function Record(wins, losses)
	return ("Won |cff40ff40%d|r   Lost |cffff5050%d|r"):format(wins, losses)
end

-- Bottom corner: the addon version

local versionText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
versionText:SetPoint("BOTTOMRIGHT", -12, 6)
versionText:SetText("v" .. ns.VERSION)

-- Below the grids: what's going on, then the buttons
local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

local logText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

local buttons = {}
local function AddButton(text, width, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button.rowWidth = width
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	buttons[#buttons + 1] = button
	return button
end

local rotateButton = AddButton("Rotate", 70, function()
	horizontal = not horizontal
	ns.Refresh()
end)
local randomButton = AddButton("Random", 70, function()
	Board.Randomize(Game.myBoard, Game.fleet, Game.shipWidth)
	holding = nil
	ns.Refresh()
end)
local clearButton = AddButton("Clear", 60, function()
	Board.Clear(Game.myBoard)
	holding = nil
	ns.Refresh()
end)
local readyButton = AddButton("Ready!", 90, Game.SetReady)
local quitButton = AddButton("Give up", 80, Game.Quit)

local currentLayout -- "full", "compact" or "compactPlacing", see Layout

-- Buttons go in a row along the bottom. Placing ships in the compact layout, all but Cancel
-- stack up where the small map would be.
local function LayoutButtons()
	local row = {}
	local columnY = SMALL_GRID_TOP + 24
	for _, button in ipairs(buttons) do
		if button:IsShown() then
			button:ClearAllPoints()
			if currentLayout == "compactPlacing" and button ~= quitButton then
				button:SetWidth(SMALL_GRID)
				button:SetPoint("TOPLEFT", SMALL_GRID_X - 6, columnY)
				columnY = columnY - 28
			else
				button:SetWidth(button.rowWidth)
				row[#row + 1] = button
			end
		end
	end
	local width = -6
	for _, button in ipairs(row) do
		width = width + button:GetWidth() + 6
	end
	local x = (panelWidth - width) / 2
	for _, button in ipairs(row) do
		button:SetPoint("BOTTOMLEFT", x, 16)
		x = x + button:GetWidth() + 6
	end
end

local function DrawOwnGrid()
	local board = Game.myBoard
	for index, cell in pairs(ownGrid.cells) do
		local ship = board.ships[board.cells[index] or 0]
		local shot = board.shots[index]
		if ship and shot then
			Paint(cell, Board.IsSunk(ship) and "sunk" or "hit", "cross")
		elseif ship then
			Paint(cell, ns.MyFaction().ship)
		else
			Paint(cell, shot and "miss" or "water")
		end
	end

	if Game.state == "playing" and Game.lastShotAtMe then
		local cell = ownGrid.cells[Game.lastShotAtMe]
		SetColor(cell.overlay, COLORS.lastShot)
		cell.overlay:Show()
	end

	-- Preview where the next ship would go
	local length = NextShip()
	if CanEditFleet() and hovered and length and not board.cells[Board.Index(hovered.x, hovered.y)] then
		local fits = Board.CanPlace(board, hovered.x, hovered.y, length, horizontal, Game.shipWidth)
		for _, pos in ipairs(Board.ShipCells(hovered.x, hovered.y, length, horizontal, Game.shipWidth)) do
			if Board.InBounds(pos[1], pos[2]) then
				local cell = ownGrid.cells[Board.Index(pos[1], pos[2])]
				SetColor(cell.overlay, fits and COLORS.fits or COLORS.blocked)
				cell.overlay:Show()
			end
		end
	end
end

local ENEMY_LOOK = {
	miss = { "miss" },
	hit = { "hit", "cross" },
	sunk = { "sunk", "cross" },
	ship = { "enemyShip" },
}

local function DrawEnemyGrid()
	for index, cell in pairs(enemyGrid.cells) do
		local look = ENEMY_LOOK[Game.marks[index]]
		if look then
			Paint(cell, look[1] == "enemyShip" and ns.EnemyFaction().ship or look[1], look[2])
		else
			Paint(cell, "water")
		end
	end
end

local function StatusLine()
	local name = ns.ShortName(Game.opponent)
	local state = Game.state
	if state == "idle" then
		return "Type a name or target a player, then click Challenge."
	elseif state == "inviting" then
		return "Waiting for " .. name .. " to accept..."
	elseif state == "placing" then
		if Game.myReady then
			return "Waiting for " .. name .. " to place their ships..."
		end
		local length = NextShip()
		if length then
			if Game.shipWidth > 1 then
				return ("Place your %s (%dx%d)."):format(ns.ShipName(length, false, Game.shipWidth), length, Game.shipWidth)
			end
			return ("Place your %s (%d). Right-click to rotate."):format(ns.ShipName(length), length)
		end
		return "All ships placed. Click Ready!"
	elseif state == "playing" then
		if Game.waiting then
			return "Firing..."
		elseif Game.myTurn then
			return "|cff40ff40Your turn!|r Fire at the enemy waters."
		end
		return name .. " is aiming..."
	elseif Game.result == "won" then
		local faction = ns.MyFaction()
		return ns.FactionText(faction, faction.victory) .. " You won!"
	end
	local defeat = Game.result == "quit" and "You gave up." or "You lost."
	return defeat .. " " .. ns.FactionText(ns.EnemyFaction(), ns.MyFaction().defeat)
end

-- Faction colors, banners and names; the faction isn't known yet while the addon loads
local function ApplyTheme()
	local mine, enemy = ns.MyFaction(), ns.EnemyFaction()
	local title = ns.FactionText(mine, mine.name) .. " vs " .. ns.FactionText(enemy, enemy.name)
	Box.SetPageTitle(panel, currentLayout == "full" and ("Schiffe versenken: " .. title) or title)
	for _, side in ipairs({ { ownGrid, mine, "Fleet" }, { enemyGrid, enemy, "Waters" } }) do
		local grid, faction, word = unpack(side)
		grid.header:SetText(ns.FactionText(faction, faction.name .. " " .. word))
		grid.banner:SetTexture(faction.banner)
		local r, g, b = unpack(faction.color)
		grid.border:SetColorTexture(r * 0.6, g * 0.6, b * 0.6, 1)
		SetColor(grid.tint, faction.tint)
	end
end

local function IsCompact()
	return ns.GetSettings().compact
end

-- Places grids and everything around them for the full or compact layout. Only does work when
-- the layout changes: switching modes, or between placing ships and playing in compact mode.
local function Layout()
	local compact = IsCompact()
	local layout = not compact and "full" or (Game.state == "placing" and "compactPlacing" or "compact")
	if layout == currentLayout then
		return
	end
	currentLayout = layout

	firstTint:ClearAllPoints()
	secondTint:ClearAllPoints()
	versus:ClearAllPoints()
	nameBox:ClearAllPoints()
	versusText:ClearAllPoints()
	statusText:ClearAllPoints()
	logText:ClearAllPoints()
	layoutButton:ClearAllPoints()
	recordText:ClearAllPoints()
	versusRecordText:ClearAllPoints()
	endSplash:ClearAllPoints()

	if compact then
		panelWidth = COMPACT_WIDTH
		Box.SetPageSize(panel, COMPACT_WIDTH, COMPACT_HEIGHT)
		local big, small = enemyGrid, ownGrid
		if layout == "compactPlacing" then
			big, small = ownGrid, enemyGrid -- nothing to see in the enemy waters yet
		end
		PlaceGrid(small, SMALL_GRID_X, SMALL_GRID_TOP, SMALL_CELL)
		PlaceGrid(big, BIG_GRID_X, BIG_GRID_TOP, CELL)
		small:SetShown(layout ~= "compactPlacing")
		big:Show()
		small.tint, big.tint = firstTint, secondTint

		local divider = SMALL_GRID_TOP - SMALL_GRID - 16
		firstTint:SetPoint("TOPLEFT", 6, -26)
		firstTint:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -6, divider)
		secondTint:SetPoint("TOPLEFT", 6, divider)
		secondTint:SetPoint("BOTTOMRIGHT", -6, 6)
		versus:Hide()
		endSplash:SetWidth(COMPACT_WIDTH - 12)
		endSplash:SetPoint("CENTER", big)

		nameBox:SetWidth(130)
		nameBox:SetPoint("TOPLEFT", 70, -34) -- clear of the portrait
		versusText:SetPoint("TOPLEFT", 64, -36)

		local sideWidth = COMPACT_WIDTH - SIDE_X - 12
		statusText:SetPoint("TOPLEFT", SIDE_X, SMALL_GRID_TOP + 24)
		statusText:SetFontObject(GameFontNormal)
		logText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
		logText:SetFontObject(GameFontHighlightSmall)
		for _, text in ipairs({ statusText, logText }) do
			text:SetWidth(sideWidth)
			text:SetJustifyH("LEFT")
		end

		layoutButton:SetSize(40, 18)
		layoutButton:SetPoint("TOPRIGHT", -28, -2) -- title bar, next to the close button

		recordText:SetPoint("TOPLEFT", logText, "BOTTOMLEFT", 0, -12)
		recordText:SetFontObject(GameFontNormal)
		versusRecordText:SetPoint("TOPLEFT", recordText, "BOTTOMLEFT", 0, -3)
		versusRecordText:SetFontObject(GameFontHighlightSmall)
		layoutButton:SetText("Full")
	else
		panelWidth = FULL_WIDTH
		Box.SetPageSize(panel, FULL_WIDTH, FULL_HEIGHT)
		PlaceGrid(ownGrid, LEFT_GRID_X, GRID_TOP, CELL)
		PlaceGrid(enemyGrid, RIGHT_GRID_X, GRID_TOP, CELL)
		ownGrid:Show()
		enemyGrid:Show()
		ownGrid.tint, enemyGrid.tint = firstTint, secondTint

		local divider = FULL_WIDTH / 2
		firstTint:SetPoint("TOPLEFT", 6, -26)
		firstTint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", divider, 6)
		secondTint:SetPoint("TOPLEFT", panel, "TOPLEFT", divider, -26)
		secondTint:SetPoint("BOTTOMRIGHT", -6, 6)
		-- Centered between your grid's glow and the enemy grid's row numbers
		local gapLeft = LEFT_GRID_X + GRID + 12
		local gapRight = RIGHT_GRID_X - 26
		versus:SetPoint("CENTER", panel, "TOPLEFT", (gapLeft + gapRight) / 2, GRID_TOP - GRID / 2)
		versus:Show()
		endSplash:SetWidth(FULL_WIDTH - 12)
		endSplash:SetPoint("CENTER", panel, "TOPLEFT", FULL_WIDTH / 2, GRID_TOP - GRID / 2)

		nameBox:SetWidth(150)
		nameBox:SetPoint("TOPLEFT", 70, -34) -- clear of the portrait
		versusText:SetPoint("TOPLEFT", 64, -36)

		statusText:SetPoint("TOP", panel, "TOPLEFT", FULL_WIDTH / 2, GRID_TOP - GRID - 24)
		statusText:SetFontObject(GameFontNormalLarge)
		logText:SetPoint("TOP", statusText, "BOTTOM", 0, -6)
		logText:SetFontObject(GameFontHighlight)
		for _, text in ipairs({ statusText, logText }) do
			text:SetWidth(FULL_WIDTH - 24)
			text:SetJustifyH("CENTER")
		end

		layoutButton:SetSize(80, 22)
		layoutButton:SetPoint("TOPRIGHT", -14, -32)

		recordText:SetPoint("TOPRIGHT", layoutButton, "TOPLEFT", -20, 0)
		recordText:SetFontObject(GameFontNormalLarge)
		versusRecordText:SetPoint("LEFT", versusText, "RIGHT", 12, 0)
		versusRecordText:SetFontObject(GameFontHighlight)
		layoutButton:SetText("Compact")
	end

	ApplyTheme()
end

function ns.ToggleCompact()
	local settings = ns.GetSettings()
	settings.compact = not settings.compact
	ns.Refresh()
end

function ns.Refresh()
	Box.Refresh() -- home page and minimap button
	if not panel:IsVisible() then
		return
	end
	local state = Game.state
	local inGame = Game.InGame()

	Layout()

	DrawOwnGrid()
	DrawEnemyGrid()

	local canChallenge = state == "idle" or state == "over"
	if state == "over" and nameBox:GetText() == "" and not Game.test then
		nameBox:SetText(ns.ShortName(Game.opponent))
	end
	nameBox:SetShown(canChallenge)
	challengeButton:SetShown(canChallenge)
	challengeButton:SetText(state == "over" and "Rematch" or "Challenge")
	versusText:SetShown(not canChallenge)
	versusRecordText:SetShown(IsCompact() or not canChallenge)
	versusText:SetText("vs " .. ns.ShortName(Game.opponent))
	if ns.stats then
		recordText:SetText(Record(ns.stats.wins, ns.stats.losses))
		local versus = not Game.test and Game.opponent and ns.stats.opponents[ns.ShortName(Game.opponent)]
		versusRecordText:SetText(versus and ("vs " .. ns.ShortName(Game.opponent) .. ":  " .. Record(versus.wins, versus.losses)) or "")
	end

	statusText:SetText(StatusLine())
	local log = Game.log
	if state == "playing" or state == "over" then
		local format = IsCompact() and "Enemy sunk: %d/%d\nYours left: %d/%d"
			or "Enemy ships sunk: %d/%d   ·   Your ships left: %d/%d"
		log = format:format(Game.enemySunk, #Game.enemyFleet, Board.ShipsLeft(Game.myBoard), #Game.fleet)
			.. (log and ("\n" .. log) or "")
	end
	logText:SetText(log or "")

	local editing = CanEditFleet()
	rotateButton:SetShown(editing)
	randomButton:SetShown(editing)
	clearButton:SetShown(editing)
	readyButton:SetShown(editing)
	readyButton:SetEnabled(#Board.Unplaced(Game.myBoard, Game.fleet) == 0)
	quitButton:SetShown(inGame or state == "inviting")
	quitButton:SetText(state == "playing" and "Give up" or "Cancel")
	LayoutButtons()

	local playing = state == "playing"
	SetGlow(enemyGlow, playing and Game.myTurn, TURN_COLOR)
	SetGlow(ownGlow, playing and not Game.myTurn, ns.EnemyFaction().color)
	dimmer:SetShown(playing and not Game.myTurn)
	if state ~= "over" then
		endSplash:Hide() -- a new game started
	end
end

function ns.ShowWindow()
	Box.Show(ns.KEY)
end

function ns.ToggleWindow()
	Box.Toggle(ns.KEY)
end

panel:SetScript("OnShow", function()
	currentLayout = nil -- lay out again, which also applies the faction theme
	if Game.state == "over" and Game.opponent and not Game.test then
		nameBox:SetText(ns.ShortName(Game.opponent))
	elseif nameBox:GetText() == "" and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		nameBox:SetText(GetUnitName("target", true))
	end
	ns.Refresh()
	if endPending and Game.state == "over" then
		PlayEndSplash(endPending)
	end
	endPending = nil
end)
