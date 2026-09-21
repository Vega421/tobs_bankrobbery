-- Heist state and timeline. The server runs every step and every timer of the heist:
--   card     robber used the card; their game plays the card + laptop animation and the minigame
--   hacking  minigame passed; the hack runs for TOB.hacktime
--   vaultitem (only with TOB.VaultItem) the robber has TOB.timer seconds to use the item; the vault
--            opens TOB.VaultItemTime after it was used
--   open     vault open, trolleys and deposit boxes can be looted for TOB.timer seconds
--   closing  loot phase over; the vault closes after TOB.VaultCloseDelay seconds
--   cleanup  vault closed; the props are removed and the bank goes on cooldown
-- Players' games only ask ("I passed the minigame", "I used the thermite") and play the animations,
-- so a cheater can't skip the hack or open the vault early.

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
TOB.TrolleyCash = TOB.TrolleyCash or {min = 50000, max = 80000}
if TOB.TrolleyCash.min > TOB.TrolleyCash.max then
    print("^3[tobs_bankrobbery] TOB.TrolleyCash.min is higher than max, so they were swapped.^7")
    TOB.TrolleyCash.min, TOB.TrolleyCash.max = TOB.TrolleyCash.max, TOB.TrolleyCash.min
end
if TOB.mincash ~= nil or TOB.maxcash ~= nil or TOB.MaxPiles ~= nil then
    print("^3[tobs_bankrobbery] TOB.mincash, TOB.maxcash and TOB.MaxPiles are no longer used. Trolleys pay TOB.TrolleyCash each; see the changelog for 2.1.0.^7")
end

-- Banks with an inner gate (doors.secondloc, like Fleeca) keep it locked outside heists
function GateLockedByDefault(bank)
    return TOB.Banks[bank].doors.secondloc ~= nil
end

-- The trolley behind the inner gate (banks with doors.secondloc). Set gateTrolley on a bank to change it.
function GateTrolley(bank)
    local b = TOB.Banks[bank]
    if b.doors.secondloc == nil then return nil end
    return b.gateTrolley or "trolley3"
end

-- Door state for every bank, built from the gate and vault settings in TOB.Banks
Doors = {}
for bank, b in pairs(TOB.Banks) do
    Doors[bank] = {
        {loc = b.gate.loc, h = b.gate.h, txtloc = b.gate.txtloc, locked = GateLockedByDefault(bank)},
        {loc = b.vault.loc, txtloc = b.vault.txtloc, locked = false},
    }
    b.onaction = false
    b.lastrobbed = LoadCooldown(bank)
end

Heists = {}         -- [bank] = the running heist (see startcheck)
Looting = {}        -- [server id] = trolley grab in progress (server/loot.lua)
VaultMoved = {}     -- [bank] = GetGameTimer() of the last vault open/close, so only that move's angle is accepted
RestartSoon = false -- set when txAdmin announces a restart (SV.BlockBeforeRestart)
LastHeistEnd = LoadLastHeistEnd() -- os.time() the last heist on any bank ended (TOB.GlobalCooldown)

local CARD_TIMEOUT = 90000  -- ms the robber has for the card, the laptop and the minigame
local OWNER_RADIUS = 30.0   -- the heist leader has to stay this close to the start panel
local CLEANUP_DELAY = 10000 -- ms between the vault closing and the props being removed

local EndReasons = {
    hack_failed = "the robber failed the hack",
    vault_timeout = "the robber didn't open the vault in time",
    robber_left = "the robber left the bank",
}

function VaultItemEnabled()
    return TOB.VaultItem ~= nil and TOB.VaultItem ~= ""
end

function IsHeistOwner(src, bank)
    return Heists[bank] ~= nil and Heists[bank].owner == src
end

-- True while the heist's vault is open: opened by the heist (not just unlocked) and not closed by police
function VaultOpen(bank)
    local h = Heists[bank]
    return h ~= nil and h.vaultOpen == true and Doors[bank][2].locked == false
end

local function CooldownLeft(bank)
    return Clock(TOB.cooldown - (os.time() - TOB.Banks[bank].lastrobbed))
end

local function AnyHeistActive()
    return next(Heists) ~= nil
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

