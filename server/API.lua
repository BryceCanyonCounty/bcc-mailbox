MailboxAPI = {}

exports("getMailboxAPI", function()
    return MailboxAPI
end)

local VORPcore = exports.vorp_core:GetCore()
local DEFAULT_SYSTEM_SENDER = "Postmaster"

local function sanitizeString(value)
    if value == nil then return nil end
    value = tostring(value)
    if value:match("%S") then
        return value
    end
    return nil
end

local function findPlayerByCharIdentifier(charIdentifier)
    if not charIdentifier then return nil end
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local user = VORPcore.getUser(src)
        if user then
            local character = user.getUsedCharacter
            if character and tostring(character.charIdentifier) == tostring(charIdentifier) then
                return src
            end
        end
    end
    return nil
end

function MailboxAPI:GetMailboxByCharIdentifier(charIdentifier)
    if not charIdentifier then return nil end
    local rows = MySQL.query.await('SELECT * FROM bcc_mailboxes WHERE char_identifier = ? LIMIT 1', { charIdentifier })
    return rows and rows[1] or nil
end

function MailboxAPI:GetMailboxIdByCharIdentifier(charIdentifier)
    local mailbox = self:GetMailboxByCharIdentifier(charIdentifier)
    return mailbox and mailbox.mailbox_id or nil
end

function MailboxAPI:GetMailboxById(mailboxId)
    if not mailboxId then return nil end
    local rows = MySQL.query.await('SELECT * FROM bcc_mailboxes WHERE mailbox_id = ? LIMIT 1', { mailboxId })
    return rows and rows[1] or nil
end

function MailboxAPI:GetMailboxByPostalCode(postalCode)
    if not postalCode then return nil end
    local normalized = tostring(postalCode):gsub('%s+', '')
    if normalized == '' then return nil end
    normalized = string.upper(normalized)
    local rows = MySQL.query.await('SELECT * FROM bcc_mailboxes WHERE postal_code = ? LIMIT 1', { normalized })
    return rows and rows[1] or nil
end

function MailboxAPI:GetPlayerSourceByMailboxId(mailboxId)
    local mailbox = self:GetMailboxById(mailboxId)
    if not mailbox then return nil end
    return findPlayerByCharIdentifier(mailbox.char_identifier)
end

function MailboxAPI:GetPlayerSourceByCharIdentifier(charIdentifier)
    return findPlayerByCharIdentifier(charIdentifier)
end

local function insertMailRow(fromChar, toMailbox, fromName, subject, message, location, etaTimestamp)
    local timestamp = os.date('%Y-%m-%d %H:%M:%S', os.time())

    local fields = {
        'from_char',
        'to_char',
        'from_name',
        'subject',
        'message',
        'location',
        'timestamp',
        'eta_timestamp',
        'is_read'
    }

    local placeholders = {}
    local params = {}

    local function push(value, allowNull)
        if value == nil and allowNull then
            placeholders[#placeholders + 1] = 'NULL'
        else
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = value
        end
    end

    push(fromChar, true)
    push(toMailbox, false)
    push(fromName, false)
    push(subject, false)
    push(message, false)
    push(location, true)
    push(timestamp, false)
    push(etaTimestamp, true)
    push(0, false)

    local query = ('INSERT INTO bcc_mailbox_messages (%s) VALUES (%s)')
        :format(table.concat(fields, ', '), table.concat(placeholders, ', '))

    return MySQL.insert.await(query, params)
end

function MailboxAPI:SendMailToMailbox(mailboxId, subject, message, options)
    if not mailboxId then
        return false, 'invalid_mailbox'
    end

    local numericMailboxId = tonumber(mailboxId)
    if not numericMailboxId then
        return false, 'invalid_mailbox'
    end

    local mailbox = self:GetMailboxById(numericMailboxId)
    if not mailbox then
        return false, 'mailbox_not_found'
    end

    subject = sanitizeString(subject)
    message = sanitizeString(message)
    if not subject or not message then
        return false, 'invalid_content'
    end

    local fromChar = sanitizeString(options and options.fromChar)
    local fromName = sanitizeString(options and options.fromName) or DEFAULT_SYSTEM_SENDER
    local location = sanitizeString(options and options.location)
    local etaTimestamp = options and tonumber(options.etaTimestamp) or nil

    local insertedId = insertMailRow(fromChar, numericMailboxId, fromName, subject, message, location, etaTimestamp)
    if not insertedId then
        return false, 'insert_failed'
    end

    if not (options and options.skipNotify) then
        local notifTarget = findPlayerByCharIdentifier(mailbox.char_identifier)
        if notifTarget then
            local mailboxIdStr = tostring(mailbox.mailbox_id)
            local postalCodeStr = tostring(mailbox.postal_code or '')
            local unreadCount = MySQL.scalar.await(
                'SELECT COUNT(*) FROM bcc_mailbox_messages WHERE is_read = 0 AND (to_char = ? OR to_char = ?)',
                { mailboxIdStr, postalCodeStr }
            )

            if (unreadCount or 0) > 0 then
                BccUtils.RPC:Notify('bcc-mailbox:checkMailNotification', { unreadCount = unreadCount }, notifTarget)
            end
        end
    end

    return true, insertedId
end

function MailboxAPI:SendMailToCharacter(charIdentifier, subject, message, options)
    if not charIdentifier then
        return false, 'invalid_character'
    end
    local mailbox = self:GetMailboxByCharIdentifier(charIdentifier)
    if not mailbox then
        return false, 'mailbox_not_found'
    end
    return self:SendMailToMailbox(mailbox.mailbox_id, subject, message, options)
end

function MailboxAPI:GetUnreadMessages(mailboxRef, opts)
    if not mailboxRef then return nil end

    local mailbox = nil
    if type(mailboxRef) == 'table' then
        mailbox = mailboxRef
    else
        local numericId = tonumber(mailboxRef)
        if numericId then
            mailbox = self:GetMailboxById(numericId)
        end
        if not mailbox then
            mailbox = self:GetMailboxByPostalCode(mailboxRef)
        end
        if not mailbox then
            mailbox = self:GetMailboxByCharIdentifier(mailboxRef)
        end
    end

    if not mailbox then
        return nil
    end

    local limit = tonumber(opts and opts.limit) or 0
    local query = [[
        SELECT *
        FROM bcc_mailbox_messages
        WHERE is_read = 0 AND (to_char = ? OR to_char = ? OR to_char = ?)
        ORDER BY id DESC
    ]]
    local params = {
        tostring(mailbox.mailbox_id),
        mailbox.postal_code and tostring(mailbox.postal_code) or '',
        mailbox.char_identifier and tostring(mailbox.char_identifier) or ''
    }

    if limit > 0 then
        query = query .. ' LIMIT ' .. tonumber(limit)
    end

    local rows = MySQL.query.await(query, params) or {}
    for _, row in ipairs(rows) do
        if type(row.timestamp) == 'number' then
            row.timestamp = os.date('%Y-%m-%d %H:%M:%S', row.timestamp)
        end
    end

    return rows
end
