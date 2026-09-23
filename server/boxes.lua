-- Deposit boxes, drilled while the vault is open. The server checks the box, the player, the drill item
-- and that the drilling took as long as it should before paying. A player drills one box at a time.

-- Picks a reward from TOB.DrillRewards by weight
local function RollBoxReward()
    local total = 0
    for _, r in ipairs(TOB.DrillRewards or {}) do total = total + (r.chance or 0) end
    if total <= 0 then return nil end
    local roll = math.random() * total
    for _, r in ipairs(TOB.DrillRewards) do
        roll = roll - (r.chance or 0)
        if roll <= 0 then return r end
    end
    return TOB.DrillRewards[#TOB.DrillRewards]
end

local function IsDrilling(src)
    for _, h in pairs(Heists) do
        for _, state in pairs(h.boxes) do
            if state.busy == src then return true end
        end
    end
    return false
end

-- Frees the boxes a player was drilling (they left)
function DropBoxes(src)
    for bank, h in pairs(Heists) do
        for box, state in pairs(h.boxes) do
            if state.busy == src then
                h.boxes[box] = nil
                TriggerClientEvent("tobsbank:boxState", -1, bank, box, nil)
                BankSound(bank, "drill_off", box)
            end
        end
    end
end

RegisterServerEvent("tobsbank:drillBox")
AddEventHandler("tobsbank:drillBox", function(bank, box)
    local _source = source

    if not TOB.DepositBoxes or not VaultOpen(bank) or Bridge.IsPolice(_source) then return end
    local pos = TOB.Banks[bank].boxes and TOB.Banks[bank].boxes[box]
    if pos == nil then return end
    if not IsNear(_source, pos, 3.0) then
        Flag(_source, "Tried to drill a deposit box at " .. BankName(bank) .. " from far away.")
        return
    end
    local h = Heists[bank]
    local state = h.boxes[box]
    if state and state.opened then return end
    if state and state.busy and state.busy ~= _source then
        TriggerClientEvent("tobsbank:drillResult", _source, bank, box, false, "box_busy")
        return
    end
    if IsDrilling(_source) then
        TriggerClientEvent("tobsbank:drillResult", _source, bank, box, false, "already_drilling")
        return
    end
    if TOB.DrillItem and TOB.DrillItem ~= "" and not Bridge.HasItem(_source, TOB.DrillItem, 1) then
        TriggerClientEvent("tobsbank:drillResult", _source, bank, box, false, "no_drill")
        return
    end
    h.boxes[box] = {busy = _source, started = GetGameTimer()}
    TriggerClientEvent("tobsbank:boxState", -1, bank, box, "busy")
    TriggerClientEvent("tobsbank:drillResult", _source, bank, box, true)
    BankSound(bank, "drill_on", box, _source) -- everyone near hears the drill (client/sounds.lua)
end)

RegisterServerEvent("tobsbank:drillDone")
AddEventHandler("tobsbank:drillDone", function(bank, box, success)
    local _source = source
    local h = Heists[bank]
    local state = h and h.boxes[box]

    if state == nil or state.busy ~= _source then return end
    BankSound(bank, "drill_off", box)
    if not VaultOpen(bank) then return end
    if not success then
        h.boxes[box] = nil
        TriggerClientEvent("tobsbank:boxState", -1, bank, box, nil)
        return
    end
    if GetGameTimer() - state.started < (TOB.DrillTime or 0) - 2000 then
        Flag(_source, "Finished drilling a deposit box at " .. BankName(bank) .. " faster than possible.")
        return
    end
    if not IsNear(_source, TOB.Banks[bank].boxes[box], 3.0) then
        Flag(_source, "Finished drilling a deposit box at " .. BankName(bank) .. " from far away.")
        return
    end

    local r = RollBoxReward()
    local pay = not TestPayoutBlocked(bank) -- a test heist (/tobtest) pays nothing but still says what was inside
    local count = r and r.type == "item" and r.name and math.random(r.min or 1, r.max or r.min or 1) or 0
    -- Full pockets: the box stays closed so the player can make room and drill it again
    if count > 0 and not Bridge.CanCarry(_source, r.name, count) then
        h.boxes[box] = nil
        TriggerClientEvent("tobsbank:boxState", -1, bank, box, nil)
        TriggerClientEvent("tobsbank:bagFull", _source)
        return
    end
    h.boxes[box] = {opened = true}
    TriggerClientEvent("tobsbank:boxState", -1, bank, box, "opened")

    if r == nil or r.type == "nothing" then
        TriggerClientEvent("tobsbank:boxReward", _source, L("box_empty"))
    elseif r.type == "money" then
        local amount = math.random(r.min or 0, r.max or r.min or 0)
        if pay then Bridge.AddMoney(_source, amount, TOB.black and "black" or "cash") end
        RecordPayout(bank, _source, amount, pay and amount or 0, 0)
        TriggerClientEvent("tobsbank:boxReward", _source, L("box_money", Money(amount)))
    elseif count > 0 then
        if not pay then
            TriggerClientEvent("tobsbank:boxReward", _source, L("box_item", count, r.label or r.name))
        elseif Bridge.AddItem(_source, r.name, count) then
            RecordPayout(bank, _source, 0, 0, count, r.name)
            TriggerClientEvent("tobsbank:boxReward", _source, L("box_item", count, r.label or r.name))
        else
            TriggerClientEvent("tobsbank:bagFull", _source)
        end
    end
end)
