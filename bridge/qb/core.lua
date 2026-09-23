-- QBCore: players, jobs, items (ox_inventory, qb-inventory or the old core) and money. Server side.
-- The database side is in bridge/qbox/data.lua: QBCore and Qbox use the same tables.
if Framework ~= "qb" then return end
if not IsDuplicityVersion() then return end

local QBCore = exports["qb-core"]:GetCoreObject()

Bridge.Metadata = true
Bridge.Inventory = Bridge.Has["ox_inventory"] and "ox" or (Bridge.Has["qb-inventory"] and "qb" or "core")
Bridge.RegisterCallback = BridgeCallbacks.Register

local function Player(src)
    return QBCore.Functions.GetPlayer(tonumber(src))
end

function Bridge.GetPlayer(src)
    local p = Player(src)
    if p == nil then return nil end
    local info = p.PlayerData.charinfo or {}
    return {
        id = p.PlayerData.citizenid,
        source = tonumber(src),
        firstname = info.firstname,
        lastname = info.lastname,
        dob = info.birthdate,
        phone = info.phone,
        gender = info.gender,
        job = Bridge.GetJob(src),
    }
end

function Bridge.GetIdentifier(src)
    local p = Player(src)
    return p and p.PlayerData.citizenid or nil
end

-- The character is in the world, kept from qb-core's events (no call to qb-core per question)
local Loaded = BridgeLoadedList(function(src) return Bridge.GetIdentifier(src) ~= nil end)
AddEventHandler("QBCore:Server:PlayerLoaded", function(player)
    Loaded.Set(player and player.PlayerData and player.PlayerData.source, true)
end)
AddEventHandler("QBCore:Server:OnPlayerUnload", function(src) Loaded.Set(src, false) end)
AddEventHandler("playerDropped", function() Loaded.Forget(source) end)

function Bridge.IsLoaded(src)
    return Loaded.IsLoaded(src)
end

-- Dead or in last stand: an isDead state bag if a medical script sets one, else qb-ambulancejob's metadata
function Bridge.IsDead(src)
    local state = BridgeState(src)
    if state and state.isDead then return true end
    local p = Player(src)
    local meta = p and p.PlayerData.metadata or {}
    return meta.isdead == true or meta.inlaststand == true
end

function Bridge.GetJob(src)
    local p = Player(src)
    if p == nil then return nil end
    local job = p.PlayerData.job or {}
    return {
        name = job.name,
        label = job.label,
        grade = job.grade and job.grade.level or 0,
        gradeLabel = job.grade and job.grade.name,
        onduty = job.onduty == true,
        boss = job.isboss == true,
    }
end

function Bridge.IsPolice(src)
    return IsPoliceJobData(Bridge.GetJob(src))
end

function Bridge.GetPlayersByJob(job)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local j = Bridge.GetJob(tonumber(id))
        if j and (job == nil or j.name == job) then out[#out + 1] = tonumber(id) end
    end
    return out
end

function Bridge.CountPolice()
    local n = 0
    for _, id in ipairs(GetPlayers()) do
        if Bridge.IsPolice(tonumber(id)) then n = n + 1 end
    end
    return n
end

-- Items: ox_inventory if it runs, else qb-inventory, else the old qb-core functions -------------

function Bridge.GetItemCount(src, item)
    if Bridge.Inventory == "ox" then return exports.ox_inventory:GetItemCount(src, item) or 0 end
    if Bridge.Inventory == "qb" then return exports["qb-inventory"]:GetItemCount(src, item) or 0 end
    local p = Player(src)
    local found = p and p.Functions.GetItemByName(item)
    return found and found.amount or 0
end

-- Weapons are items: ox_inventory names them in capitals (WEAPON_PISTOL), qb-core in lower case
function Bridge.HasWeapon(src, weapon)
    weapon = tostring(weapon)
    return Bridge.GetItemCount(src, Bridge.Inventory == "ox" and weapon:upper() or weapon:lower()) > 0
end

function Bridge.HasItem(src, item, count)
    return Bridge.GetItemCount(src, item) >= (count or 1)
end

function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if Bridge.Inventory == "ox" then return exports.ox_inventory:RemoveItem(src, item, count) == true end
    if Bridge.Inventory == "qb" then return exports["qb-inventory"]:RemoveItem(src, item, count, nil, "bridge") == true end
    local p = Player(src)
    return p ~= nil and p.Functions.RemoveItem(item, count) == true
end

function Bridge.AddItem(src, item, count, metadata)
    count = count or 1
    if Bridge.Inventory == "ox" then return exports.ox_inventory:AddItem(src, item, count, metadata) == true end
    if Bridge.Inventory == "qb" then return exports["qb-inventory"]:AddItem(src, item, count, false, metadata, "bridge") == true end
    local p = Player(src)
    return p ~= nil and p.Functions.AddItem(item, count, false, metadata) == true
end

function Bridge.CanCarry(src, item, count)
    count = count or 1
    if Bridge.Inventory == "ox" then return exports.ox_inventory:CanCarryItem(src, item, count) == true end
    if Bridge.Inventory == "qb" then return exports["qb-inventory"]:CanAddItem(src, item, count) == true end
    return true -- the old core has no check
end

-- Money ------------------------------------------------------------------

function Bridge.AddMoney(src, amount, account, reason)
    if account == "black" then return Bridge.AddItem(src, BlackMoneyItem(), amount) end
    local p = Player(src)
    return p ~= nil and p.Functions.AddMoney(account or "cash", amount, reason or "bridge") ~= false
end

function Bridge.RemoveMoney(src, amount, account, reason)
    if account == "black" then return Bridge.RemoveItem(src, BlackMoneyItem(), amount) end
    local p = Player(src)
    return p ~= nil and p.Functions.RemoveMoney(account or "cash", amount, reason or "bridge") ~= false
end

function Bridge.GetMoney(src, account)
    if account == "black" then return Bridge.GetItemCount(src, BlackMoneyItem()) end
    local p = Player(src)
    return p and (p.PlayerData.money[account or "cash"] or 0) or 0
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent("bridge:notify", src, msg, kind)
end
