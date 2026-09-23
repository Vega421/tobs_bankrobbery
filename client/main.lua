-- tobs_bankrobbery client: startup, the robber's prompts, ox_target zones, the alarm and the timer.
-- Shared by every framework; framework-specific code is in bridge/<framework>/client.lua.

-- Blocks shooting and running while an animation plays
Citizen.CreateThread(function()
    while true do
        if DisableInput then
            DisableControl()
            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- Bank alarm (banks with alarm = "..." in the config)
RegisterNetEvent("tobsbank:alarm")
AddEventHandler("tobsbank:alarm", function(bank, on)
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
RegisterNetEvent("tobsbank:thermiteFx_c")
AddEventHandler("tobsbank:thermiteFx_c", function(coords, duration)
    if #(GetEntityCoords(PlayerPedId()) - coords) > 80.0 then return end
    RequestNamedPtfxAsset("scr_ornate_heist")
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded("scr_ornate_heist") and GetGameTimer() < timeout do Citizen.Wait(10) end
    UseParticleFxAssetNextCall("scr_ornate_heist")
    local fx = StartParticleFxLoopedAtCoord("scr_heist_ornate_thermal_burn", coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
    Citizen.Wait(duration)
    StopParticleFxLooped(fx, false)
end)

-- The heist countdown, shown to robbers at the bank
Citizen.CreateThread(function()
    while true do
        local shown = false
        if next(TimerEnds) ~= nil and not IsPoliceJob() then
            local coords = GetEntityCoords(PlayerPedId())
            for bank, ends in pairs(TimerEnds) do
                local left = math.ceil((ends - GetGameTimer()) / 1000)
                if left < 0 then
                    TimerEnds[bank] = nil
                elseif TOB.Banks[bank] ~= nil and #(coords - StartVec(bank)) < 40.0 then
                    DrawTimer(left)
                    shown = true
                    break
                end
            end
        end
        Citizen.Wait(shown and 0 or 500)
    end
end)

-- STARTUP --

Bridge.Init(function()
    Bridge.TriggerCallback("tobsbank:getBanks", function(banks, doors, running)
        TOB.Banks = banks
        Doors = doors
        for k, _ in pairs(TOB.Banks) do
            Check[k] = false
            LootCheck[k] = {Loot1 = false, Loot2 = false, Loot3 = false}
        end
        if UseTarget() then
            RegisterTargets()
        end
        DoorThreads()
        JoinRunningHeists(running) -- joined during a heist: take part from where it is
        Ready = true
    end)
end)

-- "Press E" prompts for robbers: start the heist, hack the inner gate and use the vault item
Citizen.CreateThread(function()
    while not Ready do
        Citizen.Wait(500)
    end
    local useTarget = UseTarget()

    while true do
        local sleep = 1000

        if not useTarget and not DisableInput and not IsPoliceJob() then
            local coords = GetEntityCoords(PlayerPedId())

            for k, v in pairs(TOB.Banks) do
                local s = v.doors.startloc
                local start = vector3(s.x, s.y, s.z)
                local dst = #(coords - start)

                if dst <= 30 and sleep > 250 then
                    sleep = 250
                end
                if not v.onaction and not Check[k] and dst <= PromptRange(1.0) then
                    sleep = 0
                    if Prompt(start, L("start_heist"), dst, 1.0) then
                        TriggerServerEvent("tobsbank:startcheck", k)
                    end
                end
                if AwaitingGate[k] then
                    local g = v.doors.secondloc
                    local gate = vector3(g.x, g.y, g.z)
                    local gdst = #(coords - gate)
                    if gdst <= PromptRange(1.2) then
                        sleep = 0
                        if Prompt(gate, L("hack_gate"), gdst, 1.2) then
                            UseGate(k)
                        end
                    end
                end
                if AwaitingVault[k] then
                    local vt = Doors[k][2].txtloc
                    local vdst = #(coords - vt)
                    if vdst <= PromptRange(1.5) then
                        sleep = 0
                        if Prompt(vt, L("use_item", TOB.VaultItemLabel), vdst, 1.5) then
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
                    TriggerServerEvent("tobsbank:startcheck", k)
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

        -- One option per trolley kind, so the label says cash, gold or diamonds
        local kinds = {false}
        for kind, _ in pairs(TOB.SpecialTrolleys or {}) do kinds[#kinds + 1] = kind end
        for i = 1, 3 do
            local t = v["trolley" .. i]
            local loot = "Loot" .. i
            local options = {}
            for _, kind in ipairs(kinds) do
                options[#options + 1] = {
                    name = ("tob_loot_%s_%d_%s"):format(k, i, kind or "cash"),
                    icon = "fa-solid fa-sack-dollar",
                    label = LootLabel(kind or nil),
                    distance = 1.5,
                    canInteract = function()
                        local special = LootSpecial[k] and LootSpecial[k]["trolley" .. i] or false
                        return LootOpen[k] and special == kind and not LootCheck[k][loot] and not IsPoliceJob()
                    end,
                    onSelect = function() RequestLoot(k, loot) end
                }
            end
            exports.ox_target:addSphereZone({coords = vector3(t.x, t.y, t.z + 1.0), radius = 0.8, options = options})
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
                        return IsPoliceJob() and not DoorBusy and Doors[k][i].locked
                    end,
                    onSelect = function() ToggleDoor(k, i) end
                },
                {
                    name = "tob_lock_" .. k .. "_" .. i,
                    icon = "fa-solid fa-lock",
                    label = L("lock_door"),
                    distance = 2.0,
                    canInteract = function()
                        return IsPoliceJob() and not DoorBusy and not Doors[k][i].locked
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
