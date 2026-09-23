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
    elseif mode == "esx" or mode == "framework" then
        Bridge.FrameworkNotify(msg, ntype)
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
-- Falls back to the cash trolley if a special model isn't in the game files.
CASH_TROLLEY = {model = GetHashKey("hei_prop_hei_cash_trolly_01"), pile = GetHashKey("hei_prop_heist_cash_pile"), empty = GetHashKey("hei_prop_hei_cash_trolly_03")}
function TrolleyModels(kind)
    local s = kind and TOB.SpecialTrolleys and TOB.SpecialTrolleys[kind]
    if not s then return CASH_TROLLEY end
    local m = {model = ModelHash(s.model), pile = ModelHash(s.pile), empty = ModelHash(s.empty)}
    if not (IsModelInCdimage(m.model) and IsModelInCdimage(m.pile) and IsModelInCdimage(m.empty)) then
        return CASH_TROLLEY
    end
    return m
end

-- Every trolley model the script can spawn, for cleanup
function AllTrolleyModels()
    local list = {CASH_TROLLEY.model, CASH_TROLLEY.empty}
    for _, s in pairs(TOB.SpecialTrolleys or {}) do
        list[#list + 1] = ModelHash(s.model)
        list[#list + 1] = ModelHash(s.empty)
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
