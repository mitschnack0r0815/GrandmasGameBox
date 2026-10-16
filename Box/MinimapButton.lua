local _, ns = ...
local Box = ns.Box

-- Round button on the minimap edge showing the box. It pulses while a game waits for you
-- (like your turn in Schiffe versenken). Drag to move it around the minimap; the angle and
-- hidden state are saved in GrandmasGameBoxSettings.minimap.
local DEFAULT_ANGLE = 160

local button = CreateFrame("Button", "GrandmasGameBoxMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide()

-- Same textures and offsets as standard minimap buttons
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -6)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
glow:SetSize(40, 40)
glow:SetPoint("CENTER", icon)
glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
glow:SetBlendMode("ADD")
glow:SetVertexColor(1, 0.82, 0)
glow:Hide()

local pulse = glow:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.1)
fade:SetDuration(0.6)
fade:SetSmoothing("IN_OUT")

local function UpdateGlow()
	if Box.NeedsAttention() then
		if not glow:IsShown() then
			glow:Show()
			pulse:Play()
		end
	else
		pulse:Stop()
		glow:Hide()
	end
end

local function GetMinimapSettings()
	local settings = Box.GetSettings()
	settings.minimap = settings.minimap or { angle = DEFAULT_ANGLE }
	return settings.minimap
end

local function UpdatePosition()
	local angle = math.rad(GetMinimapSettings().angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, follow the cursor around the minimap edge
local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	GetMinimapSettings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

button:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", FollowCursor)
	GameTooltip:Hide()
end)
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)

-- Right-click menu entries, shared by both menu implementations below: the box, then each
-- game's own entries under its name
local function MenuItems()
	local items = {
		{ title = Box.TITLE },
		{ text = "Open", func = function() Box.Show("home") end },
	}
	for _, game in ipairs(Box.games) do
		if game.menu then
			items[#items + 1] = { divider = true }
			items[#items + 1] = { title = game.name }
			for _, item in ipairs(game.menu) do
				items[#items + 1] = item
			end
		end
	end
	items[#items + 1] = { divider = true }
	items[#items + 1] = { text = "Hide minimap button", func = function() Box.ToggleMinimapButton() end }
	return items
end

local ShowMenu
if MenuUtil and MenuUtil.CreateContextMenu then
	-- Newer clients
	ShowMenu = function(owner)
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, item in ipairs(MenuItems()) do
				if item.title then
					root:CreateTitle(item.title)
				elseif item.divider then
					root:CreateDivider()
				else
					root:CreateButton(item.text, item.func)
				end
			end
		end)
	end
else
	-- Older clients: classic dropdown menu at the cursor
	local dropdown = CreateFrame("Frame", "GrandmasGameBoxMinimapMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		for _, item in ipairs(MenuItems()) do
			if item.divider then
				if UIDropDownMenu_AddSeparator then
					UIDropDownMenu_AddSeparator(level)
				end
			else
				local info = UIDropDownMenu_CreateInfo()
				info.text = item.title or item.text
				info.isTitle = item.title and true or nil
				info.notCheckable = true
				info.func = item.func
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end, "MENU")
	ShowMenu = function()
		ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
	end
end

button:SetScript("OnClick", function(self, mouseButton)
	if mouseButton == "RightButton" then
		GameTooltip:Hide()
		ShowMenu(self)
	else
		Box.Toggle()
	end
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddDoubleLine(Box.TITLE, Box.VERSION, nil, nil, nil, 0.5, 0.5, 0.5)
	for _, game in ipairs(Box.games) do
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(game.name)
		if game.Status then
			GameTooltip:AddLine(game.Status(), 1, 1, 1)
		end
		local record = game.Record and game.Record()
		if record then
			GameTooltip:AddLine(record, 1, 1, 1)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click: Open", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Right-click: Menu", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

function Box.ToggleMinimapButton()
	local settings = GetMinimapSettings()
	settings.hide = not settings.hide
	button:SetShown(not settings.hide)
	if settings.hide then
		Box.Print("Minimap button hidden. Type /ggb minimap to show it again.")
	end
end

Box.OnRefresh(UpdateGlow)

-- SavedVariables are only available after login
icon:SetTexture(Box.ICON)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	UpdatePosition()
	button:SetShown(not GetMinimapSettings().hide)
	UpdateGlow()
end)
