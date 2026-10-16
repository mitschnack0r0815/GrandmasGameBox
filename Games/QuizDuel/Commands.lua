local _, addon = ...
local ns = addon.QuizDuel

SLASH_GRANDMASGAMEBOXQUIZ1 = "/quiz"
SLASH_GRANDMASGAMEBOXQUIZ2 = "/qd"
SlashCmdList["GRANDMASGAMEBOXQUIZ"] = function(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		ns.ToggleWindow()
	elseif msg:lower() == "test" then
		ns.StartTest()
	else
		-- /quiz <name> challenges that player
		ns.ShowWindow()
		local duel = ns.Duel.Challenge(msg)
		if duel and ns.Play then
			ns.Play(duel)
		end
	end
end
