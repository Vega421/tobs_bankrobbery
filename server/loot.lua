-- Trolleys. Each trolley is worth its bank's cash (TOB.TrolleyCash, times the gold/diamond multiplier) and
-- pays out over TOB.GrabTime seconds of grabbing: the server pays for the time the player actually spent
-- grabbing, so asking faster or more often can't pay more than the trolley holds.
-- The loot can hold a dye pack (TOB.DyePack) or a GPS tracker (TOB.Tracker, server/tracker.lua).

local Trolleys = {Loot1 = "trolley1", Loot2 = "trolley2", Loot3 = "trolley3"}
local GRAB_GRACE = 15000 -- ms after a grab could have finished before it's dropped
local MIN_ASK_GAP = 200  -- ms between two payout requests from one player
local FULL_SLACK = 1500  -- ms: a grab the player ran to its end (grabDone) this close to TOB.GrabTime pays the whole trolley

-- An item's label for the loot counter ("Gold Bar"), from ox_inventory; else its name
local labels = {}
local function ItemLabel(name)
    if labels[name] == nil then
        local ok, item = pcall(function()
            return GetResourceState("ox_inventory") == "started" and exports.ox_inventory:Items(name) or nil
        end)
        labels[name] = (ok and type(item) == "table" and item.label) or name
    end
    return labels[name]
end

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
-- the grab ends (Finish); the loot counter still counts up. done = the player stopped grabbing: a grab
-- that ran (almost) to its end pays the whole trolley. Once the trolley is empty the player is told,
-- so the grab animation stops with the money (tobsbank:trolleyEmpty).
local function Pay(src, g, done)
    local spent = GetGameTimer() - g.started
    local frac = math.min(1, spent / GrabMs())
    if done and spent >= GrabMs() - FULL_SLACK then frac = 1 end
    if frac >= 1 and not done and not g.emptySent then
        g.emptySent = true
        TriggerClientEvent("tobsbank:trolleyEmpty", src)
    end
    local owedWorth = math.floor(g.worth * frac)
    local worth, cash, items = 0, 0, 0

    if TestPayoutBlocked(g.bank) then
        -- a test heist (/tobtest): nothing is paid, but the loot counter shows what would have been
        worth = owedWorth - g.paidWorth
        if worth <= 0 then return end
        g.paidWorth = owedWorth
        local mine = RecordPayout(g.bank, src, worth, 0, 0)
        if TOB.LootCounter then
            TriggerClientEvent("tobsbank:grabbed", src, worth, Money(mine))
        end
        return
    elseif g.marked then
        worth = owedWorth - g.paidWorth
        if worth <= 0 then return end
        g.paidWorth = owedWorth
        if TOB.LootCounter then
            TriggerClientEvent("tobsbank:grabbed", src, worth, Money(g.paidWorth))
        end
        return
    elseif g.item then
        local owedItems = math.floor(g.itemTotal * frac)
        local n = owedItems - g.paidItems
        if n <= 0 then return end
        if not Bridge.AddItem(src, g.item, n) then
            if not g.full then
                g.full = true
                TriggerClientEvent("tobsbank:bagFull", src)
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
        Bridge.AddMoney(src, worth, (TOB.black or g.dirty) and "black" or "cash")
        cash = worth
    end
    g.paidWorth = owedWorth
    local mine = RecordPayout(g.bank, src, worth, cash, items, g.item)
    if TOB.LootCounter then
        -- items (gold bars, diamonds): the counter counts them, not dollars
        TriggerClientEvent("tobsbank:grabbed", src, worth, Money(mine), items, items > 0 and ItemLabel(g.item) or nil)
    end
end

