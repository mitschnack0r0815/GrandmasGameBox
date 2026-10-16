local _, ns = ...
local Box = ns.Box

-- The box window, framed like the character pane: the current page's icon as the round
-- portrait in the top left corner, its title in the title bar. One page per tab; the tabs are
-- icons hanging off the right edge like the spellbook's and professions' side tabs, the home
-- page first, then a page per game. Each page covers the whole window and brings its own size,
-- title and icon; the window takes them on when its tab is selected.
local function TemplateExists(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local window = CreateFrame("Frame", "GrandmasGameBoxFrame", UIParent,
	TemplateExists("PortraitFrameTemplate") and "PortraitFrameTemplate" or "BasicFrameTemplateWithInset")
window:SetSize(400, 300)
window:SetPoint("TOP", UIParent, "TOP", 0, -120) -- pages differ in size; they grow downward
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:SetClampRectInsets(0, -40, 0, 0) -- keep the side tabs on screen too
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "GrandmasGameBoxFrame") -- close with Escape
Box.window = window

-- The portrait stays on top of the pages
local portrait = window.PortraitContainer or window.portrait
if portrait and portrait.SetFrameLevel then
	portrait:SetFrameLevel(window:GetFrameLevel() + 20)
end

window:SetScript("OnShow", function()
	Box.Sound("IG_CHARACTER_INFO_OPEN")
end)
window:SetScript("OnHide", function()
	Box.Sound("IG_CHARACTER_INFO_CLOSE")
end)

local pages = {} -- in tab order: { key, index, tab, panel, width, height, title, icon }
local byKey = {}
local current -- the selected page

-- Games in tab order, as given to Box.AddGame
Box.games = {}

function Box.GetIcon(item)
	return type(item.icon) == "function" and item.icon() or item.icon
end

local function SetTitle(text)
	if window.SetTitle then
		window:SetTitle(text)
	elseif window.TitleText then
		window.TitleText:SetText(text)
	end
end

local function SetPortrait(icon)
	if window.SetPortraitToAsset then
		window:SetPortraitToAsset(icon)
	end
end

local function UpdateTabs()
	for _, page in ipairs(pages) do
		page.tab:SetNormalTexture(Box.GetIcon(page))
		page.tab:SetChecked(page == current)
	end
end

local function SelectPage(page)
	current = page
	for _, other in ipairs(pages) do
		other.panel:SetShown(other == page)
	end
	window:SetSize(page.width, page.height)
	SetTitle(page.title)
	SetPortrait(Box.GetIcon(page))
	UpdateTabs()
	Box.GetSettings().page = page.key
end

-- Side tab: the page's icon in the spellbook's tab frame, the page's name as tooltip
local function CreateTab(page)
	local tab = CreateFrame("CheckButton", nil, window)
	tab:SetSize(32, 32)
	if page.index == 1 then
		tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -48)
	else
		tab:SetPoint("TOPLEFT", pages[page.index - 1].tab, "BOTTOMLEFT", 0, -17)
	end

	local frame = tab:CreateTexture(nil, "BACKGROUND")
	frame:SetSize(64, 64)
	frame:SetPoint("TOPLEFT", -3, 11)
	frame:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")

	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	tab:GetCheckedTexture():SetBlendMode("ADD")

	tab:SetScript("OnClick", function()
		SelectPage(page)
		Box.Sound("IG_CHARACTER_INFO_TAB")
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(page.name)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", GameTooltip_Hide)
	return tab
end

-- Adds a tab and returns its page, a frame covering the whole window (title bar included).
-- icon: path, or a function returning one (for icons only known after login).
function Box.AddPage(key, name, icon, width, height)
	local panel = CreateFrame("Frame", nil, window)
	panel:SetAllPoints()
	panel:SetFrameLevel(window:GetFrameLevel() + 5) -- above the frame's own art
	panel:Hide()

	local page = {
		key = key, name = name, icon = icon, index = #pages + 1, panel = panel,
		width = width, height = height, title = name,
	}
	pages[page.index] = page
	byKey[key] = page
	byKey[panel] = page
	page.tab = CreateTab(page)
	return panel
end

-- Adds a game's tab. game: { key, name, description, icon (path, or a function returning one),
-- width, height, Status() -> line for the home page and tooltip, Record() -> optional line,
-- NeedsAttention() -> true while the game waits for you, menu = minimap menu entries
-- { text, func } }. Returns the game's page.
function Box.AddGame(game)
	Box.games[#Box.games + 1] = game
	game.panel = Box.AddPage(game.key, game.name, game.icon, game.width or 400, game.height or 300)
	return game.panel
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
	else
		SetPortrait(Box.GetIcon(page)) -- icons can depend on things only known after login
		UpdateTabs()
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
