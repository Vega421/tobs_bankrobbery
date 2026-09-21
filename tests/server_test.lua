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
function Bridge.AddItem(src, item, n)
    if not CANCARRY then return false end
    ITEMS[src] = ITEMS[src] or {}
    ITEMS[src][item] = (ITEMS[src][item] or 0) + n
    return true
end
function Bridge.AddMoney(src, amount) MONEY[src] = (MONEY[src] or 0) + amount end
local callbacks = {}
function Bridge.RegisterCallback(name, fn) callbacks[name] = fn end

-- LOAD THE SCRIPT --
dofile("config/config.lua"); dofile("locales/locales.lua"); dofile("config/config_server.lua")
TOB.Banks.F6.enabled = false
TOB.Banks.BROKEN = {label = "Broken bank", doors = {}}   -- missing settings: must be skipped, not crash
TOB.TrolleyCash = {min = 60000, max = 60000}              -- fixed so payouts can be checked exactly
TOB.SpecialTrolleyChance = 0  -- random gold/diamond trolleys would make payout checks flaky; test 19 turns them on
SV.Webhook = "https://discord.test/hook"
local dispatched = nil
SV.DispatchAlert = function(bank, coords, src) dispatched = {bank = bank, src = src} end
kvp["lastrobbed:F2"] = os.time() -- a cooldown saved before a restart
for _, f in ipairs({"server/util.lua", "server/heist.lua", "server/loot.lua", "server/boxes.lua", "server/doors.lua", "server/admin.lua", "server/api.lua"}) do
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
    fire(src, "TOB_fh:startcheck", bank)
end
-- Starts a heist and runs it until the vault is open
local function openHeist(bank, src)
    begin(bank, src)
    fire(src, "TOB_fh:hackStarted", bank)
    tick(TOB.hacktime)
end

-- 0. startup
check("OneSync warning printed when OneSync is off", printedHas("OneSync is off"))
check("broken bank skipped with a warning", TOB.Banks.BROKEN == nil and printedHas("Bank BROKEN is missing"))
check("disabled bank removed", TOB.Banks.F6 == nil)
check("saved cooldown loaded after a restart", TOB.Banks.F2.lastrobbed == kvp["lastrobbed:F2"])
check("fleeca gate locked by default", Doors.F1[1].locked == true and Doors.B1[1].locked == false)

