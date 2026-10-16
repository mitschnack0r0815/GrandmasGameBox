local _, addon = ...
local ns = addon.QuizDuel
local Box = addon.Box
local Duel = ns.Duel

-- The game's page in the box. Four views, one at a time:
--   list:     challenge a player, and all your duels (your turn first)
--   duel:     the score and the six rounds of one duel, with Play when it's your turn
--   pick:     choose this round's category
--   question: a question with four answers and a timer
local WIDTH, HEIGHT = 440, 560
local ROW_HEIGHT = 46
local ROUND_TOP = -104
local ROUND_STEP = 40
local SQUARE = 22

local INSET = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("InsetFrameTemplate")
	and "InsetFrameTemplate" or nil

local COLORS = {
	right = { 0.2, 0.75, 0.25 },
	wrong = { 0.8, 0.2, 0.15 },
	open = { 0.18, 0.18, 0.18 }, -- not played yet
	hidden = { 0.45, 0.45, 0.45 }, -- the opponent played it, you haven't yet
}

local function Plural(count, word)
	return count .. " " .. word .. (count == 1 and "" or "s")
end

local function Record()
	local stats = ns.stats
	if not stats then
		return
	end
	return ("Won |cff40ff40%d|r   Lost |cffff5050%d|r   Draws |cffffffff%d|r"):format(stats.wins, stats.losses, stats.draws)
end

local function ActiveCounts()
	local mine, running = 0, 0
	for _, duel in ipairs(Duel.List()) do
		if not duel.result then
			running = running + 1
			if Duel.MyTurn(duel) then
				mine = mine + 1
			end
		end
	end
	return mine, running
end

local panel = Box.AddGame({
	key = ns.KEY,
	name = ns.NAME,
	description = "WoW trivia against another player, one round at a time.",
	icon = ns.ICON,
	width = WIDTH,
	height = HEIGHT,
	Status = function()
		local mine, running = ActiveCounts()
		if mine > 0 then
			return "|cff40ff40Your turn|r in " .. Plural(mine, "duel")
		elseif running > 0 then
			return Plural(running, "duel") .. " running, waiting for your opponents"
		end
		return "No duels running"
	end,
	Record = Record,
	NeedsAttention = function()
		return (ActiveCounts()) > 0
	end,
	menu = {
		{ text = "Open", func = function() ns.ShowWindow() end },
		{ text = "Test duel vs Training Dummy", func = function() ns.StartTest() end },
	},
})

local views = {}
local currentView, currentDuel

local function NewView()
	local view = CreateFrame("Frame", nil, panel)
	view:SetAllPoints()
	view:Hide()
	views[#views + 1] = view
	return view
end

local function ShowView(view, title)
	currentView = view
	for _, other in ipairs(views) do
		other:SetShown(other == view)
	end
	Box.SetPageTitle(panel, title)
end

local function Button(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	return button
end

-- A colored square for one answer; color is a key into COLORS
local function Square(parent)
	local square = CreateFrame("Frame", nil, parent)
	square:SetSize(SQUARE, SQUARE)
	local border = square:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 0.9)
	square.fill = square:CreateTexture(nil, "ARTWORK")
	square.fill:SetPoint("TOPLEFT", 2, -2)
	square.fill:SetPoint("BOTTOMRIGHT", -2, 2)
	square.mark = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	square.mark:SetPoint("CENTER")
	return square
end

local function PaintSquare(square, color)
	local r, g, b = unpack(COLORS[color])
	square.fill:SetColorTexture(r, g, b, 1)
	square.mark:SetText(color == "hidden" and "?" or "")
end

local ShowList, ShowDuel, StartPlay

-- List view ------------------------------------------------------------------------------------

local listView = NewView()

local nameBox = CreateFrame("EditBox", nil, listView, "InputBoxTemplate")
nameBox:SetSize(150, 20)
nameBox:SetPoint("TOPLEFT", 74, -36) -- clear of the portrait
nameBox:SetAutoFocus(false)

local challengeButton = Button(listView, "Challenge", 100)
challengeButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

local function Challenge()
	nameBox:ClearFocus()
	local name = strtrim(nameBox:GetText())
	if name == "" and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		name = GetUnitName("target", true)
	end
	local duel = Duel.Challenge(name)
	if duel then
		nameBox:SetText("")
		StartPlay(duel)
	end
end
challengeButton:SetScript("OnClick", Challenge)
nameBox:SetScript("OnEnterPressed", Challenge)
nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

local recordText = listView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recordText:SetPoint("TOP", 0, -68)

local listInset = CreateFrame("Frame", nil, listView, INSET)
listInset:SetPoint("TOPLEFT", 8, -92)
listInset:SetPoint("BOTTOMRIGHT", -8, 8)

local scroll = CreateFrame("ScrollFrame", nil, listInset, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -6)
scroll:SetPoint("BOTTOMRIGHT", -28, 6)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 16 - 34, 10)
scroll:SetScrollChild(content)

