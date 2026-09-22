-- Automated tests for the admin tools (server/tools.lua, server/healthcheck.lua, locales/tools.lua)
-- and the bank sounds (client/sounds.lua). They run the real files outside FiveM, with fake natives.
-- Run from the repo root:  lua5.4 tests/tools_test.lua

local pass, fail = 0, 0
local function check(label, cond) if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end end

local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end

-- Fake server
local threads, commands, handlers, clientEvents, posts, printed = {}, {}, {}, {}, {}, {}
Citizen = {CreateThread = function(fn) threads[#threads + 1] = fn end, Wait = function() end}
function RegisterCommand(name, fn, restricted) commands[name] = {fn = fn, restricted = restricted} end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, target, ...) clientEvents[#clientEvents + 1] = {name = name, target = target, args = {...}} end
function PerformHttpRequest(url, cb, method, body) posts[#posts + 1] = {url = url, body = body} end
json = {encode = function(t) return t.embeds[1].description end}
function GetPlayerName(src) return "Admin" .. src end
-- Log from server/util.lua (tested in tests/server_test.lua): console line + Discord post
function Log(title, description)
    print("[tobs_bankrobbery] " .. title .. ": " .. description)
    if SV.Webhook ~= nil and SV.Webhook ~= "" then PerformHttpRequest(SV.Webhook, nil, "POST", json.encode({embeds = {{description = description}}})) end
end
local realPrint = print
print = function(s) printed[#printed + 1] = s end

local running = {ox_inventory = true, ox_lib = true, ox_target = true}
function GetResourceState(r) return running[r] and "started" or "missing" end
local convars = {onesync = "on"}
local convarInts = {sv_enforceGameBuild = 3095}
function GetConvar(k, d) return convars[k] or d end
function GetConvarInt(k, d) return convarInts[k] or d end
local aces = {["command.tobreset"] = true, ["command.tobpause"] = true, ["command.tobtest"] = true, ["command.tobcheck"] = true}
function IsPrincipalAceAllowed(principal, object) return principal == "group.admin" and aces[object] == true end

local oxItems = {id_card_f = true, drill = true, goldbar = true}
local qbItems = {id_card_f = {}, drill = {}}
local esxItems = {}
local brokenExports = false
exports = setmetatable({}, {__index = function(_, res)
    if brokenExports then error("export failed") end
    if res == "ox_inventory" then return {Items = function(_, name) return oxItems[name] and {} or nil end} end
    if res == "qb-core" then return {GetCoreObject = function() return {Shared = {Items = qbItems}} end} end
    if res == "es_extended" then return {getSharedObject = function() return {GetItems = function() return esxItems end} end} end
end})

SV = {Webhook = "", ResetCommand = "tobreset"}
TOB = {Locale = "en", DepositBoxes = true, DrillItem = "drill", VaultItem = "", GateItem = "", RewardItem = "",
       DrillRewards = {{type = "money", min = 1, max = 2}}, SpecialTrolleys = {}, SpecialTrolleyChance = 0,
       HackMinigame = "ox_lib", DrillMinigame = {"easy"}, Target = "auto", Prompts = "auto", Dispatch = "auto",
       Banks = {B1 = {boxes = {vector3(10, 0, 0), vector3(12, 0, 0)}, vault = {loc = vector3(5, 0, 0)}}}}
Locales = {en = {drilling = "Drilling..."}, da = {}}
function L(key) return Locales.en[key] or key end
Framework = "qbox"
function BlackMoneyItem() return "black_money" end

dofile("locales/tools.lua")
dofile("client/minigames.lua") -- shared script: MinigameGame for the health check
dofile("server/tools.lua")
dofile("server/healthcheck.lua")
for _, t in ipairs(threads) do t() end -- the resource has loaded: settings and commands

local function run(cmd, src, ...) commands[cmd].fn(src, {...}) end
local function lastChat() local e = clientEvents[#clientEvents] return e and e.args[1].args[2] end

-- Commands
check("commands are registered and admin-only", commands.tobpause.restricted and commands.tobtest.restricted and commands.tobcheck.restricted)
check("settings get defaults", SV.PauseCommand == "tobpause" and SV.TestModePayouts == false and SV.ShowPoliceCount == false and SV.BankSoundRange == 40.0)

-- Heist switch
check("heists aren't paused at start", HeistsPaused() == false)
run("tobpause", 3, "server", "event")
local paused, reason = HeistsPaused()
check("/tobpause with a reason pauses heists", paused == true and reason == "server event")
check("the refusal gives the reason", PauseRefusal() == "Bank heists are paused: server event")
check("the admin is told", lastChat() == LX("paused"))
check("it's logged in the console", printed[#printed]:find("Admin3 paused bank heists: server event") ~= nil)
run("tobpause", 0, "off")
check("/tobpause off allows heists again", HeistsPaused() == false)
SV.Webhook = "https://discord.com/api/webhooks/1/x"
run("tobpause", 0)
check("without a reason: the plain refusal", PauseRefusal() == LX("refuse_paused"))
check("with a webhook: posted to Discord", #posts == 1 and posts[1].body:find("console paused bank heists") ~= nil)
run("tobpause", 0, "off")
SV.Webhook = ""

-- Test mode
run("tobtest", 0)
check("test mode from the console is refused", printed[#printed] == LX("test_players_only"))
run("tobtest", 7)
check("/tobtest turns test mode on for that admin", IsTester(7) and not IsTester(8))
check("... and says heists pay nothing", lastChat() == LX("test_on_nopay"))
check("a tester's heist is a test heist", StartTestHeist("B1", 7) == true and IsTestHeist("B1"))
check("test heists pay nothing by default", TestPayoutBlocked("B1") == true)
SV.TestModePayouts = true
check("SV.TestModePayouts = true lets them pay", TestPayoutBlocked("B1") == false)
SV.TestModePayouts = false
check("ending it says it was a test heist (no cooldown)", EndTestHeist("B1") == true and not IsTestHeist("B1"))
check("... only once", EndTestHeist("B1") == false)
check("other players' heists are normal", StartTestHeist("B1", 8) == false and not IsTestHeist("B1") and not TestPayoutBlocked("B1"))
StartTestHeist("B1", 7)
check("a normal heist at the same bank clears the old test flag", StartTestHeist("B1", 8) == false and not IsTestHeist("B1"))
run("tobtest", 7)
check("/tobtest again turns it off", not IsTester(7) and lastChat() == LX("test_off"))
run("tobtest", 7)
source = 7
handlers.playerDropped()
check("leaving the server turns test mode off", not IsTester(7))

-- Clearer refusals
check("police count hidden by default", PoliceRefusal(4, 1) == "Not enough police in the city.")
SV.ShowPoliceCount = true
check("SV.ShowPoliceCount shows the numbers", PoliceRefusal(4, 1) == "Not enough police: 4 needed, 1 on duty.")
SV.ShowPoliceCount = false
check("bank cooldown with the time left", CooldownRefusal(75) == "This bank was robbed recently. Try again in 1 min 15 s.")
check("global cooldown", CooldownRefusal(30, true) == "Banks are on high alert after the last heist. Try again in 30 s.")
check("times: whole minutes, seconds, rounding, never negative",
      FormatDuration(120) == "2 min" and FormatDuration(59.6) == "1 min" and FormatDuration(-5) == "0 s")
check("other reasons", RefusalText("crew", 2, 1) == "You need 2 robbers at the panel (1 here)." and RefusalText("one_at_a_time") == LX("refuse_one_at_a_time"))
TOB.Locale = "da"
check("in the server's language", CooldownRefusal(60) == "Banken blev røvet for nylig. Prøv igen om 1 min.")
TOB.Locale = "xx"
check("unknown language: English", RefusalText("busy") == "This bank is already being robbed.")
TOB.Locale = "en"
check("unknown key: falls back to L()", LX("drilling") == "Drilling...")
for _, lang in ipairs({"da", "de", "sv", "no", "nl"}) do
    local missing = {}
    for key in pairs(ToolLocales.en) do if ToolLocales[lang][key] == nil then missing[#missing + 1] = key end end
    check(lang .. " has every text (missing: " .. table.concat(missing, ", ") .. ")", #missing == 0)
end

-- Bank sounds (server side)
clientEvents = {}
BankSound("B1", "drill_on", 2, 5)
local e = clientEvents[1]
check("BankSound goes to every player with the range", e.name == "tobs_bankrobbery:bankSound" and e.target == -1
      and e.args[1] == "B1" and e.args[2] == "drill_on" and e.args[3] == 2 and e.args[4] == 5 and e.args[5] == 40.0)

-- Health check
local problems, notes = HealthCheck()
check("a good setup: no problems or notes", #problems == 0 and #notes == 0)
printed = {}
threads[#threads]() -- the start check (the Wait is instant here)
check("the start check prints 'all good'", printed[#printed]:find("all good") ~= nil)

local function has(list, text) for _, l in ipairs(list) do if l:find(text, 1, true) then return true end end return false end
oxItems.drill = nil
problems = HealthCheck()
check("a missing item is a problem", has(problems, "Item 'drill' (TOB.DrillItem)"))
oxItems.drill = true
TOB.DrillRewards[2] = {type = "item", name = "rolex"}
check("reward items are checked too", has(HealthCheck(), "Item 'rolex' (TOB.DrillRewards)"))
TOB.DrillRewards[2] = nil
TOB.DepositBoxes = false
oxItems.drill = nil
check("no deposit boxes: the drill item isn't needed", #HealthCheck() == 0)
TOB.DepositBoxes, oxItems.drill = true, true

running.ox_inventory, Framework = nil, "qb"
check("QBCore without ox_inventory: qb-core's item list", #HealthCheck() == 0)
qbItems.drill = nil
check("... and a missing item there", has(HealthCheck(), "Item 'drill'"))
qbItems.drill = {}
Framework = "esx"
problems, notes = HealthCheck()
check("ESX before its items load: noted, not a problem", #problems == 0 and has(notes, "Couldn't check these items"))
esxItems = {id_card_f = {}, drill = {}}
check("ESX with items loaded", #HealthCheck() == 0)
Framework = "vrp"
problems, notes = HealthCheck()
check("vRP: items can't be checked, so noted", #problems == 0 and has(notes, "id_card_f, drill"))
Framework, brokenExports = "esx", true
problems, notes = HealthCheck()
check("an erroring export doesn't break the check", #problems == 0 and has(notes, "Couldn't check"))
brokenExports, running.ox_inventory, Framework = false, true, "qbox"

TOB.Target = "ox_target"
running.ox_target = nil
check("TOB.Target = ox_target without ox_target", has(HealthCheck(), "TOB.Target = \"ox_target\", but ox_target isn't running"))
TOB.Target, running.ox_target = "auto", true
running.ox_lib = nil
problems, notes = HealthCheck()
check("no ox_lib: both skill checks noted", #problems == 0 and has(notes, "hack's ox_lib") and has(notes, "drill's ox_lib"))
running.ox_lib = true
TOB.Banks.B1.minigames = {hack = "thermite"}
check("a bank using tobs_minigames without it running", has(select(2, HealthCheck()), "Minigames for B1 need tobs_minigames"))
running.tobs_minigames = true
check("... fine when it runs", not has(select(2, HealthCheck()), "tobs_minigames"))
running.tobs_minigames = nil
TOB.Banks.B1.minigames = nil

Framework = nil
check("no framework", has(HealthCheck(), "No framework found"))
Framework = "qbox"
convars.onesync = "off"
check("OneSync off", has(HealthCheck(), "OneSync is off"))
convars.onesync = "on"
TOB.Locale = "fr"
check("a missing language", has(HealthCheck(), "TOB.Locale = \"fr\""))
TOB.Locale = "en"
SV.Webhook = "discord.gg/abc"
check("a webhook that isn't a webhook", has(HealthCheck(), "SV.Webhook doesn't look like"))
SV.Webhook = "https://discordapp.com/api/webhooks/1/x"
check("old discordapp.com webhooks are fine", #HealthCheck() == 0)
SV.Webhook = ""
TOB.SpecialTrolleyChance, convarInts.sv_enforceGameBuild = 25, nil
check("special trolleys on an old game build", has(select(2, HealthCheck()), "sv_enforceGameBuild 2060"))
TOB.SpecialTrolleyChance = 0
aces["command.tobpause"], aces["command.tobreset"] = nil, nil
check("admins missing command aces", has(select(2, HealthCheck()), "/tobreset, /tobpause"))
aces["command.tobpause"], aces["command.tobreset"] = true, true
TOB.black, Framework = true, "qb"
running.ox_inventory = nil
check("dirty money item checked outside ESX", has(HealthCheck(), "Item 'black_money'"))
Framework = "esx"
check("... but not on ESX (it's an account)", not has(HealthCheck(), "black_money"))
TOB.black, running.ox_inventory, Framework = false, true, "qbox"

clientEvents, printed = {}, {}
oxItems.drill = nil
run("tobcheck", 4)
check("/tobcheck reports in the console and tells the admin", has(printed, "problem:") and lastChat():find("1 problem") ~= nil)
oxItems.drill = true

-- Bank sounds (client side)
local me, pos = 5, vector3(0, 0, 0)
local sounds, nextId, timeouts = {}, 100, {}
local clientHandlers = {}
function RegisterNetEvent() end
AddEventHandler = function(name, fn) clientHandlers[name] = fn end
function PlayerPedId() return 1 end
function GetEntityCoords() return pos end
function PlayerId() return 0 end
function GetPlayerServerId() return me end
function GetSoundId() nextId = nextId + 1 return nextId end
function PlaySoundFromCoord(id, name, x, y, z, set) sounds[#sounds + 1] = {"play", id, name, set, x} end
function StopSound(id) sounds[#sounds + 1] = {"stop", id} end
function ReleaseSoundId(id) sounds[#sounds + 1] = {"release", id} end
Citizen.SetTimeout = function(ms, fn) timeouts[#timeouts + 1] = {ms = ms, fn = fn} end
dofile("client/sounds.lua")
local sound = clientHandlers["tobs_bankrobbery:bankSound"]

sound("B1", "drill_on", 1, 9, 40.0)
check("a crew member near the box hears the drill", sounds[1][1] == "play" and sounds[1][3] == "Drill" and sounds[1][4] == "DLC_HEIST_FLEECA_SOUNDSET" and sounds[1][5] == 10)
sound("B1", "drill_off", 1, 9, 40.0)
check("the drill stops and the sound is released", sounds[2][1] == "stop" and sounds[3][1] == "release" and sounds[2][2] == sounds[1][2])
sounds = {}
sound("B1", "drill_on", 1, 5, 40.0)
check("the driller doesn't hear it twice", #sounds == 0)
pos = vector3(100, 0, 0)
sound("B1", "drill_on", 1, 9, 40.0)
check("players outside the range don't hear it", #sounds == 0)
pos, timeouts = vector3(0, 0, 0), {}
sound("B1", "drill_on", 2, 9, 40.0)
local first = sounds[#sounds][2]
sound("B1", "drill_on", 2, 9, 40.0)
check("a second start at the same box replaces the first", sounds[#sounds - 2][1] == "stop" and sounds[#sounds - 2][2] == first)
timeouts[1].fn()
check("the old safety timer doesn't stop the new sound", sounds[#sounds][1] == "play")
timeouts[2].fn()
check("the safety timer stops a sound whose stop never came", sounds[#sounds][1] == "release" and timeouts[2].ms == 120000)
sounds = {}
sound("B1", "vault", nil, 0, 40.0)
check("the vault door sound", sounds[1] and sounds[1][3] == "vault_unlock" and sounds[1][4] == "dlc_heist_fleeca_bank_door_sounds" and sounds[1][5] == 5)
sound("NOPE", "vault", nil, 0, 40.0)
sound("B1", "drill_off", 7, 0, 40.0)
check("unknown banks and boxes are ignored", #sounds == 1)

print = realPrint
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
