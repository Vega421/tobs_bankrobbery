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

-- Calls a qb-inventory export; falls back to the old Player.Functions (older qb-core) when it doesn't exist
local function QbInventory(fn, oldFn, src, ...)
    local args = table.pack(...)
    local ok, result = pcall(function() return exports["qb-inventory"][fn](exports["qb-inventory"], src, table.unpack(args, 1, args.n)) end)
    if ok then return result end
    local player = GetPlayer(src)
    if player == nil or player.Functions[oldFn] == nil then return nil end
    return player.Functions[oldFn](args[1], args[2])
end

function Bridge.RemoveItem(src, item, count)
    if UseOx() then return exports.ox_inventory:RemoveItem(src, item, count) == true end
    return QbInventory("RemoveItem", "RemoveItem", src, item, count, false, "tobs_bankrobbery") ~= false
end

function Bridge.CanCarry(src, item, count)
    if UseOx() then return exports.ox_inventory:CanCarryItem(src, item, count) == true end
    local ok, result = pcall(function() return exports["qb-inventory"]:CanAddItem(src, item, count) end)
    return not ok or result ~= false -- older qb-inventory has no check: assume it fits
end

function Bridge.AddItem(src, item, count)
    if UseOx() then return exports.ox_inventory:AddItem(src, item, count) == true end
    return QbInventory("AddItem", "AddItem", src, item, count, false, nil, "tobs_bankrobbery") ~= false
end

function Bridge.AddMoney(src, amount, dirty)
    if dirty then return Bridge.AddItem(src, BlackMoneyItem(), amount) end
    local player = GetPlayer(src)
    if player ~= nil then player.Functions.AddMoney("cash", amount, "tobs_bankrobbery") end
end
