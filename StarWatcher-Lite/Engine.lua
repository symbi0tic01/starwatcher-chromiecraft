StarWatcherLite = StarWatcherLite or {}
local SW = StarWatcherLite

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
E.DEFAULT_PERFECT_WINDOW = DEFAULT_WINDOW_SECONDS
local DRAIN = 0.01          -- fraction of its maximum health that a star loses each second
local STAR_LIFE = 100
local FIRST_WAVE = 16.5     -- as in DBM
local WAVE_EVERY = 60
local FIRST_WAVE_SIZE = 4
local MAX_STARS = 4
local LAST_WAVE = 4
local BANGS = { 90, 180, 270 }
local ENRAGE = 360

local DEFAULT_BUFFER = 6
local buffer = DEFAULT_BUFFER

E.MAX_STARS = MAX_STARS
E.DEFAULT_BUFFER = DEFAULT_BUFFER

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

local GREEN = { 0.2, 1, 0.2 }
local RED = { 1, 0.25, 0.25 }
local GREY = { 0.65, 0.65, 0.65 }
local WHITE = { 1, 1, 1 }

local fightStart = nil      -- GetTime() at T = 0
local started = false
local active = false        -- in combat
local pullStart = nil
local castsSeen = 0

local stars = {}            -- guid -> record { guid, wave, index, frac, at, max, marker, dead, ghost }
local usedIndex = {}        -- wave -> { [index] = true }: indexes taken by records and by unseen deaths
local unseenDead = {}       -- wave -> number of never-seen stars that died
local deathTimes = {}       -- wave -> fight times at which its stars died
local sizes = {}            -- wave -> number of stars that spawned (frozen a few seconds after the spawn)
local rowOfStar = {}        -- star name -> row 1..4 (a star keeps its row until it is gone)
local starMax = nil         -- the maximum health of a star, once one was seen
local seen = {}             -- guid -> true for the stars observed in the current scan
local pendingDamage = {}    -- guid -> damage logged on a star before the maximum health of a star was known
local deadGuids = {}        -- guid -> true for the stars that died

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

E.DEFAULT_SMASH_BUFFER = DEFAULT_SMASH_BUFFER

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
        end
    end
    smashAnchor = { n = k, T = Tc }
end

-- A Big Bang seen puts the clock of the fight right (they are at T = 90, 180, 270).
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

function E.BeginScan()
    for guid in pairs(seen) do
        seen[guid] = nil
    end
    for _, rec in pairs(stars) do
        rec.live = false
    end
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
end

-- ---------------------------------------------------------------------------------------------------------------------------
-- The model: everything the window shows
-- ---------------------------------------------------------------------------------------------------------------------------
local model = { rows = {}, header = "", headerColor = WHITE, sub = "" }
E.model = model

local function clear(t)
    for k in pairs(t) do
        t[k] = nil
    end
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
        item.guid = item.rec and item.rec.guid or nil
        item.live = item.rec and item.rec.live or false
        item.mark = item.rec and item.rec.marker or nil
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

-- A star the players have aimed: damaged beyond the passive loss. The death time of a star left alone is no plan, so it is not judged.
local function committed(item, T)
    if item.rec and item.max then
        local expected = 1 - (T - waveAt(item.wave)) / STAR_LIFE
        return expected - item.frac > 0.02
    end
    return false
end

-- Two rules about the time of a death, true wherever the star is: not within the Big Bang and star buffer of another death (together in a
-- perfect window is fine), not within the Big Bang and star buffer of a Big Bang (its perfect window is the exception), and not within the
-- Cosmic Smash buffer of the start of a smash (the perfect windows are not affected). Sets item.tooClose / item.nearBang / item.nearSmash.
local function flagDeaths(items, T)
    local list = {}
    for _, item in ipairs(items) do
        item.tooClose, item.nearSmash, item.nearBang = false, false, false
        item.committed = (not item.ignored) and committed(item, T)
        item.inPerfect = perfectWindowIndex(item.at) ~= nil
        if item.committed then
            list[#list + 1] = { at = item.at, item = item }
        end
    end
    table.sort(list, function(a, b) return a.at < b.at end)
    for i = 2, #list do
        local a, b = list[i - 1], list[i]
        local k = perfectWindowIndex(a.at)
        if b.at - a.at < buffer - 0.01 and not (k and k == perfectWindowIndex(b.at)) then
            a.item.tooClose = true
            b.item.tooClose = true
        end
    end
    for _, entry in ipairs(list) do
        local item, t = entry.item, entry.at
        if not perfectWindowIndex(t) then
            for k = 1, #BANGS do
                local startAt, endAt = BANGS[k], BANGS[k] + CAST_SECONDS
                if t > startAt - buffer and t < endAt + buffer then
                    item.nearBang = true
                end
            end
            if smashBuffer > 0 then
                for _, start in ipairs(smashStarts()) do
                    if math.abs(t - start) < smashBuffer - 0.01 then
                        item.nearSmash = true
                        break
                    end
                end
            end
        end
    end
end

-- The verdict of a star, as the window writes it: text and colour.
local function verdictOf(item)
    if item.ignored then
        return "ignore", GREY
    elseif not item.committed then
        return "not damaged", GREY
    end
    local reasons = {}
    if item.nearSmash then
        reasons[#reasons + 1] = { "Cosmic Smash", "smash" }
    end
    if item.tooClose then
        reasons[#reasons + 1] = { "another star", "star" }
    end
    if item.nearBang then
        reasons[#reasons + 1] = { "Big Bang", "Big Bang" }
    end
    if #reasons == 0 then
        return "safe", GREEN
    end
    local names = {}
    for i, reason in ipairs(reasons) do
        names[i] = (#reasons == 1) and reason[1] or reason[2]
    end
    -- the verdict column is about 150 px wide: with several reasons the words "close to" are dropped so that all of them fit
    return ((#reasons == 1) and "close to " or "") .. table.concat(names, " + "), RED
end

local function relative(seconds)
    return string.format("%ds", math.max(seconds, 0) + 0.5)
end

function E.Update(now)
    model.header, model.headerColor, model.sub = "", WHITE, ""
    clear(model.rows)
    model.active = false
    if started and fightStart then
        local over
        if now - fightStart > ENRAGE + 5 then
            over = true
        elseif not testing and now - lastActivity > ACTIVITY_TIMEOUT then
            over = true
        end
        if over then
            E.Disarm()
        end
    end
    if not started or not fightStart then
        model.header, model.headerColor = "Waiting for the fight to start", GREY
        return model
    end
    local T = now - fightStart
    if T < 0 then
        model.header, model.headerColor = string.format("Fight starts in %s", relative(-T)), GREY
        model.active = true
        return model
    end
    model.active = true

    local items = buildItems(now, T)
    allocateRows(items)
    flagDeaths(items, T)
    for _, item in ipairs(items) do
        item.verdict, item.verdictColor = verdictOf(item)
    end
    model.header, model.headerColor = string.format("Fight %d:%02d", T / 60, T % 60), WHITE

    -- the next Big Bang, the next stars and the next Cosmic Smash
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
            pieces[#pieces + 1] = string.format("stars in %s", relative(waveAt(w) - T))
            break
        end
    end
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
