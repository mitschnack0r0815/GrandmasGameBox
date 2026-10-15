local addonName, ns = ...

-- The version lives only in the .toc (## Version); see CHANGELOG.md
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(addonName, "Version") or "?"

ns.PREFIX = "SchiffeV" -- addon message prefix (max 16 characters)
ns.PROTOCOL = 2 -- bump when the messages change; both players need the same one

ns.SIZE = 10
ns.COLUMNS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }

-- Classic German fleet, longest first: 1 battleship, 2 cruisers, 3 destroyers, 4 submarines.
-- Ships may not touch, not even diagonally.
ns.FLEET = { 5, 4, 4, 3, 3, 3, 2, 2, 2, 2 }

-- Look and feel per faction. Your side of the board is your faction, the enemy waters the other one.
-- Ship names are the Warcraft II fleets.
ns.FACTIONS = {
	Alliance = {
		name = "Alliance",
		banner = "Interface\\Icons\\INV_BannerPVP_02",
		color = { 0.3, 0.55, 1 },
		ship = { 0.48, 0.58, 0.75 },
		tint = { 0.1, 0.25, 0.7, 0.18 },
		ships = { [5] = "Battleship", [4] = "Elven Destroyer", [3] = "Transport", [2] = "Gnomish Submarine" },
		victory = "For the Alliance!",
		defeat = "The Horde rules the seas.",
		victorySound = 8455, -- PVPVictoryAlliance
	},
	Horde = {
		name = "Horde",
		banner = "Interface\\Icons\\INV_BannerPVP_01",
		color = { 1, 0.25, 0.15 },
		ship = { 0.58, 0.42, 0.3 },
		tint = { 0.7, 0.1, 0.05, 0.18 },
		ships = { [5] = "Ogre Juggernaught", [4] = "Troll Destroyer", [3] = "Transport", [2] = "Giant Turtle" },
		victory = "For the Horde!",
		defeat = "The Alliance rules the seas.",
		victorySound = 8454, -- PVPVictoryHorde
	},
}

function ns.MyFaction()
	return ns.FACTIONS[UnitFactionGroup("player")] or ns.FACTIONS.Alliance
end

function ns.EnemyFaction()
	return ns.MyFaction() == ns.FACTIONS.Horde and ns.FACTIONS.Alliance or ns.FACTIONS.Horde
end

function ns.ShipName(length, enemy)
	local faction = enemy and ns.EnemyFaction() or ns.MyFaction()
	return faction.ships[length] or "ship"
end

-- "|cff...text|r" in a faction's color
function ns.FactionText(faction, text)
	local r, g, b = unpack(faction.color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

ns.INVITE_TIMEOUT = 60 -- seconds until an unanswered challenge expires
ns.RESEND_INTERVAL = 5 -- seconds between resends of a message the other side hasn't answered
ns.REVEAL_RESEND_TIME = 60 -- seconds after a game to keep resending your fleet for the reveal
ns.RESUME_MINUTES = 30 -- a game saved on /reload or logout can be resumed for this long

function ns.Print(msg)
	print("|cff4fa3ffSchiffe versenken:|r " .. msg)
end

function ns.CellName(x, y)
	return ns.COLUMNS[x] .. y
end

function ns.ShortName(name)
	return name and Ambiguate(name, "none") or "?"
end

-- PlaySound by SOUNDKIT key. Plays the first of the given keys this client has.
function ns.Sound(...)
	for i = 1, select("#", ...) do
		local sound = SOUNDKIT[select(i, ...)]
		if sound then
			PlaySound(sound)
			return
		end
	end
end
