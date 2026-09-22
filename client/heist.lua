-- The heist leader's side: card, laptop hack, dispatch, vault item, inner gate and taking over a heist.
-- The server decides when each step is done; this file plays the animations and asks the server.

-- DISPATCH (TOB.Dispatch) --

local function Dispatch(bank)
    local mode = TOB.Dispatch or "auto"
    if mode == "none" then return end
    if (mode == "auto" or mode == "ps-dispatch") and GetResourceState("ps-dispatch") == "started" then
        local camId = TOB.Banks[bank].camId
        local ok, err = pcall(function()
            if TOB.Banks[bank].doors.secondloc ~= nil then
                exports["ps-dispatch"]:FleecaBankRobbery(camId)
            else
                exports["ps-dispatch"]:PaletoBankRobbery(camId)
            end
        end)
        if not ok then print("[tobs_bankrobbery] ps-dispatch error: " .. tostring(err)) end
        return
    end
    if (mode == "auto" or mode == "custom") and type(TOB.DispatchAlert) == "function" then
        local ok, err = pcall(TOB.DispatchAlert, StartVec(bank), bank)
        if not ok then print("[tobs_bankrobbery] TOB.DispatchAlert error: " .. tostring(err)) end
    end
end

-- LAPTOP HACK (TOB.LaptopHack): the Pacific Standard hacking animation at the panel.
-- Returns what LaptopStop needs, or nil if the animation couldn't load.
local HACK_DICT = "anim@heists@ornate_bank@hack"
function LaptopStart(bank)
    local bagHash, laptopHash, cardHash = GetHashKey("hei_p_m_bag_var22_arm_s"), GetHashKey("hei_prop_hst_laptop"), GetHashKey("hei_prop_heist_card_hack_02")
    LoadDict(HACK_DICT)
    if not (HasAnimDictLoaded(HACK_DICT) and LoadModel(bagHash) and LoadModel(laptopHash) and LoadModel(cardHash)) then
        return nil
    end
    local ped = PlayerPedId()
    local spot = TOB.Banks[bank].doors.startloc.animcoords
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
local function PlantThermite(bank)
    local bagHash, thermiteHash = GetHashKey("hei_p_m_bag_var22_arm_s"), GetHashKey("hei_prop_heist_thermite")
    LoadDict(THERMITE_DICT)
    LoadModel(bagHash)
    LoadModel(thermiteHash)
    local ped = PlayerPedId()
    local door = Doors[bank][2].txtloc
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
    TriggerServerEvent("TOB_fh:thermiteFx", bank, GetEntityCoords(thermite))
    NetworkStopSynchronisedScene(scene)
    TaskPlayAnim(ped, THERMITE_DICT, "cover_eyes_intro", 8.0, 8.0, 1000, 36, 1, false, false, false)
    TaskPlayAnim(ped, THERMITE_DICT, "cover_eyes_loop", 8.0, 8.0, 3000, 49, 1, false, false, false)
    Progress(math.max(0, TOB.VaultItemTime - 5500), L("thermite_burning"))
    ClearPedTasks(ped)
    DeleteObject(thermite)
end

-- STARTING THE HEIST --

RegisterNetEvent("TOB_fh:outcome")
AddEventHandler("TOB_fh:outcome", function(ok, arg)
    if ok then
        StartHeist(arg)
    else
        Notify("error", arg)
    end
end)

