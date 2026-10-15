local _, ns = ...
local Board = ns.Board
local Game = ns.Game

-- Main window: your fleet on the left, the enemy waters you fire at on the right.
local SIZE = ns.SIZE
local CELL = 24
local GAP = 1
local STEP = CELL + GAP
local GRID = SIZE * STEP + GAP
local GRID_TOP = -104
local LEFT_GRID_X = 36
local RIGHT_GRID_X = LEFT_GRID_X + GRID + 50

local COLORS = {
	water = { 0.11, 0.27, 0.45 },
	hit = { 0.85, 0.2, 0.15 },
	sunk = { 0.38, 0.08, 0.06 },
	fits = { 0.2, 0.85, 0.3, 0.55 },
	blocked = { 0.95, 0.2, 0.2, 0.55 },
	lastShot = { 1, 0.85, 0.1, 0.35 },
}

local window = CreateFrame("Frame", "SchiffeVersenkenFrame", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(RIGHT_GRID_X + GRID + 20, 470)
window:SetPoint("CENTER")
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "SchiffeVersenkenFrame") -- close with Escape


-- Placing ships: the next ship goes on the hovered cell as its top/left end
local horizontal = true
local holding -- length of a ship picked back up from the board
local hovered -- cell under the mouse on your own grid

local function NextShip()
	local unplaced = Board.Unplaced(Game.myBoard)
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

-- background: key into COLORS or a color; mark: nil, "dot" (miss), "faint" (known water) or "cross" (hit)
local function Paint(cell, background, mark)
	SetColor(cell.bg, COLORS[background] or background)
	cell.dot:SetShown(mark == "dot" or mark == "faint")
	cell.dot:SetAlpha(mark == "faint" and 0.3 or 0.9)
	cell.cross:SetShown(mark == "cross")
	cell.overlay:Hide()
end

-- Each half of the window is tinted in its faction's color (see ApplyTheme)
local function CreateTint(anchor)
	local tint = window:CreateTexture(nil, "BACKGROUND", nil, 2)
	tint:SetPoint("TOP" .. anchor, anchor == "LEFT" and 6 or -6, -26)
	tint:SetPoint("BOTTOM", 0, 6)
	tint:SetWidth((window:GetWidth() - 12) / 2)
	return tint
end
local leftTint = CreateTint("LEFT")
local rightTint = CreateTint("RIGHT")

local versus = window:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
versus:SetPoint("CENTER", window, "TOPLEFT", (LEFT_GRID_X + GRID + RIGHT_GRID_X) / 2, GRID_TOP - GRID / 2)
versus:SetText("VS")

local function CreateGrid(left, onClick)
	local grid = CreateFrame("Frame", nil, window)
	grid:SetSize(GRID, GRID)
	grid:SetPoint("TOPLEFT", left, GRID_TOP)

	-- Faction-colored frame around the cells
	grid.border = grid:CreateTexture(nil, "BACKGROUND")
	grid.border:SetPoint("TOPLEFT", -2, 2)
	grid.border:SetPoint("BOTTOMRIGHT", 2, -2)
	local gaps = grid:CreateTexture(nil, "BACKGROUND", nil, 1)
	gaps:SetAllPoints()
	gaps:SetColorTexture(0, 0, 0, 0.85)

	grid.header = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	grid.header:SetPoint("BOTTOM", grid, "TOP", 12, 22)

	grid.banner = grid:CreateTexture(nil, "OVERLAY")
	grid.banner:SetSize(26, 26)
	grid.banner:SetPoint("RIGHT", grid.header, "LEFT", -6, 0)
	grid.banner:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	for i = 1, SIZE do
		local offset = GAP + (i - 1) * STEP + CELL / 2
		local column = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		column:SetPoint("BOTTOM", grid, "TOPLEFT", offset, 4)
		column:SetText(ns.COLUMNS[i])
		local row = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row:SetPoint("RIGHT", grid, "TOPLEFT", -5, -offset)
		row:SetText(i)
	end

	grid.cells = {}
	for y = 1, SIZE do
		for x = 1, SIZE do
			local cell = CreateFrame("Button", nil, grid)
			cell:SetSize(CELL, CELL)
			cell:SetPoint("TOPLEFT", GAP + (x - 1) * STEP, -(GAP + (y - 1) * STEP))
			cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			cell.x, cell.y = x, y

			cell.bg = cell:CreateTexture(nil, "BACKGROUND")
			cell.bg:SetAllPoints()
			cell.dot = cell:CreateTexture(nil, "ARTWORK")
			cell.dot:SetSize(6, 6)
			cell.dot:SetPoint("CENTER")
			cell.dot:SetColorTexture(1, 1, 1)
			cell.cross = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
			cell.cross:SetPoint("CENTER", 1, 0)
			cell.cross:SetText("X")
			cell.overlay = cell:CreateTexture(nil, "OVERLAY")
			cell.overlay:SetAllPoints()
			local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.15)

			cell:SetScript("OnClick", onClick)
			grid.cells[Board.Index(x, y)] = cell
		end
	end
	return grid
