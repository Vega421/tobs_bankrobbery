# Changelog

All notable changes to tobs_bankrobbery. Each version is also a [GitHub release](https://github.com/Vega421/tobs_bankrobbery/releases) with a ready-to-use zip.

Full documentation: https://vega421.github.io/scripts/tobs-bankrobbery/

## 1.0.1 · not released yet

Fixes from playing 1.0.0 on the Qbox test server.

- **Laptop hack:** the player is no longer pulled backwards when the animation starts. The scene sits `TOB.LaptopSceneForward` (new, 0.45 m) in front of the panel and `TOB.LaptopSceneOffset` (now 1.5 m) above the floor, the access card stays in the hand, and other players can't push the robber out of the scene
- **Inner gate:** hacked like the vault, with the laptop at its panel and the bank's minigame. The gate timer only starts once the minigame is passed; a failed gate minigame frees the gate for another try (with a new gate item) instead of opening it anyway
- **The inner gate has its own minigame:** `gate` in a bank's `minigames` (`config/banks.lua`), thermite at every bank by default. Any game but GTA's laptop plays without the laptop scene, with tobs_minigames' own animation, and the progress bar says "Opening the gate...". A bank without `gate` plays its hack minigame again, and without tobs_minigames the gate uses the laptop and the normal minigame as before
- **The inner gate's texts** say "open" instead of "hack" ("Open the inner gate", "Opening the gate failed. Try again."), so they fit any gate minigame
- **5 new languages:** French (`fr`), Spanish (`es`), Brazilian Portuguese (`pt`), Polish (`pl`) and Italian (`it`), for the heist and the admin tools. 11 in total; set `TOB.Locale` in `config/config.lua`
- **Grabbing ends with the money:** the trolley's payout starts with the grab animation instead of when the server says yes (the intro and taking control of the trolley came first), and the grab stops as soon as the trolley is paid out. Before, the loot counter stopped while the player kept grabbing from a trolley that still looked full. A grab that runs to its end always pays the whole trolley. The grab animation plays at the speed that empties the trolley in exactly `TOB.GrabTime` (at a fixed speed the trolley was empty early and the grabbing started over), and the money is also asked for by time, so the counter keeps going while the game is alt-tabbed
- **Looting sometimes did nothing:** the grab only looked for the trolley kind the player's game expected, so when the server had spawned another kind (gold where the game expected cash) it gave up silently and the trolley stayed taken for the rest of the heist. It now finds any trolley at the spot, and a grab that can't start hands the trolley back (nothing paid) so it can be looted again. Loot on a trolley behind a closed inner gate now says "Open the inner gate to reach the trolleys behind it." instead of doing nothing. The server also answers every loot request, and a lost answer no longer blocks looting until a restart
- **Diamond and gold trolleys:** an emptied diamond trolley came back full (its "empty" model was the full trolley, and GTA has no empty casino diamond trolley): it now stays and is held in the grab animation's last frame, in every player's game (`empty = false`). Gold trolleys showed as cash trolleys (their "empty" model didn't exist): the casino gold trolley is now held empty the same way, and its bars disappear while grabbing
- **Fleeca inner gate: the right trolleys.** Two trolleys are behind the gate (trolley1 and trolley2) and one is in front of it, but the script locked trolley3 (in front) and left the two behind the bars lootable. Banks now list theirs in `gateTrolleys` (default `{"trolley1", "trolley2"}`; Paleto `{"trolley2", "trolley3"}`, with trolley1 in front); the old `gateTrolley` still works
- **Paleto's vault door** swung into the vault: it's hung the other way than the Fleeca doors. Each bank sets the direction with `vaultTurn` (degrees to open: -90 by default, Paleto 90)
- **Gold and diamond trolleys stand behind the inner gate** (one of its trolleys, at random), as the reward for getting through it; at banks without a gate, any trolley
- **Gold and diamond trolleys pay gold bars and diamonds:** 44 `goldbar` / 44 `diamond` for a full trolley, one per grab of the animation (`item` / `itemCount` in `TOB.SpecialTrolleys`; `item = ""` pays cash as before). Both items are in the `install/` files, and `install/images/` has inventory images for `id_card_f`, `diamond` and `secure_card`. An item the inventory doesn't have is paid as cash instead of nothing. The loot counter counts the items ("12x Gold Bar") and the end message says "You grabbed 20x Gold Bar."
- **Trolleys** spawned by the leader are networked mission entities, so every player sees them
- **Standing spots:** players are put on a bank's animcoords at floor level (1 m higher left them floating)
- **All Fleeca banks** use the hacking laptop and drill minigames (with tobs_minigames), and Paleto has its own cash range (40,000–60,000)

## 1.0.0 · 2026-09-28

**The first release of tobs_bankrobbery as its own script.** It grew out of tobs_blaine and has been
rewritten: one resource for Qbox, ESX and QBCore, the server runs the whole heist, and the framework
code is shared with the other tobs_ scripts (the `bridge/` folder).

Tested in game on Qbox. QBCore and ESX are covered by the automated tests (a fake framework for
each), but haven't been played on a live server yet: please report anything that doesn't work there.

**Frameworks**
- **Qbox, ESX and QBCore in one resource**, detected automatically (`TOB.Framework = "auto"`). Qbox and QBCore count only on-duty police (`TOB.PoliceOnDuty`); items go through ox_inventory or qb-inventory
- **No vRP.** vRP servers can keep using [tobs_blaine](https://github.com/Vega421/tobs_blaine) 1.5.0 (archived)
- `TOB.PoliceJob` can be a list of jobs, for example `{"police", "sheriff"}`; `TOB.Notify = "framework"` uses the framework's notifications
- `/bankcoords` prints your position ready to paste into a new bank (`TOB.CoordsCommand`), and the `install/` folder has the items for every inventory
- The framework bridge (`bridge/`) is now the same code as in the other tobs_ scripts, with the database queries and ox_lib helpers included. Settings are unchanged (`TOB.Framework`, `TOB.PoliceJob`, `TOB.PoliceOnDuty`); `TOB.PoliceGroup` and `install/vrp.lua` are gone

**Minigames**
- **Minigames per bank** with [tobs_minigames](https://github.com/Vega421/tobs_minigames) (optional): set `minigames = {hack = ..., drill = ...}` on a bank in `config/banks.lua`. Any of its games works, with a difficulty: `{type = "thermite", difficulty = "hard"}`
- **Paleto plays GTA's hacking laptop and GTA's drill** when tobs_minigames is running. The drill screen replaces the progress bar and never finishes faster than `TOB.DrillTime`
- Without tobs_minigames, or when a GTA screen doesn't load, the bank's normal minigame runs instead. A bank can also set its own ox_lib difficulties: `hack = {"medium", "hard"}`
- `TOB.CardTime` (default 150 seconds): time for the card, the laptop and the minigame before the heist fails. It was a fixed 90 seconds, too short for the laptop on easy

**Admin tools**
- **`/tobpause [reason]`** stops new heists server-wide (running heists go on); `/tobpause off` allows them again
- **`/tobtest`** turns on test mode for you: your heists skip the police, crew and cooldown rules, set no cooldowns and pay nothing (`SV.TestModePayouts`). They're marked `[TEST]` in the Discord log
- **`/tobcheck`** lists missing items, resources and permissions; it also runs in the console when the resource starts (`SV.HealthCheck`)
- **Clearer refusals:** a heist that can't start says why, including how long the cooldown has left. `SV.ShowPoliceCount` also says how many police are needed
- **Everyone in the bank hears the drill and the vault door** (`SV.BankSoundRange`)
- Give admins the commands: `add_ace group.admin command.tobpause allow` (and `tobtest`, `tobcheck`)

**Security**
- The server runs every step of the heist and its timers (hack, vault item, inner gate, security timer, vault closing). Cheaters can no longer skip the hack, open the vault early, loot before the vault is open, or keep the vault open
- Trolleys pay for the time actually spent grabbing, so asking for cash faster pays nothing more
- One deposit box at a time per player
- Start requests are rate limited, door events only accept police, and Discord logs can't ping @everyone

**Rewards**
- **Trolleys are worth `TOB.TrolleyCash`** (default $50,000–80,000 each) and pay out over `TOB.GrabTime` seconds. Stopping early pays for the time spent. `TOB.mincash`, `TOB.maxcash` and `TOB.MaxPiles` are gone: set `TOB.TrolleyCash` instead
- `TOB.RewardItemCount` as a number is now the items in a full trolley (was per pile). Item trolleys use `itemCount`
- Full pockets: loot waits until there's room (trolleys), or the deposit box stays closed, instead of the loot being lost
- Discord logs and totals show items as items, not as cash

**New**
- **Crew takeover:** if the robber disconnects, the nearest crew member leads the heist instead of it ending
- **Any hacking minigame:** `TOB.HackMinigame` = `"ox_lib"`, `"none"` or your own function using another minigame resource. `TOB.DrillMinigame` can be a function too
- **Dispatch:** `TOB.Dispatch = "auto"` sends ps-dispatch's Paleto / Fleeca bank alerts when ps-dispatch is running. `SV.DispatchAlert` in `config_server.lua` for server-side dispatch scripts
- **For other resources:** server events `tobs_bankrobbery:heistStarted`, `vaultOpened`, `heistEnded`, and exports `IsHeistActive`, `GetHeist`, `GetBanks`, `ResetHeist`
- **ox_lib text prompts** instead of 3D text when ox_lib is running (`TOB.Prompts`)
- Cooldowns are saved, so restarting the script or the server doesn't reset them
- The countdown is shown to the whole crew at the bank, as minutes and seconds, including the vault closing
- Police see the bank's blip for the whole heist, also officers who go on duty during it
- A warning in the console when OneSync is off (the anti-cheat needs it to check positions)

**More**
- **GPS tracker** in the loot (`TOB.Tracker`, off by default): police follow the robber on the map for a while after the grab
- **Dye pack** in the loot (`TOB.DyePack`, off by default): red smoke, part of the money ruined and the rest paid as dirty money
- **Marked bills** (`TOB.MarkedBills`): each trolley pays one `markedbills` item with its value as `worth`, for QBCore / Qbox laundering
- **Per-bank cash and cooldown:** set `cash` and `cooldown` on a bank. Fleeca trolleys now hold $30,000–50,000
- **Trolleys spawned by the server** when OneSync is on (`TOB.TrolleySpawn`), so they stay when the leader leaves
- **The gate uses GTA's door system** instead of freezing the door every few frames: cheaper and in sync for everyone
- **Banks moved to `config/banks.lua`**, so the main config is short
- **4 more languages:** German (`de`), Swedish (`sv`), Norwegian (`no`) and Dutch (`nl`)

**Fixes**
- Players who join the server during a heist can loot it too (they see the taken trolleys, the deposit boxes and the countdown)
- Nobody sees "Start bank heist" while a bank is being robbed
- A trolley taken by two players at once no longer flags the second one as a cheater
- The gold and diamond trolleys show their own label with ox_target

**Updating from tobs_blaine:** delete the old `tobs_blaine` folder, change `ensure tobs_blaine` to `ensure tobs_bankrobbery` in `server.cfg`, then copy your settings into the new `config/config.lua`, `config/config_server.lua` and `config/banks.lua` (custom banks go there). Trolleys now pay `TOB.TrolleyCash` over `TOB.GrabTime` instead of the old pile settings. The admin command is still `/tobreset`.