function StartHeist(bank)
    local data = TOB.Banks[bank]

    Leading = bank
    Check[bank] = true
    DisableInput = true
    Dispatch(bank)
    local cardHash = GetHashKey("p_ld_id_card_01")
    LoadModel(cardHash)
    local ped = PlayerPedId()

    SetEntityCoords(ped, data.doors.startloc.animcoords.x, data.doors.startloc.animcoords.y, data.doors.startloc.animcoords.z)
    SetEntityHeading(ped, data.doors.startloc.animcoords.h)
    local card = CreateObject(cardHash, GetEntityCoords(ped), 1, 1, 0)
    AttachEntityToEntity(card, ped, GetPedBoneIndex(ped, 28422), 0.20, 0.038, 0.001, 10.0, 175.0, 0.0, true, true, false, true, 1, true)
    TaskStartScenarioInPlace(ped, "PROP_HUMAN_ATM", 0, true)
    Citizen.CreateThread(function() Progress(2000, L("using_card")) end)
    Citizen.Wait(1500)
    DetachEntity(card, false, false)
    SetEntityCoords(card, data.prop.first.coords, 0.0, 0.0, 0.0, false)
    SetEntityRotation(card, data.prop.first.rot, 1, true)
    FreezeEntityPosition(card, true)
    Citizen.Wait(500)
    ClearPedTasksImmediately(ped)
    DisableInput = false
    Citizen.Wait(1000)

    local laptop = TOB.LaptopHack and LaptopStart(bank) or nil
    -- the bank's own minigame (tobs_minigames), else the normal one (client/minigames.lua)
    if not BankHackMinigame(bank, function(v) return HackMinigame(bank, v) end) then
        LaptopStop(laptop)
        TriggerServerEvent("TOB_fh:hackFailed", bank)
        return
    end
    TriggerServerEvent("TOB_fh:hackStarted", bank)
    -- The hack fails if the robber is killed during it. The server opens the vault when the time is up.
    if not Progress(TOB.hacktime, L("hacking")) or IsEntityDead(PlayerPedId()) then
        LaptopStop(laptop)
        TriggerServerEvent("TOB_fh:hackFailed", bank)
        return
    end
    LaptopStop(laptop)
end

-- EVENTS FROM THE SERVER (to the leader) --

RegisterNetEvent("TOB_fh:hackDone")
AddEventHandler("TOB_fh:hackDone", function(bank)
    Notify("success", L("hack_done"))
    PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET")
end)

RegisterNetEvent("TOB_fh:heistFailed")
AddEventHandler("TOB_fh:heistFailed", function(bank, reason)
    if Locales.en[reason] then Notify("error", L(reason)) end
    Check[bank] = false
    AwaitingVault[bank] = nil
    AwaitingGate[bank] = nil
    if Leading == bank then Leading = nil end
end)

-- Extra vault step (TOB.VaultItem): the leader has TOB.timer seconds to use the item on the vault door
RegisterNetEvent("TOB_fh:awaitVaultItem")
AddEventHandler("TOB_fh:awaitVaultItem", function(bank)
    AwaitingVault[bank] = true
    Notify("inform", L("use_vault_item", TOB.VaultItemLabel), 10000)
end)

function UseVaultItem(bank)
    if not AwaitingVault[bank] then return end
    TriggerServerEvent("TOB_fh:useVaultItem", bank)
end

RegisterNetEvent("TOB_fh:vaultItemResult")
AddEventHandler("TOB_fh:vaultItemResult", function(bank, ok)
    if not ok then
        Notify("error", L("no_vault_item", TOB.VaultItemLabel))
        return
    end
    AwaitingVault[bank] = nil
    if TOB.VaultItemAnim == "thermite" then
        PlantThermite(bank)
    else
        local ped = PlayerPedId()
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_WELDING", 0, true)
        Progress(TOB.VaultItemTime, L("using_vault_item"))
        ClearPedTasks(ped)
    end
end)

-- Spawns the trolleys that aren't looted and aren't there yet (a new leader may find some already spawned)
function SpawnTrolleys(bank, special, looted)
    local data = TOB.Banks[bank]
    special = special or {}
    looted = looted or {}
    for i = 1, 3 do
        local slot = "trolley" .. i
        local t = data[slot]
        local models = TrolleyModels(special[slot])
        if not looted[slot] and GetClosestObjectOfType(t.x, t.y, t.z, 1.0, models.model, false, false, false) == 0 then
            LoadModel(models.model)
            local trolley = CreateObject(models.model, t.x, t.y, t.z, 1, 1, 0)
            SetEntityHeading(trolley, GetEntityHeading(trolley) + t.h)
        end
    end
end

