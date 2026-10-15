local _, ns = ...

StaticPopupDialogs["SCHIFFEVERSENKEN_INVITE"] = {
	text = "%s challenges you to Schiffe versenken!",
	button1 = ACCEPT,
	button2 = DECLINE,
	OnAccept = function(_, sender)
		ns.Game.AcceptInvite(sender)
	end,
	OnCancel = function(_, sender)
		ns.Game.DeclineInvite(sender)
	end,
	timeout = ns.INVITE_TIMEOUT,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local inviter -- who the open popup is from

function ns.ShowInvite(sender)
	inviter = sender
	StaticPopup_Show("SCHIFFEVERSENKEN_INVITE", ns.ShortName(sender), nil, sender)
	ns.Sound("READY_CHECK")
end

-- The challenger cancelled before we answered
function ns.HideInvite(sender)
	if inviter == sender then
		StaticPopup_Hide("SCHIFFEVERSENKEN_INVITE")
		inviter = nil
	end
end
