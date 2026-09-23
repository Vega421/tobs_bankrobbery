-- Looting: trolley prompts, the grab animation and the loot counter. The server confirms a trolley
-- before the grab starts, and pays for the time spent grabbing.

local lootPending = false

-- Asks the server for a trolley; the grab starts when the server says yes (tobsbank:lootResult)
function RequestLoot(bank, loot)
    if lootPending or DisableInput then return end
    lootPending = true
    TriggerServerEvent("tobsbank:lootup", bank, loot)
end

RegisterNetEvent("tobsbank:lootResult")
AddEventHandler("tobsbank:lootResult", function(bank, loot, ok, reason)
    lootPending = false
    if not ok then
        if reason then Notify("error", L(reason)) end
        return
    end
    local slot = "trolley" .. loot:sub(-1)
    local t = TOB.Banks[bank][slot]
    StartGrab(bank, vector3(t.x, t.y, t.z), LootSpecial[bank] and LootSpecial[bank][slot])
end)

RegisterNetEvent("tobsbank:lootup_c")
AddEventHandler("tobsbank:lootup_c", function(bank, loot)
    if LootCheck[bank] ~= nil then
        LootCheck[bank][loot] = true
    end
end)

RegisterNetEvent("tobsbank:grabbed")
AddEventHandler("tobsbank:grabbed", function(amount)
    GrabbedNow = GrabbedNow + amount
end)

RegisterNetEvent("tobsbank:bagFull")
AddEventHandler("tobsbank:bagFull", function()
    Notify("error", L("bag_full"))
end)

RegisterNetEvent("tobsbank:heistTotal")
AddEventHandler("tobsbank:heistTotal", function(mine, crew)
    Notify("success", L("heist_total", mine, crew), 10000)
end)

-- The vault opened: everyone can loot. The prompts run while the player is near this bank.
RegisterNetEvent("tobsbank:startLoot_c")
AddEventHandler("tobsbank:startLoot_c", function(data, bank)
    StartLootPhase(data, bank)
end)

-- A player who joins during a heist takes part from where it is: taken trolleys, deposit boxes and the countdown
function JoinRunningHeists(running)
    for bank, r in pairs(running or {}) do
        if TOB.Banks[bank] ~= nil then
            if r.timeLeft ~= nil and (r.stage == "vaultitem" or r.stage == "open" or r.stage == "closing") then
                TimerEnds[bank] = GetGameTimer() + r.timeLeft * 1000
            end
            if r.vaultOpen then
                TOB.Banks[bank].special = r.special
                StartLootPhase(TOB.Banks[bank], bank)
                LootOpen[bank] = r.stage == "open"
                for loot, _ in pairs(r.looted or {}) do LootCheck[bank][loot] = true end
                BoxState[bank] = r.boxes
            end
        end
    end
end

function StartLootPhase(data, bank)
    LootCheck[bank] = {Loot1 = false, Loot2 = false, Loot3 = false}
    LootActive[bank] = true
    LootOpen[bank] = true
    LootSpecial[bank] = data.special
    if UseTarget() then return end -- ox_target zones handle the prompts

    Citizen.CreateThread(function()
        local start = StartVec(bank)

        while LootActive[bank] do
            local pedcoords = GetEntityCoords(PlayerPedId())
            local sleep = 1000

            if #(pedcoords - start) < 40 and not IsPoliceJob() and not DisableInput then
                sleep = 250
                if LootOpen[bank] then
                    for i = 1, 3 do
                        local loot = "Loot" .. i
                        local t = data["trolley" .. i]
                        if not LootCheck[bank][loot] then
                            local pos = vector3(t.x, t.y, t.z + 1)
                            local d = #(pedcoords - pos)
                            if d < PromptRange(1.0) then
                                sleep = 0
                                local kind = data.special and data.special["trolley" .. i]
                                if Prompt(pos, LootLabel(kind), d, 1.0) then
                                    RequestLoot(bank, loot)
                                end
                            end
                        end
                    end
                end
                -- Deposit boxes, while the vault is open
                if TOB.DepositBoxes and data.boxes then
                    for i, box in ipairs(data.boxes) do
                        if BoxState[bank] == nil or BoxState[bank][i] == nil then
                            local d = #(pedcoords - box)
                            if d < PromptRange(1.2) then
                                sleep = 0
                                if Prompt(box, L("drill_box"), d, 1.2) then
                                    DrillBox(bank, i)
                                end
                            end
                        end
                    end
                end
            end
            Citizen.Wait(sleep)
        end
    end)
end

-- The grab animation. Pays by asking the server each time a pile lands in the bag, and tells the
-- server when the player stops (tobsbank:grabDone).
function StartGrab(bank, trolleyCoords, kind)
    local dict = "anim@heists@ornate_bank@grab_cash"
    local ped = PlayerPedId()
    local models = TrolleyModels(kind)
    local trollyobj = GetClosestObjectOfType(trolleyCoords.x, trolleyCoords.y, trolleyCoords.z, 1.0, models.model, false, false, false)
    if trollyobj == 0 and models ~= CASH_TROLLEY then
        -- the server spawns a cash trolley for gold/diamonds on game builds without those models
        models = CASH_TROLLEY
        trollyobj = GetClosestObjectOfType(trolleyCoords.x, trolleyCoords.y, trolleyCoords.z, 1.0, models.model, false, false, false)
    end

    -- Trolley missing or already being grabbed
    if trollyobj == 0 or IsEntityPlayingAnim(trollyobj, dict, "cart_cash_dissapear", 3) then
        TriggerServerEvent("tobsbank:grabDone")
        return
    end
    DisableInput = true
    GrabbedNow = 0
    local stopGrab = false
    local grabMs = (TOB.GrabTime or 37) * 1000
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
            while not stopGrab and GetGameTimer() - startedGrabbing < grabMs do
                Citizen.Wait(0)
                DisableControlAction(0, 73, true)
                if HasAnimEventFired(ped, GetHashKey("CASH_APPEAR")) and not IsEntityVisible(grabobj) then
                    SetEntityVisible(grabobj, true, false)
                end
                if HasAnimEventFired(ped, GetHashKey("RELEASE_CASH_DESTROY")) and IsEntityVisible(grabobj) then
                    SetEntityVisible(grabobj, false, false)
                    TriggerServerEvent("tobsbank:rewardCash")
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

    -- Grab for TOB.GrabTime seconds. TOB.StopGrabKey stops early; the loot counter shows what's in the bag.
    local grabEnd = GetGameTimer() + grabMs
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
    TriggerServerEvent("tobsbank:grabDone")

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
    DisableInput = false
    if TOB.LootCounter then
        Citizen.Wait(500) -- let the last payment arrive
        if GrabbedNow > 0 then Notify("success", L("grabbed", Money(GrabbedNow))) end
    end
end
