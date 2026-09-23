-- ESX Legacy: the client side (job cache, notifications, callbacks)
if Framework ~= "esx" then return end
if IsDuplicityVersion() then return end

local ESX
do
    local ok, shared = pcall(function() return exports["es_extended"]:getSharedObject() end)
    ESX = ok and shared or nil
    if ESX == nil then TriggerEvent("esx:getSharedObject", function(obj) ESX = obj end) end
end

Bridge.TriggerCallback = BridgeCallbacks.Trigger
Bridge.NotifyFallback = "framework"

local job, identifier = nil, nil

RegisterNetEvent("esx:setJob", function(newJob) job = newJob end)
RegisterNetEvent("esx:playerLoaded", function(data)
    job = data and data.job
    identifier = data and data.identifier
end)

function Bridge.Init(cb)
    Citizen.CreateThread(function()
        while ESX == nil do Citizen.Wait(200) end
        while ESX.GetPlayerData() == nil or ESX.GetPlayerData().job == nil do Citizen.Wait(500) end
        local data = ESX.GetPlayerData()
        job, identifier = data.job, data.identifier
        if cb then cb() end
    end)
end

function Bridge.GetJob()
    if job == nil then return nil end
    return {name = job.name, label = job.label, grade = job.grade or 0,
            gradeLabel = job.grade_label, onduty = true}
end

function Bridge.IsPolice()
    local j = Bridge.GetJob()
    return j ~= nil and IsPoliceJobName(j.name)
end

function Bridge.GetIdentifier()
    return identifier
end

-- The framework's own notification. bridge/shared/ui.lua wraps this as Bridge.Notify.
function Bridge.FrameworkNotify(msg, kind)
    if ESX and ESX.ShowNotification then ESX.ShowNotification(msg) end
end
