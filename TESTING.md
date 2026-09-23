# Testing tobs_bankrobbery in game

A checklist for a test server. **Part 1** is the heist itself and is the same everywhere; **part 2**
is the short list that only that framework can tell you. Tick as you go.

Keep the F8 console and the server console open: the health check, the Discord log and blocked
attempts all print there.

---

## Setup (any framework)

```cfg
ensure tobs_bankrobbery
ensure tobs_minigames        # optional, but test with it: Paleto uses its laptop and drill

add_ace group.admin command.tobreset allow
add_ace group.admin command.tobpause allow
add_ace group.admin command.tobtest  allow
add_ace group.admin command.tobcheck allow
```

Add the items from `install/` for your inventory: **`id_card_f`** (starts a heist) and **`drill`**
(deposit boxes). `secure_card` and `thermite` only if you set `TOB.GateItem` / `TOB.VaultItem`.

- [ ] The console prints the health check a few seconds after the resource starts, and it lists
      nothing missing. Otherwise fix what it names and restart.
- [ ] `/tobcheck` in game prints the same, including which inventory was detected.
- [ ] No red errors from tobs_bankrobbery in either console.

**Test mode:** run `/tobtest` first. Your heists then skip the police, crew and cooldown rules, set
no cooldown and pay nothing, so you can repeat them. Turn it off (`/tobtest` again) before the
payout tests further down.

---

## 1. The heist

### Paleto (`B1`)

- [ ] The card prompt shows at the panel; using `id_card_f` starts the heist
- [ ] The laptop animation lines up with the panel (no floating laptop, no clipping)
- [ ] The minigame opens. With tobs_minigames: GTA's hacking laptop. Without it: the ox_lib skill check
- [ ] Failing it, or letting `TOB.CardTime` (150 s) run out, ends the heist with a message
- [ ] **The alarm plays** (`PALETO_BAY_SCORE_ALARM`) and police get the alert and the blip
- [ ] The vault opens by itself when the hack time ends (the server does this, not you)
- [ ] The three trolleys are there, and a second player also sees them
- [ ] Grabbing pays over time, and the loot counter matches what you were paid
- [ ] `TOB.StopGrabKey` stops a grab early, and you keep what you had earned
- [ ] The vault closes after `TOB.timer`, then the trolleys disappear
- [ ] `/tobreset B1` ends a stuck heist

### Fleeca (`F1`-`F6`)

- [ ] The heist starts the same way, with a **silent** alarm (police get the alert, no siren)
- [ ] The **inner gate** is hacked from the second panel and actually opens
- [ ] The vault door turns the right way (check the Great Ocean Highway one, `F6`, especially)
- [ ] Per-bank `cash` from `config/banks.lua` is what a trolley pays

### Deposit boxes

- [ ] With the vault open, a box prompts to drill and needs the `drill` item
- [ ] The drill prop is in the hand and the drilling sound plays
- [ ] With tobs_minigames: GTA's drill screen, which can't finish faster than `TOB.DrillTime`
- [ ] Another player standing nearby **hears the drill and the vault door** (`SV.BankSoundRange`)
- [ ] A box pays once and can't be drilled again

### Rules, crew and police

- [ ] With fewer police online than `TOB.mincops`, the heist is refused **and says why**
- [ ] The cooldown refusal says how long is left; the global cooldown says so too
- [ ] `TOB.OneAtATime`: a second bank is refused while one is running
- [ ] `/tobpause testing` refuses new heists with that reason; running heists go on; `/tobpause off` allows them again
- [ ] The leader walking more than 30 m away ends the heist
- [ ] **The leader disconnecting** hands over to the nearest crew member, who sees the trolleys
- [ ] A player who **joins while a heist is running** sees the open vault, the trolleys and the doors
- [ ] With `TOB.Tracker.enabled = true` and `chance = 100`: police see the robber's blip move, and the robber is warned
- [ ] With `TOB.DyePack` on: the red smoke bursts when the grab ends

### Integrations

- [ ] Police get the dispatch alert (ps-dispatch if installed, otherwise the built-in alert)
- [ ] ox_lib prompts show as text UI; with ox_lib stopped, the 3D text shows instead
- [ ] ox_target zones work on the panel, the trolleys and the boxes
- [ ] The Discord webhook posts start, end and `[TEST]` heists (`SV.Webhook`)

---

## 2. Per framework

### Qbox

- [ ] `/tobcheck` says **ox_inventory**
- [ ] The card and drill items are taken and checked correctly
- [ ] Cash lands in `cash`; with `TOB.black = true` the dirty money **item** is paid
- [ ] **Marked bills** (`TOB.MarkedBills = true`): `markedbills` arrives with the right `worth` metadata, and can be laundered
- [ ] Police only count **on duty** (`TOB.PoliceOnDuty = true`): go off duty and the heist is refused
- [ ] Full pockets: fill your inventory, then grab — you're told, and nothing is lost

### QBCore

Test the inventories separately, since the bridge picks between three:

- [ ] **With ox_inventory**: `/tobcheck` says ox_inventory; items and marked bills work
- [ ] **With qb-inventory** (stop ox_inventory): `/tobcheck` says qb-inventory; items work, and
      marked bills (`TOB.MarkedBills = true`) arrive with `worth` in the info
- [ ] **With neither** (older qb-core): `/tobcheck` says the core is used; items still work and
      there's no carry check
- [ ] Cash lands in `cash`, `TOB.black = true` pays the dirty money item
- [ ] On-duty police only, same as Qbox
- [ ] The job updates without a relog when an admin changes it (the client caches it and re-reads every 10 s)

### ESX

- [ ] `/tobcheck` finds the items. If it says "couldn't check", the item list hadn't loaded yet — restart and look again
- [ ] Items come from `install/esx.sql` (or ox_inventory if you run it)
- [ ] **`TOB.black = true` pays the `black_money` account**, not an item — check the account, not the inventory
- [ ] Police count **as soon as they have the job** (ESX has no duty), so `TOB.PoliceOnDuty` changes nothing
- [ ] **No item metadata**: with `TOB.MarkedBills = true` the player gets cash instead (the config says so). Use `TOB.RewardItem` or cash on ESX
- [ ] `canCarryItem` refuses a payout when the pockets are full, and the player is told

---

## Payouts (with `/tobtest` off)

- [ ] A full trolley pays the bank's `cash` (or `TOB.TrolleyCash`), and half a grab pays about half
- [ ] The cooldown is set after the heist and survives a **resource restart** (it's saved in KVP)
- [ ] A test heist (`/tobtest`) pays nothing and sets no cooldown, and is marked `[TEST]` in Discord

## Cheating (should all be refused and logged)

With a second account or a test script, try:

- [ ] Asking for loot from far away, or at another bank
- [ ] Opening the vault or the gate without being police or the heist owner
- [ ] Sending `drillDone` before `TOB.DrillTime` has passed
- [ ] Grabbing the same trolley twice

Each should be blocked and show up in the server console (and in Discord when `SV.LogAntiCheat` is on).

---

## When you're done

Note the framework, the inventory, the game build and anything that looked or felt wrong (timings,
animations, texts). Then update the "tested in game" notes in `CLAUDE.md` and release.