local emptyText = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("CENTER")
emptyText:SetText("No duels yet.\nType a name or target a player and click Challenge.")

local rows = {}

local function CreateRow(index)
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + 4))
	row:SetPoint("TOPRIGHT", 0, -(index - 1) * (ROW_HEIGHT + 4))
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 0.82, 0, 0.12)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	row.name:SetPoint("TOPLEFT", 10, -6)
	row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.status:SetPoint("BOTTOMLEFT", 10, 7)
	row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	row.score:SetPoint("RIGHT", -12, 0)
	row:SetScript("OnClick", function(self)
		ShowDuel(self.duel)
		ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	end)
	return row
end

local RESULT_TEXT = {
	won = "|cff40ff40You won|r",
	lost = "|cffff5050You lost|r",
	draw = "|cffffd200Draw|r",
}

-- One line about where a duel stands
local function DuelStatus(duel)
	local action, r = Duel.NextAction(duel)
	local name = ns.ShortName(duel.opponent)
	if action == "over" then
		local text = RESULT_TEXT[duel.result] or ""
		if duel.endedBy == "quit" then
			text = text .. " (you gave up)"
		elseif duel.endedBy == "theyQuit" then
			text = text .. " (" .. name .. " gave up)"
		end
		return text
	end
	local round = ("Round %d/%d"):format(r, ns.ROUNDS)
	if action == "pick" or action == "answer" then
		if #duel.log == 0 and duel.iStarted then
			return "|cff40ff40Your turn!|r Pick the first category."
		end
		return "|cff40ff40Your turn!|r  ·  " .. round
	end
	local text = "Waiting for " .. name .. "  ·  " .. round
	if (duel.peerTurns or 0) < #duel.log then
		text = text .. (duel.offlineAt and "  ·  |cffff9933offline, sends later|r" or "  ·  sending...")
	end
	return text
end

local function SortKey(duel)
	if duel.result then
		return 3
	end
	return Duel.MyTurn(duel) and 1 or 2
end