-- The vault opened: the leader spawns the trolleys
RegisterNetEvent("TOB_fh:vaultOpened")
AddEventHandler("TOB_fh:vaultOpened", function(bank, special, looted, serverTrolleys)
    if not serverTrolleys then SpawnTrolleys(bank, special, looted) end -- with OneSync the server spawns them
    if special ~= nil and next(special) ~= nil then
        Notify("inform", L("special_trolley"), 7000)
    end
    Notify("error", L("security_timer", ("%d:%02d"):format(TOB.timer // 60, TOB.timer % 60)))
    if TOB.Banks[bank].doors.secondloc ~= nil then
        AwaitingGate[bank] = true
        Notify("inform", L("gate_hint"), 8000)
    end
end)

-- INNER GATE (banks with doors.secondloc) --

function UseGate(bank)
    if not AwaitingGate[bank] then return end
    TriggerServerEvent("TOB_fh:useGate", bank)
end

RegisterNetEvent("TOB_fh:gateResult")
AddEventHandler("TOB_fh:gateResult", function(bank, ok)
    if not ok then
        Notify("error", L("no_gate_item", TOB.GateItemLabel))
        return
    end
    AwaitingGate[bank] = nil
    local ped = PlayerPedId()
    local second = TOB.Banks[bank].doors.secondloc

    SetEntityCoords(ped, second.animcoords.x, second.animcoords.y, second.animcoords.z)
    SetEntityHeading(ped, second.animcoords.h)
    TaskStartScenarioInPlace(ped, "PROP_HUMAN_ATM", 0, true)
    Progress(TOB.GateHackTime, L("hacking_gate"))
    ClearPedTasks(ped)
end)

RegisterNetEvent("TOB_fh:gateOpened")
AddEventHandler("TOB_fh:gateOpened", function(bank)
    Notify("success", L("gate_open"))
end)

-- TAKING OVER: the leader disconnected and this player leads the heist now
RegisterNetEvent("TOB_fh:takeover")
AddEventHandler("TOB_fh:takeover", function(bank, info)
    Leading = bank
    Check[bank] = true
    Notify("inform", L("you_lead"), 8000)
    if info.stage == "vaultitem" and not info.itemUsed then
        AwaitingVault[bank] = true
        Notify("inform", L("use_vault_item", TOB.VaultItemLabel), 10000)
    elseif info.stage == "open" then
        if not info.serverTrolleys then SpawnTrolleys(bank, info.special, info.looted) end
        if TOB.Banks[bank].doors.secondloc ~= nil and not info.gateOpen then
            AwaitingGate[bank] = true
            Notify("inform", L("gate_hint"), 8000)
        end
    end
end)

-- END OF THE HEIST --

-- Loot phase over: the vault closes soon
RegisterNetEvent("TOB_fh:closing")
AddEventHandler("TOB_fh:closing", function(bank, seconds)
    LootOpen[bank] = false
    AwaitingGate[bank] = nil
    if #(GetEntityCoords(PlayerPedId()) - StartVec(bank)) < 40.0 then
        Notify("error", L("vault_closing_soon", seconds))
    end
end)

local function ClearHeist(bank)
    LootActive[bank] = false
    LootOpen[bank] = false
    AwaitingVault[bank] = nil
    AwaitingGate[bank] = nil
    TimerEnds[bank] = nil
    BoxState[bank] = nil
    Check[bank] = false
    if Leading == bank then Leading = nil end
end

-- The heist is over: remove the props
RegisterNetEvent("TOB_fh:cleanup")
AddEventHandler("TOB_fh:cleanup", function(bank)
    ClearHeist(bank)
    CleanBankProps(bank)
end)

-- Admin reset (SV.ResetCommand) or safety net: stop everything for this bank and remove the props
RegisterNetEvent("TOB_fh:forceReset")
AddEventHandler("TOB_fh:forceReset", function(bank)
    if Leading == bank then DisableInput = false end
    ClearHeist(bank)
    CleanBankProps(bank)
end)

-- The countdown shown to players at the bank (security timer, vault item time, vault closing)
RegisterNetEvent("TOB_fh:timer")
AddEventHandler("TOB_fh:timer", function(bank, seconds)
    TimerEnds[bank] = GetGameTimer() + seconds * 1000
end)
