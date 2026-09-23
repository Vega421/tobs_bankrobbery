-- QBCore: the client side (job cache, notifications, callbacks)
if Framework ~= "qb" then return end
if IsDuplicityVersion() then return end

local QBCore = exports["qb-core"]:GetCoreObject()

Bridge.TriggerCallback = BridgeCallbacks.Trigger
Bridge.NotifyFallback = "framework"

local job = nil

local function Refresh()
    local data = QBCore.Functions.GetPlayerData()
    job = data and data.job
end

RegisterNetEvent("QBCore:Client:OnPlayerLoaded", Refresh)
RegisterNetEvent("QBCore:Client:OnJobUpdate", function(newJob) job = newJob end)
RegisterNetEvent("QBCore:Client:SetDuty", function(onDuty)
    if job ~= nil then job.onduty = onDuty end
end)

-- Waits until the player is loaded, runs cb, then keeps the job up to date
function Bridge.Init(cb)
    Citizen.CreateThread(function()
        while (QBCore.Functions.GetPlayerData() or {}).job == nil do Citizen.Wait(500) end
        Refresh()
        if cb then cb() end
        while true do
            Citizen.Wait(10000)
            Refresh()
        end
    end)
end

function Bridge.GetJob()
    if job == nil then return nil end
    return {name = job.name, label = job.label,
            grade = job.grade and job.grade.level or 0, onduty = job.onduty == true}
end

function Bridge.IsPolice()
    return IsPoliceJobData(Bridge.GetJob())
end

function Bridge.GetIdentifier()
    local data = QBCore.Functions.GetPlayerData()
    return data and data.citizenid or nil
end

-- The framework's own notification. bridge/shared/ui.lua wraps this as Bridge.Notify.
function Bridge.FrameworkNotify(msg, kind)
    TriggerEvent("QBCore:Notify", msg, kind or "primary")
end
