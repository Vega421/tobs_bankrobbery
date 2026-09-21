-- GPS tracker hidden in the loot (TOB.Tracker). After a robber grabs a trolley with a tracker in it, police
-- see them on the map for TOB.Tracker.duration seconds, updated every TOB.Tracker.interval seconds.
-- The server sends the positions, so it needs OneSync to know where the robber is.

local Trackers = {} -- [server id] = {ends = ms, nextUpdate = ms}

if TOB.Tracker and TOB.Tracker.enabled and GetConvar("onesync", "off") == "off" then
    print("^3[tobs_bankrobbery] TOB.Tracker needs OneSync to follow robbers. Trackers won't show without it.^7")
end
if TOB.MarkedBills and not Bridge.Metadata then
    print("^3[tobs_bankrobbery] TOB.MarkedBills needs qb-inventory or ox_inventory (QBCore / Qbox). Trolleys pay cash instead.^7")
end

-- Starts (or extends) a tracker on a robber
function StartTracker(src, bank)
    local now = GetGameTimer()
    local duration = (TOB.Tracker.duration or 180) * 1000
    local t = Trackers[src]
    if t then
        t.ends = math.max(t.ends, now + duration)
    else
        Trackers[src] = {ends = now + duration, nextUpdate = 0}
    end
    if TOB.Tracker.warnRobber then
        TriggerClientEvent("TOB_fh:trackerWarn", src)
    end
    Log("GPS tracker", PlayerLabel(src) .. " took a GPS tracker from " .. BankName(bank) .. ".", 3447003)
end

function StopTracker(src)
    if Trackers[src] then
        Trackers[src] = nil
        TriggerClientEvent("TOB_fh:trackerEnd", -1, src)
    end
end

-- Server ids of every police officer online
local function PoliceOnline()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if Bridge.IsPolice(id) then list[#list + 1] = id end
    end
    return list
end

-- Called every second from the heist timeline (server/heist.lua)
function TrackerTick(now)
    if next(Trackers) == nil then return end
    local police = nil
    for src, t in pairs(Trackers) do
        if now >= t.ends then
            StopTracker(src)
        elseif now >= t.nextUpdate then
            t.nextUpdate = now + (TOB.Tracker.interval or 5) * 1000
            local coords = PlayerCoords(src)
            if coords ~= nil then
                police = police or PoliceOnline()
                local left = math.ceil((t.ends - now) / 1000)
                for _, id in ipairs(police) do
                    TriggerClientEvent("TOB_fh:trackerPos", id, src, coords, left)
                end
            end
        end
    end
end