-- The grab is over: marked bills are handed out, and the dye pack or GPS tracker goes off
local function Finish(src, g)
    Looting[src] = nil
    -- everyone's game keeps the grabbed trolley looking empty (trolleys without an empty model)
    TriggerClientEvent("tobsbank:trolleyDone", -1, g.bank, "Loot" .. g.slot:sub(-1))
    if g.marked and g.paidWorth > 0 and not TestPayoutBlocked(g.bank) then
        if Bridge.AddItem(src, TOB.MarkedBillsItem or "markedbills", 1, {worth = g.paidWorth}) then
            RecordPayout(g.bank, src, g.paidWorth, 0, 1, TOB.MarkedBillsItem or "markedbills")
        else
            -- no room for the bag: pay it as dirty money so nothing is lost
            Bridge.AddMoney(src, g.paidWorth, "black")
            RecordPayout(g.bank, src, g.paidWorth, g.paidWorth, 0)
            TriggerClientEvent("tobsbank:bagFull", src)
        end
    end
    if g.dye then
        TriggerClientEvent("tobsbank:dyePack", -1, src, TOB.DyePack.smoke or 10)
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

RegisterServerEvent("tobsbank:lootup")
AddEventHandler("tobsbank:lootup", function(bank, loot)
    local _source = source
    local slot = Trolleys[loot]
    local h = Heists[bank]

    -- Every request gets an answer: the player's game waits for one before it can loot again
    local function Deny(reason)
        TriggerClientEvent("tobsbank:lootResult", _source, bank, loot, false, reason)
    end
    if h == nil or slot == nil or Bridge.IsPolice(_source) then return Deny() end
    if Looting[_source] ~= nil then return Deny() end
    if h.looted[slot] then return Deny("trolley_taken") end
    if h.stage ~= "open" then return Deny() end
    if not VaultOpen(bank) then
        Flag(_source, "Tried to loot a trolley at " .. BankName(bank) .. " before it could be reached.")
        return Deny()
    end
    -- a trolley behind the inner gate: the player is told why (before, loot just did nothing)
    if IsGateTrolley(bank, slot) and not h.gateOpen then
        return Deny("gate_hint")
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
    -- A special trolley's item, unless the inventory doesn't have it: then it pays cash, instead of
    -- "pockets full" and nothing (the health check also names the missing item)
    if special and special.item and special.item ~= "" and (ItemExists == nil or ItemExists(special.item) ~= false) then
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
    TriggerClientEvent("tobsbank:lootResult", _source, bank, loot, true)
    TriggerClientEvent("tobsbank:lootup_c", -1, bank, loot)
end)

-- Sent when the player's game couldn't start the grab (the trolley wasn't there, or someone was
-- already emptying it). The trolley is free again and nothing is paid; once the grab has started
-- (tobsbank:grabStarted) or paid anything, it can't be handed back.
RegisterServerEvent("tobsbank:grabFailed")
AddEventHandler("tobsbank:grabFailed", function()
    local g = Looting[source]
    if g == nil or g.clockStarted or g.paidWorth > 0 then return end
    Looting[source] = nil
    local h = Heists[g.bank]
    if h ~= nil then h.looted[g.slot] = nil end
    TriggerClientEvent("tobsbank:lootFree", -1, g.bank, "Loot" .. g.slot:sub(-1))
end)

-- Sent when the grab animation starts. The trolley's clock starts here rather than when the server
-- said yes, because the intro animation and taking control of the trolley come first: otherwise the
-- money ran out seconds before the animation did. Only the first one counts; sending it late only
-- makes the trolley pay later, and without it the clock runs from the server's yes.
RegisterServerEvent("tobsbank:grabStarted")
AddEventHandler("tobsbank:grabStarted", function()
    local g = Looting[source]
    if g == nil or g.clockStarted then return end
    g.clockStarted = true
    g.started = GetGameTimer()
end)

-- Sent each time a pile lands in the bag (the grab animation's RELEASE_CASH_DESTROY event)
RegisterServerEvent("tobsbank:rewardCash")
AddEventHandler("tobsbank:rewardCash", function()
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
RegisterServerEvent("tobsbank:grabDone")
AddEventHandler("tobsbank:grabDone", function()
    local _source = source
    local g = Looting[_source]

    if g == nil then return end
    if IsNear(_source, TOB.Banks[g.bank][g.slot], 6.0) then
        Pay(_source, g, true)
    end
    Finish(_source, g)
end)
