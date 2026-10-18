TOB = {}

-- Framework: "auto" (detects qbx_core, es_extended or qb-core), "qbox", "esx" or "qb"
TOB.Framework = "auto"

-- Language: "en" (English), "da" (Danish), "de" (German), "sv" (Swedish), "no" (Norwegian), "nl" (Dutch),
-- "fr" (French), "es" (Spanish), "pt" (Brazilian Portuguese), "pl" (Polish) or "it" (Italian).
-- Texts are in locales/locales.lua.
TOB.Locale = "en"

-- Police
TOB.PoliceJob = "police" -- ESX / QBCore / Qbox job that counts as police. Several jobs: {"police", "sheriff"}
TOB.PoliceOnDuty = true -- QBCore / Qbox: only count officers who are on duty

-- Heist
TOB.mincops = 4 -- police needed online to start the heist
TOB.hacktime = 60000 -- hack duration in milliseconds (60000 = 1 min). Gives police time to arrive
TOB.timer = 300 -- seconds after the hack before the doors lock again (also the time limit for TOB.VaultItem)
TOB.VaultCloseDelay = 30 -- seconds between the last trolley being looted and the vault closing
TOB.cooldown = 600 -- seconds before a bank can be robbed again (600 = 10 min)
TOB.MinCrew = 1 -- robbers (not police) that must be near the panel to start. 1 = solo is fine
TOB.CrewRadius = 15.0 -- meters around the start panel that count as "near"
TOB.OneAtATime = false -- true = only one heist on the whole server at a time
TOB.GlobalCooldown = 0 -- seconds after any heist before any bank can be robbed (0 = off, each bank only has its own cooldown)

