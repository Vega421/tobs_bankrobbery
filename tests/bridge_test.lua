-- Runs every bridge against a fake framework and a fake database.  lua5.4 tests/bridge_test.lua
package.path = "tests/?.lua;" .. package.path
local F = dofile("tests/fakes.lua")

local pass, fail = 0, 0
local function check(label, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. label .. "\n") end
end

-- The API every bridge must provide ----------------------------------------
local SERVER_API = {"GetPlayer", "GetIdentifier", "GetJob", "IsPolice", "GetPlayersByJob", "CountPolice",
                    "GetItemCount", "HasItem", "RemoveItem", "AddItem", "CanCarry",
                    "AddMoney", "RemoveMoney", "GetMoney", "Notify", "RegisterCallback",
                    "GetPerson", "SearchPeople", "GetVehicles", "GetVehicleByPlate",
                    "GetLicences", "SetLicence", "GetPhoneNumber"}
local CLIENT_API = {"Init", "GetJob", "IsPolice", "GetIdentifier", "Notify", "TriggerCallback"}

-- Fake frameworks -----------------------------------------------------------

local function FakeOxInventory(counts, full)
    return {
        GetItemCount = function(_, src, item) return counts[item] or 0 end,
        RemoveItem = function(_, src, item, n) counts[item] = (counts[item] or 0) - n; return true end,
        AddItem = function(_, src, item, n, meta) F.added = {item = item, n = n, meta = meta}; return not full end,
        CanCarryItem = function() return not full end,
    }
end

local function FakeQbox(job, money)
    return {
        GetPlayer = function(_, src)
            if F.players[src] == nil then return nil end
            return {PlayerData = {citizenid = "ABC12345", money = money or {cash = 100, bank = 500},
                                  charinfo = {firstname = "John", lastname = "Doe", birthdate = "1990-01-01", phone = "555-0100"},
                                  job = job}}
        end,
        AddMoney = function(_, src, account, amount) F.money = {account = account, amount = amount}; return true end,
        RemoveMoney = function() return true end,
    }
end

-- Detection -----------------------------------------------------------------

F.players = {}
F.state = {qbx_core = "started", ["qb-core"] = "started"}
exports.qbx_core = FakeQbox({name = "police", onduty = true})
Load("qbox")
check("qbx_core is picked before qb-core (qbx_core provides qb-core)", Framework == "qbox")

F.state = {es_extended = "started"}
exports["es_extended"] = {getSharedObject = function() return {GetPlayerFromId = function() return nil end} end}
Load("esx")
check("es_extended is found", Framework == "esx")

F.state = {}
Load("none")
check("no framework: Framework is nil and nothing crashes", Framework == nil)

F.state = {qbx_core = "started"}
Load("qbox", "server", {Framework = "esx"})
check("BridgeConfig.Framework overrides the detection", Framework == "esx")

-- Shared helpers ------------------------------------------------------------

F.state = {qbx_core = "started"}
Load("qbox", "server", {PoliceJobs = {"police", "sheriff"}, PoliceOnDuty = true})
check("a list of police jobs", IsPoliceJobName("sheriff") and not IsPoliceJobName("ambulance"))
check("on duty is required when PoliceOnDuty is on", IsPoliceJobData({name = "police", onduty = true})
      and not IsPoliceJobData({name = "police", onduty = false}))
Load("qbox", "server", {PoliceOnDuty = false})
check("PoliceOnDuty = false counts police off duty too", IsPoliceJobData({name = "police", onduty = false}))
check("black money item per framework", BlackMoneyItem() == "black_money")

-- Qbox ----------------------------------------------------------------------

F.state = {qbx_core = "started", ox_inventory = "started", oxmysql = "started"}
F.players = {[1] = true, [2] = true}
local counts = {lockpick = 3}
exports.ox_inventory = FakeOxInventory(counts)
exports.qbx_core = FakeQbox({name = "police", onduty = true})
local b = Load("qbox")
for _, name in ipairs(SERVER_API) do check("qbox has " .. name, type(b[name]) == "function") end
check("qbox: metadata items", b.Metadata == true and b.Inventory == "ox")
local player = b.GetPlayer(1)
check("qbox: the person shape", player.id == "ABC12345" and player.firstname == "John"
      and player.dob == "1990-01-01" and player.job.name == "police" and player.job.onduty == true)
