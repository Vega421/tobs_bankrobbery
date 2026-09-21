-- GPS tracker (TOB.Tracker): police see a tracked robber on the map. Dye pack (TOB.DyePack): red smoke
-- on the robber when it bursts.

local trackerBlips = {} -- [server id] = {blip, seen = GetGameTimer()}

local function RemoveTracker(id)
    local t = trackerBlips[id]
    if t then
        RemoveBlip(t.blip)
        trackerBlips[id] = nil
    end
end

-- The server sends police the tracked robber's position every TOB.Tracker.interval seconds
RegisterNetEvent("TOB_fh:trackerPos")
AddEventHandler("TOB_fh:trackerPos", function(id, coords, secondsLeft)
    if not IsPoliceJob() then return RemoveTracker(id) end
    local t = trackerBlips[id]
    if t == nil then
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 161)
        SetBlipScale(blip, 1.2)
        SetBlipColour(blip, 1)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(L("tracker_blip"))
        EndTextCommandSetBlipName(blip)
        t = {blip = blip}
        trackerBlips[id] = t
        Notify("warning", L("tracker_police", secondsLeft), 8000)
    else
        SetBlipCoords(t.blip, coords.x, coords.y, coords.z)
    end
    t.seen = GetGameTimer()
end)

RegisterNetEvent("TOB_fh:trackerEnd")
AddEventHandler("TOB_fh:trackerEnd", function(id)
    RemoveTracker(id)
end)

-- The robber finds out they're being tracked (TOB.Tracker.warnRobber)
RegisterNetEvent("TOB_fh:trackerWarn")
AddEventHandler("TOB_fh:trackerWarn", function()
    Notify("warning", L("tracker_warn"), 10000)
end)

-- Removes blips the server stopped updating (the robber left the police's area of interest, or went off duty)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10000)
        for id, t in pairs(trackerBlips) do
            if GetGameTimer() - t.seen > 30000 then RemoveTracker(id) end
        end
    end
end)

-- Dye pack: red smoke around the robber for everyone nearby
RegisterNetEvent("TOB_fh:dyePack")
AddEventHandler("TOB_fh:dyePack", function(id, seconds)
    if id == GetPlayerServerId(PlayerId()) then
        Notify("error", L("dye_pack"), 8000)
    end
    local player = GetPlayerFromServerId(id)
    if player == -1 then return end
    local ped = GetPlayerPed(player)
    if ped == 0 or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) > 100.0 then return end
    RequestNamedPtfxAsset("core")
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded("core") and GetGameTimer() < timeout do Citizen.Wait(10) end
    UseParticleFxAssetNextCall("core")
    local fx = StartParticleFxLoopedOnEntity("exp_grd_flare", ped, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, false, false, false)
    Citizen.Wait(seconds * 1000)
    StopParticleFxLooped(fx, false)
end)
