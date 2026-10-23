-- Shared client state and helpers: notifications, progress bars, minigames, prompts, drawing and models.

Check = {}          -- [bank] = true while this player leads a heist there
LootCheck = {}      -- [bank] = {Loot1, Loot2, Loot3}: trolleys already taken
LootActive = {}     -- [bank] = true from the vault opening until it closes (deposit boxes)
LootOpen = {}       -- [bank] = true while trolleys can be looted
AwaitingVault = {}  -- [bank] = true while the leader still has to use TOB.VaultItem
AwaitingGate = {}   -- [bank] = true while the leader can hack the inner gate (banks with doors.secondloc)
LootSpecial = {}    -- [bank] = special trolleys in the running heist, e.g. {trolley2 = "gold"}
BoxState = {}       -- [bank] = {[box] = "busy" or "opened"}
TimerEnds = {}      -- [bank] = GetGameTimer() when the shown countdown ends
GrabbedNow = 0      -- cash grabbed from the current trolley (loot counter)
GrabbedItems = 0    -- items grabbed from it (gold bars, diamonds), and their label
GrabbedItemLabel = nil
Doors = {}
Ready = false       -- banks loaded from the server
DisableInput = false
Leading = nil       -- the bank this player leads a heist at
DoorBusy = false

-- NOTIFICATIONS AND PROGRESS --

-- Notifications. Pick a system with TOB.Notify in config/config.lua.
function Notify(ntype, msg, duration)
    duration = duration or 5000
    local mode = TOB.Notify

    if mode == "auto" then
        if GetResourceState("ox_lib") == "started" then
            mode = "ox_lib"
        elseif GetResourceState("mythic_notify") == "started" then
            mode = "mythic_notify"
        else
            mode = Bridge.FrameworkNotify and "framework" or "native"
        end
    end

    if mode == "ox_lib" then
        TriggerEvent("ox_lib:notify", {title = TOB.NotifyTitle, description = msg, type = ntype, duration = duration})
    elseif mode == "mythic_notify" then
        exports["mythic_notify"]:SendAlert(ntype == "warning" and "error" or ntype, msg, duration)
    elseif mode == "framework" then
        Bridge.FrameworkNotify(msg, ntype)
    else
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- Progress bars. Pick a system with TOB.Progress in config/config.lua. Waits until the bar is done
-- and returns false if it was interrupted (for example because the player died).
-- "auto": ox_lib, else QBCore's progressbar, else progressBars, else no bar (the same wait, so the
-- heist's timing never depends on which bar a server has).
local function Started(name) return GetResourceState(name) == "started" end

function Progress(ms, label)
    local mode = TOB.Progress

    if mode == "auto" then
        mode = Started("ox_lib") and "ox_lib" or Started("progressbar") and "progressbar" or Started("progressBars") and "progressBars" or "none"
    end
    if mode == "ox_lib" then
        return exports.ox_lib:progressBar({duration = ms, label = label, canCancel = false}) ~= false
    end
    if mode == "progressbar" then
        -- QBCore's progressbar answers through a callback. It doesn't start (and never answers) while
        -- another bar runs, so the wait ends after the bar's own time either way.
        local done, result = false, true
        local ok = pcall(function()
            exports["progressbar"]:Progress({
                name = "tobs_bankrobbery", duration = ms, label = label, useWhileDead = false, canCancel = false,
                controlDisables = {disableMovement = false, disableCarMovement = false, disableMouse = false, disableCombat = false},
            }, function(cancelled) done, result = true, not cancelled end)
        end)
        local deadline = GetGameTimer() + ms + 1000
        while ok and not done and GetGameTimer() < deadline do Citizen.Wait(50) end
        if not ok then Citizen.Wait(ms) end
        return result and not IsEntityDead(PlayerPedId())
    end
    if mode == "progressBars" then
        exports["progressBars"]:startUI(ms, label)
    end
    Citizen.Wait(ms)
    return not IsEntityDead(PlayerPedId())
