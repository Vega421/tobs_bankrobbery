-- Automated tests for client/minigames.lua (minigames per bank, played with tobs_minigames). They run
-- the real file outside FiveM, with a fake tobs_minigames. Run from the repo root:
-- lua5.4 tests/minigames_test.lua

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end end

TOB = {DrillTime = 15000, HackMinigame = "ox_lib", DrillMinigame = {"easy"}}
function L(k) return k end
function PlayerPedId() return 1 end
function IsEntityDead() return false end
local progress, progressOk = 0, true
function Progress() progress = progress + 1 return progressOk end

-- A fake tobs_minigames: records what it was asked, answers `answer` (true / false / nil)
local running, answer, played, broken = true, true, {}, false
function GetResourceState(res) return (res == "tobs_minigames" and running) and "started" or "missing" end
exports = setmetatable({}, {__index = function(_, res)
    if res ~= "tobs_minigames" then return nil end
    return {Start = function(_, name, opts)
        if broken then error("export failed") end
        played[#played + 1] = {name = name, opts = opts}
        return answer
    end}
end})

dofile("client/minigames.lua")

local function reset() played, progress, progressOk, answer, running, broken = {}, 0, true, true, true, false end
local fallbackGot
local function fallback(v) fallbackGot = v return true end

TOB.Banks = {
    B1 = {minigames = {hack = "hack", drill = "drill"}},
    F1 = {},
    F2 = {minigames = {hack = {type = "thermite", difficulty = "hard"}, drill = {type = "lockpick", difficulty = "easy"}}},
    F3 = {minigames = {hack = "gta_pc", drill = {type = "gta_drill", time = 5000}}},
    F4 = {minigames = {hack = function(bank) return bank == "F4" end, drill = function() return true end}},
}

-- Settings
check("a bank's own setting", MinigameSetting("B1", "hack") == "hack")
check("no setting: the global one", MinigameSetting("F1", "hack") == "ox_lib" and MinigameSetting("nope", "drill") == TOB.DrillMinigame)

-- Hack
reset()
check("B1: tobs_minigames' GTA laptop", BankHackMinigame("B1", function() error("no fallback") end) == true and played[1].name == "hack")
reset(); answer = false
check("... its failure counts", BankHackMinigame("B1", fallback) == false)
reset()
BankHackMinigame("F2", fallback)
check("any tobs_minigames game, with its settings", played[1].name == "thermite" and played[1].opts.difficulty == "hard")
reset()
BankHackMinigame("F3", fallback)
check("the old name gta_pc still means the laptop", played[1].name == "hack")
reset(); fallbackGot = nil
check("a bank without a setting: the resource's own minigame, with the global value", BankHackMinigame("F1", fallback) == true and fallbackGot == "ox_lib" and #played == 0)
reset(); running = false; fallbackGot = nil
check("tobs_minigames not running: the normal minigame instead", BankHackMinigame("B1", fallback) == true and fallbackGot == "ox_lib" and #played == 0)
reset(); answer = nil; fallbackGot = nil
check("a GTA screen that didn't load: the normal minigame instead", BankHackMinigame("B1", fallback) == true and fallbackGot == "ox_lib")
reset(); broken = true; fallbackGot = nil
check("an erroring export: the normal minigame instead", BankHackMinigame("B1", fallback) == true and fallbackGot == "ox_lib")
reset(); running = false; TOB.HackMinigame = "hack"; fallbackGot = nil
BankHackMinigame("B1", fallback)
check("... and if the global is a tobs_minigames game too: ox_lib", fallbackGot == "ox_lib")
-- function settings go to the resource's own code (which runs them safely), like its HackMinigame(bank, v)
local function own(bank) return function(v) if type(v) == "function" then return v(bank) end return true end end
TOB.HackMinigame = function(bank) FUNC_BANK = bank return true end
check("... and if the global is a function: it runs (through the resource's own code)", BankHackMinigame("B1", own("B1")) == true and FUNC_BANK == "B1" and #played == 0)
TOB.HackMinigame = "ox_lib"
reset()
check("a function setting goes to the resource's own code, with the bank", BankHackMinigame("F4", own("F4")) == true and #played == 0)

-- Drilling a deposit box
reset()
check("B1: the GTA drill, without a progress bar after it", DrillBoxMinigame("B1", function() error("no check") end) == true and played[1].name == "drill" and progress == 0)
check("... never shorter than TOB.DrillTime", played[1].opts.time == 15000)
reset()
DrillBoxMinigame("F3")
check("a shorter drill time is raised to TOB.DrillTime (and gta_drill still works)", played[1].name == "drill" and played[1].opts.time == 15000)
reset(); answer = false
check("a broken drill: not drilled", DrillBoxMinigame("B1") == false and progress == 0)
reset()
check("another game, then the progress bar", DrillBoxMinigame("F2") == true and played[1].name == "lockpick" and played[1].opts.difficulty == "easy" and progress == 1)
reset(); answer = false
check("... its failure means no progress bar and no second chance", DrillBoxMinigame("F2", function() error("no second chance") end) == false and progress == 0)
reset(); running = false
local checked
check("tobs_minigames not running: the skill check, then the progress bar", DrillBoxMinigame("B1", function(v) checked = v return true end) == true and progress == 1 and checked == TOB.DrillMinigame)
reset(); answer = nil
check("a GTA drill that didn't load: the skill check, then the progress bar", DrillBoxMinigame("B1", function() return true end) == true and progress == 1)
reset()
check("a bank without a setting: the skill check with the global value, then the progress bar",
      DrillBoxMinigame("F1", function(v) checked = v return true end) == true and checked == TOB.DrillMinigame and progress == 1 and #played == 0)
reset()
check("a failed skill check: no progress bar", DrillBoxMinigame("F1", function() return false end) == false and progress == 0)
reset()
local gotFn
check("a function setting goes to the skill check code, then the progress bar",
      DrillBoxMinigame("F4", function(v) gotFn = type(v) == "function" return v() end) == true and gotFn and progress == 1)
reset(); progressOk = false
check("an interrupted progress bar: not drilled", DrillBoxMinigame("F1") == false)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
