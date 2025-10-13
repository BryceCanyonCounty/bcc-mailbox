local VORPcore = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()

local MailboxAPI = MailboxAPI or exports['bcc-mailbox']:getMailboxAPI()

do
    local seed = os.time()
    if type(GetGameTimer) == 'function' then
        seed = seed + GetGameTimer()
    end
    math.randomseed(seed)
end

exports.vorp_inventory:registerUsableItem(Config.MailboxItem, function(data)
    local src = data.source
    DevPrint('MailboxItem used. src=', src)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint("Error: User not found for source: " .. tostring(src))
        exports.vorp_inventory:closeInventory(src)
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint("Error: Character data not found for user: " .. tostring(src))
        exports.vorp_inventory:closeInventory(src)
        return
    end

    local fullName = ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub("^%s*(.-)%s*$", "%1")
    local mailbox = GetMailboxByCharIdentifier(char.charIdentifier)

    if not mailbox then
        NotifyClient(src, _U('RegisterAtMailboxLocation'), 'error', 5000)
        exports.vorp_inventory:closeInventory(src)
        return
    end
    BccUtils.RPC:Notify('bcc-mailbox:mailboxStatus', { hasMailbox = true, mailboxId  = mailbox.mailbox_id, playerName = fullName, postalCode = mailbox.postal_code}, src)

    exports.vorp_inventory:closeInventory(src)

    local durCfg = Config.LetterDurability
    if not durCfg or not durCfg.Enabled then return end

    local itemName = Config.MailboxItem or 'letter'
    local item = exports.vorp_inventory:getItem(src, itemName)
    if not item or not item.id then return end

    local maxValue = tonumber(durCfg.Max or 100) or 100
    local damage = tonumber(durCfg.DamagePerUse or 1) or 1
    local current = (item.metadata and item.metadata.durability) or maxValue
    local newVal = math.max(0, math.floor(current - damage))

    if newVal <= 0 then
        if exports.vorp_inventory.subItemID then
            exports.vorp_inventory:subItemID(src, item.id)
        else
            exports.vorp_inventory:subItem(src, itemName, 1)
        end
        NotifyClient(src, _U('LetterDestroyed'), 'error', 4000)
        return
    end

    local meta = item.metadata or {}
    meta.durability = newVal
    meta.id = item.id
    meta.description = _U('LetterDurabilityDescription', newVal)

    exports.vorp_inventory:setItemMetadata(src, item.id, meta, 1)

    if durCfg.NotifyOnChange then
        NotifyClient(src, _U('LetterDurabilityUpdate', newVal), 'info', 3000)
    end
end, GetCurrentResourceName())

