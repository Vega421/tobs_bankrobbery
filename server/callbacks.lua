-- Small framework-independent server callback helper, used by every bridge.
TOBCallbacks = {}
local registered = {}

function TOBCallbacks.Register(name, fn)
    registered[name] = fn
end

RegisterServerEvent("TOB_cb:trigger")
AddEventHandler("TOB_cb:trigger", function(name, id, ...)
    local src = source
    local fn = registered[name]

    if fn == nil then return end
    fn(src, function(...)
        TriggerClientEvent("TOB_cb:result", src, id, ...)
    end, ...)
end)
