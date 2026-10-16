-- Per-bank minigames, played with tobs_minigames (https://github.com/Vega421/tobs_minigames) when it
-- is running. A bank in TOB.Banks can pick its own hack, gate and drill minigame:
--
--   minigames = {hack = "hack", gate = "thermite", drill = "drill"}           -- GTA's laptop, thermite, GTA's drill
--   minigames = {hack = "thermite", drill = {type = "drill", difficulty = "hard"}}
--
-- gate is the inner gate's minigame (banks with doors.secondloc); without it the gate plays the hack
-- minigame again. A gate game other than the laptop plays tobs_minigames' own animation instead of
-- the laptop scene.
--
-- Values: any tobs_minigames game ("hack", "drill", "safe", "thermite", "keypad", "wires", "lockpick",
-- "fingerprint", "hotwire", "lasers", "keyfiling", "tracker"; the old "gta_pc" / "gta_drill" mean
-- "hack" / "drill"), as a table to add a difficulty or settings; a function(bank) returning
-- true/false; or anything the global setting accepts ("ox_lib", "none", a list of ox_lib
-- difficulties). Banks without one use TOB.HackMinigame / TOB.DrillMinigame.
-- Without tobs_minigames, or when a GTA screen doesn't load, the resource's own minigame runs instead.
-- Loaded on the server too (shared script), so the health check uses the same list of games.

local Global = {hack = "HackMinigame", gate = "HackMinigame", drill = "DrillMinigame"}
local Games = {hack = true, drill = true, safe = true, thermite = true, keypad = true, wires = true, lockpick = true,
               fingerprint = true, hotwire = true, lasers = true, keyfiling = true, tracker = true}
local Old = {gta_pc = "hack", gta_drill = "drill"}

-- The minigame setting for this bank and step ("hack", "gate" or "drill"). A bank without a gate
-- setting plays its hack minigame at the gate.
function MinigameSetting(bank, kind)
    local b = TOB.Banks and TOB.Banks[bank]
    if b and type(b.minigames) == "table" and b.minigames[kind] ~= nil then return b.minigames[kind] end
    if kind == "gate" then return MinigameSetting(bank, "hack") end
    return TOB[Global[kind]]
end

-- The tobs_minigames game a setting names, and its settings: "thermite" or {type = "drill", ...}.
-- nil for anything else ("ox_lib", "none", a list of difficulties, a function).
function MinigameGame(v)
    local name, opts = v, nil
    if type(v) == "table" and v.type then name, opts = v.type, v end
    if type(name) ~= "string" then return nil end
    name = Old[name] or name
    if Games[name] then return name, opts end
    return nil
end

-- Plays a tobs_minigames game: true / false, or nil when it can't (not running, a GTA screen missing).
-- Without tobs_minigames' own animation (the heist plays the laptop scene and the drill), unless
-- animate: then the bank's setting decides ({animate = false} still turns it off).
local function Play(name, opts, animate)
    if GetResourceState("tobs_minigames") ~= "started" then return nil end
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    if not animate then o.animate = false end
    local ok, result = pcall(function() return exports.tobs_minigames:Start(name, o) end)
    if not ok then return nil end
    return result
end

-- The GTA drill is the timed part of drilling, so it's never shorter than TOB.DrillTime
local function DrillOptions(opts)
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.time = math.max(tonumber(o.time) or 0, TOB.DrillTime or 0)
    return o
end

-- The global setting, when the bank's tobs_minigames game can't be played. A tobs_minigames game
-- there can't be the fallback either, so then the plain skill check is used.
local function Fallback(kind)
    local v = TOB[Global[kind]]
    if MinigameGame(v) then return kind == "hack" and "ox_lib" or {"easy", "medium"} end
    return v
end

-- The bank's hack minigame; returns true/false. tobs_minigames games run here; anything else
-- ("ox_lib", "none", difficulties, a function) goes to fallback(value), the resource's own minigame
-- code, which also catches errors in function settings.
local function HackStep(bank, kind, fallback, animate)
    local v = MinigameSetting(bank, kind)
    local name, opts = MinigameGame(v)
    if name then
        local result = Play(name, opts, animate and name ~= "hack")
        if result ~= nil then return result == true end
        v = Fallback(kind)
    end
    return fallback(v) == true
end

function BankHackMinigame(bank, fallback)
    return HackStep(bank, "hack", fallback, false)
end

-- True when the inner gate's minigame is played at the laptop: GTA's hacking laptop, or the
-- resource's own minigame (also when tobs_minigames isn't running). Any other tobs_minigames game
-- plays its own animation instead.
function GateUsesLaptop(bank)
    local name = MinigameGame(MinigameSetting(bank, "gate"))
    if not name or name == "hack" then return true end
    return GetResourceState("tobs_minigames") ~= "started"
end

-- The inner gate's minigame (the bank's gate setting, else its hack setting); returns true/false.
-- Games other than the laptop animate through tobs_minigames when the laptop scene isn't playing.
function BankGateMinigame(bank, fallback)
    return HackStep(bank, "gate", fallback, not GateUsesLaptop(bank))
end

-- The whole drilling step for a deposit box: call this where the resource runs the drill skill check
-- and the progress bar. The GTA drill ("drill") is timed itself (never faster than TOB.DrillTime), so
-- it replaces the progress bar. Any other game, or check(value) (the resource's own skill check for
-- difficulties or a function, returning true/false; nil = no check) runs first, then the progress bar.
function DrillBoxMinigame(bank, check)
    local v = MinigameSetting(bank, "drill")
    local name, opts = MinigameGame(v)
    if name == "drill" then
        local result = Play("drill", DrillOptions(opts))
        if result ~= nil then return result == true end
    end
    local passed
    if name and name ~= "drill" then passed = Play(name, opts) end -- false must stay false
    if passed == nil then
        passed = not check or check(name and Fallback("drill") or v) == true
    end
    if passed ~= true then return false end
    return Progress(TOB.DrillTime, L("drilling")) == true and not IsEntityDead(PlayerPedId())
end