check("qbox: a player who isn't loaded is nil", b.GetPlayer(9) == nil)
check("qbox: police counted", b.IsPolice(1) and b.CountPolice() == 2)
check("qbox: item count and HasItem", b.GetItemCount(1, "lockpick") == 3 and b.HasItem(1, "lockpick", 3)
      and not b.HasItem(1, "lockpick", 4))
check("qbox: AddItem passes the metadata", b.AddItem(1, "markedbills", 1, {worth = 5000}) == true
      and F.added.meta.worth == 5000)
b.AddMoney(1, 2500, "bank")
check("qbox: money goes to the right account", F.money.account == "bank" and F.money.amount == 2500)
b.AddMoney(1, 700, "black")
check("qbox: dirty money is paid as an item", F.added.item == "black_money" and F.added.n == 700)
check("qbox: GetMoney reads the account", b.GetMoney(1, "bank") == 500)

exports.qbx_core = FakeQbox({name = "police", onduty = false})
b = Load("qbox")
check("qbox: off-duty police don't count", not b.IsPolice(1) and b.CountPolice() == 0)

exports.ox_inventory = FakeOxInventory({}, true)   -- a full inventory
exports.qbx_core = FakeQbox({name = "police", onduty = true})
b = Load("qbox")
check("qbox: a full inventory returns false", b.AddItem(1, "gold", 1) == false and b.CanCarry(1, "gold", 1) == false)

-- Qbox / QBCore database ----------------------------------------------------

F.json = {}
F.rows = {
    ["FROM players WHERE citizenid"] = {{citizenid = "ABC12345",
        charinfo = {firstname = "John", lastname = "Doe", birthdate = "1990-01-01", phone = "555-0100"},
        job = {name = "police", grade = {level = 3}, onduty = true},
        metadata = {licences = {driver = true, weapon = false}}}},
    ["FROM players\n"] = {{citizenid = "ABC12345",
        charinfo = {firstname = "John", lastname = "Doe"}, job = {name = "police"}}},
    ["FROM player_vehicles WHERE citizenid"] = {{plate = "ABC 123", vehicle = "sultan", citizenid = "ABC12345", garage = "pillbox", state = 1}},
    ["FROM player_vehicles WHERE plate"] = {{plate = "ABC 123", vehicle = "sultan", citizenid = "ABC12345", garage = "pillbox", state = 1}},
}
b = Load("qbox")
local person = b.GetPerson("ABC12345")
check("qbox data: charinfo and job are unpacked", person.firstname == "John" and person.job.grade == 3)
check("qbox data: the query is by citizenid", F.queries[1].params[1] == "ABC12345")
local vehicles = b.GetVehicles("ABC12345")
check("qbox data: vehicles", #vehicles == 1 and vehicles[1].plate == "ABC 123"
      and vehicles[1].model == "sultan" and vehicles[1].stored == true)
local byPlate = b.GetVehicleByPlate("ABC 123")
check("qbox data: a plate gives the owner too", byPlate.person.firstname == "John")
check("qbox data: licences", b.GetLicences("ABC12345").driver == true)
b.SetLicence("ABC12345", "weapon", true)
check("qbox data: a licence is written back", F.encoded.licences.weapon == true)
check("qbox data: search returns a list", type(b.SearchPeople("Doe")) == "table")

-- QBCore --------------------------------------------------------------------

local function FakeQb(inventoryRunning)
    F.state = {["qb-core"] = "started", oxmysql = "started"}
    if inventoryRunning then F.state[inventoryRunning] = "started" end
    exports["qb-core"] = {GetCoreObject = function()
        return {Functions = {GetPlayer = function(src)
            if F.players[src] == nil then return nil end
            return {PlayerData = {citizenid = "QB1", money = {cash = 50}, charinfo = {firstname = "Jane", lastname = "Roe"},
                                  job = {name = "police", grade = {level = 1}, onduty = true}},
                    Functions = {
                        GetItemByName = function(item) return {amount = 7} end,
                        AddItem = function() F.oldAdd = true; return true end,
                        RemoveItem = function() return true end,
                        AddMoney = function(account, n) F.money = {account = account, amount = n}; return true end,
                        RemoveMoney = function() return true end,
                    }}
        end}}
    end}
