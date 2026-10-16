local _, addon = ...
local Box = addon.Box

-- Quiz Duel, one of the box's games: WoW trivia against other players, played in turns that
-- don't need both players online at the same time. Its files share this table as their ns.
local ns = {}
addon.QuizDuel = ns

ns.KEY = "QuizDuel" -- the game's tab and settings in the box
ns.NAME = "Quiz Duel"
ns.ICON = "Interface\\Icons\\INV_Misc_Book_11"

ns.PREFIX = "GGBQuiz" -- addon message prefix (max 16 characters)
-- Bump when the messages or the questions change (Questions.lua); both players need the same
-- one, since rounds only send question ids
ns.PROTOCOL = 2

ns.ROUNDS = 6
ns.QUESTIONS_PER_ROUND = 3
ns.CATEGORY_CHOICES = 3 -- categories to pick from each round
ns.ANSWER_TIME = 20 -- seconds per question

ns.RESEND_INTERVAL = 30 -- seconds between resends of a turn the opponent hasn't confirmed
ns.OFFLINE_RETRY = 300 -- seconds to wait before resending to an opponent who seemed offline
ns.KEEP_FINISHED = 10 -- finished duels kept in the list

-- Test duel opponent, played locally (see the bottom of Duel.lua)
ns.TEST_OPPONENT = "Training Dummy"

function ns.Print(msg)
	print("|cffffd200" .. ns.NAME .. ":|r " .. msg)
end

ns.Sound = Box.Sound

function ns.ShortName(name)
	return name and Ambiguate(name, "none") or "?"
end

function ns.SameName(a, b)
	return a and b and Ambiguate(a, "none"):lower() == Ambiguate(b, "none"):lower()
end
