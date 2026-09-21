-- Qbox bridge (client)
if Framework ~= "qbox" then return end

Bridge = {NotifyFallback = "framework", TriggerCallback = TOBCallbacks.Trigger}
local job = nil

local function Refresh()
    local data = exports.qbx_core:GetPlayerData()
    job = data and data.job
end

RegisterNetEvent("QBCore:Client:OnPlayerLoaded")
AddEventHandler("QBCore:Client:OnPlayerLoaded", Refresh)

RegisterNetEvent("QBCore:Client:OnJobUpdate")
AddEventHandler("QBCore:Client:OnJobUpdate", function(newJob)
    job = newJob
end)

RegisterNetEvent("QBCore:Client:SetDuty")
AddEventHandler("QBCore:Client:SetDuty", function(onDuty)
    if job ~= nil then job.onduty = onDuty end
end)

-- Waits until the player is loaded, then runs cb. The job is also re-read every 10 seconds,
-- in case a duty change didn't send an event.
function Bridge.Init(cb)
    Citizen.CreateThread(function()
        while (exports.qbx_core:GetPlayerData() or {}).job == nil do Citizen.Wait(500) end
        Refresh()
        cb()
        while true do
            Citizen.Wait(10000)
            Refresh()
        end
    end)
end

function Bridge.IsPolice()
    return IsPoliceJobData(job)
end

function Bridge.Notify(msg)
    exports.qbx_core:Notify(msg, "inform")
end
