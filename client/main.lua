-- tobs_bankrobbery client. Shared by every framework version; framework-specific code is in bridge/<framework>/client.lua.

Check = {}          -- [bank] = true while this player has started a heist there
LootCheck = {}      -- [bank] = {Stop, Loot1, Loot2, Loot3}
LootActive = {}     -- [bank] = true while the loot phase is running
AwaitingVault = {}  -- [bank] = true while the robber still has to use TOB.VaultItem
AwaitingGate = {}   -- [bank] = true while the robber can hack the inner gate (banks with doors.secondloc)
HeistSpecial = {}   -- [bank] = {trolley2 = "gold"} for the heist this player started
LootSpecial = {}    -- [bank] = special trolleys in the running loot phase (sent to everyone)
BoxState = {}       -- [bank] = {[box] = "busy" or "opened"}
GrabbedNow = 0      -- cash grabbed from the current trolley (loot counter)
Doors = {}
local ready = false
local disableinput = false
local initiator = false
local startdstcheck = false
local currentname = nil
local currentcoords = nil
local dooruse = false
local timerLeft = 0
local drilling = false

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
            mode = Bridge.NotifyFallback
        end
    end

    if mode == "ox_lib" then
        TriggerEvent("ox_lib:notify", {title = TOB.NotifyTitle, description = msg, type = ntype, duration = duration})
    elseif mode == "mythic_notify" then
        exports["mythic_notify"]:SendAlert(ntype == "warning" and "error" or ntype, msg, duration)
    elseif mode == "esx" or mode == "framework" then
        Bridge.Notify(msg)
    else
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- Progress bars. Pick a system with TOB.Progress in config/config.lua. Waits until the bar is done
-- and returns false if it was interrupted (for example because the player died).
function Progress(ms, label)
    local mode = TOB.Progress

    if mode == "auto" then
        mode = GetResourceState("ox_lib") == "started" and "ox_lib" or "progressBars"
    end
    if mode == "ox_lib" then
        return exports.ox_lib:progressBar({duration = ms, label = label, canCancel = false}) ~= false
    end
    exports["progressBars"]:startUI(ms, label)
    Citizen.Wait(ms)
    return true
end

-- The hacking minigame. Returns true when passed, or when the minigame is off or ox_lib isn't running.
function Minigame()
    if not TOB.Minigame or GetResourceState("ox_lib") ~= "started" then
        return true
    end
    return exports.ox_lib:skillCheck(TOB.MinigameDifficulty, TOB.MinigameKeys)
end

-- True when ox_target should be used instead of "press E" prompts
function UseTarget()
    if TOB.Target == "ox_target" then
        return true
    end
    return TOB.Target == "auto" and GetResourceState("ox_target") == "started"
end

function IsPoliceJob()
    return Bridge.IsPolice()
end

function DrawText3D(x, y, z, text, scale) local onScreen, _x, _y = World3dToScreen2d(x, y, z) SetTextScale(scale, scale) SetTextFont(4) SetTextProportional(1) SetTextEntry("STRING") SetTextCentre(true) SetTextColour(255, 255, 255, 215) AddTextComponentString(text) DrawText(_x, _y) local factor = (string.len(text)) / 700 DrawRect(_x, _y + 0.0150, 0.095 + factor, 0.03, 41, 11, 41, 100) end
function DisableControl() DisableControlAction(0, 73, false) DisableControlAction(0, 24, true) DisableControlAction(0, 257, true) DisableControlAction(0, 25, true) DisableControlAction(0, 263, true) DisableControlAction(0, 32, true) DisableControlAction(0, 34, true) DisableControlAction(0, 31, true) DisableControlAction(0, 30, true) DisableControlAction(0, 45, true) DisableControlAction(0, 22, true) DisableControlAction(0, 44, true) DisableControlAction(0, 37, true) DisableControlAction(0, 23, true) DisableControlAction(0, 288, true) DisableControlAction(0, 289, true) DisableControlAction(0, 170, true) DisableControlAction(0, 167, true) DisableControlAction(0, 73, true) DisableControlAction(2, 199, true) DisableControlAction(0, 47, true) DisableControlAction(0, 264, true) DisableControlAction(0, 257, true) DisableControlAction(0, 140, true) DisableControlAction(0, 141, true) DisableControlAction(0, 142, true) DisableControlAction(0, 143, true) end
function ShowTimer() SetTextFont(0) SetTextProportional(0) SetTextScale(0.42, 0.42) SetTextDropShadow(0, 0, 0, 0,255) SetTextEdge(1, 0, 0, 0, 255) SetTextEntry("STRING") AddTextComponentString("~r~"..timerLeft.."~w~") DrawText(0.682, 0.96) end

local function StartVec(bank)
    local s = TOB.Banks[bank].doors.startloc
    return vector3(s.x, s.y, s.z)
end

-- Models can be a name or a number (hash), for example the Great Ocean Highway Fleeca vault
local function ModelHash(model)
    return type(model) == "number" and model or GetHashKey(model)
end

local function GateModel(bank)
    return ModelHash(TOB.Banks[bank].gateModel or TOB.door)
end

local function VaultModel(bank)
    return ModelHash(TOB.Banks[bank].vaultModel or TOB.vaultdoor)
end

local function GetVaultObject(bank)
    local s = StartVec(bank)
    return GetClosestObjectOfType(s.x, s.y, s.z, 2.0, VaultModel(bank), false, false, false)
end

-- Loads a model, giving up after 5 seconds so a missing model can't freeze the script
local function LoadModel(hash)
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Citizen.Wait(10) end
    return HasModelLoaded(hash)
end

local function LoadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Citizen.Wait(10) end
end