BccUtils.RPC:Register("bcc-mailbox:SendMail", function(params, cb, recSource)
    local _source = recSource
    local recipientPostalCode = params and params.recipientPostalCode
    local subject = params and params.subject
    local message = params and params.message

    local response = { success = false }

    local User = VORPcore.getUser(_source)
    if not User then
        DevPrint("SendMail RPC: user not found for source " .. tostring(_source))
        response.reason = 'user_not_found'
        cb(response)
        return
    end

    local Character = User.getUsedCharacter
    if not Character then
        DevPrint("SendMail RPC: character not found for user " .. tostring(_source))
        response.reason = 'character_not_found'
        cb(response)
        return
    end

    DevPrint("SendMail RPC triggered")
    DevPrint("Recipient Postal Code: '" .. tostring(recipientPostalCode) .. "'")
    DevPrint("Subject: " .. tostring(subject))
    DevPrint("Message: " .. tostring(message))

    local availableMoney = tonumber(Character.money) or 0
    if availableMoney < Config.SendMessageFee then
        NotifyClient(_source, _U('NotEnoughMoney'), "error", 5000)
        response.reason = 'insufficient_funds'
        cb(response)
        return
    end

    local rawCode = recipientPostalCode and tostring(recipientPostalCode) or ''
    local normalizedCode = NormalizePostalCode(recipientPostalCode)
    if not normalizedCode then
        NotifyClient(_source, _U('InvalidRecipient'), "error", 5000)
        response.reason = 'invalid_recipient'
        cb(response)
        return
    end

    local targetMailbox = MailboxAPI:GetMailboxByPostalCode(normalizedCode)
    if not targetMailbox then
        local potentialId = tonumber(normalizedCode)
        if potentialId then
            targetMailbox = MailboxAPI:GetMailboxById(potentialId)
        end
    end
    if not targetMailbox and rawCode ~= '' then
        targetMailbox = MailboxAPI:GetMailboxByCharIdentifier(rawCode)
    end
    if not targetMailbox and normalizedCode ~= rawCode then
        targetMailbox = MailboxAPI:GetMailboxByCharIdentifier(normalizedCode)
    end
    if not targetMailbox then
        NotifyClient(_source, _U('InvalidRecipient'), "error", 5000)
        response.reason = 'invalid_recipient'
        cb(response)
        return
    end

    local senderMailbox = MailboxAPI:GetMailboxByCharIdentifier(Character.charIdentifier)
    if not senderMailbox then
        NotifyClient(_source, _U('MailboxNotFound'), "error", 5000)
        response.reason = 'sender_mailbox_not_found'
        cb(response)
        return
    end

    local senderName = (Character.firstname or '') .. " " .. (Character.lastname or '')
    local options = {
        fromChar = senderMailbox.postal_code,
        fromName = senderName
    }

    local ok, result = MailboxAPI:SendMailToMailbox(targetMailbox.mailbox_id, subject, message, options)
    DevPrint(("[bcc-mailbox] SendMailToMailbox -> ok=%s result=%s to_mailbox=%s subject=%s")
        :format(tostring(ok), tostring(result), tostring(targetMailbox.mailbox_id), tostring(subject)))

    if ok then
        Character.removeCurrency(0, Config.SendMessageFee)
        local recipientLabel = TrimWhitespace((targetMailbox.first_name or '') .. ' ' .. (targetMailbox.last_name or ''))
        if recipientLabel == '' then
            recipientLabel = targetMailbox.postal_code or tostring(targetMailbox.mailbox_id)
        end
        NotifyClient(_source, _U('MessageSent') .. recipientLabel, "success", 5000)
        response.success = true
        response.mailboxId = targetMailbox.mailbox_id
        response.recipientLabel = recipientLabel
    else
        DevPrint("sendMail failed: " .. tostring(result))
        if result == 'invalid_content' then
            NotifyClient(_source, _U('InvalidRecipient'), "error", 5000)
        elseif result == 'invalid_mailbox' or result == 'mailbox_not_found' then
            NotifyClient(_source, _U('InvalidRecipient'), "error", 5000)
        else
            NotifyClient(_source, _U('MessageFailed'), "error", 5000)
        end
        response.reason = result or 'unknown'
    end

    cb(response)
end)

