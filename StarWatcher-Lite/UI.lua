local SW = StarWatcherLite
local E = SW.Engine

local ADDON_NAME = "StarWatcher-Lite"
local VERSION = "1.0.7"
local WIDTH = 290
local PAD = 8
local ROW_H = 34
local HEADER_H = 12
local BAR_W = WIDTH - 2 * PAD
local UPDATE_INTERVAL = 0.1
local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local ROWS_TOP = 8 + HEADER_H + 18 + 6
local HEIGHT = ROWS_TOP + E.MAX_STARS * ROW_H + 6

local DEFAULT_SCALE = 1

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

local function Colored(text, c)
    return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local GREY = { 0.65, 0.65, 0.65 }
local YELLOW = { 1, 0.85, 0.2 }

-- ---------------------------------------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "StarWatcherLiteFrame", UIParent)
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

-- the state of the fight, and under it the next Big Bang, stars and smash
local headerLine = Text(frame, 10, "LEFT", WIDTH - 2 * PAD)
headerLine:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -8)
headerLine:SetHeight(HEADER_H)
local sub = Text(frame, 11, "LEFT", WIDTH - 2 * PAD)
sub:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(8 + HEADER_H + 4))
sub:SetHeight(HEADER_H + 2)
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
    r.name:SetHeight(12)
    r.death = Text(r, 10, "LEFT", 54)
    r.death:SetPoint("TOPLEFT", r, "TOPLEFT", 72, 0)
    r.death:SetHeight(12)
    r.verdict = Text(r, 10, "RIGHT", BAR_W - 126)
    r.verdict:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.verdict:SetHeight(12)

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
    r.hp = Text(r.bar, 9, "LEFT", BAR_W - 8)
    r.hp:SetPoint("LEFT", r.bar, "LEFT", 4, 0)

    rows[i] = r
end

local configButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
configButton:SetWidth(46)
configButton:SetHeight(18)
configButton:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
configButton:SetNormalFontObject(GameFontNormalSmall)
configButton:SetHighlightFontObject(GameFontHighlightSmall)
configButton:SetText("Config")

local title = frame:CreateFontString(nil, "OVERLAY")
title:SetFont(FONT, 11, "OUTLINE")
title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 2, 4)
title:SetText("|cff33ff99StarWatcher Lite|r |cffaaaaaa" .. VERSION .. "|r")

-- ---------------------------------------------------------------------------------------------------------------------------
-- The configuration window: settings and the fight
-- ---------------------------------------------------------------------------------------------------------------------------
local config = CreateFrame("Frame", "StarWatcherLiteConfig", UIParent)
config:SetWidth(490)
config:SetHeight(346)
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

tinsert(UISpecialFrames, "StarWatcherLiteConfig")
local configTitle = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
configTitle:SetPoint("TOP", config, "TOP", 0, -16)
configTitle:SetText("StarWatcher Lite " .. VERSION)
local configClose = CreateFrame("Button", nil, config, "UIPanelCloseButton")
configClose:SetPoint("TOPRIGHT", config, "TOPRIGHT", -5, -5)

local settingsPage = CreateFrame("Frame", nil, config)
settingsPage:SetPoint("TOPLEFT", config, "TOPLEFT", 0, -40)
settingsPage:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", 0, 0)

local updating = false
local unlocked = false