-- Adds to a player's payout for the Discord log and the loot counter. worth is the cash value of what they
-- got (also for items), cash is the money actually paid. Returns their total worth this heist.
function RecordPayout(bank, src, worth, cash, items, itemName)
    local h = Heists[bank]
    if h == nil then return worth end
    local p = h.payouts[src]
    if not p then
        p = {name = GetPlayerName(src) or tostring(src), worth = 0, cash = 0, items = {}}
        h.payouts[src] = p
    end
    p.worth = p.worth + worth
    p.cash = p.cash + cash
    if items and items > 0 and itemName then
        p.items[itemName] = (p.items[itemName] or 0) + items
    end
    return p.worth
end

local function SetStage(bank, stage, ms)
    local h = Heists[bank]
    h.stage = stage
    h.stageAt = GetGameTimer()
    h.ends = ms and (h.stageAt + ms) or nil
    if ms and (stage == "vaultitem" or stage == "open" or stage == "closing") then
        TriggerClientEvent("TOB_fh:timer", -1, bank, math.floor(ms / 1000), stage)
    end
end

function CloseVault(bank)
    if Heists[bank] ~= nil then Heists[bank].vaultOpen = false end
    Doors[bank][2].locked = true
    VaultMoved[bank] = GetGameTimer()
    TriggerClientEvent("TOB_fh:toggleVault", -1, bank, true)
end

