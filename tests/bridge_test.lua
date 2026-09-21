-- Automated tests for the framework bridges (bridge/<framework>/). Each framework is faked with just the
-- functions the bridge uses, then the real bridge files are loaded and checked.
-- Run from the repo root:  lua5.4 tests/bridge_test.lua

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end end

-- Game functions shared by every run
local running, handlers, sent, printed = {}, {}, {}, {}
function vector3(x, y, z) return {x = x, y = y, z = z} end
function GetResourceState(r) return running[r] and "started" or "missing" end
function GetPlayers() return {"1", "2", "3"} end
function RegisterServerEvent() end
function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, target, ...) sent[#sent + 1] = {name = name, target = target, args = {...}} end
function TriggerServerEvent() end
function TriggerEvent() end
print = function(s) printed[#printed + 1] = s end
-- Threads run as coroutines; Wait() pauses them so a "while true" loop runs one step at a time
Citizen = {
    CreateThread = function(fn) local co = coroutine.create(fn); coroutine.resume(co) end,
    Wait = function() coroutine.yield() end,
}

-- exports.resource:fn(...) calls FAKE[resource].fn(...)
FAKE = {}
exports = setmetatable({}, {__index = function(_, res)
    return setmetatable({}, {__index = function(_, fn)
        return function(_, ...) return FAKE[res][fn](...) end
    end})
end})

local BRIDGES = {"qbox", "esx", "qb", "vrp"}

-- Loads config + framework detection + the callback helper + every bridge for one side
local function load(side, resources, config)
    running, handlers, sent, printed = {}, {}, {}, {}
    for _, r in ipairs(resources) do running[r] = true end
    Bridge, Framework = nil, nil
    dofile("config/config.lua")
    for k, v in pairs(config or {}) do TOB[k] = v end
    dofile("bridge/framework.lua")
    dofile(side .. "/callbacks.lua")
    for _, name in ipairs(BRIDGES) do dofile("bridge/" .. name .. "/" .. side .. ".lua") end
end

-- A small inventory + wallet shared by the fakes: INV[src][item], CASH[src], ADDED[src][item]
local INV, CASH, ADDED
FITS = true -- false = the player's inventory is full
local function reset()
    INV = {[1] = {id_card_f = 2}, [2] = {}, [3] = {}}
    CASH, ADDED = {}, {}
    FITS = true
end
local function added(src, item, n) ADDED[src] = ADDED[src] or {}; ADDED[src][item] = (ADDED[src][item] or 0) + n end
local oxInventory = {
    GetItemCount = function(src, item) return INV[src][item] or 0 end,
    RemoveItem = function(src, item, n)
        if (INV[src][item] or 0) < n then return false, "not_enough_items" end
        INV[src][item] = INV[src][item] - n; return true
    end,
    CanCarryItem = function() return FITS end,
    AddItem = function(src, item, n)
        if not FITS then return false, "inventory_full" end
        added(src, item, n); return true
    end,
}

-- Checks every server bridge function. Player 1 = robber with 2 cards, 2 = police on duty, 3 = police off duty.
local function serverChecks(fw, dirtyItem, offDutyCounts, fullCheck)
    check(fw .. ": detected", Framework == fw and Bridge ~= nil)
    check(fw .. ": robber isn't police", Bridge.IsPolice(1) == false)
    check(fw .. ": police on duty", Bridge.IsPolice(2) == true)
    check(fw .. ": police count", Bridge.CountPolice() == (offDutyCounts and 2 or 1))
    check(fw .. ": has item", Bridge.HasItem(1, "id_card_f", 2) == true and Bridge.HasItem(1, "id_card_f", 3) == false)
    check(fw .. ": remove item", Bridge.RemoveItem(1, "id_card_f", 1) == true and INV[1].id_card_f == 1)
    check(fw .. ": add item", Bridge.AddItem(1, "goldbar", 3) == true and ADDED[1] and ADDED[1].goldbar == 3)
    check(fw .. ": can carry", Bridge.CanCarry(1, "goldbar", 1) == true)
    if fullCheck then
        FITS = false
        check(fw .. ": full inventory -> not added", Bridge.CanCarry(1, "goldbar", 1) == false and Bridge.AddItem(1, "goldbar", 1) == false and ADDED[1].goldbar == 3)
        FITS = true
    end
    Bridge.AddMoney(1, 500, false)
    check(fw .. ": add cash", CASH[1] == 500)
    Bridge.AddMoney(1, 700, true)
    if dirtyItem then
        check(fw .. ": dirty money item", ADDED[1][dirtyItem] == 700 and CASH[1] == 500)
    else
        check(fw .. ": dirty money account", CASH.black_money == 700)
    end
    check(fw .. ": callback registered", type(Bridge.RegisterCallback) == "function")
end

---------------------------------------------------------------- Qbox
local function qbxJob(src)
    if src == 1 then return {name = "unemployed", onduty = true} end
    return {name = "police", onduty = src == 2}
end
reset()
FAKE.qbx_core = {
    GetPlayer = function(src) return {PlayerData = {job = qbxJob(src)}} end,
    AddMoney = function(src, kind, amount) if kind == "cash" then CASH[src] = (CASH[src] or 0) + amount end end,
}
FAKE.ox_inventory = oxInventory
load("server", {"qbx_core", "qb-core", "ox_inventory"}) -- qbx_core also provides qb-core
serverChecks("qbox", "black_money", false, true)
TOB.PoliceOnDuty = false
check("qbox: off-duty police counted when PoliceOnDuty is off", Bridge.CountPolice() == 2)

-- several police jobs
load("server", {"qbx_core", "ox_inventory"}, {PoliceJob = {"sheriff", "police"}})
check("qbox: police job list", Bridge.IsPolice(2) == true and Bridge.IsPolice(1) == false)

---------------------------------------------------------------- ESX
reset()
local function xPlayer(src)
    return {
        job = {name = (src == 1) and "unemployed" or "police"},
        getInventoryItem = function(item) return {count = INV[src][item] or 0} end,
        canCarryItem = function() return FITS end,
        removeInventoryItem = function(item, n) INV[src][item] = INV[src][item] - n end,
        addInventoryItem = function(item, n) added(src, item, n) end,
        addMoney = function(n) CASH[src] = (CASH[src] or 0) + n end,
        addAccountMoney = function(account, n) CASH[account] = (CASH[account] or 0) + n end,
    }
end
FAKE.es_extended = {getSharedObject = function()
    return {GetPlayerFromId = xPlayer, GetPlayers = function() return {1, 2, 3} end}
end}
load("server", {"es_extended"})
serverChecks("esx", nil, true, true) -- ESX has no duty: both police players count

---------------------------------------------------------------- QBCore with qb-inventory
reset()
local function qbPlayer(src)
    return {PlayerData = {job = qbxJob(src)}, Functions = {
        AddMoney = function(kind, amount) if kind == "cash" then CASH[src] = (CASH[src] or 0) + amount end end,
    }}
end
FAKE["qb-core"] = {GetCoreObject = function() return {Functions = {GetPlayer = qbPlayer}} end}
FAKE["qb-inventory"] = {
    GetItemCount = function(src, item) return INV[src][item] or 0 end,
    RemoveItem = function(src, item, n) INV[src][item] = INV[src][item] - n; return true end,
    CanAddItem = function() return FITS end,
    AddItem = function(src, item, n)
        if not FITS then return false end
        added(src, item, n); return true
    end,
}
load("server", {"qb-core", "qb-inventory"})
serverChecks("qb", "black_money", false, true)

-- older qb-core without qb-inventory exports: items on the player
reset()
FAKE["qb-inventory"] = setmetatable({}, {__index = function() error("No such export") end})
FAKE["qb-core"] = {GetCoreObject = function() return {Functions = {GetPlayer = function(src)
    local p = qbPlayer(src)
    p.Functions.GetItemByName = function(item) return {amount = INV[src][item] or 0} end
    p.Functions.RemoveItem = function(item, n) INV[src][item] = INV[src][item] - n; return true end
    p.Functions.AddItem = function(item, n) added(src, item, n); return true end
    return p
end}} end}
load("server", {"qb-core"})
check("old qb-core: has item", Bridge.HasItem(1, "id_card_f", 2) == true)
check("old qb-core: remove item", Bridge.RemoveItem(1, "id_card_f", 1) == true and INV[1].id_card_f == 1)
check("old qb-core: add item (nil args kept)", Bridge.AddItem(1, "goldbar", 2) == true and ADDED[1].goldbar == 2)
FAKE["qb-core"] = {GetCoreObject = function() return {Functions = {GetPlayer = qbPlayer}} end}

-- QBCore with ox_inventory: items must go through ox_inventory, not qb-inventory
reset()
FAKE["qb-inventory"] = setmetatable({}, {__index = function() error("qb-inventory used") end})
load("server", {"qb-core", "ox_inventory"})
check("qb + ox_inventory: has item", Bridge.HasItem(1, "id_card_f", 2) == true)
Bridge.RemoveItem(1, "id_card_f", 1)
Bridge.AddItem(1, "goldbar", 1)
check("qb + ox_inventory: items through ox_inventory", INV[1].id_card_f == 1 and ADDED[1].goldbar == 1)

---------------------------------------------------------------- vRP
reset()
local vRP = {
    getUserId = function(a) return a[1] end,
    hasGroup = function(a) return a[1] ~= 1 and a[2] == "Politi-Job" end,
    getUsers = function() return {[1] = 1, [2] = 2, [3] = 3} end,
    getInventoryItemAmount = function(a) return INV[a[1]][a[2]] or 0 end,
    tryGetInventoryItem = function(a) INV[a[1]][a[2]] = INV[a[1]][a[2]] - a[3] end,
    giveInventoryItem = function(a) added(a[1], a[2], a[3]) end,
    giveMoney = function(a) CASH[a[1]] = (CASH[a[1]] or 0) + a[2] end,
}
-- vrp/lib/utils.lua is read with LoadResourceFile and defines module()
VRP_PROXY = {getInterface = function() return vRP end}
function LoadResourceFile(res, file)
    if res == "vrp" and file == "lib/utils.lua" then return "function module(rsc, path) return VRP_PROXY end" end
end
load("server", {"vrp"})
serverChecks("vrp", "dirty_money", true) -- vRP groups have no duty
TriggerClientEvent = function(name, target) sent[#sent + 1] = {name = name, target = target} end
source = 2; handlers["TOB_fh:CheckCop"]()
check("vrp: police told they're police", sent[#sent].name == "TOB_fh:IsCop" and sent[#sent].target == 2)

-- vRP missing its utils file: clear error instead of a crash
LoadResourceFile = function() return nil end
load("server", {"vrp"})
check("vrp: missing utils.lua is reported", Bridge == nil and printed[#printed]:find("vrp/lib/utils.lua", 1, true) ~= nil)

---------------------------------------------------------------- detection
load("server", {})
check("no framework: nothing loaded and a warning", Bridge == nil and printed[1]:find("No framework found", 1, true) ~= nil)
load("server", {"es_extended", "vrp"}, {Framework = "vrp"})
check("TOB.Framework overrides detection", Framework == "vrp")

---------------------------------------------------------------- clients
-- Qbox client: job from qbx_core, then updated by the QBCore job and duty events
local qbxData = {}
FAKE.qbx_core = {GetPlayerData = function() return qbxData end, Notify = function(msg) NOTIFIED = msg end}
load("client", {"qbx_core", "ox_inventory"})
local ready = false
Bridge.Init(function() ready = true end)
check("qbox client: waits for the player to load", ready == false)
qbxData = {job = {name = "police", onduty = true}}
handlers["QBCore:Client:OnPlayerLoaded"]()
check("qbox client: police on duty", Bridge.IsPolice() == true)
handlers["QBCore:Client:SetDuty"](false)
check("qbox client: off duty isn't police", Bridge.IsPolice() == false)
handlers["QBCore:Client:OnJobUpdate"]({name = "police", onduty = true})
check("qbox client: job update", Bridge.IsPolice() == true)
Bridge.Notify("hi")
check("qbox client: notify", NOTIFIED == "hi" and Bridge.NotifyFallback == "framework")

-- QBCore client
local qbData = {job = {name = "unemployed", onduty = true}}
FAKE["qb-core"] = {GetCoreObject = function()
    return {Functions = {GetPlayerData = function() return qbData end, Notify = function(msg) NOTIFIED = msg end}}
end}
load("client", {"qb-core"})
ready = false
Bridge.Init(function() ready = true end)
check("qb client: init runs when loaded", ready == true and Bridge.IsPolice() == false)
handlers["QBCore:Client:OnJobUpdate"]({name = "police", onduty = true})
check("qb client: job update", Bridge.IsPolice() == true)

-- ESX client
local esxData = {job = {name = "police"}}
FAKE.es_extended = {getSharedObject = function()
    return {GetPlayerData = function() return esxData end, ShowNotification = function(msg) NOTIFIED = msg end}
end}
load("client", {"es_extended"})
Bridge.Init(function() end)
check("esx client: police", Bridge.IsPolice() == true)
handlers["esx:setJob"]({name = "mechanic"})
check("esx client: job update", Bridge.IsPolice() == false)

-- vRP client: asks the server
load("client", {"vrp"})
handlers["TOB_fh:IsCop"]()
check("vrp client: police from the server", Bridge.IsPolice() == true)

-- every client bridge has the functions client/main.lua uses
for _, fw in ipairs({{"qbox", "qbx_core"}, {"esx", "es_extended"}, {"qb", "qb-core"}, {"vrp", "vrp"}}) do
    load("client", {fw[2]})
    check(fw[1] .. " client: full API", type(Bridge.Init) == "function" and type(Bridge.IsPolice) == "function"
        and type(Bridge.TriggerCallback) == "function" and type(Bridge.Notify) == "function" and Bridge.NotifyFallback ~= nil)
end

io.write(("%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
