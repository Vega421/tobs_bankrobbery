<div align="center">

# tobs_bankrobbery

**Paleto and Fleeca bank heists for FiveM: Qbox, ESX and QBCore in one resource**

[![Release](https://img.shields.io/github/v/release/Vega421/tobs_bankrobbery?style=flat-square&color=ff6b2c&label=release)](https://github.com/Vega421/tobs_bankrobbery/releases/latest)
[![Tests](https://img.shields.io/github/actions/workflow/status/Vega421/tobs_bankrobbery/tests.yml?style=flat-square&label=tests)](https://github.com/Vega421/tobs_bankrobbery/actions/workflows/tests.yml)
[![License](https://img.shields.io/github/license/Vega421/tobs_bankrobbery?style=flat-square)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-read-ff6b2c?style=flat-square)](https://vega421.github.io/scripts/tobs-bankrobbery/)

[**Download**](https://github.com/Vega421/tobs_bankrobbery/releases/latest) · [Documentation](https://vega421.github.io/scripts/tobs-bankrobbery/) · [Changelog](CHANGELOG.md) · [Report a problem](https://github.com/Vega421/tobs_bankrobbery/issues)

</div>

---

Hack the security panel, open the vault and grab the cash from three trolleys before the police arrive. Formerly **tobs_blaine**.

## Features

- Works on **Qbox, ESX and QBCore**: the framework is detected automatically
- Paleto Bay plus all 6 Fleeca banks
- Laptop hack, thermite, bank alarm and drillable deposit boxes
- Cash, gold and diamond trolleys, with a live loot counter
- The server runs the whole heist: anti-cheat, Discord logs, saved cooldowns and an admin reset command
- Uses ox_lib, ox_target, ox_inventory and ps-dispatch (or your dispatch script) when you have them
- Any hacking minigame: ox_lib's, none, or your own; with [tobs_minigames](https://github.com/Vega421/tobs_minigames) each bank can play its own (Paleto: GTA's hacking laptop and drill)
- Admin tools: pause heists (`/tobpause`), test mode without cooldowns or pay (`/tobtest`), a setup check (`/tobcheck`) and refusals that say why a heist can't start
- If the robber disconnects, the nearest crew member takes over
- Events and exports for other resources (`IsHeistActive`, `heistStarted`, ...)
- Rewards as cash, dirty money, items or marked bills; cash and cooldown per bank; optional thermite-style vault step
- Optional GPS tracker and dye pack in the loot
- English, Danish, German, Swedish, Norwegian and Dutch; add your own banks in `config/banks.lua` (`/bankcoords` helps)
- Minimum crew size, one-heist-at-a-time, on-duty police only, and no heists right before a restart
- Almost no performance cost when nobody is near a bank

## Install

1. Download the zip from [Releases](https://github.com/Vega421/tobs_bankrobbery/releases/latest) and unzip it into `resources/`.
2. Add the items for your inventory from the `install/` folder (`esx.sql`, `ox_inventory.lua` or `qb-core.lua`).
3. Set your police job (`TOB.PoliceJob`) in `config/config.lua`.
4. Add `ensure tobs_bankrobbery` to `server.cfg` below your framework (and below tobs_minigames, if you use it).
5. Give admins the commands in `server.cfg`: `add_ace group.admin command.tobreset allow`, and the same for `tobpause`, `tobtest` and `tobcheck`.

See the [installation guide](https://vega421.github.io/scripts/tobs-bankrobbery/installation/) for details.

**Requires:** one of qbx_core, es_extended or qb-core · [ox_lib](https://github.com/overextended/ox_lib) (recommended, included with Qbox) · [ox_target](https://github.com/overextended/ox_target) (optional) · [tobs_minigames](https://github.com/Vega421/tobs_minigames) (optional)

## Development

Framework code lives only in `bridge/<framework>/`; everything else is shared. The server runs the heist (`server/heist.lua`); the client plays the animations and asks the server. Run the tests with Lua 5.4 from the repo root:

```bash
lua5.4 tests/server_test.lua && lua5.4 tests/bridge_test.lua && lua5.4 tests/client_test.lua && lua5.4 tests/minigames_test.lua && lua5.4 tests/tools_test.lua
```

## Credits and license

Made by Vega, based on [utkuali/Fleeca-Bank-Heists](https://github.com/utkuali/Fleeca-Bank-Heists). Deposit box positions from [qbcore-framework/qb-bankrobbery](https://github.com/qbcore-framework/qb-bankrobbery). Licensed under [GPL-3.0](LICENSE): you can use, change and share it, as long as your version stays open source under GPL-3.0 and keeps the credits.
