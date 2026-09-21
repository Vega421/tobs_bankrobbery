-- ESX bridge (server)
if Framework ~= "esx" then return end

ESX = nil
-- ESX Legacy uses the export; older ESX versions use the event
local ok, esxObj = pcall(function() return exports["es_extended"]:getSharedObject() end)
if ok and esxObj then
    ESX = esxObj
else
    TriggerEvent("esx:getSharedObject", function(obj) ESX = obj end)
end

Bridge = {RegisterCallback = TOBCallbacks.Register}

function Bridge.IsPolice(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer ~= nil and IsPoliceJobName(xPlayer.job.name)
end

function Bridge.CountPolice()
    local count = 0
    for _, id in ipairs(ESX.GetPlayers()) do
        if Bridge.IsPolice(id) then count = count + 1 end
    end
    return count
end

function Bridge.HasItem(src, item, count)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer == nil then return false end
    local inv = xPlayer.getInventoryItem(item)
    return inv ~= nil and (inv.count or 0) >= count
end

function Bridge.RemoveItem(src, item, count)
    if not Bridge.HasItem(src, item, count) then return false end
    ESX.GetPlayerFromId(src).removeInventoryItem(item, count)
    return true
end

function Bridge.CanCarry(src, item, count)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer == nil then return false end
    if xPlayer.canCarryItem == nil then return true end -- older ESX has no weight check
    return xPlayer.canCarryItem(item, count) ~= false
end

function Bridge.AddItem(src, item, count)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer == nil or not Bridge.CanCarry(src, item, count) then return false end
    xPlayer.addInventoryItem(item, count)
    return true
end

function Bridge.AddMoney(src, amount, dirty)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer == nil then return end
    if dirty then
        xPlayer.addAccountMoney("black_money", amount)
    else
        xPlayer.addMoney(amount)
    end
end
