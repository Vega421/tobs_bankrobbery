-- Sounds everyone in the bank hears, sent by the server (BankSound in server/tools.lua): the drill
-- while someone opens a deposit box, and the vault door opening. The Paleto alarm is already
-- played for everyone. Sound names verified in the game's sound list (DurtyFree/gta-v-data-dumps).

local Drills = {} -- ["bank:box"] = sound id
local MaxDrill = 120000 -- stop a drill sound after 2 minutes if its stop never arrives

local function Near(pos, range)
    return #(GetEntityCoords(PlayerPedId()) - vector3(pos.x, pos.y, pos.z)) <= range
end

local function StopDrill(key)
    local d = Drills[key]
    if d == nil then return end
    StopSound(d)
    ReleaseSoundId(d)
    Drills[key] = nil
end

RegisterNetEvent("tobs_bankrobbery:bankSound")
AddEventHandler("tobs_bankrobbery:bankSound", function(bank, kind, box, from, range)
    local b = TOB.Banks and TOB.Banks[bank]
    if b == nil then return end
    local key = tostring(bank) .. ":" .. tostring(box)

    if kind == "drill_off" then StopDrill(key) return end
    if from == GetPlayerServerId(PlayerId()) then return end -- the driller hears their own drill

    if kind == "drill_on" then
        local pos = b.boxes and b.boxes[box]
        if pos == nil or not Near(pos, range) then return end
        StopDrill(key)
        local id = GetSoundId()
        PlaySoundFromCoord(id, "Drill", pos.x, pos.y, pos.z, "DLC_HEIST_FLEECA_SOUNDSET", false, 0, false)
        Drills[key] = id
        -- safety net: stop it if its stop never arrives (the driller left, a lost message)
        Citizen.SetTimeout(MaxDrill, function()
            if Drills[key] == id then StopDrill(key) end
        end)
    elseif kind == "vault" then
        local pos = b.vault and b.vault.loc
        if pos == nil or not Near(pos, range) then return end
        PlaySoundFromCoord(-1, "vault_unlock", pos.x, pos.y, pos.z, "dlc_heist_fleeca_bank_door_sounds", false, 0, false)
    end
end)
