-- Automated tests for tobs_bankrobbery. They run the real script files outside FiveM, with small fake
-- versions of the game and framework functions. Run from the repo root:  lua5.4 tests/client_test.lua
-- GitHub runs them on every push (.github/workflows/tests.yml).

local ROOT = ""
local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, V) end
V.__add = function(a, b) return setmetatable({x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end

local handlers, serverEvents, zones, notes, commands = {}, {}, {}, {}, {}
function RegisterCommand(n, fn) commands[n] = fn end
local threads = {}
Citizen = {CreateThread = function(fn) threads[#threads + 1] = fn end, Wait = function() end}
function RegisterNetEvent() end
function AddEventHandler(n, fn) handlers[n] = fn end
function TriggerEvent(n, ...) if handlers[n] then handlers[n](...) end end
function TriggerServerEvent(n, ...) serverEvents[#serverEvents + 1] = {n, ...} end
function GetResourceState(r) return (r == "ox_target" or r == "ox_lib") and "started" or "missing" end
function PlayerPedId() return 1 end
function GetEntityCoords() return vector3(1000, 1000, 0) end
function GetClosestObjectOfType() return 0 end
function GetHashKey(s) return #s end
function DoesEntityExist() return false end
function AddBlipForCoord() return 5 end
for _, n in ipairs({"SetBlipSprite","SetBlipScale","SetBlipColour","PulseBlip","RemoveBlip","DeleteEntity","NetworkRequestControlOfEntity","SetEntityAsMissionEntity","FreezeEntityPosition","SetEntityHeading","print"}) do _G[n] = function() end end
exports = setmetatable({}, {__index = function(_, res)
    return setmetatable({}, {__index = function(_, fn)
        return function(_, data)
            if fn == "addSphereZone" then zones[#zones + 1] = data end
            return true
        end
    end})
end})
TriggerEvent = function(n, ...)
    if n == "ox_lib:notify" then notes[#notes + 1] = select(1, ...).description return end
    if handlers[n] then handlers[n](...) end
end

dofile(ROOT .. "config/config.lua"); dofile(ROOT .. "locales/locales.lua")
-- Fake framework bridge (the real ones are tested in tests/bridge_test.lua)
Bridge = {NotifyFallback = "native",
          Init = function(cb) INITCB = cb end,
          IsPolice = function() return false end,
          TriggerCallback = function(n, cb) cb({B1 = TOB.Banks.B1, F1 = TOB.Banks.F1}, DOORS) end,
          Notify = function(m) notes[#notes + 1] = m end}
DOORS = {F1 = {{loc = TOB.Banks.F1.gate.loc, h = 1, txtloc = TOB.Banks.F1.gate.txtloc, locked = true}, {loc = TOB.Banks.F1.vault.loc, txtloc = TOB.Banks.F1.vault.txtloc, locked = true}}, B1 = {{loc = TOB.Banks.B1.gate.loc, h = 1, txtloc = TOB.Banks.B1.gate.txtloc, locked = false},
               {loc = TOB.Banks.B1.vault.loc, txtloc = TOB.Banks.B1.vault.txtloc, locked = false}}}
dofile(ROOT .. "client/main.lua")

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; print_ = nil; io.write("FAIL: " .. label .. "\n") end end

-- run the Bridge.Init thread (loads banks, registers targets)
INITCB()
check("targets registered (B1 + F1 with gate panel and 8 deposit boxes each)", #zones == (1 + 3 + 2) + (1 + 1 + 3 + 2) + 16)
check("vault zone has vault-item option", #zones[#zones].options == 3)
handlers["TOB_fh:gateResult"]("F1", false)
check("missing gate item notified", notes[#notes] == L("no_gate_item", TOB.GateItemLabel))
handlers["TOB_fh:outcome"](false, "nope")
check("failure notified", notes[#notes] == "nope")
handlers["TOB_fh:toggleVault"]("B1", false)
check("far toggleVault just stores state", Doors.B1[2].locked == false)
handlers["TOB_fh:vaultState"]("B1", 123.0)
check("vault angle stored", Doors.B1[2].state == 123.0)
handlers["TOB_fh:startLoot_c"](TOB.Banks.B1, "B1")
check("loot active", LootActive.B1 == true)
handlers["TOB_fh:lootup_c"]("B1", "Loot2")
check("loot marked", LootCheck.B1.Loot2 == true)
handlers["TOB_fh:stopHeist_c"]("B1")
threads[#threads]() -- loot thread: far away + Stop -> exits
check("far loot thread exits on stop", LootActive.B1 == false)
handlers["TOB_fh:forceReset"]("B1")
check("force reset clears state", Check.B1 == false and AwaitingVault.B1 == nil)
handlers["TOB_fh:policenotify"]("B1")
check("non-police gets no alert", notes[#notes] == "nope")
handlers["TOB_fh:vaultItemResult"]("B1", false)
check("missing vault item notified", notes[#notes] == L("no_vault_item", TOB.VaultItemLabel))
check("target canInteract works", zones[1].options[1].canInteract() == true)
handlers["TOB_fh:drillResult"]("B1", 1, false, "no_drill")
check("missing drill notified", notes[#notes] == L("no_drill", TOB.DrillItemLabel))
handlers["TOB_fh:boxState"]("B1", 2, "opened")
check("box state stored", BoxState.B1[2] == "opened")
handlers["TOB_fh:boxesReset"]("B1")
check("boxes reset", BoxState.B1 == nil)
handlers["TOB_fh:heistTotal"]("12,000", "30,000")
check("heist total shown", notes[#notes] == L("heist_total", "12,000", "30,000"))
check("bankcoords command registered", commands[TOB.CoordsCommand] ~= nil)
io.write(("%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