local function RefreshList()
	recordText:SetText(Record() or "")
	local list = Duel.List()
	table.sort(list, function(a, b)
		local ka, kb = SortKey(a), SortKey(b)
		if ka ~= kb then
			return ka < kb
		end
		return a.updated > b.updated
	end)
	for i, duel in ipairs(list) do
		local row = rows[i] or CreateRow(i)
		rows[i] = row
		row.duel = duel
		row.name:SetText(ns.ShortName(duel.opponent))
		row.status:SetText(DuelStatus(duel))
		local mine, theirs = Duel.Score(duel)
		row.score:SetText(mine .. " : " .. theirs)
		if Duel.MyTurn(duel) then
			row.bg:SetColorTexture(0.2, 0.6, 0.2, 0.18)
		elseif duel.result then
			row.bg:SetColorTexture(1, 1, 1, 0.03)
		else
			row.bg:SetColorTexture(1, 1, 1, 0.07)
		end
		row:Show()
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	content:SetHeight(math.max(10, #list * (ROW_HEIGHT + 4)))
	emptyText:SetShown(#list == 0)
end

function ShowList()
	currentDuel = nil
	ShowView(listView, ns.NAME)
	if nameBox:GetText() == "" and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
		nameBox:SetText(GetUnitName("target", true))
	end
	RefreshList()
end

-- Duel view ------------------------------------------------------------------------------------

local duelView = NewView()

local youLabel = duelView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
youLabel:SetPoint("TOP", duelView, "TOPLEFT", WIDTH * 0.25 + 20, -38)
youLabel:SetText("You")
local themLabel = duelView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
themLabel:SetPoint("TOP", duelView, "TOPLEFT", WIDTH * 0.75, -38)

local scoreText = duelView:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
scoreText:SetPoint("TOP", duelView, "TOPLEFT", WIDTH / 2 + 10, -52)
scoreText:SetFont(scoreText:GetFont(), 30, "THICKOUTLINE")

local roundRows = {}
for r = 1, ns.ROUNDS do
	local row = CreateFrame("Frame", nil, duelView)
	row:SetSize(WIDTH - 32, ROUND_STEP - 6)
	row:SetPoint("TOP", 0, ROUND_TOP - (r - 1) * ROUND_STEP)
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.05)
	row.mine, row.theirs = {}, {}
	for i = 1, ns.QUESTIONS_PER_ROUND do
		row.mine[i] = Square(row)
		row.mine[i]:SetPoint("LEFT", 8 + (i - 1) * (SQUARE + 4), 0)
		row.theirs[i] = Square(row)
		row.theirs[i]:SetPoint("RIGHT", -8 - (ns.QUESTIONS_PER_ROUND - i) * (SQUARE + 4), 0)
	end
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.category = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.category:SetPoint("CENTER", 12, 0)
	row.icon:SetPoint("RIGHT", row.category, "LEFT", -6, 0)
	roundRows[r] = row
end

local resultText = duelView:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
resultText:SetPoint("TOP", 0, ROUND_TOP - ns.ROUNDS * ROUND_STEP - 8)
resultText:SetFont(resultText:GetFont(), 30, "THICKOUTLINE")

local duelStatus = duelView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
duelStatus:SetPoint("TOP", resultText, "BOTTOM", 0, -8)
duelStatus:SetWidth(WIDTH - 40)

local backButton = Button(duelView, "Back", 80)
backButton:SetPoint("BOTTOMLEFT", 16, 16)
backButton:SetScript("OnClick", function()
	ShowList()
end)

local playButton = Button(duelView, "Play", 140)
playButton:SetHeight(30)
playButton:SetPoint("BOTTOM", 0, 14)
playButton:SetScript("OnClick", function()
	if currentDuel.result then
		local duel = Duel.Challenge(currentDuel.opponent) -- rematch
		if duel then
			StartPlay(duel)
		end
	else
		StartPlay(currentDuel)
	end
end)

StaticPopupDialogs["GRANDMASGAMEBOX_QUIZ_GIVEUP"] = {
	text = "Give up the duel against %s?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, duel)
		Duel.GiveUp(duel)
		if not Duel.Get(duel.id) then
			ShowList() -- nothing was sent yet, so it's simply gone
		end
	end,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local endButton = Button(duelView, "Give up", 80)
endButton:SetPoint("BOTTOMRIGHT", -16, 16)
endButton:SetScript("OnClick", function()
	if currentDuel.result then
		Duel.Remove(currentDuel)
		ShowList()
	else
		StaticPopup_Show("GRANDMASGAMEBOX_QUIZ_GIVEUP", ns.ShortName(currentDuel.opponent), nil, currentDuel)
	end
end)

local function RefreshDuel()
	local duel = currentDuel
	local name = ns.ShortName(duel.opponent)
	themLabel:SetText(name)
	local mine, theirs = Duel.Score(duel)
	scoreText:SetText(mine .. " : " .. theirs)

	for r, row in ipairs(roundRows) do
		local round = duel.rounds[r]
		local category = round and ns.CATEGORY[round.category]
		row.category:SetText(category and category.name or ("Round " .. r))
		row.category:SetTextColor(category and 1 or 0.5, category and 1 or 0.5, category and 1 or 0.5)
		row.icon:SetTexture(category and category.icon)
		row.icon:SetShown(category ~= nil)
		for i = 1, ns.QUESTIONS_PER_ROUND do
			local myAnswer = round and (round.mine or round.progress or ""):sub(i, i)
			local theirAnswer = round and round.theirs and round.theirs:sub(i, i)
			if myAnswer and myAnswer ~= "" then
				PaintSquare(row.mine[i], myAnswer == "1" and "right" or "wrong")
			else
				PaintSquare(row.mine[i], "open")
			end
			if theirAnswer and round.mine then
				PaintSquare(row.theirs[i], theirAnswer == "1" and "right" or "wrong")
			elseif theirAnswer then
				PaintSquare(row.theirs[i], "hidden")
			else
				PaintSquare(row.theirs[i], "open")
			end
		end
	end

	local action = Duel.NextAction(duel)
	if duel.result == "won" then
		resultText:SetText("VICTORY!")
		resultText:SetTextColor(1, 0.82, 0)
	elseif duel.result == "lost" then
		resultText:SetText("DEFEAT")
		resultText:SetTextColor(0.9, 0.15, 0.1)
	elseif duel.result == "draw" then
		resultText:SetText("DRAW")
		resultText:SetTextColor(0.8, 0.8, 0.8)
	elseif action == "wait" then
		resultText:SetText("")
	else
		resultText:SetText("YOUR TURN!")
		resultText:SetTextColor(0.25, 1, 0.25)
	end
	duelStatus:SetText(DuelStatus(duel))

	playButton:SetShown(action == "pick" or action == "answer" or duel.result ~= nil)
	playButton:SetText(duel.result and "Rematch" or "Play")
	playButton:SetEnabled(not (duel.result and Duel.ActiveAgainst(duel.opponent)))
	endButton:SetText(duel.result and "Remove" or "Give up")
	endButton:SetEnabled(not duel.quitPending)
end

function ShowDuel(duel)
	currentDuel = duel
	duel.new = nil
	ShowView(duelView, ns.NAME .. " vs " .. ns.ShortName(duel.opponent))
	RefreshDuel()
end

-- Pick view ------------------------------------------------------------------------------------

local pickView = NewView()
local pickRound

local pickTitle = pickView:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
pickTitle:SetPoint("TOP", 20, -44)
local pickHint = pickView:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pickHint:SetPoint("TOP", pickTitle, "BOTTOM", 0, -8)
pickHint:SetText("Choose a category")

local pickButtons = {}
for i = 1, ns.CATEGORY_CHOICES do
	local button = CreateFrame("Button", nil, pickView)
	button:SetSize(WIDTH - 80, 72)
	button:SetPoint("TOP", 0, -120 - (i - 1) * 90)
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.07)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 0.82, 0, 0.15)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(52, 52)
	button.icon:SetPoint("LEFT", 12, 0)
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.name = button:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	button.name:SetPoint("LEFT", button.icon, "RIGHT", 16, 0)
	button:SetScript("OnClick", function(self)
		Duel.Pick(currentDuel, pickRound, self.category)
		ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		StartPlay(currentDuel)
	end)
	pickButtons[i] = button
end

local pickBack = Button(pickView, "Back", 80)
pickBack:SetPoint("BOTTOMLEFT", 16, 16)
pickBack:SetScript("OnClick", function()
	ShowDuel(currentDuel)
end)

local function ShowPick(duel, r)
	currentDuel, pickRound = duel, r
	ShowView(pickView, ns.NAME .. " vs " .. ns.ShortName(duel.opponent))
	pickTitle:SetText(("Round %d"):format(r))
	for i, key in ipairs(Duel.Offer(duel, r)) do
		local category = ns.CATEGORY[key]
		local button = pickButtons[i]
		button.category = key
		button.icon:SetTexture(category.icon)
		button.name:SetText(category.name)
	end
end

-- Question view --------------------------------------------------------------------------------

local questionView = NewView()
local asked -- { duel, r, index, question, order, start, answered }

local categoryText = questionView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
categoryText:SetPoint("TOPLEFT", 74, -34)
local progressText = questionView:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
progressText:SetPoint("TOPRIGHT", -20, -36)

local timer = CreateFrame("StatusBar", nil, questionView)
timer:SetPoint("TOPLEFT", 74, -60)
timer:SetPoint("TOPRIGHT", -20, -60)
timer:SetHeight(14)
timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
timer:SetMinMaxValues(0, ns.ANSWER_TIME)
local timerBg = timer:CreateTexture(nil, "BACKGROUND")
timerBg:SetAllPoints()
timerBg:SetColorTexture(0, 0, 0, 0.6)
local timerText = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timerText:SetPoint("CENTER")

local questionBox = CreateFrame("Frame", nil, questionView, INSET)
questionBox:SetPoint("TOPLEFT", 16, -88)
questionBox:SetPoint("TOPRIGHT", -16, -88)
questionBox:SetHeight(110)
local questionText = questionBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
questionText:SetPoint("TOPLEFT", 14, -10)
questionText:SetPoint("BOTTOMRIGHT", -14, 10)
questionText:SetJustifyV("MIDDLE")

local answerButtons = {}
local Answered

for i = 1, 4 do
	local button = CreateFrame("Button", nil, questionView, "UIPanelButtonTemplate")
	button:SetSize(WIDTH - 48, 44)
	button:SetPoint("TOP", 0, -212 - (i - 1) * 54)
	button:GetFontString():SetWidth(WIDTH - 90)
	button.marker = button:CreateTexture(nil, "ARTWORK", nil, 7)
	button.marker:SetPoint("TOPLEFT", 3, -3)
	button.marker:SetPoint("BOTTOMRIGHT", -3, 3)
	button.marker:Hide()
	button.tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.tag:SetPoint("BOTTOMRIGHT", -8, 4)
	button:SetScript("OnClick", function(self)
		Answered(self.choice)
	end)
	answerButtons[i] = button
end

local verdictText = questionView:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
verdictText:SetPoint("TOP", 0, -212 - 4 * 54 - 2)
verdictText:SetFont(verdictText:GetFont(), 26, "OUTLINE")
local theirNote = questionView:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
theirNote:SetPoint("TOP", verdictText, "BOTTOM", 0, -4)

local continueButton = Button(questionView, "Continue", 140)
continueButton:SetHeight(30)
continueButton:SetPoint("BOTTOM", 0, 14)
continueButton:SetScript("OnClick", function()
	StartPlay(asked.duel)
end)

local function Mark(button, color)
	local r, g, b = unpack(COLORS[color])
	button.marker:SetColorTexture(r, g, b, 0.55)
	button.marker:Show()
end

-- choice: 1-4 in Questions.lua order (1 is right), 0 when time ran out
function Answered(choice)
	if not asked or asked.answered then
		return
	end
	asked.answered = true
	local duel, r, index = asked.duel, asked.r, asked.index
	local round = duel.rounds[r]
	local theirs = round.theirs and tonumber(round.theirs:sub(index, index))
	Duel.Answer(duel, r, choice)

	for _, button in ipairs(answerButtons) do
		button:Disable()
		if button.choice == 1 then
			Mark(button, "right")
		elseif button.choice == choice then
			Mark(button, "wrong")
		end
		if theirs and button.choice == theirs then
			button.tag:SetText(ns.ShortName(duel.opponent))
		end
	end
	if choice == 1 then
		verdictText:SetText("Right!")
		verdictText:SetTextColor(0.25, 1, 0.25)
		ns.Sound("IG_QUEST_LIST_COMPLETE")
	else
		verdictText:SetText(choice == 0 and "Time's up!" or "Wrong!")
		verdictText:SetTextColor(1, 0.3, 0.2)
		ns.Sound("IG_QUEST_FAILED")
	end
	if theirs == 0 then
		theirNote:SetText(ns.ShortName(duel.opponent) .. " ran out of time.")
	elseif theirs then
		theirNote:SetText(ns.ShortName(duel.opponent) .. (theirs == 1 and " got it right." or " got it wrong."))
	else
		theirNote:SetText("")
	end
	continueButton:Show()
end

local function ShowQuestion(duel, r)
	local round = duel.rounds[r]
	local index = #(round.progress or "") + 1
	local question = ns.QUESTION[round.questions[index]]
	local order = { 1, 2, 3, 4 }
	for i = 4, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	asked = { duel = duel, r = r, index = index, question = question, start = GetTime() }
	currentDuel = duel

	ShowView(questionView, ns.NAME .. " vs " .. ns.ShortName(duel.opponent))
	local category = ns.CATEGORY[round.category]
	categoryText:SetText(("Round %d: %s"):format(r, category.name))
	progressText:SetText(("Question %d of %d"):format(index, #round.questions))
	questionText:SetText(question.text)
	for i, button in ipairs(answerButtons) do
		button.choice = order[i]
		button:SetText(question.answers[order[i]])
		button:Enable()
		button.marker:Hide()
		button.tag:SetText("")
	end
	verdictText:SetText("")
	theirNote:SetText("")
	continueButton:Hide()
	timer:SetValue(ns.ANSWER_TIME)
	timer:SetStatusBarColor(1, 0.82, 0)
end

questionView:SetScript("OnUpdate", function()
	if not asked or asked.answered then
		return
	end
	local left = math.max(0, ns.ANSWER_TIME - (GetTime() - asked.start))
	timer:SetValue(left)
	timerText:SetText(("%d"):format(math.ceil(left)))
	if left < 5 then
		timer:SetStatusBarColor(1, 0.25, 0.15)
	end
	if left <= 0 then
		Answered(0)
	end
end)

-- Leaving a question (closing the box, switching tabs) counts as running out of time
panel:SetScript("OnHide", function()
	if currentView == questionView and asked and not asked.answered then
		Answered(0)
	end
end)

-- Flow -----------------------------------------------------------------------------------------

-- Whatever the duel needs from you next: a category, a question, or nothing (the duel view)
function StartPlay(duel)
	local action, r = Duel.NextAction(duel)
	if action == "pick" then
		ShowPick(duel, r)
	elseif action == "answer" then
		ShowQuestion(duel, r)
	else
		ShowDuel(duel)
	end
end

function ns.Refresh()
	Box.Refresh() -- home page and minimap button
	if not panel:IsVisible() then
		return
	end
	if currentDuel and not Duel.Get(currentDuel.id) then
		ShowList() -- removed or never sent
	elseif currentView == listView then
		RefreshList()
	elseif currentView == duelView then
		RefreshDuel()
	end
end

function ns.OnDuelOver(duel)
	if duel.result == "won" then
		ns.Sound("READY_CHECK")
	end
end

function ns.ShowWindow()
	Box.Show(ns.KEY)
end

function ns.ToggleWindow()
	Box.Toggle(ns.KEY)
end

panel:SetScript("OnShow", function()
	if currentDuel and not Duel.Get(currentDuel.id) then
		ShowList()
	elseif currentView == duelView or currentView == pickView then
		ShowDuel(currentDuel)
	elseif currentView ~= questionView then
		ShowList()
	end
end)

-- Opens a duel at whatever it needs from you (used by /quiz <name>)
function ns.Play(duel)
	StartPlay(duel)
end

-- A duel against the Training Dummy (or the one already running)
function ns.StartTest()
	ns.ShowWindow()
	local duel = Duel.ActiveAgainst(ns.TEST_OPPONENT) or Duel.Challenge(ns.TEST_OPPONENT)
	StartPlay(duel)
end
