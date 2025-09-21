-- Client controller: events, threads and state wiring

local VORPcore = exports.vorp_core:GetCore()
local BccUtils = exports['bcc-utils'].initiate()

Mailbox = Mailbox or {}
local devPrint = Mailbox.devPrint or function() end
local sanitizePostalCodeInput = (Mailbox and Mailbox.sanitizePostalCodeInput) or function(v) return tostring(v or '') end

local function OpenMailboxMenuProxy(hasMailbox)
    if type(OpenMailboxMenu) == 'function' then
        OpenMailboxMenu(hasMailbox)
    else
        devPrint('OpenMailboxMenu not loaded yet')
    end
end

-- Notifications and actions
RegisterNetEvent("bcc-mailbox:checkMailNotification")
AddEventHandler("bcc-mailbox:checkMailNotification", function()
    devPrint("checkMailNotification")
    VORPcore.NotifyObjective(_U('NewMailNotification'), 5000)
    TriggerServerEvent("bcc-mailbox:checkMail")
end)

RegisterNetEvent("bcc-mailbox:mailboxStatus")
AddEventHandler("bcc-mailbox:mailboxStatus", function(hasMailbox, mailboxId, playerName, postalCode)
    devPrint("mailboxStatus", hasMailbox, mailboxId, playerName, postalCode)
    Mailbox.State.playermailboxId = mailboxId
    Mailbox.State.playerPostalCode = postalCode
    OpenMailboxMenuProxy(hasMailbox)
end)

RegisterNetEvent("bcc-mailbox:registerResult")
AddEventHandler("bcc-mailbox:registerResult", function(success, message)
    devPrint("registerResult", success, message)
    if success then
        OpenMailboxMenuProxy(true)
    else
        devPrint("Mailbox registration failed:", message)
    end
end)

RegisterNetEvent("bcc-mailbox:updateMailboxId")
AddEventHandler("bcc-mailbox:updateMailboxId", function(newMailboxId, newPostalCode)
    devPrint("updateMailboxId", newMailboxId, newPostalCode)
    Mailbox.State.playermailboxId = newMailboxId
    Mailbox.State.playerPostalCode = newPostalCode
    if Mailbox.State.menuOpen and Mailbox.State.MailboxDisplay ~= nil then
        Mailbox.State.MailboxDisplay:update({ value = _U('PostalCodeLabel') .. (Mailbox.State.playerPostalCode or _U('MailNotRegistered')) })
    end
end)

RegisterNetEvent("bcc-mailbox:receiveMails")
AddEventHandler("bcc-mailbox:receiveMails", function(mails)
    devPrint("receiveMails", mails and json.encode(mails) or 'nil')
    Mailbox.State.lastMails = mails or {}
    if #Mailbox.State.lastMails > 0 then
        VORPcore.NotifyObjective(_U('NewMailNotification'), 5000)
    end
    if type(OpenCheckMessagePage) == 'function' then
        OpenCheckMessagePage(Mailbox.State.lastMails)
    end
end)

RegisterNetEvent("bcc-mailbox:setRecipients")
AddEventHandler("bcc-mailbox:setRecipients", function(data)
    Mailbox.State.contacts = data or {}
    if Mailbox.State.pendingContactsAction then
        Mailbox.State.pendingContactsAction()
        Mailbox.State.pendingContactsAction = nil
    end
end)

-- Pigeon effect
RegisterNetEvent('spawnPigeon')
AddEventHandler('spawnPigeon', function()
    devPrint("spawnPigeon")
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnCoords = vector3(playerCoords.x + 0.0, playerCoords.y + 0.0, playerCoords.z + 0.0)
    local model = GetHashKey('A_C_Pigeon')
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(1)
    end
    local pigeon = CreatePed(model, spawnCoords.x, spawnCoords.y, spawnCoords.z, 0.0, true, false, true, true)
    TaskFlyAway(pigeon)
    SetModelAsNoLongerNeeded(model)
end)

-- Prompt near mailbox
CreateThread(function()
    local PromptGroup = BccUtils.Prompt:SetupPromptGroup()
    local mailboxPrompt = nil

    local function registerMailboxPrompt()
        if mailboxPrompt then
            mailboxPrompt:DeletePrompt()
        end
        mailboxPrompt = PromptGroup:RegisterPrompt(_U('OpenMailBox'), 0x4CC0E2FE, 1, 1, true, 'hold',
            { timedeventhash = "MEDIUM_TIMED_EVENT" })
    end

    while true do
        Wait(0)
        local playerCoords = GetEntityCoords(PlayerPedId())
        local nearMailbox = false

        for _, location in pairs(Config.MailboxLocations) do
            if Vdist(playerCoords, location.coords.x, location.coords.y, location.coords.z) < 2 then
                nearMailbox = true
                break
            end
        end

        if nearMailbox then
            if not mailboxPrompt then
                registerMailboxPrompt()
            end
            PromptGroup:ShowGroup(_U('NearMailbox'))

            if mailboxPrompt:HasCompleted() then
                devPrint(_U('MailboxPromptCompleted'))
                TriggerServerEvent("bcc-mailbox:checkMailbox")
                registerMailboxPrompt()
            end
        else
            if mailboxPrompt then
                mailboxPrompt:DeletePrompt()
                mailboxPrompt = nil
            end
        end
    end
end)

-- periodic mailbox info refresh (client -> server)
CreateThread(function()
    while true do
        Wait(60000)
        TriggerServerEvent('bcc-mailbox:updateMailboxInfo')
    end
end)
