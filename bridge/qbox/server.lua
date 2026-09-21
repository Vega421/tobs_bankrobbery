-- Qbox bridge (server). Items go through ox_inventory.
if Framework ~= "qbox" then return end

Bridge = {RegisterCallback = TOBCallbacks.Register}

function Bridge.IsPolice(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player ~= nil and IsPoliceJobData(player.PlayerData.job)
end

function Bridge.CountPolice()
    local count = 0
    for _, id in ipairs(GetPlayers()) do
        if Bridge.IsPolice(tonumber(id)) then count = count + 1 end
    end
    return count
end

function Bridge.HasItem(src, item, count)
    return (exports.ox_inventory:GetItemCount(src, item) or 0) >= count
end

function Bridge.RemoveItem(src, item, count)
    exports.ox_inventory:RemoveItem(src, item, count)
end

function Bridge.AddItem(src, item, count)
    exports.ox_inventory:AddItem(src, item, count)
end

function Bridge.AddMoney(src, amount, dirty)
    if dirty then return Bridge.AddItem(src, BlackMoneyItem(), amount) end
    exports.qbx_core:AddMoney(src, "cash", amount, "tobs_bankrobbery")
end