end

FakeQb("ox_inventory")
exports.ox_inventory = FakeOxInventory({bandage = 2})
b = Load("qb")
for _, name in ipairs(SERVER_API) do check("qb has " .. name, type(b[name]) == "function") end
check("qb: ox_inventory is used when it runs", b.Inventory == "ox" and b.GetItemCount(1, "bandage") == 2)

FakeQb("qb-inventory")
exports["qb-inventory"] = {GetItemCount = function(_, src, item) return 5 end,
                           AddItem = function() return true end, RemoveItem = function() return true end,
                           CanAddItem = function() return true end}
b = Load("qb")
check("qb: qb-inventory when ox_inventory isn't running", b.Inventory == "qb" and b.GetItemCount(1, "bandage") == 5)

FakeQb(nil)
b = Load("qb")
check("qb: the old core functions when there's no inventory resource", b.Inventory == "core" and b.GetItemCount(1, "bandage") == 7)
check("qb: the old core has no carry check", b.CanCarry(1, "x", 1) == true)
check("qb: the person shape is the same as Qbox's", b.GetPlayer(1).firstname == "Jane" and b.GetPlayer(1).job.grade == 1)
b.AddMoney(1, 300, "bank")
check("qb: money", F.money.account == "bank" and F.money.amount == 300)
check("qb: the database side is shared with Qbox", type(b.GetPerson) == "function")

-- ESX -----------------------------------------------------------------------

local esxPlayer
local function FakeEsx(canCarry)
    F.state = {es_extended = "started", oxmysql = "started"}
    esxPlayer = {
        identifier = "char1:abc", job = {name = "police", label = "Police", grade = 2, grade_label = "Sergeant"},
        getInventoryItem = function(item) return {count = 4} end,
        addInventoryItem = function(item, n) F.added = {item = item, n = n} end,
        removeInventoryItem = function(item, n) F.removed = {item = item, n = n} end,
        canCarryItem = function() return canCarry ~= false end,
        addMoney = function(n) F.money = {account = "cash", amount = n} end,
        removeMoney = function(n) F.money = {account = "cash", amount = -n} end,
        addAccountMoney = function(account, n) F.money = {account = account, amount = n} end,
        removeAccountMoney = function(account, n) F.money = {account = account, amount = -n} end,
        getMoney = function() return 80 end,
        getAccount = function(name) return {money = name == "black_money" and 1200 or 900} end,
    }
    exports["es_extended"] = {getSharedObject = function()
        return {GetPlayerFromId = function(src) return F.players[src] and esxPlayer or nil end}
    end}
end

FakeEsx(true)
F.rows = {["FROM users WHERE identifier"] = {{identifier = "char1:abc", firstname = "Erik", lastname = "Svensson",
           dateofbirth = "1988-05-02", phone_number = "555-0199", sex = "m", job = "police", job_grade = 2}},
          ["FROM owned_vehicles WHERE owner"] = {{owner = "char1:abc", plate = "XYZ 789", vehicle = "<v>", stored = 1}},
          ["FROM user_licenses WHERE owner"] = {{type = "drive"}}}
F.json = {["<v>"] = {model = "blista"}}
b = Load("esx")
for _, name in ipairs(SERVER_API) do check("esx has " .. name, type(b[name]) == "function") end
check("esx: no item metadata", b.Metadata == false)
check("esx: the person shape is the same", b.GetPlayer(1).firstname == "Erik" and b.GetPlayer(1).job.grade == 2)
check("esx: police have no duty, so the job alone counts", b.IsPolice(1) and b.CountPolice() == 2)
check("esx: items", b.GetItemCount(1, "bread") == 4 and b.RemoveItem(1, "bread", 2) == true)
b.AddMoney(1, 900, "black")
check("esx: dirty money goes to the black_money account", F.money.account == "black_money" and F.money.amount == 900)
check("esx: GetMoney per account", b.GetMoney(1, "black") == 1200 and b.GetMoney(1, "bank") == 900 and b.GetMoney(1) == 80)
check("esx data: users row", b.GetPerson("char1:abc").lastname == "Svensson")
check("esx data: the vehicle JSON gives the model", b.GetVehicles("char1:abc")[1].model == "blista")
check("esx data: licences from user_licenses", b.GetLicences("char1:abc").drive == true)

