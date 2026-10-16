-- Looting: trolley prompts, the grab animation and the loot counter. The server confirms a trolley
-- before the grab starts, and pays for the time spent grabbing.

local lootAsked = nil -- when the last trolley request was sent; the server answers every one
local LOOT_ANSWER_WAIT = 5000 -- ms: after this a lost answer no longer blocks looting
local PAY_ASK_EVERY = 1000 -- ms: while grabbing, the money is asked for at least this often
GRAB_DICT = "anim@heists@ornate_bank@grab_cash"
TrolleyDone = {} -- [bank][loot] = true: grabbed trolleys, kept looking empty (see KeepTrolleyEmpty)

-- The trolley at a spot, and its models: the kind this player expects first, then any other full
-- trolley (the server may have spawned another kind, e.g. a cash trolley for gold on game builds
-- without the gold models, or gold where this game fell back to cash). 0 when none is there.
local function FindTrolley(coords, kind)
    local tries = {TrolleyModels(kind), CASH_TROLLEY}
    for other, _ in pairs(TOB.SpecialTrolleys or {}) do tries[#tries + 1] = TrolleyModels(other) end
    for _, models in ipairs(tries) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 1.0, models.model, false, false, false)
        if obj ~= 0 then return obj, models end
    end
    return 0, nil
end

-- Holds a trolley in the last frame of the grab animation, so it looks emptied. For trolleys GTA has
-- no empty model for (the casino diamond trolley): they aren't swapped, they're held like this.
-- force stops what the trolley plays first (the grab that just ended); otherwise a trolley that is
-- still playing something (someone grabbing it, or already held) is left alone.
function HoldTrolleyEmpty(obj, force)
    if obj == 0 then return end
    if IsEntityPlayingAnim(obj, GRAB_DICT, "cart_cash_dissapear", 3) then
        if not force then return end
        StopEntityAnim(obj, "cart_cash_dissapear", GRAB_DICT, 1000.0)
    end
    LoadDict(GRAB_DICT)
    PlayEntityAnim(obj, "cart_cash_dissapear", GRAB_DICT, 1000.0, false, true, false, 0.0, 0)
    -- GTA counts the animation as playing only from the next frame: jumping to its end before that did
    -- nothing, and the trolley played the whole disappearing again (Qbox test). Wait for it first.
    local until_ = GetGameTimer() + 500
    while not IsEntityPlayingAnim(obj, GRAB_DICT, "cart_cash_dissapear", 3) and GetGameTimer() < until_ do
        Citizen.Wait(0)
    end
    -- Jump to the end, and play what's left very fast in case the jump doesn't take: the trolley stays
    -- on the last frame (empty) either way. (Freezing it with speed 0 kept it full when the jump failed.)
    SetEntityAnimCurrentTime(obj, GRAB_DICT, "cart_cash_dissapear", 0.99)
    SetEntityAnimSpeed(obj, GRAB_DICT, "cart_cash_dissapear", 100.0)
end

-- A grabbed trolley without an empty model is held empty in this player's game. Run again every
-- second while the vault is open, because GTA spawns the trolley full when it streams back in.
function KeepTrolleyEmpty(bank, loot)
    local slot = "trolley" .. loot:sub(-1)
    local t = TOB.Banks[bank] and TOB.Banks[bank][slot]
    if t == nil then return end
    local obj, models = FindTrolley(vector3(t.x, t.y, t.z), LootSpecial[bank] and LootSpecial[bank][slot])
    if obj ~= 0 and models.empty == nil then HoldTrolleyEmpty(obj) end
end

