-- Trolleys. Each trolley is worth its bank's cash (TOB.TrolleyCash, times the gold/diamond multiplier) and
-- pays out over TOB.GrabTime seconds of grabbing: the server pays for the time the player actually spent
-- grabbing, so asking faster or more often can't pay more than the trolley holds.
-- The loot can hold a dye pack (TOB.DyePack) or a GPS tracker (TOB.Tracker, server/tracker.lua).

local Trolleys = {Loot1 = "trolley1", Loot2 = "trolley2", Loot3 = "trolley3"}
local GRAB_GRACE = 15000 -- ms after a grab could have finished before it's dropped
local MIN_ASK_GAP = 200  -- ms between two payout requests from one player

local function GrabMs()
    return (TOB.GrabTime or 37) * 1000
end

local function Roll(chance)
    return (chance or 0) > 0 and math.random(100) <= chance
end

-- Marked bills: one item per trolley with its value as metadata (needs an inventory with metadata)
local function UseMarkedBills()
    return TOB.MarkedBills == true and Bridge.Metadata == true
end

function AllLooted(bank)
    local h = Heists[bank]
    for _, slot in pairs(Trolleys) do
        if not h.looted[slot] then return false end
    end
    return true
end

function AnyGrab(bank)
    for _, g in pairs(Looting) do
        if g.bank == bank then return true end
    end
    return false
end

-- Pays what the player has earned so far on their trolley. With marked bills nothing is paid until
-- the grab ends (Finish); the loot counter still counts up.
local function Pay(src, g)
    local frac = math.min(1, (GetGameTimer() - g.started) / GrabMs())
    local owedWorth = math.floor(g.worth * frac)
    local worth, cash, items = 0, 0, 0

    if TestPayoutBlocked(g.bank) then
        -- a test heist (/tobtest): nothing is paid, but the loot counter shows what would have been
        worth = owedWorth - g.paidWorth
        if worth <= 0 then return end
        g.paidWorth = owedWorth
        local mine = RecordPayout(g.bank, src, worth, 0, 0)
        if TOB.LootCounter then
            TriggerClientEvent("TOB_fh:grabbed", src, worth, Money(mine))
        end
        return
    elseif g.marked then
        worth = owedWorth - g.paidWorth
        if worth <= 0 then return end
        g.paidWorth = owedWorth
        if TOB.LootCounter then
            TriggerClientEvent("TOB_fh:grabbed", src, worth, Money(g.paidWorth))
        end
        return
    elseif g.item then
        local owedItems = math.floor(g.itemTotal * frac)
        local n = owedItems - g.paidItems
        if n <= 0 then return end
        if not Bridge.AddItem(src, g.item, n) then
            if not g.full then
                g.full = true
                TriggerClientEvent("TOB_fh:bagFull", src)
            end
            return
        end
        g.full = false
        g.paidItems = owedItems
        items = n
        owedWorth = math.floor(g.worth * owedItems / math.max(1, g.itemTotal))
        worth = owedWorth - g.paidWorth
    else
        worth = owedWorth - g.paidWorth
        if worth <= 0 then return end
        Bridge.AddMoney(src, worth, TOB.black or g.dirty)
        cash = worth
    end
    g.paidWorth = owedWorth
    local mine = RecordPayout(g.bank, src, worth, cash, items, g.item)
    if TOB.LootCounter then
        TriggerClientEvent("TOB_fh:grabbed", src, worth, Money(mine))
    end
end

-- The grab is over: marked bills are handed out, and the dye pack or GPS tracker goes off
local function Finish(src, g)
    Looting[src] = nil
    if g.marked and g.paidWorth > 0 and not TestPayoutBlocked(g.bank) then
        if Bridge.AddItem(src, TOB.MarkedBillsItem or "markedbills", 1, {worth = g.paidWorth}) then
            RecordPayout(g.bank, src, g.paidWorth, 0, 1, TOB.MarkedBillsItem or "markedbills")
        else
            -- no room for the bag: pay it as dirty money so nothing is lost
            Bridge.AddMoney(src, g.paidWorth, true)
            RecordPayout(g.bank, src, g.paidWorth, g.paidWorth, 0)
            TriggerClientEvent("TOB_fh:bagFull", src)
        end
    end
    if g.dye then
        TriggerClientEvent("TOB_fh:dyePack", -1, src, TOB.DyePack.smoke or 10)
        Log("Dye pack", PlayerLabel(src) .. " was hit by a dye pack at " .. BankName(g.bank) .. ".", 15158332)
    end
    if TOB.Tracker and TOB.Tracker.enabled and Roll(TOB.Tracker.chance) then
        StartTracker(src, g.bank)
    end
