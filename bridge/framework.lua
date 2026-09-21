-- Picks the framework bridge (bridge/<framework>/). Loaded on both the server and the client.
-- TOB.Framework = "auto" uses the first framework resource that is running.

local FRAMEWORKS = {
    {name = "qbox", resource = "qbx_core"},  -- before qb-core: qbx_core also "provides" qb-core
    {name = "esx", resource = "es_extended"},
    {name = "qb", resource = "qb-core"},
    {name = "vrp", resource = "vrp"},
}

local function IsRunning(resource)
    local state = GetResourceState(resource)
    return state == "started" or state == "starting"
end

Framework = TOB.Framework ~= "auto" and TOB.Framework or nil
if Framework == nil then
    for _, f in ipairs(FRAMEWORKS) do
        if IsRunning(f.resource) then
            Framework = f.name
            break
        end
    end
end
if Framework == nil then
    print("^1[tobs_bankrobbery] No framework found. Start qbx_core, es_extended, qb-core or vrp before tobs_bankrobbery, or set TOB.Framework in config/config.lua.^7")
end

-- True if the job name counts as police. TOB.PoliceJob can be one name or a list of names.
function IsPoliceJobName(name)
    if type(TOB.PoliceJob) == "table" then
        for _, job in ipairs(TOB.PoliceJob) do
            if job == name then return true end
        end
        return false
    end
    return name == TOB.PoliceJob
end

-- True if a QBCore / Qbox job table counts as police (checks duty when TOB.PoliceOnDuty is on)
function IsPoliceJobData(job)
    return job ~= nil and IsPoliceJobName(job.name) and (not TOB.PoliceOnDuty or job.onduty == true)
end

-- The item paid as dirty money when TOB.black is on (ESX uses its black_money account instead)
function BlackMoneyItem()
    if TOB.blackmoney ~= nil and TOB.blackmoney ~= "auto" then return TOB.blackmoney end
    return Framework == "vrp" and "dirty_money" or "black_money"
end
