-- QBCore bridge (server). Items go through ox_inventory when it's running, otherwise qb-inventory.
if Framework ~= "qb" then return end

QBCore = exports["qb-core"]:GetCoreObject()

Bridge = {RegisterCallback = TOBCallbacks.Register}

local function GetPlayer(src)
    return QBCore.Functions.GetPlayer(src)
end

local function UseOx()
    return GetResourceState("ox_inventory") == "started"
end

local function ItemCount(src, item)
    if UseOx() then return exports.ox_inventory:GetItemCount(src, item) or 0 end
    local ok, count = pcall(function() return exports["qb-inventory"]:GetItemCount(src, item) end)
    if ok and count then return count end
    -- older qb-core keeps the items on the player
    local player = GetPlayer(src)
    local data = player and player.Functions.GetItemByName and player.Functions.GetItemByName(item)
    return data and data.amount or 0
end

function Bridge.IsPolice(src)
    local player = GetPlayer(src)
    return player ~= nil and IsPoliceJobData(player.PlayerData.job)
end

function Bridge.CountPolice()
    local count = 0
    for _, id in ipairs(GetPlayers()) do
        if Bridge.IsPolice(tonumber(id)) then count = count + 1 end
    end
    return count
end

function Bridge.HasItem(src, item, count)
    return ItemCount(src, item) >= count
end

function Bridge.RemoveItem(src, item, count)
    if UseOx() then return exports.ox_inventory:RemoveItem(src, item, count) end
    local ok = pcall(function() exports["qb-inventory"]:RemoveItem(src, item, count, false, "tobs_bankrobbery") end)
    if not ok then
        local player = GetPlayer(src)
        if player ~= nil then player.Functions.RemoveItem(item, count) end
    end
end

function Bridge.AddItem(src, item, count)
    if UseOx() then return exports.ox_inventory:AddItem(src, item, count) end
    local ok = pcall(function() exports["qb-inventory"]:AddItem(src, item, count, false, nil, "tobs_bankrobbery") end)
    if not ok then
        local player = GetPlayer(src)
        if player ~= nil then player.Functions.AddItem(item, count) end
    end
end

function Bridge.AddMoney(src, amount, dirty)
    if dirty then return Bridge.AddItem(src, BlackMoneyItem(), amount) end
    local player = GetPlayer(src)
    if player ~= nil then player.Functions.AddMoney("cash", amount, "tobs_bankrobbery") end
end
