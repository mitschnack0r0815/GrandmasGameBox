local _, addon = ...
local Box = addon.Box

-- Schiffe versenken, one of the box's games. Its files share this table as their ns, apart from
-- the box's own namespace.
local ns = {}
addon.SchiffeVersenken = ns

ns.KEY = "SchiffeVersenken" -- the game's tab and settings in the box
ns.VERSION = Box.VERSION

ns.PREFIX = "SchiffeV" -- addon message prefix (max 16 characters)
ns.PROTOCOL = 3 -- bump when the messages change; both players need the same one

ns.SIZE = 10
ns.COLUMNS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }

-- Classic German fleet, longest first: 1 battleship, 2 cruisers, 3 destroyers, 4 submarines.
-- Ships may touch each other.
ns.FLEET = { 5, 4, 4, 3, 3, 3, 2, 2, 2, 2 }

-- Test game against a built-in opponent: both sides have a single 2x2 ship. You place yours,
-- the dummy's is always in the middle of the board (E5-F6).
ns.TEST_OPPONENT = "Training Dummy"
ns.TEST_SHIP = { x = 5, y = 5, length = 2, width = 2, horizontal = true }

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
		flagship = "Kul Tiran Flagship", -- the test game's 2x2
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
		flagship = "Orcish Dreadnought", -- the test game's 2x2
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

function ns.ShipName(length, enemy, width)
	local faction = enemy and ns.EnemyFaction() or ns.MyFaction()
	if (width or 1) > 1 then
		return faction.flagship
	end
	return faction.ships[length] or "ship"
end

-- "|cff...text|r" in a faction's color
function ns.FactionText(faction, text)
	local r, g, b = unpack(faction.color)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

ns.INVITE_TIMEOUT = 60 -- seconds until an unanswered challenge expires
ns.RESEND_INTERVAL = 5 -- seconds between resends of a message the other side hasn't answered
ns.OFFLINE_RETRY = 60 -- seconds between resends while the other side seems offline
ns.REVEAL_RESEND_TIME = 60 -- seconds after a game to keep resending your fleet for the reveal
ns.RESUME_MINUTES = 30 -- a game saved on /reload or logout can be resumed for this long

-- Account-wide settings (window layout)
function ns.GetSettings()
	return Box.GetSettings(ns.KEY)
end

function ns.Print(msg)
	print("|cff4fa3ffSchiffe versenken:|r " .. msg)
end

function ns.CellName(x, y)
	return ns.COLUMNS[x] .. y
end

function ns.ShortName(name)
	return name and Ambiguate(name, "none") or "?"
end

ns.Sound = Box.Sound
