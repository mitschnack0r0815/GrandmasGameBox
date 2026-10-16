local _, ns = ...
local Box = ns.Box

-- Home page: the box's first tab. A card per game with what's going on in it; click one to
-- switch to its tab. The box's dice are the portrait.
local WIDTH = 420
local CARD_HEIGHT = 64
local CARD_GAP = 8
local INSET_TOP = -88
local CARDS_TOP = INSET_TOP - 8

local panel = Box.AddPage("home", Box.TITLE, Box.ICON, WIDTH, 200)

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
title:SetPoint("TOPLEFT", 70, -34)
title:SetText("Welcome!")

local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetText("Pull up a chair and pick a game.")

local versionText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
versionText:SetPoint("BOTTOMRIGHT", -12, 8)
versionText:SetText("v" .. Box.VERSION)

-- Sunken area for the cards, as on the character pane
local inset = CreateFrame("Frame", nil, panel,
	C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate") and "InsetFrameTemplate" or nil)
inset:SetPoint("TOPLEFT", 8, INSET_TOP)
inset:SetPoint("BOTTOMRIGHT", -8, 24)

local cards = {}

local function CreateCard(game, index)
	local card = CreateFrame("Button", nil, inset)
	card:SetHeight(CARD_HEIGHT)
	local y = CARDS_TOP - INSET_TOP - (index - 1) * (CARD_HEIGHT + CARD_GAP)
	card:SetPoint("TOPLEFT", 8, y)
	card:SetPoint("TOPRIGHT", -8, y)

	local background = card:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 1, 1, 0.06)
	local highlight = card:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 0.82, 0, 0.12)

	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(44, 44)
	card.icon:SetPoint("LEFT", 10, 0)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 0)
	card.name:SetText(game.name)

	card.description = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.description:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.description:SetPoint("RIGHT", -10, 0)
	card.description:SetJustifyH("LEFT")
	card.description:SetText(game.description or "")

	card.status = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.status:SetPoint("TOPLEFT", card.description, "BOTTOMLEFT", 0, -3)
	card.status:SetPoint("RIGHT", -10, 0)
	card.status:SetJustifyH("LEFT")

	card:SetScript("OnClick", function()
		Box.Show(game.key)
		Box.Sound("IG_CHARACTER_INFO_TAB")
	end)
	return card
end

local function Refresh()
	if not panel:IsVisible() then
		return
	end
	for i, game in ipairs(Box.games) do
		local card = cards[i] or CreateCard(game, i)
		cards[i] = card
		card.icon:SetTexture(Box.GetIcon(game))
		local status = game.Status and game.Status() or ""
		local record = game.Record and game.Record()
		if record then
			status = status .. "  |cff999999·  " .. record .. "|r"
		end
		card.status:SetText(status)
	end
end
Box.OnRefresh(Refresh)

panel:SetScript("OnShow", Refresh)

-- Games add their tabs after this file loads, so size the page once they're all in
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	local count = #Box.games
	Box.SetPageSize(panel, WIDTH, -CARDS_TOP + count * (CARD_HEIGHT + CARD_GAP) + 32)
end)