-- 1. no cops
COPS = 0; INV[1] = {id_card_f = 1}
fire(1, "TOB_fh:startcheck", "B1")
check("no cops message", last("TOB_fh:outcome").args[2] == L("no_cops"))
-- 2. start
COPS = 4; clear(); now = now + 3000
fire(1, "TOB_fh:startcheck", "B1")
check("heist started", last("TOB_fh:outcome").args[1] == true and Heists.B1 ~= nil and Heists.B1.stage == "card")
check("card used", INV[1].id_card_f == 0)
check("police alerted", last("TOB_fh:policenotify") ~= nil)
check("everyone told the bank is busy", last("TOB_fh:bankState").args[2] == true and last("TOB_fh:bankState").target == -1)
check("start logged to discord", #http == 1)
check("heistStarted event for other resources", lastEvent("tobs_bankrobbery:heistStarted").args[1] == "B1")
check("server dispatch hook called", dispatched and dispatched.bank == "B1" and dispatched.src == 1)
check("export IsHeistActive", exported.IsHeistActive("B1") == true and exported.IsHeistActive() == true and exported.IsHeistActive("F1") == false)
-- 3. busy + rate limit
INV[2] = {id_card_f = 1}; clear()
fire(2, "TOB_fh:startcheck", "B1")
check("busy message", last("TOB_fh:outcome").args[2] == L("busy"))
clear(); fire(2, "TOB_fh:startcheck", "B1")
check("start spam is rate limited", last("TOB_fh:outcome") == nil)

-- 4. EXPLOIT: the robber can't open the vault or skip the hack
clear(); fire(1, "TOB_fh:toggleVault", "B1", false)
check("robber can't open the vault", last("TOB_fh:toggleVault") == nil and #http == 1)
clear(); tick(TOB.hacktime + 5000)
check("vault stays shut while the minigame isn't done", last("TOB_fh:toggleVault") == nil and Heists.B1.stage == "card")
-- 5. EXPLOIT: no looting before the vault is open
clear(); fire(2, "TOB_fh:lootup", "B1", "Loot1")
check("no looting before the vault opens", last("TOB_fh:lootResult").args[3] == false and last("TOB_fh:lootup_c") == nil)
clear(); fire(3, "TOB_fh:rewardCash")
check("cash without looting is blocked and flagged", MONEY[3] == nil and #http == 1)
fire(3, "TOB_fh:rewardCash")
check("flags are rate limited", #http == 1)
-- 6. EXPLOIT: no deposit boxes before the vault is open
INV[2].drill = 1; clear()
fire(2, "TOB_fh:drillBox", "B1", 1)
check("no drilling before the vault opens", last("TOB_fh:drillResult") == nil)
-- 7. the hack runs on the server
fire(2, "TOB_fh:hackStarted", "B1")
check("only the robber can start the hack", Heists.B1.stage == "card")
fire(1, "TOB_fh:hackStarted", "B1")
check("hack started", Heists.B1.stage == "hacking")
clear(); tick(TOB.hacktime - 2000)
check("vault still shut before the hack time is over", last("TOB_fh:toggleVault") == nil)
tick(2000)
check("server opens the vault when the hack is done", last("TOB_fh:toggleVault").args[2] == false and Heists.B1.stage == "open")
check("robber told to spawn the trolleys", last("TOB_fh:vaultOpened").target == 1)
check("loot phase sent to everyone", last("TOB_fh:startLoot_c").target == -1)
check("hack done told to the robber", last("TOB_fh:hackDone").target == 1)
check("security timer sent", last("TOB_fh:timer").args[2] == TOB.timer)
check("vaultOpened event for other resources", lastEvent("tobs_bankrobbery:vaultOpened") ~= nil)

-- 8. looting and paying by grab time
local T1 = TOB.Banks.B1.trolley1
at(2, T1); clear()
fire(2, "TOB_fh:lootup", "B1", "Loot1")
check("loot confirmed to the player", last("TOB_fh:lootResult").args[3] == true)
check("loot broadcast", last("TOB_fh:lootup_c") ~= nil)
at(3, T1); clear()
fire(3, "TOB_fh:lootup", "B1", "Loot1")
check("trolley can't be taken twice", last("TOB_fh:lootResult").args[3] == false and last("TOB_fh:lootResult").args[4] == "trolley_taken")
now = now + 18500
fire(2, "TOB_fh:rewardCash")
check("half the grab time pays half the trolley", MONEY[2] == 30000)
now = now + 100; fire(2, "TOB_fh:rewardCash")
check("asking again straight away pays nothing more", MONEY[2] == 30000)
now = now + 30000; fire(2, "TOB_fh:rewardCash")
check("a full trolley pays exactly its value", MONEY[2] == 60000)
now = now + 10000; fire(2, "TOB_fh:rewardCash")
check("never more than the trolley holds", MONEY[2] == 60000)
fire(2, "TOB_fh:grabDone")
check("grab finished", Looting[2] == nil)
-- 9. EXPLOIT: fast pile requests can't pay faster than grabbing
local T2 = TOB.Banks.B1.trolley2
at(2, T2)
fire(2, "TOB_fh:lootup", "B1", "Loot2")
local before = MONEY[2]
for _ = 1, 50 do now = now + 250; fire(2, "TOB_fh:rewardCash") end -- 12.5 s of spam
check("spamming pays only for the time spent", MONEY[2] - before <= math.floor(60000 * 12.5 / 37) and MONEY[2] - before > 0)
-- away from the trolley
at(2, vector3(0, 0, 1)); local m = MONEY[2]; clear()
now = now + 1000; fire(2, "TOB_fh:rewardCash")
check("no cash away from the trolley (flagged)", MONEY[2] == m and #http == 1)
at(2, T2); now = now + 30000
fire(2, "TOB_fh:grabDone")
check("finishing pays the rest", MONEY[2] - before == 60000)
at(2, vector3(0, 0, 1)); clear()
fire(2, "TOB_fh:lootup", "B1", "Loot3")
check("far trolley flagged", last("TOB_fh:lootResult").args[3] == false and #http == 1)

-- 10. all trolleys looted -> vault closes -> cleanup -> cooldown saved
local T3 = TOB.Banks.B1.trolley3
at(2, T3); fire(2, "TOB_fh:lootup", "B1", "Loot3")
tick(1000)
check("vault doesn't close while someone is still grabbing", Heists.B1.stage == "open")
now = now + 40000; fire(2, "TOB_fh:grabDone"); clear()
tick(1000)
check("all looted -> vault closing", Heists.B1.stage == "closing" and last("TOB_fh:closing").args[2] == TOB.VaultCloseDelay)
tick(TOB.VaultCloseDelay * 1000)
check("vault closes after the delay", last("TOB_fh:toggleVault").args[2] == true and Heists.B1.stage == "cleanup")
clear(); tick(10000)
check("props cleaned up and heist ended", last("TOB_fh:cleanup") ~= nil and Heists.B1 == nil)
check("everyone told the bank is free", last("TOB_fh:bankState").args[2] == false)
check("heist totals sent", last("TOB_fh:heistTotal") ~= nil and last("TOB_fh:heistTotal").args[2] == "180,000")
check("cooldown saved (survives restarts)", kvp["lastrobbed:B1"] == TOB.Banks.B1.lastrobbed and TOB.Banks.B1.lastrobbed > 0)
check("heistEnded event for other resources", lastEvent("tobs_bankrobbery:heistEnded").args[3] == 180000)
local endlog = printed[#printed]
check("end log has the reason and the payout", endlog:find("all trolleys were looted") and endlog:find("Player2: $180,000"))
-- 11. cooldown, admin reset
INV[1].id_card_f = 1; at(1, start("B1")); now = now + 3000; clear()
fire(1, "TOB_fh:startcheck", "B1")
check("cooldown message", last("TOB_fh:outcome").args[2]:find(L("cooldown", ""):sub(1, 20), 1, true))
commands[SV.ResetCommand](0, {})
check("reset clears the cooldown", TOB.Banks.B1.lastrobbed == 0 and kvp["lastrobbed:B1"] == 0)
check("reset tells clients", last("TOB_fh:forceReset") ~= nil)
check("export GetBanks", exported.GetBanks()[1].bank == "B1" and exported.GetBanks()[1].cooldownLeft == 0)

-- 12. hack failed / taking too long
clear(); begin("B1", 1)
fire(1, "TOB_fh:hackFailed", "B1")
check("failed hack ends the heist", Heists.B1 == nil and last("TOB_fh:heistFailed").args[2] == "hack_failed")
commands[SV.ResetCommand](0, {"B1"})
begin("B1", 1); clear()
tick(91000)
check("minigame never finished -> heist ends", Heists.B1 == nil and last("TOB_fh:heistFailed") ~= nil)
commands[SV.ResetCommand](0, {"B1"})

-- 13. the robber leaves the bank
begin("B1", 1); fire(1, "TOB_fh:hackStarted", "B1")
at(1, vector3(0, 0, 1)); clear(); tick(1000)
check("leaving during the hack fails the heist", Heists.B1 == nil and last("TOB_fh:heistFailed").args[2] == "robber_left")
commands[SV.ResetCommand](0, {"B1"})
openHeist("B1", 1)
at(1, vector3(0, 0, 1)); tick(1000)
check("leaving during looting closes the vault", Heists.B1.stage == "closing")
commands[SV.ResetCommand](0, {"B1"})

-- 14. the robber disconnects: the nearest crew member takes over
openHeist("B1", 1)
at(2, start("B1")); at(3, vector3(0, 0, 1)); clear()
fire(1, "playerDropped")
check("crew member takes over", Heists.B1.owner == 2 and last("TOB_fh:takeover").target == 2)
check("takeover has the heist state", last("TOB_fh:takeover").args[2].stage == "open")
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
check("vault item step instead of opening", Heists.B1.stage == "vaultitem" and last("TOB_fh:awaitVaultItem").target == 1)
local VL = TOB.Banks.B1.vault.loc
at(1, VL); clear()
fire(1, "TOB_fh:useVaultItem", "B1")
check("no item -> false", last("TOB_fh:vaultItemResult").args[2] == false)
INV[1].thermite = 1
fire(1, "TOB_fh:useVaultItem", "B1")
check("item used", last("TOB_fh:vaultItemResult").args[2] == true and INV[1].thermite == 0)
clear(); tick(TOB.VaultItemTime - 2000)
check("vault doesn't open before the thermite burned through", last("TOB_fh:toggleVault") == nil)
tick(2000)
check("vault opens after the thermite", Heists.B1.stage == "open")
commands[SV.ResetCommand](0, {"B1"})
openHeist("B1", 1); clear()
tick(TOB.timer * 1000)
check("vault item never used -> heist fails", Heists.B1 == nil and last("TOB_fh:heistFailed").args[2] == "vault_timeout")
commands[SV.ResetCommand](0, {"B1"})
TOB.VaultItem = ""

-- 16. Fleeca inner gate: the last trolley needs the gate hacked
openHeist("F1", 1)
local F1T3 = TOB.Banks.F1.trolley3
at(2, F1T3); clear()
fire(2, "TOB_fh:lootup", "F1", "Loot3")
check("gate trolley can't be looted before the gate is hacked", last("TOB_fh:lootResult").args[3] == false and #http == 1)
local sec = TOB.Banks.F1.doors.secondloc
at(1, sec); TOB.GateItem = "secure_card"; clear()
fire(1, "TOB_fh:useGate", "F1")
check("gate needs the item", last("TOB_fh:gateResult").args[2] == false)
INV[1].secure_card = 1
fire(1, "TOB_fh:useGate", "F1")
check("gate hack started", last("TOB_fh:gateResult").args[2] == true and INV[1].secure_card == 0)
clear(); tick(TOB.GateHackTime - 2000)
check("gate stays shut during the gate hack", last("TOB_fh:toggleDoor") == nil)
tick(2000)
check("server opens the gate", last("TOB_fh:toggleDoor").args[2] == false and last("TOB_fh:gateOpened").target == 1)
at(1, start("F1"))
fire(2, "TOB_fh:lootup", "F1", "Loot3")
check("gate trolley lootable after the gate", last("TOB_fh:lootResult").args[3] == true)
now = now + 40000; fire(2, "TOB_fh:grabDone")
TOB.GateItem = ""

-- 17. deposit boxes (F1 still open)
local box1, box2 = TOB.Banks.F1.boxes[1], TOB.Banks.F1.boxes[2]
INV[2] = {}; at(2, box1); clear()
fire(2, "TOB_fh:drillBox", "F1", 1)
check("box needs a drill", last("TOB_fh:drillResult").args[4] == "no_drill")
INV[2].drill = 1; clear()
fire(2, "TOB_fh:drillBox", "F1", 1)
check("drilling starts", last("TOB_fh:drillResult").args[3] == true and last("TOB_fh:boxState").args[3] == "busy")
check("drill is not used up", INV[2].drill == 1)
at(2, box2); clear()
fire(2, "TOB_fh:drillBox", "F1", 2)
check("EXPLOIT: one box at a time", last("TOB_fh:drillResult").args[4] == "already_drilling")
INV[3] = {drill = 1}; at(3, box1); clear()
fire(3, "TOB_fh:drillBox", "F1", 1)
check("second player can't drill the same box", last("TOB_fh:drillResult").args[4] == "box_busy")
at(2, box1); local m1 = MONEY[2] or 0; clear()
fire(2, "TOB_fh:drillDone", "F1", 1, true)
check("finishing too fast is blocked", last("TOB_fh:boxReward") == nil and (MONEY[2] or 0) == m1)
TOB.DrillRewards = {{type = "money", min = 5000, max = 5000, chance = 1}}
now = now + TOB.DrillTime; clear()
fire(2, "TOB_fh:drillDone", "F1", 1, true)
check("box pays out after drilling", (MONEY[2] or 0) - m1 == 5000 and last("TOB_fh:boxState").args[3] == "opened")
TOB.DrillRewards = {{type = "item", name = "goldbar", min = 2, max = 2, chance = 1}}
CANCARRY = false; at(2, box2); clear()
fire(2, "TOB_fh:drillBox", "F1", 2); now = now + TOB.DrillTime
fire(2, "TOB_fh:drillDone", "F1", 2, true)
check("full pockets: box stays closed", last("TOB_fh:bagFull") ~= nil and last("TOB_fh:boxState").args[3] == nil)
CANCARRY = true; clear()
fire(2, "TOB_fh:drillBox", "F1", 2); now = now + TOB.DrillTime
fire(2, "TOB_fh:drillDone", "F1", 2, true)
check("box item after making room", ITEMS[2] and ITEMS[2].goldbar == 2)

-- 18. loot as items, and full pockets
TOB.RewardItem = "markedbills"; TOB.RewardItemCount = 10
local F1T1 = TOB.Banks.F1.trolley1
at(3, F1T1); fire(3, "TOB_fh:lootup", "F1", "Loot1")
CANCARRY = false; clear()
now = now + 18500; fire(3, "TOB_fh:rewardCash")
now = now + 1000; fire(3, "TOB_fh:rewardCash")
check("full pockets: told once, nothing lost yet", count("TOB_fh:bagFull") == 1 and (ITEMS[3] == nil or ITEMS[3].markedbills == nil))
CANCARRY = true
now = now + 20000; fire(3, "TOB_fh:grabDone")
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
check("special trolley picked and sent", slot ~= nil and last("TOB_fh:vaultOpened").args[2][slot] == kind)
check("alarm switched on for Paleto", last("TOB_fh:alarm") and last("TOB_fh:alarm").args[2] == true)
at(2, TOB.Banks.B1[slot]); local m2 = MONEY[2] or 0; clear()
fire(2, "TOB_fh:lootup", "B1", "Loot" .. slot:sub(-1))
now = now + 40000; fire(2, "TOB_fh:grabDone")
check("special trolley multiplier", MONEY[2] - m2 == math.floor(60000 * TOB.SpecialTrolleys[kind].multiplier))
check("loot counter event", last("TOB_fh:grabbed") ~= nil)
TOB.SpecialTrolleyChance = 0
-- 20. security timer runs out
clear(); tick(TOB.timer * 1000)
check("timer runs out -> vault closing", Heists.B1.stage == "closing")
commands[SV.ResetCommand](0, {})
check("alarm switched off", last("TOB_fh:alarm") and last("TOB_fh:alarm").args[2] == false)

-- 21. crew, one at a time, global cooldown, restart protection, missing card
TOB.MinCrew = 2; INV[1].id_card_f = 1; at(1, start("B1")); at(2, vector3(0, 0, 1)); at(3, vector3(0, 0, 1)); now = now + 3000; clear()
fire(1, "TOB_fh:startcheck", "B1")
check("crew too small", last("TOB_fh:outcome").args[2] == L("need_crew", 2))
at(2, start("B1")); now = now + 3000; clear()
fire(1, "TOB_fh:startcheck", "B1")
check("crew big enough", last("TOB_fh:outcome").args[1] == true)
TOB.MinCrew = 1; TOB.OneAtATime = true
INV[3] = {id_card_f = 1}; at(3, start("F2")); TOB.Banks.F2.lastrobbed = 0; clear()
fire(3, "TOB_fh:startcheck", "F2")
check("one at a time", last("TOB_fh:outcome").args[2] == L("global_busy"))
TOB.OneAtATime = false
commands[SV.ResetCommand](0, {"B1"})
TOB.GlobalCooldown = 300
begin("B1", 1); fire(1, "TOB_fh:hackFailed", "B1")
now = now + 3000; clear(); fire(3, "TOB_fh:startcheck", "F2")
check("global cooldown", last("TOB_fh:outcome").args[2]:find(L("global_cooldown", ""):sub(1, 15), 1, true) ~= nil)
TOB.GlobalCooldown = 0
handlers["txAdmin:events:scheduledRestart"]({secondsRemaining = 1800})
now = now + 3000; clear(); fire(3, "TOB_fh:startcheck", "F2")
check("30 min warning doesn't block", last("TOB_fh:outcome").args[1] == true)
commands[SV.ResetCommand](0, {}); INV[3].id_card_f = 1
handlers["txAdmin:events:scheduledRestart"]({secondsRemaining = 900})
now = now + 3000; clear(); fire(3, "TOB_fh:startcheck", "F2")
check("15 min warning blocks", last("TOB_fh:outcome").args[2] == L("restart_soon"))
handlers["txAdmin:events:scheduledRestartSkipped"]({})
REMOVE_OK = false; now = now + 3000; clear(); fire(3, "TOB_fh:startcheck", "F2")
check("card that can't be taken -> no heist", last("TOB_fh:outcome").args[1] == false and Heists.F2 == nil)
REMOVE_OK = true; now = now + 3000; clear(); fire(3, "TOB_fh:startcheck", "F2")
check("skipped restart unblocks", last("TOB_fh:outcome").args[1] == true)
commands[SV.ResetCommand](0, {})

-- 22. police doors
local G = TOB.Banks.B1.gate.loc
at(3, G); clear()
fire(3, "TOB_fh:toggleDoor", "B1", true)
check("stranger can't use the gate", last("TOB_fh:toggleDoor") == nil)
POLICE[3] = true
fire(3, "TOB_fh:toggleDoor", "B1", "yes")
check("door state must be true/false", last("TOB_fh:toggleDoor") == nil)
fire(3, "TOB_fh:toggleDoor", "B1", true)
check("police can lock the gate", last("TOB_fh:toggleDoor").args[2] == true)
at(3, vector3(0, 0, 1)); clear()
fire(3, "TOB_fh:toggleDoor", "B1", false)
check("police must be at the gate", last("TOB_fh:toggleDoor") == nil)
POLICE[3] = nil
-- 23. vault angle only accepted right after a real vault move
now = now + 30000
at(2, VL); clear()
fire(2, "TOB_fh:updateVaultState", "B1", 45.0)
check("vault angle ignored without a vault move", last("TOB_fh:vaultState") == nil)
openHeist("B1", 1)
fire(2, "TOB_fh:updateVaultState", "B1", 45.0)
check("vault angle accepted after a move", last("TOB_fh:vaultState").args[2] == 45.0)
clear(); fire(2, "TOB_fh:updateVaultState", "B1", 99.0)
check("only the first report counts", last("TOB_fh:vaultState") == nil)
-- 24. exports: reset from another resource
check("export ResetHeist", exported.ResetHeist("B1") == true and Heists.B1 == nil)
-- 25. safety net for stuck heists
openHeist("B1", 1)
local realos = os.time
local fake = realos() + 100000
os.time = function() return fake end
clear(); HeistTick()
os.time = realos
check("stuck heist ended by the safety net", Heists.B1 == nil and last("TOB_fh:forceReset") ~= nil)
-- 26. update check and the getBanks callback
threads[#threads](); http[#http].cb(200, "v9.9.9")
check("update available printed", printed[#printed]:find("9.9.9 is available"))
http[#http].cb(200, "v2.1.0")
check("up to date printed", printed[#printed]:find("up to date"))
local got; callbacks["TOB_fh:getBanks"](1, function(b, d) got = d end)
check("doors built from the config", got.B1[1].h == 42.639282226562 and got.B1[2].loc.y > 6475 and got.F6 == nil)

realprint(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
