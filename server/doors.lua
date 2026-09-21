-- Police lock and unlock the gate and the vault. The robber's gate and vault are opened by the
-- server itself (server/heist.lua), so these events are for police only.

RegisterServerEvent("TOB_fh:toggleDoor")
AddEventHandler("TOB_fh:toggleDoor", function(key, state)
    local _source = source

    if Doors[key] == nil or type(state) ~= "boolean" then return end
    if not Bridge.IsPolice(_source) then
        Flag(_source, "Tried to use the gate at " .. BankName(key) .. " without being police.")
        return
    end
    if not IsNear(_source, Doors[key][1].loc, 5.0) then return end
    Doors[key][1].locked = state
    TriggerClientEvent("TOB_fh:toggleDoor", -1, key, state)
end)

RegisterServerEvent("TOB_fh:toggleVault")
AddEventHandler("TOB_fh:toggleVault", function(key, state)
    local _source = source

    if Doors[key] == nil or type(state) ~= "boolean" then return end
    if not Bridge.IsPolice(_source) then
        Flag(_source, "Tried to use the vault at " .. BankName(key) .. " without being police.")
        return
    end
    if not IsNear(_source, Doors[key][2].loc, 5.0) then return end
    Doors[key][2].locked = state
    VaultMoved[key] = GetGameTimer()
    TriggerClientEvent("TOB_fh:toggleVault", -1, key, state)
end)

-- The first player near the vault reports the door's final angle after it moved, so players who
-- weren't nearby see it correctly later. Only accepted within 20 s of a real open/close (the animation takes 9 s).
RegisterServerEvent("TOB_fh:updateVaultState")
AddEventHandler("TOB_fh:updateVaultState", function(key, state)
    if Doors[key] == nil or type(state) ~= "number" then return end
    if VaultMoved[key] == nil or GetGameTimer() - VaultMoved[key] > 20000 then return end
    if not IsNear(source, Doors[key][2].loc, 60.0) then return end
    VaultMoved[key] = nil
    Doors[key][2].state = state
    TriggerClientEvent("TOB_fh:vaultState", -1, key, state)
end)
