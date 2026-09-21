-- ox_inventory (Qbox, or ESX / QBCore with ox_inventory): add these to ox_inventory/data/items.lua.
-- id_card_f starts a heist. drill opens the deposit boxes (TOB.DrillItem, set it to "" if you don't want an item).
-- Only add secure_card / thermite if you use TOB.GateItem / TOB.VaultItem.

['id_card_f'] = {
    label = 'Malicious Access Card',
    weight = 10,
    stack = true,
    close = true,
    description = 'A cloned access card used to breach bank security systems.',
},

['drill'] = {
    label = 'Drill',
    weight = 3000,
    stack = false,
    close = true,
    description = 'Opens safe deposit boxes.',
},

['secure_card'] = {
    label = 'Secure ID Card',
    weight = 10,
    stack = true,
    close = true,
    description = 'A bank employee ID card.',
},

['thermite'] = {
    label = 'Thermite',
    weight = 500,
    stack = true,
    close = true,
    description = 'Burns through a vault door.',
},
