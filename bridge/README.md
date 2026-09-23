# tobs_bridge

> This folder is a copy of [tobs_bridge](https://github.com/Vega421/tobs_bridge), shared with the
> other tobs_ scripts. **Fix things there and copy the folder back**, so every script gets the fix.
> `BridgeConfig` for this script is set at the end of `config/config.lua`.

One `Bridge` for **Qbox, QBCore and ESX**: framework calls, database queries and ox_lib, so a script
is written once and runs on all three.

It isn't a resource. You copy the `bridge/` folder into your script, so your script keeps working
with no extra dependency for the people who install it.

```lua
-- your script never names a framework
local person = Bridge.GetPlayer(src)          -- {id, firstname, lastname, dob, phone, job = {...}}
if Bridge.IsPolice(src) then ... end
Bridge.AddMoney(src, 5000, "bank")
local cars = Bridge.GetVehicles(person.id)    -- the right table and columns per framework
```

## Install

1. Copy `bridge/` into your script.
2. Add the lines from [`example_fxmanifest.lua`](example_fxmanifest.lua) to your `fxmanifest.lua`.
3. Set `BridgeConfig` in your own config, **before** `bridge/framework.lua` loads:

```lua
BridgeConfig = {
    Framework   = "auto",              -- "auto", "qbox", "qb", "esx"
    PoliceJobs  = {"police", "sheriff"},
    PoliceOnDuty = true,               -- Qbox / QBCore: count on-duty police only
    BlackMoney  = "auto",              -- the dirty money item ("auto" = black_money)
    Notify      = "auto",              -- "auto" (ox_lib when it runs), "oxlib" or "framework"
}
```

The queries need **oxmysql**. Without it they return `nil` and say so once in the console, instead
of crashing.

## What it gives you

| | |
| --- | --- |
| **Players** | `GetPlayer`, `GetIdentifier`, `GetJob`, `IsPolice`, `CountPolice`, `GetPlayersByJob` |
| **Items** | `GetItemCount`, `HasItem`, `AddItem`, `RemoveItem`, `CanCarry` |
| **Money** | `AddMoney`, `RemoveMoney`, `GetMoney` — accounts `"cash"`, `"bank"`, `"black"` |
| **Database** | `GetPerson`, `SearchPeople`, `GetVehicles`, `GetVehicleByPlate`, `GetLicences`, `SetLicence`, `GetPhoneNumber` |
| **Client** | `Init`, `GetJob`, `IsPolice`, `GetIdentifier`, `Notify`, `TriggerCallback` |
| **ox_lib** (optional) | `Notify`, `Progress`, `TextUI`, `HideTextUI`, `Input`, `Alert` — each falls back when ox_lib isn't running |

Every function returns **the same shape on all three frameworks**. A person is always:

```lua
{id = "ABC12345", firstname = "John", lastname = "Doe", dob = "1990-01-01",
 phone = "555-0100", gender = "m", job = {name = "police", grade = 3, onduty = true}}
```

Full list with return values and gotchas: **[API.md](API.md)**.

## How it works

`bridge/framework.lua` checks which framework resource is running and sets `Framework`. Every other
file starts with the same guard, so only one framework's code ever runs:

```lua
if Framework ~= "qbox" then return end
```

Each framework has `core.lua` (players, jobs, items, money), `data.lua` (the SQL) and `client.lua`.
Qbox and QBCore share `bridge/qbox/data.lua`, because their tables are the same.

`bridge/shared/ui.lua` is the ox_lib half: `Bridge.Notify`, `Bridge.Progress`, `Bridge.TextUI`,
`Bridge.Input` and `Bridge.Alert`. ox_lib is **never a dependency** — without it, notifications go to
the framework, the progress bar still waits the full time (so your timings don't change), the text UI
becomes GTA's help text, and the dialogs return `nil`.

**Adding a framework** is one folder plus one line in `FRAMEWORKS`, and the tests tell you what's
missing. Nothing outside `bridge/` changes.

## Tests

```bash
lua5.4 tests/bridge_test.lua     # 134 checks
```

They run the real bridge files against a fake framework and a fake database (no game, no server),
and check that every framework provides the whole API and returns the same shapes. When you change
a bridge, add a check.

## What's tested in game

| Framework | Calls | Queries |
| --------- | ----- | ------- |
| Qbox | not yet | not yet |
| QBCore | not yet | not yet |
| ESX | not yet | not yet |

## Notes per framework

- **Qbox before QBCore:** qbx_core's manifest has `provide 'qb-core'`, so a Qbox server also looks
  like a QBCore one. The detection order handles it.
- **QBCore items:** ox_inventory if it runs, else qb-inventory, else the old `Player.Functions.*Item`.
  `Bridge.Inventory` says which one was picked.
- **ESX has no duty**, so police count as soon as they have the job, and items carry no metadata
  (`Bridge.Metadata == false`). Dirty money is the `black_money` account, not an item.
- **ox_lib** is detected at runtime (`Bridge.Has["ox_lib"]`), never required. `BridgeConfig.Notify`
  forces one way or the other when you want to.

MIT licensed — use it in free and paid scripts.
