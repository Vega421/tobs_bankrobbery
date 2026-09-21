-- ESX with the default inventory: run this on your database.
-- id_card_f starts a heist. drill opens the deposit boxes (TOB.DrillItem, set it to "" if you don't want an item).
-- Only add secure_card / thermite if you use TOB.GateItem / TOB.VaultItem.
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('id_card_f', 'Malicious Access Card', 1, 3, 1),
    ('drill', 'Drill', 3, 0, 1);
--  ('secure_card', 'Secure ID Card', 1, 0, 1),
--  ('thermite', 'Thermite', 1, 0, 1);