BccUtils.RPC:Register('bcc-mailbox:UpdateMailboxInfo', function(params, cb, src)
    DevPrint('UpdateMailboxInfo RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('UpdateMailboxInfo: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('UpdateMailboxInfo: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local charIdentifier = char.charIdentifier
    local firstName = char.firstname
    local lastName  = char.lastname

    local affectedRows = UpdateMailboxNames(charIdentifier, firstName, lastName)

    if affectedRows > 0 then
        DevPrint('UpdateMailboxInfo: updated char_identifier=', charIdentifier)

        local mailbox = MailboxAPI:GetMailboxByCharIdentifier(charIdentifier)
        if mailbox then
            cb(true, {
                mailboxId  = mailbox.mailbox_id,
                postalCode = mailbox.postal_code
            })
            return
        end

        cb(true)
        return
    end

    DevPrint('UpdateMailboxInfo: update failed for char_identifier=', charIdentifier)
    NotifyClient(src, _U('UpdateMailboxFailed') .. tostring(charIdentifier), 'error', 4000)
    cb(false)
end)

BccUtils.RPC:Register('bcc-mailbox:CheckMailbox', function(params, cb, src)
    DevPrint('CheckMailbox RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('CheckMailbox: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('CheckMailbox: invalid player/char (no char)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local charIdentifier = char.charIdentifier
    local fullName = (char.firstname or '') .. ' ' .. (char.lastname or '')

    local mailboxRow = GetMailboxByCharIdentifier(charIdentifier)

    if mailboxRow then
        DevPrint('CheckMailbox: found mailbox for char_identifier=', charIdentifier, 'mailbox_id=', mailboxRow.mailbox_id)
        cb(true, {
            fullName   = TrimWhitespace(fullName),
            hasMailbox = true,
            mailboxId  = mailboxRow.mailbox_id,
            postalCode = mailboxRow.postal_code,
        })
        return
    end

    DevPrint('CheckMailbox: no mailbox for char_identifier=', charIdentifier)
    cb(true, {
        fullName   = TrimWhitespace(fullName),
        hasMailbox = false,
    })
end)

BccUtils.RPC:Register('bcc-mailbox:FetchMail', function(params, cb, src)
    DevPrint('FetchMail RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('FetchMail: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('FetchMail: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local mailboxRow = GetMailboxByCharIdentifier(char.charIdentifier)
    if not mailboxRow then
        DevPrint('FetchMail: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false)
        return
    end

    local recipientMailboxId = mailboxRow.mailbox_id
    local recipientPostal    = mailboxRow.postal_code
    local charIdentifier     = tostring(char.charIdentifier)

    local mails = GetMailsForRecipient(recipientMailboxId, recipientPostal, charIdentifier)
    DevPrint('FetchMail: fetched ', #mails, ' mails for char_identifier=', charIdentifier)

    if #mails == 0 then
        NotifyClient(src, _U('NoMailsFound'), 'info', 5000)
        cb(true, { mails = {}, count = 0 })
        return
    end

    cb(true, { mails = mails, count = #mails })
end)

BccUtils.RPC:Register('bcc-mailbox:PollUnread', function(params, cb, src)
    DevPrint('PollUnread RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('PollUnread: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('PollUnread: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false)
        return
    end

    local mailbox = GetMailboxByCharIdentifier(char.charIdentifier)
    if not mailbox then
        DevPrint('PollUnread: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false)
        return
    end

    local mailboxIdStr = tostring(mailbox.mailbox_id)
    local postalCodeStr = mailbox.postal_code and tostring(mailbox.postal_code) or ''
    local charIdStr     = tostring(char.charIdentifier)

    local unreadCount = CountUnreadForRecipient(mailboxIdStr, postalCodeStr, charIdStr)
    DevPrint('PollUnread: unread=', unreadCount, ' for char_identifier=', charIdStr)

    cb(true, { unread = unreadCount })
end)

BccUtils.RPC:Register('bcc-mailbox:MarkMailRead', function(params, cb, src)
    DevPrint('MarkMailRead RPC called. src=', src, 'params=', params)

    local numericId = params and tonumber(params.mailId)
    if not numericId then
        DevPrint('MarkMailRead: invalid mailId')
        cb(false, { reason = 'invalid_id' })
        return
    end

    local markRead = (params and params.read)
    if markRead == nil then markRead = true end
    local desiredState = markRead and 1 or 0

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('MarkMailRead: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('MarkMailRead: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local mailbox = GetMailboxByCharIdentifier(char.charIdentifier)
    if not mailbox then
        DevPrint('MarkMailRead: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false, { reason = 'mailbox_not_found' })
        return
    end

    local mail = GetMailById(numericId)
    if not mail then
        DevPrint('MarkMailRead: mail not found. id=', numericId)
        cb(false, { reason = 'mail_not_found' })
        return
    end

    local toChar = mail.to_char and tostring(mail.to_char) or ''
    local authorized = (toChar ~= '') and (
        toChar == tostring(mailbox.mailbox_id)
        or toChar == tostring(mailbox.postal_code)
        or toChar == tostring(mailbox.char_identifier)
    )

    if not authorized then
        DevPrint('MarkMailRead: not authorized. id=', numericId, ' to_char=', toChar)
        cb(false, { reason = 'not_authorized' })
        return
    end

    local currentState = tonumber(mail.is_read or 0) or 0
    if currentState == desiredState then
        DevPrint('MarkMailRead: already set. id=', numericId, ' state=', desiredState)
        cb(true, { alreadySet = true, readState = desiredState })
        return
    end

    local updated = UpdateMailReadState(
        desiredState,
        numericId,
        tostring(mailbox.mailbox_id),
        mailbox.postal_code and tostring(mailbox.postal_code) or '',
        mailbox.char_identifier and tostring(mailbox.char_identifier) or ''
    )

    if updated > 0 then
        DevPrint('MarkMailRead: updated. id=', numericId, ' new_state=', desiredState)
        if Config.CoreHudIntegration and Config.CoreHudIntegration.enabled and char and char.charIdentifier then
            exports['bcc-corehud']:RefreshMailboxCore(char.charIdentifier)
        end
        cb(true, { readState = desiredState })
        return
    end

    DevPrint('MarkMailRead: update failed. id=', numericId)
    cb(false, { reason = 'update_failed' })
end)

BccUtils.RPC:Register('bcc-mailbox:PurchaseLetter', function(params, cb, src)
    DevPrint('PurchaseLetter RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('PurchaseLetter: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('PurchaseLetter: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then
        DevPrint('PurchaseLetter: invalid ped for src=', src)
        cb(false, { reason = 'invalid_ped' })
        return
    end

    local pedCoords = GetEntityCoords(ped)
    local radius = tonumber(Config.LetterPurchaseRadius or 3.0) or 3.0
    local nearMailbox = false

    if Config.MailboxLocations then
        for _, location in pairs(Config.MailboxLocations) do
            local loc = location and location.coords
            if loc then
                local dx = pedCoords.x - loc.x
                local dy = pedCoords.y - loc.y
                local dz = pedCoords.z - loc.z
                local distanceSquared = dx * dx + dy * dy + dz * dz
                if distanceSquared <= (radius * radius) then
                    nearMailbox = true
                    break
                end
            end
        end
    end

    if not nearMailbox then
        DevPrint('PurchaseLetter: player not near mailbox. src=', src)
        NotifyClient(src, _U('LetterPurchaseNotNear'), 'error', 5000)
        cb(false, { reason = 'not_near_mailbox' })
        return
    end

    local cost = tonumber(Config.LetterPurchaseCost or 0) or 0
    local balance = tonumber(char.money or 0) or 0
    if cost > 0 and balance < cost then
        DevPrint('PurchaseLetter: insufficient funds. have=', balance, 'need=', cost)
        NotifyClient(src, _U('LetterPurchaseNoFunds'), 'error', 5000)
        cb(false, { reason = 'insufficient_funds' })
        return
    end

    local itemName = Config.MailboxItem or 'letter'

    exports.vorp_inventory:canCarryItem(src, itemName, 1, function(canCarry)
        if not canCarry then
            DevPrint('PurchaseLetter: cannot carry item. src=', src)
            NotifyClient(src, _U('LetterInventoryFull'), 'error', 5000)
            cb(false, { reason = 'cannot_carry' })
            return
        end

        if cost > 0 then
            char.removeCurrency(0, cost)
        end

        local metadata
        local durCfg = Config.LetterDurability
        if durCfg and durCfg.Enabled then
            local maxValue = tonumber(durCfg.Max or 100) or 100
            metadata = {
                durability = maxValue,
                description = _U('LetterDurabilityDescription', maxValue)
            }
        end

        if metadata then
            exports.vorp_inventory:addItem(src, itemName, 1, metadata)
        else
            exports.vorp_inventory:addItem(src, itemName, 1)
        end

        NotifyClient(src, _U('LetterPurchased'), 'success', 5000)
        cb(true, { success = true })
    end)
end)

BccUtils.RPC:Register('bcc-mailbox:RegisterMailbox', function(params, cb, src)
    DevPrint('RegisterMailbox RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('RegisterMailbox: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('RegisterMailbox: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local fee = tonumber(Config.RegistrationFee) or 0
    local balance = tonumber(char.money or 0) or 0
    if balance < fee then
        DevPrint('RegisterMailbox: insufficient funds. have=', balance, 'need=', fee)
        NotifyClient(src, _U('MailboxRegistrationFee'), 'error', 5000)
        cb(false, { reason = 'insufficient_funds' })
        return
    end

    -- charge fee (cash = currency 0 like your other handlers)
    char.removeCurrency(0, fee)

    local charIdentifier = char.charIdentifier
    local firstName      = char.firstname
    local lastName       = char.lastname
    local postalCode     = GenerateUniquePostalCode()

    local insertId = CreateMailbox(charIdentifier, firstName, lastName, postalCode)
    if not insertId then
        DevPrint('RegisterMailbox: insert failed for char_identifier=', tostring(charIdentifier))
        NotifyClient(src, _U('MailboxRegistrationFailed'), 'error', 5000)
        cb(false, { reason = 'insert_failed' })
        return
    end

    local result = GetMailboxById(insertId)
    if not result then
        DevPrint('RegisterMailbox: verification select failed for mailbox_id=', tostring(insertId))
        NotifyClient(src, _U('RegistrationError'), 'error', 5000)
        cb(false, { reason = 'registration_error' })
        return
    end

    DevPrint('RegisterMailbox: success. mailbox_id=', result.mailbox_id, ' postal=', postalCode)
    NotifyClient(src, _U('MailboxRegistered'), 'success', 5000)
    cb(true, {
        mailboxId  = result.mailbox_id,
        postalCode = postalCode,
    })
end)

BccUtils.RPC:Register('bcc-mailbox:DeleteMail', function(params, cb, src)
    DevPrint('DeleteMail RPC called. src=', src, 'params=', params)

    local mailId = params and tonumber(params.mailId)
    if not mailId then
        DevPrint('DeleteMail: invalid mailId')
        cb(false, { reason = 'invalid_id' })
        return
    end

    -- match the SellGold-style user/char validation
    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('DeleteMail: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end
    local char = user.getUsedCharacter
    if not char then
        DevPrint('DeleteMail: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local affected = DeleteMailById(mailId)
    if affected > 0 then
        DevPrint('DeleteMail: deleted id=', mailId)
        if Config.CoreHudIntegration and Config.CoreHudIntegration.enabled and char and char.charIdentifier then
            exports['bcc-corehud']:RefreshMailboxCore(char.charIdentifier)
        end
        NotifyClient(src, _U('MailDeleted'), 'success', 5000)
        cb(true)
        return
    end

    DevPrint('DeleteMail: delete failed id=', mailId)
    NotifyClient(src, _U('MailDeletionFailed'), 'error', 5000)
    cb(false, { reason = 'delete_failed' })
end)

BccUtils.RPC:Register('bcc-mailbox:GetRecipients', function(params, cb, src)
    DevPrint('GetRecipients RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('GetRecipients: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('GetRecipients: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local mailbox = MailboxAPI:GetMailboxByCharIdentifier(char.charIdentifier)
    if not mailbox then
        DevPrint('GetRecipients: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false, { reason = 'mailbox_not_found' })
        return
    end

    -- 1) fetch raw rows
    local rows = FetchContactsRows(mailbox.mailbox_id) or {}

    -- 2) shape inside RPC
    local contacts = {}
    for _, r in ipairs(rows) do
        local fullName = TrimWhitespace((r.first_name or '') .. ' ' .. (r.last_name or ''))
        local alias    = r.contact_alias and TrimWhitespace(r.contact_alias) or nil
        local display  = (alias and alias ~= '' and alias)
            or (fullName ~= '' and fullName)
            or tostring(r.postal_code)

        contacts[#contacts + 1] = {
            id          = r.id,
            displayName = display,
            mailboxId   = tostring(r.mailbox_id),
            postalCode  = r.postal_code and tostring(r.postal_code) or nil,
            firstName   = r.first_name,
            lastName    = r.last_name,
        }
    end

    DevPrint('GetRecipients: contacts_count=', #contacts, ' mailbox_id=', mailbox.mailbox_id)
    cb(true, { contacts = contacts, count = #contacts })
end)

BccUtils.RPC:Register('bcc-mailbox:GetContacts', function(params, cb, src)
    DevPrint('GetContacts RPC called. src=', src, 'params=', params)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('GetContacts: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end

    local char = user.getUsedCharacter
    if not char then
        DevPrint('GetContacts: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local mailbox = MailboxAPI:GetMailboxByCharIdentifier(char.charIdentifier)
    if not mailbox then
        DevPrint('GetContacts: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false, { reason = 'mailbox_not_found' })
        return
    end

    local rows = FetchContactsRows(mailbox.mailbox_id)

    local contacts = {}
    for _, r in ipairs(rows) do
        local fullName = TrimWhitespace((r.first_name or '') .. ' ' .. (r.last_name or ''))
        local alias    = r.contact_alias and TrimWhitespace(r.contact_alias) or nil
        local display  = (alias and alias ~= '' and alias)
            or (fullName ~= '' and fullName)
            or tostring(r.postal_code)

        contacts[#contacts + 1] = {
            id          = r.id,
            displayName = display,
            mailboxId   = tostring(r.mailbox_id),
            postalCode  = r.postal_code and tostring(r.postal_code) or nil,
            firstName   = r.first_name,
            lastName    = r.last_name,
        }
    end

    DevPrint('GetContacts: fetched ', #contacts, ' contacts for mailbox_id=', mailbox.mailbox_id)
    cb(true, { contacts = contacts, count = #contacts })
end)

BccUtils.RPC:Register('bcc-mailbox:AddContact', function(params, cb, src)
    DevPrint('AddContact RPC called. src=', src, 'params=', params)

    local contactCode  = params and params.contactCode
    local contactAlias = params and params.contactAlias

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('AddContact: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end
    local char = user.getUsedCharacter
    if not char then
        DevPrint('AddContact: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local ownerMailbox = MailboxAPI:GetMailboxByCharIdentifier(char.charIdentifier)
    if not ownerMailbox then
        DevPrint('AddContact: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false, { reason = 'mailbox_not_found' })
        return
    end

    local normalized = NormalizePostalCode(contactCode)
    if not normalized then
        DevPrint('AddContact: invalid contact code')
        NotifyClient(src, _U('InvalidContactCode'), 'error', 5000)
        cb(false, { reason = 'invalid_code' })
        return
    end

    local targetMailbox = MailboxAPI:GetMailboxByPostalCode(normalized)
    if not targetMailbox then
        DevPrint('AddContact: target mailbox not found for code=', tostring(normalized))
        NotifyClient(src, _U('InvalidContactCode'), 'error', 5000)
        cb(false, { reason = 'target_not_found' })
        return
    end

    if targetMailbox.mailbox_id == ownerMailbox.mailbox_id then
        DevPrint('AddContact: cannot add self. mailbox_id=', ownerMailbox.mailbox_id)
        NotifyClient(src, _U('CannotAddSelf'), 'error', 5000)
        cb(false, { reason = 'self_not_allowed' })
        return
    end

    local existing = FindContactByOwnerAndTarget(ownerMailbox.mailbox_id, targetMailbox.mailbox_id)
    if existing then
        DevPrint('AddContact: duplicate contact. owner=', ownerMailbox.mailbox_id, ' target=', targetMailbox.mailbox_id)
        NotifyClient(src, _U('ContactAlreadyExists'), 'error', 5000)
        cb(false, { reason = 'duplicate' })
        return
    end

    local insertId = InsertContact(ownerMailbox.mailbox_id, targetMailbox.mailbox_id, contactAlias)
    if not insertId then
        DevPrint('AddContact: insert failed')
        NotifyClient(src, _U('ContactAddFailed') or _U('MailboxRegistrationFailed'), 'error', 5000)
        cb(false, { reason = 'insert_failed' })
        return
    end

    -- Refresh list (DB rows) and shape inside RPC
    local rows = FetchContactsRows(ownerMailbox.mailbox_id)
    local contacts = {}
    for _, r in ipairs(rows) do
        local fullName = TrimWhitespace((r.first_name or '') .. ' ' .. (r.last_name or ''))
        local alias    = r.contact_alias and TrimWhitespace(r.contact_alias) or nil
        local display  = (alias and alias ~= '' and alias)
            or (fullName ~= '' and fullName)
            or tostring(r.postal_code)

        contacts[#contacts + 1] = {
            id          = r.id,
            displayName = display,
            mailboxId   = tostring(r.mailbox_id),
            postalCode  = r.postal_code and tostring(r.postal_code) or nil,
            firstName   = r.first_name,
            lastName    = r.last_name,
        }
    end

    DevPrint('AddContact: success. owner=', ownerMailbox.mailbox_id, ' new_count=', #contacts)
    NotifyClient(src, _U('ContactAdded'), 'success', 5000)
    cb(true, { contacts = contacts, count = #contacts })
end)

BccUtils.RPC:Register('bcc-mailbox:RemoveContact', function(params, cb, src)
    DevPrint('RemoveContact RPC called. src=', src, 'params=', params)

    local contactId = params and tonumber(params.contactId)

    local user = VORPcore.getUser(src)
    if not user then
        DevPrint('RemoveContact: invalid player/char (no user)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'user_not_found' })
        return
    end
    local char = user.getUsedCharacter
    if not char then
        DevPrint('RemoveContact: invalid player/char (no character)')
        NotifyClient(src, _U('error_invalid_character_data'), 'error', 4000)
        cb(false, { reason = 'character_not_found' })
        return
    end

    local ownerMailbox = MailboxAPI:GetMailboxByCharIdentifier(char.charIdentifier)
    if not ownerMailbox then
        DevPrint('RemoveContact: mailbox not found for char_identifier=', tostring(char.charIdentifier))
        NotifyClient(src, _U('MailboxNotFound'), 'error', 5000)
        cb(false, { reason = 'mailbox_not_found' })
        return
    end

    if not contactId then
        DevPrint('RemoveContact: invalid contactId')
        NotifyClient(src, _U('InvalidContactRemoval'), 'error', 5000)
        cb(false, { reason = 'invalid_id' })
        return
    end

    local affected = DeleteContact(ownerMailbox.mailbox_id, contactId)
    if affected <= 0 then
        DevPrint('RemoveContact: delete failed. id=', contactId)
        NotifyClient(src, _U('InvalidContactRemoval'), 'error', 5000)
        cb(false, { reason = 'remove_failed' })
        return
    end

    -- Refresh list (DB rows) and shape inside RPC
    local rows = FetchContactsRows(ownerMailbox.mailbox_id)
    local contacts = {}
    for _, r in ipairs(rows) do
        local fullName = TrimWhitespace((r.first_name or '') .. ' ' .. (r.last_name or ''))
        local alias    = r.contact_alias and TrimWhitespace(r.contact_alias) or nil
        local display  = (alias and alias ~= '' and alias)
            or (fullName ~= '' and fullName)
            or tostring(r.postal_code)

        contacts[#contacts + 1] = {
            id          = r.id,
            displayName = display,
            mailboxId   = tostring(r.mailbox_id),
            postalCode  = r.postal_code and tostring(r.postal_code) or nil,
            firstName   = r.first_name,
            lastName    = r.last_name,
        }
    end

    DevPrint('RemoveContact: success. owner=', ownerMailbox.mailbox_id, ' new_count=', #contacts)
    NotifyClient(src, _U('ContactRemoved'), 'success', 5000)
    cb(true, { contacts = contacts, count = #contacts })
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
