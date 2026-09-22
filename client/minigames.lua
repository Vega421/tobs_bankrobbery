-- Per-bank minigames, played with tobs_minigames (https://github.com/Vega421/tobs_minigames) when it
-- is running. A bank in TOB.Banks can pick its own hack and drill minigame:
--
--   minigames = {hack = "hack", drill = "drill"}                              -- GTA's laptop and drill
--   minigames = {hack = "thermite", drill = {type = "drill", difficulty = "hard"}}
--
-- Values: any tobs_minigames game ("hack", "drill", "safe", "thermite", "keypad", "wires", "lockpick",
-- "fingerprint", "hotwire", "lasers", "keyfiling", "tracker"; the old "gta_pc" / "gta_drill" mean
-- "hack" / "drill"), as a table to add a difficulty or settings; a function(bank) returning
-- true/false; or anything the global setting accepts ("ox_lib", "none", a list of ox_lib
-- difficulties). Banks without one use TOB.HackMinigame / TOB.DrillMinigame.
-- Without tobs_minigames, or when a GTA screen doesn't load, the resource's own minigame runs instead.

local Global = {hack = "HackMinigame", drill = "DrillMinigame"}
local Games = {hack = true, drill = true, safe = true, thermite = true, keypad = true, wires = true, lockpick = true,
               fingerprint = true, hotwire = true, lasers = true, keyfiling = true, tracker = true}
local Old = {gta_pc = "hack", gta_drill = "drill"}

-- The minigame setting for this bank and step ("hack" or "drill")
function MinigameSetting(bank, kind)
    local b = TOB.Banks and TOB.Banks[bank]
    if b and type(b.minigames) == "table" and b.minigames[kind] ~= nil then return b.minigames[kind] end
    return TOB[Global[kind]]
end

-- The tobs_minigames game a setting names, and its settings: "thermite" or {type = "drill", ...}.
-- nil for anything else ("ox_lib", "none", a list of difficulties, a function).
local function Game(v)
    local name, opts = v, nil
    if type(v) == "table" and v.type then name, opts = v.type, v end
    if type(name) ~= "string" then return nil end
    name = Old[name] or name
    if Games[name] then return name, opts end
    return nil
end

-- Plays a tobs_minigames game: true / false, or nil when it can't (not running, a GTA screen missing).
-- Without tobs_minigames' own animation: the heist already plays the laptop scene and the drill.
local function Play(name, opts)
    if GetResourceState("tobs_minigames") ~= "started" then return nil end
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.animate = false
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

-- The global setting, when the bank's minigame can't be played: a tobs_minigames game or a function
-- there can't be the fallback, so then the plain skill check is used
local function Fallback(kind)
    local v = TOB[Global[kind]]
    if Game(v) or type(v) == "function" then return kind == "hack" and "ox_lib" or {"easy", "medium"} end
    return v
end

-- The bank's hack minigame; returns true/false. tobs_minigames games and function settings run here;
-- anything else goes to fallback(value), the resource's own minigame code.
function BankHackMinigame(bank, fallback)
    local v = MinigameSetting(bank, "hack")
    if type(v) == "function" then return v(bank) == true end
    local name, opts = Game(v)
    if name then
        local result = Play(name, opts)
        if result ~= nil then return result == true end
        local global = TOB.HackMinigame
        if type(global) == "function" then return global(bank) == true end
        v = Fallback("hack")
    end
    return fallback(v) == true
end

-- The whole drilling step for a deposit box: call this where the resource runs the drill skill check
-- and the progress bar. The GTA drill ("drill") is timed itself (never faster than TOB.DrillTime), so
-- it replaces the progress bar. Any other game, a function setting, or check(value) (the resource's
-- own skill check, returning true/false; nil = no check) runs first, then the progress bar.
function DrillBoxMinigame(bank, check)
    local v = MinigameSetting(bank, "drill")
    local name, opts = Game(v)
    if name == "drill" then
        local result = Play("drill", DrillOptions(opts))
        if result ~= nil then return result == true end
    end
    local passed
    if type(v) == "function" then
        passed = v(bank) == true
    elseif name then
        if name ~= "drill" then passed = Play(name, opts) end -- not `x and y or nil`: false must stay false
        if passed == nil then passed = not check or check(Fallback("drill")) == true end
    else
        passed = not check or check(v) == true
    end
    if passed ~= true then return false end
    return Progress(TOB.DrillTime, L("drilling")) == true and not IsEntityDead(PlayerPedId())
end
