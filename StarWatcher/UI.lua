local SW = StarWatcher
local E = SW.Engine

local STAR_NAME = "Collapsing Star"
local VERSION = "1.0.7"
local MAX_TASKS = 4
local TASK_H = 12
local WIDTH = 274
local PAD = 8
local ROW_H = 46
local SLOT_H = 42
local SLOT_ROWS = 3
local DOTS = 5
local BAR_W = WIDTH - 2 * 8
local UPDATE_INTERVAL = 0.1
local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local ROWS_TOP = 8 + (MAX_TASKS + 1) * TASK_H + 16 + 6
local SLOTS_TOP = ROWS_TOP + E.MAX_STARS * ROW_H + 8
local HEIGHT = SLOTS_TOP + 16 + SLOT_ROWS * SLOT_H + 6

local HEALTH_COLORS = {
    { 0.75, { 0.2, 0.8, 0.2 } },
    { 0.55, { 0.6, 0.85, 0.15 } },
    { 0.30, { 0.95, 0.85, 0.1 } },
    { 0.15, { 0.95, 0.5, 0.1 } },
    { 0, { 0.85, 0.15, 0.15 } },
}

local function HealthColor(fraction)
    for i = 1, #HEALTH_COLORS do
        if fraction >= HEALTH_COLORS[i][1] then
            return HEALTH_COLORS[i][2]
        end
    end
    return HEALTH_COLORS[#HEALTH_COLORS][2]
end

local function Num(n)
    local s = string.format("%d", n + 0.5)
    local replaced
    repeat
        s, replaced = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
    until replaced == 0
    return s
end

local function Abbrev(n)
    local a = math.abs(n)
    if a >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif a >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return string.format("%d", n)
end

local function Colored(text, c)
    return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local GREEN = { 0.2, 1, 0.2 }
local RED = { 1, 0.25, 0.25 }
local GREY = { 0.65, 0.65, 0.65 }
local WHITE = { 1, 1, 1 }
local YELLOW = { 1, 0.85, 0.2 }

-- ---------------------------------------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "StarWatcherFrame", UIParent)
frame:SetWidth(WIDTH)
frame:SetHeight(HEIGHT)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
frame:Hide()

local function Text(parent, size, justify, width)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetJustifyH(justify or "LEFT")
    if width then
        fs:SetWidth(width)
    end
    return fs
end

local strategyLine = Text(frame, 10, "LEFT", WIDTH - 2 * PAD)
strategyLine:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -8)
strategyLine:SetHeight(TASK_H)
local shownStrategy
local function UpdateStrategyLine()
    local n = E.GetStrategy()
    if n ~= shownStrategy then
        shownStrategy = n
        strategyLine:SetText("|cffffd100" .. n .. "-stars strategy:|r")
    end
end
UpdateStrategyLine()
local taskLines = {}
for i = 1, MAX_TASKS do
    taskLines[i] = Text(frame, 10, "LEFT", WIDTH - 2 * PAD)
    taskLines[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(8 + i * TASK_H))
    taskLines[i]:SetHeight(TASK_H)
end
local sub = Text(frame, 11, "LEFT", WIDTH - 2 * PAD)
sub:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(8 + (MAX_TASKS + 1) * TASK_H + 4))
sub:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])

-- the four star rows
local rows = {}
for i = 1, E.MAX_STARS do
    local r = CreateFrame("Frame", nil, frame)
    r:SetWidth(WIDTH - 2 * PAD)
    r:SetHeight(ROW_H - 2)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(ROWS_TOP + (i - 1) * ROW_H))

    r.glow = CreateFrame("Frame", nil, r)
    r.glow:SetPoint("TOPLEFT", r, "TOPLEFT", -3, 3)
    r.glow:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 3, -1)
    r.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    r.glow:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    r.glow:Hide()
    r.name = Text(r, 10, "LEFT", 72)
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.slot = Text(r, 10, "LEFT", 56)
    r.slot:SetPoint("TOPLEFT", r, "TOPLEFT", 72, 0)
    r.death = Text(r, 10, "LEFT", 52)
    r.death:SetPoint("TOPLEFT", r, "TOPLEFT", 130, 0)
    r.dev = Text(r, 10, "RIGHT", 50)
    r.dev:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)

    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetWidth(BAR_W)
    r.bar:SetHeight(16)
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -14)
    r.bar:SetStatusBarTexture(BAR_TEXTURE)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(0)
    r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(r.bar)
    r.bg:SetTexture(BAR_TEXTURE)
    r.bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    r.doom = Text(r, 9, "LEFT", BAR_W)
    r.doom:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -31)
    r.hp = Text(r.bar, 9, "LEFT", BAR_W - 5 - DOTS * 15)
    r.hp:SetPoint("LEFT", r.bar, "LEFT", 4, 0)

    r.dots = {}
    for j = 1, DOTS do
        local d = CreateFrame("Frame", nil, r.bar)
        d:SetWidth(14)
        d:SetHeight(14)
        d:SetPoint("RIGHT", r.bar, "RIGHT", -1 - (j - 1) * 15, 0)
        d.icon = d:CreateTexture(nil, "ARTWORK")
        d.icon:SetAllPoints(d)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.timer = Text(d, 8, "CENTER", 24)
        d.timer:SetPoint("CENTER", d, "CENTER", 0, 0)
        d:Hide()
        r.dots[j] = d
    end
    rows[i] = r