end

-- MINIGAMES --

-- Runs a server owner's minigame function. A broken function doesn't stop the heist: the error is
-- printed in F8 and the minigame counts as passed.
local function CustomMinigame(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        print("[tobs_bankrobbery] Minigame error: " .. tostring(result))
        return true
    end
    return result == true
end

-- The hacking minigame. m = the setting to play (TOB.HackMinigame when nil; client/minigames.lua passes
-- a bank's own setting): "ox_lib", "none", a function or a list of ox_lib difficulties. Returns true when passed.
function HackMinigame(bank, m)
    if m == nil then m = TOB.HackMinigame end
    if TOB.Minigame == false or m == "none" or m == false then return true end
    if type(m) == "function" then return CustomMinigame(m, bank) end
    if GetResourceState("ox_lib") ~= "started" then return true end
    local difficulty = type(m) == "table" and #m > 0 and m or TOB.MinigameDifficulty
    return exports.ox_lib:skillCheck(difficulty, TOB.MinigameKeys) == true
end

-- The drilling minigame. m = the setting to play (TOB.DrillMinigame when nil): a list of ox_lib
-- difficulties, "ox_lib", "none" or a function. Returns true when passed.
function DrillMinigame(bank, box, m)
    if m == nil then m = TOB.DrillMinigame end
    if type(m) == "function" then return CustomMinigame(m, bank, box) end
    if m == "ox_lib" then m = {"easy", "medium"} end
    if type(m) ~= "table" or #m == 0 or GetResourceState("ox_lib") ~= "started" then return true end
    return exports.ox_lib:skillCheck(m, TOB.MinigameKeys) == true
end

-- TARGETING --
-- TOB.Target "auto": ox_target if it runs, else qb-target, else "press E" prompts.

-- "ox_target", "qb-target", or nil for "press E"
function TargetSystem()
    local t = TOB.Target or "auto"
    if t == "none" then return nil end
    if t == "ox_target" or t == "qb-target" then return t end
    if Started("ox_target") then return "ox_target" end
    if Started("qb-target") then return "qb-target" end
    return nil
end

-- True when a target eye is used instead of "press E" prompts
function UseTarget()
    return TargetSystem() ~= nil
end

-- One target zone, written in ox_target's shape: {coords, radius, options = {{name, icon, label,
-- distance, canInteract, onSelect}}}. ox_target gets it straight away. qb-target zones wait for
-- FlushTargetZones, because qb-target handles overlap differently: where zones overlap it only ever
-- looks at the first one (even when that one has nothing to show), so the zones are merged and sized
-- there first.
local qbPending, qbZones, qbModels = {}, {}, {}
local QB_REACH = 2.5   -- qb-target measures from the player to the point looked at, not to the zone
local QB_MERGE = 0.6   -- zones closer than this become one zone with all their options

