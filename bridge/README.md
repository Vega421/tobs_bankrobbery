# The framework bridge

One resource, four frameworks. Every line that knows about Qbox, ESX, QBCore or vRP lives in this
folder; the rest of the script only calls `Bridge.*`.

This file explains how it works, how to add a framework, and how to reuse the folder in a new script.

---

## How it works

### 1. One check at startup

`bridge/framework.lua` runs on the client and the server and sets one global, `Framework`:

```lua
local FRAMEWORKS = {
    {name = "qbox", resource = "qbx_core"},  -- before qb-core: qbx_core also "provides" qb-core
    {name = "esx",  resource = "es_extended"},
    {name = "qb",   resource = "qb-core"},
    {name = "vrp",  resource = "vrp"},
}
```

The first one that's running wins, so nothing has to be configured. `TOB.Framework` in
`config/config.lua` overrides it when a server runs two frameworks at once.

**The order matters:** qbx_core's manifest has `provide 'qb-core'`, so a Qbox server also looks like
a QBCore server. Qbox is checked first.

### 2. One file per framework, only one runs

`fxmanifest.lua` loads all eight bridge files. Each one starts with the same line:

```lua
-- bridge/qbox/server.lua
if Framework ~= "qbox" then return end

Bridge = {RegisterCallback = TOBCallbacks.Register}

function Bridge.IsPolice(src) ... end
function Bridge.AddMoney(src, amount, dirty) ... end
```

So on a Qbox server the ESX, QBCore and vRP files return immediately and cost nothing, and exactly
one `Bridge` table exists afterwards.

The load order in `fxmanifest.lua` is: config → `bridge/framework.lua` → `callbacks.lua` → the four
bridges → the rest of the script.

### 3. The script never names a framework

```lua
-- server/boxes.lua doesn't know which framework is running
if count > 0 and not Bridge.CanCarry(_source, r.name, count) then
    -- pockets full: tell the player, pay nothing
elseif Bridge.AddItem(_source, r.name, count) then
    -- paid
end
```

Adding a framework is one new folder. No file outside `bridge/` changes.

---

## The Bridge API

Every bridge must provide all of these. `tests/bridge_test.lua` fails if one is missing.

### Server

| Function | Returns | Notes |
| -------- | ------- | ----- |
| `Bridge.IsPolice(src)` | `true` / `false` | Uses `IsPoliceJobData` (Qbox, QBCore) or `TOB.PoliceGroup` (vRP) |
| `Bridge.CountPolice()` | number | Loops `GetPlayers()` |
| `Bridge.HasItem(src, item, count)` | `true` / `false` | |
| `Bridge.RemoveItem(src, item, count)` | `true` / `false` | `false` = the player didn't have it |
| `Bridge.AddItem(src, item, count, metadata)` | `true` / `false` | `false` = the inventory is full. `metadata` only where `Bridge.Metadata = true` |
| `Bridge.CanCarry(src, item, count)` | `true` / `false` | Check before a payout, so nothing is lost |
| `Bridge.AddMoney(src, amount, dirty)` | — | `dirty` pays the black money account (ESX) or item |
| `Bridge.RegisterCallback(name, fn)` | — | `fn(src, cb, ...)`; call `cb(result)` |
| `Bridge.Metadata` | `true` / `nil` | `true` on qb and qbox (items can carry `{worth = ...}`) |

### Client

| Function | Returns | Notes |
| -------- | ------- | ----- |
| `Bridge.Init(cb)` | — | Waits until the player is loaded, then calls `cb()`. Keeps the job up to date |
| `Bridge.IsPolice()` | `true` / `false` | Reads the cached job, never the core object per frame |
| `Bridge.TriggerCallback(name, cb, ...)` | — | The other half of `RegisterCallback` |
| `Bridge.Notify(msg)` | — | The framework's own notification |
| `Bridge.NotifyFallback` | `"framework"` / `"native"` | Which notification to use when ox_lib and the rest aren't running (vRP has none, so `"native"`) |

Shared helpers in `bridge/framework.lua`, usable anywhere: `IsPoliceJobName(name)`,
`IsPoliceJobData(job)` (checks duty when `TOB.PoliceOnDuty` is on) and `BlackMoneyItem()`.

### Callbacks

`client/callbacks.lua` and `server/callbacks.lua` are a tiny framework-independent request/answer
helper (`TOBCallbacks`), so the script doesn't need `QBCore.Functions.TriggerCallback`,
`ESX.TriggerServerCallback` and vRP's proxy separately. Each bridge just points at it:

```lua
-- server
Bridge = {RegisterCallback = TOBCallbacks.Register}
Bridge.RegisterCallback("TOB_fh:getBanks", function(source, cb)
    cb(BanksForClient(), DoorStates(), RunningHeists())
end)

-- client
Bridge.TriggerCallback("TOB_fh:getBanks", function(banks, doors, running)
    -- draw the blips and targets
end)
```

---

## Adding a framework

1. Add it to `FRAMEWORKS` in `bridge/framework.lua`, in the right order (a framework that
   `provide`s another must come before it).
2. `mkdir bridge/<name>` and write `client.lua` and `server.lua`, both starting with
   `if Framework ~= "<name>" then return end`, filling in every function in the tables above.
3. Add both files to `fxmanifest.lua`, next to the others.
4. Add the framework to `tests/bridge_test.lua`: it runs each bridge against a fake framework and
   checks the whole API, so it tells you what you missed.
5. Note anything framework-specific in the config (`TOB.PoliceJob` vs `TOB.PoliceGroup`) and add an
   items file in `install/`.

**What usually differs:** on-duty police (Qbox and QBCore have `job.onduty`, ESX and vRP don't),
item metadata (only ox_inventory and qb-inventory), dirty money (ESX has a `black_money` account,
the others use an item) and whether the client can read the job at all (vRP can't: it asks the
server).

---

## Reusing this in another script

Copy these files, keep the names, and the rest of the new script is framework-free from day one:

```
bridge/framework.lua          -- change TOB.* to your own config prefix
bridge/<qbox|esx|qb|vrp>/client.lua, server.lua
client/callbacks.lua, server/callbacks.lua
tests/bridge_test.lua
```

Then trim the API down to what the new script actually needs, and keep the test in step.

**A script that needs the database** (an MDT, a dealership, a market) needs more than exports: the
player tables differ (`players.charinfo` in Qbox and QBCore, `users` in ESX). Put those queries in
the bridge too, returning one shape:

```lua
-- Bridge.GetPerson(citizenid) -> {id, firstname, lastname, dob, phone} or nil
```

Qbox → QBCore is then cheap (nearly the same tables); ESX is the real work.

**Gotchas that cost time here**

- vRP's `lib/utils.lua` is loaded at runtime with `LoadResourceFile` + `load`, not from the
  manifest, so the resource still starts on servers without vRP.
- Across resources the QBCore core object is a copy, so the client caches the job from events
  (`QBCore:Client:OnJobUpdate`, `SetDuty`) and re-reads it every 10 seconds instead of asking per
  frame.
- Server-side `GetPlayerPed` / `GetEntityCoords` need OneSync. Treat a `vector3(0,0,0)` as "can't
  check", not "far away".
