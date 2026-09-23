-- tobs_bridge: framework detection, shared helpers and the database wrapper.
-- Loaded on the client and the server, before every bridge/<framework>/ file.
--
-- Set BridgeConfig before this file loads (see README.md) to change the defaults.

BridgeConfig = BridgeConfig or {}
local C = BridgeConfig

C.Framework    = C.Framework    or "auto"        -- "auto", "qbox", "qb", "esx"
C.PoliceJobs   = C.PoliceJobs   or {"police"}    -- one name or a list
C.PoliceOnDuty = C.PoliceOnDuty ~= false         -- Qbox / QBCore only: count on-duty police only
C.BlackMoney   = C.BlackMoney   or "auto"        -- dirty money item ("auto" = black_money)
C.Notify       = C.Notify       or "auto"        -- "auto" (ox_lib when it runs), "oxlib" or "framework"
C.Debug        = C.Debug        or false

local FRAMEWORKS = {
    {name = "qbox", resource = "qbx_core"},   -- before qb-core: qbx_core also "provides" qb-core
    {name = "esx",  resource = "es_extended"},
    {name = "qb",   resource = "qb-core"},
}

local function IsRunning(resource)
    local state = GetResourceState(resource)
    return state == "started" or state == "starting"
end

-- Framework: the name of the running framework, or nil
Framework = C.Framework ~= "auto" and C.Framework or nil
if Framework == nil then
    for _, f in ipairs(FRAMEWORKS) do
        if IsRunning(f.resource) then
            Framework = f.name
            break
        end
    end
end

Bridge = {Framework = Framework}

function BridgeLog(...)
    print(("^3[bridge]^7 %s"):format(table.concat({...}, " ")))
end

function BridgeError(...)
    print(("^1[bridge]^7 %s"):format(table.concat({...}, " ")))
end

if Framework == nil then
    BridgeError("No framework found. Start qbx_core, es_extended or qb-core first, or set BridgeConfig.Framework.")
end

-- Police ------------------------------------------------------------------

-- True if a job name counts as police (BridgeConfig.PoliceJobs is a name or a list)
function IsPoliceJobName(name)
    if name == nil then return false end
    if type(C.PoliceJobs) == "table" then
        for _, job in ipairs(C.PoliceJobs) do
            if job == name then return true end
        end
        return false
    end
    return name == C.PoliceJobs
end

-- True if a job table counts as police (checks duty when BridgeConfig.PoliceOnDuty is on)
function IsPoliceJobData(job)
    return job ~= nil and IsPoliceJobName(job.name) and (not C.PoliceOnDuty or job.onduty == true)
end

-- The item paid as dirty money (ESX uses its black_money account instead)
function BlackMoneyItem()
    if C.BlackMoney ~= nil and C.BlackMoney ~= "auto" then return C.BlackMoney end
    return "black_money"
end

-- The optional resources a bridge uses, detected once
Bridge.Has = setmetatable({}, {__index = function(t, resource)
    local running = IsRunning(resource)
    rawset(t, resource, running)
    return running
end})