-- A grab ended (the server's word, sent to everyone)
RegisterNetEvent("tobsbank:trolleyDone")
AddEventHandler("tobsbank:trolleyDone", function(bank, loot)
    TrolleyDone[bank] = TrolleyDone[bank] or {}
    TrolleyDone[bank][loot] = true
    KeepTrolleyEmpty(bank, loot)
end)

-- Asks the server for a trolley; the grab starts when the server says yes (tobsbank:lootResult)
function RequestLoot(bank, loot)
    if DisableInput or (lootAsked and GetGameTimer() - lootAsked < LOOT_ANSWER_WAIT) then return end
    lootAsked = GetGameTimer()
    TriggerServerEvent("tobsbank:lootup", bank, loot)
end

RegisterNetEvent("tobsbank:lootResult")
AddEventHandler("tobsbank:lootResult", function(bank, loot, ok, reason)
    lootAsked = nil
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

-- A grab that couldn't start handed its trolley back: it can be looted again
RegisterNetEvent("tobsbank:lootFree")
AddEventHandler("tobsbank:lootFree", function(bank, loot)
    if LootCheck[bank] ~= nil then
        LootCheck[bank][loot] = false
    end
end)

RegisterNetEvent("tobsbank:grabbed")
AddEventHandler("tobsbank:grabbed", function(amount, _, items, label)
    GrabbedNow = GrabbedNow + amount
    -- items (gold bars, diamonds): counted by number, with the item's label
    if (tonumber(items) or 0) > 0 then
        GrabbedItems = GrabbedItems + items
        GrabbedItemLabel = label or GrabbedItemLabel
    end
end)

-- The server paid the whole trolley: the grab stops, so the animation ends with the money
RegisterNetEvent("tobsbank:trolleyEmpty")
AddEventHandler("tobsbank:trolleyEmpty", function()
    TrolleyEmptied = true
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
                for loot, _ in pairs(r.looted or {}) do
                    LootCheck[bank][loot] = true
                    TrolleyDone[bank][loot] = true
                end
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
    TrolleyDone[bank] = {}

    -- Grabbed trolleys without an empty model stay held empty, also after GTA streams them in again
    Citizen.CreateThread(function()
        while LootActive[bank] do
            for loot, _ in pairs(TrolleyDone[bank] or {}) do KeepTrolleyEmpty(bank, loot) end
            Citizen.Wait(1000)
        end
    end)
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
    local dict = GRAB_DICT
    local ped = PlayerPedId()
    local trollyobj, models = FindTrolley(trolleyCoords, kind)

    -- Trolley missing or already being grabbed: the server gets the trolley back, nothing is paid,
    -- and it can be looted again (before, it stayed taken and the heist lost it)
    if trollyobj == 0 or IsEntityPlayingAnim(trollyobj, dict, "cart_cash_dissapear", 3) then
        TriggerServerEvent("tobsbank:grabFailed")
        return
    end
    DisableInput = true
    GrabbedNow = 0
    GrabbedItems, GrabbedItemLabel = 0, nil
    TrolleyEmptied = false
    local stopGrab = false
    local grabMs = (TOB.GrabTime or 37) * 1000
    local bagHash = GetHashKey("hei_p_m_bag_var22_arm_s")

    LoadDict(dict)
    LoadModel(bagHash)
    if models.empty then LoadModel(models.empty) end
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
    -- The grab plays at the speed that empties the trolley in exactly TOB.GrabTime, so the trolley and
    -- the money run out together (at a fixed speed the trolley was empty before the time was up and
    -- the grabbing started over). GTA's animation length is read from the game; 1.3 if it can't be.
    local cartLength = GetAnimDuration(dict, "cart_cash_dissapear")
    local speed = (tonumber(cartLength) or 0) > 0 and cartLength / (grabMs / 1000) or 1.3
    local scene2 = NetworkCreateSynchronisedScene(tpos, trot, 2, false, false, 1065353216, 0, speed)

    NetworkAddPedToSynchronisedScene(ped, scene2, dict, "grab", 1.5, -4.0, 1, 16, 1148846080, 0)
    NetworkAddEntityToSynchronisedScene(bag, scene2, dict, "bag_grab", 4.0, -8.0, 1)
    NetworkAddEntityToSynchronisedScene(trollyobj, scene2, dict, "cart_cash_dissapear", 4.0, -8.0, 1)
    NetworkStartSynchronisedScene(scene2)
    -- the trolley's payout clock starts now, with the animation
    TriggerServerEvent("tobsbank:grabStarted")

    -- Grab for TOB.GrabTime seconds, or until the server says the trolley is empty. TOB.StopGrabKey
    -- stops early; the loot counter shows what's in the bag.
    local grabEnd = GetGameTimer() + grabMs
    local nextAsk = GetGameTimer() + PAY_ASK_EVERY
    while GetGameTimer() < grabEnd and not TrolleyEmptied do
        Citizen.Wait(0)
        -- Also ask for the money by time: the piles landing in the bag (an animation event) can be
        -- missed, e.g. while the game is alt-tabbed, and then the counter stopped and the server
        -- never said the trolley was empty. The server pays by time, so asking more pays no more.
        if GetGameTimer() >= nextAsk then
            nextAsk = GetGameTimer() + PAY_ASK_EVERY
            TriggerServerEvent("tobsbank:rewardCash")
        end
        if TOB.StopGrabKey then
            ShowHelp(L("stop_grab"))
            if IsDisabledControlJustPressed(0, TOB.StopGrabKey) then break end
        end
        if TOB.LootCounter then
            DrawCounter(GrabbedItems > 0 and ("%dx %s"):format(GrabbedItems, GrabbedItemLabel or "") or ("$" .. Money(GrabbedNow)))
        end
    end
    stopGrab = true
    TriggerServerEvent("tobsbank:grabDone")

    local scene3 = NetworkCreateSynchronisedScene(tpos, trot, 2, false, false, 1065353216, 0, 1.3)
    NetworkAddPedToSynchronisedScene(ped, scene3, dict, "exit", 1.5, -4.0, 1, 16, 1148846080, 0)
    NetworkAddEntityToSynchronisedScene(bag, scene3, dict, "bag_exit", 4.0, -8.0, 1)
    NetworkStartSynchronisedScene(scene3)
    if models.empty then
        -- swapped for its empty model
        local empty = CreateObject(models.empty, tpos + vector3(0.0, 0.0, -0.985), true)
        SetEntityRotation(empty, trot)
        timeout = GetGameTimer() + 3000
        while not NetworkHasControlOfEntity(trollyobj) and GetGameTimer() < timeout do
            NetworkRequestControlOfEntity(trollyobj)
            Citizen.Wait(10)
        end
        DeleteObject(trollyobj)
        PlaceObjectOnGroundProperly(empty)
    else
        -- no empty model (gold, diamonds): it stays, held in the grab animation's last frame. The grab
        -- scene is stopped first, or the trolley kept playing it and the hold didn't take.
        NetworkStopSynchronisedScene(scene2)
        HoldTrolleyEmpty(trollyobj, true)
    end
    Citizen.Wait(1800)
    DeleteObject(bag)
    SetPedComponentVariation(ped, 5, 45, 0, 0)
    -- a held trolley still plays the grab animation, so its dictionary stays loaded
    if models.empty then
        RemoveAnimDict(dict)
        SetModelAsNoLongerNeeded(models.empty)
    end
    SetModelAsNoLongerNeeded(bagHash)
    DisableInput = false
    if TOB.LootCounter then
        Citizen.Wait(500) -- let the last payment arrive
        if GrabbedItems > 0 then
            Notify("success", L("grabbed_items", GrabbedItems, GrabbedItemLabel or ""))
        elseif GrabbedNow > 0 then
            Notify("success", L("grabbed", Money(GrabbedNow)))
        end
    end
end
