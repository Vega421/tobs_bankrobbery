-- The frameworks tobs_bankrobbery supports: Qbox and QBCore. The shared bridge (bridge/framework.lua)
-- also knows ESX, but this resource doesn't load its ESX files, so an ESX server gets a clear message
-- instead of errors further on. Loaded on both sides, right after bridge/framework.lua.

local SUPPORTED = { qbox = true, qb = true }

if Framework ~= nil and not SUPPORTED[Framework] then
    BridgeError(("tobs_bankrobbery doesn't support %s: it runs on Qbox (qbx_core) and QBCore (qb-core)."):format(Framework))
    Framework = nil
    Bridge.Framework = nil
end
