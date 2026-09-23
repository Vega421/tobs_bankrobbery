-- Fake FiveM, framework and database functions, so the real bridge files can run in plain Lua.
-- Every test file starts by loading this and calling Load("<framework>").

local F = {}

F.state = {}      -- resource states
F.queries = {}    -- every SQL query the bridge ran: {sql, params}
F.rows = {}       -- what a query answers: {["FROM players"] = {row, ...}}
F.events = {}     -- TriggerClientEvent calls
F.players = {}    -- fake online players: [src] = data used by the fake framework
F.triggered = {}  -- TriggerEvent calls (ox_lib notifications)

function GetResourceState(name) return F.state[name] or "missing" end
function IsDuplicityVersion() return F.server end
function GetPlayers()
    local out = {}
    for src in pairs(F.players) do out[#out + 1] = tostring(src) end
    table.sort(out)
    return out
end
function TriggerClientEvent(name, src, ...) F.events[#F.events + 1] = {name = name, src = src, ...} end
function TriggerEvent(name, ...) F.triggered[#F.triggered + 1] = {name = name, ...} end
function RegisterServerEvent() end
function RegisterNetEvent() end
function AddEventHandler() end
function LoadResourceFile() return "return function() end" end

-- Natives the ox_lib fallbacks use
F.feed, F.help, F.anims = {}, nil, {}
function BeginTextCommandThefeedPost() F.pending = true end
function AddTextComponentSubstringPlayerName(s) F.pendingText = s end
function EndTextCommandThefeedPostTicker() F.feed[#F.feed + 1] = F.pendingText end
function BeginTextCommandDisplayHelp() end
function EndTextCommandDisplayHelp() F.help = F.pendingText end
function PlayerPedId() return 1 end
function IsEntityDead() return F.dead == true end
function GetGameTimer() F.clock = (F.clock or 0) + 25; return F.clock end
function RequestAnimDict(d) F.anims[#F.anims + 1] = d end
function HasAnimDictLoaded() return true end
function TaskPlayAnim(_, dict, clip) F.played = {dict = dict, clip = clip} end
function ClearPedTasks() F.cleared = true end
function NetworkIsPlayerActive() return true end
function PlayerId() return 0 end

-- Citizen.Wait counts: a thread with a "while true" loop is stopped after F.waitLimit waits,
-- so one pass of a loop can be tested without hanging the test.
F.waits, F.waitLimit = 0, 2000
Citizen = {
    CreateThread = function(fn) F.threads = (F.threads or 0) + 1; F.lastThread = fn end,
    Wait = function()
        F.waits = F.waits + 1
        if F.waits > F.waitLimit then error("wait limit", 0) end
    end,
    Await = function(p) return p.value end,
}

-- Runs a thread body until it ends or hits the wait limit
function RunThread(fn)
    F.waits = 0
    local ok, err = pcall(fn)
    return ok or err == "wait limit"
end
promise = {new = function() return {resolve = function(self, v) self.value = v end} end}

-- Just enough json for the tests (the bridge only encodes plain tables)
json = {
    decode = function(s) return F.json and F.json[s] or nil end,
    encode = function(t) F.encoded = t; return "<json>" end,
}

-- The fake oxmysql: answers from F.rows by matching a piece of the query
local function Answer(sql)
    for needle, rows in pairs(F.rows) do
        if sql:find(needle, 1, true) then return rows end
    end
    return nil
end

local oxmysql = {
    query = function(_, sql, params, cb) F.queries[#F.queries + 1] = {sql = sql, params = params}; cb(Answer(sql)) end,
}
oxmysql.single = function(_, sql, params, cb)
    F.queries[#F.queries + 1] = {sql = sql, params = params}
    local rows = Answer(sql)
    cb(rows and rows[1] or nil)
end
-- A scalar query returns the one selected column, like oxmysql does
oxmysql.scalar = function(_, sql, params, cb)
    F.queries[#F.queries + 1] = {sql = sql, params = params}
    local rows = Answer(sql)
    local row = rows and rows[1]
    if row == nil then return cb(nil) end
    local column = sql:match("SELECT%s+([%w_]+)%s+FROM")
    if column and row[column] ~= nil then return cb(row[column]) end
    for _, v in pairs(row) do return cb(v) end
    cb(nil)
end
oxmysql.update = function(_, sql, params, cb) F.queries[#F.queries + 1] = {sql = sql, params = params}; cb(1) end

F.oxmysql = oxmysql
exports = {oxmysql = oxmysql}

-- Loads the bridge for one framework, server or client side
function Load(framework, side, config)
    F.server = side ~= "client"
    F.queries, F.events, F.threads, F.feed, F.clock = {}, {}, 0, {}, 0
    F.triggered, F.help, F.played, F.cleared, F.dead = {}, nil, nil, false, false
    F.waits = 0
    Bridge, Framework, Db, BridgeCallbacks, BridgeConfig = nil, nil, nil, nil, config or {}
    F.state["oxmysql"] = "started"
    dofile("bridge/framework.lua")
    dofile("bridge/shared/callbacks.lua")
    dofile("bridge/shared/db.lua")
    for _, name in ipairs({"qbox", "qb", "esx"}) do
        for _, file in ipairs({"core.lua", "data.lua", "client.lua"}) do
            local path = ("bridge/%s/%s"):format(name, file)
            local f = io.open(path)
            if f then f:close(); dofile(path) end
        end
    end
    dofile("bridge/shared/notify.lua")
    dofile("bridge/shared/ui.lua")
    return Bridge
end

return F
