-- Police alerts: a notification when a heist starts, and a flashing map blip on the bank for as long
-- as the heist runs. Officers who come on duty during a heist get the blip too.

local blips = {} -- [bank] = blip

local function RemovePoliceBlip(bank)
    if blips[bank] ~= nil then
        RemoveBlip(blips[bank])
        blips[bank] = nil
    end
end

local function AddPoliceBlip(bank)
    if blips[bank] ~= nil then return end
    local s = StartVec(bank)
    local blip = AddBlipForCoord(s.x, s.y, s.z)
    SetBlipSprite(blip, 161)
    SetBlipScale(blip, 2.0)
    SetBlipColour(blip, 1)
    PulseBlip(blip)
    blips[bank] = blip
end

RegisterNetEvent("tobsbank:policenotify")
AddEventHandler("tobsbank:policenotify", function(bank)
    if TOB.BuiltInPoliceAlert and TOB.Banks[bank] ~= nil and IsPoliceJob() then
        Notify("warning", L("police_alert"), 10000)
        AddPoliceBlip(bank)
    end
end)

-- The server tells everyone when a bank's heist starts or ends
RegisterNetEvent("tobsbank:bankState")
AddEventHandler("tobsbank:bankState", function(bank, active)
    if TOB.Banks[bank] == nil then return end
    TOB.Banks[bank].onaction = active
    if not active then RemovePoliceBlip(bank) end
end)

-- Keeps the blips right when a player goes on or off duty during a heist
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        if Ready and TOB.BuiltInPoliceAlert then
            local police = IsPoliceJob()
            for bank, b in pairs(TOB.Banks) do
                if police and b.onaction then
                    AddPoliceBlip(bank)
                else
                    RemovePoliceBlip(bank)
                end
            end
        end
    end
end)
