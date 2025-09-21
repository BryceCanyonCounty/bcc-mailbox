-- migrated from server/services/migration.lua to mirror bcc-shops layout

CreateThread(function()
    local seed = os.time()
    if type(GetGameTimer) == 'function' then
        seed = seed + GetGameTimer()
    end
    math.randomseed(seed)

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `bcc_mailboxes` (
            `char_identifier` VARCHAR(255) DEFAULT NULL,
            `mailbox_id` INT(11) NOT NULL AUTO_INCREMENT,
            `postal_code` VARCHAR(10) DEFAULT NULL,
            `first_name` VARCHAR(255) DEFAULT NULL,
            `last_name` VARCHAR(255) DEFAULT NULL,
            PRIMARY KEY (`mailbox_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await("ALTER TABLE `bcc_mailboxes` ADD COLUMN IF NOT EXISTS `postal_code` VARCHAR(10) DEFAULT NULL")
    MySQL.query.await("ALTER TABLE `bcc_mailboxes` ADD COLUMN IF NOT EXISTS `first_name` VARCHAR(255) DEFAULT NULL")
    MySQL.query.await("ALTER TABLE `bcc_mailboxes` ADD COLUMN IF NOT EXISTS `last_name` VARCHAR(255) DEFAULT NULL")
    MySQL.query.await("ALTER TABLE `bcc_mailboxes` ADD COLUMN IF NOT EXISTS `char_identifier` VARCHAR(255) DEFAULT NULL")

    MySQL.query.await([[ 
        CREATE UNIQUE INDEX IF NOT EXISTS `uniq_postal_code` ON `bcc_mailboxes` (`postal_code`);
    ]])

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `bcc_mailbox_messages` (
            `from_char` VARCHAR(255) DEFAULT NULL,
            `to_char` VARCHAR(255) DEFAULT NULL,
            `from_name` VARCHAR(255) NOT NULL,
            `message` TEXT DEFAULT NULL,
            `subject` VARCHAR(255) DEFAULT NULL,
            `location` VARCHAR(255) DEFAULT NULL,
            `timestamp` DATETIME DEFAULT CURRENT_TIMESTAMP,
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `eta_timestamp` BIGINT(20) DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `bcc_mailbox_contacts` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `owner_mailbox_id` INT(11) NOT NULL,
            `contact_mailbox_id` INT(11) NOT NULL,
            `contact_alias` VARCHAR(255) DEFAULT NULL,
            `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_mailbox_contact` (`owner_mailbox_id`, `contact_mailbox_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local function generatePostalCode()
        local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        local function randomLetter()
            local index = math.random(1, #letters)
            return letters:sub(index, index)
        end
        local function randomDigit()
            return tostring(math.random(0, 9))
        end
        return randomLetter() .. randomLetter() .. randomDigit() .. randomDigit() .. randomDigit()
    end

    local function generateUniquePostalCode()
        while true do
            local candidate = generatePostalCode()
            local exists = MySQL.scalar.await('SELECT 1 FROM `bcc_mailboxes` WHERE `postal_code` = ? LIMIT 1', { candidate })
            if not exists then
                return candidate
            end
        end
    end

    local rows = MySQL.query.await("SELECT `mailbox_id` FROM `bcc_mailboxes` WHERE `postal_code` IS NULL OR `postal_code` = ''")
    if rows and #rows > 0 then
        for _, row in ipairs(rows) do
            local code = generateUniquePostalCode()
            local ok = pcall(function()
                MySQL.update.await('UPDATE `bcc_mailboxes` SET `postal_code` = ? WHERE `mailbox_id` = ?', { code, row.mailbox_id })
            end)
            if not ok then
                local code2 = generateUniquePostalCode()
                MySQL.update.await('UPDATE `bcc_mailboxes` SET `postal_code` = ? WHERE `mailbox_id` = ?', { code2, row.mailbox_id })
            end
        end
    end

    print("Database tables for \x1b[35m\x1b[1m*bcc-mailbox*\x1b[0m created or updated \x1b[32msuccessfully\x1b[0m.")
end)

