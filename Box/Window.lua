local _, ns = ...
local Box = ns.Box

-- The box window: one page per tab along the bottom edge, the home page first, then a page
-- per game. Each page covers the whole window and brings its own size and title; the window
-- takes them on when its tab is selected.
local window = CreateFrame("Frame", "GrandmasGameBoxFrame", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(400, 300)
window:SetPoint("TOP", UIParent, "TOP", 0, -120) -- pages differ in size; they grow downward
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "GrandmasGameBoxFrame") -- close with Escape
Box.window = window

-- Bottom tabs as on the character window; plain buttons if the client doesn't have them
local hasTabTemplate = C_XMLUtil and C_XMLUtil.GetTemplateInfo
	and C_XMLUtil.GetTemplateInfo("PanelTabButtonTemplate") ~= nil

local pages = {} -- in tab order: { key, tab, panel, width, height, title }
local byKey = {}
local current -- the selected page

-- Games in tab order, as given to Box.AddGame
Box.games = {}

local function SetTitle(text)
	if window.TitleText then
		window.TitleText:SetText(text)
	end
end

local function SelectPage(page)
	current = page
	for _, other in ipairs(pages) do
		other.panel:SetShown(other == page)
	end
	window:SetSize(page.width, page.height)
	SetTitle(page.title)
	if hasTabTemplate then
		PanelTemplates_SetTab(window, page.index)
	else
		for _, other in ipairs(pages) do
			other.tab:SetEnabled(other ~= page)
		end
	end
	Box.GetSettings().page = page.key
end

-- Adds a tab and returns its page, a frame covering the whole window (title bar included)
function Box.AddPage(key, tabText, width, height)
	local index = #pages + 1

	-- PanelTemplates expects tabs named <window>Tab<n>
	local tab = CreateFrame("Button", "GrandmasGameBoxFrameTab" .. index, window,
		hasTabTemplate and "PanelTabButtonTemplate" or "UIPanelButtonTemplate")
	tab:SetID(index)
	tab:SetText(tabText)
	if index == 1 then
		tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
	else
		tab:SetPoint("LEFT", pages[index - 1].tab, "RIGHT", 3, 0)
	end
	if hasTabTemplate then
		PanelTemplates_TabResize(tab, 0)
	else
		tab:SetSize(120, 24)
	end

	local panel = CreateFrame("Frame", nil, window)
	panel:SetAllPoints()
	panel:SetFrameLevel(window:GetFrameLevel() + 5) -- above the inset's art
	panel:Hide()

	local page = { key = key, index = index, tab = tab, panel = panel, width = width, height = height, title = Box.TITLE }
	pages[index] = page
	byKey[key] = page
	byKey[panel] = page

	tab:SetScript("OnClick", function()
		SelectPage(page)
		Box.Sound("IG_CHARACTER_INFO_TAB")
	end)
	if hasTabTemplate then
		PanelTemplates_SetNumTabs(window, index)
	end
	return panel
end

-- Adds a game's tab. game: { key, name, description, icon (path, or a function returning one),
-- width, height, Status() -> line for the home page and tooltip, Record() -> optional line,
-- NeedsAttention() -> true while the game waits for you, menu = minimap menu entries
-- { text, func } }. Returns the game's page.
function Box.AddGame(game)
	Box.games[#Box.games + 1] = game
	game.panel = Box.AddPage(game.key, game.name, game.width or 400, game.height or 300)
	return game.panel
end

function Box.GetIcon(game)
	return type(game.icon) == "function" and game.icon() or game.icon
end

-- A page changes its own size (like a game's compact layout)
function Box.SetPageSize(panel, width, height)
	local page = byKey[panel]
	page.width, page.height = width, height
	if page == current then
		window:SetSize(width, height)
	end
end

function Box.SetPageTitle(panel, text)
	local page = byKey[panel]
	page.title = text
	if page == current then
		SetTitle(text)
	end
end

-- Opens the box on a page (by key); without one, on the page it was last on
function Box.Show(key)
	local page = byKey[key or Box.GetSettings().page or ""] or pages[1]
	window:Show()
	if page ~= current or not page.panel:IsShown() then
		SelectPage(page)
	end
end

-- Opens the box on a page, or closes it if that page is already showing
function Box.Toggle(key)
	local page = byKey[key or ""]
	if window:IsShown() and (not page or page == current) then
		window:Hide()
	else
		Box.Show(key)
	end
end

-- Something changed in a game: the home page and minimap button show it
local listeners = {}
function Box.OnRefresh(func)
	listeners[#listeners + 1] = func
end

function Box.Refresh()
	for _, func in ipairs(listeners) do
		func()
	end
end

function Box.NeedsAttention()
	for _, game in ipairs(Box.games) do
		if game.NeedsAttention and game.NeedsAttention() then
			return true
		end
	end
	return false
end
