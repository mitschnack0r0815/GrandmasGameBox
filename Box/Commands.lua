local _, ns = ...
local Box = ns.Box

-- Each game keeps its own slash command too (like /sv)
SLASH_GRANDMASGAMEBOX1 = "/ggb"
SLASH_GRANDMASGAMEBOX2 = "/gamebox"
SlashCmdList["GRANDMASGAMEBOX"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "" then
		Box.Toggle("home")
	elseif msg == "minimap" then
		Box.ToggleMinimapButton()
	elseif msg == "version" then
		Box.Print("Version " .. Box.VERSION)
	else
		Box.Print("/ggb: open the box  ·  /ggb minimap: show/hide the minimap button  ·  /ggb version")
	end
end