-- Hacking minigame, played before the hack. Failing it ends the heist; police are already alerted.
--   "ox_lib" = ox_lib skill check (skipped if ox_lib isn't running), "none" = no minigame,
--   or your own function using another minigame resource. It must return true when the player passed:
--   TOB.HackMinigame = function(bank)
--       return exports["my_minigame"]:Start(...) -- see that resource's documentation
--   end
-- A bank can play its own minigame with tobs_minigames: see minigames in config/banks.lua.
TOB.HackMinigame = "ox_lib"
TOB.CardTime = 150 -- seconds the robber has for the card, the laptop and the minigame before the heist fails
                   -- (tobs_minigames' laptop gives up to 90 s on easy, plus its how-to card and the animation)
TOB.MinigameDifficulty = {"easy", "easy", "medium", "medium"} -- ox_lib: one entry per round: "easy", "medium" or "hard"
TOB.MinigameKeys = {"w", "a", "s", "d"} -- ox_lib: keys the skill check can ask for

-- Extra vault step: after the hack the robber must use this item on the vault door.
TOB.VaultItem = "" -- item name, e.g. "thermite" or "drill". "" = the vault opens right after the hack
TOB.VaultItemLabel = "thermite" -- name shown to players
TOB.VaultItemTime = 15000 -- milliseconds the robber works on the vault door

-- Inner gate (banks with doors.secondloc: all of them by default): after the vault opens, the robber opens a
-- second panel to reach the trolleys behind it (gateTrolleys in config/banks.lua). Its minigame is the bank's
-- gate game (minigames in config/banks.lua: thermite by default).
TOB.GateItem = "" -- item needed for the second panel, e.g. "secure_card". "" = no item needed
TOB.GateItemLabel = "Secure ID Card" -- name shown to players
TOB.GateHackTime = 10000 -- milliseconds opening the gate takes after its minigame

-- Rewards. A full trolley pays TOB.TrolleyCash; stopping early pays for the time spent grabbing.
TOB.TrolleyCash = {min = 50000, max = 80000} -- cash in one full trolley (3 trolleys per heist)
TOB.GrabTime = 37 -- seconds it takes to empty a trolley (the grab animation is played at the speed that matches)
TOB.black = false -- true pays dirty money instead of cash (ESX: the black_money account, others: the TOB.blackmoney item)
TOB.blackmoney = "auto" -- dirty money item: "auto" = "black_money" (QBCore / Qbox)
TOB.RewardItem = "" -- give this item instead of money, e.g. "markedbills". "" = pay money
TOB.RewardItemCount = "cash" -- "cash" = item count equals the cash amount (money-like items), or the number of items in a full trolley (e.g. 10 bags)
-- Marked bills (QBCore / Qbox laundering): each trolley pays one item whose metadata holds its cash value
-- ({worth = ...}, like qb-bankrobbery). Needs qb-inventory or ox_inventory; other setups get cash instead.
TOB.MarkedBills = false
TOB.MarkedBillsItem = "markedbills"

-- GPS tracker hidden in the loot: police follow the robber on the map for a while after they grabbed a trolley
TOB.Tracker = {
    enabled = false,
    chance = 30,       -- % chance per grabbed trolley
    duration = 180,    -- seconds police can follow the robber
    interval = 5,      -- seconds between position updates on the police map
    warnRobber = true, -- tell the robber they're being tracked
}

-- Dye pack in the loot: it bursts when the robber finishes grabbing (red smoke) and stains the money
TOB.DyePack = {
    enabled = false,
    chance = 20,  -- % chance per trolley
    loss = 0.25,  -- part of the trolley's value that is ruined (0.25 = 25%)
    dirty = true, -- the rest is paid as dirty money (like TOB.black)
    smoke = 10,   -- seconds of red smoke on the robber
}

-- Animations and sound
TOB.LaptopHack = true -- laptop hacking animation at the panel during the hack (also at the inner gate)
TOB.LaptopSceneOffset = 1.5 -- metres above a bank's animcoords (floor level) the laptop scene is placed (Qbox
                            -- test: 1.5 puts the laptop on the panel's shelf; at 0 the player went under the floor)
TOB.LaptopSceneForward = 0.45 -- metres the scene is moved forward, towards the panel, so the player isn't pulled
                              -- backwards when the animation starts. Raise it (0.55, 0.65) if they still jerk back
TOB.VaultItemAnim = "thermite" -- animation for TOB.VaultItem: "thermite" (charge + burning sparks) or "weld"
TOB.Alarm = true -- play the bank's alarm (banks with alarm = "...") until the heist ends. Fleeca banks use a silent alarm

-- Grabbing
TOB.StopGrabKey = 73 -- key to stop grabbing early and keep what you grabbed (73 = X). false = can't stop
TOB.LootCounter = true -- show the cash (or gold bars / diamonds) grabbed on screen, and everyone's total at the end

-- Who spawns the trolleys: "auto" = the server when OneSync is on (they stay when players leave),
-- otherwise the heist leader's game. "server" or "client" to force one.
TOB.TrolleySpawn = "auto"

-- Special trolleys: sometimes one trolley holds gold or diamonds and pays more.
-- Their models are from the Casino Heist update: they need game build 2060 or newer (sv_enforceGameBuild).
TOB.SpecialTrolleyChance = 25 -- % chance per heist that one trolley is special (0 = off)
TOB.SpecialTrolleys = {
    gold = {model = "ch_prop_gold_trolly_01a", pile = "ch_prop_gold_bar_01a", empty = false, multiplier = 2.0, item = "goldbar", itemCount = 44},
    diamond = {model = "ch_prop_diamond_trolly_01a", pile = "ch_prop_vault_dimaondbox_01a", empty = false, multiplier = 3.0, item = "diamond", itemCount = 44},
    -- empty = the model a looted trolley turns into. false = GTA has no empty version of that trolley (the
    -- casino gold and diamond trolleys): it stays, held empty in the last frame of the grab animation.
    -- The casino trolleys empty while grabbing; base-game ones like prop_gold_trolly_full don't.
    -- item = "goldbar", itemCount = 44 pays that item instead of cash (itemCount = items in a full trolley; 44 is
    -- one per grab of the animation, measured in game; the
    -- items are worth what your server pays for them, e.g. at a fence). item = "" pays cash (the trolley's
    -- value times multiplier). An item your inventory doesn't have is paid as cash (add them: install/).
}

-- Deposit boxes in the vault: drill them open while the vault is open
TOB.DepositBoxes = true
TOB.DrillItem = "drill" -- item needed to drill (not used up). "" = no item needed
TOB.DrillItemLabel = "drill" -- name shown to players
TOB.DrillTime = 15000 -- milliseconds per box
TOB.DrillMinigame = {"easy", "medium"} -- ox_lib skill check while drilling ({} = none), or your own function(bank, box) like TOB.HackMinigame
-- What a box can contain. chance = weight. type "money" or "item" (the item must exist in your inventory)
TOB.DrillRewards = {
    {type = "money", min = 1500, max = 4000, chance = 60},
    {type = "money", min = 5000, max = 12000, chance = 25},
    {type = "nothing", chance = 15},
    -- {type = "item", name = "goldbar", min = 1, max = 3, chance = 10},
    -- {type = "item", name = "rolex", min = 1, max = 2, chance = 10},
}

-- Interaction and UI
TOB.Target = "auto" -- "auto" (ox_target if running, else qb-target, else press E), "ox_target", "qb-target" or "none" (always press E)
TOB.Prompts = "auto" -- "press E" prompts: "auto" (ox_lib text UI if running, otherwise 3D text), "ox_lib" or "3d"
TOB.Progress = "auto" -- "auto" (ox_lib, else QBCore's progressbar, else progressBars, else no bar), "ox_lib", "progressbar", "progressBars" or "none"
TOB.Notify = "auto" -- "auto", "ox_lib", "mythic_notify", "framework" (ESX / QBCore notifications) or "native". "auto" uses ox_lib, then mythic_notify, then the framework's
TOB.NotifyTitle = "Bank Robbery" -- title shown on ox_lib notifications
TOB.CoordsCommand = "bankcoords" -- prints your position (for adding banks) in chat and the F8 console. false = off

-- Police alerts
TOB.BuiltInPoliceAlert = true -- notification + map blip for police. Set false if your dispatch script handles it

-- Dispatch alert, sent from the robber's game when the heist starts:
--   "auto" = ps-dispatch if it's running, otherwise TOB.DispatchAlert below
--   "ps-dispatch" = its Paleto / Fleeca bank robbery alerts, "custom" = TOB.DispatchAlert, "none" = off
-- Server-side dispatch scripts: use SV.DispatchAlert in config/config_server.lua.
TOB.Dispatch = "auto"

-- Your own dispatch call (TOB.Dispatch = "auto" or "custom"). Paste your dispatch script's alert here,
-- using its own documentation. coords is the bank's position (vector3), bank is "B1", "F1", ...
TOB.DispatchAlert = function(coords, bank)
    -- Example (replace with your dispatch script's call):
    -- exports["my_dispatch"]:SendAlert({code = "10-90", message = "Bank robbery", coords = coords})
end

-- Banks
TOB.FleecaBanks = true -- include the 6 Fleeca banks. Set false if you run another Fleeca heist script
-- The banks themselves (positions, and per-bank cash and cooldown) are in config/banks.lua

-- The framework bridge (bridge/, shared with the other tobs_ scripts) reads these. Don't change
-- them here: change the TOB settings above. See bridge/README.md.
BridgeConfig = {
    Framework = TOB.Framework,
    PoliceJobs = TOB.PoliceJob,
    PoliceOnDuty = TOB.PoliceOnDuty,
    BlackMoney = TOB.blackmoney,
    Notify = "framework", -- this script has its own Notify() in client/util.lua (TOB.Notify)
}
