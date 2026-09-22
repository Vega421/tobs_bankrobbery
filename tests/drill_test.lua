-- Automated tests for the drilling minigame (client/drill.lua). They run the real file outside FiveM,
-- with fake natives. Run from the repo root:  lua5.4 tests/drill_test.lua

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end end

TOB = {Locale = "en", DrillTime = 15000}
Citizen = {Wait = function() end}
function L(k) return k end

-- Fake natives: controls are read from `held` / `pressed`, the scaleform calls are recorded
local held, pressed, calls, method = {}, {}, {}, nil
local loaded, dead, frames, script = true, false, 0, nil
function IsDisabledControlPressed(_, c) return held[c] == true end
function IsControlPressed(_, c) return held[c] == true end
function IsControlJustPressed(_, c) return pressed[c] == true end
function IsDisabledControlJustPressed(_, c) return pressed[c] == true end
function DisableControlAction() end
function PlayerPedId() return 1 end
function IsEntityDead() return dead end
function GetFrameTime()
    frames = frames + 1
    if script then script(frames) end
    return 1 / 60
end
function RequestScaleformMovie(name) calls[#calls + 1] = "load " .. name return 7 end
function HasScaleformMovieLoaded() return loaded end
function BeginScaleformMovieMethod(_, m) method = m end
function ScaleformMovieMethodAddParamFloat(v) calls[#calls + 1] = method .. " " .. v end
function EndScaleformMovieMethod() end
function SetScaleformMovieAsNoLongerNeeded() calls[#calls + 1] = "unload" end
for _, n in ipairs({"DrawScaleformMovieFullscreen", "BeginTextCommandDisplayHelp", "AddTextComponentSubstringPlayerName", "EndTextCommandDisplayHelp"}) do _G[n] = function() end end
local progressed
function Progress(ms, label) progressed = {ms, label} return true end
local fx = {}
local now = 0
function GetGameTimer() now = now + 16 return now end
function PlaySoundFrontend(_, name, set) fx[#fx + 1] = name .. "@" .. set end
function ShakeGameplayCam(name, amp) fx[#fx + 1] = "shake " .. name end
function SetGameplayCamShakeAmplitude(a) fx[#fx + 1] = "amp " .. a end
function StopGameplayCamShaking() fx[#fx + 1] = "stop shake" end
function SetPadShake(_, ms, f) fx[#fx + 1] = "pad " .. ms .. " " .. f end
function StopPadShake() fx[#fx + 1] = "stop pad" end
local function has(prefix, list)
    local n = 0
    for _, v in ipairs(list or fx) do if v:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
end

dofile("client/drill.lua")

-- Runs Step at 60 fps with a strategy fn(s) -> input until it ends; returns result and seconds taken
local function simulate(strategy, o)
    o = o or TOBDrill.Defaults
    local s, t = {speed = 0, pos = 0, depth = 0, heat = 0}, 0
    for _ = 1, 60 * 600 do
        t = t + 1 / 60
        local r = TOBDrill.Step(s, strategy(s), 1 / 60, o)
        if r ~= nil then return r, t, s end
    end
    return nil, t, s
end

local function flatOut(s) return {push = true, faster = s.speed < 1} end
local function careful(s)
    if s.heat > 0.8 then s.resting = true elseif s.heat < 0.2 then s.resting = false end
    return {push = not s.resting, faster = s.speed < 1}
end
local function cruise(s) return {push = true, faster = s.speed < 0.7, slower = s.speed > 0.72} end

-- Rules
local r, t = simulate(flatOut)
check("full speed without pausing overheats and breaks", r == false and t < 15)
r, t = simulate(careful)
check("pausing to cool drills through", r == true)
check("never faster than TOB.DrillTime", t >= 15)
check("a careful drill takes under twice the drill time (" .. string.format("%.1f", t) .. " s)", t < 30)
r, t = simulate(cruise)
check("cruising at 70 % never overheats", r == true)
local fastest = select(2, simulate(function(s) s.heat = 0 return {push = true, faster = true} end))
check("even with no heat at all it takes TOB.DrillTime", fastest >= 15)

local s = {speed = 0.05, pos = 0, depth = 0, heat = 0}
TOBDrill.Step(s, {push = true}, 1, TOBDrill.Defaults)
check("too slow: the drill doesn't cut", s.pos == 0)
s = {speed = 1, pos = 0.2, depth = 0.5, heat = 0.5}
TOBDrill.Step(s, {push = true}, 0.1, TOBDrill.Defaults)
check("pushing through the drilled part moves without heating", s.pos > 0.2 and s.depth == 0.5 and s.heat < 0.5)
s = {speed = 1, pos = 0.5, depth = 0.5, heat = 0}
TOBDrill.Step(s, {back = true}, 0.1, TOBDrill.Defaults)
check("pulling back keeps the hole depth", s.pos < 0.5 and s.depth == 0.5)
s = {speed = 0.5, pos = 0.5, depth = 0.5, heat = 0}
TOBDrill.Step(s, {push = true}, 5, TOBDrill.Defaults)
check("a long frame counts as at most 0.1 s", s.pos <= 0.5 + 0.5 * 0.1 / 15 + 1e-9)
local slow = select(2, simulate(careful, {time = 30000, heat = 0.3, cool = 0.25, minSpeed = 0.1}))
check("a longer time makes drilling slower", slow >= 30)

-- Events for the effects
s = {speed = 1, pos = 0.198, depth = 0.198, heat = 0}
local _, ev = TOBDrill.Step(s, {push = true}, 0.1, TOBDrill.Defaults)
check("crossing a pin depth: pin event", ev == "pin" and s.cutting == true)
_, ev = TOBDrill.Step(s, {push = true}, 0.01, TOBDrill.Defaults)
check("a pin breaks only once", ev == nil)
s = {speed = 0.05, pos = 0.3, depth = 0.3, heat = 0}
_, ev = TOBDrill.Step(s, {push = true}, 0.1, TOBDrill.Defaults)
check("pushing too slowly: jam event", ev == "jam" and s.cutting == false)
s = {speed = 0.05, pos = 0.1, depth = 0.3, heat = 0}
_, ev = TOBDrill.Step(s, {push = true}, 0.1, TOBDrill.Defaults)
check("no jam inside the drilled part", ev == nil)
local st, count = {speed = 0, pos = 0, depth = 0, heat = 0}, 0
for _ = 1, 60 * 600 do
    local r2, e = TOBDrill.Step(st, careful(st), 1 / 60, TOBDrill.Defaults)
    if e == "pin" then count = count + 1 end
    if r2 ~= nil then break end
end
check("a full drill breaks all 4 pins", count == 4)

-- Start: the whole screen, with scripted key presses
local function start(fn, opts)
    held, pressed, calls, frames, dead, script, fx = {}, {}, {}, 0, false, fn, {}
    return TOBDrill.Start(opts)
end
r = start(function() held = {[35] = true, [32] = true} end)
check("holding W + D at full speed breaks the drill", r == false)
check("loads the DRILLING scaleform", calls[1] == "load DRILLING")
check("sets speed, position, temperature and depth", table.concat(calls, ","):find("SET_TEMPERATURE 0.") and table.concat(calls, ","):find("SET_HOLE_DEPTH 0.") ~= nil)
check("frees the scaleform when done", calls[#calls] == "unload" and TOBDrill.active == false)
check("overheating plays the jam sound", has("Drill_Jam@DLC_HEIST_FLEECA_SOUNDSET") >= 1)
check("camera shakes while cutting and stops after", has("shake ROAD_VIBRATION_SHAKE") == 1 and has("amp 0.") > 0 and has("stop shake") == 1 and has("stop pad") == 1)
check("controller vibrates while cutting", has("pad 50 ") > 0)

r = start(function() held = {[32] = true, [175] = true} end, {heat = 0.0})
check("with no heat, the arrow keys drill through", r == true)
check("and it took TOB.DrillTime", frames / 60 >= 15)
check("4 pin break sounds with a jolt each", has("Drill_Pin_Break@DLC_HEIST_FLEECA_SOUNDSET") == 4 and has("pad 300 255") == 4 and has("amp 2.0") >= 1)
r = start(function(f) held = {[32] = true} if f == 150 then pressed = {[177] = true} end end)
check("pushing without speed jams: one sound per 1.5 s (2 in 2.4 s)", has("Drill_Jam") == 2)
TOB.DrillGame = {shake = false, heat = 0.0}
r = start(function() held = {[32] = true, [35] = true} end)
check("shake = false: no camera or controller shake", has("shake") == 0 and has("amp") == 0 and has("pad") == 0 and has("stop") == 0)
check("... but the pin sounds still play", has("Drill_Pin_Break") == 4)
TOB.DrillGame = nil

r = start(function(f) held = {[32] = true, [35] = true} if f == 30 then pressed = {[177] = true} end end)
check("Backspace stops drilling (false)", r == false and frames == 30)
r = start(function(f) held = {[32] = true} if f == 10 then dead = true end end)
check("dying stops drilling (false)", r == false)
TOBDrill.active = true
check("a second drill while one is running is refused", TOBDrill.Start() == false)
TOBDrill.active = false

TOB.DrillTime = 20000
r = start(function() held = {[32] = true, [35] = true} end, {heat = 0.0, time = 5000})
check("time can't go below TOB.DrillTime", r == true and frames / 60 >= 20)
TOB.DrillTime = 15000

TOB.DrillGame = {heat = 0.0}
r = start(function() held = {[32] = true, [35] = true} end)
check("TOB.DrillGame overrides the defaults", r == true)
TOB.DrillGame = nil

loaded = false
r = start(function() end)
check("no scaleform: falls back to a progress bar", r == true and progressed[1] == 15000 and progressed[2] == "drilling")
check("the fallback doesn't lock the minigame", TOBDrill.active ~= true)
loaded = true

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