end

-- Finishes every grab at a bank (the heist is ending)
function FinishBankGrabs(bank)
    for id, g in pairs(Looting) do
        if g.bank == bank then Finish(id, g) end
    end
end

-- Removes grabs whose player stopped asking long ago (crashed or never sent grabDone)
function DropStaleGrabs(now)
    for id, g in pairs(Looting) do
        if now - g.started > GrabMs() + GRAB_GRACE then Finish(id, g) end
    end
end

RegisterServerEvent("TOB_fh:lootup")
AddEventHandler("TOB_fh:lootup", function(bank, loot)
    local _source = source
    local slot = Trolleys[loot]
    local h = Heists[bank]

    if h == nil or slot == nil or Bridge.IsPolice(_source) then return end
    local function Deny(reason)
        TriggerClientEvent("TOB_fh:lootResult", _source, bank, loot, false, reason)
    end
    if Looting[_source] ~= nil then return Deny() end
    if h.looted[slot] then return Deny("trolley_taken") end
    if h.stage ~= "open" then return Deny() end
    if not VaultOpen(bank) or (slot == GateTrolley(bank) and not h.gateOpen) then
        Flag(_source, "Tried to loot a trolley at " .. BankName(bank) .. " before it could be reached.")
        return Deny()
    end
    if not IsNear(_source, TOB.Banks[bank][slot], 5.0) then
        Flag(_source, "Tried to loot a trolley at " .. BankName(bank) .. " from far away.")
        return Deny()
    end

    local kind = h.special and h.special[slot]
    local special = kind and TOB.SpecialTrolleys and TOB.SpecialTrolleys[kind]
    local cash = BankCash(bank)
    local worth = math.random(cash.min, cash.max)
    if special then
        worth = math.floor(worth * (special.multiplier or 1))
    end
    -- A dye pack ruins part of the money; the rest can be paid as dirty money
    local dye = TOB.DyePack and TOB.DyePack.enabled and Roll(TOB.DyePack.chance)
    if dye then
        worth = math.floor(worth * (1 - (TOB.DyePack.loss or 0)))
    end
    local item, itemTotal, marked = nil, 0, false
    if special and special.item and special.item ~= "" then
        item, itemTotal = special.item, special.itemCount or 20
    elseif TOB.RewardItem ~= nil and TOB.RewardItem ~= "" then
        item = TOB.RewardItem
        itemTotal = TOB.RewardItemCount == "cash" and worth or (tonumber(TOB.RewardItemCount) or 1)
    elseif UseMarkedBills() then
        marked = true
    end

    h.looted[slot] = true
    Looting[_source] = {bank = bank, slot = slot, started = GetGameTimer(), last = 0,
                        worth = worth, paidWorth = 0, item = item, itemTotal = itemTotal, paidItems = 0,
                        marked = marked, dye = dye, dirty = dye and TOB.DyePack.dirty == true}
    TriggerClientEvent("TOB_fh:lootResult", _source, bank, loot, true)
    TriggerClientEvent("TOB_fh:lootup_c", -1, bank, loot)
end)

-- Sent each time a pile lands in the bag (the grab animation's RELEASE_CASH_DESTROY event)
RegisterServerEvent("TOB_fh:rewardCash")
AddEventHandler("TOB_fh:rewardCash", function()
    local _source = source
    local g = Looting[_source]

    if g == nil then
        Flag(_source, "Asked for heist cash without looting a trolley.")
        return
    end
    local now = GetGameTimer()
    if now - g.last < MIN_ASK_GAP then return end
    g.last = now
    if not IsNear(_source, TOB.Banks[g.bank][g.slot], 6.0) then
        Flag(_source, "Asked for heist cash away from the trolley at " .. BankName(g.bank) .. ".")
        return
    end
    Pay(_source, g)
end)

-- Sent when the player stops grabbing (finished or pressed the stop key): pays the rest and frees the player
RegisterServerEvent("TOB_fh:grabDone")
AddEventHandler("TOB_fh:grabDone", function()
    local _source = source
    local g = Looting[_source]

    if g == nil then return end
    if IsNear(_source, TOB.Banks[g.bank][g.slot], 6.0) then
        Pay(_source, g)
    end
    Finish(_source, g)
end)
