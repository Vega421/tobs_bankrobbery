-- The database wrapper every data.lua uses (oxmysql). Server only.
-- Db.Query / Db.Single / Db.Scalar wait for the answer; Db.Execute doesn't return rows.
-- Everything returns nil (and logs once) when oxmysql isn't running, so a script never crashes on it.

if not IsDuplicityVersion() then return end

Db = {}
local warned = false

local function Ready()
    if Bridge.Has["oxmysql"] then return true end
    if not warned then
        warned = true
        BridgeError("oxmysql isn't running: no database queries. Start oxmysql before this resource.")
    end
    return false
end

-- Runs one oxmysql export and waits for the callback
local function Run(method, sql, params)
    if not Ready() then return nil end
    local p = promise.new()
    local ok, err = pcall(function()
        exports.oxmysql[method](exports.oxmysql, sql, params or {}, function(result)
            p:resolve(result)
        end)
    end)
    if not ok then
        BridgeError(("query failed: %s"):format(tostring(err)))
        return nil
    end
    return Citizen.Await(p)
end

function Db.Query(sql, params)  return Run("query", sql, params) end   -- a list of rows, or nil
function Db.Single(sql, params) return Run("single", sql, params) end  -- one row, or nil
function Db.Scalar(sql, params) return Run("scalar", sql, params) end  -- one value, or nil
function Db.Execute(sql, params) return Run("update", sql, params) end -- rows changed, or nil

-- JSON columns (players.charinfo, players.job, ...) come back as a string on some servers
function Db.Json(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" or value == "" then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end
