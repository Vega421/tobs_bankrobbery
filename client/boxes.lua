-- Deposit boxes: drill them open while the vault is open (TOB.DepositBoxes)

local drilling = false
local STAND_OFF = 0.55 -- metres between the wall and where the robber stands to drill

-- Where to stand for a box, square to the wall it's in: the wall's facing (its surface normal) gives
-- the spot in front of the box and the heading. Facing the box's centre from wherever the player stood
-- (a target eye lets them stand off to the side) turned the drill animation sideways.
-- The wall is found with short lines in 16 directions from just in front of the box, keeping the hit
-- nearest the box: one line from the player hit the side wall at boxes near a corner (Paleto, QBCore
-- test). Map and objects both count (a vault can be built from props). nil when nothing is hit.
local RAY_FLAGS = 1 + 16
local function DrillSpot(ped, pos, here)
    local dir = vector3(here.x - pos.x, here.y - pos.y, 0.0)
    local len = #dir
    if len < 0.01 then return nil end
    local from = vector3(pos.x + dir.x / len * 0.4, pos.y + dir.y / len * 0.4, pos.z)
    local best, bestDist, bestN
    for i = 0, 15 do
        local a = i * math.pi / 8
        local to = vector3(from.x + math.cos(a) * 1.2, from.y + math.sin(a) * 1.2, from.z)
        local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, RAY_FLAGS, ped, 4)
        local _, hit, hitAt, normal = GetShapeTestResult(ray)
        if hit == 1 or hit == true then
            local n = vector3(normal.x, normal.y, 0.0)
            local nl = #n
            if nl >= 0.5 then -- a wall, not a floor or shelf top
                local d = #(vector3(pos.x - hitAt.x, pos.y - hitAt.y, 0.0))
                if not bestDist or d < bestDist then
                    best, bestDist, bestN = hitAt, d, vector3(n.x / nl, n.y / nl, 0.0)
                end
            end
        end
    end
    if not best then return nil end
    -- in front of the box (not of where the line hit), at the player's height
    local base = bestDist < 0.6 and pos or best
    return vector3(base.x + bestN.x * STAND_OFF, base.y + bestN.y * STAND_OFF, here.z), GetHeadingFromVector_2d(-bestN.x, -bestN.y)
end

-- Walks the robber to the drill spot (a step at most) and turns them to the wall
local function GoToDrillSpot(ped, pos)
    local here = GetEntityCoords(ped)
    local spot, heading = DrillSpot(ped, pos, here)
    if not spot then
        SetEntityHeading(ped, GetHeadingFromVector_2d(pos.x - here.x, pos.y - here.y))
        return
    end
    if #(here - spot) > 0.15 then
        TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 1500, heading, 0.05)
        local deadline = GetGameTimer() + 1500
        while #(GetEntityCoords(ped) - spot) > 0.15 and GetGameTimer() < deadline do Citizen.Wait(50) end
        ClearPedTasks(ped)
    end
    SetEntityHeading(ped, heading)
end

function DrillBox(bank, box)
    if drilling or DisableInput then return end
    TriggerServerEvent("tobsbank:drillBox", bank, box)
end

RegisterNetEvent("tobsbank:drillResult")
AddEventHandler("tobsbank:drillResult", function(bank, box, ok, reason)
    if not ok then
        Notify("error", L(reason, TOB.DrillItemLabel))
        return
    end
    drilling = true
    local ped = PlayerPedId()
    local pos = TOB.Banks[bank].boxes[box]
    local dict = "anim@heists@fleeca_bank@drilling"
    local drillHash = GetHashKey("hei_prop_heist_drill")

    GoToDrillSpot(ped, pos)
    local here = GetEntityCoords(ped)
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
    TriggerServerEvent("tobsbank:drillDone", bank, box, passed)
end)

RegisterNetEvent("tobsbank:boxState")
AddEventHandler("tobsbank:boxState", function(bank, box, state)
    BoxState[bank] = BoxState[bank] or {}
    BoxState[bank][box] = state
end)

RegisterNetEvent("tobsbank:boxesReset")
AddEventHandler("tobsbank:boxesReset", function(bank)
    BoxState[bank] = nil
end)

RegisterNetEvent("tobsbank:boxReward")
AddEventHandler("tobsbank:boxReward", function(text)
    Notify("success", text, 7000)
end)
