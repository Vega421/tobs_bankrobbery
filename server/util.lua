-- Shared server helpers: logs, anti-cheat flags, distance checks, rate limits, formatting and saved cooldowns.

REPO = "Vega421/tobs_bankrobbery" -- GitHub repo checked for new versions

function BankName(bank)
    local b = TOB.Banks[bank]
    return b and b.label and ("%s (%s)"):format(b.label, bank) or tostring(bank)
end

function Money(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

function Duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%dm %02ds"):format(seconds // 60, seconds % 60)
end

-- DISCORD LOGS --

function PlayerLabel(src)
    local name = GetPlayerName(src) or "unknown"
    local license = "unknown"
    local discord

    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:find("^license:") then license = id end
        if id:find("^discord:") then discord = id:sub(9) end
    end
    local label = ("**%s** (id %s, `%s`)"):format(name, src, license)
    if discord then
        label = label .. (" <@%s>"):format(discord)
    end
    return label
end

function Log(title, description, color)
    print(("[tobs_bankrobbery] %s: %s"):format(title, description:gsub("%*", ""):gsub("`", "")))
    if SV.Webhook == nil or SV.Webhook == "" then return end
    PerformHttpRequest(SV.Webhook, function() end, "POST", json.encode({
        username = "tobs_bankrobbery",
        embeds = {{
            title = title,
            description = description,
            color = color,
            footer = {text = GetCurrentResourceName()},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
        allowed_mentions = {parse = {}}, -- player names can't ping @everyone
    }), {["Content-Type"] = "application/json"})
end

-- Anti-cheat flags, at most once a minute per player and reason so a cheater can't flood the webhook
local flagged = {}
function Flag(src, reason)
    if not SV.LogAntiCheat then return end
    local key = tostring(src) .. "|" .. reason
    if flagged[key] and os.time() - flagged[key] < 60 then return end
    flagged[key] = os.time()
    Log("Suspicious event blocked", PlayerLabel(src) .. "\n" .. reason, 15158332)
end

-- Rate limit: true when src did `what` less than ms ago (the call should be ignored)
local lastCall = {}
function TooSoon(src, what, ms)
    local key = tostring(src) .. "|" .. what
    local now = GetGameTimer()
    if lastCall[key] and now - lastCall[key] < ms then return true end
    lastCall[key] = now
    return false
end

-- Forgets a player's flags and rate limits when they leave
function ForgetPlayer(src)
    local prefix = tostring(src) .. "|"
    for key, _ in pairs(flagged) do
        if key:sub(1, #prefix) == prefix then flagged[key] = nil end
    end
    for key, _ in pairs(lastCall) do
        if key:sub(1, #prefix) == prefix then lastCall[key] = nil end
    end
end

-- POSITIONS --
-- Without OneSync the server can't see player positions: PlayerCoords returns nil and the
-- distance checks are skipped. A warning is printed at startup.

function PlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if c.x == 0.0 and c.y == 0.0 and c.z == 0.0 then return nil end
    return c
end

-- Distance from the player to pos, or nil when the server can't tell
function DistanceTo(src, pos)
    local c = PlayerCoords(src)
    if c == nil then return nil end
    return #(c - vector3(pos.x, pos.y, pos.z))
end

-- True when the player is within maxDist of pos (or when the server can't tell)
function IsNear(src, pos, maxDist)
    local d = DistanceTo(src, pos)
    return d == nil or d <= maxDist
end

if GetConvar("onesync", "off") == "off" then
    print("^1[tobs_bankrobbery] OneSync is off. The anti-cheat can't check where players are, so distance checks are skipped. Set 'set onesync on' in server.cfg.^7")
end

-- SAVED COOLDOWNS --
-- Stored with resource KVP, so restarting the script or the server doesn't reset them.

function SaveCooldown(bank, t)
    SetResourceKvpInt("lastrobbed:" .. bank, t)
end

function LoadCooldown(bank)
    return GetResourceKvpInt("lastrobbed:" .. bank) or 0
end

function SaveLastHeistEnd(t)
    SetResourceKvpInt("lastheistend", t)
end

function LoadLastHeistEnd()
    return GetResourceKvpInt("lastheistend") or 0
end
