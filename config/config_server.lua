-- Server-only settings. This file is never sent to players, so secrets like the webhook are safe here.
SV = {}

-- Discord logs: heist started/ended with payouts, admin resets and blocked cheat attempts.
-- Paste a webhook URL (Discord channel settings > Integrations > Webhooks). "" = no Discord logs.
SV.Webhook = ""
SV.LogAntiCheat = true -- also log blocked cheat attempts (max once a minute per player and reason)

-- Admin command to reset a stuck heist: /tobreset [bank]. Give admins permission in server.cfg:
--   add_ace group.admin command.tobreset allow
SV.ResetCommand = "tobreset"

-- Block new heists this many minutes before a txAdmin scheduled restart (0 = off).
-- txAdmin warns at 30, 15, 10, 5, 4, 3, 2 and 1 minutes, so the block starts at the first warning inside this window.
SV.BlockBeforeRestart = 15

-- Print a message in the server console when a newer version is released on GitHub
SV.CheckForUpdates = true

-- Server-side dispatch or logging: runs on the server when a heist starts. Paste your dispatch
-- script's server-side alert here (from its own documentation). For client-side dispatch scripts
-- use TOB.Dispatch in config/config.lua instead.
-- bank = "B1", "F1", ...; coords = vector3 of the bank; playerId = the robber; label = the bank's name
SV.DispatchAlert = function(bank, coords, playerId, label)
end