end

-- the upcoming slots
local slotTitle = Text(frame, 11, "LEFT", 200)
slotTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -SLOTS_TOP)
slotTitle:SetText(Colored("Upcoming slots", GREY))
local fillTitle = Text(frame, 8, "CENTER", 34)
fillTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 36, -SLOTS_TOP + 1)
fillTitle:SetText(Colored("filled", GREY))
local spaceTitle = Text(frame, 8, "CENTER", 34)
spaceTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -SLOTS_TOP + 1)
spaceTitle:SetText(Colored("spaced", GREY))

local TEXT_W = BAR_W - 74
local slots = {}
for i = 1, SLOT_ROWS do
    local s = CreateFrame("Frame", nil, frame)
    s:SetWidth(BAR_W)
    s:SetHeight(SLOT_H - 3)
    s:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(SLOTS_TOP + 16 + (i - 1) * SLOT_H))
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints(s)
    s.bg:SetTexture(0.1, 0.1, 0.1, 0.6)
    s.label = Text(s, 10, "LEFT", TEXT_W)
    s.label:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -2)
    s.timing = Text(s, 9, "RIGHT", TEXT_W)
    s.timing:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -3)
    s.lines = {}
    for k = 1, 2 do
        s.lines[k] = Text(s, 9, "LEFT", TEXT_W)
        s.lines[k]:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -2 - k * 12)
    end
    s.fill = s:CreateTexture(nil, "OVERLAY")
    s.fill:SetWidth(18)
    s.fill:SetHeight(18)
    s.fill:SetPoint("RIGHT", s, "RIGHT", -45, 0)
    s.space = s:CreateTexture(nil, "OVERLAY")
    s.space:SetWidth(18)
    s.space:SetHeight(18)
    s.space:SetPoint("RIGHT", s, "RIGHT", -9, 0)
    s:Hide()
    slots[i] = s
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- Raid markers: the stars are marked as they are targeted, with the markers the raid leader did not keep free
-- ---------------------------------------------------------------------------------------------------------------------------
local MARK_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
local MARK_LABELS = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }

local function NextFreeMarker(currentGuid)
    local used = E.UsedMarkers(currentGuid)
    local excluded = StarWatcherDB.excludedMarks
    for _, marker in ipairs(MARK_ORDER) do
        if not used[marker] and not excluded[marker] then
            return marker
        end
    end
    return nil
end

local function CanMark()
    return GetNumRaidMembers() == 0 or IsRaidLeader() or IsRaidOfficer()
end

local function AutoMarkTarget()
    if not StarWatcherDB or StarWatcherDB.markMode ~= "auto" or not E.IsStarted() then
        return
    end
    if UnitName("target") ~= STAR_NAME or not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        return
    end
    if GetRaidTargetIndex("target") or not CanMark() then
        return
    end
    local guid = UnitGUID("target")
    local marker = NextFreeMarker(guid)
    if marker then
        SetRaidTarget("target", marker)
        E.NoteMarker(guid, marker)
    end
end

-- Dynamic marking: a star that is targeted by somebody (or is the focus ...) is marked while it is placed right and loses its marker when
-- it is not. Only the markers set here are ever taken off, and only for a star that a unit token points at right now.
local DYNAMIC_HOLD = 0.5       -- seconds a state has to hold before the marker follows it
local DYNAMIC_PAUSE = 1        -- seconds between two changes of the marker of a star
local dynamicState = {}        -- guid -> { placed, since, changed }
local addonMarks = {}          -- guid -> marker that the addon set on it

function SW.DynamicMark(model, now)
    if not StarWatcherDB or StarWatcherDB.markMode ~= "dynamic" or not E.IsStarted() or not CanMark() then
        return
    end
    for i = 1, E.MAX_STARS do
        local item = model.rows[i]
        local rec = item and item.rec
        local guid = item and item.guid
        local token = rec and rec.token
        if guid and token and not rec.dead and UnitExists(token) and UnitGUID(token) == guid then
            local placed = E.IsPlaced(item)
            local state = dynamicState[guid]
            if not state then
                state = { placed = placed, since = now, changed = -DYNAMIC_PAUSE }
                dynamicState[guid] = state
            end
            if state.placed ~= placed then
                state.placed, state.since = placed, now
            end
            local current = GetRaidTargetIndex(token)
            if addonMarks[guid] and current ~= addonMarks[guid] then
                addonMarks[guid] = nil      -- changed by hand: not ours any more
            end
            if now - state.since >= DYNAMIC_HOLD and now - state.changed >= DYNAMIC_PAUSE then
                if placed and not current then
                    local marker = NextFreeMarker(guid)
                    if marker then
                        SetRaidTarget(token, marker)
                        E.NoteMarker(guid, marker)
                        addonMarks[guid] = marker
                        state.changed = now
                    end
                elseif not placed and current and addonMarks[guid] == current then
                    SetRaidTarget(token, 0)
                    addonMarks[guid] = nil
                    state.changed = now
                end
            end
        end
    end
end

