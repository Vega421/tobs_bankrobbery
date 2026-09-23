-- ESX Legacy: players, jobs, items and money. Server side.
if Framework ~= "esx" then return end
if not IsDuplicityVersion() then return end

local ESX
do -- ESX Legacy uses the export; older ESX used the event
    local ok, shared = pcall(function() return exports["es_extended"]:getSharedObject() end)
    ESX = ok and shared or nil
    if ESX == nil then
        TriggerEvent("esx:getSharedObject", function(obj) ESX = obj end)
    end
end

Bridge.Metadata = false      -- ESX items carry no metadata
Bridge.Inventory = Bridge.Has["ox_inventory"] and "ox" or "esx"
Bridge.RegisterCallback = BridgeCallbacks.Register

local function Player(src)
    return ESX and ESX.GetPlayerFromId(tonumber(src)) or nil
end

function Bridge.GetPlayer(src)
    local p = Player(src)
    if p == nil then return nil end
    local person = Bridge.GetPerson(p.identifier) or {}
    return {
        id = p.identifier,
        source = tonumber(src),
        firstname = person.firstname,
        lastname = person.lastname,
        dob = person.dob,
        phone = person.phone,
        gender = person.gender,
        job = Bridge.GetJob(src),
    }
end

function Bridge.GetIdentifier(src)
    local p = Player(src)
    return p and p.identifier or nil
end

function Bridge.GetJob(src)
    local p = Player(src)
    if p == nil then return nil end
    local job = p.job or {}
    return {
        name = job.name,
        label = job.label,
        grade = job.grade or 0,
        gradeLabel = job.grade_label,
        onduty = true,           -- ESX has no duty; police count when they have the job
        boss = false,
    }
end

function Bridge.IsPolice(src)
    local job = Bridge.GetJob(src)
    return job ~= nil and IsPoliceJobName(job.name)
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

-- Items ------------------------------------------------------------------

function Bridge.GetItemCount(src, item)
    if Bridge.Inventory == "ox" then return exports.ox_inventory:GetItemCount(src, item) or 0 end
    local p = Player(src)
    local found = p and p.getInventoryItem(item)
    return found and found.count or 0
end

function Bridge.HasItem(src, item, count)
    return Bridge.GetItemCount(src, item) >= (count or 1)
end

function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if Bridge.Inventory == "ox" then return exports.ox_inventory:RemoveItem(src, item, count) == true end
    local p = Player(src)
    if p == nil or Bridge.GetItemCount(src, item) < count then return false end
    p.removeInventoryItem(item, count)
    return true
end

-- metadata is ignored: ESX items can't carry it (Bridge.Metadata is false)
function Bridge.AddItem(src, item, count)
    count = count or 1
    if Bridge.Inventory == "ox" then return exports.ox_inventory:AddItem(src, item, count) == true end
    local p = Player(src)
    if p == nil or not p.canCarryItem(item, count) then return false end
    p.addInventoryItem(item, count)
    return true
end

function Bridge.CanCarry(src, item, count)
    count = count or 1
    if Bridge.Inventory == "ox" then return exports.ox_inventory:CanCarryItem(src, item, count) == true end
    local p = Player(src)
    return p ~= nil and p.canCarryItem(item, count) == true
end

-- Money: ESX keeps dirty money in its own black_money account --------------

function Bridge.AddMoney(src, amount, account)
    local p = Player(src)
    if p == nil then return false end
    if account == "black" then p.addAccountMoney("black_money", amount)
    elseif account == "bank" then p.addAccountMoney("bank", amount)
    else p.addMoney(amount) end
    return true
end

function Bridge.RemoveMoney(src, amount, account)
    local p = Player(src)
    if p == nil then return false end
    if Bridge.GetMoney(src, account) < amount then return false end
    if account == "black" then p.removeAccountMoney("black_money", amount)
    elseif account == "bank" then p.removeAccountMoney("bank", amount)
    else p.removeMoney(amount) end
    return true
end

function Bridge.GetMoney(src, account)
    local p = Player(src)
    if p == nil then return 0 end
    if account == "black" then return (p.getAccount("black_money") or {}).money or 0 end
    if account == "bank" then return (p.getAccount("bank") or {}).money or 0 end
    return p.getMoney()
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent("bridge:notify", src, msg, kind)
end
