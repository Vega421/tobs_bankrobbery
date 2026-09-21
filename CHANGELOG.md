# Changelog

All notable changes to tobs_bankrobbery. Each version is also a [GitHub release](https://github.com/Vega421/tobs_bankrobbery/releases) with a ready-to-use zip.

Full documentation: https://vega421.github.io/scripts/tobs-bankrobbery/

## 2.1.0 · 2026-09-21

A security and reliability update: the server now runs the whole heist, and trolleys pay by the time spent grabbing.

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

**Fixes**
- Nobody sees "Start bank heist" while a bank is being robbed
- A trolley taken by two players at once no longer flags the second one as a cheater
- The gold and diamond trolleys show their own label with ox_target

**Updating from 2.0.0:** replace the whole folder, then copy your settings into the new `config/config.lua` (new: `TOB.TrolleyCash`, `TOB.GrabTime`, `TOB.HackMinigame`, `TOB.Prompts`, `TOB.Dispatch`) and `config/config_server.lua` (new: `SV.DispatchAlert`).

## 2.0.0 · 2026-09-21

**tobs_blaine is now tobs_bankrobbery: one resource for every framework.** The ESX, vRP and Qbox versions are merged; the heist is the same as 1.5.0.

- **Qbox, ESX, QBCore and vRP in one download.** The framework is detected automatically (`TOB.Framework = "auto"`)
- **Qbox and QBCore support:** police must be on duty (`TOB.PoliceOnDuty`), items through ox_inventory or qb-inventory, cash through the framework
- `TOB.PoliceJob` can be a list of jobs, for example `{"police", "sheriff"}`
- `/bankcoords` prints your position ready to paste into `TOB.Banks` when adding a bank (`TOB.CoordsCommand`)
- Item files for every inventory in the `install/` folder
- `TOB.blackmoney = "auto"`: `dirty_money` on vRP, `black_money` on QBCore and Qbox (ESX still uses the `black_money` account)
- `TOB.Notify = "framework"` uses ESX, QBCore or Qbox notifications (`"esx"` still works)
- Tests for every framework bridge

**Updating from tobs_blaine:** delete the old `tobs_blaine` folder, change `ensure tobs_blaine` to `ensure tobs_bankrobbery` in `server.cfg`, and copy your settings into the new `config/` files. vRP servers: `TOB.Locale` is now `"en"` by default (set `"da"` for Danish) and `TOB.VaultCloseDelay` is 30. The admin command is still `/tobreset`.

History before 2.0.0 is from tobs_blaine (the ESX and vRP versions shared the same code and version numbers from 1.3.0).

## 1.5.0 · 2026-09-21

- **Deposit boxes:** drill the safe deposit boxes in every vault (8 per bank) with the heist drilling animation and an ox_lib skill check. Rewards come from `TOB.DrillRewards` (cash, items or nothing). Needs a `drill` item by default. Box positions from qbcore-framework/qb-bankrobbery (GPL-3.0)
- **Laptop hack:** the Pacific Standard laptop hacking animation during the hack (`TOB.LaptopHack`)
- **Thermite:** the vault item now plants a thermal charge with burning sparks everyone nearby can see (`TOB.VaultItemAnim`)
- **Bank alarm:** the real Paleto Bay bank alarm plays during the heist. Fleeca banks use a silent alarm (`TOB.Alarm`)
- **Gold and diamond trolleys:** sometimes one trolley holds gold (2× pay) or diamonds (3× pay) (`TOB.SpecialTrolleys`, `TOB.SpecialTrolleyChance`)
- **Stop grabbing early:** press X to stop and keep what's in the bag (`TOB.StopGrabKey`)
- **Loot counter:** see the cash you're grabbing on screen, and everyone's total when the heist ends (`TOB.LootCounter`)
- Fixed grabbing getting stuck if the trolley was already gone, and a model loading check that didn't wait for all models

## 1.4.1 · 2026-09-21

Security and reliability fixes from a full audit:

- **Security:** heist cash is only paid while the player is at the trolley they're looting
- **Security:** only the real vault open/close can set the vault door angle, so players can't swing the vault open
- Heists that get stuck end automatically after the longest possible heist time
- Fleeca inner gates stay locked outside heists and are relocked afterwards
- Crew members who arrive after the trolleys spawn can loot too
- The hack fails if the robber is killed during it
- Banks with missing settings are skipped with a console warning instead of breaking the script, and `mincash`/`maxcash` in the wrong order are fixed automatically
- Automated tests run on every push, and a release is only published when they pass

## 1.4.0 · 2026-09-21

- **All 6 Fleeca banks** included, with an inner gate the robber hacks to reach the last trolley (positions from utkuali/Fleeca-Bank-Heists). Turn them off with `TOB.FleecaBanks = false`
- `TOB.GateItem`: optional item for the inner gate, such as `secure_card`
- `TOB.MinCrew`: minimum number of robbers at the panel to start
- `TOB.OneAtATime` and `TOB.GlobalCooldown`: stop players chaining banks
- `SV.BlockBeforeRestart`: no new heists shortly before a txAdmin scheduled restart
- Every bank has a `label` (shown in Discord logs) and an `enabled` switch

## 1.3.1 · 2026-09-21

- Files organized into `config/`, `locales/`, `client/` and `server/` folders. `TOB.lua` is now `config/config.lua`. When updating, replace the whole `tobs_blaine` folder and copy your settings into the new config files

## 1.3.0 · 2026-09-21

- Discord logs of heists, payouts, admin resets and blocked cheat attempts
- Admin reset command `/tobreset`
- Update check on server start
- Loot as items with `TOB.RewardItem`
- Optional vault item step with `TOB.VaultItem`
- More banks can be added from the config
- Loot checks for far-away players now stop when the heist ends
- New `config_server.lua` for server-only settings

## 1.2.1 · 2026-09-21

- Vault door: only players near the bank run the door animation. Before, every player on the server ran it, and far-away players could make the vault look wrong for players who arrived later
- Prompt and loot loops only run every frame when a prompt can be on screen
- Removed unused old code
- Police status is checked every 10 seconds instead of every 3, so it sends far less traffic to the server

## 1.2.0 · 2026-09-21

- Hacking minigame with ox_lib's skill check (`TOB.Minigame`). Failing it ends the heist
- ox_target support (`TOB.Target`); press E still works
- Progress bars use ox_lib when it's running (`TOB.Progress`), so `progressBars` is no longer required
- All text moved to `locales.lua`, with Danish and English (`TOB.Locale`)
- Dispatch hook `TOB.DispatchAlert` and `TOB.BuiltInPoliceAlert`
- Default hack time is now 1 minute (was 1 second) so police can respond
- `TOB.VaultCloseDelay` setting; the security timer message now shows the real time
- Performance: the script now does almost nothing when players aren't near the bank
- Fixed a second heist in the same session not being lootable by players who saw the first

## 1.1.0 · 2026-09-21

- Fixed police not getting the robbery alert
- Fixed the police check being sent to the wrong player, which broke door locking for police
- Fixed only the player who started the heist being able to loot. Everyone near the bank can loot now
- Security: server-side anti-cheat checks. Mod menus could previously trigger unlimited cash payouts
- The heist now ends cleanly if the player who started it disconnects
- Removed the missing `lib/Tunnel.lua` and `lib/Proxy.lua` files from `fxmanifest.lua`, which stopped the script loading
- Removed the unused HT-Base dependency
- Added `TOB.PoliceGroup` so the police group can be changed
- Added `TOB.Notify`: ox_lib, mythic_notify or GTA notifications, picked automatically by default
- Moved the map file into `stream/` so FiveM loads it
- Fixed wrong descriptions in `TOB.lua`
- Added GPL-3.0 license and ready-to-use release zips

## 1.0.0 · 2021-07-03

- First release