local MARK_MODES = { "off", "auto", "dynamic" }
local function NextMarkMode(mode)
    for i, name in ipairs(MARK_MODES) do
        if name == mode then
            return MARK_MODES[i % #MARK_MODES + 1]
        end
    end
    return "auto"
end

local autoMarkButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
autoMarkButton:SetWidth(100)
autoMarkButton:SetHeight(18)
autoMarkButton:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
autoMarkButton:SetNormalFontObject(GameFontNormalSmall)
autoMarkButton:SetHighlightFontObject(GameFontHighlightSmall)

local configButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
configButton:SetWidth(46)
configButton:SetHeight(18)
configButton:SetPoint("BOTTOMRIGHT", autoMarkButton, "BOTTOMLEFT", -3, 0)
configButton:SetNormalFontObject(GameFontNormalSmall)
configButton:SetHighlightFontObject(GameFontHighlightSmall)
configButton:SetText("Config")

local title = frame:CreateFontString(nil, "OVERLAY")
title:SetFont(FONT, 11, "OUTLINE")
title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 2, 4)
title:SetText("|cff33ff99StarWatcher|r |cffaaaaaa" .. VERSION .. "|r")

local shownAutoMark
local function UpdateAutoMarkButton()
    local mode = StarWatcherDB and StarWatcherDB.markMode or "off"
    if mode == shownAutoMark then
        return
    end
    shownAutoMark = mode
    autoMarkButton:SetText("Marks: " .. mode)
    if mode == "auto" then
        autoMarkButton:GetFontString():SetTextColor(0.3, 1, 0.3)
    elseif mode == "dynamic" then
        autoMarkButton:GetFontString():SetTextColor(0.4, 0.8, 1)
    else
        autoMarkButton:GetFontString():SetTextColor(0.7, 0.7, 0.7)
    end
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- The configuration window: the settings
-- ---------------------------------------------------------------------------------------------------------------------------
local config = CreateFrame("Frame", "StarWatcherConfig", UIParent)
config:SetWidth(490)
config:SetHeight(476)
config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
config:SetFrameStrata("DIALOG")
config:SetMovable(true)
config:EnableMouse(true)
config:RegisterForDrag("LeftButton")
config:SetScript("OnDragStart", config.StartMoving)
config:SetScript("OnDragStop", config.StopMovingOrSizing)
config:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
config:Hide()

tinsert(UISpecialFrames, "StarWatcherConfig")
local configTitle = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
configTitle:SetPoint("TOP", config, "TOP", 0, -16)
configTitle:SetText("StarWatcher " .. VERSION)
local configClose = CreateFrame("Button", nil, config, "UIPanelCloseButton")
configClose:SetPoint("TOPRIGHT", config, "TOPRIGHT", -5, -5)

-- three tabs, one page each
local tabNames = { "Display", "Strategy", "Markers" }
local pages, tabButtons = {}, {}
local currentTab = "Display"
local function ShowTab(name)
    currentTab = name
    for _, tab in ipairs(tabNames) do
        if tab == name then
            pages[tab]:Show()
            tabButtons[tab]:Disable()
        else
            pages[tab]:Hide()
            tabButtons[tab]:Enable()
        end
    end
end
for index, tab in ipairs(tabNames) do
    local page = CreateFrame("Frame", nil, config)
    page:SetPoint("TOPLEFT", config, "TOPLEFT", 0, -66)
    page:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    pages[tab] = page
    local button = CreateFrame("Button", "StarWatcherConfigTab" .. index, config, "UIPanelButtonTemplate")
    button:SetWidth(110)
    button:SetHeight(22)
    button:SetPoint("TOPLEFT", config, "TOPLEFT", 28 + (index - 1) * 114, -40)
    button:SetText(tab)
    button:SetScript("OnClick", function() ShowTab(tab) end)
    tabButtons[tab] = button
end
local displayPage, strategyPage, markersPage = pages.Display, pages.Strategy, pages.Markers

SW.UI = {}
local updating = false
local unlocked = false
SW.UI.IsUnlocked = function() return unlocked or config:IsShown() end

local function CreateCheckbox(name, parent, x, y, label, onClick)
    local box = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetWidth(24)
    box:SetHeight(24)
    _G[name .. "Text"]:SetText(label)
    box:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return box
end

local function CreateSlider(parent, name, y, label, low, high, step, format, onChange)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, y)
    slider:SetWidth(360)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    _G[name .. "Low"]:SetText(string.format(format, low))
    _G[name .. "High"]:SetText(string.format(format, high))
    slider.label = label
    slider.format = format
    slider:SetScript("OnValueChanged", function(self, value)
        _G[name .. "Text"]:SetText(label .. ": " .. string.format(format, value))
        if not updating then
            onChange(value)
        end
    end)
    return slider
end

local function CreateHeading(parent, x, y, text, font)
    local heading = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    heading:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    heading:SetText(text)
    return heading
end

-- ---- tab 1: Display
local scaleSlider = CreateSlider(displayPage, "StarWatcherConfigScale", -22, "Scale", 0.5, 2, 0.05, "%.2f", function(value)
    StarWatcherDB.scale = value
    frame:SetScale(value)
    SW.Rolling.SetScale(value)
end)
-- the whole main window: every element of it, not only the background
local windowOpacitySlider = CreateSlider(displayPage, "StarWatcherConfigWindowOpacity", -66, "Main window opacity (%)", 20, 100, 5, "%d", function(value)
    StarWatcherDB.windowOpacity = value / 100
    frame:SetAlpha(value / 100)
end)
local timelineBox = CreateCheckbox("StarWatcherConfigTimeline", displayPage, 26, -100, "Show the rolling timeline (30 s behind, 90 s ahead)", function(checked)
    StarWatcherDB.timeline = checked
end)
local timelineOpacitySlider = CreateSlider(displayPage, "StarWatcherConfigTimelineOpacity", -158, "Rolling timeline opacity (%)", 20, 100, 5, "%d", function(value)
    StarWatcherDB.timelineOpacity = value / 100
    SW.Rolling.SetOpacity(value / 100)
end)

