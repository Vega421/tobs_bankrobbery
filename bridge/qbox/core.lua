-- Qbox: players, jobs, items (ox_inventory) and money. Server side.
if Framework ~= "qbox" then return end
if not IsDuplicityVersion() then return end

Bridge.Metadata = true       -- items can carry metadata ({worth = 5000})
Bridge.Inventory = "ox"
Bridge.RegisterCallback = BridgeCallbacks.Register

local function Player(src)
    return exports.qbx_core:GetPlayer(tonumber(src))
end

-- The one shape every framework returns: nil when the player isn't loaded
function Bridge.GetPlayer(src)
    local p = Player(src)
    if p == nil then return nil end
    local d = p.PlayerData
    local info = d.charinfo or {}
    return {
        id = d.citizenid,
        source = tonumber(src),
        firstname = info.firstname,
        lastname = info.lastname,
        dob = info.birthdate,
        phone = info.phone,
        gender = info.gender,
        job = Bridge.GetJob(src),
    }
end

function Bridge.GetIdentifier(src)
    local p = Player(src)
    return p and p.PlayerData.citizenid or nil
end

function Bridge.GetJob(src)
    local p = Player(src)
    if p == nil then return nil end
    local job = p.PlayerData.job or {}
    return {
        name = job.name,
        label = job.label,
        grade = job.grade and job.grade.level or 0,
        gradeLabel = job.grade and job.grade.name,
        onduty = job.onduty == true,
        boss = job.isboss == true,
    }
end

function Bridge.IsPolice(src)
    return IsPoliceJobData(Bridge.GetJob(src))
end

function Bridge.GetPlayersByJob(job)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local j = Bridge.GetJob(tonumber(id))
        if j and (job == nil or j.name == job) then out[#out + 1] = tonumber(id) end
    end
    return out
end

function Bridge.CountPolice()
    local n = 0
    for _, id in ipairs(GetPlayers()) do
        if Bridge.IsPolice(tonumber(id)) then n = n + 1 end
    end
    return n
end

-- Items ------------------------------------------------------------------

function Bridge.GetItemCount(src, item)
    return exports.ox_inventory:GetItemCount(src, item) or 0
end

function Bridge.HasItem(src, item, count)
    return Bridge.GetItemCount(src, item) >= (count or 1)
end

function Bridge.RemoveItem(src, item, count)
    return exports.ox_inventory:RemoveItem(src, item, count or 1) == true
end

function Bridge.AddItem(src, item, count, metadata)
    return exports.ox_inventory:AddItem(src, item, count or 1, metadata) == true
end

function Bridge.CanCarry(src, item, count)
    return exports.ox_inventory:CanCarryItem(src, item, count or 1) == true
end

-- Money ------------------------------------------------------------------
-- account: "cash" (default), "bank" or "black" (dirty money)

function Bridge.AddMoney(src, amount, account, reason)
    if account == "black" then return Bridge.AddItem(src, BlackMoneyItem(), amount) end
    return exports.qbx_core:AddMoney(tonumber(src), account or "cash", amount, reason or "bridge") ~= false
end

function Bridge.RemoveMoney(src, amount, account, reason)
    if account == "black" then return Bridge.RemoveItem(src, BlackMoneyItem(), amount) end
    return exports.qbx_core:RemoveMoney(tonumber(src), account or "cash", amount, reason or "bridge") ~= false
end

function Bridge.GetMoney(src, account)
    if account == "black" then return Bridge.GetItemCount(src, BlackMoneyItem()) end
    local p = Player(src)
    return p and (p.PlayerData.money[account or "cash"] or 0) or 0
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent("bridge:notify", src, msg, kind)
end
