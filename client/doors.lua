-- The gate and the vault door: kept in the right state for everyone, and police lock/unlock prompts.
-- The gate uses GTA's door system, registered locally for each player; the server decides if it's locked.

local gateRegistered = {} -- [bank] = true once the gate is in the door system
GATE_SEARCH = 4.0         -- metres around gate.loc to look for the gate model

local function GateDoorHash(bank)
    return GetHashKey("tobs_bankrobbery_gate_" .. bank)
end

-- Applies the server's locked state to the gate (1 = locked, 0 = unlocked)
local function ApplyGate(bank)
    if gateRegistered[bank] then
        DoorSystemSetDoorState(GateDoorHash(bank), Doors[bank][1].locked and 1 or 0, false, false)
    end
end

function DoorThreads()
    -- Registers the gate when the player comes near, and keeps its lock state applied
    -- (the game only applies it once the door's physics are loaded)
    Citizen.CreateThread(function()
        while true do
            local near = false
            local pcoords = GetEntityCoords(PlayerPedId())

            for k, v in pairs(Doors) do
                if #(pcoords - v[1].loc) < 60.0 then
                    near = true
                    if not gateRegistered[k] then
                        -- 4 m, not 1.5: a gate.loc a little off (the old Fleeca ones were ~2 m from the gate)
                        -- still finds it; a bank has one gate of its model
                        local obj = GetClosestObjectOfType(v[1].loc.x, v[1].loc.y, v[1].loc.z, GATE_SEARCH, GateModel(k), false, false, false)
                        if obj ~= 0 then
                            local c = GetEntityCoords(obj)
                            AddDoorToSystem(GateDoorHash(k), GateModel(k), c.x, c.y, c.z, false, false, false)
                            gateRegistered[k] = true
                        end
                    end
                    ApplyGate(k)
                end
            end
            Citizen.Wait(near and 1000 or 3000)
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
        TriggerServerEvent("tobsbank:toggleVault", k, not Doors[k][i].locked)
    else
        TriggerServerEvent("tobsbank:toggleDoor", k, not Doors[k][i].locked)
    end
    SetTimeout(3000, function() DoorBusy = false end) -- in case the server ignored it
end

RegisterNetEvent("tobsbank:toggleDoor")
AddEventHandler("tobsbank:toggleDoor", function(key, state)
    if Doors[key] ~= nil then
        Doors[key][1].locked = state
        ApplyGate(key)
    end
    DoorBusy = false
end)

RegisterNetEvent("tobsbank:toggleVault")
AddEventHandler("tobsbank:toggleVault", function(key, state)
    if Doors[key] == nil then return end
    local obj = GetVaultObject(key)

    Doors[key][2].locked = state
    -- vault closed: the deposit boxes can't be drilled any more
    if state then
        LootActive[key] = false
        if #(GetEntityCoords(PlayerPedId()) - StartVec(key)) < 40.0 then Notify("error", L("vault_closing")) end
    end
    -- Only players near the bank have the vault loaded. Everyone else just keeps the state,
    -- and gets the final door angle from the server (tobsbank:vaultState).
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
    TriggerServerEvent("tobsbank:updateVaultState", key, Doors[key][2].state)
    DoorBusy = false
end)

RegisterNetEvent("tobsbank:vaultState")
AddEventHandler("tobsbank:vaultState", function(key, heading)
    if Doors[key] ~= nil then
        Doors[key][2].state = heading
    end
end)
