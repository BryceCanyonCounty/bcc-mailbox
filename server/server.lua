local VORPcore = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()

-- Defensive defaults if shared config not yet loaded
if type(Config) ~= 'table' then Config = {} end
Config.MailboxItem = Config.MailboxItem or 'letter'
Config.SendMessageFee = Config.SendMessageFee or 2
Config.devMode = Config.devMode or false
local MailboxAPI = MailboxAPI or exports['bcc-mailbox']:getMailboxAPI()

do
    local seed = os.time()
    if type(GetGameTimer) == 'function' then
        seed = seed + GetGameTimer()
    end
    math.randomseed(seed)
end

local function generatePostalCode()
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local function randomLetter()
        local idx = math.random(1, #letters)
        return letters:sub(idx, idx)
    end
    local function randomDigit()
        return tostring(math.random(0, 9))
    end
    return randomLetter() .. randomLetter() .. randomDigit() .. randomDigit() .. randomDigit()
end

local function generateUniquePostalCode()
    while true do
        local candidate = generatePostalCode()
        local exists = MySQL.scalar.await('SELECT 1 FROM bcc_mailboxes WHERE postal_code = ? LIMIT 1', { candidate })
        if not exists then
            return candidate
        end
    end
end

local function normalizePostalCode(code)
    if not code then return nil end
    code = tostring(code):gsub('%s+', '')
    if code == '' then return nil end
    return string.upper(code)
end

-- tiny helper to find an online player's source by char_identifier
local function findPlayerByCharIdentifier(charidentifier)
    for _, src in ipairs(GetPlayers()) do
        local User = VORPcore.getUser(src)
        if User then
            local Character = User.getUsedCharacter
            if Character and Character.charIdentifier == charidentifier then
                return src
            end
        end
    end
    return nil
end

local function fetchAndSendContacts(src, ownerMailboxId)
    if not ownerMailboxId then return end

    local contactRows = MySQL.query.await([[
        SELECT
            c.id,
            c.contact_alias,
            m.mailbox_id,
            m.postal_code,
            m.first_name,
            m.last_name
        FROM bcc_mailbox_contacts c
        INNER JOIN bcc_mailboxes m ON c.contact_mailbox_id = m.mailbox_id
        WHERE c.owner_mailbox_id = ?
        ORDER BY COALESCE(c.contact_alias, m.first_name, '')
    ]], { ownerMailboxId }) or {}

    for _, contact in ipairs(contactRows) do
        local fullName = string.format('%s %s', contact.first_name or '', contact.last_name or ''):gsub('^%s*(.-)%s*$',
            '%1')
        contact.displayName = contact.contact_alias or (#fullName > 0 and fullName or contact.postal_code)
    end

    TriggerClientEvent('bcc-mailbox:setRecipients', src, contactRows)
    return contactRows
end

function devPrint(msg)
    if Config.devMode then
        print(msg)
    end
end

function handleMailboxItemUse(src, itemName)
    local User = VORPcore.getUser(src)

    if User then
        local Character = User.getUsedCharacter
        if Character then
            local charidentifier = Character.charIdentifier
            local firstName = Character.firstname
            local lastName = Character.lastname

            MySQL.query('SELECT mailbox_id, postal_code FROM bcc_mailboxes WHERE char_identifier = ?', { charidentifier },
                function(result)
                    if result and #result > 0 then
                        local mailboxId = result[1].mailbox_id
                        local postalCode = result[1].postal_code
                        TriggerClientEvent("bcc-mailbox:mailboxStatus", src, true, mailboxId,
                            firstName .. " " .. lastName, postalCode)
                    else
                        TriggerClientEvent("bcc-mailbox:mailboxStatus", src, false, nil, firstName .. " " .. lastName,
                            nil)
                    end
                end)
        else
            devPrint("Error: Character data not found for user: " .. src)
        end
    else
        devPrint("Error: User not found for source: " .. src)
    end
    exports.vorp_inventory:closeInventory(src)
end

exports.vorp_inventory:registerUsableItem(Config.MailboxItem, function(data)
    local src = data.source
    exports.vorp_inventory:closeInventory(src)
    handleMailboxItemUse(data.source, Config.MailboxItem)
end, GetCurrentResourceName())

function updateMailboxInfo(src)
    local User = VORPcore.getUser(src)
    if User then
        local Character = User.getUsedCharacter
        if Character then
            local charidentifier = Character.charIdentifier
            local firstName = Character.firstname
            local lastName = Character.lastname

            MySQL.update('UPDATE bcc_mailboxes SET first_name = ?, last_name = ? WHERE char_identifier = ?',
                { firstName, lastName, charidentifier }, function(affectedRows)
                    if affectedRows and affectedRows > 0 then
                        devPrint(_U('UpdateMailboxInfo') .. charidentifier)
                        local mailbox = MailboxAPI:GetMailboxByCharIdentifier(charidentifier)
                        if mailbox then
                            TriggerClientEvent('bcc-mailbox:updateMailboxId', src, mailbox.mailbox_id,
                                mailbox.postal_code)
                        end
                    else
                        devPrint(_U('UpdateMailboxFailed') .. charidentifier)
                    end
                end)
        else
            devPrint("Error: Character data not found for user: " .. src)
        end
    else
        devPrint("Error: User not found for source: " .. src)
    end
end

-- ======================
-- SEND MAIL (fixed + logs + optional push)
-- ======================
RegisterNetEvent("bcc-mailbox:sendMail")
AddEventHandler("bcc-mailbox:sendMail", function(recipientPostalCode, subject, message)
    local _source = source
    local User = VORPcore.getUser(_source)
    if not User then
        devPrint("sendMail: user not found for source " .. tostring(_source))
        return
    end

    local Character = User.getUsedCharacter
    if not Character then
        devPrint("sendMail: character not found for user " .. tostring(_source))
        return
    end

    devPrint("sendMail event triggered")
    devPrint("Recipient Postal Code: '" .. tostring(recipientPostalCode) .. "'")
    devPrint("Subject: " .. tostring(subject))
    devPrint("Message: " .. tostring(message))

    local availableMoney = tonumber(Character.money) or 0
    if availableMoney < Config.SendMessageFee then
        VORPcore.NotifyObjective(_source, _U('NotEnoughMoney'), 5000)
        return
    end

    local normalizedCode = normalizePostalCode(recipientPostalCode)
    if not normalizedCode then
        VORPcore.NotifyObjective(_source, _U('InvalidRecipient'), 5000)
        return
    end

    local targetMailbox = MailboxAPI:GetMailboxByPostalCode(normalizedCode)
    if not targetMailbox then
        VORPcore.NotifyObjective(_source, _U('InvalidRecipient'), 5000)
        return
    end

    local senderMailbox = MailboxAPI:GetMailboxByCharIdentifier(Character.charIdentifier)
    if not senderMailbox then
        VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
        return
    end

    local senderName = (Character.firstname or '') .. " " .. (Character.lastname or '')
    local options = {
        fromChar = senderMailbox.postal_code, -- keep using postal as in your client
        fromName = senderName
    }

    local ok, result = MailboxAPI:SendMailToMailbox(targetMailbox.mailbox_id, subject, message, options)
    print(("[bcc-mailbox] SendMailToMailbox -> ok=%s result=%s to_mailbox=%s subject=%s")
        :format(tostring(ok), tostring(result), tostring(targetMailbox.mailbox_id), tostring(subject)))

    if ok then
        Character.removeCurrency(0, Config.SendMessageFee)
        VORPcore.NotifyObjective(_source, _U('MessageSent'), 5000)

        -- OPTIONAL: notify recipient if online
        local recChar = MySQL.single.await('SELECT char_identifier FROM bcc_mailboxes WHERE mailbox_id = ? LIMIT 1',
            { targetMailbox.mailbox_id })
        if recChar and recChar.char_identifier then
            local tSrc = findPlayerByCharIdentifier(recChar.char_identifier)
            if tSrc then
                TriggerClientEvent("bcc-mailbox:checkMailNotification", tSrc)
            end
        end
    else
        devPrint("sendMail failed: " .. tostring(result))
        if result == 'invalid_content' then
            VORPcore.NotifyObjective(_source, _U('InvalidRecipient'), 5000)
        elseif result == 'invalid_mailbox' or result == 'mailbox_not_found' then
            VORPcore.NotifyObjective(_source, _U('InvalidRecipient'), 5000)
        else
            VORPcore.NotifyObjective(_source, _U('MessageFailed'), 5000)
        end
    end
end)

RegisterNetEvent("bcc-mailbox:updateMailboxInfo")
AddEventHandler("bcc-mailbox:updateMailboxInfo", function()
    local _source = source
    updateMailboxInfo(_source)
end)

RegisterNetEvent("bcc-mailbox:checkMailbox")
AddEventHandler("bcc-mailbox:checkMailbox", function()
    local _source = source
    local User = VORPcore.getUser(_source)
    if not User then return end
    local Character = User.getUsedCharacter
    if not Character then return end
    local charidentifier = Character.charIdentifier
    local firstName = Character.firstname
    local lastName = Character.lastname

    MySQL.query('SELECT mailbox_id, postal_code FROM bcc_mailboxes WHERE char_identifier = ?', { charidentifier },
        function(result)
            if result and #result > 0 then
                TriggerClientEvent("bcc-mailbox:mailboxStatus", _source, true, result[1].mailbox_id,
                    firstName .. " " .. lastName, result[1].postal_code)
            else
                TriggerClientEvent("bcc-mailbox:mailboxStatus", _source, false, nil, firstName .. " " .. lastName, nil)
            end
        end)
end)

-- ======================
-- CHECK MAIL (fixed to match id OR postal, safe timestamps)
-- ======================
RegisterNetEvent("bcc-mailbox:checkMail")
AddEventHandler("bcc-mailbox:checkMail", function()
    local _source = source
    local User = VORPcore.getUser(_source)
    if not User then return end
    local Character = User.getUsedCharacter
    if not Character then return end

    MySQL.query('SELECT mailbox_id, postal_code FROM bcc_mailboxes WHERE char_identifier = ? LIMIT 1',
        { Character.charIdentifier }, function(result)
            if result and #result > 0 then
                local recipientMailboxId = result[1].mailbox_id
                local recipientPostal    = result[1].postal_code

                -- Match both representations (string compare): mailbox_id OR postal_code
                MySQL.query([[
                SELECT *
                FROM bcc_mailbox_messages
                WHERE to_char = ? OR to_char = ?
                ORDER BY id DESC
            ]], { tostring(recipientMailboxId), recipientPostal }, function(mails)
                    if mails and #mails > 0 then
                        for _, mail in ipairs(mails) do
                            -- keep DATETIME strings; only format if it's a numeric epoch
                            if type(mail.timestamp) == "number" then
                                mail.timestamp = os.date('%Y-%m-%d %H:%M:%S', mail.timestamp)
                            end
                        end
                        TriggerClientEvent("bcc-mailbox:receiveMails", _source, mails)
                    else
                        VORPcore.NotifyObjective(_source, _U('NoMailsFound'), 5000)
                    end
                end)
            else
                VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
            end
        end)
end)

RegisterNetEvent("bcc-mailbox:registerMailbox")
AddEventHandler("bcc-mailbox:registerMailbox", function()
    local _source = source
    local User = VORPcore.getUser(_source)
    if not User then return end
    local Character = User.getUsedCharacter
    if not Character then return end
    local charidentifier = Character.charIdentifier
    local first_name = Character.firstname
    local last_name = Character.lastname

    if Character.money >= Config.RegistrationFee then
        Character.removeCurrency(0, Config.RegistrationFee)

        local postalCode = generateUniquePostalCode()

        MySQL.insert(
            'INSERT INTO bcc_mailboxes (char_identifier, first_name, last_name, postal_code) VALUES (?, ?, ?, ?)',
            { charidentifier, first_name, last_name, postalCode }, function(insertId)
                if insertId then
                    MySQL.query('SELECT mailbox_id FROM bcc_mailboxes WHERE mailbox_id = ?', { insertId },
                        function(result)
                            if result and #result > 0 then
                                local newMailboxId = result[1].mailbox_id
                                TriggerClientEvent("bcc-mailbox:updateMailboxId", _source, newMailboxId, postalCode)
                                TriggerClientEvent("bcc-mailbox:registerResult", _source, true, _U('MailboxRegistered'))
                            else
                                TriggerClientEvent("bcc-mailbox:registerResult", _source, false, _U('RegistrationError'))
                            end
                        end)
                else
                    TriggerClientEvent("bcc-mailbox:registerResult", _source, false, _U('MailboxRegistrationFailed'))
                end
            end)
    else
        VORPcore.NotifyObjective(_source, _U('MailboxRegistrationFee'), 5000)
    end
end)

RegisterNetEvent("bcc-mailbox:deleteMail")
AddEventHandler("bcc-mailbox:deleteMail", function(mailId)
    local _source = source
    local affected = MySQL.update.await('DELETE FROM bcc_mailbox_messages WHERE id = ?', { mailId })
    if affected and affected > 0 then
        VORPcore.NotifyObjective(_source, _U('MailDeleted'), 5000)
    else
        VORPcore.NotifyObjective(_source, _U('MailDeletionFailed'), 5000)
    end
end)

RegisterNetEvent("bcc-mailbox:getRecipients")
AddEventHandler("bcc-mailbox:getRecipients", function()
    local _source = source
    local User = VORPcore.getUser(_source); if not User then return end
    local Character = User.getUsedCharacter; if not Character then return end

    local mailbox = MailboxAPI:GetMailboxByCharIdentifier(Character.charIdentifier)
    if not mailbox then
        VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
        return
    end

    fetchAndSendContacts(_source, mailbox.mailbox_id)
end)

RegisterNetEvent("bcc-mailbox:getContacts")
AddEventHandler("bcc-mailbox:getContacts", function()
    local _source = source
    local User = VORPcore.getUser(_source); if not User then return end
    local Character = User.getUsedCharacter; if not Character then return end

    local mailbox = MailboxAPI:GetMailboxByCharIdentifier(Character.charIdentifier)
    if not mailbox then
        VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
        return
    end

    fetchAndSendContacts(_source, mailbox.mailbox_id)
end)

RegisterNetEvent("bcc-mailbox:addContact")
AddEventHandler("bcc-mailbox:addContact", function(contactCode, contactAlias)
    local _source = source
    local User = VORPcore.getUser(_source); if not User then return end
    local Character = User.getUsedCharacter; if not Character then return end

    local ownerMailbox = MailboxAPI:GetMailboxByCharIdentifier(Character.charIdentifier)
    if not ownerMailbox then
        VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
        return
    end

    local normalizedCode = normalizePostalCode(contactCode)
    if not normalizedCode then
        VORPcore.NotifyObjective(_source, _U('InvalidContactCode'), 5000)
        return
    end

    local targetMailbox = MailboxAPI:GetMailboxByPostalCode(normalizedCode)
    if not targetMailbox then
        VORPcore.NotifyObjective(_source, _U('InvalidContactCode'), 5000)
        return
    end

    if targetMailbox.mailbox_id == ownerMailbox.mailbox_id then
        VORPcore.NotifyObjective(_source, _U('CannotAddSelf'), 5000)
        return
    end

    local existing = MySQL.query.await(
        'SELECT id FROM bcc_mailbox_contacts WHERE owner_mailbox_id = ? AND contact_mailbox_id = ? LIMIT 1',
        { ownerMailbox.mailbox_id, targetMailbox.mailbox_id })

    if existing and #existing > 0 then
        VORPcore.NotifyObjective(_source, _U('ContactAlreadyExists'), 5000)
        return
    end

    MySQL.insert.await(
        'INSERT INTO bcc_mailbox_contacts (owner_mailbox_id, contact_mailbox_id, contact_alias) VALUES (?, ?, ?)',
        { ownerMailbox.mailbox_id, targetMailbox.mailbox_id, contactAlias })

    VORPcore.NotifyObjective(_source, _U('ContactAdded'), 5000)
    fetchAndSendContacts(_source, ownerMailbox.mailbox_id)
end)

RegisterNetEvent("bcc-mailbox:removeContact")
AddEventHandler("bcc-mailbox:removeContact", function(contactId)
    local _source = source
    local User = VORPcore.getUser(_source); if not User then return end
    local Character = User.getUsedCharacter; if not Character then return end

    local ownerMailbox = MailboxAPI:GetMailboxByCharIdentifier(Character.charIdentifier)
    if not ownerMailbox then
        VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
        return
    end

    local numericId = tonumber(contactId)
    if not numericId then
        VORPcore.NotifyObjective(_source, _U('InvalidContactRemoval'), 5000)
        return
    end

    local affected = MySQL.update.await('DELETE FROM bcc_mailbox_contacts WHERE id = ? AND owner_mailbox_id = ?',
        { numericId, ownerMailbox.mailbox_id })

    if affected and affected > 0 then
        VORPcore.NotifyObjective(_source, _U('ContactRemoved'), 5000)
        fetchAndSendContacts(_source, ownerMailbox.mailbox_id)
    else
        VORPcore.NotifyObjective(_source, _U('InvalidContactRemoval'), 5000)
    end
end)

function GetPlayers()
    local players = {}
    for i = 0, GetNumPlayerIndices() - 1 do
        local player = tonumber(GetPlayerFromIndex(i))
        if player then
            table.insert(players, player)
        end
    end
    return players
end

BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-mailbox')
