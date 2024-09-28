local VORPcore = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()

-- Function to print debug messages
function devPrint(msg)
    if Config.devMode then
        print(msg)
    end
end

-- Function to register mailbox item
local function registerMailboxItem(itemName)
    exports.vorp_inventory:registerUsableItem(itemName, function(data)
        handleMailboxItemUse(data.source, itemName)
    end)
end

-- Function to handle mailbox item use
function handleMailboxItemUse(src, itemName)
    local User = VORPcore.getUser(src)

    if User then
        local Character = User.getUsedCharacter
        if Character then
            local charidentifier = Character.charIdentifier
            local firstName = Character.firstname
            local lastName = Character.lastname

            exports.oxmysql:query('SELECT mailbox_id FROM bcc_mailboxes WHERE char_identifier = ?', {charidentifier}, function(result)
                if result and #result > 0 then
                    local mailboxId = result[1].mailbox_id
                    TriggerClientEvent("bcc-mailbox:mailboxStatus", src, true, mailboxId, firstName .. " " .. lastName)
                else
                    TriggerClientEvent("bcc-mailbox:mailboxStatus", src, false, nil, firstName .. " " .. lastName)
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

registerMailboxItem(Config.MailboxItem)

-- Function to update mailbox info
function updateMailboxInfo(src)
    local User = VORPcore.getUser(src)
    if User then
        local Character = User.getUsedCharacter
        if Character then
            local charidentifier = Character.charIdentifier
            local firstName = Character.firstname
            local lastName = Character.lastname

            exports.oxmysql:execute('UPDATE bcc_mailboxes SET first_name = ?, last_name = ? WHERE char_identifier = ?', {firstName, lastName, charidentifier}, function(affectedRows)
                if affectedRows and affectedRows > 0 then
                    devPrint(_U('UpdateMailboxInfo') .. charidentifier)
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

-- Function to get player source by mailbox ID
function GetPlayerFromMailboxId(mailboxId, callback)
    local foundPlayerId = nil
    local players = GetPlayers()
    local totalPlayers = #players
    local checkedPlayers = 0

    for _, playerId in ipairs(players) do
        local User = VORPcore.getUser(playerId)
        if User then
            local Character = User.getUsedCharacter
            if Character then
                exports.oxmysql:query('SELECT mailbox_id FROM bcc_mailboxes WHERE char_identifier = ?', {Character.charIdentifier}, function(result)
                    checkedPlayers = checkedPlayers + 1
                    if result and #result > 0 then
                        local playerMailboxId = tostring(result[1].mailbox_id)
                        devPrint("Checking player: " .. playerId .. " with Mailbox ID: '" .. playerMailboxId .. "'")
                        if playerMailboxId == tostring(mailboxId) then
                            foundPlayerId = playerId
                            devPrint("Found matching player: " .. playerId)
                            callback(foundPlayerId)
                            return
                        end
                    end

                    -- If all players have been checked and no match was found
                    if checkedPlayers == totalPlayers and not foundPlayerId then
                        devPrint("No matching player found for Mailbox ID: '" .. mailboxId .. "'")
                        callback(nil)
                    end
                end)
            else
                checkedPlayers = checkedPlayers + 1
                if checkedPlayers == totalPlayers and not foundPlayerId then
                    devPrint("No matching player found for Mailbox ID: '" .. mailboxId .. "'")
                    callback(nil)
                end
            end
        else
            checkedPlayers = checkedPlayers + 1
            if checkedPlayers == totalPlayers and not foundPlayerId then
                devPrint("No matching player found for Mailbox ID: '" .. mailboxId .. "'")
                callback(nil)
            end
        end
    end
end

RegisterNetEvent("bcc-mailbox:sendMail")
AddEventHandler("bcc-mailbox:sendMail", function(recipientMailboxId, subject, message)
    local _source = source
    local User = VORPcore.getUser(_source)
    local Character = User.getUsedCharacter
    local senderCharId = Character.charIdentifier
    local senderName = Character.firstname .. " " .. Character.lastname

    devPrint("sendMail event triggered")
    devPrint("Recipient Mailbox ID: '" .. recipientMailboxId .. "'")
    devPrint("Subject: " .. subject)
    devPrint("Message: " .. message)

    if Character.money >= Config.SendMessageFee then
        Character.removeCurrency(0, Config.SendMessageFee)

        exports.oxmysql:query('SELECT mailbox_id FROM bcc_mailboxes WHERE char_identifier = ?', {senderCharId}, function(senderResult)
            if senderResult and #senderResult > 0 then
                local senderMailboxId = senderResult[1].mailbox_id
                if recipientMailboxId and recipientMailboxId ~= "" and subject and subject ~= "" and message and message ~= "" then
                    local formattedTimestamp = os.date('%Y-%m-%d %H:%M:%S', os.time())
                    exports.oxmysql:insert('INSERT INTO bcc_mailbox_messages (from_char, to_char, from_name, subject, message, timestamp) VALUES (?, ?, ?, ?, ?, ?)', 
                    {senderMailboxId, recipientMailboxId, senderName, subject, message, formattedTimestamp}, function(inserted)
                        if inserted then
                            VORPcore.NotifyObjective(_source, _U('MessageSent'), 5000)

                            -- Notify the recipient about the new mail using the callback
                            GetPlayerFromMailboxId(recipientMailboxId, function(recipientSource)
                                if recipientSource then
                                    devPrint("Notifying recipient: " .. recipientSource)  -- Debug print
                                    TriggerClientEvent("bcc-mailbox:checkMailNotification", recipientSource)
                                else
                                    devPrint("Recipient not found for mailbox identifier: '" .. recipientMailboxId .. "'")  -- Debug print
                                end
                            end)
                        else
                            VORPcore.NotifyObjective(_source, _U('MessageFailed'), 5000)
                        end
                    end)
                else
                    VORPcore.NotifyObjective(_source, _U('InvalidRecipient'), 5000)
                end
            else
                VORPcore.NotifyObjective(_source, _U('MailboxNotFound'), 5000)
            end
        end)
    else
        VORPcore.NotifyObjective(_source, _U('NotEnoughMoney'), 5000)
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
    local Character = User.getUsedCharacter
    local charidentifier = Character.charIdentifier
    local firstName = Character.firstname
    local lastName = Character.lastname

    exports.oxmysql:query('SELECT mailbox_id FROM bcc_mailboxes WHERE char_identifier = ?', {charidentifier}, function(result)
        if result and #result > 0 then
            TriggerClientEvent("bcc-mailbox:mailboxStatus", _source, true, result[1].mailbox_id, firstName .. " " .. lastName)
        else
            TriggerClientEvent("bcc-mailbox:mailboxStatus", _source, false, nil, firstName .. " " .. lastName)
        end
    end)
end)

RegisterNetEvent("bcc-mailbox:checkMail")
AddEventHandler("bcc-mailbox:checkMail", function()
    local _source = source
    local User = VORPcore.getUser(_source)
    local Character = User.getUsedCharacter
    local charidentifier = Character.charIdentifier

    exports.oxmysql:execute('SELECT mailbox_id FROM bcc_mailboxes WHERE char_identifier = ?', {charidentifier}, function(result)
        if result and #result > 0 then
            local recipientMailboxId = result[1].mailbox_id

            exports.oxmysql:execute('SELECT * FROM bcc_mailbox_messages WHERE to_char = ?', {recipientMailboxId}, function(mails)
                if mails and #mails > 0 then
                    for _, mail in ipairs(mails) do
                        mail.timestamp = os.date('%Y-%m-%d %H:%M:%S', mail.timestamp)
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
    local Character = User.getUsedCharacter
    local charidentifier = Character.charIdentifier
    local first_name = Character.firstname
    local last_name = Character.lastname

    if Character.money >= Config.RegistrationFee then
        Character.removeCurrency(0, Config.RegistrationFee)

        exports.oxmysql:insert('INSERT INTO bcc_mailboxes (char_identifier, first_name, last_name) VALUES (?, ?, ?)', 
        {charidentifier, first_name, last_name}, function(insertId)
            if insertId then
                exports.oxmysql:execute('SELECT mailbox_id FROM bcc_mailboxes WHERE mailbox_id = ?', {insertId}, function(result)
                    if result and #result > 0 then
                        local newMailboxId = result[1].mailbox_id
                        TriggerClientEvent("bcc-mailbox:updateMailboxId", _source, newMailboxId)
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

    exports.oxmysql:execute('DELETE FROM bcc_mailbox_messages WHERE id = ?', {mailId}, function(affectedRows)
        if affectedRows then
            VORPcore.NotifyObjective(_source, _U('MailDeleted'), 5000)
        else
            VORPcore.NotifyObjective(_source, _U('MailDeletionFailed'), 5000)
        end
    end)
end)

RegisterNetEvent("bcc-mailbox:getRecipients")
AddEventHandler("bcc-mailbox:getRecipients", function()
    local _source = source

    exports.oxmysql:query('SELECT mailbox_id, CONCAT(first_name, " ", last_name) AS name FROM bcc_mailboxes', {}, function(results)
        if results then
            TriggerClientEvent('bcc-mailbox:setRecipients', _source, results)
        end
    end)
end)

-- Function to get all players
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