-- Ends the heist. cooldown = false (admin reset) lets the bank be robbed again straight away.
function EndHeist(bank, reason, cooldown)
    local h = Heists[bank]
    if h ~= nil then
        local lines, totalWorth, totalCash = {}, 0, 0
        for _, p in pairs(h.payouts) do
            totalWorth = totalWorth + p.worth
            totalCash = totalCash + p.cash
            local items = {}
            for name, n in pairs(p.items) do items[#items + 1] = ("%d × %s"):format(n, name) end
            local extra = #items > 0 and (" (paid as %s)"):format(table.concat(items, ", ")) or ""
            lines[#lines + 1] = ("%s: $%s%s"):format(p.name, Money(p.worth), extra)
        end
        if TOB.LootCounter then
            for id, p in pairs(h.payouts) do
                TriggerClientEvent("TOB_fh:heistTotal", id, Money(p.worth), Money(totalWorth))
            end
        end
        if TOB.Alarm and TOB.Banks[bank].alarm then
            TriggerClientEvent("TOB_fh:alarm", -1, bank, false)
        end
        Log("Heist ended: " .. BankName(bank), ("Reason: %s\nDuration: %s\nTotal: $%s\n%s"):format(
            reason, Duration(os.time() - h.started), Money(totalWorth), #lines > 0 and table.concat(lines, "\n") or "Nobody was paid."), 15105570)
        HeistEnded(bank, reason, totalWorth)
    end

    TOB.Banks[bank].lastrobbed = cooldown == false and 0 or os.time()
    SaveCooldown(bank, TOB.Banks[bank].lastrobbed)
    if cooldown ~= false and h ~= nil then
        LastHeistEnd = os.time()
        SaveLastHeistEnd(LastHeistEnd)
    end
    TOB.Banks[bank].onaction = false
    TOB.Banks[bank].special = nil
    Heists[bank] = nil
    TriggerClientEvent("TOB_fh:bankState", -1, bank, false)
    TriggerClientEvent("TOB_fh:boxesReset", -1, bank)
    for id, g in pairs(Looting) do
        if g.bank == bank then Looting[id] = nil end
    end
    if GateLockedByDefault(bank) and not Doors[bank][1].locked then
        Doors[bank][1].locked = true
        TriggerClientEvent("TOB_fh:toggleDoor", -1, bank, true)
    end
end

-- Ends a heist that failed before the vault opened, and tells the robber why
local function FailHeist(bank, reason)
    local h = Heists[bank]
    if h == nil then return end
    if h.owner then TriggerClientEvent("TOB_fh:heistFailed", h.owner, bank, reason) end
    TriggerClientEvent("TOB_fh:cleanup", -1, bank)
    EndHeist(bank, EndReasons[reason] or reason)
end

-- The vault opens and the loot phase starts. The leader's game spawns the trolleys.
function OpenVault(bank)
    local h = Heists[bank]
    h.vaultOpen = true
    Doors[bank][2].locked = false
    VaultMoved[bank] = GetGameTimer()
    TriggerClientEvent("TOB_fh:toggleVault", -1, bank, false)
    SetStage(bank, "open", TOB.timer * 1000)
    TOB.Banks[bank].special = h.special
    TriggerClientEvent("TOB_fh:vaultOpened", h.owner, bank, h.special, h.looted)
    TriggerClientEvent("TOB_fh:startLoot_c", -1, TOB.Banks[bank], bank)
    TriggerEvent("tobs_bankrobbery:vaultOpened", bank)
end

-- Loot phase over: the vault closes after TOB.VaultCloseDelay seconds
function StartClosing(bank, reason)
    local h = Heists[bank]
    if h == nil or h.stage == "closing" or h.stage == "cleanup" then return end
    h.reason = reason
    SetStage(bank, "closing", (TOB.VaultCloseDelay or 30) * 1000)
    TriggerClientEvent("TOB_fh:closing", -1, bank, TOB.VaultCloseDelay or 30)
end

local function HackDone(bank)
    local h = Heists[bank]
    TriggerClientEvent("TOB_fh:hackDone", h.owner, bank)
    if VaultItemEnabled() then
        SetStage(bank, "vaultitem", TOB.timer * 1000)
        TriggerClientEvent("TOB_fh:awaitVaultItem", h.owner, bank)
    else
        OpenVault(bank)
    end
end

-- The robber left: the nearest crew member (not police) near the bank leads the heist instead.
-- Returns false when nobody can take over.
local function Handover(bank, oldOwner)
    local h = Heists[bank]
    local start = TOB.Banks[bank].doors.startloc
    local best, bestDist

    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= oldOwner and not Bridge.IsPolice(id) then
            local d = DistanceTo(id, start)
            if d ~= nil and d <= OWNER_RADIUS and (bestDist == nil or d < bestDist) then
                best, bestDist = id, d
            end
        end
    end
    if best == nil then return false end
    h.owner = best
    TriggerClientEvent("TOB_fh:takeover", best, bank, {
        stage = h.stage,
        itemUsed = h.itemUsedAt ~= nil,
        gateOpen = h.gateOpen == true or h.gateAt ~= nil,
        special = h.special,
        looted = h.looted,
    })
    Log("Heist handed over: " .. BankName(bank), PlayerLabel(best) .. " now leads the heist.", 16740396)
    return true
end

-- The heist leader disconnected
function OwnerLeft(bank, src)
    local h = Heists[bank]
    if h.stage == "closing" or h.stage == "cleanup" then
        h.owner = nil -- the vault closes on its own
    elseif h.stage == "card" or not Handover(bank, src) then
        if h.stage == "open" then
            h.owner = nil
            StartClosing(bank, "the robber disconnected")
        else
            h.owner = nil
            FailHeist(bank, "the robber disconnected")
        end
    end
end

-- EVENTS --

RegisterServerEvent("TOB_fh:startcheck")
AddEventHandler("TOB_fh:startcheck", function(bank)
    local _source = source

    if TOB.Banks[bank] == nil or TooSoon(_source, "start", 2000) or Bridge.IsPolice(_source) then return end
    if not IsNear(_source, TOB.Banks[bank].doors.startloc, 5.0) then
        Flag(_source, "Tried to start the heist at " .. tostring(bank) .. " from far away.")
        return
    end

    local globalLeft = (TOB.GlobalCooldown or 0) > 0 and TOB.GlobalCooldown - (os.time() - LastHeistEnd) or 0

    if RestartSoon then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("restart_soon"))
    elseif TOB.OneAtATime and AnyHeistActive() and Heists[bank] == nil then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("global_busy"))
    elseif globalLeft > 0 then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("global_cooldown", Clock(globalLeft)))
    elseif Bridge.CountPolice() < TOB.mincops then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("no_cops"))
    elseif CrewNear(bank) < (TOB.MinCrew or 1) then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("need_crew", TOB.MinCrew))
    elseif not Bridge.HasItem(_source, "id_card_f", 1) then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("no_card"))
    elseif Heists[bank] ~= nil then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("busy"))
    elseif (os.time() - TOB.cooldown) <= TOB.Banks[bank].lastrobbed then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("cooldown", CooldownLeft(bank)))
    elseif not Bridge.RemoveItem(_source, "id_card_f", 1) then
        TriggerClientEvent("TOB_fh:outcome", _source, false, L("no_card"))
    else
        local special = nil
        local kinds = {}
        for kind, _ in pairs(TOB.SpecialTrolleys or {}) do kinds[#kinds + 1] = kind end
        table.sort(kinds)
        if #kinds > 0 and math.random(100) <= (TOB.SpecialTrolleyChance or 0) then
            special = {["trolley" .. math.random(3)] = kinds[math.random(#kinds)]}
        end
        Heists[bank] = {owner = _source, started = os.time(), looted = {}, payouts = {}, boxes = {}, special = special}
        SetStage(bank, "card")
        TOB.Banks[bank].onaction = true
        -- the inner gate stays locked until the robber hacks it
        if GateLockedByDefault(bank) and not Doors[bank][1].locked then
            Doors[bank][1].locked = true
            TriggerClientEvent("TOB_fh:toggleDoor", -1, bank, true)
        end

        TriggerClientEvent("TOB_fh:outcome", _source, true, bank)
        TriggerClientEvent("TOB_fh:bankState", -1, bank, true)
        if TOB.Alarm and TOB.Banks[bank].alarm then
            TriggerClientEvent("TOB_fh:alarm", -1, bank, true)
        end
        TriggerClientEvent("TOB_fh:policenotify", -1, bank)
        Log("Heist started: " .. BankName(bank), PlayerLabel(_source) .. " started a heist.", 16740396)
        HeistStarted(bank, _source)
    end
end)

-- The robber passed the minigame: the hack runs for TOB.hacktime
RegisterServerEvent("TOB_fh:hackStarted")
AddEventHandler("TOB_fh:hackStarted", function(bank)
    local h = Heists[bank]
    if h == nil or h.owner ~= source or h.stage ~= "card" then return end
    SetStage(bank, "hacking", TOB.hacktime)
end)

-- The robber failed the minigame or was killed during the hack
RegisterServerEvent("TOB_fh:hackFailed")
AddEventHandler("TOB_fh:hackFailed", function(bank)
    local h = Heists[bank]
    if h == nil or h.owner ~= source or (h.stage ~= "card" and h.stage ~= "hacking") then return end
    FailHeist(bank, "hack_failed")
end)

RegisterServerEvent("TOB_fh:useVaultItem")
AddEventHandler("TOB_fh:useVaultItem", function(bank)
    local _source = source
    local h = Heists[bank]

    if h == nil or h.owner ~= _source or h.stage ~= "vaultitem" or h.itemUsedAt ~= nil then return end
    if not IsNear(_source, Doors[bank][2].loc, 5.0) then
        Flag(_source, "Tried to use the vault item at " .. BankName(bank) .. " from far away.")
        return
    end
    if Bridge.HasItem(_source, TOB.VaultItem, 1) and Bridge.RemoveItem(_source, TOB.VaultItem, 1) then
        h.itemUsedAt = GetGameTimer()
        TriggerClientEvent("TOB_fh:vaultItemResult", _source, bank, true)
    else
        TriggerClientEvent("TOB_fh:vaultItemResult", _source, bank, false)
    end
end)

-- Banks with doors.secondloc (Fleeca) have an inner gate the robber hacks after the vault opens.
-- The gate opens TOB.GateHackTime after the hack started.
RegisterServerEvent("TOB_fh:useGate")
AddEventHandler("TOB_fh:useGate", function(bank)
    local _source = source
    local h = Heists[bank]

    if h == nil or h.owner ~= _source or h.stage ~= "open" or h.gateAt ~= nil or TOB.Banks[bank].doors.secondloc == nil then return end
    if not IsNear(_source, TOB.Banks[bank].doors.secondloc, 5.0) then
        Flag(_source, "Tried to hack the inner gate at " .. BankName(bank) .. " from far away.")
        return
    end
    local item = TOB.GateItem
    if item ~= nil and item ~= "" then
        if not (Bridge.HasItem(_source, item, 1) and Bridge.RemoveItem(_source, item, 1)) then
            TriggerClientEvent("TOB_fh:gateResult", _source, bank, false)
            return
        end
    end
    h.gateAt = GetGameTimer()
    TriggerClientEvent("TOB_fh:gateResult", _source, bank, true)
end)

-- Thermite sparks for everyone near the vault (the robber's game asks, the server checks)
RegisterServerEvent("TOB_fh:thermiteFx")
AddEventHandler("TOB_fh:thermiteFx", function(bank, coords)
    local h = Heists[bank]

    if h == nil or h.owner ~= source or h.itemUsedAt == nil or h.fxSent then return end
    if (type(coords) ~= "vector3" and type(coords) ~= "table") or type(coords.x) ~= "number" then return end
    local c = vector3(coords.x, coords.y, coords.z)
    if #(c - vector3(Doors[bank][2].loc.x, Doors[bank][2].loc.y, Doors[bank][2].loc.z)) > 4.0 then return end
    h.fxSent = true
    TriggerClientEvent("TOB_fh:thermiteFx_c", -1, c, TOB.VaultItemTime)
end)

AddEventHandler("playerDropped", function()
    local _source = source

    Looting[_source] = nil
    DropBoxes(_source)
    ForgetPlayer(_source)
    for bank, h in pairs(Heists) do
        if h.owner == _source then
            OwnerLeft(bank, _source)
        end
    end
end)

-- What a player joining during a heist needs to take part: stage, special trolleys, taken trolleys,
-- deposit boxes and the time left on the countdown
local function RunningHeists()
    local list = {}
    for bank, h in pairs(Heists) do
        local looted, boxes = {}, {}
        for slot, _ in pairs(h.looted) do looted["Loot" .. slot:sub(-1)] = true end
        for box, state in pairs(h.boxes) do boxes[box] = state.opened and "opened" or "busy" end
        list[bank] = {
            stage = h.stage,
            vaultOpen = VaultOpen(bank),
            special = h.special,
            looted = looted,
            boxes = boxes,
            timeLeft = h.ends and math.max(0, math.floor((h.ends - GetGameTimer()) / 1000)) or nil,
        }
    end
    return list
end

Bridge.RegisterCallback("TOB_fh:getBanks", function(source, cb)
    cb(TOB.Banks, Doors, RunningHeists())
end)

-- TIMELINE --
-- Runs every second: moves each heist to its next stage when its time is up.

-- Longest a heist can possibly take; a heist running longer is ended (safety net)
local function MaxHeistSeconds()
    return math.ceil((CARD_TIMEOUT + TOB.hacktime + (TOB.VaultItemTime or 0) + CLEANUP_DELAY) / 1000)
        + TOB.timer * 2 + (TOB.VaultCloseDelay or 30) + 300
end

function HeistTick()
    local now = GetGameTimer()

    for bank, h in pairs(Heists) do
        local stage = h.stage

        if os.time() - h.started > MaxHeistSeconds() then
            TriggerClientEvent("TOB_fh:forceReset", -1, bank)
            CloseVault(bank)
            EndHeist(bank, "it ran too long and was ended automatically")
        elseif stage == "card" then
            if now - h.stageAt > CARD_TIMEOUT then FailHeist(bank, "hack_failed") end
        elseif stage == "hacking" then
            if now >= h.ends then HackDone(bank) end
        elseif stage == "vaultitem" then
            if h.itemUsedAt ~= nil then
                if now >= h.itemUsedAt + (TOB.VaultItemTime or 0) then OpenVault(bank) end
            elseif now >= h.ends then
                FailHeist(bank, "vault_timeout")
            end
        elseif stage == "open" then
            if now >= h.ends then
                StartClosing(bank, "the security timer ran out")
            elseif AllLooted(bank) and not AnyGrab(bank) then
                StartClosing(bank, "all trolleys were looted")
            end
        elseif stage == "closing" then
            if now >= h.ends then
                CloseVault(bank)
                SetStage(bank, "cleanup", CLEANUP_DELAY)
            end
        elseif stage == "cleanup" then
            if now >= h.ends then
                TriggerClientEvent("TOB_fh:cleanup", -1, bank)
                EndHeist(bank, h.reason or "finished")
            end
        end

        h = Heists[bank]
        if h ~= nil then
            -- inner gate: opens TOB.GateHackTime after the robber started hacking it
            if h.gateAt ~= nil and not h.gateOpen and now >= h.gateAt + (TOB.GateHackTime or 0) then
                h.gateOpen = true
                Doors[bank][1].locked = false
                TriggerClientEvent("TOB_fh:toggleDoor", -1, bank, false)
                if h.owner then TriggerClientEvent("TOB_fh:gateOpened", h.owner, bank) end
            end
            -- the leader has to stay at the bank
            if h.owner ~= nil and (h.stage == "hacking" or h.stage == "vaultitem" or h.stage == "open")
                and not IsNear(h.owner, TOB.Banks[bank].doors.startloc, OWNER_RADIUS) then
                if h.stage == "open" then
                    StartClosing(bank, "the robber left the bank")
                else
                    FailHeist(bank, "robber_left")
                end
            end
        end
    end
    DropStaleGrabs(now)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        HeistTick()
    end
end)
