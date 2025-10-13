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

local function updatePostalDisplay()
    if Mailbox.State.menuOpen and Mailbox.State.MailboxDisplay ~= nil then
        Mailbox.State.MailboxDisplay:update({
            value = _U('PostalCodeLabel') .. (Mailbox.State.playerPostalCode or _U('MailNotRegistered'))
        })
    end
end

local function applyMailboxStatus(data, opts)
    if not data then return end
    if data.hasMailbox == false then
        Mailbox.State.playermailboxId = nil
        Mailbox.State.playerPostalCode = nil
    else
        Mailbox.State.playermailboxId = data.mailboxId or Mailbox.State.playermailboxId
        Mailbox.State.playerPostalCode = data.postalCode or Mailbox.State.playerPostalCode
    end
    updatePostalDisplay()
    if opts and opts.openMenu then
        OpenMailboxMenuProxy(data.hasMailbox ~= false)
    end
end

Mailbox.ApplyMailboxStatus = applyMailboxStatus

local function applyMailList(mails, opts)
    Mailbox.State.lastMails = mails or {}
    local skipNotify = (opts and opts.skipNotify) or Mailbox.State.suppressMailNotify
    Mailbox.State.suppressMailNotify = false

    if not skipNotify then
        local hasUnread = false
        for _, mail in ipairs(Mailbox.State.lastMails) do
            if tonumber(mail.is_read or 0) ~= 1 then
                hasUnread = true
                break
            end
        end
        if hasUnread then
            Notify(_U('NewMailNotification'), "info", 5000)
        end
    end

    local openPage = true
    if opts and opts.openPage ~= nil then
        openPage = opts.openPage
    end

    if openPage and type(OpenCheckMessagePage) == 'function' then
        OpenCheckMessagePage(Mailbox.State.lastMails)
    end
end

Mailbox.ApplyMailList = applyMailList

BccUtils.RPC:Register('bcc-mailbox:checkMailNotification', function(params, cb)
    local unreadCount = params and params.unreadCount
    devPrint("checkMailNotification", unreadCount)

    local unreadTotal = tonumber(unreadCount or 0) or 0
    if unreadTotal > 0 then
        Notify(_U('NewMailNotification'), "info", 5000)
    end

    local ok, data = BccUtils.RPC:Call("bcc-mailbox:FetchMail", {})
    if ok and data then
        applyMailList(data.mails or {}, { skipNotify = true })
    end

    if cb then cb(true) end
end)

BccUtils.RPC:Register('bcc-mailbox:mailboxStatus', function(params, cb)
    local hasMailbox  = params and params.hasMailbox
    local mailboxId   = params and params.mailboxId
    local playerName  = params and params.playerName
    local postalCode  = params and params.postalCode

    devPrint("mailboxStatus", hasMailbox, mailboxId, playerName, postalCode)
    applyMailboxStatus({ hasMailbox = hasMailbox, mailboxId = mailboxId, postalCode = postalCode }, { openMenu = true })

    if cb then cb(true) end
end)

function SpawnPigeon()
    devPrint("spawnPigeon")
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnCoords = vector3(playerCoords.x + 0.0, playerCoords.y + 0.0, playerCoords.z + 0.0)

    local model = GetHashKey('A_C_Pigeon')
    RequestModel(model, false)
    while not HasModelLoaded(model) do
        Wait(1)
    end

    local pigeon = CreatePed(model, spawnCoords.x, spawnCoords.y, spawnCoords.z, 0.0, true, false, true, true)

    TaskFlyAway(pigeon, playerPed)
    SetModelAsNoLongerNeeded(model)
end

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

        local playerPed = PlayerPedId()

        -- if dead: clear prompt and chill
        if IsEntityDead(playerPed) then
            if mailboxPrompt then
                mailboxPrompt:DeletePrompt()
                mailboxPrompt = nil
            end
            Mailbox.State.nearMailbox = false
            Wait(1000) -- throttle while dead
        else
            -- alive: proximity + prompt logic
            local playerCoords = GetEntityCoords(playerPed)
            local nearMailbox = false

            for _, location in pairs(Config.MailboxLocations) do
                if Vdist(playerCoords, location.coords.x, location.coords.y, location.coords.z) < 2.0 then
                    nearMailbox = true
                    break
                end
            end

            Mailbox.State.nearMailbox = nearMailbox

            if nearMailbox then
                if not mailboxPrompt then
                    registerMailboxPrompt()
                end

                PromptGroup:ShowGroup(_U('NearMailbox'))

                if mailboxPrompt:HasCompleted() then
                    devPrint(_U('MailboxPromptCompleted'))

                    local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:CheckMailbox", {})
                    if ok and data then
                        applyMailboxStatus({
                            hasMailbox = data.hasMailbox,
                            mailboxId  = data.mailboxId,
                            postalCode = data.postalCode,
                            fullName   = data.fullName,
                        }, { openMenu = true })
                    else
                        applyMailboxStatus({
                            mailboxId  = Mailbox.State.playermailboxId,
                            postalCode = Mailbox.State.playerPostalCode,
                            hasMailbox = false
                        }, { openMenu = true })
                    end

                    registerMailboxPrompt()
                end
            else
                if mailboxPrompt then
                    mailboxPrompt:DeletePrompt()
                    mailboxPrompt = nil
                end
                Mailbox.State.nearMailbox = false
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)

        local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:UpdateMailboxInfo", {})
        if ok and data then
            applyMailboxStatus({
                mailboxId  = data.mailboxId or Mailbox.State.playermailboxId,
                postalCode = data.postalCode or Mailbox.State.playerPostalCode
            }, { openMenu = false })
        end
    end
end)

CreateThread(function()
    local intervalMinutes = tonumber(Config.UnreadReminderIntervalMinutes or 15) or 15
    local intervalMs = math.max(60000, math.floor(intervalMinutes * 60000))
    Wait(30000)
    while true do
        local ok, poll = BccUtils.RPC:CallAsync("bcc-mailbox:PollUnread", {})
        if ok and poll and (tonumber(poll.unread or 0) or 0) > 0 then
            BccUtils.RPC:Notify('bcc-mailbox:checkMailNotification', { unreadCount = poll.unread })
        end
        Wait(intervalMs)
    end
end)