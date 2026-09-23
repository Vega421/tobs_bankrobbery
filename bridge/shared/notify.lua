-- Bridge.Notify(src, msg) on the server sends this event; the client shows it (ox_lib or the framework)
if IsDuplicityVersion() then return end

RegisterNetEvent("bridge:notify", function(msg, kind)
    if Bridge.Notify then Bridge.Notify(msg, kind) end
end)
