# bridge/

The only code in tobs_bankrobbery that talks to your framework. The rest of the script asks the
bridge ("is this player police?", "give them cash") and works the same on every framework.

**You don't need to change anything in this folder.** All its settings come from
`config/config.lua`.

## Which framework it uses

With `TOB.Framework = "auto"` it picks the first one that runs:

1. **Qbox** (`qbx_core`)
2. **ESX** (`es_extended`)
3. **QBCore** (`qb-core`)

Qbox is checked before QBCore because qbx_core also reports itself as qb-core. To force one, set
`TOB.Framework` to `"qbox"`, `"esx"` or `"qb"`.

## The settings it reads

| In `config/config.lua` | What it does in the bridge |
| ---------------------- | -------------------------- |
| `TOB.Framework` | `"auto"`, `"qbox"`, `"esx"` or `"qb"` |
| `TOB.PoliceJob` | The job that counts as police, or a list: `{"police", "sheriff"}` |
| `TOB.PoliceOnDuty` | Qbox and QBCore: only officers on duty count. ESX has no duty, so everyone with the job counts |
| `TOB.blackmoney` | The dirty money item when `TOB.black = true` (`"auto"` = `black_money`). ESX uses the `black_money` account instead |

## Inventories

- **Qbox:** ox_inventory.
- **QBCore:** ox_inventory if it runs, else qb-inventory, else the old qb-core item functions.
- **ESX:** ox_inventory if it runs, else ESX's own inventory.

Item metadata (the `worth` on marked bills) only exists on Qbox and QBCore.

## Tested

In game on **Qbox**. QBCore and ESX are covered by `tests/bridge_test.lua`, which runs these files
against a fake version of each framework, but haven't been played on a live server yet.
