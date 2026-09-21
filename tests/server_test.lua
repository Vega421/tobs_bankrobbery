-- Automated tests for tobs_bankrobbery. They run the real script files outside FiveM, with small fake
-- versions of the game and framework functions. Run from the repo root:  lua5.4 tests/server_test.lua
-- GitHub runs them on every push (.github/workflows/tests.yml).

local ROOT = ""
local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end

local handlers, sent, http, commands = {}, {}, {}, {}
local now = 100000
function RegisterServerEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, target, ...) sent[#sent + 1] = {name = name, target = target, args = {...}} end
function GetPlayerPed(src) return PEDS and PEDS[src] or 0 end
function GetEntityCoords(ped) return POS[ped] end
function GetPlayers() return {"1", "2", "3"} end
function GetPlayerName(src) return "Player" .. src end
function GetPlayerIdentifiers(src) return {"license:abc" .. src, "discord:99" .. src} end
function GetGameTimer() return now end
function GetCurrentResourceName() return "tobs_bankrobbery" end
function GetResourceMetadata() return "1.4.1" end
function PerformHttpRequest(url, cb, method, body) http[#http + 1] = {url = url, cb = cb, method = method, body = body} end
function RegisterCommand(name, fn) commands[name] = fn end
json = {encode = function() return "{}" end, decode = function(s) return {tag_name = s, html_url = "https://x"} end}
local threads = {}
-- Wait() normally does nothing; LOOP_LIMIT lets a test run exactly one pass of a "while true" loop
local waits, LOOP_LIMIT = 0, nil
Citizen = {CreateThread = function(fn) threads[#threads + 1] = fn end, Wait = function()
    waits = waits + 1
    if LOOP_LIMIT and waits > LOOP_LIMIT then error("stop loop") end
end}
local printed = {}
local realprint = print
print = function(s) printed[#printed + 1] = s end

-- Fake framework bridge
INV = {}; MONEY = {}; ITEMS = {}; POLICE = {}; COPS = 0
Bridge = {Repo = "Vega421/test"}
function Bridge.IsPolice(src) return POLICE[src] == true end
function Bridge.CountPolice() return COPS end
function Bridge.HasItem(src, item, n) return ((INV[src] or {})[item] or 0) >= n end
function Bridge.RemoveItem(src, item, n) INV[src][item] = INV[src][item] - n end
function Bridge.AddItem(src, item, n) ITEMS[src] = (ITEMS[src] or 0) + n end
function Bridge.AddMoney(src, amount) MONEY[src] = (MONEY[src] or 0) + amount end
local callbacks = {}
function Bridge.RegisterCallback(name, fn) callbacks[name] = fn end

local function load(f) dofile(f) end
load(ROOT .. "config/config.lua"); load(ROOT .. "locales/locales.lua"); load(ROOT .. "config/config_server.lua")
TOB.Banks.F6.enabled = false
TOB.Banks.BROKEN = {label = "Broken bank", doors = {}}  -- missing settings: must be skipped, not crash
TOB.mincash, TOB.maxcash = 6500, 3000                   -- wrong way round: must be swapped
TOB.SpecialTrolleyChance = 0  -- random gold/diamond trolleys would make payout checks flaky; test 26 turns them on
SV.Webhook = "https://discord.test/hook"
load(ROOT .. "server/main.lua")

local function fire(src, name, ...) source = src; handlers[name](...) end
local function last(name) for i = #sent, 1, -1 do if sent[i].name == name then return sent[i] end end end
local function clear() sent = {}; http = {} end
local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; realprint("FAIL: " .. label) end end

-- 1. no cops
INV[1] = {id_card_f = 1}
fire(1, "TOB_fh:startcheck", "B1")
check("no cops message", last("TOB_fh:outcome").args[2] == L("no_cops"))
-- 2. start ok
COPS = 4; clear()
fire(1, "TOB_fh:startcheck", "B1")
check("heist started", last("TOB_fh:outcome").args[1] == true and TOB.Banks.B1.onaction)
check("card used", INV[1].id_card_f == 0)
check("police alerted", last("TOB_fh:policenotify") ~= nil)
check("start logged to discord", #http == 1)
-- 3. busy
INV[2] = {id_card_f = 1}
fire(2, "TOB_fh:startcheck", "B1")
check("busy message", last("TOB_fh:outcome").args[2] == L("busy"))
-- 4. cash without looting is blocked and flagged
clear()
fire(3, "TOB_fh:rewardCash")
check("no money without loot", MONEY[3] == nil)
check("flag logged", #http == 1)
fire(3, "TOB_fh:rewardCash")
check("flag rate limited", #http == 1)
-- 5. loot: 3 piles paid, too-fast pile blocked, re-loot ignored
fire(2, "TOB_fh:lootup", "B1", "Loot1")
check("lootup broadcast", last("TOB_fh:lootup_c") ~= nil)
for i = 1, 3 do now = now + 400; fire(2, "TOB_fh:rewardCash") end
local paid = MONEY[2]
check("3 piles paid", paid ~= nil and paid >= 3 * TOB.mincash and paid <= 3 * TOB.maxcash)
now = now + 100; fire(2, "TOB_fh:rewardCash")
check("too fast blocked", MONEY[2] == paid)
clear(); fire(3, "TOB_fh:lootup", "B1", "Loot1")
check("trolley can't be looted twice", last("TOB_fh:lootup_c") == nil)
-- MaxPiles cap
TOB.MaxPiles = 5
for i = 1, 5 do now = now + 400; fire(2, "TOB_fh:rewardCash") end
local capped = MONEY[2]
now = now + 400; fire(2, "TOB_fh:rewardCash")
check("MaxPiles cap", MONEY[2] == capped)
-- grab window
now = now + 60000; local before = MONEY[2]; TOB.MaxPiles = 60
fire(2, "TOB_fh:rewardCash")
check("grab window closes", MONEY[2] == before)
-- 6. doors
clear(); fire(3, "TOB_fh:toggleDoor", "B1", false)
check("stranger can't use gate", last("TOB_fh:toggleDoor") == nil)
POLICE[3] = true; fire(3, "TOB_fh:toggleDoor", "B1", false)
check("police can use gate", last("TOB_fh:toggleDoor") ~= nil)
POLICE[3] = nil
-- vault item
TOB.VaultItem = "thermite"; clear()
fire(1, "TOB_fh:toggleVault", "B1", false)
check("vault blocked before item", last("TOB_fh:toggleVault") == nil)
fire(1, "TOB_fh:useVaultItem", "B1")
check("no item -> false", last("TOB_fh:vaultItemResult").args[2] == false)
INV[1].thermite = 1
fire(1, "TOB_fh:useVaultItem", "B1")
check("item -> true", last("TOB_fh:vaultItemResult").args[2] == true and INV[1].thermite == 0)
fire(1, "TOB_fh:toggleVault", "B1", false)
check("vault opens after item", last("TOB_fh:toggleVault") ~= nil)
TOB.VaultItem = ""
-- non-owner can't end the heist
fire(2, "TOB_fh:setCooldown", "B1")
check("stranger can't end heist", TOB.Banks.B1.onaction)
-- 7. owner ends it; payouts logged; cooldown
clear(); fire(1, "TOB_fh:setCooldown", "B1", "hack_failed")
check("heist ended", not TOB.Banks.B1.onaction and TOB.Banks.B1.lastrobbed > 0)
check("end logged", #http == 1)
local endlog = printed[#printed]
check("end log has reason and payout", endlog:find("hacking minigame") and endlog:find("Player2"))
INV[1].id_card_f = 1
fire(1, "TOB_fh:startcheck", "B1")
check("cooldown message", last("TOB_fh:outcome").args[2]:find(L("cooldown", ""):sub(1, 20), 1, true))
-- 8. admin reset clears cooldown
clear(); commands[SV.ResetCommand](0, {})
check("reset clears cooldown", TOB.Banks.B1.lastrobbed == 0)
check("reset tells clients", last("TOB_fh:forceReset") ~= nil)
fire(1, "TOB_fh:startcheck", "B1")
check("can start after reset", last("TOB_fh:outcome").args[1] == true)
-- 9. robber disconnects
clear(); fire(1, "playerDropped")
check("drop ends heist", not TOB.Banks.B1.onaction and last("TOB_fh:toggleVault").args[2] == true)
-- 10. item rewards
TOB.RewardItem = "markedbills"; TOB.RewardItemCount = 1
INV[2].id_card_f = 1; TOB.Banks.B1.lastrobbed = 0
fire(2, "TOB_fh:startcheck", "B1"); fire(2, "TOB_fh:lootup", "B1", "Loot2")
now = now + 400; fire(2, "TOB_fh:rewardCash"); now = now + 400; fire(2, "TOB_fh:rewardCash")
check("item reward", ITEMS[2] == 2)
TOB.RewardItem = ""
-- 11. distance check (OneSync)
PEDS = {[3] = 33}; POS = {[33] = vector3(0, 0, 0.5)}
INV[3] = {id_card_f = 1}; TOB.Banks.B1.onaction = false; clear()
fire(3, "TOB_fh:startcheck", "B1")
check("far start blocked", last("TOB_fh:outcome") == nil)
PEDS = nil
-- 12. update check
threads[#threads](); http[#http].cb(200, "v9.9.9")
check("update available printed", printed[#printed]:find("9.9.9 is available"))
http[#http].cb(200, "v1.4.1")
check("up to date printed", printed[#printed]:find("up to date"))
-- 13. getBanks callback
local got; callbacks["TOB_fh:getBanks"](1, function(b, d) got = d end)
check("doors built from config", got.B1[1].h == 42.639282226562 and got.B1[2].loc.y > 6475)

-- 14. disabled bank is removed
check("disabled bank removed", TOB.Banks.F6 == nil and got.F6 == nil and got.F1 ~= nil)
-- reset all state for the new rules
commands[SV.ResetCommand](0, {})
for _, b in pairs(TOB.Banks) do b.lastrobbed = 0 end
-- 15. minimum crew (player 1 near, players 2 and 3 far)
local B1 = TOB.Banks.B1.doors.startloc
PEDS = {[1] = 11, [2] = 22, [3] = 33}
POS = {[11] = vector3(B1.x, B1.y, B1.z), [22] = vector3(0, 0, 1), [33] = vector3(0, 0, 1)}
TOB.MinCrew = 2; INV[1] = {id_card_f = 1}; clear()
fire(1, "TOB_fh:startcheck", "B1")
check("crew too small", last("TOB_fh:outcome").args[2] == L("need_crew", 2))
POS[22] = vector3(B1.x + 3, B1.y, B1.z); clear()
fire(1, "TOB_fh:startcheck", "B1")
check("crew big enough", last("TOB_fh:outcome").args[1] == true)
TOB.MinCrew = 1
-- 16. one heist at a time
TOB.OneAtATime = true
local F1 = TOB.Banks.F1.doors.startloc
POS[33] = vector3(F1.x, F1.y, F1.z); INV[3] = {id_card_f = 1}; clear()
fire(3, "TOB_fh:startcheck", "F1")
check("one at a time", last("TOB_fh:outcome").args[2] == L("global_busy"))
TOB.OneAtATime = false
-- 17. inner gate (Fleeca): robber can't open it before hacking, can after
POS[11] = vector3(F1.x, F1.y, F1.z); INV[1].id_card_f = 1; TOB.Banks.F1.lastrobbed = 0; clear()
fire(1, "TOB_fh:startcheck", "F1")
check("fleeca heist started", last("TOB_fh:outcome").args[1] == true)
clear(); fire(1, "TOB_fh:toggleDoor", "F1", false)
check("gate blocked before hack", last("TOB_fh:toggleDoor") == nil)
local sec = TOB.Banks.F1.doors.secondloc
POS[11] = vector3(sec.x, sec.y, sec.z)
TOB.GateItem = "secure_card"
fire(1, "TOB_fh:useGate", "F1")
check("gate needs item", last("TOB_fh:gateResult").args[2] == false)
INV[1].secure_card = 1
fire(1, "TOB_fh:useGate", "F1")
check("gate hacked with item", last("TOB_fh:gateResult").args[2] == true and INV[1].secure_card == 0)
fire(1, "TOB_fh:toggleDoor", "F1", false)
check("gate opens after hack", last("TOB_fh:toggleDoor").args[2] == false)
TOB.GateItem = ""
-- 18. global cooldown after a heist ends
TOB.GlobalCooldown = 300
fire(1, "TOB_fh:setCooldown", "F1")
fire(2, "TOB_fh:setCooldown", "B1")
INV[2] = {id_card_f = 1}; TOB.Banks.F2.lastrobbed = 0
local F2 = TOB.Banks.F2.doors.startloc; POS[22] = vector3(F2.x, F2.y, F2.z); clear()
fire(2, "TOB_fh:startcheck", "F2")
check("global cooldown", last("TOB_fh:outcome").args[2]:find(L("global_cooldown", ""):sub(1, 15), 1, true) ~= nil)
TOB.GlobalCooldown = 0
-- 19. restart protection
handlers["txAdmin:events:scheduledRestart"]({secondsRemaining = 1800})
clear(); fire(2, "TOB_fh:startcheck", "F2")
check("30 min warning doesn't block", last("TOB_fh:outcome").args[1] == true)
fire(2, "TOB_fh:setCooldown", "F2"); TOB.Banks.F2.lastrobbed = 0; INV[2].id_card_f = 1
handlers["txAdmin:events:scheduledRestart"]({secondsRemaining = 900})
clear(); fire(2, "TOB_fh:startcheck", "F2")
check("15 min warning blocks", last("TOB_fh:outcome").args[2] == L("restart_soon"))
handlers["txAdmin:events:scheduledRestartSkipped"]({})
clear(); fire(2, "TOB_fh:startcheck", "F2")
check("skipped restart unblocks", last("TOB_fh:outcome").args[1] == true)
PEDS = nil


-- 20. config check
check("broken bank skipped", TOB.Banks.BROKEN == nil and got.BROKEN == nil)
check("mincash/maxcash swapped", TOB.mincash == 3000 and TOB.maxcash == 6500)
local warned = false
for _, line in ipairs(printed) do if line:find("Bank BROKEN is missing") then warned = true end end
check("broken bank warning printed", warned)
-- 21. Fleeca inner gate is locked outside heists, and relocked afterwards
check("fleeca gate locked by default", got.F1[1].locked == true and got.B1[1].locked == false)
commands[SV.ResetCommand](0, {})
check("admin reset keeps fleeca gate locked", got.F1[1].locked == true and got.B1[1].locked == false)
-- 22. cash only paid at the trolley
for _, b in pairs(TOB.Banks) do b.lastrobbed = 0 end
local P = TOB.Banks.B1.doors.startloc
PEDS = {[1] = 11, [2] = 22}; POS = {[11] = vector3(P.x, P.y, P.z), [22] = vector3(0, 0, 1)}
INV[1] = {id_card_f = 1}; clear()
fire(1, "TOB_fh:startcheck", "B1")
local T1 = TOB.Banks.B1.trolley1
POS[22] = vector3(T1.x, T1.y, T1.z)
fire(2, "TOB_fh:lootup", "B1", "Loot1")
local before = MONEY[2] or 0
POS[22] = vector3(0, 0, 1)
now = now + 400; fire(2, "TOB_fh:rewardCash")
check("no cash away from trolley", (MONEY[2] or 0) == before)
POS[22] = vector3(T1.x, T1.y, T1.z)
now = now + 400; fire(2, "TOB_fh:rewardCash")
check("cash at trolley", (MONEY[2] or 0) > before)
-- 23. loot phase goes to everyone
clear(); fire(1, "TOB_fh:startLoot", nil, "B1")
check("loot phase sent to everyone", last("TOB_fh:startLoot_c").target == -1)
-- 24. vault angle only accepted right after a real vault move
now = now + 30000 -- let the admin reset's vault move from test 21 expire
local V = TOB.Banks.B1.vault.loc
POS[22] = vector3(V.x, V.y, V.z); clear()
fire(2, "TOB_fh:updateVaultState", "B1", 45.0)
check("vault angle ignored without a vault move", last("TOB_fh:vaultState") == nil)
POS[11] = vector3(V.x, V.y, V.z)
fire(1, "TOB_fh:toggleVault", "B1", false)
fire(2, "TOB_fh:updateVaultState", "B1", 45.0)
check("vault angle accepted after a move", last("TOB_fh:vaultState").args[2] == 45.0)
clear(); fire(2, "TOB_fh:updateVaultState", "B1", 99.0)
check("only the first report counts", last("TOB_fh:vaultState") == nil)
now = now + 60000; fire(1, "TOB_fh:toggleVault", "B1", true); now = now + 30000; clear()
fire(2, "TOB_fh:updateVaultState", "B1", 10.0)
check("late report ignored", last("TOB_fh:vaultState") == nil)
-- 25. stuck heists end automatically
realos = os.time
local fake = realos() + 100000
os.time = function() return fake end
waits, LOOP_LIMIT = 0, 1
local safety
for _, fn in ipairs(threads) do
    local okRun = pcall(fn)
    if not TOB.Banks.B1.onaction then safety = true break end
end
LOOP_LIMIT = nil; os.time = realos
check("stuck heist ended by safety net", safety == true and last("TOB_fh:forceReset") ~= nil)
PEDS = nil

-- 26. special trolley pays the multiplier, and the loot counter and totals are sent
commands[SV.ResetCommand](0, {})
for _, b in pairs(TOB.Banks) do b.lastrobbed = 0 end
TOB.SpecialTrolleyChance = 100
local P2 = TOB.Banks.B1.doors.startloc
PEDS = {[1] = 11, [2] = 22}; POS = {[11] = vector3(P2.x, P2.y, P2.z), [22] = vector3(P2.x, P2.y, P2.z)}
INV[1] = {id_card_f = 1}; clear()
fire(1, "TOB_fh:startcheck", "B1")
local outcome = last("TOB_fh:outcome")
local special = outcome.args[3]
local slot, kind = next(special or {})
check("special trolley picked and sent to the robber", slot ~= nil and TOB.SpecialTrolleys[kind] ~= nil)
check("alarm switched on for Paleto", last("TOB_fh:alarm") and last("TOB_fh:alarm").args[2] == true)
fire(1, "TOB_fh:startLoot", nil, "B1")
check("loot phase carries the special trolley", last("TOB_fh:startLoot_c").args[1].special[slot] == kind)
local tr = TOB.Banks.B1[slot]
POS[22] = vector3(tr.x, tr.y, tr.z)
fire(2, "TOB_fh:lootup", "B1", "Loot" .. slot:sub(-1))
TOB.mincash, TOB.maxcash = 1000, 1000
local m0 = MONEY[2] or 0; clear()
now = now + 400; fire(2, "TOB_fh:rewardCash")
check("special trolley multiplier", (MONEY[2] or 0) - m0 == math.floor(1000 * TOB.SpecialTrolleys[kind].multiplier))
check("loot counter event", last("TOB_fh:grabbed") and last("TOB_fh:grabbed").args[1] == math.floor(1000 * TOB.SpecialTrolleys[kind].multiplier))
TOB.mincash, TOB.maxcash = 3000, 6500
TOB.SpecialTrolleyChance = 0
-- 27. deposit boxes
local box = TOB.Banks.B1.boxes[1]
POS[22] = vector3(box.x, box.y, box.z); clear()
fire(2, "TOB_fh:drillBox", "B1", 1)
check("box can't be drilled while the vault is closed", last("TOB_fh:drillResult") == nil)
fire(1, "TOB_fh:toggleVault", "B1", false)
TOB.DrillItem = "drill"; clear()
fire(2, "TOB_fh:drillBox", "B1", 1)
check("box needs a drill", last("TOB_fh:drillResult").args[3] == false and last("TOB_fh:drillResult").args[4] == "no_drill")
INV[2].drill = 1; clear()
fire(2, "TOB_fh:drillBox", "B1", 1)
check("drilling starts", last("TOB_fh:drillResult").args[3] == true and last("TOB_fh:boxState").args[3] == "busy")
check("drill is not used up", INV[2].drill == 1)
INV[3] = {drill = 1}; PEDS[3] = 33; POS[33] = vector3(box.x, box.y, box.z); clear()
fire(3, "TOB_fh:drillBox", "B1", 1)
check("second player can't drill the same box", last("TOB_fh:drillResult").args[4] == "box_busy")
local m1 = MONEY[2] or 0; clear()
fire(2, "TOB_fh:drillDone", "B1", 1, true)
check("finishing too fast is blocked", last("TOB_fh:boxReward") == nil and (MONEY[2] or 0) == m1)
TOB.DrillRewards = {{type = "money", min = 5000, max = 5000, chance = 1}}
now = now + TOB.DrillTime; clear()
fire(2, "TOB_fh:drillDone", "B1", 1, true)
check("box pays out after drilling", (MONEY[2] or 0) - m1 == 5000 and last("TOB_fh:boxState").args[3] == "opened")
clear(); fire(2, "TOB_fh:drillBox", "B1", 1)
check("opened box can't be drilled again", last("TOB_fh:drillResult") == nil)
-- 28. heist end: totals, alarm off, boxes reset
clear(); fire(1, "TOB_fh:setCooldown", "B1")
local totals = 0
for _, e in ipairs(sent) do if e.name == "TOB_fh:heistTotal" then totals = totals + 1 end end
check("everyone paid gets their total", totals >= 1)
check("alarm switched off", last("TOB_fh:alarm") and last("TOB_fh:alarm").args[2] == false)
check("boxes reset", last("TOB_fh:boxesReset") ~= nil)
PEDS = nil

realprint(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
