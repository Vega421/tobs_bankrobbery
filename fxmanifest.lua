fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Vega"
description "Paleto and Fleeca bank heists for Qbox, ESX, QBCore and vRP"
version "2.1.0"
repository "https://github.com/Vega421/tobs_bankrobbery"

shared_scripts {
    "config/config.lua",
    "config/banks.lua",
    "locales/locales.lua",
    "bridge/framework.lua",
}

client_scripts {
    "client/callbacks.lua",
    "bridge/qbox/client.lua",
    "bridge/esx/client.lua",
    "bridge/qb/client.lua",
    "bridge/vrp/client.lua",
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
    "server/callbacks.lua",
    "bridge/qbox/server.lua",
    "bridge/esx/server.lua",
    "bridge/qb/server.lua",
    "bridge/vrp/server.lua",
    "server/util.lua",
    "server/heist.lua",
    "server/loot.lua",
    "server/tracker.lua",
    "server/boxes.lua",
    "server/doors.lua",
    "server/admin.lua",
    "server/api.lua",
}
