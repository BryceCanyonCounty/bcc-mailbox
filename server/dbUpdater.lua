CreateThread(function()
    -- Create the bcc_mailboxes table if it doesn't exist
    MySQL.query.await([[ 
        CREATE TABLE IF NOT EXISTS `bcc_mailboxes` (
            `char_identifier` VARCHAR(255) DEFAULT NULL,
            `mailbox_id` INT(11) NOT NULL AUTO_INCREMENT,
            `first_name` VARCHAR(255) DEFAULT NULL,
            `last_name` VARCHAR(255) DEFAULT NULL,
            PRIMARY KEY (`mailbox_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
    ]])

    -- Create the bcc_mailbox_messages table if it doesn't exist
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `bcc_mailbox_messages` (
            `from_char` VARCHAR(255) DEFAULT NULL,
            `to_char` VARCHAR(255) DEFAULT NULL,
            `from_name` VARCHAR(255) NOT NULL,
            `message` TEXT DEFAULT NULL,
            `subject` VARCHAR(255) DEFAULT NULL,
            `location` VARCHAR(255) DEFAULT NULL,
            `timestamp` DATETIME DEFAULT CURRENT_TIMESTAMP(),
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `eta_timestamp` BIGINT(20) DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
    ]])

    -- Print a success message to the console
    print("Database tables for \x1b[35m\x1b[1m*bcc-mailbox*\x1b[0m created or updated \x1b[32msuccessfully\x1b[0m.")
end)