end

local ownGrid = CreateGrid(LEFT_GRID_X, function(cell, button)
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
			if length and Board.CanPlace(board, cell.x, cell.y, length, horizontal) then
				Board.Place(board, cell.x, cell.y, length, horizontal)
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

local enemyGrid = CreateGrid(RIGHT_GRID_X, function(cell, button)
	if button == "LeftButton" then
		Game.Shoot(cell.x, cell.y)
	end
end)

-- Whose turn it is: a pulsing frame around the grid in play, and the enemy waters dimmed while
-- you can't fire
local GLOW_LAYERS = { { width = 3, alpha = 1 }, { width = 7, alpha = 0.3 } }

local function CreateGlow(grid)
	local glow = CreateFrame("Frame", nil, window)
	-- Hugs the faction border; the edges grow outward from here
	glow:SetPoint("TOPLEFT", grid, -2, 2)
	glow:SetPoint("BOTTOMRIGHT", grid, 2, -2)
	glow:SetFrameLevel(grid:GetFrameLevel() + 2)
	glow.edges = {}
	for _, layer in ipairs(GLOW_LAYERS) do
		local w = layer.width
		local top, bottom = glow:CreateTexture(nil, "ARTWORK"), glow:CreateTexture(nil, "ARTWORK")
		top:SetHeight(w)
		top:SetPoint("BOTTOMLEFT", glow, "TOPLEFT", -w, 0)
		top:SetPoint("BOTTOMRIGHT", glow, "TOPRIGHT", w, 0)
		bottom:SetHeight(w)
		bottom:SetPoint("TOPLEFT", glow, "BOTTOMLEFT", -w, 0)
		bottom:SetPoint("TOPRIGHT", glow, "BOTTOMRIGHT", w, 0)
		local left, right = glow:CreateTexture(nil, "ARTWORK"), glow:CreateTexture(nil, "ARTWORK")
		left:SetWidth(w)
		left:SetPoint("TOPRIGHT", glow, "TOPLEFT")
		left:SetPoint("BOTTOMRIGHT", glow, "BOTTOMLEFT")
		right:SetWidth(w)
		right:SetPoint("TOPLEFT", glow, "TOPRIGHT")
		right:SetPoint("BOTTOMLEFT", glow, "BOTTOMRIGHT")
		for _, edge in ipairs({ top, bottom, left, right }) do
			edge.alpha = layer.alpha
			glow.edges[#glow.edges + 1] = edge
		end
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

local function SetGlow(glow, shown, color)
	if not shown then
		glow.pulse:Stop()
		glow:Hide()
		return
	end
	local r, g, b = unpack(color)
	for _, edge in ipairs(glow.edges) do
		edge:SetColorTexture(r, g, b, edge.alpha)
	end
	if not glow:IsShown() then
		glow:Show()
		glow.pulse:Play()
	end
end

local ownGlow = CreateGlow(ownGrid)
local enemyGlow = CreateGlow(enemyGrid)
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
	if window:IsShown() then
		splash:Show()
		splashAnimation:Stop()
		splashAnimation:Play()
	end
end

-- Top row: who to challenge, and your record
local nameBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
nameBox:SetSize(150, 20)
nameBox:SetPoint("TOPLEFT", LEFT_GRID_X + 6, -34)
nameBox:SetAutoFocus(false)

local challengeButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
challengeButton:SetSize(100, 22)
challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
challengeButton:SetText("Challenge")

local function Challenge()
	nameBox:ClearFocus()
	local name = strtrim(nameBox:GetText())
	if name == "" and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		name = GetUnitName("target", true)
		nameBox:SetText(name)
	end
	Game.Invite(name)
end
challengeButton:SetScript("OnClick", Challenge)
nameBox:SetScript("OnEnterPressed", Challenge)
nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

local versusText = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
versusText:SetPoint("TOPLEFT", LEFT_GRID_X, -36)

local recordText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
recordText:SetPoint("TOPRIGHT", -22, -38)

local versionText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
versionText:SetPoint("BOTTOMRIGHT", -12, 8)
versionText:SetText("v" .. ns.VERSION)

-- Below the grids: what's going on, then the buttons
local statusText = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
statusText:SetPoint("TOP", window, "TOPLEFT", (LEFT_GRID_X + RIGHT_GRID_X + GRID) / 2, GRID_TOP - GRID - 12)

local logText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logText:SetPoint("TOP", statusText, "BOTTOM", 0, -6)

local buttons = {}
local function AddButton(text, width, onClick)
	local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	buttons[#buttons + 1] = button
	return button
end

local rotateButton = AddButton("Rotate", 80, function()
	horizontal = not horizontal
	ns.Refresh()
end)
local randomButton = AddButton("Random", 80, function()
	Board.Randomize(Game.myBoard)
	holding = nil
	ns.Refresh()
end)
local clearButton = AddButton("Clear", 80, function()
	Board.Clear(Game.myBoard)
	holding = nil
	ns.Refresh()
end)
local readyButton = AddButton("Ready!", 100, Game.SetReady)
local quitButton = AddButton("Give up", 90, Game.Quit)

local function LayoutButtons()
	local shown = {}
	for _, button in ipairs(buttons) do
		if button:IsShown() then
			shown[#shown + 1] = button
		end
	end
	local width = -6
	for _, button in ipairs(shown) do
		width = width + button:GetWidth() + 6
	end
	local x = (window:GetWidth() - width) / 2
	for _, button in ipairs(shown) do
		button:ClearAllPoints()
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
			Paint(cell, "water", shot and "dot")
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
		local fits = Board.CanPlace(board, hovered.x, hovered.y, length, horizontal)
		for _, pos in ipairs(Board.ShipCells(hovered.x, hovered.y, length, horizontal)) do
			if Board.InBounds(pos[1], pos[2]) then
				local cell = ownGrid.cells[Board.Index(pos[1], pos[2])]
				SetColor(cell.overlay, fits and COLORS.fits or COLORS.blocked)
				cell.overlay:Show()
			end
		end
	end
end

local ENEMY_LOOK = {
	miss = { "water", "dot" },
	water = { "water", "faint" },
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
	if window.TitleText then
		window.TitleText:SetText("Schiffe versenken: " .. ns.FactionText(mine, mine.name) .. " vs " .. ns.FactionText(enemy, enemy.name))
	end
	for _, side in ipairs({ { ownGrid, mine, leftTint, "Fleet" }, { enemyGrid, enemy, rightTint, "Waters" } }) do
		local grid, faction, tint, word = unpack(side)
		grid.header:SetText(ns.FactionText(faction, faction.name .. " " .. word))
		grid.banner:SetTexture(faction.banner)
		local r, g, b = unpack(faction.color)
		grid.border:SetColorTexture(r * 0.6, g * 0.6, b * 0.6, 1)
		SetColor(tint, faction.tint)
	end
end

function ns.Refresh()
	if ns.UpdateMinimapButton then
		ns.UpdateMinimapButton()
	end
	if not window:IsShown() then
		return
	end
	local state = Game.state
	local inGame = Game.InGame()

	DrawOwnGrid()
	DrawEnemyGrid()

	local canChallenge = state == "idle" or state == "over"
	if state == "over" and nameBox:GetText() == "" then
		nameBox:SetText(ns.ShortName(Game.opponent))
	end
	nameBox:SetShown(canChallenge)
	challengeButton:SetShown(canChallenge)
	challengeButton:SetText(state == "over" and "Rematch" or "Challenge")
	versusText:SetShown(not canChallenge)
	versusText:SetText("vs " .. ns.ShortName(Game.opponent))
	if ns.stats then
		recordText:SetText(("Won %d  ·  Lost %d"):format(ns.stats.wins, ns.stats.losses))
	end

	statusText:SetText(StatusLine())
	local log = Game.log
	if state == "playing" or state == "over" then
		log = ("Enemy ships sunk: %d/%d   ·   Your ships left: %d/%d"):format(
			Game.enemySunk, #ns.FLEET, Board.ShipsLeft(Game.myBoard), #ns.FLEET) .. (log and ("\n" .. log) or "")
	end
	logText:SetText(log or "")

	local editing = CanEditFleet()
	rotateButton:SetShown(editing)
	randomButton:SetShown(editing)
	clearButton:SetShown(editing)
	readyButton:SetShown(editing)
	readyButton:SetEnabled(#Board.Unplaced(Game.myBoard) == 0)
	quitButton:SetShown(inGame or state == "inviting")
	quitButton:SetText(state == "playing" and "Give up" or "Cancel")
	LayoutButtons()

	local playing = state == "playing"
	SetGlow(enemyGlow, playing and Game.myTurn, TURN_COLOR)
	SetGlow(ownGlow, playing and not Game.myTurn, ns.EnemyFaction().color)
	dimmer:SetShown(playing and not Game.myTurn)
end

function ns.ShowWindow()
	window:Show()
end

function ns.ToggleWindow()
	window:SetShown(not window:IsShown())
end

window:SetScript("OnShow", function()
	ApplyTheme()
	if Game.state == "over" and Game.opponent then
		nameBox:SetText(ns.ShortName(Game.opponent))
	elseif nameBox:GetText() == "" and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		nameBox:SetText(GetUnitName("target", true))
	end
	ns.Refresh()
end)