FakeEsx(false)   -- pockets full
b = Load("esx")
check("esx: a full inventory returns false", b.AddItem(1, "gold", 1) == false and b.CanCarry(1, "gold", 1) == false)

-- The client side -----------------------------------------------------------

F.state = {qbx_core = "started"}
local clientJob = {name = "police", grade = {level = 4}, onduty = true}
exports.qbx_core = {GetPlayerData = function() return {citizenid = "ABC12345", job = clientJob} end,
                    Notify = function(_, msg) F.notified = msg end}
b = Load("qbox", "client")
for _, name in ipairs(CLIENT_API) do check("qbox client has " .. name, type(b[name]) == "function") end
b.Init(function() F.ready = true end)
check("qbox client: Init keeps running without hanging", RunThread(F.lastThread))
check("qbox client: Init waits for the player, then calls back", F.ready == true)
check("qbox client: the job is cached and read from the cache", b.GetJob().grade == 4 and b.IsPolice())
b.Notify("hello")
check("qbox client: notifications go to the framework", F.notified == "hello")

-- Without oxmysql -------------------------------------------------------------

F.state = {qbx_core = "started"}   -- oxmysql missing
exports.qbx_core = FakeQbox({name = "police", onduty = true})
b = Load("qbox")
F.state["oxmysql"] = "missing"
check("no oxmysql: queries answer nil instead of crashing", b.GetPerson("ABC12345") == nil)


-- ox_lib: notifications, progress bars and text prompts -----------------------

local function FakeOxLib()
    return {
        progressBar = function(_, opts) F.progress = opts; return true end,
        showTextUI = function(_, text) F.textUi = text end,
        hideTextUI = function() F.textUi = nil end,
        inputDialog = function(_, heading) return {heading} end,
        alertDialog = function() return "confirm" end,
    }
end

F.state = {qbx_core = "started", ox_lib = "started"}
exports.ox_lib = FakeOxLib()
exports.qbx_core = {GetPlayerData = function() return {citizenid = "ABC12345", job = clientJob} end,
                    Notify = function(_, msg) F.notified = msg end}
b = Load("qbox", "client")
F.notified = nil
b.Notify("vault open", "success")
check("ox_lib: notifications go to ox_lib when it runs",
      F.triggered[#F.triggered].name == "ox_lib:notify" and F.triggered[#F.triggered][1].description == "vault open"
      and F.triggered[#F.triggered][1].type == "success" and F.notified == nil)
check("ox_lib: progress bar", b.Progress({label = "Drilling", duration = 8000}) == true
      and F.progress.duration == 8000 and F.progress.label == "Drilling")
b.TextUI("[E] Open")
check("ox_lib: text UI", F.textUi == "[E] Open")
b.HideTextUI()
check("ox_lib: text UI hidden", F.textUi == nil)
check("ox_lib: input and alert dialogs", b.Input("Plate", {})[1] == "Plate" and b.Alert({}) == "confirm")

F.state = {qbx_core = "started"}   -- no ox_lib
b = Load("qbox", "client")
F.notified = nil
b.Notify("vault open")
check("no ox_lib: the framework notification is used", F.notified == "vault open")
check("no ox_lib: the progress bar still waits the full time",
      b.Progress({duration = 3000, anim = {dict = "anim@heists", clip = "drill"}}) == true
      and F.played.clip == "drill" and F.cleared == true)
F.dead = true
check("no ox_lib: dying during the progress bar fails it", b.Progress({duration = 1000}) == false)
F.dead = false
b.TextUI("[E] Open")
check("no ox_lib: text UI falls back to GTA's help text", RunThread(F.lastThread) and F.help == "[E] Open")
check("no ox_lib: input and alert say so by returning nil", b.Input("Plate", {}) == nil and b.Alert({}) == nil)

F.state = {qbx_core = "started", ox_lib = "started"}
exports.ox_lib = FakeOxLib()
b = Load("qbox", "client", {Notify = "framework"})
F.notified = nil
b.Notify("hello")
check("BridgeConfig.Notify = \"framework\" ignores ox_lib", F.notified == "hello")

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