-- Trolley, pile and empty-trolley models for a kind ("gold", "diamond" or nil for cash).
-- Falls back to the cash trolley if a special model isn't in the game files.
local CASH_TROLLEY = {model = GetHashKey("hei_prop_hei_cash_trolly_01"), pile = GetHashKey("hei_prop_heist_cash_pile"), empty = GetHashKey("hei_prop_hei_cash_trolly_03")}
local function TrolleyModels(kind)
    local s = kind and TOB.SpecialTrolleys and TOB.SpecialTrolleys[kind]
    if not s then return CASH_TROLLEY end
    local m = {model = ModelHash(s.model), pile = ModelHash(s.pile), empty = ModelHash(s.empty)}
    if not (IsModelInCdimage(m.model) and IsModelInCdimage(m.pile) and IsModelInCdimage(m.empty)) then
        return CASH_TROLLEY
    end
    return m
end

-- Every trolley model the script can spawn, for cleanup
local function AllTrolleyModels()
    local list = {CASH_TROLLEY.model, CASH_TROLLEY.empty}
    for _, s in pairs(TOB.SpecialTrolleys or {}) do
        list[#list + 1] = ModelHash(s.model)
        list[#list + 1] = ModelHash(s.empty)
    end
    return list
end

local function LootLabel(kind)
    if kind and Locales.en["loot_" .. kind] then return L("loot_" .. kind) end
    return L("loot")
end

local function Money(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function ShowHelp(text)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function DrawCounter(text)
    SetTextFont(4)
    SetTextScale(0.7, 0.7)
    SetTextColour(114, 204, 114, 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.86)
end

Citizen.CreateThread(function()
    while true do
        if disableinput then
            DisableControl()
            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

RegisterNetEvent("TOB_fh:lootup_c")
AddEventHandler("TOB_fh:lootup_c", function(bank, loot)
    if LootCheck[bank] ~= nil then
        LootCheck[bank][loot] = true
    end
end)

RegisterNetEvent("TOB_fh:outcome")
AddEventHandler("TOB_fh:outcome", function(ok, arg, special)
    if ok then
        Check[arg] = true
        HeistSpecial[arg] = special
        StartHeist(arg)
    else
        Notify("error", arg)
    end
end)

RegisterNetEvent("TOB_fh:startLoot_c")
AddEventHandler("TOB_fh:startLoot_c", function(data, name)
    -- Fresh loot state for every heist, so a second heist can be looted too
    LootCheck[name] = {Stop = false, Loot1 = false, Loot2 = false, Loot3 = false}
    LootActive[name] = true
    LootSpecial[name] = data.special
    Citizen.CreateThread(function()
        local useTarget = UseTarget()
        local start = vector3(data.doors.startloc.x, data.doors.startloc.y, data.doors.startloc.z)
        local ending = false

        while true do
            local pedcoords = GetEntityCoords(PlayerPedId())
            local lc = LootCheck[name]
            local sleep = 1000

            if #(pedcoords - start) < 40 then
                sleep = 250
                if not useTarget and not IsPoliceJob() then
                    for i = 1, 3 do
                        local loot = "Loot" .. i
                        local t = data["trolley" .. i]

                        if not lc[loot] then
                            local dst1 = #(pedcoords - vector3(t.x, t.y, t.z + 1))

                            if dst1 < 5 then
                                sleep = 0
                                local kind = data.special and data.special["trolley" .. i]
                                DrawText3D(t.x, t.y, t.z + 1, "[~r~E~w~] " .. LootLabel(kind), 0.40)
                                if dst1 < 1 and IsControlJustReleased(0, 38) then
                                    TriggerServerEvent("TOB_fh:lootup", name, loot)
                                    StartGrab(name, vector3(t.x, t.y, t.z), kind)
                                end
                            end
                        end
                    end
                    -- Deposit boxes, while the vault is open
                    if TOB.DepositBoxes and data.boxes and not lc.Stop then
                        for i, box in ipairs(data.boxes) do
                            if BoxState[name] == nil or BoxState[name][i] == nil then
                                local d = #(pedcoords - box)
                                if d < 3 then
                                    sleep = 0
                                    DrawText3D(box.x, box.y, box.z, "[~r~E~w~] " .. L("drill_box"), 0.35)
                                    if d < 1.2 and IsControlJustReleased(0, 38) then
                                        DrillBox(name, i)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- All trolleys looted or the heist stopped: the robber starts closing the vault.
            -- Deposit boxes stay open until the vault actually closes.
            if (lc.Stop or (lc.Loot1 and lc.Loot2 and lc.Loot3)) and not ending then
                ending = true
                if initiator and currentname == name then
                    Citizen.CreateThread(function() TriggerEvent("TOB_fh:reset", name, data) end)
                end
            end
            if lc.Stop or (ending and Doors[name] and Doors[name][2].locked) then
                lc.Stop = false
                LootActive[name] = false
                return
            end
            Citizen.Wait(sleep)
        end
    end)
end)

RegisterNetEvent("TOB_fh:stopHeist_c")
AddEventHandler("TOB_fh:stopHeist_c", function(name)
    if LootCheck[name] ~= nil then
        LootCheck[name].Stop = true
    end
end)

-- Bank alarm (banks with alarm = "..." in the config)
RegisterNetEvent("TOB_fh:alarm")
AddEventHandler("TOB_fh:alarm", function(bank, on)
    local b = TOB.Banks[bank]
    if b == nil or b.alarm == nil then return end
    if on then
        local timeout = GetGameTimer() + 5000
        while not PrepareAlarm(b.alarm) and GetGameTimer() < timeout do Citizen.Wait(100) end
        StartAlarm(b.alarm, true)
    else
        StopAlarm(b.alarm, true)
    end
end)

-- Thermite sparks, shown to everyone near the vault
RegisterNetEvent("TOB_fh:thermiteFx_c")
AddEventHandler("TOB_fh:thermiteFx_c", function(coords, duration)
    if #(GetEntityCoords(PlayerPedId()) - coords) > 80.0 then return end
    RequestNamedPtfxAsset("scr_ornate_heist")
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded("scr_ornate_heist") and GetGameTimer() < timeout do Citizen.Wait(10) end
    UseParticleFxAssetNextCall("scr_ornate_heist")
    local fx = StartParticleFxLoopedAtCoord("scr_heist_ornate_thermal_burn", coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
    Citizen.Wait(duration)
    StopParticleFxLooped(fx, false)
end)

RegisterNetEvent("TOB_fh:grabbed")
AddEventHandler("TOB_fh:grabbed", function(amount)
    GrabbedNow = GrabbedNow + amount
end)

RegisterNetEvent("TOB_fh:heistTotal")
AddEventHandler("TOB_fh:heistTotal", function(mine, crew)
    Notify("success", L("heist_total", mine, crew), 10000)
end)

RegisterNetEvent("TOB_fh:boxState")
AddEventHandler("TOB_fh:boxState", function(bank, box, state)
    BoxState[bank] = BoxState[bank] or {}
    BoxState[bank][box] = state
end)

RegisterNetEvent("TOB_fh:boxesReset")
AddEventHandler("TOB_fh:boxesReset", function(bank)
    BoxState[bank] = nil
end)

RegisterNetEvent("TOB_fh:boxReward")
AddEventHandler("TOB_fh:boxReward", function(text)
    Notify("success", text, 7000)
end)

-- DEPOSIT BOXES --

function DrillBox(bank, box)
    if drilling then return end
    TriggerServerEvent("TOB_fh:drillBox", bank, box)
end

RegisterNetEvent("TOB_fh:drillResult")
AddEventHandler("TOB_fh:drillResult", function(bank, box, ok, reason)
    if not ok then
        Notify("error", L(reason, TOB.DrillItemLabel))
        return
    end
    drilling = true
    local ped = PlayerPedId()
    local pos = TOB.Banks[bank].boxes[box]
    local here = GetEntityCoords(ped)
    local dict = "anim@heists@fleeca_bank@drilling"
    local drillHash = GetHashKey("hei_prop_heist_drill")

    SetEntityHeading(ped, GetHeadingFromVector_2d(pos.x - here.x, pos.y - here.y))
    LoadDict(dict)
    LoadModel(drillHash)
    TaskPlayAnim(ped, dict, "drill_straight_idle", 3.0, 3.0, -1, 1, 0, false, false, false)
    local drill = CreateObject(drillHash, here.x, here.y, here.z, true, true, true)
    AttachEntityToEntity(drill, ped, GetPedBoneIndex(ped, 57005), 0.14, 0, -0.01, 90.0, -90.0, 180.0, true, true, false, true, 1, true)
    local sound = GetSoundId()
    PlaySoundFromEntity(sound, "Drill", drill, "DLC_HEIST_FLEECA_SOUNDSET", true, 0)
    disableinput = true

    local ok2 = true
    if TOB.DrillMinigame and #TOB.DrillMinigame > 0 and GetResourceState("ox_lib") == "started" then
        ok2 = exports.ox_lib:skillCheck(TOB.DrillMinigame, TOB.MinigameKeys)
    end
    if ok2 then
        ok2 = Progress(TOB.DrillTime, L("drilling")) and not IsEntityDead(ped)
    else
        Notify("error", L("drill_failed"))
    end

    StopSound(sound)
    ReleaseSoundId(sound)
    StopAnimTask(ped, dict, "drill_straight_idle", 1.0)
    DeleteObject(drill)
    disableinput = false
    drilling = false
    TriggerServerEvent("TOB_fh:drillDone", bank, box, ok2)
end)

RegisterNetEvent("TOB_fh:policenotify")
AddEventHandler("TOB_fh:policenotify", function(name)
    if TOB.BuiltInPoliceAlert and IsPoliceJob() then
        local s = StartVec(name)

        Notify("warning", L("police_alert"), 10000)
        local blip = AddBlipForCoord(s.x, s.y, s.z)
        SetBlipSprite(blip, 161)
        SetBlipScale(blip, 2.0)
        SetBlipColour(blip, 1)
        PulseBlip(blip)
        Citizen.Wait(240000)
        RemoveBlip(blip)
    end
end)

-- Admin reset (TOB.ResetCommand): stop everything for this bank and remove the props
RegisterNetEvent("TOB_fh:forceReset")
AddEventHandler("TOB_fh:forceReset", function(name)
    if LootCheck[name] ~= nil then
        LootCheck[name].Stop = true
    end
    LootActive[name] = false
    AwaitingVault[name] = nil
    AwaitingGate[name] = nil
    Check[name] = false
    if currentname == name then
        initiator = false
        startdstcheck = false
        disableinput = false
        if IdProp ~= nil and DoesEntityExist(IdProp) then
            DeleteEntity(IdProp)
        end
    end
    BoxState[name] = nil
    local b = TOB.Banks[name]
    for i = 1, 3 do
        local t = b["trolley" .. i]
        for _, model in ipairs(AllTrolleyModels()) do
            local obj = GetClosestObjectOfType(t.x, t.y, t.z, 1.5, model, false, false, false)
            if obj ~= 0 then
                NetworkRequestControlOfEntity(obj)
                SetEntityAsMissionEntity(obj, true, true)
                DeleteEntity(obj)
            end
        end
    end
end)

-- DOORS --

local function DoorThreads()
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

            if IsPoliceJob() and not dooruse and not useTarget then
                local pcoords = GetEntityCoords(PlayerPedId())

                for k, v in pairs(Doors) do
                    for i = 1, 2 do
                        local dst = #(pcoords - v[i].loc)

                        if dst <= 5.0 then
                            sleep = 0
                        elseif dst <= 30.0 and sleep > 250 then
                            sleep = 250
                        end
                        if dst <= 4.0 then
                            local label = v[i].locked and L("unlock_door") or L("lock_door")
                            DrawText3D(v[i].txtloc.x, v[i].txtloc.y, v[i].txtloc.z, "[~r~E~w~] " .. label, 0.40)
                            if dst <= 1.5 and IsControlJustReleased(0, 38) then
                                ToggleDoor(k, i)
                            end
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
            local sleep = 1000
            local pcoords = GetEntityCoords(PlayerPedId())

            for k, v in pairs(Doors) do
                if v[2].state ~= nil and not dooruse and #(pcoords - v[2].loc) <= 20.0 then
                    local obj = GetVaultObject(k)
                    if obj ~= 0 then
                        SetEntityHeading(obj, v[2].state)
                    end
                end
            end
            Citizen.Wait(sleep)
        end
    end)
end

function ToggleDoor(k, i)
    dooruse = true
    if i == 2 then
        TriggerServerEvent("TOB_fh:toggleVault", k, not Doors[k][i].locked)
    else
        TriggerServerEvent("TOB_fh:toggleDoor", k, not Doors[k][i].locked)
    end
end

RegisterNetEvent("TOB_fh:toggleDoor")
AddEventHandler("TOB_fh:toggleDoor", function(key, state)
    if Doors[key] ~= nil then
        Doors[key][1].locked = state
    end
    dooruse = false
end)

RegisterNetEvent("TOB_fh:toggleVault")
AddEventHandler("TOB_fh:toggleVault", function(key, state)
    if Doors[key] == nil then return end
    local obj = GetVaultObject(key)

    Doors[key][2].locked = state
    -- Only players near the bank have the vault loaded. Everyone else just keeps the state,
    -- and gets the final door angle from the server (TOB_fh:vaultState).
    if obj == 0 then
        dooruse = false
        return
    end
    dooruse = true
    Doors[key][2].state = nil
    local step = state and 0.10 or -0.10
    for _ = 1, 900 do
        SetEntityHeading(obj, GetEntityHeading(obj) + step)
        Citizen.Wait(10)
    end
    Doors[key][2].state = GetEntityHeading(obj)
    TriggerServerEvent("TOB_fh:updateVaultState", key, Doors[key][2].state)
    dooruse = false
end)

RegisterNetEvent("TOB_fh:vaultState")
AddEventHandler("TOB_fh:vaultState", function(key, heading)
    if Doors[key] ~= nil then
        Doors[key][2].state = heading
    end
end)

-- HEIST --

AddEventHandler("TOB_fh:reset", function(name, data)
    Check[name] = false
    AwaitingGate[name] = nil
    Notify("error", L("vault_closing_soon", TOB.VaultCloseDelay))
    Citizen.Wait(TOB.VaultCloseDelay * 1000)
    Notify("error", L("vault_closing"))
    TriggerServerEvent("TOB_fh:toggleVault", name, true)
    CleanUp(data, name)
end)

local function FailHeist(name, reason)
    Notify("error", L(reason))
    Check[name] = false
    initiator = false
    AwaitingVault[name] = nil
    AwaitingGate[name] = nil
    if IdProp ~= nil and DoesEntityExist(IdProp) then
        DeleteEntity(IdProp)
    end
    TriggerServerEvent("TOB_fh:setCooldown", name, reason)
end

-- LAPTOP HACK (TOB.LaptopHack): the Pacific Standard hacking animation at the panel.
-- Returns what LaptopStop needs, or nil if the animation couldn't load.
local HACK_DICT = "anim@heists@ornate_bank@hack"
function LaptopStart(name)
    local bagHash, laptopHash, cardHash = GetHashKey("hei_p_m_bag_var22_arm_s"), GetHashKey("hei_prop_hst_laptop"), GetHashKey("hei_prop_heist_card_hack_02")
    LoadDict(HACK_DICT)
    if not (HasAnimDictLoaded(HACK_DICT) and LoadModel(bagHash) and LoadModel(laptopHash) and LoadModel(cardHash)) then
        return nil
    end
    local ped = PlayerPedId()
    local spot = TOB.Banks[name].doors.startloc.animcoords
    local origin = vector3(spot.x, spot.y, spot.z)
    local rot = vector3(0.0, 0.0, spot.h)
    local here = GetEntityCoords(ped)
    local props = {
        bag = CreateObject(bagHash, here.x, here.y, here.z, true, true, false),
        laptop = CreateObject(laptopHash, here.x, here.y, here.z, true, true, false),
        card = CreateObject(cardHash, here.x, here.y, here.z, true, true, false),
    }
    local function Scene(part, looped)
        local scene = NetworkCreateSynchronisedScene(origin.x, origin.y, origin.z, rot.x, rot.y, rot.z, 2, false, looped, 1065353216, 0, 1.3)
        NetworkAddPedToSynchronisedScene(ped, scene, HACK_DICT, part, 1.5, -4.0, 1, 16, 1148846080, 0)
        NetworkAddEntityToSynchronisedScene(props.bag, scene, HACK_DICT, part .. "_bag", 4.0, -8.0, 1)
        NetworkAddEntityToSynchronisedScene(props.laptop, scene, HACK_DICT, part .. "_laptop", 4.0, -8.0, 1)
        NetworkAddEntityToSynchronisedScene(props.card, scene, HACK_DICT, part .. "_card", 4.0, -8.0, 1)
        return scene
    end
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    NetworkStartSynchronisedScene(Scene("hack_enter", false))
    Citizen.Wait(6300)
    NetworkStartSynchronisedScene(Scene("hack_loop", true))
    return {props = props, exit = function() return Scene("hack_exit", false) end}
end

function LaptopStop(ctx)
    if ctx == nil then return end
    local scene = ctx.exit()
    NetworkStartSynchronisedScene(scene)
    Citizen.Wait(4600)
    NetworkStopSynchronisedScene(scene)
    for _, obj in pairs(ctx.props) do DeleteObject(obj) end
    SetPedComponentVariation(PlayerPedId(), 5, 45, 0, 0)
end

-- THERMITE (TOB.VaultItemAnim = "thermite"): plant a charge on the vault door and let it burn
local THERMITE_DICT = "anim@heists@ornate_bank@thermal_charge"
local function PlantThermite(name)
    local bagHash, thermiteHash = GetHashKey("hei_p_m_bag_var22_arm_s"), GetHashKey("hei_prop_heist_thermite")
    LoadDict(THERMITE_DICT)
    LoadModel(bagHash)
    LoadModel(thermiteHash)
    local ped = PlayerPedId()
    local door = Doors[name][2].txtloc
    local here = GetEntityCoords(ped)
    local heading = GetHeadingFromVector_2d(door.x - here.x, door.y - here.y)

    SetEntityHeading(ped, heading)
    Citizen.Wait(100)
    here = GetEntityCoords(ped)
    local scene = NetworkCreateSynchronisedScene(here.x, here.y, here.z, 0.0, 0.0, heading, 2, false, false, 1065353216, 0, 1.3)
    local bag = CreateObject(bagHash, here.x, here.y, here.z, true, true, false)
    SetEntityCollision(bag, false, true)
    NetworkAddPedToSynchronisedScene(ped, scene, THERMITE_DICT, "thermal_charge", 1.5, -4.0, 1, 16, 1148846080, 0)
    NetworkAddEntityToSynchronisedScene(bag, scene, THERMITE_DICT, "bag_thermal_charge", 4.0, -8.0, 1)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    NetworkStartSynchronisedScene(scene)
    Citizen.CreateThread(function() Progress(5500, L("planting_thermite")) end)
    Citizen.Wait(1500)
    local thermite = CreateObject(thermiteHash, here.x, here.y, here.z + 0.2, true, true, true)
    SetEntityCollision(thermite, false, true)
    AttachEntityToEntity(thermite, ped, GetPedBoneIndex(ped, 28422), 0, 0, 0, 0, 0, 200.0, true, true, false, true, 1, true)
    Citizen.Wait(4000)
    DeleteObject(bag)
    SetPedComponentVariation(ped, 5, 45, 0, 0)
    DetachEntity(thermite, true, true)
    FreezeEntityPosition(thermite, true)
    TriggerServerEvent("TOB_fh:thermiteFx", name, GetEntityCoords(thermite))
    NetworkStopSynchronisedScene(scene)
    TaskPlayAnim(ped, THERMITE_DICT, "cover_eyes_intro", 8.0, 8.0, 1000, 36, 1, false, false, false)
    TaskPlayAnim(ped, THERMITE_DICT, "cover_eyes_loop", 8.0, 8.0, 3000, 49, 1, false, false, false)
    Progress(TOB.VaultItemTime, L("thermite_burning"))
    ClearPedTasks(ped)
    DeleteObject(thermite)
end

function StartHeist(name)
    local data = TOB.Banks[name]

    TriggerServerEvent("TOB_fh:toggleDoor", name, true) -- make sure the gate is locked for this heist
    disableinput = true
    currentname = name
    currentcoords = StartVec(name)
    initiator = true
    -- Server owners' dispatch integration (config/config.lua). pcall so a broken hook can't stop the heist.
    local ok, err = pcall(TOB.DispatchAlert, currentcoords)
    if not ok then
        print("[tobs_bankrobbery] TOB.DispatchAlert error: " .. tostring(err))
    end
    RequestModel("p_ld_id_card_01")
    while not HasModelLoaded("p_ld_id_card_01") do
        Citizen.Wait(1)
    end
    local ped = PlayerPedId()

    SetEntityCoords(ped, data.doors.startloc.animcoords.x, data.doors.startloc.animcoords.y, data.doors.startloc.animcoords.z)
    SetEntityHeading(ped, data.doors.startloc.animcoords.h)
    IdProp = CreateObject(GetHashKey("p_ld_id_card_01"), GetEntityCoords(ped), 1, 1, 0)
    AttachEntityToEntity(IdProp, ped, GetPedBoneIndex(ped, 28422), 0.20, 0.038, 0.001, 10.0, 175.0, 0.0, true, true, false, true, 1, true)
    TaskStartScenarioInPlace(ped, "PROP_HUMAN_ATM", 0, true)
    Citizen.CreateThread(function() Progress(2000, L("using_card")) end)
    Citizen.Wait(1500)
    DetachEntity(IdProp, false, false)
    SetEntityCoords(IdProp, data.prop.first.coords, 0.0, 0.0, 0.0, false)
    SetEntityRotation(IdProp, data.prop.first.rot, 1, true)
    FreezeEntityPosition(IdProp, true)
    Citizen.Wait(500)
    ClearPedTasksImmediately(ped)
    disableinput = false
    Citizen.Wait(1000)
    local laptop = TOB.LaptopHack and LaptopStart(name) or nil
    if not Minigame() then
        LaptopStop(laptop)
        FailHeist(name, "hack_failed")
        return
    end
    -- The hack fails if the robber is killed during it
    if not Progress(TOB.hacktime, L("hacking")) or IsEntityDead(PlayerPedId()) then
        LaptopStop(laptop)
        FailHeist(name, "hack_failed")
        return
    end
    LaptopStop(laptop)
    Notify("success", L("hack_done"))
    PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET")

    if TOB.VaultItem ~= nil and TOB.VaultItem ~= "" then
        WaitForVaultItem(name)
    else
        OpenVault(name)
    end
end

function OpenVault(name)
    TriggerServerEvent("TOB_fh:toggleVault", name, false)
    startdstcheck = true
    timerLeft = TOB.timer
    Notify("error", L("security_timer", string.format("%d:%02d", math.floor(TOB.timer / 60), TOB.timer % 60)))
    SpawnTrolleys(TOB.Banks[name], name)
    if TOB.Banks[name].doors.secondloc ~= nil then
        AwaitingGate[name] = true
        Notify("inform", L("gate_hint"), 8000)
    end
end

-- Inner gate (banks with doors.secondloc): the robber hacks a second panel to reach the last trolley
function UseGate(name)
    if not AwaitingGate[name] then return end
    TriggerServerEvent("TOB_fh:useGate", name)
end

RegisterNetEvent("TOB_fh:gateResult")
AddEventHandler("TOB_fh:gateResult", function(name, ok)
    if not ok then
        Notify("error", L("no_gate_item", TOB.GateItemLabel))
        return
    end
    AwaitingGate[name] = nil
    local ped = PlayerPedId()
    local second = TOB.Banks[name].doors.secondloc

    SetEntityCoords(ped, second.animcoords.x, second.animcoords.y, second.animcoords.z)
    SetEntityHeading(ped, second.animcoords.h)
    TaskStartScenarioInPlace(ped, "PROP_HUMAN_ATM", 0, true)
    Progress(TOB.GateHackTime, L("hacking_gate"))
    ClearPedTasks(ped)
    TriggerServerEvent("TOB_fh:toggleDoor", name, false)
    Notify("success", L("gate_open"))
end)

-- Extra vault step (TOB.VaultItem): the robber has TOB.timer seconds to use the item on the vault door
function WaitForVaultItem(name)
    AwaitingVault[name] = true
    Notify("inform", L("use_vault_item", TOB.VaultItemLabel), 10000)
    Citizen.CreateThread(function()
        local deadline = GetGameTimer() + TOB.timer * 1000

        while AwaitingVault[name] do
            if GetGameTimer() > deadline or #(GetEntityCoords(PlayerPedId()) - currentcoords) > 30.0 then
                FailHeist(name, "vault_timeout")
                return
            end
            Citizen.Wait(500)
        end
    end)
end

function UseVaultItem(name)
    if not AwaitingVault[name] then return end
    TriggerServerEvent("TOB_fh:useVaultItem", name)
end

RegisterNetEvent("TOB_fh:vaultItemResult")
AddEventHandler("TOB_fh:vaultItemResult", function(name, ok)
    if not ok then
        Notify("error", L("no_vault_item", TOB.VaultItemLabel))
        return
    end
    AwaitingVault[name] = nil
    local ped = PlayerPedId()

    if TOB.VaultItemAnim == "thermite" then
        PlantThermite(name)
    else
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_WELDING", 0, true)
        Progress(TOB.VaultItemTime, L("using_vault_item"))
        ClearPedTasks(ped)
    end
    OpenVault(name)
end)

function CleanUp(data, name)
    Citizen.Wait(10000)
    for i = 1, 3, 1 do
        for _, model in ipairs(AllTrolleyModels()) do
            local obj = GetClosestObjectOfType(data.objects[i].x, data.objects[i].y, data.objects[i].z, 0.75, model, false, false, false)

            if DoesEntityExist(obj) then
                DeleteEntity(obj)
            end
        end
    end
    if IdProp ~= nil and DoesEntityExist(IdProp) then
        DeleteEntity(IdProp)
    end
    TriggerServerEvent("TOB_fh:setCooldown", name)
    initiator = false
end

function SpawnTrolleys(data, name)
    local special = HeistSpecial[name] or {}
    for i = 1, 3 do
        local t = data["trolley" .. i]
        local models = TrolleyModels(special["trolley" .. i])
        LoadModel(models.model)
        local trolley = CreateObject(models.model, t.x, t.y, t.z, 1, 1, 0)

        SetEntityHeading(trolley, GetEntityHeading(trolley) + t.h)
    end
    if next(special) ~= nil then
        Notify("inform", L("special_trolley"), 7000)
    end
    -- The server decides who can loot (everyone near the bank)
    TriggerServerEvent("TOB_fh:startLoot", nil, name)
end

function StartGrab(name, trolleyCoords, kind)
    local dict = "anim@heists@ornate_bank@grab_cash"
    local ped = PlayerPedId()
    local models = TrolleyModels(kind)
    local trollyobj = GetClosestObjectOfType(trolleyCoords or GetEntityCoords(ped), 1.0, models.model, false, false, false)

    -- Trolley gone (someone else grabbed it) or already being grabbed
    if trollyobj == 0 or IsEntityPlayingAnim(trollyobj, dict, "cart_cash_dissapear", 3) then
        return
    end
    disableinput = true
    GrabbedNow = 0
    local stopGrab = false
    local bagHash = GetHashKey("hei_p_m_bag_var22_arm_s")

    LoadDict(dict)
    LoadModel(bagHash)
    LoadModel(models.empty)
    LoadModel(models.pile)

    -- Shows the pile in the hand and asks the server to pay each time one is dropped in the bag
    local function PilesInHand()
        local grabobj = CreateObject(models.pile, GetEntityCoords(ped), true)

        FreezeEntityPosition(grabobj, true)
        SetEntityInvincible(grabobj, true)
        SetEntityNoCollisionEntity(grabobj, ped)
        SetEntityVisible(grabobj, false, false)
        AttachEntityToEntity(grabobj, ped, GetPedBoneIndex(ped, 60309), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0, true)
        local startedGrabbing = GetGameTimer()

        Citizen.CreateThread(function()
            while not stopGrab and GetGameTimer() - startedGrabbing < 37000 do
                Citizen.Wait(0)
                DisableControlAction(0, 73, true)
                if HasAnimEventFired(ped, GetHashKey("CASH_APPEAR")) and not IsEntityVisible(grabobj) then
                    SetEntityVisible(grabobj, true, false)
                end
                if HasAnimEventFired(ped, GetHashKey("RELEASE_CASH_DESTROY")) and IsEntityVisible(grabobj) then
                    SetEntityVisible(grabobj, false, false)
                    TriggerServerEvent("TOB_fh:rewardCash")
                end
            end
            DeleteObject(grabobj)
        end)
    end

    local timeout = GetGameTimer() + 3000
    while not NetworkHasControlOfEntity(trollyobj) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(trollyobj)
        Citizen.Wait(10)
    end
    local bag = CreateObject(bagHash, GetEntityCoords(ped), true, false, false)
    local tpos, trot = GetEntityCoords(trollyobj), GetEntityRotation(trollyobj)
    local scene1 = NetworkCreateSynchronisedScene(tpos, trot, 2, false, false, 1065353216, 0, 1.3)

    NetworkAddPedToSynchronisedScene(ped, scene1, dict, "intro", 1.5, -4.0, 1, 16, 1148846080, 0)
    NetworkAddEntityToSynchronisedScene(bag, scene1, dict, "bag_intro", 4.0, -8.0, 1)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    NetworkStartSynchronisedScene(scene1)
    Citizen.Wait(1500)
    PilesInHand()
    local scene2 = NetworkCreateSynchronisedScene(tpos, trot, 2, false, false, 1065353216, 0, 1.3)

    NetworkAddPedToSynchronisedScene(ped, scene2, dict, "grab", 1.5, -4.0, 1, 16, 1148846080, 0)
    NetworkAddEntityToSynchronisedScene(bag, scene2, dict, "bag_grab", 4.0, -8.0, 1)
    NetworkAddEntityToSynchronisedScene(trollyobj, scene2, dict, "cart_cash_dissapear", 4.0, -8.0, 1)
    NetworkStartSynchronisedScene(scene2)

    -- Grab for up to 37 s. TOB.StopGrabKey stops early; the loot counter shows what's in the bag.
    local grabEnd = GetGameTimer() + 37000
    while GetGameTimer() < grabEnd do
        Citizen.Wait(0)
        if TOB.StopGrabKey then
            ShowHelp(L("stop_grab"))
            if IsDisabledControlJustPressed(0, TOB.StopGrabKey) then break end
        end
        if TOB.LootCounter then
            DrawCounter("$" .. Money(GrabbedNow))
        end
    end
    stopGrab = true

    local scene3 = NetworkCreateSynchronisedScene(tpos, trot, 2, false, false, 1065353216, 0, 1.3)
    NetworkAddPedToSynchronisedScene(ped, scene3, dict, "exit", 1.5, -4.0, 1, 16, 1148846080, 0)
    NetworkAddEntityToSynchronisedScene(bag, scene3, dict, "bag_exit", 4.0, -8.0, 1)
    NetworkStartSynchronisedScene(scene3)
    local empty = CreateObject(models.empty, tpos + vector3(0.0, 0.0, -0.985), true)
    SetEntityRotation(empty, trot)
    timeout = GetGameTimer() + 3000
    while not NetworkHasControlOfEntity(trollyobj) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(trollyobj)
        Citizen.Wait(10)
    end
    DeleteObject(trollyobj)
    PlaceObjectOnGroundProperly(empty)
    Citizen.Wait(1800)
    DeleteObject(bag)
    SetPedComponentVariation(ped, 5, 45, 0, 0)
    RemoveAnimDict(dict)
    SetModelAsNoLongerNeeded(models.empty)
    SetModelAsNoLongerNeeded(bagHash)
    disableinput = false
    if TOB.LootCounter and GrabbedNow > 0 then
        Notify("success", L("grabbed", Money(GrabbedNow)))
    end
end

-- Ends the heist if the robber leaves the bank
Citizen.CreateThread(function()
    while true do
        if startdstcheck and initiator then
            if #(GetEntityCoords(PlayerPedId()) - currentcoords) > 20 then
                LootCheck[currentname].Stop = true
                startdstcheck = false
                TriggerServerEvent("TOB_fh:stopHeist", currentname)
            end
        end
        Citizen.Wait(500)
    end
end)

-- Security timer: ends the heist when it runs out
Citizen.CreateThread(function()
    while true do
        if startdstcheck and initiator then
            if timerLeft > 0 then
                timerLeft = timerLeft - 1
            else
                startdstcheck = false
                TriggerServerEvent("TOB_fh:stopHeist", currentname)
            end
        end
        Citizen.Wait(1000)
    end
end)

Citizen.CreateThread(function()
    while true do
        if startdstcheck and initiator then
            ShowTimer()
            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- STARTUP --

Bridge.Init(function()
    Bridge.TriggerCallback("TOB_fh:getBanks", function(banks, doors)
        TOB.Banks = banks
        Doors = doors
        for k, _ in pairs(TOB.Banks) do
            Check[k] = false
            LootCheck[k] = {Stop = false, Loot1 = false, Loot2 = false, Loot3 = false}
        end
        if UseTarget() then
            RegisterTargets()
        end
        DoorThreads()
        ready = true
    end)
end)

-- "Press E" prompts for robbers: start the heist and use the vault item
Citizen.CreateThread(function()
    while not ready do
        Citizen.Wait(500)
    end
    local useTarget = UseTarget()

    while true do
        local sleep = 1000

        if not IsPoliceJob() and not useTarget then
            local coords = GetEntityCoords(PlayerPedId())

            for k, v in pairs(TOB.Banks) do
                local s = v.doors.startloc
                local dst = #(coords - vector3(s.x, s.y, s.z))

                if dst <= 6 then
                    sleep = 0
                elseif dst <= 30 and sleep > 250 then
                    sleep = 250
                end
                if not v.onaction and dst <= 5 and not Check[k] then
                    DrawText3D(s.x, s.y, s.z, "[~r~E~w~] " .. L("start_heist"), 0.40)
                    if dst <= 1 and IsControlJustReleased(0, 38) then
                        TriggerServerEvent("TOB_fh:startcheck", k)
                    end
                end
                if AwaitingGate[k] then
                    local g = v.doors.secondloc
                    local gdst = #(coords - vector3(g.x, g.y, g.z))

                    if gdst <= 5 then
                        sleep = 0
                        DrawText3D(g.x, g.y, g.z, "[~r~E~w~] " .. L("hack_gate"), 0.40)
                        if gdst <= 1.2 and IsControlJustReleased(0, 38) then
                            UseGate(k)
                        end
                    end
                end
                if AwaitingVault[k] then
                    local vt = Doors[k][2].txtloc
                    local vdst = #(coords - vt)

                    if vdst <= 5 then
                        sleep = 0
                        DrawText3D(vt.x, vt.y, vt.z, "[~r~E~w~] " .. L("use_item", TOB.VaultItemLabel), 0.40)
                        if vdst <= 1.5 and IsControlJustReleased(0, 38) then
                            UseVaultItem(k)
                        end
                    end
                end
            end
        end
        Citizen.Wait(sleep)
    end
end)

-- ox_target zones, used instead of "press E" prompts when TOB.Target allows it
function RegisterTargets()
    for k, v in pairs(TOB.Banks) do
        local start = v.doors.startloc

        exports.ox_target:addSphereZone({
            coords = vector3(start.x, start.y, start.z),
            radius = 1.0,
            options = {{
                name = "tob_start_" .. k,
                icon = "fa-solid fa-id-card",
                label = L("start_heist"),
                distance = 1.5,
                canInteract = function()
                    return not IsPoliceJob() and not TOB.Banks[k].onaction and not Check[k]
                end,
                onSelect = function()
                    TriggerServerEvent("TOB_fh:startcheck", k)
                end
            }}
        })

        if v.doors.secondloc ~= nil then
            local second = v.doors.secondloc

            exports.ox_target:addSphereZone({
                coords = vector3(second.x, second.y, second.z),
                radius = 1.0,
                options = {{
                    name = "tob_gate_" .. k,
                    icon = "fa-solid fa-laptop-code",
                    label = L("hack_gate"),
                    distance = 1.5,
                    canInteract = function()
                        return AwaitingGate[k] == true
                    end,
                    onSelect = function() UseGate(k) end
                }}
            })
        end

        for i = 1, 3 do
            local t = v["trolley" .. i]
            local loot = "Loot" .. i

            exports.ox_target:addSphereZone({
                coords = vector3(t.x, t.y, t.z + 1.0),
                radius = 0.8,
                options = {{
                    name = "tob_loot_" .. k .. "_" .. i,
                    icon = "fa-solid fa-sack-dollar",
                    label = L("loot"),
                    distance = 1.5,
                    canInteract = function()
                        return LootActive[k] and not LootCheck[k][loot] and not IsPoliceJob()
                    end,
                    onSelect = function()
                        TriggerServerEvent("TOB_fh:lootup", k, loot)
                        StartGrab(k, vector3(t.x, t.y, t.z), LootSpecial[k] and LootSpecial[k]["trolley" .. i])
                    end
                }}
            })
        end
    end

    if TOB.DepositBoxes then
        for k, v in pairs(TOB.Banks) do
            for i, box in ipairs(v.boxes or {}) do
                exports.ox_target:addSphereZone({
                    coords = box,
                    radius = 0.6,
                    options = {{
                        name = "tob_box_" .. k .. "_" .. i,
                        icon = "fa-solid fa-screwdriver-wrench",
                        label = L("drill_box"),
                        distance = 1.5,
                        canInteract = function()
                            return LootActive[k] and not IsPoliceJob() and (BoxState[k] == nil or BoxState[k][i] == nil)
                        end,
                        onSelect = function() DrillBox(k, i) end
                    }}
                })
            end
        end
    end

    for k, v in pairs(Doors) do
        for i = 1, 2 do
            local options = {
                {
                    name = "tob_unlock_" .. k .. "_" .. i,
                    icon = "fa-solid fa-lock-open",
                    label = L("unlock_door"),
                    distance = 2.0,
                    canInteract = function()
                        return IsPoliceJob() and not dooruse and Doors[k][i].locked
                    end,
                    onSelect = function() ToggleDoor(k, i) end
                },
                {
                    name = "tob_lock_" .. k .. "_" .. i,
                    icon = "fa-solid fa-lock",
                    label = L("lock_door"),
                    distance = 2.0,
                    canInteract = function()
                        return IsPoliceJob() and not dooruse and not Doors[k][i].locked
                    end,
                    onSelect = function() ToggleDoor(k, i) end
                }
            }
            if i == 2 then
                options[#options + 1] = {
                    name = "tob_vaultitem_" .. k,
                    icon = "fa-solid fa-fire",
                    label = L("use_item", TOB.VaultItemLabel),
                    distance = 2.0,
                    canInteract = function()
                        return AwaitingVault[k] == true
                    end,
                    onSelect = function() UseVaultItem(k) end
                }
            end
            exports.ox_target:addSphereZone({coords = v[i].txtloc, radius = 1.0, options = options})
        end
    end
end

-- Setup helper for adding banks: prints your position and heading, ready to paste into TOB.Banks
if TOB.CoordsCommand then
    RegisterCommand(TOB.CoordsCommand, function()
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local text = ("{x = %.4f, y = %.4f, z = %.4f, h = %.4f}"):format(c.x, c.y, c.z, GetEntityHeading(ped))

        print(text)
        TriggerEvent("chat:addMessage", {args = {"tobs_bankrobbery", text}})
    end, false)
end
