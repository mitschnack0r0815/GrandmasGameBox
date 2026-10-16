local addonName, ns = ...

-- Grandma's Game Box: one window with a tab per game. Box/ holds the window, the home tab and
-- the minimap button; each game lives in Games/<Name>/ with its own namespace table and adds
-- its tab with Box.AddGame (see Box/Window.lua).
local Box = {}
ns.Box = Box

-- The version lives only in the .toc (## Version); see CHANGELOG.md
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
Box.VERSION = GetAddOnMetadata(addonName, "Version") or "?"
Box.TITLE = "Grandma's Game Box"
Box.ICON = "Interface\\Icons\\INV_Misc_Dice_02"

-- Account-wide settings: the box's own (minimap button) plus one table per game
function Box.GetSettings(game)
	GrandmasGameBoxSettings = GrandmasGameBoxSettings or {}
	local settings = GrandmasGameBoxSettings
	if game then
		settings.games = settings.games or {}
		settings.games[game] = settings.games[game] or {}
		return settings.games[game]
	end
	return settings
end

function Box.Print(msg)
	print("|cffffb347" .. Box.TITLE .. ":|r " .. msg)
end

-- PlaySound by SOUNDKIT key. Plays the first of the given keys this client has.
function Box.Sound(...)
	for i = 1, select("#", ...) do
		local sound = SOUNDKIT[select(i, ...)]
		if sound then
			PlaySound(sound)
			return
		end
	end
end
