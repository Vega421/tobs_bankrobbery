-- Per-bank minigames. A bank in TOB.Banks can pick its own hack and drill minigame:
--
--   minigames = {hack = "gta_pc", drill = "gta_drill"}
--   minigames = {hack = {type = "gta_pc", lives = 3, background = 1}}   -- with options
--
-- Values: "gta_pc" (GTA hacking laptop, client/hack.lua), "gta_drill" (GTA drilling screen,
-- client/drill.lua), a function(bank) returning true/false, or anything the global setting accepts
-- ("ox_lib", "none", a list of ox_lib difficulties). Banks without one use TOB.HackMinigame /
-- TOB.DrillMinigame.

local Global = {hack = "HackMinigame", drill = "DrillMinigame"}
local Presets = {
    gta_pc = function(opts) return TOBHack.Start(opts) end,
    gta_drill = function(opts) return TOBDrill.Start(opts) end,
}

-- The minigame setting for this bank and step ("hack" or "drill")
function MinigameSetting(bank, kind)
    local b = TOB.Banks and TOB.Banks[bank]
    if b and type(b.minigames) == "table" and b.minigames[kind] ~= nil then return b.minigames[kind] end
    return TOB[Global[kind]]
end

-- Runs the bank's minigame and returns true/false (for the hack; drilling uses DrillBoxMinigame below). GTA presets and functions run here; any other
-- value goes to fallback(value), the resource's normal minigame code.
function RunMinigame(bank, kind, fallback)
    local v = MinigameSetting(bank, kind)
    if type(v) == "function" then return v(bank) == true end
    local name, opts = v, nil
    if type(v) == "table" and v.type then name, opts = v.type, v end
    if Presets[name] then return Presets[name](opts) == true end
    return fallback(v) == true
end

-- The whole drilling step for a deposit box: call this where the resource runs the drill skill check
-- and the progress bar. The GTA drill is timed itself (never faster than TOB.DrillTime), so it
-- replaces the progress bar. Any other setting runs check(value) first (the resource's own skill
-- check, returning true/false; nil = no check), or a function setting with the bank, and then the
-- progress bar of TOB.DrillTime.
function DrillBoxMinigame(bank, check)
    local v = MinigameSetting(bank, "drill")
    local name, opts = v, nil
    if type(v) == "table" and v.type then name, opts = v.type, v end
    if name == "gta_drill" then return TOBDrill.Start(opts) == true end
    if type(v) == "function" then
        if v(bank) ~= true then return false end
    elseif check and check(v) ~= true then
        return false
    end
    return Progress(TOB.DrillTime, L("drilling")) == true and not IsEntityDead(PlayerPedId())
end
