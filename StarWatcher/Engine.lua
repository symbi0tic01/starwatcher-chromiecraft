StarWatcher = StarWatcher or {}
local SW = StarWatcher

local E = {}
SW.Engine = E

local STAR_NAME = "Collapsing Star"
local BOSS_NAME = "Algalon"
local BIG_BANG_NAME = "Big Bang"

-- ---------------------------------------------------------------------------------------------------------------------------
-- The fight, in fight time T (seconds after the roleplay ends and Algalon goes for the raid). Big Bangs start at T = 90, 180, 270 and last
-- 8 s (the last 2 to 4 s, a setting, are the "perfect window": stars may die together there); the enrage is at 360. A wave of stars spawns at T = 16.5 and
-- every 60 s after, and brings the number of living stars back to 4; a star left alone dies 100 s after it spawned (it loses 1% of its
-- health each second). Waves from the 5th on are ignored: their stars die too close to the enrage.
-- ---------------------------------------------------------------------------------------------------------------------------
local PULL_YELL = "your actions are illogical" -- matched on a part of the yell, in lower case
local RP_FIRST_PULL = 26    -- seconds of roleplay on the first pull
local RP_RETRY = 8          -- and after a wipe
local DESPAWN_FULL = 60     -- the despawn timer of Algalon (minutes) is full before the first pull has started
local CAST_SECONDS = 8
local DEFAULT_WINDOW_SECONDS = 4
local WINDOW_SECONDS = DEFAULT_WINDOW_SECONDS -- the perfect window: this many seconds back from the end of the Big Bang cast (2, 3 or 4)
local DRAIN = 0.01          -- fraction of its maximum health that a star loses each second
local STAR_LIFE = 100
local FIRST_WAVE = 16.5     -- as in DBM
local WAVE_EVERY = 60
local FIRST_WAVE_SIZE = 4
local MAX_STARS = 4
local LAST_WAVE = 4
local BANGS = { 90, 180, 270 }
local ENRAGE = 360
-- Curse of Doom (rank 2, spell 47867): one hit of DOOM_BASE + DOOM_COEFFICIENT x spell power, after DOOM_DURATION seconds. The coefficient is
-- the one of AzerothCore's spell_bonus_data (2.0); the base is the 3.3.5 tooltip value. The hit can not crit. Effects on the target
-- (Curse of the Elements ...) are ignored.
local DOOM_NAME = "Curse of Doom"
local DOOM_BASE = 7300
local DOOM_COEFFICIENT = 2.0
local doomDuration = 60
local doomSpellPower = 3000
local DEFAULT_SPAWN_MARGIN = 1
local spawnMargin = DEFAULT_SPAWN_MARGIN -- a window opens this long after a spawn, and one that ends at a spawn ends this long before it
local DEFAULT_BUFFER = 6
local buffer = DEFAULT_BUFFER

E.MAX_STARS = MAX_STARS

function E.SetBuffer(seconds)
    buffer = tonumber(seconds) or DEFAULT_BUFFER
    if buffer < 0 then
        buffer = 0
    end
end

function E.GetBuffer()
    return buffer
end

function E.SetPerfectWindow(seconds)
    seconds = tonumber(seconds)
    WINDOW_SECONDS = (seconds == 2 or seconds == 3 or seconds == 4) and seconds or DEFAULT_WINDOW_SECONDS
end

function E.GetPerfectWindow()
    return WINDOW_SECONDS
end

-- which Doom windows the line shows: for one curse, for two warlocks casting together, both, or none
local showSingle, showDouble = true, true
function E.SetDoomModes(single, double)
    showSingle, showDouble = single and true or false, double and true or false
end
function E.GetDoomModes()
    return showSingle, showDouble
end

function E.SetDoomSpellPower(value)
    doomSpellPower = tonumber(value) or 3000
    if doomSpellPower < 0 then
        doomSpellPower = 0
    end
end

function E.GetDoomSpellPower()
    return doomSpellPower
end

-- Talents of the warlock that raise the hit: Shadow Mastery (+15%) and Malediction (+3%) are always assumed. They multiply (the server
-- multiplies each aura of damage done). The damage is fixed at the moment of the cast, with the spell power of that moment; Death's
-- Embrace does not count, since the target has more than 35% health then. 2498 spell power gives 14564, as measured in game.
local DOOM_MULTIPLIER = (1 + 15 / 100) * (1 + 3 / 100)

local function doomDamage()
    local raw = DOOM_BASE + DOOM_COEFFICIENT * doomSpellPower
    return raw * DOOM_MULTIPLIER
end

-- the damage, the base and the coefficient of the formula, and the multiplier of the talents
function E.DoomDamage()
    return doomDamage(), DOOM_BASE, DOOM_COEFFICIENT, DOOM_MULTIPLIER
end

function E.SetSpawnMargin(seconds)
    spawnMargin = tonumber(seconds) or DEFAULT_SPAWN_MARGIN
    if spawnMargin < 0 then
        spawnMargin = 0
    end
end

function E.GetSpawnMargin()
    return spawnMargin
end

-- 2 or 3: the number of stars that die in each minute
local strategy = 2
function E.SetStrategy(n)
    strategy = (tonumber(n) == 3) and 3 or 2
end
function E.GetStrategy()
    return strategy
end

local GREEN = { 0.2, 1, 0.2 }
local RED = { 1, 0.25, 0.25 }
local GREY = { 0.65, 0.65, 0.65 }
local WHITE = { 1, 1, 1 }
local YELLOW = { 1, 0.85, 0.2 }

local fightStart = nil      -- GetTime() at T = 0
local started = false
local active = false        -- in combat
local pullStart = nil
local castsSeen = 0

local stars = {}            -- guid -> record { guid, wave, index, frac, at, max, marker, auras, dead, ghost }
local usedIndex = {}        -- wave -> { [index] = true }: indexes taken by records and by unseen deaths
local unseenDead = {}       -- wave -> number of never-seen stars that died
local deathTimes = {}       -- wave -> fight times at which its stars died
local sizes = {}            -- wave -> number of stars that spawned (frozen a few seconds after the spawn)
local rowOfStar = {}        -- star name -> row 1..4 (a star keeps its row until it is gone)
local learnedDots = {}      -- aura names seen ticking on a star
local starMax = nil         -- the maximum health of a star, once one was seen
local seen = {}             -- guid -> true for the stars observed in the current scan
local pendingMark = {}      -- guid -> marker just set on a star, not read back yet
local pendingDamage = {}    -- guid -> damage logged on a star before the maximum health of a star was known
local deadGuids = {}        -- guid -> true for the stars that died

-- The messages about the fight (its start, the smashes measured, its end) are only printed when asked for with /sw chat on; the answer to
-- a command of the player is always printed (force).
local chatOn = false
function E.SetChat(value)
    chatOn = value and true or false
end
function E.GetChat()
    return chatOn
end

local function Tell(text, force)
    if chatOn or force then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99StarWatcher|r: " .. text)
    end
end

-- Cosmic Smash: Algalon casts it 25 s after the start of the fight and every 25 s after; the raid has to move, so a star must not die
-- within the smash buffer before or after the start of a smash (the perfect windows are not affected: nobody is there). The times are
-- corrected from the casts seen (smashAnchor: the k-th smash was seen at fight time T; smashPeriod: the measured interval).
local SMASH_FIRST = 25
local SMASH_EVERY = 25
local SMASH_CAST = 4.5
local DEFAULT_SMASH_BUFFER = 3
local smashBuffer = DEFAULT_SMASH_BUFFER
local smashAnchor = nil
local smashPeriod = SMASH_EVERY

