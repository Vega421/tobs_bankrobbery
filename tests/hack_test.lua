-- Automated tests for the hacking laptop (client/hack.lua) and per-bank minigames (client/minigames.lua).
-- They run the real files outside FiveM, with fake natives. Run from the repo root:  lua5.4 tests/hack_test.lua

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end end

TOB = {Locale = "en", DrillTime = 15000, MinigameDifficulty = {"easy"}, MinigameKeys = {"e"}}
local now = 0
Citizen = {Wait = function() now = now + 16 end}
function GetGameTimer() return now end

-- Fake natives. Each frame, script(frame) can press keys; clicks answer with the next id in `answers`.
local calls, method, params = {}, nil, nil
local pressed, answers, frame, script = {}, {}, 0, nil
local loaded, dead = true, false
local function record() calls[#calls + 1] = {method, table.unpack(params)} end
function RequestScaleformMovieSkipRenderWhilePaused(n) calls[#calls + 1] = {"load " .. n} return 9 end
function HasScaleformMovieLoaded() return loaded end
function BeginScaleformMovieMethod(_, m) method, params = m, {} end
function ScaleformMovieMethodAddParamInt(v) params[#params + 1] = v end
function ScaleformMovieMethodAddParamFloat(v) params[#params + 1] = v end
function ScaleformMovieMethodAddParamBool(v) params[#params + 1] = v end
function ScaleformMovieMethodAddParamTextureNameString(v) params[#params + 1] = v end
function EndScaleformMovieMethod() record() end
function EndScaleformMovieMethodReturnValue() record() return 77 end
function IsScaleformMovieMethodReturnValueReady(h) return h == 77 end
function GetScaleformMovieMethodReturnValueInt() return table.remove(answers, 1) or 0 end
function SetScaleformMovieAsNoLongerNeeded() calls[#calls + 1] = {"unload"} end
function DrawScaleformMovieFullscreen()
    frame = frame + 1
    pressed = {}
    if script then script(frame) end
end
function IsDisabledControlJustPressed(_, c) return pressed[c] == true end
function GetControlNormal() return 0.5 end
function DisableControlAction() end
function PlayerPedId() return 1 end
function IsEntityDead() return dead end
local sounds = {}
function PlaySoundFrontend(_, name) sounds[#sounds + 1] = name end
for _, n in ipairs({"SetTextFont", "SetTextScale", "SetTextColour", "SetTextCentre", "SetTextOutline",
                    "BeginTextCommandDisplayText", "AddTextComponentSubstringPlayerName", "EndTextCommandDisplayText"}) do _G[n] = function() end end

dofile("client/hack.lua")
TOBDrill = {Start = function(opts) DRILLOPTS = opts return true end}
dofile("client/minigames.lua")

local function named(m)
    local out = {}
    for _, c in ipairs(calls) do if c[1] == m then out[#out + 1] = c end end
    return out
end

-- Runs TOBHack.Start; clicks[frame] = id means a left click on that frame answers with id
local function hack(clicks, opts, extra)
    calls, answers, frame, sounds, dead = {}, {}, 0, {}, false
    script = function(f)
        if clicks[f] then pressed[24] = true; answers[#answers + 1] = clicks[f] end
        if extra then extra(f) end
    end
    return TOBHack.Start(opts)
end
local R = TOBHack.Result

-- Handle: the rules, one click result at a time
local o = {lives = 3, ipConnect = true, columnSpeed = {150, 255}}
local t = {ip_first = "first", ip_ok = "ok", win = "win", lose = "lose"}
local g = {lives = 3}
calls = {}
check("BruteForce before HackConnect is refused", TOBHack.Handle(9, g, R.BRUTEFORCE, o, t) == nil and g.app == nil and g.note == "first")
TOBHack.Handle(9, g, R.HACKCONNECT, o, t)
check("HackConnect opens the IP app", g.app == "ip" and named("OPEN_APP")[1][2] == 0.0)
TOBHack.Handle(9, g, R.WORD_WIN, o, t)
check("a BruteForce win can't end the IP app", g.app == "ip")
TOBHack.Handle(9, g, R.WRONG_LETTER, o, t)
check("a wrong pick in IP Connect costs a life", g.lives == 2)
TOBHack.Handle(9, g, R.IP_WIN, o, t)
check("IP Connect won: back to the desktop", g.app == nil and g.ipDone == true)
TOBHack.Handle(9, g, R.BRUTEFORCE, o, t)
local word = named("SET_ROULETTE_WORD")[1]
check("BruteForce opens with an 8 letter password", g.app == "word" and #word[2] == 8 and word[2]:match("^%u+$"))
check("desktop clicks do nothing inside an app", TOBHack.Handle(9, g, R.HACKCONNECT, o, t) == nil and g.app == "word")
TOBHack.Handle(9, g, R.WRONG_LETTER, o, t)
check("wrong letter: one life left", g.lives == 1)
check("last life gone: hack failed", TOBHack.Handle(9, g, R.WRONG_LETTER, o, t) == false)
g = {lives = 3, app = "word"}
check("all letters found: hacked", TOBHack.Handle(9, g, R.WORD_WIN, o, t) == true)
check("IP Connect lost: hack failed", TOBHack.Handle(9, {lives = 3, app = "ip"}, R.IP_LOSE, o, t) == false)
check("Power Off: hack failed", TOBHack.Handle(9, {lives = 3}, R.POWER_OFF, o, t) == false)
g = {lives = 3}
TOBHack.Handle(9, g, R.BRUTEFORCE, {lives = 3, ipConnect = false}, t)
check("ipConnect = false: BruteForce opens straight away", g.app == "word")
check("custom words are used", TOBHack.Word({words = {"PALETOBY"}}) == "PALETOBY")

-- Start: the whole laptop with scripted clicks
local r = hack({[2] = R.HACKCONNECT, [5] = R.IP_WIN, [8] = R.BRUTEFORCE, [12] = R.WORD_WIN})
check("full hack: HackConnect, then BruteForce -> true", r == true)
check("loads HACKING_PC", calls[1][1] == "load HACKING_PC")
check("sets 8 column speeds", #named("SET_COLUMN_SPEED") == 8)
check("sets up the desktop", #named("ADD_PROGRAM") == 2 and #named("SET_LABELS") == 1)
check("the win message stays up ~2.5 s before closing", frame >= 12 + 2500 / 16 - 1)
check("frees the laptop when done", calls[#calls][1] == "unload" and not TOBHack.active)

r = hack({[2] = R.BRUTEFORCE}, {lives = 2, ipConnect = false}, function(f) if f == 4 or f == 6 then pressed[24] = true; answers[#answers + 1] = R.WRONG_LETTER end end)
check("out of lives -> false", r == false)
r = hack({[2] = R.POWER_OFF})
check("Power Off -> false", r == false)
r = hack({}, {timeLimit = 2})
check("time runs out -> false", r == false and now > 0)
r = hack({}, nil, function(f) if f == 3 then pressed[200] = true end end)
check("ESC -> false", r == false and frame == 3)
r = hack({}, nil, function(f) if f == 3 then dead = true end end)
check("dying -> false", r == false)
r = hack({[2] = R.HACKCONNECT}, nil, function(f)
    if f == 4 then pressed[172] = true end
    if f == 6 then pressed[176] = true; answers[#answers + 1] = R.IP_WIN end
    if f == 8 then pressed[24] = true; answers[#answers + 1] = R.POWER_OFF end
end)
check("arrow up in IP Connect is sent to the laptop", named("SET_INPUT_EVENT")[1] and named("SET_INPUT_EVENT")[1][2] == 8)
check("Enter selects inside an app", #named("SET_INPUT_EVENT_SELECT") >= 2)
TOB.HackGame = {background = 1}
hack({[2] = R.POWER_OFF})
check("TOB.HackGame sets the wallpaper", named("SET_BACKGROUND")[1][2] == 1)
TOB.HackGame = nil
TOBHack.active = true
check("a second laptop while one is open is refused", TOBHack.Start() == false)
TOBHack.active = false

loaded = false
check("no laptop screen: nil, so the caller runs its normal minigame", hack({}) == nil and not TOBHack.active)
loaded = true

-- Per-bank minigames
TOB.HackMinigame, TOB.DrillMinigame = "ox_lib", {"easy"}
TOB.Banks = {B1 = {minigames = {hack = "gta_pc", drill = "gta_drill"}}, F1 = {}, F2 = {minigames = {hack = {type = "gta_pc", lives = 2}}},
             F3 = {minigames = {drill = function(bank) return bank == "F3" end}}}
check("bank with its own setting", MinigameSetting("B1", "hack") == "gta_pc")
check("bank without: the global setting", MinigameSetting("F1", "hack") == "ox_lib" and MinigameSetting("F1", "drill") == TOB.DrillMinigame)
check("unknown bank: the global setting", MinigameSetting("nope", "drill") == TOB.DrillMinigame)
calls, script, frame = {}, nil, 0
r = BankHackMinigame("B1", function() error("fallback shouldn't run") end)
check("B1 hack runs the GTA laptop", r == false and calls[1][1] == "load HACKING_PC") -- no clicks: times out
local got
check("F1 uses the resource's normal code with the global value", BankHackMinigame("F1", function(v) got = v return true end) == true and got == "ox_lib")
calls, frame = {}, 0
script = function(f) if f == 2 then pressed[24] = true; answers[#answers + 1] = R.POWER_OFF end end
BankHackMinigame("F2", function() end)
check("options in the bank setting reach the laptop", named("SET_LIVES")[1][2] == 2)
TOB.Banks.F5 = {minigames = {hack = function(bank) return bank == "F5" end}}
check("a function setting gets the bank", BankHackMinigame("F5", function() error("no fallback") end) == true)
TOB.Banks.F5.minigames.hack = function() return "yes" end
check("a function must return true to pass", BankHackMinigame("F5", function() end) == false)
loaded, got = false, nil
check("laptop doesn't load: the global setting runs instead", BankHackMinigame("B1", function(v) got = v return true end) == true and got == "ox_lib")
TOB.HackMinigame = "gta_pc"
BankHackMinigame("B1", function(v) got = v return true end)
check("... and if the global is the laptop too: ox_lib", got == "ox_lib")
TOB.HackMinigame = function(bank) got = bank return true end
check("... and if the global is a function: it runs with the bank", BankHackMinigame("B1", function() error("no fallback") end) == true and got == "B1")
TOB.HackMinigame, loaded = "ox_lib", true

-- Deposit box drilling: the GTA drill replaces the progress bar, everything else runs before it
local progress, checked = 0, nil
function Progress() progress = progress + 1 return PROGRESS_OK end
function L(k) return k end
PROGRESS_OK = true
TOB.Banks.F4 = {minigames = {drill = {type = "gta_drill", heat = 0.2}}}
progress, DRILLOPTS = 0, nil
check("GTA drill: no progress bar after it", DrillBoxMinigame("B1", function() error("no skill check") end) == true and progress == 0)
check("GTA drill with options gets them", DrillBoxMinigame("F4") == true and DRILLOPTS.heat == 0.2 and progress == 0)
check("other banks: skill check with the global value, then the progress bar",
      DrillBoxMinigame("F1", function(v) checked = v return true end) == true and checked == TOB.DrillMinigame and progress == 1)
progress = 0
check("failed skill check: no progress bar", DrillBoxMinigame("F1", function() return false end) == false and progress == 0)
check("no skill check given: just the progress bar", DrillBoxMinigame("F1") == true and progress == 1)
progress = 0
TOB.Banks.F3.minigames.drill = function(bank) return bank == "F3" end
check("a function setting runs, then the progress bar", DrillBoxMinigame("F3") == true and progress == 1)
PROGRESS_OK = false
check("interrupted progress bar: not drilled", DrillBoxMinigame("F1") == false)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
