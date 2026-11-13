StarWatcher = StarWatcher or {}
local SW = StarWatcher
local E = SW.Engine

-- The rolling timeline: a wide, thin window that scrolls with the fight. "now" stays at a fixed place; from the top:
--   1. the names of the windows
--   2. the safe windows (green, yellow for the perfect windows of the Big Bangs)
--   3. the events of the fight, as points: the spawn of the stars, the start of a Cosmic Smash, the start of a Big Bang
--   4. the star placements: a pointer at the exact moment each star dies, with its mark and name under it
--   and the fight time under it all.
local R = {}
SW.Rolling = R

local WIDTH, HEIGHT = 800, 86
local PAD = 6
local BEHIND, AHEAD = 30, 90          -- seconds shown behind and ahead of now
local SPAN = BEHIND + AHEAD
local FONT = "Fonts\\FRIZQT__.TTF"

-- the rows, from the top of the window
local NAMES_TOP = 4
local WINDOWS_TOP, WINDOWS_H = 17, 12
local EVENTS_TOP, EVENTS_H = 31, 12
local POINTER_TOP = 46                -- the apex of the pointers
local LABELS_TOP = 58
local AXIS_TOP = 72

local GREEN = { 0.24, 0.67, 0.31 }
local YELLOW = { 1, 0.8, 0.24 }
local POINTER_GREEN = { 0.2, 1, 0.2 }
local POINTER_RED = { 1, 0.25, 0.25 }
local POINTER_YELLOW = { 1, 0.85, 0.2 }
local POINTER_PURPLE = { 0.75, 0.5, 1 }
local POINTER_GREY = { 0.65, 0.65, 0.65 }

local frame = CreateFrame("Frame", "StarWatcherTimeline", UIParent)
frame:SetWidth(WIDTH)
frame:SetHeight(HEIGHT)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -230)
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
frame:SetBackdropColor(0, 0, 0, 1)
frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
frame:Hide()

-- How much of the background shows: 1 is completely opaque (the default), less lets you see through the background, the lanes and the
-- windows; the text, the icons and the pointers stay solid.
local opacity = 1
function R.SetOpacity(value)
    opacity = math.max(0.2, math.min(tonumber(value) or 1, 1))
    frame:SetBackdropColor(0, 0, 0, opacity)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.4 + 0.6 * opacity)
end

local rects, labels = {}, {}
local usedRects, usedLabels = 0, 0

-- a coloured rectangle (layer: "ARTWORK" under, "OVERLAY" over)
local function Rect(x1, x2, top, height, color, alpha, layer)
    usedRects = usedRects + 1
    local tex = rects[usedRects]
    if not tex then
        tex = frame:CreateTexture(nil, "ARTWORK")
        rects[usedRects] = tex
    end
    tex:SetDrawLayer(layer or "ARTWORK")
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, -top)
    tex:SetWidth(math.max(x2 - x1, 1))
    tex:SetHeight(height)
    tex:SetTexture(color[1], color[2], color[3], alpha or 0.85)
    tex:Show()
end

local function Label(x, top, text, size, color, anchor)
    usedLabels = usedLabels + 1
    local fs = labels[usedLabels]
    if not fs then
        fs = frame:CreateFontString(nil, "OVERLAY")
        labels[usedLabels] = fs
    end
    fs:SetFont(FONT, size or 9, "OUTLINE")
    fs:ClearAllPoints()
    fs:SetPoint(anchor or "TOP", frame, "TOPLEFT", x, -top)
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:Show()
end

-- the icons of the events come from the game: the icon of the spell, by its id
local ICON_SIZE = 12
local icons = nil
local function ResolveIcons()
    local function spellIcon(id)
        local _, _, icon = GetSpellInfo(id)
        return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    icons = {
        bang = spellIcon(64584),         -- Big Bang
        smash = spellIcon(64596),        -- Cosmic Smash
        star = "Interface\\Icons\\INV_Enchant_EssenceCosmicGreater",    -- Collapsing Star (as in DBM)
    }
end

local iconTextures, usedIcons = {}, 0
-- an icon centred on x, in a row
local function Icon(path, x, top, size)
    usedIcons = usedIcons + 1
    local tex = iconTextures[usedIcons]
    if not tex then
        tex = frame:CreateTexture(nil, "OVERLAY")
        iconTextures[usedIcons] = tex
    end
    tex:SetDrawLayer("OVERLAY")
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x - size / 2, -top)
    tex:SetWidth(size)
    tex:SetHeight(size)
    tex:SetTexture(path)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetAlpha(0.95)
    tex:Show()
end

local function MarkText(marker)
    if marker and marker >= 1 and marker <= 8 then
        return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:12|t", marker)
    end
    return ""
end

-- A pointer: a small inverted V, 10 px high, whose apex is on x and whose base is about 12 px wide. One-pixel rows, each wider than the one
-- above, with a fainter fringe a pixel wider under each row to soften the edges.
local POINTER_ROWS = 10
local function Pointer(x, color)
    for k = 0, POINTER_ROWS - 1 do
        local half = 0.5 + k * 0.61
        local top = POINTER_TOP + k
        Rect(x - half - 1, x + half + 1, top, 1, color, 0.4, "OVERLAY")
        Rect(x - half, x + half, top, 1, color, 1, "OVERLAY")
    end
end

