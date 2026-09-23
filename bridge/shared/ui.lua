-- ox_lib, when it runs: notifications, progress bars and text prompts. Client side.
-- Everything falls back to the framework (or to nothing) when ox_lib isn't installed, so a script
-- can always call Bridge.Progress / Bridge.TextUI without checking first.
if IsDuplicityVersion() then return end

local function UseOxLib()
    if BridgeConfig.Notify == "framework" then return false end
    if BridgeConfig.Notify == "oxlib" then return true end
    return Bridge.Has["ox_lib"]
end

-- Bridge.Notify(msg, kind): kind is "inform" (default), "success", "error" or "warning"
function Bridge.Notify(msg, kind)
    if UseOxLib() then
        return TriggerEvent("ox_lib:notify", {description = msg, type = kind or "inform"})
    end
    if Bridge.FrameworkNotify then return Bridge.FrameworkNotify(msg, kind) end
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

-- Bridge.Progress({label, duration, canCancel, disable, anim, prop}) -> true when it finished.
-- Without ox_lib it just waits, so the timing your script relies on is the same either way.
function Bridge.Progress(opts)
    opts = opts or {}
    local duration = opts.duration or 5000
    if Bridge.Has["ox_lib"] then
        return exports.ox_lib:progressBar({
            duration = duration,
            label = opts.label,
            useWhileDead = opts.useWhileDead == true,
            canCancel = opts.canCancel ~= false,
            disable = opts.disable or {move = false, car = true, combat = true},
            anim = opts.anim,
            prop = opts.prop,
        }) == true
    end
    if opts.anim and opts.anim.dict then
        RequestAnimDict(opts.anim.dict)
        local deadline = GetGameTimer() + 2000
        while not HasAnimDictLoaded(opts.anim.dict) and GetGameTimer() < deadline do Citizen.Wait(10) end
        if HasAnimDictLoaded(opts.anim.dict) then
            TaskPlayAnim(PlayerPedId(), opts.anim.dict, opts.anim.clip, 3.0, -8.0, duration, opts.anim.flag or 49, 0, false, false, false)
        end
    end
    local ped = PlayerPedId()
    local deadline = GetGameTimer() + duration
    while GetGameTimer() < deadline do
        if IsEntityDead(ped) then return false end
        Citizen.Wait(50)
    end
    if opts.anim and opts.anim.dict then ClearPedTasks(ped) end
    return true
end

-- Bridge.TextUI("[E] Open the vault") / Bridge.HideTextUI(): ox_lib's text UI, or GTA's help text
local helpText = nil

function Bridge.TextUI(text)
    if Bridge.Has["ox_lib"] then return exports.ox_lib:showTextUI(text) end
    if helpText == text then return end
    helpText = text
    Citizen.CreateThread(function()
        while helpText ~= nil do
            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName(helpText)
            EndTextCommandDisplayHelp(0, false, false, -1)
            Citizen.Wait(0)
        end
    end)
end

function Bridge.HideTextUI()
    helpText = nil
    if Bridge.Has["ox_lib"] then exports.ox_lib:hideTextUI() end
end

-- Bridge.Input / Bridge.Menu are only there with ox_lib: they return nil without it, so a script
-- can offer them as an extra instead of depending on them.
function Bridge.Input(heading, rows)
    if not Bridge.Has["ox_lib"] then return nil end
    return exports.ox_lib:inputDialog(heading, rows)
end

function Bridge.Alert(opts)
    if not Bridge.Has["ox_lib"] then return nil end
    return exports.ox_lib:alertDialog(opts)
end
