-- Admin reset, txAdmin restart protection and the update check.

-- Resets one bank: stops its heist, closes the vault, relocks the gate and clears the cooldown
function ResetBank(bank, reason)
    TriggerClientEvent("TOB_fh:forceReset", -1, bank)
    CloseVault(bank)
    Doors[bank][1].locked = GateLockedByDefault(bank)
    TriggerClientEvent("TOB_fh:toggleDoor", -1, bank, Doors[bank][1].locked)
    EndHeist(bank, reason or "reset by an admin", false)
end

-- /tobreset [bank]  (no bank = all banks). Needs: add_ace group.admin command.tobreset allow
RegisterCommand(SV.ResetCommand, function(src, args)
    local who = src == 0 and "the server console" or PlayerLabel(src)
    local count = 0

    for bank, _ in pairs(TOB.Banks) do
        if args[1] == nil or args[1] == bank then
            ResetBank(bank)
            count = count + 1
        end
    end
    local msg = count > 0 and ("Reset %d bank(s)."):format(count) or ("No bank called %s."):format(args[1])
    if src == 0 then
        print("[tobs_bankrobbery] " .. msg)
    else
        TriggerClientEvent("TOB_fh:outcome", src, false, msg)
    end
    if count > 0 then
        Log("Heist reset", who .. " reset " .. (args[1] or "all banks") .. ".", 3447003)
    end
end, true)

-- RESTART PROTECTION --
-- txAdmin announces scheduled restarts; block new heists in the last SV.BlockBeforeRestart minutes
AddEventHandler("txAdmin:events:scheduledRestart", function(data)
    local minutes = SV.BlockBeforeRestart or 0
    if minutes > 0 and data and data.secondsRemaining and data.secondsRemaining <= minutes * 60 and not RestartSoon then
        RestartSoon = true
        Log("Heists blocked", ("Server restart in %d minutes. New heists are blocked until the restart."):format(math.ceil(data.secondsRemaining / 60)), 9807270)
    end
end)

AddEventHandler("txAdmin:events:scheduledRestartSkipped", function()
    RestartSoon = false
end)

-- UPDATE CHECK --

local function IsNewer(latest, current)
    local a, b = {}, {}
    for n in latest:gmatch("%d+") do a[#a + 1] = tonumber(n) end
    for n in current:gmatch("%d+") do b[#b + 1] = tonumber(n) end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

Citizen.CreateThread(function()
    if not SV.CheckForUpdates then return end
    Citizen.Wait(5000)
    local current = GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "0.0.0"

    PerformHttpRequest(("https://api.github.com/repos/%s/releases/latest"):format(REPO), function(status, body)
        if status ~= 200 or not body then return end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= "table" or type(data.tag_name) ~= "string" then return end
        local latest = data.tag_name:gsub("^v", "")
        if IsNewer(latest, current) then
            print(("^3[tobs_bankrobbery] Version %s is available (you have %s). Download: %s^7"):format(latest, current, data.html_url))
        else
            print(("^2[tobs_bankrobbery] Version %s is up to date.^7"):format(current))
        end
    end, "GET", "", {["User-Agent"] = "tobs_bankrobbery", ["Accept"] = "application/vnd.github+json"})
end)
