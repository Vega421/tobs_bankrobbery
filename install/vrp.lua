-- vRP: add these to vrp/cfg/items.lua.
-- id_card_f starts a heist. drill opens the deposit boxes (TOB.DrillItem, set it to "" if you don't want an item).
-- Only add secure_card / thermite if you use TOB.GateItem / TOB.VaultItem.

["id_card_f"] = {"Malicious Access Card", "Starts a bank heist.", nil, 0.1},
["drill"] = {"Drill", "Opens safe deposit boxes.", nil, 3.0},
["secure_card"] = {"Secure ID Card", "A bank employee ID card.", nil, 0.1},
["thermite"] = {"Thermite", "Burns through a vault door.", nil, 0.5},
