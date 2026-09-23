fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Vega"
description "Paleto and Fleeca bank heists for Qbox, ESX and QBCore"
version "1.0.0"
repository "https://github.com/Vega421/tobs_bankrobbery"

-- Minigames per bank (played with tobs_minigames when it runs), admin tools (/tobpause, /tobtest,
-- /tobcheck) and bank sounds. Their own blocks so they merge without touching the lists below. They load
-- first, so they only use the config, the bridges and the heist code once the resource has started.
shared_scripts {
    "locales/tools.lua",
    "client/minigames.lua", -- shared: the server's health check uses its list of games
}

client_scripts {
    "client/sounds.lua",
}

server_scripts {
    "server/tools.lua",
    "server/healthcheck.lua",
}

shared_scripts {
    "config/config.lua",
    "config/banks.lua",
    "locales/locales.lua",
    "bridge/framework.lua",
    "bridge/shared/callbacks.lua",
}

client_scripts {
    "bridge/qbox/client.lua",
    "bridge/esx/client.lua",
    "bridge/qb/client.lua",
    "bridge/shared/ui.lua",
    "bridge/shared/notify.lua",
    "client/util.lua",
    "client/heist.lua",
    "client/loot.lua",
    "client/boxes.lua",
    "client/police.lua",
    "client/tracker.lua",
    "client/doors.lua",
    "client/main.lua",
}

server_scripts {
    "config/config_server.lua",
    "bridge/shared/db.lua",
    "bridge/qbox/core.lua",
    "bridge/qbox/data.lua",
    "bridge/qb/core.lua",
    "bridge/esx/core.lua",
    "bridge/esx/data.lua",
    "server/util.lua",
    "server/heist.lua",
    "server/loot.lua",
    "server/tracker.lua",
    "server/boxes.lua",
    "server/doors.lua",
    "server/admin.lua",
    "server/api.lua",
}
