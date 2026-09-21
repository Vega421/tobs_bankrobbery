-- Small framework-independent server callback helper, used by every bridge.
TOBCallbacks = {}
local requestId = 0
local pending = {}

function TOBCallbacks.Trigger(name, cb, ...)
    pending[requestId] = cb
    TriggerServerEvent("TOB_cb:trigger", name, requestId, ...)
    requestId = requestId < 65535 and requestId + 1 or 0
end

RegisterNetEvent("TOB_cb:result")
AddEventHandler("TOB_cb:result", function(id, ...)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(...) end
end)