function E.SetSmashBuffer(seconds)
    smashBuffer = tonumber(seconds) or DEFAULT_SMASH_BUFFER
    if smashBuffer < 0 then
        smashBuffer = 0
    end
end

function E.GetSmashBuffer()
    return smashBuffer
end

-- the fight time of the start of the k-th smash
local function smashTime(k)
    if smashAnchor then
        return smashAnchor.T + (k - smashAnchor.n) * smashPeriod
    end
    return SMASH_FIRST + (k - 1) * SMASH_EVERY
end

local function smashStarts()
    local list = {}
    local k = 1
    while smashTime(k) < ENRAGE do
        list[#list + 1] = smashTime(k)
        k = k + 1
    end
    return list
end

local function reset()
    smashAnchor, smashPeriod = nil, SMASH_EVERY
    for k in pairs(pendingMark) do pendingMark[k] = nil end
    for k in pairs(pendingDamage) do pendingDamage[k] = nil end
    for k in pairs(deadGuids) do deadGuids[k] = nil end
    fightStart = nil
    started = false
    castsSeen = 0
    for _, t in ipairs({ stars, usedIndex, unseenDead, deathTimes, sizes, rowOfStar }) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- Finding the start of the fight
-- ---------------------------------------------------------------------------------------------------------------------------
-- The fight is over when nothing of it has been seen for this long (a wipe, or the player's death with nobody left to see it), or when the
-- enrage has gone by. Algalon dying ends it too.
local ACTIVITY_TIMEOUT = 30
local lastActivity = 0
local testing = false

-- Something of the fight was seen (the combat log, a star).
function E.Touch(now)
    if now > lastActivity then
        lastActivity = now
    end
end

function E.BeginAt(at, why, test)
    reset()
    started = true
    active = true
    fightStart = at
    testing = test and true or false
    lastActivity = math.max(GetTime(), at)
    Tell(string.format("fight start from %s: first Big Bang in %.0f s", why or "?", at + BANGS[1] - GetTime()), test)
end

-- Entering combat arms the tracker; a pull yell heard just before starts the fight from the end of the roleplay.
function E.Arm()
    active = true
    if not started and pullStart and GetTime() - pullStart < 120 then
        E.BeginAt(pullStart, "the pull yell")
    end
    pullStart = nil
end

function E.Disarm()
    active = false
    pullStart = nil
    reset()
end

function E.IsStarted()
    return started
end

function E.FightTime(now)
    return fightStart and (now - fightStart) or nil
end

-- The minutes left on Algalon's despawn timer, as shown by the world state, or nil.
local function despawnMinutes()
    for i = 1, GetNumWorldStateUI() do
        local _, _, text = GetWorldStateUIInfo(i)
        if text and string.find(text, BOSS_NAME, 1, true) then
            local minutes = string.match(text, "(%d+)")
            if minutes then
                return tonumber(minutes)
            end
        end
    end
    return nil
end

-- Algalon's pull yell. The roleplay that follows lasts 26 s on the first pull and 8 s after a wipe; the despawn timer tells which.
function E.OnYell(message, sender, now)
    if not message or not sender then
        return
    end
    if not string.find(sender, BOSS_NAME, 1, true) or not string.find(string.lower(message), PULL_YELL, 1, true) then
        return
    end
    local minutes = despawnMinutes()
    local first = (not minutes or minutes == 0 or minutes >= DESPAWN_FULL)
    local rp = first and RP_FIRST_PULL or RP_RETRY
    pullStart = now + rp
    Tell(string.format("pull yell: %s pull, roleplay %d s", first and "first" or "next", rp))
    if active then
        E.BeginAt(pullStart, "the pull yell")
    end
end

-- tokens: the target tokens of the group members. Once Algalon targets one of the group, the fight starts.
function E.Poll(tokens, now)
    if not active or started then
        return
    end
    for i = 1, #tokens do
        local token = tokens[i]
        if UnitExists(token) and UnitCanAttack("player", token) and not UnitIsDead(token) then
            local name = UnitName(token)
            if name and string.find(name, BOSS_NAME, 1, true) then
                local victim = token .. "target"
                if UnitExists(victim) and UnitIsPlayer(victim) and not UnitCanAttack("player", victim) then
                    E.BeginAt(now, "Algalon going for " .. (UnitName(victim) or "the raid"))
                    return
                end
            end
        end
    end
end

-- The combat log as a second way: the first time Algalon hits, casts at or affects somebody in the group.
function E.OnHit(sourceName, destName, now)
    if not active or started or not sourceName or not destName then
        return
    end
    if string.find(sourceName, BOSS_NAME, 1, true) and (UnitInRaid(destName) or UnitInParty(destName) or UnitIsUnit(destName, "player")) then
        E.BeginAt(now, "Algalon going for " .. destName)
    end
end

-- A Big Bang seen puts the clock of the fight right (they are at T = 90, 180, 270).
-- Cosmic Smash seen (combat log): puts the schedule right and measures the interval.
function E.OnSmash(now)
    if not started or not fightStart then
        return
    end
    local Tc = now - fightStart
    local k = math.max(math.floor((Tc - SMASH_FIRST) / SMASH_EVERY + 0.5) + 1, 1)
    if smashAnchor then
        local measured = (Tc - smashAnchor.T) / math.max(k - smashAnchor.n, 1)
        if k > smashAnchor.n and measured > 20 and measured < 30 then
            smashPeriod = measured
            Tell(string.format("Cosmic Smash %d seen at %.1f s, %.2f s after the previous one", k, Tc, measured))
        end
    else
        Tell(string.format("Cosmic Smash %d seen at %.1f s (expected %.1f s)", k, Tc, smashTime(k)))
    end
    smashAnchor = { n = k, T = Tc }
end

function E.OnCast(sourceName, spellName)
    if not started or spellName ~= BIG_BANG_NAME then
        return
    end
    if not sourceName or not string.find(sourceName, BOSS_NAME, 1, true) then
        return
    end
    local now = GetTime()
    castsSeen = castsSeen + 1
    local base = fightStart or (now - BANGS[1] * castsSeen)
    local k = math.floor((now - base) / 90 + 0.5)
    if k >= 1 and k <= #BANGS and math.abs(now - (base + 90 * k)) < 10 then
        fightStart = now - BANGS[k]
    end
end

function E.LearnDot(spellName)
    if spellName then
        learnedDots[spellName] = true
    end
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- The schedule
-- ---------------------------------------------------------------------------------------------------------------------------
local function waveAt(w)
    return FIRST_WAVE + WAVE_EVERY * (w - 1)
end

local function lastWaveSpawned(T)
    if T < FIRST_WAVE then
        return 0
    end
    return math.floor((T - FIRST_WAVE) / WAVE_EVERY) + 1
end

-- How many stars spawn in a wave: enough to bring the living stars back to 4.
local function sizeOf(w, T)
    if w == 1 then
        return FIRST_WAVE_SIZE
    end
    if sizes[w] then
        return sizes[w]
    end
    local alive = 0
    for v = 1, w - 1 do
        if waveAt(w) <= waveAt(v) + STAR_LIFE then
            local dead = 0
            for _, t in ipairs(deathTimes[v] or {}) do
                if t < waveAt(w) + 0.5 then
                    dead = dead + 1
                end
            end
            alive = alive + math.max(sizeOf(v, T) - dead, 0)
        end
    end
    local size = math.max(MAX_STARS - alive, 0)
    if T and T >= waveAt(w) + 3 then
        sizes[w] = size
    end
    return size
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- The slots: the windows in which the stars die, grouped by the minute they serve
-- ---------------------------------------------------------------------------------------------------------------------------
-- A window: capacity is how many stars fit, as many times as the buffer fits in it (the perfect windows hold any number).
local function makeWindow(name, from, to, perfect)
    if from > to then
        return nil
    end
    local capacity = math.huge
    if not perfect and buffer > 0 then
        capacity = math.floor((to - from) / buffer)
    end
    return { name = name, from = from, to = to, perfect = perfect, capacity = capacity }
end

local function nominalSize(w)
    if w == 1 then
        return FIRST_WAVE_SIZE
    end
    return (strategy == 3) and 3 or 2
end

-- The groups of windows of the strategy, in time order. Each has the windows, and contrib: how many stars of each wave die in it (a star
-- can be made to die earlier than it would on its own, never later). size(w) is the number of stars that spawned in wave w.
--   2 stars: S1 takes 2 of the first 4 stars, the 2 others die around the first Big Bang; every later pair dies in the window of the
--            next minute (S2, S3, then around the third Big Bang).
--   3 stars: S1 takes 3 of the first 4; then every minute the star left alive by the minute before dies with 2 stars of the new wave, and 1
--            star of the new wave is left alive. PRE-BB1 is forbidden (S1 can drag on).
local function slotGroups(size, T)
    local groups = {}
    local function bang(name, k)
        local e = BANGS[k] + CAST_SECONDS
        return makeWindow(name, e - WINDOW_SECONDS, e, true)
    end
    -- A window that is not perfect is cut by the zones around the smashes into pieces A, B, C ... (in time order). A window left in one
    -- piece keeps its name. S1A, the first piece of S1, is an exception: it holds one star although it is shorter than the buffer.
    local function cut(w)
        if w.perfect or smashBuffer <= 0 then
            return { w }
        end
        local segs = { { w.from, w.to } }
        for _, start in ipairs(smashStarts()) do
            local z0, z1 = start - smashBuffer, start + smashBuffer
            local new = {}
            for _, seg in ipairs(segs) do
                if z1 <= seg[1] or z0 >= seg[2] then
                    new[#new + 1] = seg
                else
                    if seg[1] < z0 then
                        new[#new + 1] = { seg[1], z0 }
                    end
                    if z1 < seg[2] then
                        new[#new + 1] = { z1, seg[2] }
                    end
                end
            end
            segs = new
        end
        local pieces = {}
        for k, seg in ipairs(segs) do
            if seg[2] - seg[1] > 0.05 then
                local name = (#segs > 1) and (w.name .. string.char(64 + k)) or w.name
                local piece = makeWindow(name, seg[1], seg[2], false)
                if piece and name == "S1A" and piece.capacity < 1 then
                    piece.capacity = 1
                end
                -- a piece too short to hold a star is dropped
                if piece and piece.capacity >= 1 then
                    pieces[#pieces + 1] = piece
                end
            end
        end
        return pieces
    end
    local function group(contrib, ...)
        local windows, names, quota = {}, {}, 0
        for _, w in ipairs({ ... }) do
            names[#names + 1] = w.name
            for _, piece in ipairs(cut(w)) do
                windows[#windows + 1] = piece
            end
        end
        local kept = {}
        for wave, q in pairs(contrib) do
            if q > 0 and waveAt(wave) <= T then
                kept[wave] = q
                quota = quota + q
            end
        end
        if #windows > 0 and quota > 0 then
            groups[#groups + 1] = { windows = windows, contrib = kept, quota = quota, label = table.concat(names, "/"),
                opens = windows[1].from, closes = windows[#windows].to }
        end
    end
    local nat = function(w) return waveAt(w) + STAR_LIFE end
    local function clip(w, limit)
        if w and w.to > limit then
            return makeWindow(w.name, w.from, limit, w.perfect)
        end
        return w
    end
    if strategy == 3 then
        group({ [1] = size(1) - 1 }, makeWindow("S1", FIRST_WAVE + spawnMargin, waveAt(2) - spawnMargin))
        group({ [1] = 1, [2] = size(2) - 1 }, bang("BB1", 1), makeWindow("POST-BB1", BANGS[1] + CAST_SECONDS + buffer, waveAt(3) - spawnMargin))
        group({ [2] = 1, [3] = size(3) - 1 }, makeWindow("S2", waveAt(3) + spawnMargin, BANGS[2] - buffer), bang("BB2", 2))
        group({ [3] = 1, [4] = size(4) - 1 }, makeWindow("S3", waveAt(4) + spawnMargin, waveAt(5) - spawnMargin))
        group({ [4] = 1 }, makeWindow("PRE-BB3", waveAt(5) + spawnMargin, BANGS[3] - buffer), bang("BB3", 3),
            clip(makeWindow("POST-BB3", BANGS[3] + CAST_SECONDS + buffer, nat(4)), nat(4)))
    else
        group({ [1] = 2 }, makeWindow("S1", FIRST_WAVE + spawnMargin, waveAt(2) - spawnMargin))
        group({ [1] = size(1) - 2 }, makeWindow("PRE-BB1", waveAt(2) + spawnMargin, BANGS[1] - buffer), bang("BB1", 1),
            makeWindow("POST-BB1", BANGS[1] + CAST_SECONDS + buffer, nat(1)))
        group({ [2] = size(2) }, clip(makeWindow("S2", waveAt(3) + spawnMargin, BANGS[2] - buffer), nat(2)))
        group({ [3] = size(3) }, clip(makeWindow("S3", waveAt(4) + spawnMargin, BANGS[3] - buffer), nat(3)))
        group({ [4] = size(4) }, makeWindow("PRE-BB3", waveAt(5) + spawnMargin, BANGS[3] - buffer), bang("BB3", 3),
            makeWindow("POST-BB3", BANGS[3] + CAST_SECONDS + buffer, nat(4)))
    end
    return groups
end

-- Everything the rolling timeline draws, for the strategy and settings in use (fight time).
function E.TimelineData()
    local data = { enrage = ENRAGE, buffer = buffer, bangs = {}, spawns = {}, windows = {}, doom = {}, smashes = {}, smashBuffer = smashBuffer }
    for _, start in ipairs(smashStarts()) do
        data.smashes[#data.smashes + 1] = start
    end
    for k, s in ipairs(BANGS) do
        data.bangs[k] = { from = s, to = s + CAST_SECONDS, perfectFrom = s + CAST_SECONDS - WINDOW_SECONDS }
    end
    for w = 1, 6 do
        data.spawns[w] = waveAt(w)
    end
    for _, g in ipairs(slotGroups(nominalSize, math.huge)) do
        for _, win in ipairs(g.windows) do
            data.windows[#data.windows + 1] = { name = win.name, from = win.from, to = win.to, perfect = win.perfect }
        end
    end
    -- the curse is cast doomDuration before the landing in a perfect window; some star must be alive at both moments
    for k, s in ipairs(BANGS) do
        local landFrom, landTo = s + CAST_SECONDS - WINDOW_SECONDS, s + CAST_SECONDS
        local feasible = false
        for w = 1, 6 do
            if waveAt(w) <= landTo - doomDuration and waveAt(w) + STAR_LIFE >= landTo then
                feasible = true
            end
        end
        data.doom[k] = { name = "BB" .. k, from = landFrom - doomDuration, to = landTo - doomDuration, feasible = feasible }
    end
    return data
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- The stars
-- ---------------------------------------------------------------------------------------------------------------------------
local function recordsOf(wave)
    local n = 0
    for _, rec in pairs(stars) do
        if rec.wave == wave then
            n = n + 1
        end
    end
    return n
end

local function takeIndex(wave)
    usedIndex[wave] = usedIndex[wave] or {}
    local i = 0
    while usedIndex[wave][i] do
        i = i + 1
    end
    usedIndex[wave][i] = true
    return i
end

-- The wave a star seen for the first time belongs to. An untouched star's health says how old it is; a damaged one looks older than it
-- is, so the waves that spawned before it "looks" born are ruled out, and of the others the earliest with a free place is taken.
local function assignWave(frac, T)
    local last = math.max(lastWaveSpawned(T), 1)
    frac = math.max(math.min(frac, 1), 0)
    local apparentSpawn = T - (1 - frac) * STAR_LIFE
    local fallback
    for w = 1, last do
        if waveAt(w) >= apparentSpawn - 3 then
            if recordsOf(w) + (unseenDead[w] or 0) < sizeOf(w, T) then
                return w
            end
            fallback = fallback or w
        end
    end
    return fallback or last
end

-- A star died (combat log). A star that was seen is marked dead; one that never was uses up a place of the oldest wave that has one.
function E.OnStarDeath(guid, now)
    if not started or not fightStart then
        return
    end
    local T = now - fightStart
    deadGuids[guid] = true
    local rec = stars[guid]
    if rec then
        if not rec.dead then
            rec.dead = true
            deathTimes[rec.wave] = deathTimes[rec.wave] or {}
            table.insert(deathTimes[rec.wave], T)
        end
        return
    end
    for w = 1, lastWaveSpawned(T) do
        if recordsOf(w) + (unseenDead[w] or 0) < sizeOf(w, T) then
            unseenDead[w] = (unseenDead[w] or 0) + 1
            takeIndex(w)
            deathTimes[w] = deathTimes[w] or {}
            table.insert(deathTimes[w], T)
            return
        end
    end
end

-- The oldest wave that still has a star nobody has a record of: the guess for a star first heard of in the combat log.
local function oldestFreeWave(T)
    for w = 1, lastWaveSpawned(T) do
        if waveAt(w) + STAR_LIFE > T and recordsOf(w) + (unseenDead[w] or 0) < sizeOf(w, T) then
            return w
        end
    end
    return nil
end

-- The passive loss of a star is a tick of 1% of its maximum health once per second, applied by the server (it is not in the combat log).
-- rec.tickAt is the game time of one tick of that star, learned from the drops of its health between two reads; without it the loss is
-- taken as smooth.
local TICK_PERIOD = 1

-- the number of ticks in (t0, t1] (game time)
local function ticksBetween(rec, t0, t1)
    if t1 <= t0 then
        return 0
    end
    if rec and rec.tickAt then
        return math.floor((t1 - rec.tickAt) / TICK_PERIOD) - math.floor((t0 - rec.tickAt) / TICK_PERIOD)
    end
    return (t1 - t0) / TICK_PERIOD
end

-- the game time of the n-th tick after t0 (n >= 1; any positive number when the ticks are not known)
local function tickTime(rec, t0, n)
    if rec and rec.tickAt then
        return rec.tickAt + (math.floor((t0 - rec.tickAt) / TICK_PERIOD) + n) * TICK_PERIOD
    end
    return t0 + n * TICK_PERIOD
end

-- when a star that has the fraction f of its health at the game time t0 dies on its own
local function deathTime(rec, f, t0)
    if f <= 0 then
        return t0
    end
    if rec and rec.tickAt then
        return tickTime(rec, t0, math.max(math.ceil(f / DRAIN - 1e-6), 1))
    end
    return t0 + f / DRAIN
end

-- t is the middle of the two reads between which the tick was seen (so within 0.05 s of it); the estimates are averaged over the ticks seen.
local function learnTick(rec, t)
    if not rec.tickAt then
        rec.tickAt, rec.tickCount = t, 1
        return
    end
    local k = math.floor((t - rec.tickAt) / TICK_PERIOD + 0.5)
    local err = t - (rec.tickAt + k * TICK_PERIOD)
    if math.abs(err) < 0.4 then
        rec.tickCount = math.min((rec.tickCount or 1) + 1, 6)
        rec.tickAt = rec.tickAt + k * TICK_PERIOD + err / rec.tickCount
    end
end

-- The ticks are believed at rec.tickAt + k, but every read says something about them: a read that shows a drop that the read before it
-- did not show means a tick fell in between; a read that shows no drop means none did. Called with the times of the two reads (p, now)
-- and whether the drop was seen, it moves the believed ticks (by no more than the gap between the reads) so that they agree.
local function constrainTicks(rec, p, now, dropSeen)
    if not rec.tickAt then
        return
    end
    if dropSeen then
        -- a believed tick must fall in (p, now]: take the one nearest to the middle of it
        local mid = (p + now) / 2
        local tau = rec.tickAt + math.floor((mid - rec.tickAt) / TICK_PERIOD + 0.5) * TICK_PERIOD
        if tau > now then
            rec.tickAt = rec.tickAt - (tau - now)
        elseif tau <= p then
            rec.tickAt = rec.tickAt + (p + 0.001 - tau)
        end
    else
        -- no believed tick may fall in (p, now]
        local tau = rec.tickAt + math.floor((now - rec.tickAt) / TICK_PERIOD) * TICK_PERIOD
        if tau > p and tau <= now then
            rec.tickAt = rec.tickAt + (now + 0.001 - tau)
        end
    end
end

local function fractionNow(rec, now)
    return math.max(math.min(rec.frac - DRAIN * ticksBetween(rec, rec.at, now), 1), 0)
end

-- Damage taken by a star (combat log). The star's health goes down by it; a star nobody has targeted yet gets a record from its first
-- damage: it is the oldest star not known yet, with the health the schedule gives it minus the damage.
function E.OnStarDamage(guid, amount, now)
    if not started or not fightStart or not amount or amount <= 0 or deadGuids[guid] then
        return
    end
    local rec = stars[guid]
    if rec and (rec.dead or rec.ghost) then
        return
    end
    local max = (rec and rec.max) or starMax
    if not max then
        pendingDamage[guid] = (pendingDamage[guid] or 0) + amount
        return
    end
    local T = now - fightStart
    if rec then
        rec.hitAt = now
    end
    if not rec then
        local wave = oldestFreeWave(T)
        if not wave then
            return
        end
        rec = { guid = guid, wave = wave, index = takeIndex(wave), fromLog = true, max = max, at = now, hitAt = now }
        rec.frac = math.max(1 - (T - waveAt(wave)) / STAR_LIFE, 0)
        stars[guid] = rec
    else
        rec.frac = fractionNow(rec, now)
        rec.at = now
    end
    rec.frac = rec.frac - amount / max
end

-- A star that came from the combat log is seen for real: its health says which wave it belongs to.
local function rehome(rec, frac, T)
    rec.fromLog = nil
    local old = rec.wave
    stars[rec.guid] = nil
    local wave = assignWave(frac, T)
    stars[rec.guid] = rec
    if wave ~= old then
        if usedIndex[old] then
            usedIndex[old][rec.index] = nil
        end
        rec.wave = wave
        rec.index = takeIndex(wave)
    end
end

-- The markers on the stars alive, apart from the one with this guid (and the markers just set that the scan has not read yet).
function E.UsedMarkers(exceptGuid)
    local used = {}
    for _, rec in pairs(stars) do
        if rec.marker and rec.guid ~= exceptGuid and not rec.dead and not rec.ghost then
            used[rec.marker] = true
        end
    end
    for guid, marker in pairs(pendingMark) do
        if guid ~= exceptGuid then
            used[marker] = true
        end
    end
    return used
end

function E.NoteMarker(guid, marker)
    pendingMark[guid] = marker
end

function E.BeginScan()
    for guid in pairs(seen) do
        seen[guid] = nil
    end
    for _, rec in pairs(stars) do
        rec.live = false
        rec.token = nil
    end
end

local function scanAuras(rec, unit)
    local list = {}
    local byName = {}
    local dooms = {}
    for i = 1, 40 do
        local name, _, icon, _, _, duration, expires = UnitDebuff(unit, i)
        if not name then
            break
        end
        if name == DOOM_NAME then
            if expires and expires > 0 then
                dooms[#dooms + 1] = expires
            end
            if duration and duration > 0 then
                doomDuration = duration
            end
        elseif learnedDots[name] then
            local a = byName[name]
            if not a then
                a = { name = name, icon = icon, duration = duration, expires = expires or 0, sources = 0 }
                byName[name] = a
                list[#list + 1] = a
            end
            a.sources = a.sources + 1
            if expires and expires > a.expires then
                a.expires = expires
            end
        end
    end
    rec.auras = list
    rec.dooms = dooms
end

-- Reads one unit token; if it is a star, brings its record up to date.
function E.Observe(unit, now)
    if not started or not fightStart then
        return
    end
    if UnitName(unit) ~= STAR_NAME or not UnitExists(unit) then
        return
    end
    local guid = UnitGUID(unit)
    if not guid or seen[guid] then
        return
    end
    if UnitIsDead(unit) then
        if stars[guid] then
            E.OnStarDeath(guid, now)
        end
        return
    end
    seen[guid] = true
    lastActivity = math.max(lastActivity, now)
    local max = UnitHealthMax(unit)
    if not max or max <= 0 then
        return
    end
    local frac = UnitHealth(unit) / max
    local T = now - fightStart
    local rec = stars[guid]
    if not rec then
        local wave = assignWave(frac, T)
        rec = { guid = guid, wave = wave, index = takeIndex(wave) }
        stars[guid] = rec
    end
    if rec.dead then
        return
    end
    if rec.fromLog then
        rehome(rec, frac, T)
    end
    rec.frac, rec.at, rec.live = frac, now, true
    rec.token = unit      -- a unit token that points at this star right now (for the markers)
    if max > 100 then
        -- a drop of 1% of the maximum health between two close reads, with no hit in the log, is a tick of the passive loss
        local hpNow = frac * max
        if rec.readHp and rec.readAt and now > rec.readAt and now - rec.readAt <= 0.35 then
            local slope = DRAIN * max
            local hit = rec.hitAt and now - rec.hitAt <= 0.6
            local dropped = math.abs(rec.readHp - hpNow - slope) <= 0.2 * slope
            if not hit then
                if dropped then
                    learnTick(rec, (rec.readAt + now) / 2)
                end
                if dropped or hpNow >= rec.readHp - 0.2 * slope then
                    constrainTicks(rec, rec.readAt, now, dropped)
                end
            end
        end
        rec.readHp, rec.readAt = hpNow, now
        rec.max = max
        if not starMax then
            starMax = max
            for g, damage in pairs(pendingDamage) do
                pendingDamage[g] = nil
                E.OnStarDamage(g, damage, now)
            end
        end
        starMax = max
    end
    rec.marker = GetRaidTargetIndex(unit)
    pendingMark[guid] = nil
    scanAuras(rec, unit)
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------------------------------------------------------
-- How many stars (of any wave, or of one wave) died inside a window.
local function deathsIn(window, wave)
    local used = 0
    for w, times in pairs(deathTimes) do
        if not wave or wave == w then
            for _, t in ipairs(times) do
                if t >= window.from - 1 and t <= window.to + 1 then
                    used = used + 1
                end
            end
        end
    end
    return used
end

local function deathsInGroup(g, wave)
    local used = 0
    for _, w in ipairs(g.windows) do
        used = used + deathsIn(w, wave)
    end
    return used
end

-- Gives each living star a slot. First the stars already aimed at a window claim it (respecting the room of the window and what is left
-- of the group's number of stars for their wave; whether the deaths are far enough apart is judged apart, in the spacing of the group);
-- then the others take the first window, in time order, that still has room, is still open or to come, and opens before the star would
-- die on its own (a star can be made to die earlier, never later). So the players choose which stars go where.
local function assignSlots(items, T, groups)
    local list = {}
    for i = 1, #items do
        local item = items[i]
        item.slot, item.claimed, item.group = nil, false, nil
        if not item.ignored then
            list[#list + 1] = item
        end
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        end
        if a.wave ~= b.wave then
            return a.wave < b.wave
        end
        return a.index < b.index
    end)
    local taken, groupTaken = {}, {}
    for _, g in ipairs(groups) do
        groupTaken[g] = {}
    end
    local function groupRoom(g, wave)
        return (g.contrib[wave] or 0) - deathsInGroup(g, wave) - (groupTaken[g][wave] or 0)
    end
    local function windowRoom(w)
        if w.capacity == math.huge then
            return math.huge
        end
        return w.capacity - deathsIn(w) - (taken[w] or 0)
    end
    local function place(item, g, w)
        item.slot, item.group = w, g
        taken[w] = (taken[w] or 0) + 1
        groupTaken[g][item.wave] = (groupTaken[g][item.wave] or 0) + 1
    end
    for _, item in ipairs(list) do
        for _, g in ipairs(groups) do
            if not item.slot and groupRoom(g, item.wave) > 0 then
                for _, w in ipairs(g.windows) do
                    if item.at >= w.from and item.at <= w.to and w.to >= T and windowRoom(w) > 0 then
                        place(item, g, w)
                        item.claimed = true
                        break
                    end
                end
            end
        end
    end
    -- the stars not placed yet: of the windows they can still reach, the smallest one with no star yet (the small windows are the ones
    -- that must not be missed, and the large ones leave time), then the smallest one with room
    for _, item in ipairs(list) do
        if not item.slot then
            for _, g in ipairs(groups) do
                if not item.slot and groupRoom(g, item.wave) > 0 then
                    local best, bestKey
                    for _, w in ipairs(g.windows) do
                        if w.to >= T and w.from <= item.at + 0.5 and windowRoom(w) > 0 then
                            local key = ((taken[w] or 0) > 0 and 1e9 or 0) + (w.capacity == math.huge and 1e6 or w.capacity * 1000) + w.from
                            if not best or key < bestKey then
                                best, bestKey = w, key
                            end
                        end
                    end
                    if best then
                        place(item, g, best)
                    end
                end
            end
        end
    end
end

-- The fight time at which the star should die for the "perfect burn": the end of a perfect window, otherwise the middle of what is
-- reachable in the window.
local function burnTarget(item, T)
    local w = item.slot
    if not w then
        return nil
    end
    if w.perfect then
        return w.to
    end
    local lo = math.max(w.from, T)
    local hi = math.min(w.to, item.at)
    if hi < lo then
        hi = lo
    end
    return (lo + hi) / 2
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- The model: everything the window shows
-- ---------------------------------------------------------------------------------------------------------------------------
local model = { rows = {}, groups = {}, tasks = {}, header = "", headerColor = WHITE, sub = "" }
E.model = model

local function clear(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

local function colored(text, c)
    return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local function markText(marker)
    if marker and marker >= 1 and marker <= 8 then
        return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:12|t", marker)
    end
    return ""
end

-- the marker (if any) and the name of a star, for the messages
local function starLabel(item)
    return markText(item.mark) .. string.format("%d-%d", item.wave, item.index)
end

local function buildItems(now, T)
    local items = {}
    for w = 1, math.max(lastWaveSpawned(T), 1) do
        if waveAt(w) <= T then
            local size = sizeOf(w, T)
            local present = 0
            for _, rec in pairs(stars) do
                if rec.wave == w then
                    present = present + 1
                    if not rec.dead and not rec.ghost then
                        local frac = fractionNow(rec, now)
                        if not rec.live and frac <= 0 then
                            -- no longer followed and its time is up: it died, and the combat log did not tell
                            rec.dead = true
                            deathTimes[w] = deathTimes[w] or {}
                            table.insert(deathTimes[w], deathTime(rec, rec.frac, rec.at) - fightStart)
                        else
                            items[#items + 1] = { wave = w, index = rec.index, rec = rec, frac = frac, max = rec.max or starMax }
                        end
                    end
                end
            end
            present = present + (unseenDead[w] or 0)
            if T < waveAt(w) + STAR_LIFE + 3 then
                local frac = math.max(1 - (T - waveAt(w)) / STAR_LIFE, 0)
                local index = 0
                for _ = 1, size - present do
                    while usedIndex[w] and usedIndex[w][index] do
                        index = index + 1
                    end
                    items[#items + 1] = { wave = w, index = index, placeholder = true, frac = frac, max = starMax }
                    index = index + 1
                end
            end
        end
    end
    -- never more than 4 living stars: drop the ones followed least recently, then the guessed ones
    while #items > MAX_STARS do
        local drop, dropAt
        for i, item in ipairs(items) do
            if item.rec and not item.rec.live and (not dropAt or item.rec.at < dropAt) then
                drop, dropAt = i, item.rec.at
            end
        end
        if not drop then
            for i = #items, 1, -1 do
                if items[i].placeholder then
                    drop = i
                    break
                end
            end
        end
        drop = drop or #items
        if items[drop].rec then
            items[drop].rec.ghost = true
        end
        table.remove(items, drop)
    end
    table.sort(items, function(a, b)
        if a.wave ~= b.wave then
            return a.wave < b.wave
        end
        return a.index < b.index
    end)
    for _, item in ipairs(items) do
        item.name = string.format("Star-%d-%d", item.wave, item.index)
        item.ignored = item.wave > LAST_WAVE
        item.at = deathTime(item.rec, item.frac, now) - fightStart
        item.deathIn = item.at - T
        item.doom = nil
        if item.rec and item.rec.dooms and #item.rec.dooms > 0 and item.max then
            -- every curse on the star lands in its turn (two warlocks can cast together); the star dies at the first landing that finds
            -- at most the Doom damage left, or when what is left after the last one runs out
            local landings = {}
            for _, expires in ipairs(item.rec.dooms) do
                if expires - fightStart > T - 0.5 then
                    landings[#landings + 1] = expires
                end
            end
            table.sort(landings)
            local hp, last, D = item.frac * item.max, now, doomDamage()
            for n, at in ipairs(landings) do
                local landing = at - fightStart
                local before = hp - DRAIN * item.max * ticksBetween(item.rec, last, at)
                if before <= 0 then
                    item.doom = { state = "late", landing = landing, count = n, before = before }
                    break
                elseif before <= D then
                    item.doom = { state = "kills", landing = landing, count = n, before = before }
                    item.at = landing
                    item.deathIn = landing - T
                    break
                end
                hp, last = before - D, at
                if n == #landings then
                    -- the curses do not kill the star but take their damage off: it dies when what is left runs out
                    item.doom = { state = "short", landing = landing, short = hp, count = n, before = before }
                    item.at = deathTime(item.rec, hp / item.max, at) - fightStart
                    item.deathIn = item.at - T
                end
            end
        end
        item.guid = item.rec and item.rec.guid or nil
        item.live = item.rec and item.rec.live or false
        item.mark = item.rec and item.rec.marker or nil
        item.auras = item.rec and item.rec.auras or nil
        if item.max then
            item.hp = item.frac * item.max
        end
    end
    return items
end

local function allocateRows(items)
    local present = {}
    for _, item in ipairs(items) do
        present[item.name] = true
    end
    for name in pairs(rowOfStar) do
        if not present[name] then
            rowOfStar[name] = nil
        end
    end
    local used = {}
    for _, item in ipairs(items) do
        if rowOfStar[item.name] then
            used[rowOfStar[item.name]] = true
        end
    end
    for _, item in ipairs(items) do
        if not rowOfStar[item.name] then
            for s = 1, MAX_STARS do
                if not used[s] then
                    rowOfStar[item.name] = s
                    used[s] = true
                    break
                end
            end
        end
        model.rows[rowOfStar[item.name] or MAX_STARS] = item
    end
end

-- Is this death time (fight time) inside a perfect window of a Big Bang? Deaths together in one are fine.
local function perfectWindowIndex(t)
    for k = 1, #BANGS do
        local e = BANGS[k] + CAST_SECONDS
        if t >= e - WINDOW_SECONDS - 1e-6 and t <= e + 1e-6 then
            return k
        end
    end
    return nil
end

-- Is this star placed right: the state in which its pointer on the timeline is green, yellow or purple? (committed, and either a Doom
-- kills it or it is in a safe or perfect window with no warning)
function E.IsPlaced(item)
    if not item.committed then
        return false
    end
    if item.doom and item.doom.state == "kills" then
        return true
    end
    if item.tooClose or item.nearSmash or item.nearBang then
        return false
    end
    return (item.inPerfect or item.claimed) and true or false
end

-- A star the players have aimed: damaged beyond the passive loss, or placed in a window, or under a Doom. The death time of a star left
-- alone is no plan, so it is not judged.
local function committed(item, T)
    if item.claimed or item.doom then
        return true
    end
    if item.rec and item.max then
        local expected = 1 - (T - waveAt(item.wave)) / STAR_LIFE
        return expected - item.frac > 0.02
    end
    return false
end

-- Two rules about the time of a death, true wherever the star is: not within the Big Bang and star buffer of another death (together in a perfect
-- window is fine), and not within the Cosmic Smash buffer of the start of a smash (the perfect windows are not affected). Sets
-- item.tooClose / item.nearSmash and item.dangerText (what to tell).
local function flagDeaths(items, T)
    local list, lines, parts = {}, {}, {}
    for _, item in ipairs(items) do
        item.tooClose, item.nearSmash, item.nearBang = false, false, false
        item.committed = (not item.ignored) and committed(item, T)
        item.inPerfect = perfectWindowIndex(item.at) ~= nil
        if not item.ignored and committed(item, T) then
            list[#list + 1] = { at = item.at, item = item }
        end
    end
    table.sort(list, function(a, b) return a.at < b.at end)
    -- two deaths too close: one line for the pair
    for i = 2, #list do
        local a, b = list[i - 1], list[i]
        local k = perfectWindowIndex(a.at)
        if b.at - a.at < buffer - 0.01 and not (k and k == perfectWindowIndex(b.at)) then
            a.item.tooClose = true
            b.item.tooClose = true
            lines[#lines + 1] = string.format("%s & %s die %ds apart", starLabel(a.item), starLabel(b.item), b.at - a.at + 0.5)
        end
    end
    -- too close to a Big Bang (not in its perfect window) or to a Cosmic Smash: one line per star, "BB1-3s" is 3 s before Big Bang 1,
    -- "BB1+3s" 3 s after its end, "smash -1s" 1 s before the start of a smash
    for _, entry in ipairs(list) do
        local item, t = entry.item, entry.at
        if not perfectWindowIndex(t) then
            local found = {}
            for k = 1, #BANGS do
                local startAt, endAt = BANGS[k], BANGS[k] + CAST_SECONDS
                if t > startAt - buffer and t < startAt then
                    found[#found + 1] = string.format("BB%d-%ds", k, startAt - t + 0.5)
                elseif t >= startAt and t <= endAt then
                    found[#found + 1] = string.format("in BB%d", k)
                elseif t > endAt and t < endAt + buffer then
                    found[#found + 1] = string.format("BB%d+%ds", k, t - endAt + 0.5)
                end
            end
            if #found > 0 then
                item.nearBang = true
            end
            if smashBuffer > 0 then
                for _, start in ipairs(smashStarts()) do
                    if math.abs(t - start) < smashBuffer - 0.01 then
                        item.nearSmash = true
                        found[#found + 1] = string.format("smash %s%ds", t < start and "-" or "+", math.abs(t - start) + 0.5)
                        break
                    end
                end
            end
            if #found > 0 then
                lines[#lines + 1] = string.format("%s dies %s", starLabel(item), table.concat(found, ", "))
            end
        end
    end
    return lines
end

local function buildGroups(items, groups, T)
    local shown = {}
    for _, g in ipairs(groups) do
        if g.closes >= T - 0.5 then
            g.done, g.placed, g.members = 0, 0, {}
            for wave, quota in pairs(g.contrib) do
                g.done = g.done + math.min(deathsInGroup(g, wave), quota)
            end
            for _, item in ipairs(items) do
                if item.group == g then
                    g.members[#g.members + 1] = item
                    if item.claimed then
                        g.placed = g.placed + 1
                    end
                end
            end
            g.unplaced = math.max(g.quota - g.done - g.placed, 0)
            g.filled = g.unplaced == 0
            -- spaced: none of its stars dies too close to another star or to a Cosmic Smash (the flags are worked out for all the stars)
            g.spaced = true
            for _, item in ipairs(g.members) do
                if item.tooClose or item.nearSmash or item.nearBang then
                    g.spaced = false
                end
            end
            shown[#shown + 1] = g
        end
    end
    return shown
end

local function relative(seconds)
    return string.format("%ds", math.max(seconds, 0) + 0.5)
end

local DOOM_COLOR = { 0.75, 0.5, 1 }

-- 150000 -> "150.0K", 1250000 -> "1.25M"
local function kilo(n)
    if n >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return string.format("%d", n)
end

-- the range of damage is shown rounded inwards (up for the first number, down for the second), so any damage inside it is good
local function kiloRange(low, high)
    local function text(n)
        if n >= 1000000 then
            return string.format("%.2fM", n / 1000000)
        end
        return string.format("%.1fK", n / 1000)
    end
    local lo = math.ceil(low / 100) * 100
    local hi = math.floor(high / 100) * 100
    if hi < lo then
        hi = lo
    end
    return text(lo), text(hi)
end

local function countdown(seconds)
    if seconds < 10 then
        return string.format("%.1fs", math.max(seconds, 0))
    end
    return string.format("%ds", seconds + 0.5)
end

-- The Doom window (DW) of a star: both things to get right are shown from the start. The cast: the curse lands doomDuration seconds after it,
-- so casting at the middle of the cast window (the perfect window shifted back by doomDuration) lands it in the middle of the perfect
-- window, with half the window on each side. The damage: when it lands, the star must have more than 0 health and at most the damage Dn of
-- the curses (D for one curse, 2 D for two warlocks casting together). The star loses `slope` at each tick of the passive loss, so what is
-- left at the landing is known; the damage can be done before or after the cast, as long as it is right when the curse lands.
local TICK_MARGIN = 0.1

-- 2 -> "2", 1.5 -> "1.5"
local function seconds1(x)
    return (string.format("%.1f", x):gsub("%.0$", ""))
end

local function doomWindowTextRaw(item, w, T, now, D)
    local rec = item.rec
    local slope = DRAIN * item.max
    local castFrom, castTo = w.from - doomDuration, w.to - doomDuration
    local middle = (w.from + w.to) / 2 - doomDuration      -- the cast that lands in the middle of the perfect window
    local margin = (w.to - w.from) / 2
    if T > w.to + 1 then
        return nil
    end
    -- the curse is on the star
    if item.doom then
        local doom = item.doom
        local left = doom.landing - T
        if doom.state == "kills" and doom.landing >= w.from - 0.3 and doom.landing <= w.to + 0.3 then
            return string.format("DW LOCKED%s - lands in %ds | %s to spare", (doom.count or 1) > 1 and " x2" or "", left + 0.5,
                kilo(math.max(doom.before or 0, 0))), DOOM_COLOR
        elseif doom.state == "short" then
            -- the damage still to deal: enough for the Doom to kill (what is left after it), not so much that the star dies before it lands
            local a, b = kiloRange(doom.short, math.max(doom.before or doom.short, doom.short))
            return string.format("DW LOCKED - lands in %ds | dmg %s-%s", left + 0.5, a, b), (left > 10) and YELLOW or RED
        elseif doom.state == "late" then
            return "DW too much damage, dies before landing", RED
        end
        return "DW: the Doom lands outside the window", RED
    end
    if T > castTo then
        return "DW window missed", GREY
    end
    -- The curse can be cast at any moment of the cast window as long as it kills the star on the other side: the cast times that work are
    -- the ones for which the number of ticks N until the landing keeps (health - N x slope) in ]0, Dn]: a stretch of time from the tick that
    -- brings the health down to Dn to the tick that kills the star. span(x, Dn, from) gives that stretch (fight time, inside the cast
    -- window, and not before `from`) for a star that has lost x more health.
    local function span(x, Dn, from)
        local h = item.hp - x
        if h <= 0 then
            return nil
        end
        local lo, hi
        if rec and rec.tickAt then
            local nlo = math.ceil((h - Dn) / slope - 1e-9)
            local nhi = math.max(math.ceil(h / slope - 1e-9), 1)
            lo = (nlo >= 1) and tickTime(rec, now, nlo) or -math.huge
            hi = tickTime(rec, now, nhi)
        else
            lo = now + math.max((h - Dn) / slope, 0)
            hi = now + h / slope
        end
        -- (the tick times are known to about a tenth of a second: the stretch is kept that far from the ticks that bound it)
        local a0 = math.max(lo - doomDuration - fightStart + (lo == -math.huge and 0 or TICK_MARGIN), from)
        local a1 = math.min(hi - doomDuration - fightStart - TICK_MARGIN, castTo)
        if a1 <= a0 then
            return nil
        end
        return a0, a1
    end

    -- The health is right now for one curse (n = 1) or two (n = 2): a cast works at some moment of the window that is still ahead.
    local tRef = math.max(T, castFrom)
    local ready, s, e
    for n = 1, 2 do
        if not ready and ((n == 1 and showSingle) or (n == 2 and showDouble)) then
            local a0, a1 = span(0, n * D, tRef)
            if a0 then
                ready, s, e = n, a0, a1
            end
        end
    end
    if ready then
        -- the cast to aim at is the middle of the window when this health allows it, else the middle of what works
        local f0, f1 = span(0, ready * D, castFrom)
        f0, f1 = f0 or s, f1 or e
        local c = middle
        if c < f0 or c > f1 then
            c = (f0 + f1) / 2
        end
        local around = math.max(math.min(c - f0, f1 - c), 0)
        if T >= c then
            return "CAST NOW" .. ((ready == 2) and " (both)" or "") .. "! " .. countdown(e - T) .. " left", GREEN
        end
        if T >= c - 3 then
            return string.format("CAST%s in %s! +-%s", (ready == 2) and " x2" or "", countdown(c - T), seconds1(around)), GREEN
        end
        local spare = item.hp - slope * ticksBetween(rec, now, fightStart + c + doomDuration)
        return string.format("DW %shp ok (%s to spare) | cast %s +-%s", (ready == 2) and "x2 " or "", kilo(math.max(spare, 0)), countdown(c - T),
            seconds1(around)), GREEN
    end

    -- Damage is still needed: the range for a landing in the middle of the perfect window (or as soon as a cast now can land), rounded inwards.
    local landing = math.min(math.max((w.from + w.to) / 2, T + doomDuration), w.to)
    local nA = ticksBetween(rec, now, fightStart + landing - TICK_MARGIN)
    local nB = ticksBetween(rec, now, fightStart + landing + TICK_MARGIN)
    local high = item.hp - math.max(nA, nB) * slope
    if high <= 0 then
        return "DW too much damage, star too low", GREY
    end
    local function range(n)
        return math.max(item.hp - math.min(nA, nB) * slope - n * D, 0), high
    end
    local castPart
    if T <= middle then
        castPart = string.format("cast %s +-%s", countdown(middle - T), seconds1(margin))
    else
        castPart = string.format("cast NOW %s", countdown(castTo - T))
    end
    local text
    if showSingle and showDouble then
        local a, b = kiloRange(range(1))
        local c, d = kiloRange(range(2))
        text = string.format("DW %s | %s-%s | x2 %s-%s", castPart, a, b, c, d)
    elseif showSingle then
        local a, b = kiloRange(range(1))
        text = string.format("DW %s | dmg %s-%s", castPart, a, b)
    else
        local c, d = kiloRange(range(2))
        text = string.format("DW x2 %s | dmg %s-%s", castPart, c, d)
    end
    return text, YELLOW
end

local function doomWindowText(item, w, T, now, D)
    local text, color = doomWindowTextRaw(item, w, T, now, D)
    if item.rec and text then
        item.rec.lastDwText, item.rec.lastDwColor = text, color
    end
    return text, color
end

function E.Update(now)
    model.header, model.headerColor, model.sub = "", WHITE, ""
    clear(model.rows)
    clear(model.groups)
    clear(model.tasks)
    model.active = false
    if started and fightStart then
        local over
        if now - fightStart > ENRAGE + 5 then
            over = "the enrage has gone by"
        elseif not testing and now - lastActivity > ACTIVITY_TIMEOUT then
            over = "nothing seen for " .. ACTIVITY_TIMEOUT .. " s"
        end
        if over then
            Tell("fight over (" .. over .. ")")
            E.Disarm()
        end
    end
    if not started or not fightStart then
        model.header, model.headerColor = "Waiting for the fight to start", GREY
        model.tasks[1] = { text = model.header, color = GREY }
        return model
    end
    local T = now - fightStart
    if T < 0 then
        model.header, model.headerColor = string.format("Fight starts in %s", relative(-T)), GREY
        model.tasks[1] = { text = model.header, color = GREY }
        model.active = true
        return model
    end
    model.active = true

    local items = buildItems(now, T)
    local slotList = slotGroups(function(w) return sizeOf(w, T) end, T)
    assignSlots(items, T, slotList)
    allocateRows(items)
    for _, item in ipairs(items) do
        local target = burnTarget(item, T)
        if target and item.max then
            item.dev = item.hp - item.max * DRAIN * ticksBetween(item.rec, now, fightStart + target)
            item.devLimit = item.max * 0.02
        end
        item.tooClose = false
        item.doomText, item.doomColor = nil, nil
        local D = doomDamage()
        -- the perfect window of the star's wave (BB1 or BB3), if it has one: the Doom window (DW) of the star
        local w
        for _, g in ipairs(slotList) do
            if g.contrib[item.wave] then
                for _, candidate in ipairs(g.windows) do
                    if candidate.perfect and not w and T <= candidate.to + 1 then
                        w = candidate
                    end
                end
            end
        end
        local firstMinute = item.claimed and item.slot.name == "S1" -- on track to die in S1: no Doom line
        if item.ignored or firstMinute then
            -- nothing
        elseif w and item.max and item.hp and (showSingle or showDouble) then
            item.doomText, item.doomColor = doomWindowText(item, w, T, now, D)
        elseif item.doom then
            local left = item.doom.landing - T
            if item.doom.state == "kills" then
                item.doomText, item.doomColor = string.format("Doom lands in %ds: the star dies then", left + 0.5), DOOM_COLOR
            elseif item.doom.state == "short" then
                item.doomText, item.doomColor = string.format("Doom lands in %ds but the star has %d hp too many", left + 0.5, item.doom.short + 0.5), RED
            else
                item.doomText, item.doomColor = string.format("Doom lands in %ds, after the star died", left + 0.5), GREY
            end
        end
        item.state = item.ignored and "ignore" or (not item.slot and "none") or (item.claimed and "ok" or "place")
    end

    local dangers = flagDeaths(items, T)
    local groups = buildGroups(items, slotList, T)
    for i = 1, math.min(#groups, 3) do
        model.groups[i] = groups[i]
    end

    -- the list of things to do at the top, one per line
    local tasks = model.tasks
    for _, g in ipairs(groups) do
        if g.unplaced > 0 then
            tasks[#tasks + 1] = { text = string.format("%s > %s", plural(g.unplaced, "star"), g.label), color = WHITE, action = true }
        end
    end
    for _, text in ipairs(dangers) do
        tasks[#tasks + 1] = { text = text, color = RED, action = true }
    end
    for _, item in ipairs(items) do
        if item.state == "none" then
            tasks[#tasks + 1] = { text = starLabel(item) .. " no slot", color = RED, action = true }
        end
    end
    if #tasks == 0 then
        if T > waveAt(LAST_WAVE + 1) - 5 then
            tasks[1] = { text = "Nothing to do: ignore the new stars", color = GREEN }
        elseif T < FIRST_WAVE then
            tasks[1] = { text = string.format("Stars spawn in %s", relative(FIRST_WAVE - T)), color = WHITE }
        else
            tasks[1] = { text = "Nothing to do, all star deaths correctly placed.", color = GREEN }
        end
    end
    model.header, model.headerColor = tasks[1].text, tasks[1].color

    -- under it: the next Big Bang and the next stars
    local pieces = {}
    for k = 1, #BANGS do
        local startAt, endAt = BANGS[k], BANGS[k] + CAST_SECONDS
        if T < startAt then
            pieces[#pieces + 1] = string.format("Big Bang in %s", relative(startAt - T))
            break
        elseif T <= endAt then
            pieces[#pieces + 1] = string.format("Big Bang ends in %s", relative(endAt - T))
            break
        end
    end
    for w = 1, LAST_WAVE + 1 do
        if waveAt(w) > T then
            if w <= LAST_WAVE + 1 and w <= 5 then
                pieces[#pieces + 1] = string.format("stars in %s", relative(waveAt(w) - T))
            end
            break
        end
    end
    -- the next Cosmic Smash (and "smash now" while the last one is casting)
    for _, start in ipairs(smashStarts()) do
        if T <= start + SMASH_CAST then
            if T >= start then
                pieces[#pieces + 1] = "smash now"
            else
                pieces[#pieces + 1] = string.format("smash in %s", relative(start - T))
            end
            break
        end
    end
    model.sub = table.concat(pieces, "   ")
    model.T = T
    return model
end

-- For the window: one line per star of a group, coloured (the number of stars already killed is in g.done).
function E.MemberLines(g)
    local lines = {}
    for _, item in ipairs(g.members) do
        if item.claimed then
            lines[#lines + 1] = markText(item.mark) .. colored(string.format("%s  %s", item.name, item.slot.name), (item.tooClose or item.nearSmash or item.nearBang) and RED or GREEN)
        else
            lines[#lines + 1] = markText(item.mark) .. colored(item.name .. "  to place", YELLOW)
        end
    end
    if #lines == 0 then
        lines[1] = colored(g.done > 0 and "all killed" or "no star yet", GREY)
    end
    return lines
end