-- ---- tab 2: Strategy
CreateHeading(strategyPage, 28, -8, "Strategy")
local strategyTwo = CreateFrame("CheckButton", "StarWatcherConfigStrategy2", strategyPage, "UIRadioButtonTemplate")
strategyTwo:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", 32, -24)
_G["StarWatcherConfigStrategy2Text"]:SetText("2 stars strategy")
local strategyThree = CreateFrame("CheckButton", "StarWatcherConfigStrategy3", strategyPage, "UIRadioButtonTemplate")
strategyThree:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", 32, -46)
_G["StarWatcherConfigStrategy3Text"]:SetText("3 stars strategy")
local function ChooseStrategy(n)
    StarWatcherDB.strategy = n
    E.SetStrategy(n)
    strategyTwo:SetChecked(n == 2)
    strategyThree:SetChecked(n == 3)
    UpdateStrategyLine()
end
strategyTwo:SetScript("OnClick", function() ChooseStrategy(2) end)
strategyThree:SetScript("OnClick", function() ChooseStrategy(3) end)

local bufferSlider = CreateSlider(strategyPage, "StarWatcherConfigBuffer", -100, "Big Bang and star buffer (seconds)", 0, 20, 1, "%d", function(value)
    StarWatcherDB.buffer = value
    E.SetBuffer(value)
end)
local marginSlider = CreateSlider(strategyPage, "StarWatcherConfigMargin", -144, "Star spawn buffer (seconds)", 0, 5, 0.5, "%.1f", function(value)
    StarWatcherDB.spawnMargin = value
    E.SetSpawnMargin(value)
end)
local smashSlider = CreateSlider(strategyPage, "StarWatcherConfigSmash", -188, "Cosmic Smash buffer (seconds, 0 = off)", 0, 6, 0.5, "%.1f", function(value)
    StarWatcherDB.smashBuffer = value
    E.SetSmashBuffer(value)
end)

-- the perfect window: 2, 3 or 4 seconds before the end of the Big Bang cast
CreateHeading(strategyPage, 28, -226, "Perfect window (seconds before the end of the Big Bang cast)")
local perfectRadios = {}
local function ChoosePerfect(n)
    StarWatcherDB.perfectWindow = n
    E.SetPerfectWindow(n)
    for seconds, radio in pairs(perfectRadios) do
        radio:SetChecked(seconds == E.GetPerfectWindow())
    end
end
for index, entry in ipairs({ { 2, "2 s", 28 }, { 3, "3 s", 98 }, { 4, "4 s", 168 } }) do
    local radio = CreateFrame("CheckButton", "StarWatcherConfigPerfect" .. index, strategyPage, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", entry[3], -242)
    _G["StarWatcherConfigPerfect" .. index .. "Text"]:SetText(entry[2])
    radio:SetScript("OnClick", function() ChoosePerfect(entry[1]) end)
    perfectRadios[entry[1]] = radio
end

-- Curse of Doom: the spell power of the warlock (the talents are always assumed: see the engine)
CreateHeading(strategyPage, 28, -282, "Curse of Doom")
local doomDamageLabel = strategyPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
doomDamageLabel:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", 32, -334)
doomDamageLabel:SetWidth(420)
doomDamageLabel:SetJustifyH("LEFT")

local function ShowDoomDamage()
    local damage, base, coefficient, multiplier = E.DoomDamage()
    doomDamageLabel:SetText(string.format("= %d damage = (%d + %.1f x spell power) x %.3f", damage + 0.5, base, coefficient, multiplier))
end

local function ApplyDoomSettings()
    local mode = StarWatcherDB.doomWindows or "both"
    E.SetDoomModes(mode == "single" or mode == "both", mode == "both")
    E.SetDoomSpellPower(StarWatcherDB.doomSpellPower or 3000)
end

local doomDefaults = { doomSpellPower = 3000 }
local doomPowerText = strategyPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
doomPowerText:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", 32, -308)
doomPowerText:SetText("Spell power")
local doomPowerBox = CreateFrame("EditBox", "StarWatcherConfigDoomPower", strategyPage, "InputBoxTemplate")
doomPowerBox:SetPoint("LEFT", doomPowerText, "RIGHT", 8, 0)
doomPowerBox:SetWidth(56)
doomPowerBox:SetHeight(20)
doomPowerBox:SetAutoFocus(false)
doomPowerBox:SetNumeric(true)
doomPowerBox:SetMaxLetters(5)
local function CommitDoomPower(self)
    local value = tonumber(self:GetText())
    if value then
        StarWatcherDB.doomSpellPower = value
        ApplyDoomSettings()
        ShowDoomDamage()
    end
end
doomPowerBox:SetScript("OnEnterPressed", function(self)
    CommitDoomPower(self)
    self:ClearFocus()
end)
doomPowerBox:SetScript("OnEditFocusLost", CommitDoomPower)
doomPowerBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)

