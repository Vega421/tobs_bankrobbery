# tobs_bridge: the API

Every function below exists on **all three frameworks** and returns the same shape. `src` is a player
source; `id` is a person id (`citizenid` on Qbox and QBCore, `identifier` on ESX).

---

## Shapes

```lua
person = {
    id = "ABC12345", source = 3,          -- source only when the player is online
    firstname = "John", lastname = "Doe",
    dob = "1990-01-01", phone = "555-0100", gender = "m",
    job = {name = "police", label = "Police", grade = 3, gradeLabel = "Sergeant",
           onduty = true, boss = false},
}

vehicle = {plate = "ABC 123", model = "sultan", owner = "ABC12345",
           garage = "pillbox", stored = true, fakeplate = nil,
           person = person}     -- only from GetVehicleByPlate
```

---

## Server: players

| Function | Returns |
| -------- | ------- |
| `Bridge.GetPlayer(src)` | `person`, or `nil` when the player isn't loaded |
| `Bridge.GetIdentifier(src)` | the person id, or `nil` |
| `Bridge.GetJob(src)` | the `job` table, or `nil` |
| `Bridge.IsPolice(src)` | `true` / `false` (uses `BridgeConfig.PoliceJobs` + `PoliceOnDuty`) |
| `Bridge.CountPolice()` | number of police online |
| `Bridge.GetPlayersByJob(job)` | a list of sources; `nil` for the job gives every loaded player |

## Server: items

| Function | Returns |
| -------- | ------- |
| `Bridge.GetItemCount(src, item)` | number |
| `Bridge.HasItem(src, item, count)` | `true` / `false` |
| `Bridge.AddItem(src, item, count, metadata)` | `true` / `false` — `false` means the pockets are full |
| `Bridge.RemoveItem(src, item, count)` | `true` / `false` — `false` means they didn't have it |
| `Bridge.CanCarry(src, item, count)` | `true` / `false` |

`metadata` (for example `{worth = 5000}` on marked bills) only works where `Bridge.Metadata == true`:
Qbox and QBCore. It's ignored on ESX.

`Bridge.Inventory` says what's being used: `"ox"`, `"qb"`, `"esx"` or `"core"`.

## Server: money

| Function | Returns |
| -------- | ------- |
| `Bridge.AddMoney(src, amount, account, reason)` | `true` / `false` |
| `Bridge.RemoveMoney(src, amount, account, reason)` | `true` / `false` — `false` when they can't pay |
| `Bridge.GetMoney(src, account)` | number |

`account` is `"cash"` (the default), `"bank"` or `"black"`. Dirty money is ESX's `black_money`
account, and an item everywhere else (`BridgeConfig.BlackMoney`, `"auto"` picks one).

**Always check the return value of a payout**, and use `CanCarry` before paying in items.

## Server: the database

Needs oxmysql. Each one returns `nil` (or an empty list) when the row doesn't exist, or when
oxmysql isn't running.

| Function | Returns |
| -------- | ------- |
| `Bridge.GetPerson(id)` | `person` (without `source`) |
| `Bridge.SearchPeople(text, limit)` | a list of `person`, matching first name, last name, phone or id. `limit` is 25 by default |
| `Bridge.GetVehicles(id)` | a list of `vehicle` |
| `Bridge.GetVehicleByPlate(plate)` | `vehicle` with `person` filled in |
| `Bridge.GetLicences(id)` | `{driver = true, weapon = false, ...}` |
| `Bridge.SetLicence(id, name, has)` | `true` / `false` |
| `Bridge.GetPhoneNumber(id)` | string or `nil` |

Where the data comes from:

| | Qbox / QBCore | ESX |
| --- | --- | --- |
| People | `players` (`charinfo`, `job` JSON) | `users` |
| Vehicles | `player_vehicles` | `owned_vehicles` |
| Licences | `players.metadata.licences` | `user_licenses` |

## Server: callbacks and notifications

```lua
Bridge.RegisterCallback("myscript:canStart", function(src, cb, bank)
    cb(CanStart(src, bank))
end)

Bridge.Notify(src, "The vault is open", "success")   -- sent to that player
```

## Client

| Function | Returns |
| -------- | ------- |
| `Bridge.Init(cb)` | — waits until the player is loaded, calls `cb()`, then keeps the job up to date |
| `Bridge.GetJob()` | the `job` table, or `nil` before the player is loaded |
| `Bridge.IsPolice()` | `true` / `false` |
| `Bridge.GetIdentifier()` | the person id |
| `Bridge.Notify(msg, kind)` | — ox_lib when it runs, else the framework ([below](#client-ox_lib-optional)). `kind`: `"inform"`, `"success"`, `"error"`, `"warning"` |
| `Bridge.TriggerCallback(name, cb, ...)` | — the other half of `RegisterCallback` |
| `Bridge.FrameworkNotify(msg, kind)` | — the framework's own notification, used when ox_lib isn't running |

The job is **cached from events** and re-read every 10 seconds, never asked for per frame: across
resources the core object is copied on every call.

## Client: ox_lib (optional)

ox_lib is detected at runtime. Every one of these works without it.

| Function | With ox_lib | Without it |
| -------- | ----------- | ---------- |
| `Bridge.Notify(msg, kind)` | `ox_lib:notify` | the framework's notification |
| `Bridge.Progress({label, duration, canCancel, disable, anim, prop})` | `progressBar`, `false` when cancelled | waits the full `duration`, plays `anim` if given, `false` if the player dies |
| `Bridge.TextUI(text)` / `Bridge.HideTextUI()` | `showTextUI` / `hideTextUI` | GTA's help text |
| `Bridge.Input(heading, rows)` | `inputDialog` | `nil` |
| `Bridge.Alert(opts)` | `alertDialog` | `nil` |

`Bridge.Progress` always takes the whole `duration`, with or without ox_lib, so a server-side time
check never disagrees with what the player saw. `Bridge.Input` and `Bridge.Alert` return `nil`
without ox_lib on purpose: offer them as an extra, don't build a flow that needs them.

`BridgeConfig.Notify` overrides the detection: `"auto"` (the default), `"oxlib"` or `"framework"`.

## Shared helpers

| Function | Returns |
| -------- | ------- |
| `Framework` | `"qbox"`, `"qb"`, `"esx"` or `nil` |
| `IsPoliceJobName(name)` | `true` / `false` |
| `IsPoliceJobData(job)` | `true` / `false`, checking duty when `BridgeConfig.PoliceOnDuty` is on |
| `BlackMoneyItem()` | the dirty money item for this framework |
| `Bridge.Has["ox_lib"]` | `true` / `false` — is that resource running (checked once, then remembered) |

## Adding a framework

1. Add it to `FRAMEWORKS` in `bridge/framework.lua`, before anything it `provide`s.
2. Write `bridge/<name>/core.lua`, `data.lua` and `client.lua`, each starting with
   `if Framework ~= "<name>" then return end`. The client file provides `Bridge.FrameworkNotify`;
   `bridge/shared/ui.lua` wraps it.
3. Add the files to your `fxmanifest.lua`.
4. Add the framework to `tests/bridge_test.lua`: it checks the whole API and the shapes, so it names
   whatever you forgot.
