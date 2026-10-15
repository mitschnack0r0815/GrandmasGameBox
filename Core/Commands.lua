local _, ns = ...

SLASH_SCHIFFEVERSENKEN1 = "/schiffe"
SLASH_SCHIFFEVERSENKEN2 = "/sv"
SlashCmdList["SCHIFFEVERSENKEN"] = function(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		ns.ToggleWindow()
	elseif msg == "quit" then
		ns.Game.Quit()
	elseif msg == "test" then
		ns.Game.StartTest()
	elseif msg == "compact" then
		ns.ToggleCompact()
	elseif msg == "minimap" then
		ns.ToggleMinimapButton()
	elseif msg == "version" then
		ns.Print("Version " .. ns.VERSION)
	elseif msg == "stats" then
		local stats = ns.stats
		ns.Print(("%d won, %d lost."):format(stats.wins, stats.losses))
		for name, versus in pairs(stats.opponents) do
			print(("  vs %s: %d won, %d lost"):format(name, versus.wins, versus.losses))
		end
	else
		-- /sv <name> challenges that player
		ns.Game.Invite(msg)
		ns.ShowWindow()
	end
end
