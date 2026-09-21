-- vRP bridge (server)
if Framework ~= "vrp" then return end

-- vRP's lib/utils.lua defines module(). It's loaded here instead of in fxmanifest.lua,
-- so the resource still starts on servers without vRP.
local utils = LoadResourceFile("vrp", "lib/utils.lua")
if utils == nil then
    print("^1[tobs_bankrobbery] Could not read vrp/lib/utils.lua. Is vrp started before tobs_bankrobbery?^7")
    return
end
load(utils, "@vrp/lib/utils.lua")()

local Proxy = module("vrp", "lib/Proxy")
vRP = Proxy.getInterface("vRP")

Bridge = {RegisterCallback = TOBCallbacks.Register}

function Bridge.IsPolice(src)
    local user_id = vRP.getUserId({src})
    return user_id ~= nil and vRP.hasGroup({user_id, TOB.PoliceGroup})
end

function Bridge.CountPolice()
    local count = 0
    for user_id, _ in pairs(vRP.getUsers({})) do
        if vRP.hasGroup({user_id, TOB.PoliceGroup}) then count = count + 1 end
    end
    return count
end

function Bridge.HasItem(src, item, count)
    local user_id = vRP.getUserId({src})
    return user_id ~= nil and vRP.getInventoryItemAmount({user_id, item}) >= count
end

function Bridge.RemoveItem(src, item, count)
    local user_id = vRP.getUserId({src})
    if user_id ~= nil then vRP.tryGetInventoryItem({user_id, item, count}) end
end

function Bridge.AddItem(src, item, count)
    local user_id = vRP.getUserId({src})
    if user_id ~= nil then vRP.giveInventoryItem({user_id, item, count}) end
end

function Bridge.AddMoney(src, amount, dirty)
    local user_id = vRP.getUserId({src})
    if user_id == nil then return end
    if dirty then
        vRP.giveInventoryItem({user_id, BlackMoneyItem(), amount})
    else
        vRP.giveMoney({user_id, amount})
    end
end

-- Tells each player whether they're police (vRP has no client-side job data)
RegisterServerEvent("TOB_fh:CheckCop")
AddEventHandler("TOB_fh:CheckCop", function()
    local src = source

    if Bridge.IsPolice(src) then
        TriggerClientEvent("TOB_fh:IsCop", src)
    else
        TriggerClientEvent("TOB_fh:IsNOTCop", src)
    end
end)