local function CreateSlider(name, y, label, low, high, step, format, onChange)
    local slider = CreateFrame("Slider", name, settingsPage, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", settingsPage, "TOPLEFT", 28, y)
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

local scaleSlider = CreateSlider("StarWatcherLiteConfigScale", -14, "Scale", 0.5, 2, 0.05, "%.2f", function(value)
    StarWatcherLiteDB.scale = value
    frame:SetScale(value)
end)
local bufferSlider = CreateSlider("StarWatcherLiteConfigBuffer", -58, "Big Bang and star buffer (seconds)", 0, 20, 1, "%d", function(value)
    StarWatcherLiteDB.buffer = value
    E.SetBuffer(value)
end)
local smashSlider = CreateSlider("StarWatcherLiteConfigSmash", -102, "Cosmic Smash buffer (seconds, 0 = off)", 0, 6, 0.5, "%.1f", function(value)
    StarWatcherLiteDB.smashBuffer = value
    E.SetSmashBuffer(value)
end)

-- the whole window: every element of it, not only the background
local opacitySlider = CreateSlider("StarWatcherLiteConfigOpacity", -146, "Window opacity (%)", 20, 100, 5, "%d", function(value)
    StarWatcherLiteDB.windowOpacity = value / 100
    frame:SetAlpha(value / 100)
end)

-- the perfect window: 2, 3 or 4 seconds before the end of the Big Bang cast
local perfectHeading = settingsPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
perfectHeading:SetPoint("TOPLEFT", settingsPage, "TOPLEFT", 28, -190)
perfectHeading:SetText("Perfect window (seconds before the end of the Big Bang cast)")
local perfectRadios = {}
local function ChoosePerfect(n)
    StarWatcherLiteDB.perfectWindow = n
    E.SetPerfectWindow(n)
    for seconds, radio in pairs(perfectRadios) do
        radio:SetChecked(seconds == E.GetPerfectWindow())
    end
end
for index, entry in ipairs({ { 2, "2 s", 28 }, { 3, "3 s", 98 }, { 4, "4 s", 168 } }) do
    local radio = CreateFrame("CheckButton", "StarWatcherLiteConfigPerfect" .. index, settingsPage, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", settingsPage, "TOPLEFT", entry[3], -206)
    _G["StarWatcherLiteConfigPerfect" .. index .. "Text"]:SetText(entry[2])
    radio:SetScript("OnClick", function() ChoosePerfect(entry[1]) end)
    perfectRadios[entry[1]] = radio
end

local function RefreshConfig()
    updating = true
    scaleSlider:SetValue(StarWatcherLiteDB.scale or DEFAULT_SCALE)
    bufferSlider:SetValue(StarWatcherLiteDB.buffer or E.DEFAULT_BUFFER)
    smashSlider:SetValue(StarWatcherLiteDB.smashBuffer or E.DEFAULT_SMASH_BUFFER)
    opacitySlider:SetValue((StarWatcherLiteDB.windowOpacity or 1) * 100)
    for seconds, radio in pairs(perfectRadios) do
        radio:SetChecked(seconds == (StarWatcherLiteDB.perfectWindow or E.DEFAULT_PERFECT_WINDOW))
    end
    updating = false
end

local defaultsButton = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
defaultsButton:SetWidth(130)
defaultsButton:SetHeight(22)
defaultsButton:SetPoint("TOPLEFT", settingsPage, "TOPLEFT", 28, -240)
defaultsButton:SetNormalFontObject(GameFontNormalSmall)
defaultsButton:SetHighlightFontObject(GameFontHighlightSmall)
defaultsButton:SetText("Reset to defaults")
defaultsButton:SetScript("OnClick", function()
    StarWatcherLiteDB.scale = DEFAULT_SCALE
    StarWatcherLiteDB.buffer = E.DEFAULT_BUFFER
    StarWatcherLiteDB.smashBuffer = E.DEFAULT_SMASH_BUFFER
    StarWatcherLiteDB.perfectWindow = E.DEFAULT_PERFECT_WINDOW
    StarWatcherLiteDB.windowOpacity = 1
    frame:SetScale(DEFAULT_SCALE)
    frame:SetAlpha(1)
    E.SetBuffer(E.DEFAULT_BUFFER)
    E.SetSmashBuffer(E.DEFAULT_SMASH_BUFFER)
    E.SetPerfectWindow(E.DEFAULT_PERFECT_WINDOW)
    RefreshConfig()
end)

local footer = settingsPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("TOPLEFT", settingsPage, "TOPLEFT", 28, -274)
footer:SetText("Documentation: see the StarWatcher guide (PDF)")

local function ToggleConfig()
    if config:IsShown() then
        config:Hide()
    else
        RefreshConfig()
        config:Show()
    end
end

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

local function DrawRow(r, item)
    if not item then
        r.name:SetText(Colored("free slot", { 0.4, 0.4, 0.4 }))
        r.death:SetText("")
        r.verdict:SetText("")
        r.bar:SetValue(0)
        r.hp:SetText("")
        return
    end
    r.name:SetText(MarkText(item.mark) .. item.name)
    r.death:SetText(Colored(string.format("dies %ds", item.deathIn + 0.5), item.verdictColor))
    r.verdict:SetText(Colored(item.verdict, item.verdictColor))

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
end

local glowRow = nil

local function Draw(model)
    headerLine:SetText(model.header)
    headerLine:SetTextColor(model.headerColor[1], model.headerColor[2], model.headerColor[3])
    sub:SetText(model.sub)
    local targetGUID = UnitGUID("target")
    local focusGUID = UnitGUID("focus")
    glowRow = nil
    for i = 1, E.MAX_STARS do
        local item = model.rows[i]
        DrawRow(rows[i], item)
        if item and item.guid and (item.guid == targetGUID or item.guid == focusGUID) then
            glowRow = rows[i]
            rows[i].glow:Show()
        else
            rows[i].glow:Hide()
        end
    end
    if model.active or unlocked or config:IsShown() then
        frame:Show()
    else
        frame:Hide()
    end
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- Finding the stars: the group's targets, and the player's own units
-- ---------------------------------------------------------------------------------------------------------------------------
local STAR_NAME = "Collapsing Star"
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
    Draw(E.Update(now))
end

-- the window is shown while the configuration is open (to place it) and goes away when it closes, unless a fight is on
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
    StarWatcherLiteDB.left = frame:GetLeft()
    StarWatcherLiteDB.top = frame:GetTop()
end

local function RestorePosition()
    if StarWatcherLiteDB.left and StarWatcherLiteDB.top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", StarWatcherLiteDB.left, StarWatcherLiteDB.top)
    end
    frame:SetScale(StarWatcherLiteDB.scale or DEFAULT_SCALE)
    frame:SetAlpha(StarWatcherLiteDB.windowOpacity or 1)
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
    elseif event == "PLAYER_REGEN_DISABLED" then
        E.Arm()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not UnitIsDeadOrGhost("player") then
            E.Disarm()
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        RebuildGroupTargets()
    elseif event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then
            return
        end
        StarWatcherLiteDB = StarWatcherLiteDB or {}
        StarWatcherLiteDB.buffer = StarWatcherLiteDB.buffer or E.DEFAULT_BUFFER
        StarWatcherLiteDB.smashBuffer = StarWatcherLiteDB.smashBuffer or E.DEFAULT_SMASH_BUFFER
        E.SetBuffer(StarWatcherLiteDB.buffer)
        E.SetSmashBuffer(StarWatcherLiteDB.smashBuffer)
        E.SetPerfectWindow(StarWatcherLiteDB.perfectWindow)
        RestorePosition()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ---------------------------------------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------------------------------------
local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99StarWatcher Lite|r: " .. text)
end

SLASH_STARWATCHERLITE1 = "/swl"
SlashCmdList["STARWATCHERLITE"] = function(input)
    local command, argument = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "unlock" then
        unlocked = true
        Print("unlocked: drag the window to move it, /swl lock when done")
    elseif command == "lock" then
        unlocked = false
        Print("locked")
    elseif command == "scale" then
        local scale = tonumber(argument)
        if scale and scale >= 0.5 and scale <= 2 then
            StarWatcherLiteDB.scale = scale
            frame:SetScale(scale)
        else
            Print("usage: /swl scale 0.5 to 2")
        end
    elseif command == "opacity" then
        local percent = tonumber(argument)
        if percent and percent >= 20 and percent <= 100 then
            StarWatcherLiteDB.windowOpacity = percent / 100
            frame:SetAlpha(percent / 100)
            RefreshConfig()
        else
            Print("usage: /swl opacity 20 to 100 (" .. math.floor((StarWatcherLiteDB.windowOpacity or 1) * 100 + 0.5) .. " now)")
        end
    elseif command == "buffer" then
        local seconds = tonumber(argument)
        if seconds and seconds >= 0 and seconds <= 20 then
            StarWatcherLiteDB.buffer = seconds
            E.SetBuffer(seconds)
            Print("Big Bang and star buffer: " .. seconds .. " s")
        else
            Print("usage: /swl buffer 0 to 20 (seconds, " .. E.GetBuffer() .. " now)")
        end
    elseif command == "smash" then
        local seconds = tonumber(argument)
        if seconds and seconds >= 0 and seconds <= 6 then
            StarWatcherLiteDB.smashBuffer = seconds
            E.SetSmashBuffer(seconds)
            Print("Cosmic Smash buffer: " .. seconds .. " s")
        else
            Print("usage: /swl smash 0 to 6 (seconds, 0 = off, " .. E.GetSmashBuffer() .. " now)")
        end
    elseif command == "perfect" then
        local seconds = tonumber(argument)
        if seconds == 2 or seconds == 3 or seconds == 4 then
            ChoosePerfect(seconds)
            Print("perfect window: " .. seconds .. " s")
        else
            Print("usage: /swl perfect 2 | 3 | 4 (" .. E.GetPerfectWindow() .. " now)")
        end
    elseif command == "test" then
        local at = tonumber(argument) or 20
        E.BeginAt(GetTime() - at, "a test (" .. at .. " s into the fight)", true)
        Print("test fight started " .. at .. " s in; /swl reset to stop it")
    elseif command == "config" then
        ToggleConfig()
    elseif command == "reset" then
        E.Disarm()
        Print("reset")
    else
        Print("/swl config | scale <n> | opacity <20-100> | buffer <s> | smash <s> | perfect 2|3|4 | test [seconds] | reset (the guide PDF lists them all)")
    end
end