-- the colour of the pointer of a star, from where its death falls
local function PointerColor(item)
    if not item.committed then
        return POINTER_GREY          -- left alone: its time is no plan
    elseif item.doom and item.doom.state == "kills" then
        return POINTER_PURPLE        -- a good Doom
    elseif item.tooClose or item.nearSmash or item.nearBang then
        return POINTER_RED
    elseif item.inPerfect then
        return POINTER_YELLOW        -- in a perfect window
    elseif item.claimed then
        return POINTER_GREEN         -- in the right spot
    end
    return POINTER_RED               -- aimed, but not in any safe window
end

-- preview: the configuration window is open, the timeline is shown (at 25 s of an idle fight) whatever the option says, to be placed
function R.Draw(model, now, unlocked, preview)
    local enabled = StarWatcherDB and StarWatcherDB.timeline
    if not preview and (not enabled or not (model.active or unlocked)) then
        frame:Hide()
        return
    end
    frame:Show()
    local T = model.T or 25            -- (outside a fight, to place the window: the situation at 25 s)
    local t0 = T - BEHIND
    local inner = WIDTH - 2 * PAD
    local function X(t)
        return PAD + (t - t0) / SPAN * inner
    end
    -- a stretch of time (fight seconds) as the two ends of a rectangle, cut to what is shown; nil if it is not in view
    local function Span(a, b)
        local lo, hi = math.max(a, t0), math.min(b, T + AHEAD)
        if hi <= lo then
            return nil
        end
        return X(lo), X(hi)
    end
    local function InView(t)
        return t >= t0 and t <= T + AHEAD
    end

    usedRects, usedLabels, usedIcons = 0, 0, 0
    if not icons then
        ResolveIcons()
    end
    local data = E.TimelineData()

    -- 1 and 2: the windows and their names; every perfect window is there, whether the strategy uses it or not
    Rect(PAD, WIDTH - PAD, WINDOWS_TOP, WINDOWS_H, { 0.14, 0.14, 0.17 }, opacity)
    local drawn = {}
    local function Window(name, from, to, perfect)
        local x1, x2 = Span(from, to)
        if x1 then
            Rect(x1, x2, WINDOWS_TOP, WINDOWS_H, perfect and YELLOW or GREEN, opacity)
            if x2 - x1 > (perfect and 18 or 26) then
                Label((x1 + x2) / 2, NAMES_TOP, name, 9, perfect and { 1, 0.9, 0.5 } or { 0.75, 1, 0.75 })
            end
        end
    end
    for _, win in ipairs(data.windows) do
        Window(win.name, win.from, win.to, win.perfect)
        if win.perfect then
            drawn[win.name] = true
        end
    end
    for k, bang in ipairs(data.bangs) do
        if not drawn["BB" .. k] then
            Window("BB" .. k, bang.perfectFrom, bang.to, true)
        end
    end

    -- 3: the events, as points
    for _, bang in ipairs(data.bangs) do
        if InView(bang.from) then
            Icon(icons.bang, X(bang.from), EVENTS_TOP, ICON_SIZE)
        end
    end
    for _, start in ipairs(data.smashes) do
        if InView(start) then
            Icon(icons.smash, X(start), EVENTS_TOP, ICON_SIZE)
        end
    end
    for _, at in ipairs(data.spawns) do
        if InView(at) then
            Icon(icons.star, X(at), EVENTS_TOP, ICON_SIZE)
        end
    end

    -- 4: where the stars die
    for i = 1, E.MAX_STARS do
        local item = model.rows[i]
        if item and not item.ignored and InView(item.at) then
            local color = PointerColor(item)
            local x = X(item.at)
            Pointer(x, color)
            Label(x, LABELS_TOP, MarkText(item.mark) .. string.format("%d-%d", item.wave, item.index), 9, color)
        end
    end

    -- the axis: the fight time, a mark every 10 s and its time every 30 s; and now
    local xNow = X(T)
    for t = math.ceil(t0 / 10) * 10, T + AHEAD, 10 do
        local x = X(t)
        Rect(x, x + 1, AXIS_TOP, (t % 30 == 0) and 5 or 3, { 0.55, 0.55, 0.55 }, 1)
        if t % 30 == 0 and t >= 0 and math.abs(x - xNow) > 24 then
            Label(x, AXIS_TOP + 5, string.format("%d:%02d", t / 60, t % 60), 8, { 0.7, 0.7, 0.7 })
        end
    end
    Rect(xNow - 1, xNow + 1, NAMES_TOP + 10, AXIS_TOP - NAMES_TOP - 6, { 1, 1, 1 }, 0.8, "OVERLAY")
    Label(xNow, AXIS_TOP + 5, string.format("%d:%02d", T / 60, T % 60), 8, { 1, 1, 1 })

    for i = usedRects + 1, #rects do
        rects[i]:Hide()
    end
    for i = usedLabels + 1, #labels do
        labels[i]:Hide()
    end
    for i = usedIcons + 1, #iconTextures do
        iconTextures[i]:Hide()
    end
end

-- placing it: Shift + drag, like the main window
function R.Init()
    if StarWatcherDB.tlLeft and StarWatcherDB.tlTop then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", StarWatcherDB.tlLeft, StarWatcherDB.tlTop)
    end
    frame:SetScale(StarWatcherDB.scale or 1)
    R.SetOpacity(StarWatcherDB.timelineOpacity or 1)
end

function R.SetScale(scale)
    frame:SetScale(scale)
end

frame:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() or (SW.UI and SW.UI.IsUnlocked and SW.UI.IsUnlocked()) then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if StarWatcherDB then
        StarWatcherDB.tlLeft = self:GetLeft()
        StarWatcherDB.tlTop = self:GetTop()
    end
end)
