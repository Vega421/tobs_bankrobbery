-- Deposit boxes: drill them open while the vault is open (TOB.DepositBoxes)

local drilling = false

function DrillBox(bank, box)
    if drilling or DisableInput then return end
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
    -- not networked: the others hear it from the server's bank sound (client/sounds.lua), so not twice
    PlaySoundFromEntity(sound, "Drill", drill, "DLC_HEIST_FLEECA_SOUNDSET", false, 0)
    DisableInput = true

    -- the minigame and the drilling time (client/minigames.lua): the GTA drill screen, or the skill check + progress bar
    local passed = DrillBoxMinigame(bank, function(v) return DrillMinigame(bank, box, v) end)
    if not passed then Notify("error", L("drill_failed")) end

    StopSound(sound)
    ReleaseSoundId(sound)
    StopAnimTask(ped, dict, "drill_straight_idle", 1.0)
    DeleteObject(drill)
    DisableInput = false
    drilling = false
    TriggerServerEvent("TOB_fh:drillDone", bank, box, passed)
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