-- which windows the Doom line shows: none, the one for a single curse, or that one and the one for two warlocks together
local doomModeLabel = strategyPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
doomModeLabel:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", 32, -360)
doomModeLabel:SetText("Doom windows:")
local doomModes = {}
local function ChooseDoomMode(mode)
    StarWatcherDB.doomWindows = mode
    ApplyDoomSettings()
    for name, radio in pairs(doomModes) do
        radio:SetChecked(name == mode)
    end
end
for index, entry in ipairs({ { "none", "None", 112 }, { "single", "Single", 176 }, { "both", "Single and double", 252 } }) do
    local radio = CreateFrame("CheckButton", "StarWatcherConfigDoomMode" .. index, strategyPage, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", strategyPage, "TOPLEFT", entry[3], -356)
    _G["StarWatcherConfigDoomMode" .. index .. "Text"]:SetText(entry[2])
    radio:SetScript("OnClick", function() ChooseDoomMode(entry[1]) end)
    doomModes[entry[1]] = radio
end

-- ---- tab 3: Markers
CreateHeading(markersPage, 28, -8, "Raid markers")
local markRadios = {}
local function ChooseMarkMode(mode)
    StarWatcherDB.markMode = mode
    for name, radio in pairs(markRadios) do
        radio:SetChecked(name == mode)
    end
end
for index, entry in ipairs({ { "off", "No marking", 28 }, { "auto", "Auto", 128 }, { "dynamic", "Dynamic", 200 } }) do
    local radio = CreateFrame("CheckButton", "StarWatcherConfigMarkMode" .. index, markersPage, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", markersPage, "TOPLEFT", entry[3], -24)
    _G["StarWatcherConfigMarkMode" .. index .. "Text"]:SetText(entry[2])
    radio:SetScript("OnClick", function() ChooseMarkMode(entry[1]) end)
    markRadios[entry[1]] = radio
end
CreateHeading(markersPage, 32, -62, "Markers kept free (raid lead):", "GameFontNormalSmall")
local markBoxes = {}
for marker = 1, 8 do
    local column = marker <= 4 and 0 or 1
    local line = (marker - 1) % 4
    local label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. marker .. ":16|t " .. MARK_LABELS[marker]
    markBoxes[marker] = CreateCheckbox("StarWatcherConfigMark" .. marker, markersPage, 26 + column * 180, -78 - line * 24, label, function(checked)
        StarWatcherDB.excludedMarks[marker] = checked or nil
    end)
end

-- on every tab
local footer = config:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("BOTTOMLEFT", config, "BOTTOMLEFT", 28, 18)
footer:SetText("Documentation: see the StarWatcher guide (PDF)")

local function RefreshConfig()
    updating = true
    scaleSlider:SetValue(StarWatcherDB.scale or 1)
    bufferSlider:SetValue(StarWatcherDB.buffer or 6)
    marginSlider:SetValue(StarWatcherDB.spawnMargin or 1)
    smashSlider:SetValue(StarWatcherDB.smashBuffer or 3)
    for seconds, radio in pairs(perfectRadios) do
        radio:SetChecked(seconds == (StarWatcherDB.perfectWindow or 4))
    end
    doomPowerBox:SetText(tostring(StarWatcherDB.doomSpellPower or doomDefaults.doomSpellPower))
    ShowDoomDamage()
    for name, radio in pairs(doomModes) do
        radio:SetChecked(name == (StarWatcherDB.doomWindows or "both"))
    end
    strategyTwo:SetChecked(E.GetStrategy() == 2)
    strategyThree:SetChecked(E.GetStrategy() == 3)
    for name, radio in pairs(markRadios) do
        radio:SetChecked(name == (StarWatcherDB.markMode or "off"))
    end
    windowOpacitySlider:SetValue((StarWatcherDB.windowOpacity or 1) * 100)
    timelineBox:SetChecked(StarWatcherDB.timeline)
    timelineOpacitySlider:SetValue((StarWatcherDB.timelineOpacity or 1) * 100)
    for marker = 1, 8 do
        markBoxes[marker]:SetChecked(StarWatcherDB.excludedMarks[marker])
    end
    updating = false
end

local function ToggleConfig()
    if config:IsShown() then
        config:Hide()
    else
        RefreshConfig()
        ShowTab(currentTab)
        config:Show()
    end
end

autoMarkButton:SetScript("OnClick", function()
    StarWatcherDB.markMode = NextMarkMode(StarWatcherDB.markMode)
    if config:IsShown() then
        RefreshConfig()
    end
end)
configButton:SetScript("OnClick", ToggleConfig)

-- ---------------------------------------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------------------------------------
local function MarkText(marker)
    if marker and marker >= 1 and marker <= 8 then
        return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14|t ", marker)
    end
    return ""
end

local function DrawRow(r, item, now)
    if not item then
        r.name:SetText(Colored("free slot", { 0.4, 0.4, 0.4 }))
        r.slot:SetText("")
        r.death:SetText("")
        r.dev:SetText("")
        r.bar:SetValue(0)
        r.hp:SetText("")
        r.doom:SetText("")
        for j = 1, DOTS do
            r.dots[j]:Hide()
        end
        return
    end
    r.name:SetText(MarkText(item.mark) .. item.name)

    local danger = item.tooClose or item.nearSmash or item.nearBang
    if danger and item.slot then
        r.slot:SetText(Colored(item.slot.name .. " !", RED))
    elseif danger then
        r.slot:SetText(Colored(item.nearBang and "bang !" or (item.nearSmash and "smash !" or "close !"), RED))
    elseif item.state == "ok" then
        r.slot:SetText(Colored(item.slot.name, GREEN))
    elseif item.state == "place" then
        r.slot:SetText(Colored(item.slot.name, YELLOW))
    elseif item.state == "ignore" then
        r.slot:SetText(Colored("ignore", GREY))
    else
        r.slot:SetText(Colored("no slot", RED))
    end

    local deathColor = GREY
    if item.tooClose or item.nearSmash or item.nearBang then
        deathColor = RED
    elseif item.state == "ok" then
        deathColor = GREEN
    end
    r.death:SetText(Colored(string.format("dies %ds", item.deathIn + 0.5), deathColor))
    if item.dev then
        local c = YELLOW
        if math.abs(item.dev) <= item.devLimit then
            c = GREEN
        elseif item.dev < 0 then
            c = RED
        end
        r.dev:SetText(Colored(string.format("%s%s", item.dev >= 0 and "+" or "-", Abbrev(math.abs(item.dev))), c))
    else
        r.dev:SetText("")
    end

    if item.doomText then
        r.doom:SetText(Colored(item.doomText, item.doomColor))
    else
        r.doom:SetText("")
    end

    local c = HealthColor(item.frac)
    r.bar:SetStatusBarColor(c[1], c[2], c[3], item.live and 1 or 0.55)
    r.bar:SetValue(item.frac)
    local pct = string.format("%d%%", item.frac * 100 + 0.5)
    local prefix = item.live and "" or "~"
    if item.hp then
        r.hp:SetText(string.format("%s%s / %s  (%s)", prefix, Num(item.hp), Num(item.max), pct))
    else
        r.hp:SetText(prefix .. pct)
    end

    local n = 0
    if item.auras then
        for _, aura in ipairs(item.auras) do
            local left = aura.expires - now
            if left > 0 and n < DOTS then
                n = n + 1
                local d = r.dots[n]
                d.icon:SetTexture(aura.icon)
                d.timer:SetText(left >= 10 and string.format("%d", left) or string.format("%.1f", left))
                d:Show()
            end
        end
    end
    for j = n + 1, DOTS do
        r.dots[j]:Hide()
    end
end

local function DrawSlot(s, g, T, now)
    if not g then
        s:Hide()
        return
    end
    local timing
    if T < g.opens then
        timing = string.format("in %ds", g.opens - T + 0.5)
    else
        timing = string.format("%ds left", math.max(g.closes - T, 0) + 0.5)
    end
    if g.done > 0 then
        timing = string.format("%d killed, %s", g.done, timing)
    end
    s.label:SetText(Colored(g.label, WHITE))
    s.timing:SetText(Colored(timing, GREY))
    local lines = E.MemberLines(g)
    if #lines > 2 then
        lines[2] = lines[2] .. string.format(" (+%d)", #lines - 2)
    end
    for k = 1, 2 do
        s.lines[k]:SetText(lines[k] or "")
    end
    s.fill:SetTexture(g.filled and TICK or CROSS)
    s.space:SetTexture(g.spaced and TICK or CROSS)
    s:Show()
end


local glowRow = nil

local function Draw(model, now)
    local tasks = model.tasks
    for i = 1, MAX_TASKS do
        local task = tasks[i]
        if task and i == MAX_TASKS and #tasks > MAX_TASKS then
            task = { text = string.format("%s  (+%d more)", task.text, #tasks - MAX_TASKS), color = task.color, action = task.action }
        end
        if task then
            local bullet = task.action and "\226\128\162 " or ""
            taskLines[i]:SetText(bullet .. task.text)
            taskLines[i]:SetTextColor(task.color[1], task.color[2], task.color[3])
        else
            taskLines[i]:SetText("")
        end
    end
    sub:SetText(model.sub)
    local targetGUID = UnitGUID("target")
    local focusGUID = UnitGUID("focus")
    glowRow = nil
    for i = 1, E.MAX_STARS do
        local item = model.rows[i]
        DrawRow(rows[i], item, now)
        if item and item.guid and (item.guid == targetGUID or item.guid == focusGUID) then
            glowRow = rows[i]
            rows[i].glow:Show()
        else
            rows[i].glow:Hide()
        end
    end
    SW.Rolling.Draw(model, now, unlocked, config:IsShown())
    for i = 1, SLOT_ROWS do
        DrawSlot(slots[i], model.groups[i], model.T or 0, now)
    end
    UpdateAutoMarkButton()
    if model.active or unlocked or config:IsShown() then
        frame:Show()
    else
        frame:Hide()
    end
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- Finding the stars: the group's targets, and the player's own units
-- ---------------------------------------------------------------------------------------------------------------------------
local OWN_UNITS = { "target", "focus", "mouseover", "targettarget" }
local groupTargets = {}

local function RebuildGroupTargets()
    for i = #groupTargets, 1, -1 do
        groupTargets[i] = nil
    end
    local raid = GetNumRaidMembers()
    if raid > 0 then
        for i = 1, raid do
            groupTargets[#groupTargets + 1] = "raid" .. i .. "target"
        end
        return
    end
    for i = 1, GetNumPartyMembers() do
        groupTargets[#groupTargets + 1] = "party" .. i .. "target"
    end
end

local function Refresh()
    local now = GetTime()
    E.Poll(groupTargets, now)
    E.BeginScan()
    for i = 1, #OWN_UNITS do
        E.Observe(OWN_UNITS[i], now)
    end
    for i = 1, #groupTargets do
        E.Observe(groupTargets[i], now)
    end
    local model = E.Update(now)
    Draw(model, now)
    SW.DynamicMark(model, now)
end

-- the windows are shown while the configuration is open (to place them) and go away when it closes, unless a fight is on
config:SetScript("OnShow", Refresh)
config:SetScript("OnHide", Refresh)

local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if glowRow then
        glowRow.glow:SetAlpha(0.3 + 0.7 * (0.5 + 0.5 * math.sin(GetTime() * 7)))
    end
    since = since + elapsed
    if since >= UPDATE_INTERVAL then
        since = 0
        Refresh()
    end
end)

local function SavePosition()
    StarWatcherDB.left = frame:GetLeft()
    StarWatcherDB.top = frame:GetTop()
end

local function RestorePosition()
    if StarWatcherDB.left and StarWatcherDB.top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", StarWatcherDB.left, StarWatcherDB.top)
    end
    frame:SetScale(StarWatcherDB.scale or 1)
    frame:SetAlpha(StarWatcherDB.windowOpacity or 1)
end

frame:SetScript("OnDragStart", function(self)
    if unlocked or config:IsShown() or IsShiftKeyDown() then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PARTY_MEMBERS_CHANGED")
driver:RegisterEvent("RAID_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("CHAT_MSG_MONSTER_YELL")
driver:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- the damage events of the combat log, and the position of the amount after the 8 common fields
local DAMAGE_EVENTS = { SWING_DAMAGE = 1, RANGE_DAMAGE = 4, SPELL_DAMAGE = 4, SPELL_PERIODIC_DAMAGE = 4, DAMAGE_SHIELD = 4, DAMAGE_SPLIT = 4 }

local function OnCombatLog(timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
    local now = GetTime()
    E.OnHit(sourceName, destName, now)
    -- anything that involves the stars or Algalon shows that the fight goes on; Algalon dying ends it
    if destName == STAR_NAME or sourceName == STAR_NAME or (sourceName and string.find(sourceName, "Algalon", 1, true))
        or (destName and string.find(destName, "Algalon", 1, true)) then
        E.Touch(now)
        if subevent == "UNIT_DIED" and destName and string.find(destName, "Algalon", 1, true) then
            E.Disarm()
            return
        end
    end
    if destName == STAR_NAME then
        if subevent == "UNIT_DIED" then
            E.OnStarDeath(destGUID, now)
        else
            local position = DAMAGE_EVENTS[subevent]
            if position then
                E.OnStarDamage(destGUID, (select(position, ...)), now)
            end
            if subevent == "SPELL_PERIODIC_DAMAGE" then
                E.LearnDot((select(2, ...)))
            end
        end
    end
    if subevent == "SPELL_CAST_START" then
        E.OnCast(sourceName, (select(2, ...)))
    end
    if subevent == "SPELL_CAST_SUCCESS" and (select(2, ...)) == "Cosmic Smash" then
        E.OnSmash(now)
    end
end

driver:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog(...)
    elseif event == "CHAT_MSG_MONSTER_YELL" then
        E.OnYell((...), select(2, ...), GetTime())
    elseif event == "PLAYER_TARGET_CHANGED" then
        AutoMarkTarget()
    elseif event == "PLAYER_REGEN_DISABLED" then
        E.Arm()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not UnitIsDeadOrGhost("player") then
            E.Disarm()
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        RebuildGroupTargets()
    elseif event == "ADDON_LOADED" then
        if ... ~= "StarWatcher" then
            return
        end
        StarWatcherDB = StarWatcherDB or {}
        StarWatcherDB.buffer = StarWatcherDB.buffer or 6
        StarWatcherDB.strategy = StarWatcherDB.strategy or 2
        E.SetStrategy(StarWatcherDB.strategy)
        UpdateStrategyLine()
        StarWatcherDB.excludedMarks = StarWatcherDB.excludedMarks or {}
        if StarWatcherDB.markMode == nil then
            StarWatcherDB.markMode = StarWatcherDB.autoMark and "auto" or "off"
        end
        StarWatcherDB.autoMark = nil
        E.SetBuffer(StarWatcherDB.buffer)
        StarWatcherDB.spawnMargin = StarWatcherDB.spawnMargin or 1
        StarWatcherDB.smashBuffer = StarWatcherDB.smashBuffer or 3
        E.SetSmashBuffer(StarWatcherDB.smashBuffer)
        E.SetPerfectWindow(StarWatcherDB.perfectWindow)
        E.SetChat(StarWatcherDB.chat)
        for key, value in pairs(doomDefaults) do
            StarWatcherDB[key] = StarWatcherDB[key] or value
        end
        StarWatcherDB.doomShadowMastery, StarWatcherDB.doomMalediction = nil, nil
        ApplyDoomSettings()
        E.SetSpawnMargin(StarWatcherDB.spawnMargin)
        RestorePosition()
        SW.Rolling.Init()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ---------------------------------------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------------------------------------
local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99StarWatcher|r: " .. text)
end

SLASH_STARWATCHER1 = "/sw"
SLASH_STARWATCHER2 = "/starwatcher"
SlashCmdList["STARWATCHER"] = function(input)
    local command, argument = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "unlock" then
        unlocked = true
        Print("unlocked: drag the window to move it, /sw lock when done")
    elseif command == "lock" then
        unlocked = false
        Print("locked")
    elseif command == "scale" then
        local scale = tonumber(argument)
        if scale and scale >= 0.5 and scale <= 2 then
            StarWatcherDB.scale = scale
            frame:SetScale(scale)
        else
            Print("usage: /sw scale 0.5 to 2")
        end
    elseif command == "opacity" then
        local percent = tonumber(argument)
        if percent and percent >= 20 and percent <= 100 then
            StarWatcherDB.windowOpacity = percent / 100
            frame:SetAlpha(percent / 100)
            if config:IsShown() then
                RefreshConfig()
            end
        else
            Print("usage: /sw opacity 20 to 100 (main window, " .. math.floor((StarWatcherDB.windowOpacity or 1) * 100 + 0.5) .. " now)")
        end
    elseif command == "buffer" then
        local seconds = tonumber(argument)
        if seconds and seconds >= 0 and seconds <= 20 then
            StarWatcherDB.buffer = seconds
            E.SetBuffer(seconds)
            Print("Big Bang and star buffer: " .. seconds .. " s")
        else
            Print("usage: /sw buffer 0 to 20 (seconds, " .. E.GetBuffer() .. " now)")
        end
    elseif command == "perfect" then
        local seconds = tonumber(argument)
        if seconds == 2 or seconds == 3 or seconds == 4 then
            ChoosePerfect(seconds)
            Print("perfect window: " .. seconds .. " s")
        else
            Print("usage: /sw perfect 2 | 3 | 4 (" .. E.GetPerfectWindow() .. " now)")
        end
    elseif command == "test" then
        local at = tonumber(argument) or 20
        E.BeginAt(GetTime() - at, "a test (" .. at .. " s into the fight)", true)
    elseif command == "automark" then
        local lowered = string.lower(argument)
        if lowered == "on" then
            lowered = "auto"
        end
        if lowered == "off" or lowered == "auto" or lowered == "dynamic" then
            StarWatcherDB.markMode = lowered
        else
            StarWatcherDB.markMode = NextMarkMode(StarWatcherDB.markMode)
        end
        if config:IsShown() then
            RefreshConfig()
        end
        Print("marking: " .. StarWatcherDB.markMode)
    elseif command == "strategy" then
        local n = tonumber(argument)
        if n == 2 or n == 3 then
            ChooseStrategy(n)
            Print("strategy: " .. n .. " stars")
        else
            Print("usage: /sw strategy 2 | 3 (" .. E.GetStrategy() .. " now)")
        end
    elseif command == "chat" then
        local lowered = string.lower(argument)
        if lowered == "on" then
            StarWatcherDB.chat = true
        elseif lowered == "off" then
            StarWatcherDB.chat = false
        else
            StarWatcherDB.chat = not StarWatcherDB.chat
        end
        E.SetChat(StarWatcherDB.chat)
        Print("messages about the fight " .. (StarWatcherDB.chat and "on" or "off"))
    elseif command == "timeline" then
        local lowered = string.lower(argument)
        if lowered == "on" then
            StarWatcherDB.timeline = true
        elseif lowered == "off" then
            StarWatcherDB.timeline = false
        else
            StarWatcherDB.timeline = not StarWatcherDB.timeline
        end
        Print("rolling timeline " .. (StarWatcherDB.timeline and "on" or "off"))
    elseif command == "doomwindow" then
        local which = string.lower(argument)
        if which == "single" or which == "both" or which == "none" then
            ChooseDoomMode(which)
            Print("Doom windows shown: " .. which)
        else
            Print("usage: /sw doomwindow none | single | both")
        end
    elseif command == "doom" then
        local power = tonumber(argument)
        if power and power >= 0 then
            StarWatcherDB.doomSpellPower = power
            E.SetDoomSpellPower(power)
            ApplyDoomSettings()
            Print(string.format("Curse of Doom: %d damage with %d spell power", E.DoomDamage() + 0.5, power))
        else
            Print(string.format("usage: /sw doom <spell power> (%d now, %d damage)", E.GetDoomSpellPower(), E.DoomDamage() + 0.5))
        end
    elseif command == "smash" then
        local seconds = tonumber(argument)
        if seconds and seconds >= 0 and seconds <= 6 then
            StarWatcherDB.smashBuffer = seconds
            E.SetSmashBuffer(seconds)
            Print("Cosmic Smash buffer: " .. seconds .. " s")
        else
            Print("usage: /sw smash 0 to 6 (seconds, 0 = off, " .. E.GetSmashBuffer() .. " now)")
        end
    elseif command == "spawn" then
        local seconds = tonumber(argument)
        if seconds and seconds >= 0 and seconds <= 5 then
            StarWatcherDB.spawnMargin = seconds
            E.SetSpawnMargin(seconds)
            Print("star spawn buffer: " .. seconds .. " s")
        else
            Print("usage: /sw spawn 0 to 5 (seconds, " .. E.GetSpawnMargin() .. " now)")
        end
    elseif command == "marks" or command == "config" then
        ToggleConfig()
    elseif command == "reset" then
        E.Disarm()
        Print("reset")
    else
        Print("/sw config | scale <n> | opacity <20-100> | buffer <s> | spawn <s> | smash <s> | perfect 2|3|4 | strategy 2|3 | doom <spell power> | doomwindow none|single|both | automark [off|auto|dynamic] | timeline [on|off] | chat [on|off] | test [seconds] | reset (the guide PDF lists them all)")
    end
end
