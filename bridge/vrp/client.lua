-- vRP bridge (client)
if Framework ~= "vrp" then return end

Bridge = {NotifyFallback = "native", TriggerCallback = TOBCallbacks.Trigger}
local isPolice = false

-- vRP has no client-side job data, so ask the server every 10 seconds
Citizen.CreateThread(function()
    while true do
        TriggerServerEvent("TOB_fh:CheckCop")
        Citizen.Wait(10000)
    end
end)

RegisterNetEvent("TOB_fh:IsCop")
AddEventHandler("TOB_fh:IsCop", function()
    isPolice = true
end)

RegisterNetEvent("TOB_fh:IsNOTCop")
AddEventHandler("TOB_fh:IsNOTCop", function()
    isPolice = false
end)

function Bridge.Init(cb)
    cb()
end

function Bridge.IsPolice()
    return isPolice
end

function Bridge.Notify(msg)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end
