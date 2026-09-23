-- Framework-independent client -> server callbacks, so no bridge needs QBCore.Functions.TriggerCallback,
-- ESX.TriggerServerCallback. Loaded on both sides.

BridgeCallbacks = {}

if IsDuplicityVersion() then
    local registered = {}

    function BridgeCallbacks.Register(name, fn)
        registered[name] = fn
    end

    RegisterServerEvent("bridge:cb:ask")
    AddEventHandler("bridge:cb:ask", function(name, id, ...)
        local src = source
        local fn = registered[name]
        if fn == nil then return end
        fn(src, function(...)
            TriggerClientEvent("bridge:cb:answer", src, id, ...)
        end, ...)
    end)
else
    local nextId, pending = 0, {}

    function BridgeCallbacks.Trigger(name, cb, ...)
        pending[nextId] = cb
        TriggerServerEvent("bridge:cb:ask", name, nextId, ...)
        nextId = nextId < 65535 and nextId + 1 or 0
    end

    RegisterNetEvent("bridge:cb:answer")
    AddEventHandler("bridge:cb:answer", function(id, ...)
        local cb = pending[id]
        pending[id] = nil
        if cb then cb(...) end
    end)
end
