-- The gate and the vault door: kept in the right state for everyone, and police lock/unlock prompts.

function DoorThreads()
    -- Keeps the gate frozen (locked) and at the right angle while players are near
    Citizen.CreateThread(function()
        while true do
            local near = false
            local pcoords = GetEntityCoords(PlayerPedId())

            for k, v in pairs(Doors) do
                if #(pcoords - v[1].loc) < 60.0 then
                    near = true
                    if v[1].obj == nil or not DoesEntityExist(v[1].obj) then
                        v[1].obj = GetClosestObjectOfType(v[1].loc, 1.5, GateModel(k), false, false, false)
                    end
                    FreezeEntityPosition(v[1].obj, v[1].locked)
                    if v[1].locked then
                        SetEntityHeading(v[1].obj, v[1].h)
                    end
                end
            end
            Citizen.Wait(near and 200 or 2000)
        end
    end)

    -- "Press E" prompts for police at the gate and the vault
    Citizen.CreateThread(function()
        local useTarget = UseTarget()

        while true do
            local sleep = 1000

            if IsPoliceJob() and not DoorBusy and not useTarget then
                local pcoords = GetEntityCoords(PlayerPedId())

                for k, v in pairs(Doors) do
                    for i = 1, 2 do
                        local dst = #(pcoords - v[i].loc)

                        if dst <= PromptRange(1.5) then
                            sleep = 0
                            local label = v[i].locked and L("unlock_door") or L("lock_door")
                            if Prompt(v[i].txtloc, label, dst, 1.5) then
                                ToggleDoor(k, i)
                            end
                        elseif dst <= 30.0 and sleep > 250 then
                            sleep = 250
                        end
                    end
                end
            end
            Citizen.Wait(sleep)
        end
    end)

    -- Keeps the vault door at its last known angle for players who come near later
    Citizen.CreateThread(function()
        while true do
            local pcoords = GetEntityCoords(PlayerPedId())

            for k, v in pairs(Doors) do
                if v[2].state ~= nil and not DoorBusy and #(pcoords - v[2].loc) <= 20.0 then
                    local obj = GetVaultObject(k)
                    if obj ~= 0 then
                        SetEntityHeading(obj, v[2].state)
                    end
                end
            end
            Citizen.Wait(1000)
        end
    end)
end

-- Police only: the server ignores everyone else
function ToggleDoor(k, i)
    DoorBusy = true
    if i == 2 then
        TriggerServerEvent("TOB_fh:toggleVault", k, not Doors[k][i].locked)
    else
        TriggerServerEvent("TOB_fh:toggleDoor", k, not Doors[k][i].locked)
    end
    SetTimeout(3000, function() DoorBusy = false end) -- in case the server ignored it
end

RegisterNetEvent("TOB_fh:toggleDoor")
AddEventHandler("TOB_fh:toggleDoor", function(key, state)
    if Doors[key] ~= nil then
        Doors[key][1].locked = state
    end
    DoorBusy = false
end)

RegisterNetEvent("TOB_fh:toggleVault")
AddEventHandler("TOB_fh:toggleVault", function(key, state)
    if Doors[key] == nil then return end
    local obj = GetVaultObject(key)

    Doors[key][2].locked = state
    -- vault closed: the deposit boxes can't be drilled any more
    if state then LootActive[key] = false end
    -- Only players near the bank have the vault loaded. Everyone else just keeps the state,
    -- and gets the final door angle from the server (TOB_fh:vaultState).
    if obj == 0 then
        DoorBusy = false
        return
    end
    DoorBusy = true
    Doors[key][2].state = nil
    local step = state and 0.10 or -0.10
    for _ = 1, 900 do
        SetEntityHeading(obj, GetEntityHeading(obj) + step)
        Citizen.Wait(10)
    end
    Doors[key][2].state = GetEntityHeading(obj)
    TriggerServerEvent("TOB_fh:updateVaultState", key, Doors[key][2].state)
    DoorBusy = false
end)

RegisterNetEvent("TOB_fh:vaultState")
AddEventHandler("TOB_fh:vaultState", function(key, heading)
    if Doors[key] ~= nil then
        Doors[key][2].state = heading
    end
end)
