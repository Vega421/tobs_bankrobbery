-- tobs_bankrobbery server. Shared by every framework version; framework-specific code is in bridge/<framework>/server.lua.

local REPO = "Vega421/tobs_bankrobbery" -- GitHub repo checked for new versions

-- CONFIG CHECK --
-- Banks with enabled = false are removed, and banks with missing settings are skipped with a
-- console warning, so one typo can't break the whole script.
local REQUIRED = {"doors", "gate", "vault", "prop", "trolley1", "trolley2", "trolley3", "objects"}
for bank, b in pairs(TOB.Banks) do
    local missing = {}
    for _, field in ipairs(REQUIRED) do
        if b[field] == nil then missing[#missing + 1] = field end
    end
    if b.doors ~= nil and b.doors.startloc == nil then missing[#missing + 1] = "doors.startloc" end
    if b.enabled == false then
        TOB.Banks[bank] = nil
    elseif #missing > 0 then
        print(("^1[tobs_bankrobbery] Bank %s is missing %s and was skipped. Check config/config.lua.^7"):format(bank, table.concat(missing, ", ")))
        TOB.Banks[bank] = nil
    end
end
if TOB.mincash > TOB.maxcash then
    print("^3[tobs_bankrobbery] TOB.mincash is higher than TOB.maxcash, so they were swapped.^7")
    TOB.mincash, TOB.maxcash = TOB.maxcash, TOB.mincash
end

-- Banks with an inner gate (doors.secondloc, like Fleeca) keep it locked outside heists
local function GateLockedByDefault(bank)
    return TOB.Banks[bank].doors.secondloc ~= nil
end

-- Door state for every bank, built from the gate and vault settings in TOB.Banks
Doors = {}
for bank, b in pairs(TOB.Banks) do
    Doors[bank] = {
        {loc = b.gate.loc, h = b.gate.h, txtloc = b.gate.txtloc, locked = GateLockedByDefault(bank)},
        {loc = b.vault.loc, txtloc = b.vault.txtloc, locked = false},
    }
end

-- Heist state lives on the server, so a cheater can't trigger payouts,
-- doors or heist events from their own game.
local Owner = {}      -- [bank] = server id of the player who started the heist
local Started = {}    -- [bank] = os.time() the heist started
local Looted = {}     -- [bank] = {Loot1 = true, ...}
local Looting = {}    -- [server id] = {bank, started, last, piles}
local Payouts = {}    -- [bank] = {[server id] = {name, cash, items, piles}}
local VaultReady = {} -- [bank] = true once TOB.VaultItem has been used
local GateReady = {}  -- [bank] = true once the robber hacked the inner gate (banks with doors.secondloc)
local LastHeistEnd = 0 -- os.time() the last heist on any bank ended (TOB.GlobalCooldown)
local RestartSoon = false -- set when txAdmin announces a restart (SV.BlockBeforeRestart)
local VaultMoved = {}  -- [bank] = GetGameTimer() of the last vault open/close, so only that move's angle is accepted
local Special = {}     -- [bank] = {trolley2 = "gold"}: special trolleys for the running heist
local Boxes = {}       -- [bank] = {[box] = {opened = true} or {busy = src, started = ms}}
local Trolleys = {Loot1 = "trolley1", Loot2 = "trolley2", Loot3 = "trolley3"}
local GRAB_WINDOW = 50000 -- ms a player can collect piles after starting a trolley (the animation is about 40 s)
local MIN_PILE_GAP = 250  -- ms between two piles

local function VaultItemEnabled()
    return TOB.VaultItem ~= nil and TOB.VaultItem ~= ""
end

local function BankName(bank)
    local b = TOB.Banks[bank]
    return b and b.label and ("%s (%s)"):format(b.label, bank) or tostring(bank)
end

-- DISCORD LOGS --

local function PlayerLabel(src)
    local name = GetPlayerName(src) or "unknown"
    local license = "unknown"
    local discord

    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:find("^license:") then license = id end
        if id:find("^discord:") then discord = id:sub(9) end
    end
    local label = ("**%s** (id %s, `%s`)"):format(name, src, license)
    if discord then
        label = label .. (" <@%s>"):format(discord)
    end
    return label
end

local function Log(title, description, color)
    print(("[tobs_bankrobbery] %s: %s"):format(title, description:gsub("%*", ""):gsub("`", "")))
    if SV.Webhook == nil or SV.Webhook == "" then return end
    PerformHttpRequest(SV.Webhook, function() end, "POST", json.encode({
        username = "tobs_bankrobbery",
        embeds = {{
            title = title,
            description = description,
            color = color,
            footer = {text = GetCurrentResourceName()},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    }), {["Content-Type"] = "application/json"})
end

-- Anti-cheat flags, at most once a minute per player and reason so a cheater can't flood the webhook
local flagged = {}
local function Flag(src, reason)
    if not SV.LogAntiCheat then return end
    local key = tostring(src) .. "|" .. reason
    if flagged[key] and os.time() - flagged[key] < 60 then return end
    flagged[key] = os.time()
    Log("Suspicious event blocked", PlayerLabel(src) .. "\n" .. reason, 15158332)
end

-- HELPERS --

-- Returns true when the player is within maxDist of pos.
-- Without OneSync the server can't see player positions, so the check is skipped.
local function IsNear(src, pos, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local coords = GetEntityCoords(ped)
    if coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0 then return true end
    return #(coords - vector3(pos.x, pos.y, pos.z)) <= maxDist
end

local function IsHeistOwner(src, bank)
    return TOB.Banks[bank] ~= nil and TOB.Banks[bank].onaction and Owner[bank] == src
end

local function Money(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function Duration(seconds)
    return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
end

-- Ends the heist. cooldown = false (admin reset) lets the bank be robbed again straight away.
local function EndHeist(bank, reason, cooldown)
    local lines = {}
    local total = 0

    for _, p in pairs(Payouts[bank] or {}) do
        total = total + p.cash
        local items = (TOB.RewardItem or "") ~= "" and (" (%d × %s)"):format(p.items, TOB.RewardItem) or ""
        lines[#lines + 1] = ("%s: $%d%s from %d piles"):format(p.name, p.cash, items, p.piles)
    end
    if Started[bank] and TOB.LootCounter then
        for id, p in pairs(Payouts[bank] or {}) do
            TriggerClientEvent("TOB_fh:heistTotal", id, Money(p.cash), Money(total))
        end
    end
    if Started[bank] and TOB.Alarm and TOB.Banks[bank].alarm then
        TriggerClientEvent("TOB_fh:alarm", -1, bank, false)
    end
    if Started[bank] then
        Log("Heist ended: " .. BankName(bank), ("Reason: %s\nDuration: %s\nTotal: $%d\n%s"):format(
            reason, Duration(os.time() - Started[bank]), total, #lines > 0 and table.concat(lines, "\n") or "Nobody was paid."), 15105570)
    end

    TOB.Banks[bank].lastrobbed = cooldown == false and 0 or os.time()
    if cooldown ~= false and Started[bank] then
        LastHeistEnd = os.time()
    end
    TOB.Banks[bank].onaction = false
    Owner[bank] = nil
    Started[bank] = nil
    Looted[bank] = nil
    Payouts[bank] = nil
    VaultReady[bank] = nil
    GateReady[bank] = nil
    Special[bank] = nil
    TOB.Banks[bank].special = nil
    if Boxes[bank] then
        Boxes[bank] = nil
        TriggerClientEvent("TOB_fh:boxesReset", -1, bank)
    end
    for id, l in pairs(Looting) do
        if l.bank == bank then Looting[id] = nil end
    end
    if GateLockedByDefault(bank) and not Doors[bank][1].locked then
        Doors[bank][1].locked = true
        TriggerClientEvent("TOB_fh:toggleDoor", -1, bank, true)
    end
end

local function CloseVault(bank)
    Doors[bank][2].locked = true
    VaultMoved[bank] = GetGameTimer()
    TriggerClientEvent("TOB_fh:toggleVault", -1, bank, true)
end

local function Clock(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(math.fmod(seconds, 60)))
end

local function CooldownLeft(bank)
    return Clock(TOB.cooldown - (os.time() - TOB.Banks[bank].lastrobbed))
end

local function AnyHeistActive()
    for _, b in pairs(TOB.Banks) do
        if b.onaction then return true end
    end
    return false
end

-- Robbers near the start panel (not police). Without OneSync every player counts.
local function CrewNear(bank)
    local count = 0
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if not Bridge.IsPolice(id) and IsNear(id, TOB.Banks[bank].doors.startloc, TOB.CrewRadius or 15.0) then
            count = count + 1
        end
    end
    return count
end

-- Adds to a player's payout for the Discord log and the loot counter. Returns their new total.
local function RecordPayout(bank, src, cash, items)
    if Payouts[bank] == nil then return cash end
    local p = Payouts[bank][src]
    if not p then
        p = {name = GetPlayerName(src) or tostring(src), cash = 0, items = 0, piles = 0}
        Payouts[bank][src] = p
    end
    p.cash = p.cash + cash
    p.items = p.items + (items or 0)
    return p.cash
end

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

local function GiveReward(src, amount)
    if TOB.RewardItem ~= nil and TOB.RewardItem ~= "" then
        local count = TOB.RewardItemCount == "cash" and amount or (tonumber(TOB.RewardItemCount) or 1)
        Bridge.AddItem(src, TOB.RewardItem, count)
        return count
    end
    Bridge.AddMoney(src, amount, TOB.black)
    return 0
end

-- EVENTS --

RegisterServerEvent("TOB_fh:startcheck")
AddEventHandler("TOB_fh:startcheck", function(bank)
    local _source = source

    if TOB.Banks[bank] == nil or Bridge.IsPolice(_source) then return end
    if not IsNear(_source, TOB.Banks[bank].doors.startloc, 5.0) then
        Flag(_source, "Tried to start the heist at " .. tostring(bank) .. " from far away.")
        return
    end

    local globalLeft = (TOB.GlobalCooldown or 0) > 0 and TOB.GlobalCooldown - (os.time() - LastHeistEnd) or 0

    if RestartSoon then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("restart_soon"))
    elseif TOB.OneAtATime and AnyHeistActive() and not TOB.Banks[bank].onaction then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("global_busy"))
    elseif globalLeft > 0 then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("global_cooldown", Clock(globalLeft)))
    elseif Bridge.CountPolice() < TOB.mincops then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("no_cops"))
    elseif CrewNear(bank) < (TOB.MinCrew or 1) then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("need_crew", TOB.MinCrew))
    elseif not Bridge.HasItem(_source, "id_card_f", 1) then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("no_card"))
    elseif TOB.Banks[bank].onaction then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("busy"))
    elseif (os.time() - TOB.cooldown) <= TOB.Banks[bank].lastrobbed then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("cooldown", CooldownLeft(bank)))
    else
        TOB.Banks[bank].onaction = true
        Owner[bank] = _source
        Started[bank] = os.time()
        Looted[bank] = {}
        Payouts[bank] = {}
        Bridge.RemoveItem(_source, "id_card_f", 1)
        Special[bank] = nil
        local kinds = {}
        for kind, _ in pairs(TOB.SpecialTrolleys or {}) do kinds[#kinds + 1] = kind end
        table.sort(kinds)
        if #kinds > 0 and math.random(100) <= (TOB.SpecialTrolleyChance or 0) then
            Special[bank] = {["trolley" .. math.random(3)] = kinds[math.random(#kinds)]}
        end
        TriggerClientEvent("TOB_fh:outcome", _source, true, bank, Special[bank])
        if TOB.Alarm and TOB.Banks[bank].alarm then
            TriggerClientEvent("TOB_fh:alarm", -1, bank, true)
        end
        TriggerClientEvent("TOB_fh:policenotify", -1, bank)
        Log("Heist started: " .. BankName(bank), PlayerLabel(_source) .. " started a heist.", 16740396)
    end
end)

RegisterServerEvent("TOB_fh:useVaultItem")
AddEventHandler("TOB_fh:useVaultItem", function(bank)
    local _source = source

    if not VaultItemEnabled() or not IsHeistOwner(_source, bank) or VaultReady[bank] then return end
    if not IsNear(_source, Doors[bank][2].loc, 5.0) then
        Flag(_source, "Tried to use the vault item at " .. tostring(bank) .. " from far away.")
        return
    end
    if Bridge.HasItem(_source, TOB.VaultItem, 1) then
        Bridge.RemoveItem(_source, TOB.VaultItem, 1)
        VaultReady[bank] = true
        TriggerClientEvent("TOB_fh:vaultItemResult", _source, bank, true)
    else
        TriggerClientEvent("TOB_fh:vaultItemResult", _source, bank, false)
    end
end)

-- Banks with doors.secondloc (Fleeca) have an inner gate the robber hacks after the vault opens
RegisterServerEvent("TOB_fh:useGate")
AddEventHandler("TOB_fh:useGate", function(bank)
    local _source = source

    if not IsHeistOwner(_source, bank) or GateReady[bank] or TOB.Banks[bank].doors.secondloc == nil then return end
    if not IsNear(_source, TOB.Banks[bank].doors.secondloc, 5.0) then
        Flag(_source, "Tried to hack the inner gate at " .. BankName(bank) .. " from far away.")
        return
    end
    local item = TOB.GateItem
    if item ~= nil and item ~= "" then
        if not Bridge.HasItem(_source, item, 1) then
            TriggerClientEvent("TOB_fh:gateResult", _source, bank, false)
            return
        end
        Bridge.RemoveItem(_source, item, 1)
    end
    GateReady[bank] = true
    TriggerClientEvent("TOB_fh:gateResult", _source, bank, true)
end)

RegisterServerEvent("TOB_fh:lootup")
AddEventHandler("TOB_fh:lootup", function(bank, trolley)
    local _source = source

    if TOB.Banks[bank] == nil or not TOB.Banks[bank].onaction or Trolleys[trolley] == nil then return end
    if Bridge.IsPolice(_source) then return end
    Looted[bank] = Looted[bank] or {}
    if Looted[bank][trolley] then return end
    if not IsNear(_source, TOB.Banks[bank][Trolleys[trolley]], 5.0) then
        Flag(_source, "Tried to loot a trolley at " .. tostring(bank) .. " from far away.")
        return
    end

    Looted[bank][trolley] = true
    Looting[_source] = {bank = bank, trolley = Trolleys[trolley], started = GetGameTimer(), last = 0, piles = 0}
    TriggerClientEvent("TOB_fh:lootup_c", -1, bank, trolley)
end)

RegisterServerEvent("TOB_fh:toggleDoor")
AddEventHandler("TOB_fh:toggleDoor", function(key, state)
    local _source = source

    if Doors[key] == nil then return end
    local police = Bridge.IsPolice(_source)
    if not (police or IsHeistOwner(_source, key)) then
        Flag(_source, "Tried to use the gate at " .. BankName(key) .. " without being police or the robber.")
        return
    end
    -- The robber can only unlock an inner gate after hacking it
    if not police and state == false and not GateReady[key] then
        Flag(_source, "Tried to open the inner gate at " .. BankName(key) .. " without hacking it.")
        return
    end
    Doors[key][1].locked = state
    TriggerClientEvent("TOB_fh:toggleDoor", -1, key, state)
end)

RegisterServerEvent("TOB_fh:toggleVault")
AddEventHandler("TOB_fh:toggleVault", function(key, state)
    local _source = source

    if Doors[key] == nil then return end
    local police = Bridge.IsPolice(_source)
    if not (police or IsHeistOwner(_source, key)) then
        Flag(_source, "Tried to use the vault at " .. tostring(key) .. " without being police or the robber.")
        return
    end
    -- With TOB.VaultItem set, the robber can only open the vault after using the item
    if not police and state == false and VaultItemEnabled() and not VaultReady[key] then
        Flag(_source, "Tried to open the vault at " .. tostring(key) .. " without using " .. TOB.VaultItem .. ".")
        return
    end
    Doors[key][2].locked = state
    VaultMoved[key] = GetGameTimer()
    TriggerClientEvent("TOB_fh:toggleVault", -1, key, state)
end)

RegisterServerEvent("TOB_fh:updateVaultState")
AddEventHandler("TOB_fh:updateVaultState", function(key, state)
    if Doors[key] == nil or type(state) ~= "number" then return end
    -- Only the first report within 20 s of a real open/close counts (the animation takes 9 s)
    if VaultMoved[key] == nil or GetGameTimer() - VaultMoved[key] > 20000 then return end
    if not IsNear(source, Doors[key][2].loc, 60.0) then return end
    VaultMoved[key] = nil
    Doors[key][2].state = state
    -- Share the final vault angle, so players who weren't nearby see it correctly later
    TriggerClientEvent("TOB_fh:vaultState", -1, key, state)
end)

RegisterServerEvent("TOB_fh:startLoot")
AddEventHandler("TOB_fh:startLoot", function(_, name)
    local _source = source

    if not IsHeistOwner(_source, name) then
        Flag(_source, "Tried to start the loot phase at " .. tostring(name) .. " without being the robber.")
        return
    end
    -- Everyone gets the loot phase, so crew members arriving later can still loot.
    -- Bank data comes from the server, and lootup checks the player is at the trolley.
    TOB.Banks[name].special = Special[name]
    TriggerClientEvent("TOB_fh:startLoot_c", -1, TOB.Banks[name], name)
end)

RegisterServerEvent("TOB_fh:stopHeist")
AddEventHandler("TOB_fh:stopHeist", function(name)
    if not IsHeistOwner(source, name) then return end
    TriggerClientEvent("TOB_fh:stopHeist_c", -1, name)
end)

RegisterServerEvent("TOB_fh:rewardCash")
AddEventHandler("TOB_fh:rewardCash", function()
    local _source = source
    local l = Looting[_source]

    if l == nil then
        Flag(_source, "Asked for heist cash without looting a trolley.")
        return
    end
    local now = GetGameTimer()
    if now - l.started > GRAB_WINDOW then return end
    if not IsNear(_source, TOB.Banks[l.bank][l.trolley], 6.0) then
        Flag(_source, "Asked for heist cash away from the trolley at " .. BankName(l.bank) .. ".")
        return
    end
    if now - l.last < MIN_PILE_GAP then
        Flag(_source, "Asked for heist cash faster than the grab animation allows.")
        return
    end
    if l.piles >= TOB.MaxPiles then
        Flag(_source, ("Hit TOB.MaxPiles (%d) on one trolley. If this happens to normal players, raise TOB.MaxPiles."):format(TOB.MaxPiles))
        return
    end
    l.piles = l.piles + 1
    l.last = now

    local amount = math.random(TOB.mincash, TOB.maxcash)
    local items = 0
    local kind = Special[l.bank] and Special[l.bank][l.trolley]
    local special = kind and TOB.SpecialTrolleys and TOB.SpecialTrolleys[kind]
    if special then
        amount = math.floor(amount * (special.multiplier or 1))
    end
    if special and special.item and special.item ~= "" then
        Bridge.AddItem(_source, special.item, 1)
        items = 1
    else
        items = GiveReward(_source, amount)
    end
    local mine = RecordPayout(l.bank, _source, amount, items)
    if Payouts[l.bank] and Payouts[l.bank][_source] then
        Payouts[l.bank][_source].piles = Payouts[l.bank][_source].piles + 1
    end
    if TOB.LootCounter then
        TriggerClientEvent("TOB_fh:grabbed", _source, amount, Money(mine))
    end
end)

-- DEPOSIT BOXES --
-- Drilled while the vault is open. The server checks the box, the player, the drill item
-- and that the drilling took as long as it should before paying.

local function VaultOpen(bank)
    return TOB.Banks[bank] ~= nil and TOB.Banks[bank].onaction and Doors[bank][2].locked == false
end

RegisterServerEvent("TOB_fh:drillBox")
AddEventHandler("TOB_fh:drillBox", function(bank, box)
    local _source = source

    if not TOB.DepositBoxes or not VaultOpen(bank) or Bridge.IsPolice(_source) then return end
    local pos = TOB.Banks[bank].boxes and TOB.Banks[bank].boxes[box]
    if pos == nil then return end
    if not IsNear(_source, pos, 3.0) then
        Flag(_source, "Tried to drill a deposit box at " .. BankName(bank) .. " from far away.")
        return
    end
    Boxes[bank] = Boxes[bank] or {}
    local state = Boxes[bank][box]
    if state and state.opened then return end
    if state and state.busy and state.busy ~= _source then
        TriggerClientEvent("TOB_fh:drillResult", _source, bank, box, false, "box_busy")
        return
    end
    if TOB.DrillItem and TOB.DrillItem ~= "" and not Bridge.HasItem(_source, TOB.DrillItem, 1) then
        TriggerClientEvent("TOB_fh:drillResult", _source, bank, box, false, "no_drill")
        return
    end
    Boxes[bank][box] = {busy = _source, started = GetGameTimer()}
    TriggerClientEvent("TOB_fh:boxState", -1, bank, box, "busy")
    TriggerClientEvent("TOB_fh:drillResult", _source, bank, box, true)
end)

RegisterServerEvent("TOB_fh:drillDone")
AddEventHandler("TOB_fh:drillDone", function(bank, box, success)
    local _source = source
    local state = Boxes[bank] and Boxes[bank][box]

    if state == nil or state.busy ~= _source or not VaultOpen(bank) then return end
    if not success then
        Boxes[bank][box] = nil
        TriggerClientEvent("TOB_fh:boxState", -1, bank, box, nil)
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
    Boxes[bank][box] = {opened = true}
    TriggerClientEvent("TOB_fh:boxState", -1, bank, box, "opened")

    local r = RollBoxReward()
    if r == nil or r.type == "nothing" then
        TriggerClientEvent("TOB_fh:boxReward", _source, L("box_empty"))
    elseif r.type == "money" then
        local amount = math.random(r.min or 0, r.max or r.min or 0)
        Bridge.AddMoney(_source, amount, TOB.black)
        RecordPayout(bank, _source, amount, 0)
        TriggerClientEvent("TOB_fh:boxReward", _source, L("box_money", Money(amount)))
    elseif r.type == "item" and r.name then
        local count = math.random(r.min or 1, r.max or r.min or 1)
        Bridge.AddItem(_source, r.name, count)
        RecordPayout(bank, _source, 0, count)
        TriggerClientEvent("TOB_fh:boxReward", _source, L("box_item", count, r.label or r.name))
    end
end)

-- Thermite sparks for everyone near the vault (the robber's game asks, the server checks)
RegisterServerEvent("TOB_fh:thermiteFx")
AddEventHandler("TOB_fh:thermiteFx", function(bank, coords)
    local _source = source

    if not IsHeistOwner(_source, bank) or not VaultReady[bank] then return end
    if (type(coords) ~= "vector3" and type(coords) ~= "table") or type(coords.x) ~= "number" then return end
    local c = vector3(coords.x, coords.y, coords.z)
    if #(c - vector3(Doors[bank][2].loc.x, Doors[bank][2].loc.y, Doors[bank][2].loc.z)) > 4.0 then return end
    TriggerClientEvent("TOB_fh:thermiteFx_c", -1, c, TOB.VaultItemTime)
end)

local EndReasons = {
    hack_failed = "the robber failed the hacking minigame",
    vault_timeout = "the robber didn't open the vault in time",
}

RegisterServerEvent("TOB_fh:setCooldown")
AddEventHandler("TOB_fh:setCooldown", function(name, reason)
    if not IsHeistOwner(source, name) then return end
    EndHeist(name, EndReasons[reason] or "finished")
end)

-- If the player who started the heist leaves, close the vault and end the heist
AddEventHandler("playerDropped", function()
    local _source = source

    Looting[_source] = nil
    for bank, list in pairs(Boxes) do
        for box, state in pairs(list) do
            if state.busy == _source then
                list[box] = nil
                TriggerClientEvent("TOB_fh:boxState", -1, bank, box, nil)
            end
        end
    end
    for key, _ in pairs(flagged) do
        if key:sub(1, #tostring(_source) + 1) == tostring(_source) .. "|" then flagged[key] = nil end
    end
    for bank, owner in pairs(Owner) do
        if owner == _source then
            TriggerClientEvent("TOB_fh:stopHeist_c", -1, bank)
            CloseVault(bank)
            EndHeist(bank, "the robber disconnected")
        end
    end
end)

-- Safety net: a heist that runs far longer than possible is ended, for example if the
-- robber's game stopped following the heist without disconnecting.
local function MaxHeistSeconds()
    return math.ceil(TOB.hacktime / 1000 + (TOB.VaultItemTime or 0) / 1000 + (TOB.GateHackTime or 0) / 1000)
        + TOB.timer * 2 + TOB.VaultCloseDelay + 300
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(30000)
        for bank, started in pairs(Started) do
            if os.time() - started > MaxHeistSeconds() then
                TriggerClientEvent("TOB_fh:stopHeist_c", -1, bank)
                TriggerClientEvent("TOB_fh:forceReset", -1, bank)
                CloseVault(bank)
                EndHeist(bank, "it ran too long and was ended automatically")
            end
        end
    end
end)

Bridge.RegisterCallback("TOB_fh:getBanks", function(source, cb)
    cb(TOB.Banks, Doors)
end)

-- RESTART PROTECTION --
-- txAdmin announces scheduled restarts; block new heists in the last SV.BlockBeforeRestart minutes
AddEventHandler("txAdmin:events:scheduledRestart", function(data)
    local minutes = SV.BlockBeforeRestart or 0
    if minutes > 0 and data and data.secondsRemaining and data.secondsRemaining <= minutes * 60 and not RestartSoon then
        RestartSoon = true
        Log("Heists blocked", ("Server restart in %d minutes. New heists are blocked until the restart."):format(math.ceil(data.secondsRemaining / 60)), 9807270)
    end
end)

AddEventHandler("txAdmin:events:scheduledRestartSkipped", function()
    RestartSoon = false
end)

-- ADMIN RESET --
-- /tobreset [bank]  (no bank = all banks). Needs: add_ace group.admin command.tobreset allow
RegisterCommand(SV.ResetCommand, function(src, args)
    local who = src == 0 and "the server console" or PlayerLabel(src)
    local count = 0

    for bank, _ in pairs(TOB.Banks) do
        if args[1] == nil or args[1] == bank then
            TriggerClientEvent("TOB_fh:stopHeist_c", -1, bank)
            TriggerClientEvent("TOB_fh:forceReset", -1, bank)
            CloseVault(bank)
            Doors[bank][1].locked = GateLockedByDefault(bank)
            TriggerClientEvent("TOB_fh:toggleDoor", -1, bank, Doors[bank][1].locked)
            EndHeist(bank, "reset by an admin", false)
            count = count + 1
        end
    end
    local msg = count > 0 and ("Reset %d bank(s)."):format(count) or ("No bank called %s."):format(args[1])
    if src == 0 then
        print("[tobs_bankrobbery] " .. msg)
    else
        TriggerClientEvent("TOB_fh:outcome", src, false, msg)
    end
    if count > 0 then
        Log("Heist reset", who .. " reset " .. (args[1] or "all banks") .. ".", 3447003)
    end
end, true)

-- UPDATE CHECK --

local function IsNewer(latest, current)
    local a, b = {}, {}
    for n in latest:gmatch("%d+") do a[#a + 1] = tonumber(n) end
    for n in current:gmatch("%d+") do b[#b + 1] = tonumber(n) end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

Citizen.CreateThread(function()
    if not SV.CheckForUpdates then return end
    Citizen.Wait(5000)
    local current = GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "0.0.0"

    PerformHttpRequest(("https://api.github.com/repos/%s/releases/latest"):format(REPO), function(status, body)
        if status ~= 200 or not body then return end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= "table" or type(data.tag_name) ~= "string" then return end
        local latest = data.tag_name:gsub("^v", "")
        if IsNewer(latest, current) then
            print(("^3[tobs_bankrobbery] Version %s is available (you have %s). Download: %s^7"):format(latest, current, data.html_url))
        else
            print(("^2[tobs_bankrobbery] Version %s is up to date.^7"):format(current))
        end
    end, "GET", "", {["User-Agent"] = "tobs_bankrobbery", ["Accept"] = "application/vnd.github+json"})
end)
