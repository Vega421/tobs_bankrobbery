-- Health check: a few seconds after start, the console lists what's missing or set up wrong, so it's
-- fixed before players find it. /tobcheck runs it again. SV.HealthCheck = false turns the start check off.
-- Problems stop something from working; notes are worth a look.

local function Defaults()
    SV.CheckCommand = SV.CheckCommand or "tobcheck"
    if SV.HealthCheck == nil then SV.HealthCheck = true end
end

local function Started(res) return GetResourceState(res) == "started" end

-- Does the item exist in the inventory? true / false, or nil when it can't be checked (vRP, errors)
function ItemExists(name)
    local ok, result = pcall(function()
        if Started("ox_inventory") then
            return exports.ox_inventory:Items(name) ~= nil
        end
        if Framework == "qb" or Framework == "qbox" then
            local QBCore = exports["qb-core"]:GetCoreObject()
            return QBCore.Shared.Items[name] ~= nil or QBCore.Shared.Items[name:lower()] ~= nil
        end
        if Framework == "esx" then
            local items = exports["es_extended"]:getSharedObject().GetItems()
            if next(items) == nil then return nil end -- not loaded from the database yet
            return items[name] ~= nil
        end
        return nil
    end)
    if not ok then return nil end
    return result
end

-- Items the config uses: {name, what it's for}
local function ConfiguredItems()
    local list, seen = {}, {}
    local function add(name, what)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = {name, what}
        end
    end
    add(TOB.CardItem or "id_card_f", "the access card")
    if TOB.DepositBoxes ~= false then add(TOB.DrillItem, "TOB.DrillItem") end
    add(TOB.VaultItem, "TOB.VaultItem")
    add(TOB.GateItem, "TOB.GateItem")
    add(TOB.RewardItem, "TOB.RewardItem")
    if TOB.MarkedBills then add(TOB.MarkedBillsItem or "markedbills", "TOB.MarkedBillsItem") end
    if TOB.black and Framework ~= "esx" then add(BlackMoneyItem(), "dirty money (TOB.blackmoney)") end
    for _, r in ipairs(TOB.DrillRewards or {}) do
        if r.type == "item" then add(r.name, "TOB.DrillRewards") end
    end
    for kind, s in pairs(TOB.SpecialTrolleys or {}) do add(s.item, "TOB.SpecialTrolleys." .. kind) end
    return list
end

-- Settings that need another resource running: {setting, value that needs it, resource}
local Needs = {
    {"TOB.Target", "ox_target", "ox_target"},
    {"TOB.Prompts", "ox_lib", "ox_lib"},
    {"TOB.Dispatch", "ps-dispatch", "ps-dispatch"},
}

function HealthCheck()
    local problems, notes = {}, {}
    local function problem(text) problems[#problems + 1] = text end
    local function note(text) notes[#notes + 1] = text end

    if Framework == nil then
        problem("No framework found. Start qbx_core, es_extended, qb-core or vrp before this resource, or set TOB.Framework.")
    end
    if GetConvar("onesync", "off") == "off" then
        problem("OneSync is off: the server can't check where players are. Add 'set onesync on' to server.cfg.")
    end

    local unchecked = {}
    for _, it in ipairs(ConfiguredItems()) do
        local exists = ItemExists(it[1])
        if exists == false then
            problem(("Item '%s' (%s) doesn't exist in your inventory. Add it (see the install/ folder)."):format(it[1], it[2]))
        elseif exists == nil then
            unchecked[#unchecked + 1] = it[1]
        end
    end
    if #unchecked > 0 then
        note("Couldn't check these items, make sure they exist: " .. table.concat(unchecked, ", ") .. ".")
    end

    for _, n in ipairs(Needs) do
        if TOB[n[1]:sub(5)] == n[2] and not Started(n[3]) then
            problem(("%s = \"%s\", but %s isn't running."):format(n[1], n[2], n[3]))
        end
    end
    local oxGame = TOB.HackMinigame == "ox_lib" or (TOB.HackMinigame == nil and TOB.Minigame)
    if oxGame and not Started("ox_lib") then
        note("The hack's ox_lib skill check is skipped because ox_lib isn't running.")
    end
    if type(TOB.DrillMinigame) == "table" and #TOB.DrillMinigame > 0 and not Started("ox_lib") then
        note("The drill's ox_lib skill check is skipped because ox_lib isn't running.")
    end
    -- minigames played with tobs_minigames (MinigameGame in client/minigames.lua, a shared script) need it running
    local function usesGame(v) return MinigameGame(v) ~= nil end
    local users = {}
    if usesGame(TOB.HackMinigame) or usesGame(TOB.DrillMinigame) then users[#users + 1] = "the global settings" end
    for name, b in pairs(TOB.Banks or {}) do
        if type(b.minigames) == "table" and (usesGame(b.minigames.hack) or usesGame(b.minigames.drill)) then users[#users + 1] = name end
    end
    table.sort(users)
    if #users > 0 and not Started("tobs_minigames") then
        note(("Minigames for %s need tobs_minigames, which isn't running: the normal minigames are used."):format(table.concat(users, ", ")))
    end

    if TOB.Locale ~= nil and Locales ~= nil and Locales[TOB.Locale] == nil then
        problem(("TOB.Locale = \"%s\" doesn't exist in locales/locales.lua; English is used."):format(TOB.Locale))
    end
    if type(SV.Webhook) == "string" and SV.Webhook ~= ""
        and not SV.Webhook:find("^https://discord%.com/api/webhooks/")
        and not SV.Webhook:find("^https://discordapp%.com/api/webhooks/") then
        problem("SV.Webhook doesn't look like a Discord webhook URL (https://discord.com/api/webhooks/...).")
    end
    if (TOB.SpecialTrolleyChance or 0) > 0 and GetConvarInt("sv_enforceGameBuild", 0) < 2060 then
        note("Gold and diamond trolleys use the cash trolley model: set sv_enforceGameBuild 2060 or newer to see them.")
    end

    local missing = {}
    for _, cmd in ipairs({SV.ResetCommand, SV.PauseCommand, SV.TestCommand, SV.CheckCommand}) do
        if cmd and cmd ~= "" and not IsPrincipalAceAllowed("group.admin", "command." .. cmd) then
            missing[#missing + 1] = cmd
        end
    end
    if #missing > 0 then
        note("Admins can't use /" .. table.concat(missing, ", /") .. " yet. Add to server.cfg: add_ace group.admin command.<name> allow")
    end

    return problems, notes
end

local function Report()
    local problems, notes = HealthCheck()
    if #problems == 0 and #notes == 0 then
        print("^2[tobs_bankrobbery] Health check: all good.^7")
        return problems, notes
    end
    print(("^3[tobs_bankrobbery] Health check: %d problem(s), %d note(s)^7"):format(#problems, #notes))
    for _, p in ipairs(problems) do print("^1  problem:^7 " .. p) end
    for _, n in ipairs(notes) do print("^3  note:^7 " .. n) end
    return problems, notes
end

Citizen.CreateThread(function()
    Defaults()
    RegisterCommand(SV.CheckCommand, function(src)
        local problems, notes = Report()
        if src ~= 0 then
            TriggerClientEvent("chat:addMessage", src, {args = {"tobs_bankrobbery",
                ("Health check: %d problem(s), %d note(s). Details in the server console."):format(#problems, #notes)}})
        end
    end, true)
    if not SV.HealthCheck then return end
    Citizen.Wait(5000) -- frameworks and inventories load their items first
    Report()
end)
