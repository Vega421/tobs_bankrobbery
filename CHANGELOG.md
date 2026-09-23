# Changelog

All notable changes to tobs_bankrobbery. Each version is also a [GitHub release](https://github.com/Vega421/tobs_bankrobbery/releases) with a ready-to-use zip.

Full documentation: https://vega421.github.io/scripts/tobs-bankrobbery/

## 1.0.0 · 2026-09-23

**The first release of tobs_bankrobbery as its own script.** It grew out of tobs_blaine (and the 2.x
versions that merged the framework copies), and it's been rewritten enough that the version numbers
start again at 1.0.0: the server runs the whole heist, the framework code is the shared
[tobs_bridge](https://github.com/Vega421/tobs_bridge), and vRP is gone.

Servers on 2.0.0 can update by replacing the folder (the settings are the same); the number going
down is deliberate. vRP servers should stay on 2.0.0.

**Frameworks**
- **vRP support is removed.** The resource is now Qbox, QBCore and ESX only. vRP servers should stay on 2.0.0
- The framework bridge is now the shared [tobs_bridge](https://github.com/Vega421/tobs_bridge): the same `Bridge` code as the other tobs_ scripts, with the database queries and ox_lib helpers included. Settings are unchanged (`TOB.Framework`, `TOB.PoliceJob`, `TOB.PoliceOnDuty`); `TOB.PoliceGroup` and `install/vrp.lua` are gone

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

**Updating from 2.0.0:** replace the whole folder, then copy your settings into the new `config/config.lua` (new: `TOB.TrolleyCash`, `TOB.GrabTime`, `TOB.HackMinigame`, `TOB.Prompts`, `TOB.Dispatch`, `TOB.MarkedBills`, `TOB.Tracker`, `TOB.DyePack`, `TOB.TrolleySpawn`) and `config/config_server.lua` (new: `SV.DispatchAlert`). Custom banks go in the new `config/banks.lua`.

**Older history:** the 2.x and tobs_blaine versions are in
[CHANGELOG-tobs_blaine.md](CHANGELOG-tobs_blaine.md).
