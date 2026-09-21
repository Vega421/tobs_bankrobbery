-- Integrations for other resources: server events, exports and the server-side dispatch hook.
--
-- Events (server side, listen with AddEventHandler):
--   tobs_bankrobbery:heistStarted (bank, playerId, coords)   a heist started
--   tobs_bankrobbery:vaultOpened  (bank)                     the vault opened, looting starts
--   tobs_bankrobbery:heistEnded   (bank, reason, totalCash)  the heist ended
-- Exports (server side):
--   exports.tobs_bankrobbery:IsHeistActive(bank)  true while bank (or any bank, without an argument) is being robbed
--   exports.tobs_bankrobbery:GetHeist(bank)       {stage, leader, started, label} or nil
--   exports.tobs_bankrobbery:GetBanks()           list of {bank, label, active, cooldownLeft}
--   exports.tobs_bankrobbery:ResetHeist(bank)     same as /tobreset bank

local function BankCoords(bank)
    local s = TOB.Banks[bank].doors.startloc
    return vector3(s.x, s.y, s.z)
end

-- Called by server/heist.lua when a heist starts
function HeistStarted(bank, src)
    local coords = BankCoords(bank)
    TriggerEvent("tobs_bankrobbery:heistStarted", bank, src, coords)
    if type(SV.DispatchAlert) == "function" then
        local ok, err = pcall(SV.DispatchAlert, bank, coords, src, TOB.Banks[bank].label)
        if not ok then print("^1[tobs_bankrobbery] SV.DispatchAlert error: " .. tostring(err) .. "^7") end
    end
end

-- Called by server/heist.lua when a heist ends
function HeistEnded(bank, reason, total)
    TriggerEvent("tobs_bankrobbery:heistEnded", bank, reason, total)
end

exports("IsHeistActive", function(bank)
    if bank == nil then return next(Heists) ~= nil end
    return Heists[bank] ~= nil
end)

exports("GetHeist", function(bank)
    local h = Heists[bank]
    if h == nil then return nil end
    return {stage = h.stage, leader = h.owner, started = h.started, label = TOB.Banks[bank].label}
end)

exports("GetBanks", function()
    local list = {}
    for bank, b in pairs(TOB.Banks) do
        local left = math.max(0, BankCooldown(bank) - (os.time() - b.lastrobbed))
        list[#list + 1] = {bank = bank, label = b.label, active = Heists[bank] ~= nil, cooldownLeft = left}
    end
    table.sort(list, function(a, b) return a.bank < b.bank end)
    return list
end)

exports("ResetHeist", function(bank)
    if TOB.Banks[bank] == nil then return false end
    ResetBank(bank, "reset by " .. (GetInvokingResource() or "another resource"))
    return true
end)
