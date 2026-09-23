-- Automated tests for tobs_bankrobbery's server. They run the real server files outside FiveM, with small fake
-- versions of the game functions and a fake framework bridge. Run from the repo root:  lua5.4 tests/server_test.lua
-- GitHub runs them on every push (.github/workflows/tests.yml).

local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end

-- FAKE GAME --
local handlers, sent, http, commands, events, kvp, exported = {}, {}, {}, {}, {}, {}, {}
local now = 100000
local convars = {}
function RegisterServerEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, target, ...) sent[#sent + 1] = {name = name, target = target, args = {...}} end
function TriggerEvent(name, ...) events[#events + 1] = {name = name, args = {...}} end
function GetPlayerPed(src) return PEDS and PEDS[src] or 0 end
function GetEntityCoords(ped) return POS[ped] end
function GetPlayers() return {"1", "2", "3"} end
function GetPlayerName(src) return "Player" .. src end
function GetPlayerIdentifiers(src) return {"license:abc" .. src, "discord:99" .. src} end
function GetGameTimer() return now end
function GetConvar(name, default) return convars[name] or default end
function GetCurrentResourceName() return "tobs_bankrobbery" end
function GetInvokingResource() return "test" end
function GetResourceMetadata() return "2.1.0" end
function SetResourceKvpInt(k, v) kvp[k] = v end
function GetResourceKvpInt(k) return kvp[k] end
function PerformHttpRequest(url, cb, method, body) http[#http + 1] = {url = url, cb = cb, method = method, body = body} end
function RegisterCommand(name, fn) commands[name] = fn end
-- server-side objects (trolleys spawned by the server)
local objects, deleted = {}, {}
function CreateObject(model, x, y, z) objects[#objects + 1] = {model = model, x = x}; return 900 + #objects end
function SetEntityHeading() end
function DoesEntityExist(obj) return deleted[obj] == nil end
function DeleteEntity(obj) deleted[obj] = true end
function GetHashKey(s) return #s end
exports = setmetatable({}, {__call = function(_, name, fn) exported[name] = fn end})
json = {encode = function() return "{}" end, decode = function(s) return {tag_name = s, html_url = "https://x"} end}
local threads = {}
Citizen = {CreateThread = function(fn) threads[#threads + 1] = fn end, Wait = function() end}
local printed = {}
local realprint = print
print = function(s) printed[#printed + 1] = s end

-- FAKE FRAMEWORK BRIDGE --
INV = {}; MONEY = {}; ITEMS = {}; POLICE = {}; COPS = 4; CANCARRY = true; REMOVE_OK = true
Bridge = {}
function Bridge.IsPolice(src) return POLICE[src] == true end
function Bridge.CountPolice() return COPS end
function Bridge.HasItem(src, item, n) return ((INV[src] or {})[item] or 0) >= n end
function Bridge.RemoveItem(src, item, n)
    if not REMOVE_OK then return false end
    INV[src][item] = INV[src][item] - n
    return true
end
function Bridge.CanCarry() return CANCARRY end
function Bridge.AddItem(src, item, n, metadata)
    if not CANCARRY then return false end
    if metadata then METADATA[#METADATA + 1] = {src = src, item = item, n = n, metadata = metadata} end
    ITEMS[src] = ITEMS[src] or {}
    ITEMS[src][item] = (ITEMS[src][item] or 0) + n
    return true
end
DIRTY = {}; METADATA = {}
-- account: "cash" (the default) or "black" (dirty money)
function Bridge.AddMoney(src, amount, account)
    MONEY[src] = (MONEY[src] or 0) + amount
    if account == "black" then DIRTY[src] = (DIRTY[src] or 0) + amount end
end
local callbacks = {}
function Bridge.RegisterCallback(name, fn) callbacks[name] = fn end

-- LOAD THE SCRIPT --
dofile("config/config.lua"); dofile("config/banks.lua"); dofile("locales/locales.lua"); dofile("config/config_server.lua")
TOB.Banks.F6.enabled = false
TOB.Banks.BROKEN = {label = "Broken bank", doors = {}}   -- missing settings: must be skipped, not crash
TOB.TrolleyCash = {min = 60000, max = 60000}              -- fixed so payouts can be checked exactly
for _, b in pairs(TOB.Banks) do b.cash = nil end        -- every bank pays TOB.TrolleyCash; test 27 sets one
TOB.SpecialTrolleyChance = 0  -- random gold/diamond trolleys would make payout checks flaky; test 19 turns them on
SV.Webhook = "https://discord.test/hook"
local dispatched = nil
SV.DispatchAlert = function(bank, coords, src) dispatched = {bank = bank, src = src} end
kvp["lastrobbed:F2"] = os.time() -- a cooldown saved before a restart
-- admin tools (tested on their own in tests/tools_test.lua): run their startup thread for the commands
dofile("locales/tools.lua"); dofile("server/tools.lua"); threads[#threads]()
for _, f in ipairs({"server/util.lua", "server/heist.lua", "server/loot.lua", "server/tracker.lua", "server/boxes.lua", "server/doors.lua", "server/admin.lua", "server/api.lua"}) do
    dofile(f)
end

-- HELPERS --
local function fire(src, name, ...) source = src; handlers[name](...) end
local function last(name) for i = #sent, 1, -1 do if sent[i].name == name then return sent[i] end end end
local function count(name) local n = 0 for _, e in ipairs(sent) do if e.name == name then n = n + 1 end end return n end
local function lastEvent(name) for i = #events, 1, -1 do if events[i].name == name then return events[i] end end end
local function clear() sent = {}; http = {}; events = {} end
local function tick(ms) now = now + ms; HeistTick() end
local function printedHas(text) for _, line in ipairs(printed) do if line:find(text, 1, true) then return true end end return false end
-- puts a player at a position (OneSync on)
local function at(src, pos)
    PEDS = PEDS or {}; POS = POS or {}
    PEDS[src] = src * 11
    POS[src * 11] = vector3(pos.x, pos.y, pos.z)
end
local function start(bank) return TOB.Banks[bank].doors.startloc end
local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; realprint("FAIL: " .. label) end end
-- Starts a heist at bank with player src (card, position, past the rate limit)
local function begin(bank, src)
    at(src, start(bank)); INV[src] = INV[src] or {}; INV[src].id_card_f = 1
    now = now + 3000
    fire(src, "tobsbank:startcheck", bank)
end
-- Starts a heist and runs it until the vault is open
local function openHeist(bank, src)
    begin(bank, src)
    fire(src, "tobsbank:hackStarted", bank)
    tick(TOB.hacktime)
end

-- 0. startup
check("OneSync off: no second warning while the health check runs on start", not printedHas("OneSync is off"))
SV.HealthCheck = false; dofile("server/util.lua"); SV.HealthCheck = true
check("OneSync warning printed when the health check is off", printedHas("OneSync is off"))
check("broken bank skipped with a warning", TOB.Banks.BROKEN == nil and printedHas("Bank BROKEN is missing"))
check("disabled bank removed", TOB.Banks.F6 == nil)
check("saved cooldown loaded after a restart", TOB.Banks.F2.lastrobbed == kvp["lastrobbed:F2"])
check("fleeca gate locked by default", Doors.F1[1].locked == true and Doors.B1[1].locked == false)

-- 1. no cops
COPS = 0; INV[1] = {id_card_f = 1}
fire(1, "tobsbank:startcheck", "B1")
check("no cops message", last("tobsbank:outcome").args[2] == PoliceRefusal(TOB.mincops, 0))
-- 2. start
COPS = 4; clear(); now = now + 3000
fire(1, "tobsbank:startcheck", "B1")
check("heist started", last("tobsbank:outcome").args[1] == true and Heists.B1 ~= nil and Heists.B1.stage == "card")
check("card used", INV[1].id_card_f == 0)
check("police alerted", last("tobsbank:policenotify") ~= nil)
check("everyone told the bank is busy", last("tobsbank:bankState").args[2] == true and last("tobsbank:bankState").target == -1)
check("start logged to discord", #http == 1)
check("heistStarted event for other resources", lastEvent("tobs_bankrobbery:heistStarted").args[1] == "B1")
check("server dispatch hook called", dispatched and dispatched.bank == "B1" and dispatched.src == 1)
check("export IsHeistActive", exported.IsHeistActive("B1") == true and exported.IsHeistActive() == true and exported.IsHeistActive("F1") == false)
-- 3. busy + rate limit
INV[2] = {id_card_f = 1}; clear()
fire(2, "tobsbank:startcheck", "B1")
check("busy message", last("tobsbank:outcome").args[2] == RefusalText("busy"))
clear(); fire(2, "tobsbank:startcheck", "B1")
check("start spam is rate limited", last("tobsbank:outcome") == nil)

-- 4. EXPLOIT: the robber can't open the vault or skip the hack
clear(); fire(1, "tobsbank:toggleVault", "B1", false)
check("robber can't open the vault", last("tobsbank:toggleVault") == nil and #http == 1)
clear(); tick(TOB.hacktime + 5000)
check("vault stays shut while the minigame isn't done", last("tobsbank:toggleVault") == nil and Heists.B1.stage == "card")
-- 5. EXPLOIT: no looting before the vault is open
clear(); fire(2, "tobsbank:lootup", "B1", "Loot1")
check("no looting before the vault opens", last("tobsbank:lootResult").args[3] == false and last("tobsbank:lootup_c") == nil)
clear(); fire(3, "tobsbank:rewardCash")
check("cash without looting is blocked and flagged", MONEY[3] == nil and #http == 1)
fire(3, "tobsbank:rewardCash")
check("flags are rate limited", #http == 1)
-- 6. EXPLOIT: no deposit boxes before the vault is open
INV[2].drill = 1; clear()
fire(2, "tobsbank:drillBox", "B1", 1)
check("no drilling before the vault opens", last("tobsbank:drillResult") == nil)
-- 7. the hack runs on the server
fire(2, "tobsbank:hackStarted", "B1")
check("only the robber can start the hack", Heists.B1.stage == "card")
fire(1, "tobsbank:hackStarted", "B1")
check("hack started", Heists.B1.stage == "hacking")
clear(); tick(TOB.hacktime - 2000)
check("vault still shut before the hack time is over", last("tobsbank:toggleVault") == nil)
tick(2000)
check("server opens the vault when the hack is done", last("tobsbank:toggleVault").args[2] == false and Heists.B1.stage == "open")
check("robber told to spawn the trolleys", last("tobsbank:vaultOpened").target == 1)
check("loot phase sent to everyone", last("tobsbank:startLoot_c").target == -1)
check("hack done told to the robber", last("tobsbank:hackDone").target == 1)
check("security timer sent", last("tobsbank:timer").args[2] == TOB.timer)
check("vaultOpened event for other resources", lastEvent("tobs_bankrobbery:vaultOpened") ~= nil)

-- 8. looting and paying by grab time
local T1 = TOB.Banks.B1.trolley1
at(2, T1); clear()
fire(2, "tobsbank:lootup", "B1", "Loot1")
check("loot confirmed to the player", last("tobsbank:lootResult").args[3] == true)
check("loot broadcast", last("tobsbank:lootup_c") ~= nil)
at(3, T1); clear()
fire(3, "tobsbank:lootup", "B1", "Loot1")
check("trolley can't be taken twice", last("tobsbank:lootResult").args[3] == false and last("tobsbank:lootResult").args[4] == "trolley_taken")
now = now + 18500
fire(2, "tobsbank:rewardCash")
check("half the grab time pays half the trolley", MONEY[2] == 30000)
now = now + 100; fire(2, "tobsbank:rewardCash")
check("asking again straight away pays nothing more", MONEY[2] == 30000)
now = now + 30000; fire(2, "tobsbank:rewardCash")
check("a full trolley pays exactly its value", MONEY[2] == 60000)
now = now + 10000; fire(2, "tobsbank:rewardCash")
check("never more than the trolley holds", MONEY[2] == 60000)
fire(2, "tobsbank:grabDone")
check("grab finished", Looting[2] == nil)
-- a player joining now gets the running heist
local joined; callbacks["tobsbank:getBanks"](3, function(b, d, running) joined = running end)
check("late joiner gets the running heist", joined.B1 and joined.B1.stage == "open" and joined.B1.vaultOpen == true)
check("late joiner sees the taken trolley and the time left", joined.B1.looted.Loot1 == true and joined.B1.timeLeft > 0 and joined.F1 == nil)
-- 9. EXPLOIT: fast pile requests can't pay faster than grabbing
local T2 = TOB.Banks.B1.trolley2
at(2, T2)
fire(2, "tobsbank:lootup", "B1", "Loot2")
local before = MONEY[2]
for _ = 1, 50 do now = now + 250; fire(2, "tobsbank:rewardCash") end -- 12.5 s of spam
check("spamming pays only for the time spent", MONEY[2] - before <= math.floor(60000 * 12.5 / 37) and MONEY[2] - before > 0)
-- away from the trolley
at(2, vector3(0, 0, 1)); local m = MONEY[2]; clear()
now = now + 1000; fire(2, "tobsbank:rewardCash")
check("no cash away from the trolley (flagged)", MONEY[2] == m and #http == 1)
at(2, T2); now = now + 30000
fire(2, "tobsbank:grabDone")
check("finishing pays the rest", MONEY[2] - before == 60000)
at(2, vector3(0, 0, 1)); clear()
fire(2, "tobsbank:lootup", "B1", "Loot3")
check("far trolley flagged", last("tobsbank:lootResult").args[3] == false and #http == 1)

-- 10. all trolleys looted -> vault closes -> cleanup -> cooldown saved
local T3 = TOB.Banks.B1.trolley3
at(2, T3); fire(2, "tobsbank:lootup", "B1", "Loot3")
tick(1000)
check("vault doesn't close while someone is still grabbing", Heists.B1.stage == "open")
now = now + 40000; fire(2, "tobsbank:grabDone"); clear()
tick(1000)
check("all looted -> vault closing", Heists.B1.stage == "closing" and last("tobsbank:closing").args[2] == TOB.VaultCloseDelay)
tick(TOB.VaultCloseDelay * 1000)
check("vault closes after the delay", last("tobsbank:toggleVault").args[2] == true and Heists.B1.stage == "cleanup")
clear(); tick(10000)
check("props cleaned up and heist ended", last("tobsbank:cleanup") ~= nil and Heists.B1 == nil)
check("everyone told the bank is free", last("tobsbank:bankState").args[2] == false)
check("heist totals sent", last("tobsbank:heistTotal") ~= nil and last("tobsbank:heistTotal").args[2] == "180,000")
check("cooldown saved (survives restarts)", kvp["lastrobbed:B1"] == TOB.Banks.B1.lastrobbed and TOB.Banks.B1.lastrobbed > 0)
check("heistEnded event for other resources", lastEvent("tobs_bankrobbery:heistEnded").args[3] == 180000)
local endlog = printed[#printed]
check("end log has the reason and the payout", endlog:find("all trolleys were looted") and endlog:find("Player2: $180,000"))
-- 11. cooldown, admin reset
INV[1].id_card_f = 1; at(1, start("B1")); now = now + 3000; clear()
fire(1, "tobsbank:startcheck", "B1")
check("cooldown message", last("tobsbank:outcome").args[2]:find(LX("refuse_cooldown", ""):sub(1, 20), 1, true))
commands[SV.ResetCommand](0, {})
check("reset clears the cooldown", TOB.Banks.B1.lastrobbed == 0 and kvp["lastrobbed:B1"] == 0)
check("reset tells clients", last("tobsbank:forceReset") ~= nil)
check("export GetBanks", exported.GetBanks()[1].bank == "B1" and exported.GetBanks()[1].cooldownLeft == 0)

-- 12. hack failed / taking too long
clear(); begin("B1", 1)
fire(1, "tobsbank:hackFailed", "B1")
check("failed hack ends the heist", Heists.B1 == nil and last("tobsbank:heistFailed").args[2] == "hack_failed")
commands[SV.ResetCommand](0, {"B1"})
begin("B1", 1); clear()
tick(TOB.CardTime * 1000 + 1000)
check("minigame never finished -> heist ends", Heists.B1 == nil and last("tobsbank:heistFailed") ~= nil)
commands[SV.ResetCommand](0, {"B1"})

-- 13. the robber leaves the bank
begin("B1", 1); fire(1, "tobsbank:hackStarted", "B1")
at(1, vector3(0, 0, 1)); clear(); tick(1000)
check("leaving during the hack fails the heist", Heists.B1 == nil and last("tobsbank:heistFailed").args[2] == "robber_left")
commands[SV.ResetCommand](0, {"B1"})
openHeist("B1", 1)
at(1, vector3(0, 0, 1)); clear(); tick(1000)
check("leaving during looting closes the vault", Heists.B1.stage == "closing")
check("leaving during looting tells the leader (out of range of the closing message)",
    last("tobsbank:leaderLeft") ~= nil and last("tobsbank:leaderLeft").target == 1)
commands[SV.ResetCommand](0, {"B1"})

-- 14. the robber disconnects: the nearest crew member takes over
openHeist("B1", 1)
at(2, start("B1")); at(3, vector3(0, 0, 1)); clear()
fire(1, "playerDropped")
check("crew member takes over", Heists.B1.owner == 2 and last("tobsbank:takeover").target == 2)
check("takeover has the heist state", last("tobsbank:takeover").args[2].stage == "open")
check("export GetHeist shows the new leader", exported.GetHeist("B1").leader == 2)
at(1, vector3(0, 0, 1)); at(2, vector3(0, 0, 1)); clear() -- player 1 already left
fire(2, "playerDropped")
check("nobody left to take over -> vault closes", Heists.B1.stage == "closing" and Heists.B1.owner == nil)
commands[SV.ResetCommand](0, {"B1"})
begin("B1", 1); clear()
fire(1, "playerDropped")
check("drop before the hack ends the heist", Heists.B1 == nil)
commands[SV.ResetCommand](0, {"B1"})

-- 15. vault item: the vault opens TOB.VaultItemTime after the item is used, and not before
TOB.VaultItem = "thermite"
openHeist("B1", 1)
check("vault item step instead of opening", Heists.B1.stage == "vaultitem" and last("tobsbank:awaitVaultItem").target == 1)
local VL = TOB.Banks.B1.vault.loc
at(1, VL); clear()
fire(1, "tobsbank:useVaultItem", "B1")
check("no item -> false", last("tobsbank:vaultItemResult").args[2] == false)
INV[1].thermite = 1
fire(1, "tobsbank:useVaultItem", "B1")
check("item used", last("tobsbank:vaultItemResult").args[2] == true and INV[1].thermite == 0)
clear(); tick(TOB.VaultItemTime - 2000)
check("vault doesn't open before the thermite burned through", last("tobsbank:toggleVault") == nil)
tick(2000)
check("vault opens after the thermite", Heists.B1.stage == "open")
commands[SV.ResetCommand](0, {"B1"})
openHeist("B1", 1); clear()
tick(TOB.timer * 1000)
check("vault item never used -> heist fails", Heists.B1 == nil and last("tobsbank:heistFailed").args[2] == "vault_timeout")
commands[SV.ResetCommand](0, {"B1"})
TOB.VaultItem = ""

-- 16. Fleeca inner gate: the last trolley needs the gate hacked
openHeist("F1", 1)
local F1T3 = TOB.Banks.F1.trolley3
at(2, F1T3); clear()
fire(2, "tobsbank:lootup", "F1", "Loot3")
check("gate trolley can't be looted before the gate is hacked", last("tobsbank:lootResult").args[3] == false and #http == 1)
local sec = TOB.Banks.F1.doors.secondloc
at(1, sec); TOB.GateItem = "secure_card"; clear()
fire(1, "tobsbank:useGate", "F1")
check("gate needs the item", last("tobsbank:gateResult").args[2] == false)
INV[1].secure_card = 1
fire(1, "tobsbank:useGate", "F1")
check("gate hack started", last("tobsbank:gateResult").args[2] == true and INV[1].secure_card == 0)
clear(); tick(TOB.GateHackTime - 2000)
check("gate stays shut during the gate hack", last("tobsbank:toggleDoor") == nil)
tick(2000)
check("server opens the gate", last("tobsbank:toggleDoor").args[2] == false and last("tobsbank:gateOpened").target == 1)
at(1, start("F1"))
fire(2, "tobsbank:lootup", "F1", "Loot3")
check("gate trolley lootable after the gate", last("tobsbank:lootResult").args[3] == true)
now = now + 40000; fire(2, "tobsbank:grabDone")
TOB.GateItem = ""

-- 17. deposit boxes (F1 still open)
local box1, box2 = TOB.Banks.F1.boxes[1], TOB.Banks.F1.boxes[2]
INV[2] = {}; at(2, box1); clear()
fire(2, "tobsbank:drillBox", "F1", 1)
check("box needs a drill", last("tobsbank:drillResult").args[4] == "no_drill")
INV[2].drill = 1; clear()
fire(2, "tobsbank:drillBox", "F1", 1)
check("drilling starts", last("tobsbank:drillResult").args[3] == true and last("tobsbank:boxState").args[3] == "busy")
check("drill is not used up", INV[2].drill == 1)
at(2, box2); clear()
fire(2, "tobsbank:drillBox", "F1", 2)
check("EXPLOIT: one box at a time", last("tobsbank:drillResult").args[4] == "already_drilling")
INV[3] = {drill = 1}; at(3, box1); clear()
fire(3, "tobsbank:drillBox", "F1", 1)
check("second player can't drill the same box", last("tobsbank:drillResult").args[4] == "box_busy")
at(2, box1); local m1 = MONEY[2] or 0; clear()
fire(2, "tobsbank:drillDone", "F1", 1, true)
check("finishing too fast is blocked", last("tobsbank:boxReward") == nil and (MONEY[2] or 0) == m1)
TOB.DrillRewards = {{type = "money", min = 5000, max = 5000, chance = 1}}
now = now + TOB.DrillTime; clear()
fire(2, "tobsbank:drillDone", "F1", 1, true)
check("box pays out after drilling", (MONEY[2] or 0) - m1 == 5000 and last("tobsbank:boxState").args[3] == "opened")
TOB.DrillRewards = {{type = "item", name = "goldbar", min = 2, max = 2, chance = 1}}
CANCARRY = false; at(2, box2); clear()
fire(2, "tobsbank:drillBox", "F1", 2); now = now + TOB.DrillTime
fire(2, "tobsbank:drillDone", "F1", 2, true)
check("full pockets: box stays closed", last("tobsbank:bagFull") ~= nil and last("tobsbank:boxState").args[3] == nil)
CANCARRY = true; clear()
fire(2, "tobsbank:drillBox", "F1", 2); now = now + TOB.DrillTime
fire(2, "tobsbank:drillDone", "F1", 2, true)
check("box item after making room", ITEMS[2] and ITEMS[2].goldbar == 2)

-- 18. loot as items, and full pockets
TOB.RewardItem = "markedbills"; TOB.RewardItemCount = 10
local F1T1 = TOB.Banks.F1.trolley1
at(3, F1T1); fire(3, "tobsbank:lootup", "F1", "Loot1")
CANCARRY = false; clear()
now = now + 18500; fire(3, "tobsbank:rewardCash")
now = now + 1000; fire(3, "tobsbank:rewardCash")
check("full pockets: told once, nothing lost yet", count("tobsbank:bagFull") == 1 and (ITEMS[3] == nil or ITEMS[3].markedbills == nil))
CANCARRY = true
now = now + 20000; fire(3, "tobsbank:grabDone")
check("items paid for a full trolley", ITEMS[3].markedbills == 10 and MONEY[3] == nil)
TOB.RewardItem = ""; TOB.RewardItemCount = "cash"
commands[SV.ResetCommand](0, {})
check("admin reset relocks the fleeca gate", Doors.F1[1].locked == true)
local reslog = false
for _, line in ipairs(printed) do if line:find("Player3: $60,000 (paid as 10 × markedbills)", 1, true) then reslog = true end end
check("log shows items instead of cash", reslog)

-- 19. special trolley pays the multiplier
TOB.SpecialTrolleyChance = 100
openHeist("B1", 1)
local slot, kind = next(Heists.B1.special)
check("special trolley picked and sent", slot ~= nil and last("tobsbank:vaultOpened").args[2][slot] == kind)
check("alarm switched on for Paleto", last("tobsbank:alarm") and last("tobsbank:alarm").args[2] == true)
at(2, TOB.Banks.B1[slot]); local m2 = MONEY[2] or 0; clear()
fire(2, "tobsbank:lootup", "B1", "Loot" .. slot:sub(-1))
now = now + 40000; fire(2, "tobsbank:grabDone")
check("special trolley multiplier", MONEY[2] - m2 == math.floor(60000 * TOB.SpecialTrolleys[kind].multiplier))
check("loot counter event", last("tobsbank:grabbed") ~= nil)
TOB.SpecialTrolleyChance = 0
-- 20. security timer runs out
clear(); tick(TOB.timer * 1000)
check("timer runs out -> vault closing", Heists.B1.stage == "closing")
commands[SV.ResetCommand](0, {})
check("alarm switched off", last("tobsbank:alarm") and last("tobsbank:alarm").args[2] == false)

-- 21. crew, one at a time, global cooldown, restart protection, missing card
TOB.MinCrew = 2; INV[1].id_card_f = 1; at(1, start("B1")); at(2, vector3(0, 0, 1)); at(3, vector3(0, 0, 1)); now = now + 3000; clear()
fire(1, "tobsbank:startcheck", "B1")
check("crew too small", last("tobsbank:outcome").args[2] == RefusalText("crew", 2, 1))
at(2, start("B1")); now = now + 3000; clear()
fire(1, "tobsbank:startcheck", "B1")
check("crew big enough", last("tobsbank:outcome").args[1] == true)
TOB.MinCrew = 1; TOB.OneAtATime = true
INV[3] = {id_card_f = 1}; at(3, start("F2")); TOB.Banks.F2.lastrobbed = 0; clear()
fire(3, "tobsbank:startcheck", "F2")
check("one at a time", last("tobsbank:outcome").args[2] == RefusalText("one_at_a_time"))
TOB.OneAtATime = false
commands[SV.ResetCommand](0, {"B1"})
TOB.GlobalCooldown = 300
begin("B1", 1); fire(1, "tobsbank:hackFailed", "B1")
now = now + 3000; clear(); fire(3, "tobsbank:startcheck", "F2")
check("global cooldown", last("tobsbank:outcome").args[2]:find(LX("refuse_global_cooldown", ""):sub(1, 15), 1, true) ~= nil)
TOB.GlobalCooldown = 0
handlers["txAdmin:events:scheduledRestart"]({secondsRemaining = 1800})
now = now + 3000; clear(); fire(3, "tobsbank:startcheck", "F2")
check("30 min warning doesn't block", last("tobsbank:outcome").args[1] == true)
commands[SV.ResetCommand](0, {}); INV[3].id_card_f = 1
handlers["txAdmin:events:scheduledRestart"]({secondsRemaining = 900})
now = now + 3000; clear(); fire(3, "tobsbank:startcheck", "F2")
check("15 min warning blocks", last("tobsbank:outcome").args[2] == RefusalText("restart"))
handlers["txAdmin:events:scheduledRestartSkipped"]({})
REMOVE_OK = false; now = now + 3000; clear(); fire(3, "tobsbank:startcheck", "F2")
check("card that can't be taken -> no heist", last("tobsbank:outcome").args[1] == false and Heists.F2 == nil)
REMOVE_OK = true; now = now + 3000; clear(); fire(3, "tobsbank:startcheck", "F2")
check("skipped restart unblocks", last("tobsbank:outcome").args[1] == true)
commands[SV.ResetCommand](0, {})

-- 22. police doors
local G = TOB.Banks.B1.gate.loc
at(3, G); clear()
fire(3, "tobsbank:toggleDoor", "B1", true)
check("stranger can't use the gate", last("tobsbank:toggleDoor") == nil)
POLICE[3] = true
fire(3, "tobsbank:toggleDoor", "B1", "yes")
check("door state must be true/false", last("tobsbank:toggleDoor") == nil)
fire(3, "tobsbank:toggleDoor", "B1", true)
check("police can lock the gate", last("tobsbank:toggleDoor").args[2] == true)
at(3, vector3(0, 0, 1)); clear()
fire(3, "tobsbank:toggleDoor", "B1", false)
check("police must be at the gate", last("tobsbank:toggleDoor") == nil)
POLICE[3] = nil
-- 23. vault angle only accepted right after a real vault move
now = now + 30000
at(2, VL); clear()
fire(2, "tobsbank:updateVaultState", "B1", 45.0)
check("vault angle ignored without a vault move", last("tobsbank:vaultState") == nil)
openHeist("B1", 1)
fire(2, "tobsbank:updateVaultState", "B1", 45.0)
check("vault angle accepted after a move", last("tobsbank:vaultState").args[2] == 45.0)
clear(); fire(2, "tobsbank:updateVaultState", "B1", 99.0)
check("only the first report counts", last("tobsbank:vaultState") == nil)
-- 24. exports: reset from another resource
check("export ResetHeist", exported.ResetHeist("B1") == true and Heists.B1 == nil)
-- 25. safety net for stuck heists
openHeist("B1", 1)
local realos = os.time
local fake = realos() + 100000
os.time = function() return fake end
clear(); HeistTick()
os.time = realos
check("stuck heist ended by the safety net", Heists.B1 == nil and last("tobsbank:forceReset") ~= nil)
-- 26. update check and the getBanks callback
threads[#threads](); http[#http].cb(200, "v9.9.9")
check("update available printed", printed[#printed]:find("9.9.9 is available"))
http[#http].cb(200, "v2.1.0")
check("up to date printed", printed[#printed]:find("up to date"))
local got; callbacks["tobsbank:getBanks"](1, function(b, d) got = d end)
check("doors built from the config", got.B1[1].h == 42.639282226562 and got.B1[2].loc.y > 6475 and got.F6 == nil)


-- 27. per-bank cash and cooldown
TOB.Banks.F1.cash = {min = 40000, max = 40000}
openHeist("F1", 1)
at(2, TOB.Banks.F1.trolley1); local m27 = MONEY[2] or 0
fire(2, "tobsbank:lootup", "F1", "Loot1"); now = now + 40000; fire(2, "tobsbank:grabDone")
check("bank's own cash per trolley", MONEY[2] - m27 == 40000)
commands[SV.ResetCommand](0, {})
TOB.Banks.F1.cash = nil
TOB.Banks.F1.lastrobbed = os.time() - 100
at(1, start("F1")); INV[1].id_card_f = 1; now = now + 3000; clear()
fire(1, "tobsbank:startcheck", "F1")
check("default cooldown still running", last("tobsbank:outcome").args[1] == false)
TOB.Banks.F1.cooldown = 60; now = now + 3000; clear()
fire(1, "tobsbank:startcheck", "F1")
check("bank's own cooldown", last("tobsbank:outcome").args[1] == true)
TOB.Banks.F1.cooldown = nil
commands[SV.ResetCommand](0, {})

-- 28. trolleys spawned by the server
TOB.TrolleySpawn = "server"
openHeist("B1", 1)
check("server spawns the trolleys", #objects == 3 and last("tobsbank:vaultOpened").args[4] == true)
check("gold/diamond fall back to a cash trolley below game build 2060", objects[1].model == #"hei_prop_hei_cash_trolly_01")
at(2, start("B1")); at(3, vector3(0, 0, 1)); clear()
fire(1, "playerDropped")
check("takeover knows the server has the trolleys", last("tobsbank:takeover").args[2].serverTrolleys == true)
commands[SV.ResetCommand](0, {})
check("server trolleys removed when the heist ends", deleted[901] and deleted[902] and deleted[903])
TOB.TrolleySpawn = "client"
openHeist("B1", 1)
check("client spawn mode: no server trolleys", #objects == 3 and last("tobsbank:vaultOpened").args[4] == false)
commands[SV.ResetCommand](0, {})

-- 29. marked bills: one item per trolley with its value
TOB.MarkedBills = true; Bridge.Metadata = true; METADATA = {}
openHeist("B1", 1)
at(2, TOB.Banks.B1.trolley1); local m29 = MONEY[2] or 0; clear()
fire(2, "tobsbank:lootup", "B1", "Loot1")
now = now + 18500; fire(2, "tobsbank:rewardCash")
check("marked bills: nothing paid while grabbing", (MONEY[2] or 0) == m29 and #METADATA == 0 and last("tobsbank:grabbed").args[1] == 30000)
now = now + 30000; fire(2, "tobsbank:grabDone")
check("marked bills: one bag with the trolley's worth", #METADATA == 1 and METADATA[1].item == "markedbills" and METADATA[1].n == 1 and METADATA[1].metadata.worth == 60000)
at(2, TOB.Banks.B1.trolley2); CANCARRY = false; local d29 = DIRTY[2] or 0
fire(2, "tobsbank:lootup", "B1", "Loot2"); now = now + 40000; fire(2, "tobsbank:rewardCash"); fire(2, "tobsbank:grabDone")
check("marked bills: no room -> paid as dirty money", DIRTY[2] - d29 == 60000)
CANCARRY = true
Bridge.Metadata = nil; at(2, TOB.Banks.B1.trolley3); local m29b = MONEY[2]
fire(2, "tobsbank:lootup", "B1", "Loot3"); now = now + 40000; fire(2, "tobsbank:grabDone")
check("marked bills without metadata support: cash", MONEY[2] - m29b == 60000)
TOB.MarkedBills = false
commands[SV.ResetCommand](0, {})

-- 30. dye pack
TOB.DyePack.enabled = true; TOB.DyePack.chance = 100
openHeist("B1", 1)
at(2, TOB.Banks.B1.trolley1); local m30, d30 = MONEY[2], DIRTY[2] or 0; clear()
fire(2, "tobsbank:lootup", "B1", "Loot1"); now = now + 40000; fire(2, "tobsbank:grabDone")
check("dye pack ruins part of the money", MONEY[2] - m30 == 45000)
check("dye pack: the rest is dirty money", DIRTY[2] - d30 == 45000)
check("dye pack bursts when grabbing ends", last("tobsbank:dyePack").args[1] == 2 and last("tobsbank:dyePack").target == -1)
TOB.DyePack.enabled = false
commands[SV.ResetCommand](0, {})

-- 31. GPS tracker
TOB.Tracker.enabled = true; TOB.Tracker.chance = 100
openHeist("B1", 1)
at(2, TOB.Banks.B1.trolley1); POLICE[3] = true; clear()
fire(2, "tobsbank:lootup", "B1", "Loot1"); now = now + 40000; fire(2, "tobsbank:grabDone")
check("robber warned about the tracker", last("tobsbank:trackerWarn").target == 2)
at(2, vector3(500, 500, 30)); clear(); tick(1000)
check("police get the robber's position", last("tobsbank:trackerPos").target == 3 and last("tobsbank:trackerPos").args[1] == 2 and last("tobsbank:trackerPos").args[2].x == 500)
check("only police get it", count("tobsbank:trackerPos") == 1)
clear(); tick(1000)
check("position updates every interval", last("tobsbank:trackerPos") == nil)
clear(); tick(TOB.Tracker.duration * 1000)
check("tracker stops after its time", last("tobsbank:trackerEnd") ~= nil)
commands[SV.ResetCommand](0, {})
openHeist("B1", 1)
at(2, TOB.Banks.B1.trolley1); fire(2, "tobsbank:lootup", "B1", "Loot1"); now = now + 40000; fire(2, "tobsbank:grabDone")
clear(); fire(2, "playerDropped")
check("tracker stops when the robber leaves", last("tobsbank:trackerEnd") ~= nil)
TOB.Tracker.enabled = false; POLICE[3] = nil
commands[SV.ResetCommand](0, {})

-- 32. a heist ending mid-grab still hands out marked bills
TOB.MarkedBills = true; Bridge.Metadata = true; METADATA = {}
openHeist("B1", 1)
at(2, TOB.Banks.B1.trolley1); fire(2, "tobsbank:lootup", "B1", "Loot1")
now = now + 18500; fire(2, "tobsbank:rewardCash")
commands[SV.ResetCommand](0, {})
check("grab finished when the heist ends", #METADATA == 1 and METADATA[1].metadata.worth == 30000 and Looting[2] == nil)
TOB.MarkedBills = false; Bridge.Metadata = nil

-- 33. admin tools in the heist (server/tools.lua): pause, refusals, test mode, bank sounds
commands[SV.PauseCommand](0, {"server", "event"}); clear()
begin("B1", 1)
check("paused: heist refused with the reason", last("tobsbank:outcome").args[2] == PauseRefusal() and Heists.B1 == nil)
commands[SV.PauseCommand](0, {"off"}); clear()
begin("B1", 1)
check("allowed again after /tobpause off", Heists.B1 ~= nil)
commands[SV.ResetCommand](0, {})
POLICE[1] = true; clear(); begin("B1", 1)
check("police get a refusal instead of silence", last("tobsbank:outcome").args[2] == RefusalText("police_job"))
POLICE[1] = nil
TOB.Banks.B1.lastrobbed = os.time(); clear(); begin("B1", 1)
check("cooldown refusal says how long", last("tobsbank:outcome").args[2]:find(FormatDuration(TOB.cooldown):sub(1, 3), 1, true) ~= nil)
-- test mode: no police needed, no cooldown, no pay
commands[SV.TestCommand](1, {})
COPS = 0; local robbedAt, lastEnd = TOB.Banks.B1.lastrobbed, LastHeistEnd; clear()
openHeist("B1", 1)
check("test mode skips the police and cooldown rules", Heists.B1 ~= nil and Heists.B1.stage == "open")
check("test heist is labelled in the log", printedHas("[TEST] Heist started"))
check("... and logged once, not twice", not printedHas("started a test heist"))
check("vault sound for everyone in the bank", last("tobs_bankrobbery:bankSound").args[2] == "vault" and last("tobs_bankrobbery:bankSound").target == -1)
at(2, TOB.Banks.B1.trolley1); local m33 = MONEY[2] or 0; clear()
fire(2, "tobsbank:lootup", "B1", "Loot1"); now = now + 40000; fire(2, "tobsbank:grabDone")
check("test heist: the trolley pays nothing", (MONEY[2] or 0) == m33)
check("... but the loot counter still counts", last("tobsbank:grabbed") ~= nil and last("tobsbank:grabbed").args[1] == 60000)
TOB.DrillRewards = {{type = "money", min = 5000, max = 5000, chance = 1}}
INV[2].drill = 1; at(2, TOB.Banks.B1.boxes[1]); clear()
fire(2, "tobsbank:drillBox", "B1", 1)
local on = last("tobs_bankrobbery:bankSound")
check("drill sound for everyone but the driller", on.args[2] == "drill_on" and on.args[3] == 1 and on.args[4] == 2)
now = now + TOB.DrillTime; clear()
fire(2, "tobsbank:drillDone", "B1", 1, true)
check("drill sound stops", last("tobs_bankrobbery:bankSound").args[2] == "drill_off")
check("test heist: the box pays nothing but says what was inside", (MONEY[2] or 0) == m33 and last("tobsbank:boxReward") ~= nil)
at(2, TOB.Banks.B1.boxes[2]); fire(2, "tobsbank:drillBox", "B1", 2); clear()
tick(TOB.timer * 1000); tick((TOB.VaultCloseDelay or 30) * 1000); tick(10000)
check("test heist ends normally", Heists.B1 == nil and printedHas("[TEST] Heist ended"))
check("a heist ending mid-drill stops the drill sound", last("tobs_bankrobbery:bankSound") ~= nil and last("tobs_bankrobbery:bankSound").args[2] == "drill_off")
check("test heist sets no cooldown", TOB.Banks.B1.lastrobbed == robbedAt and LastHeistEnd == lastEnd)
commands[SV.TestCommand](1, {}); COPS = 4
clear(); begin("B1", 1)
check("test mode off: the rules apply again", last("tobsbank:outcome").args[1] == false)
commands[SV.ResetCommand](0, {})

realprint(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
