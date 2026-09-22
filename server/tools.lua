-- Admin tools and helpers for the heist code:
--   /tobpause [reason]  stops new heists server-wide (running heists go on); /tobpause off allows them again
--   /tobtest            test mode for the admin who types it: their heists skip the police, crew,
--                       cooldown and global rules, don't set cooldowns, and pay nothing (SV.TestModePayouts)
--   Refusal texts that say why a heist can't start, and sounds everyone in the bank hears.
-- Commands need an ace, e.g.  add_ace group.admin command.tobpause allow

-- Defaults for settings that can also go in config/config_server.lua. Set when the resource has
-- loaded, because this file loads before the config.
local function Defaults()
    SV.PauseCommand = SV.PauseCommand or "tobpause"
    SV.TestCommand = SV.TestCommand or "tobtest"
    if SV.TestModePayouts == nil then SV.TestModePayouts = false end
    if SV.ShowPoliceCount == nil then SV.ShowPoliceCount = false end -- refusals say how many police are on duty
    SV.BankSoundRange = SV.BankSoundRange or 40.0 -- meters around the sound where players hear it
end

local Paused -- nil, or {reason = "...", by = "name"}
local Testers = {} -- [source] = true while test mode is on
local TestHeists = {} -- [bank] = source of the admin testing it

local function Name(src)
    if src == 0 then return "console" end
    return GetPlayerName(src) or ("player " .. tostring(src))
end

-- Console line plus a Discord message when SV.Webhook is set (Log in server/util.lua)
local function ToolLog(text)
    Log("Admin", text, 16750848)
end

local function Tell(src, text)
    if src == 0 then print(text) return end
    TriggerClientEvent("chat:addMessage", src, {args = {"tobs_bankrobbery", text}})
end

-- HEIST SWITCH

-- true and the reason ("" if none) while heists are paused
function HeistsPaused()
    if Paused == nil then return false end
    return true, Paused.reason
end

-- The refusal text for a paused server
function PauseRefusal()
    if Paused and Paused.reason ~= "" then return LX("refuse_paused_reason", Paused.reason) end
    return LX("refuse_paused")
end

local function PauseCommand(src, args)
    if args[1] == "off" then
        if Paused == nil then Tell(src, LX("resumed")) return end
        Paused = nil
        ToolLog(Name(src) .. " allowed bank heists again.")
        Tell(src, LX("resumed"))
        return
    end
    Paused = {reason = table.concat(args, " "), by = Name(src)}
    ToolLog(Name(src) .. " paused bank heists" .. (Paused.reason ~= "" and (": " .. Paused.reason) or "."))
    Tell(src, LX("paused"))
end

-- TEST MODE

-- True while this player has test mode on: skip the police, crew, cooldown and global rules for them
function IsTester(src)
    return Testers[src] == true
end

-- Call when a heist starts: remembers that it's a test heist. Returns true if it is.
function StartTestHeist(bank, src)
    if not IsTester(src) then TestHeists[bank] = nil return false end
    TestHeists[bank] = src -- the heist's own start log says [TEST]
    return true
end

function IsTestHeist(bank)
    return TestHeists[bank] ~= nil
end

-- True when this heist's payouts should be skipped (a test heist and SV.TestModePayouts is off)
function TestPayoutBlocked(bank)
    return IsTestHeist(bank) and not SV.TestModePayouts
end

-- Call when a heist ends. Returns true if it was a test heist (then don't save a cooldown).
function EndTestHeist(bank)
    local was = TestHeists[bank] ~= nil
    TestHeists[bank] = nil
    return was
end

local function TestCommand(src)
    if src == 0 then print(LX("test_players_only")) return end
    Testers[src] = not Testers[src] or nil
    if Testers[src] then
        ToolLog(Name(src) .. " turned test mode on.")
        Tell(src, SV.TestModePayouts and LX("test_on") or LX("test_on_nopay"))
    else
        ToolLog(Name(src) .. " turned test mode off.")
        Tell(src, LX("test_off"))
    end
end

AddEventHandler("playerDropped", function()
    Testers[source] = nil
end)

-- CLEARER REFUSALS (texts for the heist code's existing "can't start" messages)

-- need = police needed, have = police on duty
function PoliceRefusal(need, have)
    if SV.ShowPoliceCount then return LX("refuse_police_count", need, have) end
    return LX("refuse_police")
end

-- secondsLeft until the bank (or, with global = true, any bank) can be robbed
function CooldownRefusal(secondsLeft, global)
    return LX(global and "refuse_global_cooldown" or "refuse_cooldown", FormatDuration(secondsLeft))
end

-- key without "refuse_": "one_at_a_time", "busy", "restart", "crew", "item", "police_job", "bank_off"
function RefusalText(key, ...)
    return LX("refuse_" .. key, ...)
end

-- SOUND FOR THE WHOLE BUILDING

-- Plays a bank sound for everyone near it except `from` (who hears their own):
--   "drill_on" / "drill_off" (box = deposit box number), "vault" (the vault door opening)
function BankSound(bank, kind, box, from)
    TriggerClientEvent("tobs_bankrobbery:bankSound", -1, bank, kind, box, from or 0, SV.BankSoundRange)
end

Citizen.CreateThread(function()
    Defaults()
    RegisterCommand(SV.PauseCommand, PauseCommand, true)
    RegisterCommand(SV.TestCommand, TestCommand, true)
end)
