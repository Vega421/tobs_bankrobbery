-- The banks. Loaded after config/config.lua.

-- Default door models. A bank can override them with gateModel / vaultModel (a name or a hash number).
TOB.vaultdoor = "v_ilev_cbankvauldoor01"
TOB.door = "v_ilev_cbankvaulgate01"

-- To add a bank, copy a block, give it a new name (for example B2) and fill in its positions
-- (stand on each spot and type /bankcoords).
-- Optional per bank: cash = {min = ..., max = ...} (a full trolley, instead of TOB.TrolleyCash) and
-- cooldown = seconds (instead of TOB.cooldown).
-- enabled = false hides a bank. doors.secondloc adds an inner gate the robber has to hack (like Fleeca).
-- minigames = {hack = ..., drill = ...} plays tobs_minigames' games at this bank (optional resource:
-- https://github.com/Vega421/tobs_minigames): any game name ("hack" = GTA's laptop, "drill" = GTA's drill,
-- "thermite", "keypad", ...) or {type = "thermite", difficulty = "hard"}. Without tobs_minigames the bank
-- uses TOB.HackMinigame / TOB.DrillMinigame. The games' own settings are in tobs_minigames' config.lua.
-- Fleeca positions are from utkuali/Fleeca-Bank-Heists (GPL-3.0). Deposit box positions (boxes) are from
-- qbcore-framework/qb-bankrobbery (GPL-3.0).
TOB.Banks = {
    B1 = {
        label = "Paleto Bay (Blaine County Savings)",
        enabled = true,
        alarm = "PALETO_BAY_SCORE_ALARM",
        minigames = {hack = "hack", drill = "drill"}, -- GTA's hacking laptop and drill (with tobs_minigames)
        doors = {
            startloc = {x = -105.44020080566, y = 6472.8505859375, z = 31.62672996521, h = 10.240501403809, animcoords = {x = -105.46078491211, y = 6471.5737304688, z = 30.626703262329, h = 43.363094329834}}
        },
        gate = {loc = vector3(-105.15334320068, 6472.7075195312, 31.626728057861), h = 42.639282226562, txtloc = vector3(-105.34651184082, 6472.708984375, 31.626726150513)},
        vault = {loc = vector3(-105.84294891357, 6475.4428710938, 31.62670135498), txtloc = vector3(-105.84294891357, 6475.4428710938, 31.62670135498)},
        prop = {
            first = {coords = vector3(-105.875, 6472.126, 31.87645), rot = vector3(-103.4942855835, 6471.9970703125, 31.626707077026)}
        },
        trolley1 = {x = -107.82345581055, y = 6475.4278320312, z = 30.62670135498, h = 221.48431396484},
        trolley2 = {x = -102.43961334229, y = 6477.1049804688, z = 30.626722335815, h = 97.833953857422},
        trolley3 = {x = -104.86431884766, y = 6479.0537109375, z = 30.62672996521, h = 168.07682800293},
        objects = {
            vector3(-107.38459777832, 6474.9672851562, 31.62670135498),
            vector3(-102.97591400146, 6477.0712890625, 31.62670135498),
            vector3(-105.05332183838, 6478.5517578125, 31.626705169678)
        },
        boxes = {vector3(-107.4, 6473.87, 31.62), vector3(-107.66, 6475.61, 31.62), vector3(-103.52, 6475.03, 31.62), vector3(-102.3, 6476.13, 31.66), vector3(-102.43, 6477.45, 31.67), vector3(-103.97, 6478.97, 31.62), vector3(-105.39, 6479.19, 31.67), vector3(-106.57, 6478.01, 31.62)},
        onaction = false,
        lastrobbed = 0
    },
    F1 = {
        label = "Fleeca Alta (Hawick Ave)",
        enabled = TOB.FleecaBanks,
        cash = {min = 30000, max = 50000}, -- Fleeca vaults hold less than Paleto
        gateModel = "v_ilev_gb_vaubar",
        vaultModel = "v_ilev_gb_vauldr",
        doors = {
            startloc = {x = 310.93, y = -284.44, z = 54.16, h = -90, animcoords = {x = 311.05, y = -284, z = 53.16, h = 248.6}},
            secondloc = {x = 312.93, y = -284.45, z = 54.16, h = 160.91, animcoords = {x = 313.41, y = -284.42, z = 53.16, h = 160.91}}
        },
        gate = {loc = vector3(312.93, -284.45, 54.16), h = 160.91, txtloc = vector3(312.93, -284.45, 54.16)},
        vault = {loc = vector3(310.93, -284.44, 54.16), txtloc = vector3(310.93, -284.44, 54.16)},
        prop = {
            first = {coords = vector3(311.5481, -284.5114, 54.285), rot = vector3(90, 180, 21)}
        },
        trolley1 = {x = 313.45, y = -289.24, z = 53.14, h = -15},
        trolley2 = {x = 311.51, y = -288.54, z = 53.14, h = -15},
        trolley3 = {x = 314.49, y = -283.65, z = 53.14, h = 160},
        objects = {vector3(313.45, -289.24, 53.14), vector3(311.51, -288.54, 53.14), vector3(314.49, -283.65, 53.14)},
        boxes = {vector3(311.16, -287.71, 54.14), vector3(311.86, -286.21, 54.14), vector3(313.39, -289.15, 54.14), vector3(311.7, -288.45, 54.14), vector3(314.23, -288.77, 54.14), vector3(314.83, -287.33, 54.14), vector3(315.24, -284.85, 54.14), vector3(314.08, -283.38, 54.14)},
        onaction = false,
        lastrobbed = 0
    },
    F2 = {
        label = "Fleeca Legion Square",
        enabled = TOB.FleecaBanks,
        cash = {min = 30000, max = 50000}, -- Fleeca vaults hold less than Paleto
        gateModel = "v_ilev_gb_vaubar",
        vaultModel = "v_ilev_gb_vauldr",
        doors = {
            startloc = {x = 146.61, y = -1046.02, z = 29.37, h = 244.2, animcoords = {x = 146.75, y = -1045.6, z = 28.37, h = 244.2}},
            secondloc = {x = 148.76, y = -1045.89, z = 29.37, h = 158.54, animcoords = {x = 149.1, y = -1046.08, z = 28.37, h = 158.54}}
        },
        gate = {loc = vector3(148.76, -1045.89, 29.37), h = 158.54, txtloc = vector3(148.76, -1045.89, 29.37)},
        vault = {loc = vector3(146.61, -1046.02, 29.37), txtloc = vector3(146.61, -1046.02, 29.37)},
        prop = {
            first = {coords = vector3(147.22, -1046.148, 29.487), rot = vector3(90, 180, 20)}
        },
        trolley1 = {x = 147.25, y = -1050.38, z = 28.35, h = -15},
        trolley2 = {x = 149.21, y = -1051.07, z = 28.35, h = -15},
        trolley3 = {x = 150.23, y = -1045.4, z = 28.35, h = 160},
        objects = {vector3(147.25, -1050.38, 28.35), vector3(149.21, -1051.07, 28.35), vector3(150.23, -1045.4, 28.35)},
        boxes = {vector3(149.84, -1044.9, 29.34), vector3(151.16, -1046.64, 29.34), vector3(147.16, -1047.72, 29.34), vector3(146.54, -1049.28, 29.34), vector3(146.88, -1050.33, 29.34), vector3(150, -1050.67, 29.34), vector3(149.47, -1051.28, 29.34), vector3(150.58, -1049.09, 29.34)},
        onaction = false,
        lastrobbed = 0
    },
    F3 = {
        label = "Fleeca Rockford Hills",
        enabled = TOB.FleecaBanks,
        cash = {min = 30000, max = 50000}, -- Fleeca vaults hold less than Paleto
        gateModel = "v_ilev_gb_vaubar",
        vaultModel = "v_ilev_gb_vauldr",
        doors = {
            startloc = {x = -1211.07, y = -336.68, z = 37.78, h = 296.76, animcoords = {x = -1211.25, y = -336.37, z = 36.78, h = 296.76}},
            secondloc = {x = -1209.66, y = -335.15, z = 37.78, h = 213.67, animcoords = {x = -1209.4, y = -335.05, z = 36.78, h = 213.67}}
        },
        gate = {loc = vector3(-1209.66, -335.15, 37.78), h = 213.67, txtloc = vector3(-1209.66, -335.15, 37.78)},
        vault = {loc = vector3(-1211.07, -336.68, 37.78), txtloc = vector3(-1211.07, -336.68, 37.78)},
        prop = {
            first = {coords = vector3(-1210.5, -336.37, 37.901), rot = vector3(-90, 0, 25)}
        },
        trolley1 = {x = -1207.5, y = -339.2, z = 36.76, h = 30},
        trolley2 = {x = -1205.61, y = -338.24, z = 36.76, h = 30},
        trolley3 = {x = -1209.1, y = -333.59, z = 36.76, h = 210},
        objects = {vector3(-1207.5, -339.2, 36.76), vector3(-1205.61, -338.24, 36.76), vector3(-1209.1, -333.59, 36.76)},
        boxes = {vector3(-1209.68, -333.65, 37.75), vector3(-1207.46, -333.77, 37.75), vector3(-1209.45, -337.47, 37.75), vector3(-1208.65, -339.06, 37.75), vector3(-1207.75, -339.42, 37.75), vector3(-1205.28, -338.14, 37.75), vector3(-1205.08, -337.28, 37.75), vector3(-1205.92, -335.75, 37.75)},
        onaction = false,
        lastrobbed = 0
    },
    F4 = {
        label = "Fleeca Great Ocean Highway",
        enabled = TOB.FleecaBanks,
        cash = {min = 30000, max = 50000}, -- Fleeca vaults hold less than Paleto
        gateModel = "v_ilev_gb_vaubar",
        vaultModel = 4231427725, -- this branch has a different vault door
        doors = {
            startloc = {x = -2956.68, y = 481.34, z = 15.7, h = 353.97, animcoords = {x = -2956.68, y = 481.34, z = 14.7, h = 353.97}},
            secondloc = {x = -2957.26, y = 483.53, z = 15.7, h = 267.73, animcoords = {x = -2957.26, y = 483.53, z = 14.7, h = 267.73}}
        },
        gate = {loc = vector3(-2957.26, 483.53, 15.7), h = 267.73, txtloc = vector3(-2957.26, 483.53, 15.7)},
        vault = {loc = vector3(-2956.68, 481.34, 15.7), txtloc = vector3(-2956.68, 481.34, 15.7)},
        prop = {
            first = {coords = vector3(-2956.59, 482.05, 15.815), rot = vector3(90, 180, -88)}
        },
        trolley1 = {x = -2952.69, y = 483.34, z = 14.68, h = 85},
        trolley2 = {x = -2952.57, y = 485.18, z = 14.68, h = 85},
        trolley3 = {x = -2958.35, y = 484.69, z = 14.68, h = 270},
        objects = {vector3(-2952.69, 483.34, 14.68), vector3(-2952.57, 485.18, 14.68), vector3(-2958.35, 484.69, 14.68)},
        boxes = {vector3(-2958.54, 484.1, 15.67), vector3(-2957.3, 485.95, 15.67), vector3(-2955.09, 482.43, 15.67), vector3(-2953.26, 482.42, 15.67), vector3(-2952.63, 483.09, 15.67), vector3(-2952.45, 485.66, 15.67), vector3(-2953.13, 486.26, 15.67), vector3(-2954.98, 486.37, 15.67)},
        onaction = false,
        lastrobbed = 0
    },
    F5 = {
        label = "Fleeca Burton",
        enabled = TOB.FleecaBanks,
        cash = {min = 30000, max = 50000}, -- Fleeca vaults hold less than Paleto
        gateModel = "v_ilev_gb_vaubar",
        vaultModel = "v_ilev_gb_vauldr",
        doors = {
            startloc = {x = -354.15, y = -55.11, z = 49.04, h = 251.05, animcoords = {x = -354.15, y = -55.11, z = 48.04, h = 251.05}},
            secondloc = {x = -351.97, y = -55.18, z = 49.04, h = 159.79, animcoords = {x = -351.97, y = -55.18, z = 48.04, h = 159.79}}
        },
        gate = {loc = vector3(-351.97, -55.18, 49.04), h = 159.79, txtloc = vector3(-351.97, -55.18, 49.04)},
        vault = {loc = vector3(-354.15, -55.11, 49.04), txtloc = vector3(-354.15, -55.11, 49.04)},
        prop = {
            first = {coords = vector3(-353.5, -55.37, 49.157), rot = vector3(90, 180, 20)}
        },
        trolley1 = {x = -353.34, y = -59.48, z = 48.01, h = -15},
        trolley2 = {x = -351.57, y = -60.09, z = 48.01, h = -15},
        trolley3 = {x = -350.57, y = -54.45, z = 48.01, h = 160},
        objects = {vector3(-353.34, -59.48, 48.01), vector3(-351.57, -60.09, 48.01), vector3(-350.57, -54.45, 48.01)},
        boxes = {vector3(-350.99, -54.13, 49.01), vector3(-349.53, -55.77, 49.01), vector3(-353.54, -56.94, 49.01), vector3(-354.09, -58.55, 49.01), vector3(-353.81, -59.48, 49.01), vector3(-349.8, -58.3, 49.01), vector3(-351.14, -60.37, 49.01), vector3(-350.4, -59.92, 49.01)},
        onaction = false,
        lastrobbed = 0
    },
    F6 = {
        label = "Fleeca Harmony (Route 68)",
        enabled = TOB.FleecaBanks,
        cash = {min = 30000, max = 50000}, -- Fleeca vaults hold less than Paleto
        gateModel = "v_ilev_gb_vaubar",
        vaultModel = "v_ilev_gb_vauldr",
        doors = {
            startloc = {x = 1176.4, y = 2712.75, z = 38.09, h = 84.83, animcoords = {x = 1176.4, y = 2712.75, z = 37.09, h = 84.83}},
            secondloc = {x = 1174.24, y = 2712.47, z = 38.09, h = 359.05, animcoords = {x = 1174.33, y = 2712.09, z = 37.09, h = 359.05}}
        },
        gate = {loc = vector3(1174.24, 2712.47, 38.09), h = 160.91, txtloc = vector3(1174.24, 2712.47, 38.09)},
        vault = {loc = vector3(1176.4, 2712.75, 38.09), txtloc = vector3(1176.4, 2712.75, 38.09)},
        prop = {
            first = {coords = vector3(1175.7, 2712.82, 38.207), rot = vector3(90, 180, 180)}
        },
        trolley1 = {x = 1174.24, y = 2716.69, z = 37.07, h = -180},
        trolley2 = {x = 1172.27, y = 2716.67, z = 37.07, h = -180},
        trolley3 = {x = 1173.23, y = 2711.02, z = 37.07, h = 0},
        objects = {vector3(1174.24, 2716.69, 37.07), vector3(1172.27, 2716.67, 37.07), vector3(1173.23, 2711.02, 37.07)},
        boxes = {vector3(1173.69, 2710.76, 38.07), vector3(1171.78, 2711.94, 38.07), vector3(1175.25, 2714.51, 38.07), vector3(1175.26, 2715.97, 38.07), vector3(1174.27, 2716.83, 38.07), vector3(1172.32, 2716.82, 38.07), vector3(1171.25, 2716.08, 38.07), vector3(1171.23, 2714.44, 38.07)},
        onaction = false,
        lastrobbed = 0
    }
}
