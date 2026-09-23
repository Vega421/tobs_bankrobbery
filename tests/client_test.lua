-- Automated tests for tobs_bankrobbery's client. They run the real client files outside FiveM, with small fake
-- versions of the game functions and a fake framework bridge. Run from the repo root:  lua5.4 tests/client_test.lua
-- GitHub runs them on every push (.github/workflows/tests.yml).

local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, V) end
V.__add = function(a, b) return setmetatable({x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end

-- FAKE GAME --
-- Any game function the tests don't define returns false and is counted in CALLS[name].
-- Read script globals that can be nil with rawget(_G, name), or this returns a function.
CALLS = {}
setmetatable(_G, {__index = function(_, name)
    return function() CALLS[name] = (CALLS[name] or 0) + 1; return false end
end})
local handlers, serverEvents, zones, notes, commands, exportCalls, printed = {}, {}, {}, {}, {}, {}, {}
local threads = {}
local clock = 0
-- STOPWAIT makes Wait() stop a thread, so one pass of a "while true" loop can be run with pcall
STOPWAIT = false
Citizen = {CreateThread = function(fn) threads[#threads + 1] = fn end, SetTimeout = function() end, Wait = function() if STOPWAIT then error("stop") end end}
function GetPlayerServerId() return 7 end
function PlayerId() return 1 end
function GetPlayerFromServerId(id) return id == 99 and -1 or id end
function GetPlayerPed(p) return p end
function GetGameTimer() clock = clock + 100; return clock end
function SetTimeout() end
function RegisterNetEvent() end
function AddEventHandler(n, fn) handlers[n] = fn end
function TriggerServerEvent(n, ...) serverEvents[#serverEvents + 1] = {n, ...} end
function RegisterCommand(n, fn) commands[n] = fn end
RUNNING = {ox_target = true, ox_lib = true}
function GetResourceState(r) return RUNNING[r] and "started" or "missing" end
PEDPOS = vector3(1000, 1000, 0)
function PlayerPedId() return 1 end
function GetEntityCoords() return PEDPOS end
function GetClosestObjectOfType() return 0 end
function GetEntityHeading() return 0.0 end
function GetHashKey(s) return #s end
function AddBlipForCoord() CALLS.AddBlipForCoord = (CALLS.AddBlipForCoord or 0) + 1; return 5 end
function IsControlJustReleased() return PRESSED == true end
print = function(s) printed[#printed + 1] = s end
-- exports.resource:fn(data) is recorded; ox_target zones are kept
SKILL = true
exports = setmetatable({}, {__index = function(_, res)
    return setmetatable({}, {__index = function(_, fn)
        return function(_, data, ...)
            exportCalls[#exportCalls + 1] = {res = res, fn = fn, data = data, opts = (...)}
            if fn == "addSphereZone" then zones[#zones + 1] = data end
            if fn == "skillCheck" then return SKILL end
            if fn == "Start" and res == "tobs_minigames" then return rawget(_G, "MGRESULT") end
            return true
        end
    end})
end})
function TriggerEvent(n, ...)
    if n == "ox_lib:notify" then notes[#notes + 1] = select(1, ...).description return end
    if handlers[n] then handlers[n](...) end
end
local function lastExport(fn) for i = #exportCalls, 1, -1 do if exportCalls[i].fn == fn then return exportCalls[i] end end end
local function lastServer(n) for i = #serverEvents, 1, -1 do if serverEvents[i][1] == n then return serverEvents[i] end end end

dofile("config/config.lua"); dofile("config/banks.lua"); dofile("locales/locales.lua")
-- The shipped config has an inner gate at every bank (Paleto too). These tests use Paleto as the bank
-- WITHOUT one and Fleeca F1 as the bank with one, so both kinds stay covered; the shipped gates are
-- checked separately below.
SHIPPED_B1 = {secondloc = TOB.Banks.B1.doors.secondloc, gateModel = TOB.Banks.B1.gateModel, gate = TOB.Banks.B1.gate}
TOB.Banks.B1.doors.secondloc = nil
-- Fake framework bridge (the real ones are tested in tests/bridge_test.lua)
POLICE = false
RUNNING_HEISTS = {} -- heists running when this player joins (test 10)
Bridge = {FrameworkNotify = function(m) notes[#notes + 1] = m end,
          Init = function(cb) INITCB = cb end,
          IsPolice = function() return POLICE end,
          TriggerCallback = function(n, cb) cb({B1 = TOB.Banks.B1, F1 = TOB.Banks.F1}, DOORS, RUNNING_HEISTS) end,
          Notify = function(m) notes[#notes + 1] = m end}
DOORS = {F1 = {{loc = TOB.Banks.F1.gate.loc, h = 1, txtloc = TOB.Banks.F1.gate.txtloc, locked = true}, {loc = TOB.Banks.F1.vault.loc, txtloc = TOB.Banks.F1.vault.txtloc, locked = false}},
         B1 = {{loc = TOB.Banks.B1.gate.loc, h = 1, txtloc = TOB.Banks.B1.gate.txtloc, locked = false}, {loc = TOB.Banks.B1.vault.loc, txtloc = TOB.Banks.B1.vault.txtloc, locked = false}}}
dofile("locales/tools.lua")
for _, f in ipairs({"client/minigames.lua", "client/sounds.lua", "client/util.lua", "client/heist.lua", "client/loot.lua", "client/boxes.lua", "client/police.lua", "client/tracker.lua", "client/doors.lua", "client/main.lua"}) do
    dofile(f)
end

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end end

-- 1. startup: banks from the server, ox_target zones
INITCB()
check("ready after loading the banks", Ready == true)
-- B1: start + 3 trolleys + 2 doors + 8 boxes; F1: the same + the gate panel
check("targets registered", #zones == (1 + 3 + 2 + 8) + (1 + 1 + 3 + 2 + 8))
local function zoneNamed(name)
    for _, z in ipairs(zones) do for _, o in ipairs(z.options) do if o.name == name then return o end end end
end
check("one loot option per trolley kind", zoneNamed("tob_loot_B1_2_cash") ~= nil and zoneNamed("tob_loot_B1_2_gold") ~= nil)
check("start option works", zoneNamed("tob_start_B1").canInteract() == true)
check("vault zone has the vault-item option", zoneNamed("tob_vaultitem_B1") ~= nil)

-- 2. the server says a bank is busy: nobody sees "start heist"
handlers["tobsbank:bankState"]("B1", true)
check("bank marked busy", TOB.Banks.B1.onaction == true and zoneNamed("tob_start_B1").canInteract() == false)
handlers["tobsbank:bankState"]("B1", false)

-- 3. loot phase: options follow the trolley kind, and the grab waits for the server
check("no looting before the vault opens", not zoneNamed("tob_loot_B1_2_cash").canInteract())
local data = {}
for k, v in pairs(TOB.Banks.B1) do data[k] = v end
data.special = {trolley2 = "gold"}
handlers["tobsbank:startLoot_c"](data, "B1")
check("loot phase active", LootActive.B1 == true and LootOpen.B1 == true)
check("gold trolley shows the gold option", zoneNamed("tob_loot_B1_2_gold").canInteract() == true and zoneNamed("tob_loot_B1_2_cash").canInteract() == false)
check("cash trolley shows the cash option", zoneNamed("tob_loot_B1_1_cash").canInteract() == true)
zoneNamed("tob_loot_B1_1_cash").onSelect()
check("loot asks the server first", lastServer("tobsbank:lootup")[3] == "Loot1")
local asked = #serverEvents
zoneNamed("tob_loot_B1_1_cash").onSelect()
check("no second request while waiting", #serverEvents == asked)
handlers["tobsbank:lootResult"]("B1", "Loot1", false, "trolley_taken")
check("refused loot is explained", notes[#notes] == L("trolley_taken"))
handlers["tobsbank:lootup_c"]("B1", "Loot2")
check("taken trolley hidden", LootCheck.B1.Loot2 == true and zoneNamed("tob_loot_B1_2_gold").canInteract() == false)
handlers["tobsbank:lootResult"]("B1", "Loot1", true)
check("missing trolley: grab ends at once", lastServer("tobsbank:grabDone") ~= nil)
handlers["tobsbank:bagFull"]()
check("full pockets explained", notes[#notes] == L("bag_full"))
handlers["tobsbank:closing"]("B1", 30)
check("closing stops the trolleys", LootOpen.B1 == false and zoneNamed("tob_loot_B1_1_cash").canInteract() == false)
handlers["tobsbank:cleanup"]("B1")
check("cleanup ends the loot phase", LootActive.B1 == false and BoxState.B1 == nil)

-- 4. minigames: ox_lib, none, your own function, a broken function
check("ox_lib skill check used", HackMinigame("B1") == true and lastExport("skillCheck").data == TOB.MinigameDifficulty)
SKILL = false
check("failed skill check", HackMinigame("B1") == false)
SKILL = true
TOB.HackMinigame = function(bank) return bank == "B1" end
check("custom minigame function", HackMinigame("B1") == true and HackMinigame("F1") == false)
TOB.HackMinigame = function() error("broken") end
check("broken minigame lets the heist go on", HackMinigame("B1") == true and printed[#printed]:find("Minigame error"))
TOB.HackMinigame = "none"
local before = #exportCalls
check("no minigame", HackMinigame("B1") == true and #exportCalls == before)
TOB.HackMinigame = "ox_lib"
TOB.DrillMinigame = function(bank, box) return box == 3 end
check("custom drill minigame", DrillMinigame("B1", 3) == true and DrillMinigame("B1", 1) == false)
TOB.DrillMinigame = {"easy"}

-- 5. starting a heist: dispatch and the hack
RUNNING["ps-dispatch"] = true
handlers["tobsbank:outcome"](true, "B1")
check("ps-dispatch Paleto alert", lastExport("PaletoBankRobbery") ~= nil and lastExport("PaletoBankRobbery").res == "ps-dispatch")
check("hack started after the minigame", lastServer("tobsbank:hackStarted")[2] == "B1")
check("leading the heist", Leading == "B1" and Check.B1 == true)
handlers["tobsbank:outcome"](true, "F1")
check("ps-dispatch Fleeca alert", lastExport("FleecaBankRobbery") ~= nil)
RUNNING["ps-dispatch"] = nil
local customCalled
TOB.DispatchAlert = function(coords, bank) customCalled = bank end
handlers["tobsbank:outcome"](true, "B1")
check("custom dispatch without ps-dispatch", customCalled == "B1")
SKILL = false
handlers["tobsbank:outcome"](true, "B1")
check("failed minigame tells the server", lastServer("tobsbank:hackFailed")[2] == "B1")
SKILL = true
handlers["tobsbank:outcome"](false, "nope")
check("refused start is explained", notes[#notes] == "nope")
handlers["tobsbank:heistFailed"]("B1", "vault_timeout")
check("failed heist clears the leader", rawget(_G, "Leading") == nil and notes[#notes] == L("vault_timeout"))

-- 6. vault item, gate and taking over
handlers["tobsbank:awaitVaultItem"]("B1")
check("vault item prompt", AwaitingVault.B1 == true and zoneNamed("tob_vaultitem_B1").canInteract() == true)
handlers["tobsbank:vaultItemResult"]("B1", false)
check("missing vault item explained", notes[#notes] == L("no_vault_item", TOB.VaultItemLabel))
handlers["tobsbank:vaultOpened"]("F1", nil, {})
check("gate hint after the Fleeca vault opens", AwaitingGate.F1 == true and zoneNamed("tob_gate_F1").canInteract() == true)
handlers["tobsbank:gateResult"]("F1", false)
check("missing gate item explained", notes[#notes] == L("no_gate_item", TOB.GateItemLabel))
AwaitingVault.B1 = nil
handlers["tobsbank:takeover"]("B1", {stage = "vaultitem", itemUsed = false})
check("taking over the vault item step", Leading == "B1" and AwaitingVault.B1 == true)
check("new leader is told", notes[#notes] == L("use_vault_item", TOB.VaultItemLabel) or notes[#notes - 1] == L("you_lead"))
handlers["tobsbank:forceReset"]("B1")
check("admin reset clears the heist", AwaitingVault.B1 == nil and rawget(_G, "Leading") == nil)

-- 7. police
POLICE = true
local blips = CALLS.AddBlipForCoord or 0
handlers["tobsbank:policenotify"]("B1")
check("police alert and blip", notes[#notes] == L("police_alert") and CALLS.AddBlipForCoord == blips + 1)
handlers["tobsbank:bankState"]("B1", false)
check("blip removed when the heist ends", (CALLS.RemoveBlip or 0) >= 1)
check("police can lock doors", zoneNamed("tob_lock_B1_1").canInteract() == true and zoneNamed("tob_start_B1").canInteract() == false)
POLICE = false

-- 8. prompts use ox_lib's text UI when it's running
check("prompt mode is the text UI", PromptMode() == "textui")
before = #exportCalls
check("far away: no prompt", Prompt(vector3(0, 0, 0), "Test", 3.0, 1.0) == false and #exportCalls == before)
PRESSED = true
check("close: prompt shown and E works", Prompt(vector3(0, 0, 0), "Test", 0.5, 1.0) == true and lastExport("showTextUI").data == "[E] Test")
PRESSED = false
before = #exportCalls
Prompt(vector3(0, 0, 0), "Test", 0.5, 1.0)
check("same text isn't sent again", #exportCalls == before)

-- 9. other events
handlers["tobsbank:drillResult"]("B1", 1, false, "already_drilling")
check("drilling refusal explained", notes[#notes] == L("already_drilling"))
handlers["tobsbank:boxState"]("B1", 2, "opened")
check("box state stored", BoxState.B1[2] == "opened")
handlers["tobsbank:heistTotal"]("12,000", "30,000")
check("heist total shown", notes[#notes] == L("heist_total", "12,000", "30,000"))
handlers["tobsbank:timer"]("B1", 90)
check("timer stored", TimerEnds.B1 ~= nil)
handlers["tobsbank:vaultState"]("B1", 123.0)
check("vault angle stored", Doors.B1[2].state == 123.0)
check("bankcoords command registered", commands[TOB.CoordsCommand] ~= nil)
-- 10. joining the server during a heist: take part from where it is
RUNNING_HEISTS = {B1 = {stage = "open", vaultOpen = true, special = {trolley3 = "diamond"}, looted = {Loot1 = true}, boxes = {[2] = "opened"}, timeLeft = 120},
                  F1 = {stage = "hacking", vaultOpen = false, looted = {}, boxes = {}}}
INITCB()
check("late joiner can loot", LootActive.B1 == true and LootOpen.B1 == true)
check("late joiner sees what's taken", LootCheck.B1.Loot1 == true and LootCheck.B1.Loot2 == false and BoxState.B1[2] == "opened")
check("late joiner sees the special trolley", LootSpecial.B1.trolley3 == "diamond")
check("late joiner sees the countdown", TimerEnds.B1 ~= nil)
check("no loot phase before the vault opens", not LootActive.F1)
-- 11. GPS tracker (police) and dye pack
POLICE = true
local blipsBefore = CALLS.AddBlipForCoord or 0
handlers["tobsbank:trackerPos"](12, vector3(10, 20, 30), 120)
check("tracker blip for police", CALLS.AddBlipForCoord == blipsBefore + 1 and notes[#notes] == L("tracker_police", 120))
handlers["tobsbank:trackerPos"](12, vector3(11, 20, 30), 115)
check("tracker blip moves, no second blip", CALLS.AddBlipForCoord == blipsBefore + 1 and (CALLS.SetBlipCoords or 0) >= 1)
local removed = CALLS.RemoveBlip or 0
handlers["tobsbank:trackerEnd"](12)
check("tracker blip removed", CALLS.RemoveBlip == removed + 1)
POLICE = false
handlers["tobsbank:trackerPos"](13, vector3(10, 20, 30), 120)
check("no tracker blip for robbers", CALLS.AddBlipForCoord == blipsBefore + 1)
handlers["tobsbank:trackerWarn"]()
check("robber warned", notes[#notes] == L("tracker_warn"))
handlers["tobsbank:dyePack"](7, 10)
check("dye pack: the robber is told", notes[#notes] == L("dye_pack"))
check("dye pack: red smoke", (CALLS.StartParticleFxLoopedOnEntity or 0) == 1)
handlers["tobsbank:dyePack"](99, 10)
check("dye pack on someone out of range: nothing", (CALLS.StartParticleFxLoopedOnEntity or 0) == 1)

-- 12. the gate uses GTA's door system
local gateThread = #threads + 1
DoorThreads()
local searchRadius
GetClosestObjectOfType = function(x, y, z, radius) searchRadius = searchRadius or radius; return 55 end
PEDPOS = TOB.Banks.F1.gate.loc
STOPWAIT = true; pcall(threads[gateThread]); STOPWAIT = false
check("gate registered in the door system", (CALLS.AddDoorToSystem or 0) == 1)
check("the gate is searched for within 4 m (a gate.loc a little off still finds it)", searchRadius == 4.0)
local applied = CALLS.DoorSystemSetDoorState or 0
check("gate lock applied", applied >= 1)
handlers["tobsbank:toggleDoor"]("F1", false)
check("gate unlock applied at once", CALLS.DoorSystemSetDoorState == applied + 1 and Doors.F1[1].locked == false)
STOPWAIT = true; pcall(threads[gateThread]); STOPWAIT = false
check("gate registered only once", CALLS.AddDoorToSystem == 1)
GetClosestObjectOfType = function() return 0 end

-- 13. per-bank minigames with tobs_minigames (client/minigames.lua, tested on its own in tests/minigames_test.lua)
local function lastStart() local e = lastExport("Start") return e and e.res == "tobs_minigames" and e or nil end
RUNNING.tobs_minigames = true; MGRESULT = true
local skills = #exportCalls
handlers["tobsbank:outcome"](true, "B1")
check("Paleto plays GTA's hacking laptop", lastStart() ~= nil and lastStart().data == "hack")
check("... without tobs_minigames' own animation (the heist plays the laptop scene)", lastStart().opts.animate == false)
local sc = false
for i = skills + 1, #exportCalls do if exportCalls[i].fn == "skillCheck" then sc = true end end
check("won laptop game starts the hack, no skill check on top", not sc and lastServer("tobsbank:hackStarted")[2] == "B1")
MGRESULT = false
handlers["tobsbank:outcome"](true, "B1")
check("lost laptop game fails the hack", lastServer("tobsbank:hackFailed")[2] == "B1")
MGRESULT = nil; SKILL = true
local calls = #exportCalls
handlers["tobsbank:outcome"](true, "B1")
local usedSkill = false
for i = calls + 1, #exportCalls do if exportCalls[i].fn == "skillCheck" then usedSkill = true end end
check("GTA screen doesn't load: the ox_lib skill check instead", usedSkill and lastServer("tobsbank:hackStarted")[2] == "B1")
RUNNING.tobs_minigames = nil
calls = #exportCalls
handlers["tobsbank:outcome"](true, "B1")
local startedMg = false
for i = calls + 1, #exportCalls do if exportCalls[i].res == "tobs_minigames" then startedMg = true end end
check("without tobs_minigames: the normal minigame", not startedMg and lastExport("skillCheck").data == TOB.MinigameDifficulty)
TOB.Banks.F1.minigames = {hack = {"hard"}}
handlers["tobsbank:outcome"](true, "F1")
check("a bank's own ox_lib difficulties", lastExport("skillCheck").data[1] == "hard")
TOB.Banks.F1.minigames = {hack = function() error("broken") end}
local okRun = pcall(handlers["tobsbank:outcome"], true, "F1")
check("a broken function on a bank doesn't stop the heist", okRun and lastServer("tobsbank:hackStarted")[2] == "F1" and printed[#printed]:find("Minigame error") ~= nil)
TOB.Banks.F1.minigames = nil
-- drilling a deposit box
RUNNING.tobs_minigames = true; MGRESULT = true
calls = #exportCalls
local drillNetworked
function PlaySoundFromEntity(_, name, _, _, isNetwork) if name == "Drill" then drillNetworked = isNetwork end end
handlers["tobsbank:drillResult"]("B1", 1, true)
check("the driller's drill sound isn't networked (the others get the server's bank sound)", drillNetworked == false)
local bar = false
for i = calls + 1, #exportCalls do
    if exportCalls[i].fn == "progressBar" then bar = true end
end
check("Paleto box: GTA's drill replaces the progress bar", lastStart().data == "drill" and not bar and lastServer("tobsbank:drillDone")[4] == true)
MGRESULT = false
handlers["tobsbank:drillResult"]("B1", 1, true)
check("lost drill game: box not opened", lastServer("tobsbank:drillDone")[4] == false and notes[#notes] == L("drill_failed"))
RUNNING.tobs_minigames = nil
calls = #exportCalls
handlers["tobsbank:drillResult"]("B1", 1, true)
local skill, progress = false, false
for i = calls + 1, #exportCalls do
    if exportCalls[i].fn == "skillCheck" then skill = true end
    if exportCalls[i].fn == "progressBar" then progress = true end
end
check("without tobs_minigames: skill check, then the progress bar", skill and progress and lastServer("tobsbank:drillDone")[4] == true)
-- sounds from the server
handlers["tobs_bankrobbery:bankSound"]("B1", "drill_on", 1, 3, 40.0)
check("far from the bank: no drill sound", (CALLS.PlaySoundFromCoord or 0) == 0)
PEDPOS = TOB.Banks.B1.boxes[1]
handlers["tobs_bankrobbery:bankSound"]("B1", "drill_on", 1, 3, 40.0)
check("near the bank: the drill is heard", CALLS.PlaySoundFromCoord == 1)
handlers["tobs_bankrobbery:bankSound"]("B1", "drill_on", 1, 7, 40.0)
check("the driller doesn't hear it twice", CALLS.PlaySoundFromCoord == 1)
PEDPOS = vector3(1000, 1000, 0)

for _, name in ipairs({"StartHeist", "StartGrab", "RequestLoot", "SpawnTrolleys", "DrillBox", "UseGate", "UseVaultItem", "ToggleDoor", "DoorThreads", "RegisterTargets", "CleanBankProps"}) do
    check(name .. " defined", rawget(_G, name) ~= nil)
end

io.write(("%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