function AddTargetZone(zone)
    if TargetSystem() ~= "qb-target" then
        return exports.ox_target:addSphereZone(zone)
    end
    qbPending[#qbPending + 1] = zone
end

-- qb-target: registers the zones added since the last call, so that overlap works like ox_target's
-- (all options of the zones at the aimed-at point):
-- 1. zones at (almost) the same spot are merged (a Fleeca's start panel and vault door, Paleto's gate)
-- 2. overlapping zones with the same option (deposit boxes side by side) are made smaller until they
--    don't overlap: qb-target keys options by label, so one box could never show the other's
-- 3. other overlapping zones each get the other's options, so whichever one qb-target picks shows
--    everything (a deposit box next to the inner gate's panel can't hide the gate)
function FlushTargetZones()
    if TargetSystem() ~= "qb-target" then return end
    local zones = {}
    for _, z in ipairs(qbPending) do
        local into
        for _, c in ipairs(zones) do
            if #(c.coords - z.coords) < QB_MERGE then into = c break end
        end
        if into then
            into.radius = math.max(into.radius, z.radius)
            for _, o in ipairs(z.options) do into.own[#into.own + 1] = o end
        else
            local own = {}
            for _, o in ipairs(z.options) do own[#own + 1] = o end
            zones[#zones + 1] = {coords = z.coords, radius = z.radius, own = own}
        end
    end
    qbPending = {}

    local function labels(z)
        local set = {}
        for _, o in ipairs(z.own) do set[o.label] = true end
        return set
    end
    local function shareLabel(a, b)
        local la = labels(a)
        for _, o in ipairs(b.own) do if la[o.label] then return true end end
        return false
    end
    -- 2. same option: smaller until they don't overlap
    for i, a in ipairs(zones) do
        for j, b in ipairs(zones) do
            if i < j and shareLabel(a, b) then
                local d = #(a.coords - b.coords)
                if a.radius + b.radius > d - 0.05 then
                    local r = math.max(0.25, d / 2 - 0.05)
                    a.radius, b.radius = math.min(a.radius, r), math.min(b.radius, r)
                end
            end
        end
    end
    -- 3. other overlaps: each zone also carries the options of the zones it overlaps
    for i, a in ipairs(zones) do
        a.options = {}
        for _, o in ipairs(a.own) do a.options[#a.options + 1] = o end
        for j, b in ipairs(zones) do
            if i ~= j and not shareLabel(a, b) and #(a.coords - b.coords) < a.radius + b.radius then
                for _, o in ipairs(b.own) do a.options[#a.options + 1] = o end
            end
        end
    end

    for _, z in ipairs(zones) do
        -- qb-target keys options by label: two doors in one zone would hide one, so repeats get a number
        local options, seen = {}, {}
        for _, o in ipairs(z.options) do
            local label = o.label
            seen[label] = (seen[label] or 0) + 1
            if seen[label] > 1 then label = ("%s (%d)"):format(label, seen[label]) end
            options[#options + 1] = {icon = o.icon, label = label, canInteract = o.canInteract, action = o.onSelect}
        end
        local name = ("tobs_bankrobbery_%d"):format(#qbZones + 1)
        exports["qb-target"]:AddCircleZone(name, z.coords, z.radius, {name = name, debugPoly = false, useZ = true},
            {options = options, distance = QB_REACH})
        qbZones[#qbZones + 1] = name
    end
end

-- qb-target: the trolleys are targeted as objects (their models) instead of zones, so aiming at a
-- trolley always finds it, whatever zone is near. slots = {{bank, slot, pos}}; each trolley kind gets
-- its own label, and the option works out which bank and trolley the aimed-at object is.
function AddTrolleyModelTargets(slots, kinds)
    local function slotAt(entity)
        local pos, best, bestDist = GetEntityCoords(entity), nil, 1.5
        for _, s in ipairs(slots) do
            local d = #(pos - s.pos)
            if d < bestDist then best, bestDist = s, d end
        end
        return best
    end
    for _, kind in ipairs(kinds) do
        local model = TrolleyModels(kind or nil).model
        local label = LootLabel(kind or nil)
        exports["qb-target"]:AddTargetModel({model}, {distance = QB_REACH, options = {{
            icon = "fa-solid fa-sack-dollar",
            label = label,
            canInteract = function(entity)
                local s = slotAt(entity)
                if not s then return false end
                local special = LootSpecial[s.bank] and LootSpecial[s.bank]["trolley" .. s.slot] or false
                return LootOpen[s.bank] and special == kind and not LootCheck[s.bank]["Loot" .. s.slot] and not IsPoliceJob()
            end,
            action = function(entity)
                local s = slotAt(entity)
                if s then RequestLoot(s.bank, "Loot" .. s.slot) end
            end,
        }}})
        qbModels[#qbModels + 1] = {model = model, label = label}
    end
end

-- qb-target keeps a stopped resource's zones and models (ox_target drops them by itself): remove
-- ours, or a restart of this resource leaves targets behind that call into the old, stopped copy
AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, name in ipairs(qbZones) do
        pcall(function() exports["qb-target"]:RemoveZone(name) end)
    end
    for _, m in ipairs(qbModels) do
        pcall(function() exports["qb-target"]:RemoveTargetModel({m.model}, m.label) end)
    end
end)

function IsPoliceJob()
    return Bridge.IsPolice()
end

-- PROMPTS --
-- "Press E" prompts, shown with ox_lib's text UI when it's running (TOB.Prompts), otherwise as 3D text.

local promptMode = nil
function PromptMode()
    if promptMode == nil then
        local p = TOB.Prompts or "auto"
        if p == "3d" then
            promptMode = "3d"
        elseif p == "ox_lib" or GetResourceState("ox_lib") == "started" then
            promptMode = "textui"
        else
            promptMode = "3d"
        end
    end
    return promptMode
end

-- Distance at which a prompt loop has to run every frame
function PromptRange(useDist)
    return PromptMode() == "textui" and useDist + 0.5 or 5.0
end

local shownText, shownAt = nil, 0
local function ShowTextUI(text)
    shownAt = GetGameTimer()
    if shownText ~= text then
        shownText = text
        exports.ox_lib:showTextUI(text)
    end
end

-- Shows "[E] text" at pos and returns true when the player presses E within useDist.
-- dist is the player's distance to pos.
function Prompt(pos, text, dist, useDist)
    if PromptMode() == "textui" then
        if dist > useDist then return false end
        ShowTextUI("[E] " .. text)
        return IsControlJustReleased(0, 38)
    end
    if dist <= 5.0 then
        DrawText3D(pos.x, pos.y, pos.z, "[~r~E~w~] " .. text, 0.40)
    end
    return dist <= useDist and IsControlJustReleased(0, 38)
end

-- Hides the text UI shortly after no prompt asked for it
Citizen.CreateThread(function()
    while true do
        if shownText ~= nil and GetGameTimer() - shownAt > 300 then
            shownText = nil
            exports.ox_lib:hideTextUI()
        end
        Citizen.Wait(shownText and 100 or 500)
    end
end)

-- DRAWING --

function DrawText3D(x, y, z, text, scale) local onScreen, _x, _y = World3dToScreen2d(x, y, z) SetTextScale(scale, scale) SetTextFont(4) SetTextProportional(1) SetTextEntry("STRING") SetTextCentre(true) SetTextColour(255, 255, 255, 215) AddTextComponentString(text) DrawText(_x, _y) local factor = (string.len(text)) / 700 DrawRect(_x, _y + 0.0150, 0.095 + factor, 0.03, 41, 11, 41, 100) end
function DisableControl() DisableControlAction(0, 73, false) DisableControlAction(0, 24, true) DisableControlAction(0, 257, true) DisableControlAction(0, 25, true) DisableControlAction(0, 263, true) DisableControlAction(0, 32, true) DisableControlAction(0, 34, true) DisableControlAction(0, 31, true) DisableControlAction(0, 30, true) DisableControlAction(0, 45, true) DisableControlAction(0, 22, true) DisableControlAction(0, 44, true) DisableControlAction(0, 37, true) DisableControlAction(0, 23, true) DisableControlAction(0, 288, true) DisableControlAction(0, 289, true) DisableControlAction(0, 170, true) DisableControlAction(0, 167, true) DisableControlAction(0, 73, true) DisableControlAction(2, 199, true) DisableControlAction(0, 47, true) DisableControlAction(0, 264, true) DisableControlAction(0, 257, true) DisableControlAction(0, 140, true) DisableControlAction(0, 141, true) DisableControlAction(0, 142, true) DisableControlAction(0, 143, true) end

function ShowHelp(text)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function DrawCounter(text)
    SetTextFont(4)
    SetTextScale(0.7, 0.7)
    SetTextColour(114, 204, 114, 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.86)
end

-- The heist countdown (security timer, then the vault closing), bottom right
function DrawTimer(seconds)
    SetTextFont(0)
    SetTextScale(0.42, 0.42)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(("~r~%d:%02d~w~"):format(seconds // 60, seconds % 60))
    EndTextCommandDisplayText(0.682, 0.96)
end

function Money(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- MODELS AND PROPS --

function StartVec(bank)
    local s = TOB.Banks[bank].doors.startloc
    return vector3(s.x, s.y, s.z)
end

-- Models can be a name or a number (hash), for example the Great Ocean Highway Fleeca vault
function ModelHash(model)
    return type(model) == "number" and model or GetHashKey(model)
end

function GateModel(bank)
    return ModelHash(TOB.Banks[bank].gateModel or TOB.door)
end

function VaultModel(bank)
    return ModelHash(TOB.Banks[bank].vaultModel or TOB.vaultdoor)
end

function GetVaultObject(bank)
    local s = StartVec(bank)
    return GetClosestObjectOfType(s.x, s.y, s.z, 2.0, VaultModel(bank), false, false, false)
end

-- Loads a model, giving up after 5 seconds so a missing model can't freeze the script
function LoadModel(hash)
    if type(hash) == "string" then hash = GetHashKey(hash) end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Citizen.Wait(10) end
    return HasModelLoaded(hash)
end

function LoadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Citizen.Wait(10) end
end

-- Trolley, pile and empty-trolley models for a kind ("gold", "diamond" or nil for cash).
-- Falls back to the cash trolley if a special model isn't in the game files. empty = false (a
-- trolley GTA has no empty model for, like the casino diamond trolley): empty is nil, and the
-- trolley is held in the grab animation's last frame instead (HoldTrolleyEmpty in client/loot.lua).
CASH_TROLLEY = {model = GetHashKey("hei_prop_hei_cash_trolly_01"), pile = GetHashKey("hei_prop_heist_cash_pile"), empty = GetHashKey("hei_prop_hei_cash_trolly_03")}
function TrolleyModels(kind)
    local s = kind and TOB.SpecialTrolleys and TOB.SpecialTrolleys[kind]
    if not s then return CASH_TROLLEY end
    local m = {model = ModelHash(s.model), pile = ModelHash(s.pile), empty = s.empty ~= false and ModelHash(s.empty) or nil}
    if not (IsModelInCdimage(m.model) and IsModelInCdimage(m.pile) and (m.empty == nil or IsModelInCdimage(m.empty))) then
        return CASH_TROLLEY
    end
    return m
end

-- Every trolley model the script can spawn, for cleanup
function AllTrolleyModels()
    local list = {CASH_TROLLEY.model, CASH_TROLLEY.empty}
    for _, s in pairs(TOB.SpecialTrolleys or {}) do
        list[#list + 1] = ModelHash(s.model)
        if s.empty ~= false then list[#list + 1] = ModelHash(s.empty) end
    end
    return list
end

function LootLabel(kind)
    if kind and Locales.en["loot_" .. kind] then return L("loot_" .. kind) end
    return L("loot")
end

local function DeleteNear(pos, radius, model)
    local obj = GetClosestObjectOfType(pos.x, pos.y, pos.z, radius, model, false, false, false)
    if obj ~= 0 then
        NetworkRequestControlOfEntity(obj)
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

-- Removes the heist props at a bank (trolleys and the used card) for players near it
function CleanBankProps(bank)
    local b = TOB.Banks[bank]
    if b == nil or #(GetEntityCoords(PlayerPedId()) - StartVec(bank)) > 100.0 then return end
    for i = 1, 3 do
        local t = b["trolley" .. i]
        for _, model in ipairs(AllTrolleyModels()) do
            DeleteNear(t, 1.5, model)
        end
    end
    DeleteNear(b.prop.first.coords, 1.0, GetHashKey("p_ld_id_card_01"))
end
