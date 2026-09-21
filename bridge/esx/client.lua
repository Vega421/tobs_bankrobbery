-- ESX bridge (client)
if Framework ~= "esx" then return end

ESX = nil
-- ESX Legacy uses the export; older ESX versions use the event
local ok, esxObj = pcall(function() return exports["es_extended"]:getSharedObject() end)
if ok and esxObj then
    ESX = esxObj
else
    TriggerEvent("esx:getSharedObject", function(obj) ESX = obj end)
end

Bridge = {NotifyFallback = "framework", TriggerCallback = TOBCallbacks.Trigger}
local PlayerData = nil

RegisterNetEvent("esx:setJob")
AddEventHandler("esx:setJob", function(job)
    if PlayerData ~= nil then PlayerData.job = job end
end)

RegisterNetEvent("esx:playerLoaded")
AddEventHandler("esx:playerLoaded", function(xPlayer)
    PlayerData = xPlayer
end)

-- Waits until ESX and the player's job are loaded, then runs cb
function Bridge.Init(cb)
    Citizen.CreateThread(function()
        while ESX == nil do Citizen.Wait(100) end
        while ESX.GetPlayerData().job == nil do Citizen.Wait(100) end
        PlayerData = ESX.GetPlayerData()
        cb()
    end)
end

function Bridge.IsPolice()
    return PlayerData ~= nil and PlayerData.job ~= nil and IsPoliceJobName(PlayerData.job.name)
end

function Bridge.Notify(msg)
    ESX.ShowNotification(msg)
end
