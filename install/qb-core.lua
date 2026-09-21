-- QBCore with qb-inventory: add these to qb-core/shared/items.lua, and put an image for each item
-- in your inventory's image folder (for example qb-inventory/html/images/).
-- id_card_f starts a heist. drill opens the deposit boxes (TOB.DrillItem, set it to "" if you don't want an item).
-- Only add secure_card / thermite if you use TOB.GateItem / TOB.VaultItem.
-- Using ox_inventory on QBCore? Use install/ox_inventory.lua instead.

id_card_f   = { name = 'id_card_f', label = 'Malicious Access Card', weight = 10, type = 'item', image = 'id_card_f.png', unique = false, useable = false, shouldClose = true, description = 'A cloned access card used to breach bank security systems.' },
drill       = { name = 'drill', label = 'Drill', weight = 3000, type = 'item', image = 'drill.png', unique = false, useable = false, shouldClose = true, description = 'Opens safe deposit boxes.' },
secure_card = { name = 'secure_card', label = 'Secure ID Card', weight = 10, type = 'item', image = 'secure_card.png', unique = false, useable = false, shouldClose = true, description = 'A bank employee ID card.' },
thermite    = { name = 'thermite', label = 'Thermite', weight = 500, type = 'item', image = 'thermite.png', unique = false, useable = false, shouldClose = true, description = 'Burns through a vault door.' },
