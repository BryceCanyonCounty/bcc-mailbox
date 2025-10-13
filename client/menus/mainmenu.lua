local FeatherMenu = exports['feather-menu'].initiate()
local BccUtils = exports['bcc-utils'].initiate()

Mailbox = Mailbox or {}
local State = Mailbox.State or {}
local devPrint = Mailbox.devPrint or function() end
local sanitizePostalCodeInput = Mailbox.sanitizePostalCodeInput or function(v) return v end

local function loadContacts(nextStep)
    -- capture BOTH return values
    local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:GetContacts", {})

    if ok and data then
        Mailbox.State.contacts = data.contacts or {}
        if type(nextStep) == 'function' then
            nextStep()
        end
    else
        Mailbox.State.contacts = {}
        -- optional: debug
        -- print('GetContacts failed:', data and data.reason)
    end
end

local function fetchMailList(options)
    local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:FetchMail", {})

    if ok and data and Mailbox.ApplyMailList then
        Mailbox.ApplyMailList(data.mails or {}, options)
    end
end

local function purchaseLetter()
    devPrint('purchaseLetter request')
    local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:PurchaseLetter", {})
    if not ok then
        devPrint('Purchase letter failed')
    end
end

-- Create and expose the mailbox menu once
Mailbox.Menu = Mailbox.Menu or FeatherMenu:RegisterMenu('feather:mailbox:menu', {
    top = "3%",
    left = "3%",
    ['720width'] = '400px',
    ['1080width'] = '500px',
    ['2kwidth'] = '600px',
    ['4kwidth'] = '800px',
    style = {},
    contentslot = {
        style = {
            ['height'] = '450px',
            ['min-height'] = '300px'
        }
    },
    draggable = true,
}, {
    opened = function()
        State.menuOpen = true
        DisplayRadar(false)
    end,
    closed = function()
        State.menuOpen = false
        DisplayRadar(true)
    end
})

-- keep local refs to pages
local RegisterPage, MailActionPage, ManageContactsPage, AddContactPage, SendMessagePage, CheckMessagePage, SelectRecipientPage

-- Open the root mailbox menu
function OpenMailboxMenu(hasMailbox)
    devPrint('OpenMailboxMenu', tostring(hasMailbox))
    SendMessagePage = nil
    CheckMessagePage = nil
    SelectRecipientPage = nil
    ManageContactsPage = nil
    AddContactPage = nil
    RegisterPage = nil
    MailActionPage = nil

    if not State.playermailboxId then
        State.playermailboxId = _U('MailNotRegistered')
    end

    -- Only update display when menu is active to avoid feather-menu internal nils
    if State.menuOpen and State.MailboxDisplay ~= nil then
        State.MailboxDisplay:update({ value = _U('PostalCodeLabel') ..
        (State.playerPostalCode or _U('MailNotRegistered')) })
    end

    if not RegisterPage then
        devPrint('Creating RegisterPage')
        RegisterPage = Mailbox.Menu:RegisterPage('register:page')
        RegisterPage:RegisterElement('header', {
            value = _U('RegisterPageHeader'),
            slot = "header",
            style = {}
        })

        RegisterPage:RegisterElement('button', {
            label = _U('MailboxRegistrationButton'),
            style = {}
        }, function()
            devPrint("Register Mailbox button pressed")
            local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:RegisterMailbox", {})
            if ok and data then
                if Mailbox.ApplyMailboxStatus then
                    Mailbox.ApplyMailboxStatus({
                        mailboxId = data.mailboxId,
                        postalCode = data.postalCode,
                        hasMailbox = true
                    }, { openMenu = false })
                else
                    Mailbox.State.playermailboxId = data.mailboxId
                    Mailbox.State.playerPostalCode = data.postalCode
                end
                OpenMailboxMenu(true)
            else
                devPrint("Mailbox registration failed via RPC")
            end
        end)
        devPrint("RegisterPage created")

        if State.nearMailbox then
            RegisterPage:RegisterElement('button', {
                label = _U('PurchaseLetterButton'),
                style = {}
            }, function()
                devPrint("Purchase letter button pressed")
                purchaseLetter()
            end)
        end
    end

    if not MailActionPage then
        devPrint("Creating MailActionPage")
        MailActionPage = Mailbox.Menu:RegisterPage('mailaction:page')
        MailActionPage:RegisterElement('header', {
            value = _U('MailActionPageHeader'),
            slot = "header",
            style = {}
        })

        MailActionPage:RegisterElement('line', {
            slot = "header",
            style = {}
        })

        State.MailboxDisplay = MailActionPage:RegisterElement('textdisplay', {
            value = _U('PostalCodeLabel') .. (State.playerPostalCode or _U('MailNotRegistered')),
            slot = "content",
            style = {}
        })

        MailActionPage:RegisterElement('button', {
            label = _U('SendMailButton'),
            style = {}
        }, function()
            devPrint("Send Mail button pressed")
            loadContacts(function()
                OpenSendMessagePage()
            end)
        end)

        MailActionPage:RegisterElement('button', {
            label = _U('CheckMailButton'),
            style = {}
        }, function()
            devPrint("Check Mail button pressed")
            Mailbox.State.suppressMailNotify = true
            fetchMailList({ skipNotify = true })
        end)

        if State.nearMailbox then
            MailActionPage:RegisterElement('button', {
                label = _U('PurchaseLetterButton'),
                style = {}
            }, function()
                devPrint("Buy letter button pressed")
                purchaseLetter()
            end)
        end

        MailActionPage:RegisterElement('button', {
            label = _U('ManageContactsButton'),
            style = {}
        }, function()
            devPrint("Manage Contacts button pressed")
            loadContacts(function()
                OpenManageContactsPage()
            end)
        end)
        devPrint("MailActionPage created")
    end

    if hasMailbox then
        devPrint("Opening MailActionPage")
        Mailbox.Menu:Open({ startupPage = MailActionPage })
    else
        devPrint("Opening RegisterPage")
        Mailbox.Menu:Open({ startupPage = RegisterPage })
    end
    -- After open, display becomes safe to update
    if State.MailboxDisplay ~= nil then
        State.MailboxDisplay:update({ value = _U('PostalCodeLabel') ..
        (State.playerPostalCode or _U('MailNotRegistered')) })
    end
end

function OpenCheckMessagePage(mails)
    devPrint("Opening CheckMessagePage")
    CheckMessagePage = Mailbox.Menu:RegisterPage('checkmail:page')
    CheckMessagePage:RegisterElement('header', {
        value = _U('ReceivedMessagesHeader'),
        slot = "header",
        style = {}
    })

    CheckMessagePage:RegisterElement('line', {
        slot = "header",
        style = {}
    })

    for index, mail in ipairs(mails or {}) do
        local fromName = mail.from_name or "Unknown"
        local subject = mail.subject or "No Subject"
        local fromCode = mail.from_char and tostring(mail.from_char) or _U('UnknownPostalCode')
        local buttonLabel = tostring(index) ..
        ". " .. _U('mailFrom') .. " " .. fromName .. " (" .. fromCode .. ") — " .. subject

        CheckMessagePage:RegisterElement('button', {
            label = buttonLabel,
            slot = "content",
            style = {}
        }, function()
            OpenMessagePage(mail)
        end)
    end

    CheckMessagePage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    CheckMessagePage:RegisterElement('button', {
        label = _U('BackButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        OpenMailboxMenu(true)
    end)

    CheckMessagePage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    CheckMessagePage:RouteTo()
end

function OpenMessagePage(mail)
    devPrint("Opening MessagePage for mail:", mail and json.encode(mail) or 'nil')
    local MessagePage = Mailbox.Menu:RegisterPage('message:page')

    local mailId = tonumber(mail and mail.id or 0)
    if mailId and mailId > 0 then
        if tonumber(mail.is_read or 0) ~= 1 then
            -- ⬇️ capture BOTH return values
            local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:MarkMailRead", { mailId = mailId, read = true })

            if ok and data then
                mail.is_read = tonumber(data.readState or 1) or 1

                -- update cache
                local list = State.lastMails or {}
                for index, cached in ipairs(list) do
                    if tonumber(cached.id or 0) == mailId then
                        cached.is_read = mail.is_read
                        break
                    end
                end
            else
                -- optional: handle error (data may contain .reason)
                -- print('MarkMailRead failed', data and data.reason)
            end
        end
    end

    MessagePage:RegisterElement('header', {
        value = _U('MessageContentHeader'),
        slot = "header",
        style = {}
    })

    local fromName = mail.from_name or _U('UnknownSender')
    local fromCode = mail.from_char and tostring(mail.from_char) or _U('UnknownPostalCode')
    local messageHTML = table.concat({
        [[<div style="width: 80%; margin: 40px auto; padding: 20px; font-family: 'Bookman Old Style', serif; border: 1px solid #8B4513; border-radius: 5px;">]],
        [[    <p style="font-size:18px; margin-bottom: 6px; text-align:left;">]],
        [[        ]] .. _U('mailFrom') .. " " .. fromName .. " (" .. fromCode .. ")",
        [[    </p>]],
        [[    <p style="font-size:22px; font-weight:bold; margin-bottom: 10px; text-align:center; text-shadow: 1px 1px 2px #000;">]],
        [[        ]] .. (mail.subject or "No Subject"),
        [[    </p>]],
        [[    <p style="font-size:18px; line-height: 1.7; text-align:left; white-space:pre-wrap; border: 1px solid #8B4513; border-radius: 3px; padding: 10px;">]],
        [[        ]] .. (mail.message or "No message content"),
        [[    </p>]],
        [[</div>]]
    }, '\n')

    MessagePage:RegisterElement('html', {
        value = { messageHTML },
        style = {}
    })

    MessagePage:RegisterElement('checkbox', {
        label = _U('MarkAsUnreadLabel'),
        start = (tonumber(mail.is_read or 0) == 0)
    }, function(data)
        local markUnread = data.value and data.value ~= false
        local current = tonumber(mail.is_read or 0) or 0
        local desired = markUnread and 0 or 1
        if current == desired then return end

        local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:MarkMailRead", { mailId = mail.id, read = not markUnread })
        if ok and data then
            local state = tonumber(data.readState or desired) or desired
            mail.is_read = state
            for index, cached in ipairs(State.lastMails or {}) do
                if tonumber(cached.id or 0) == tonumber(mail.id or 0) then
                    State.lastMails[index].is_read = state
                    break
                end
            end
        else
            -- revert checkbox to previous state if update failed
            Mailbox.State.suppressMailNotify = true
            fetchMailList({ skipNotify = true })
        end
    end)

    MessagePage:RegisterElement('line', {
        slot = "footer",
        style = {},
    })

    MessagePage:RegisterElement('button', {
        label = _U('BackButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        OpenCheckMessagePage(State.lastMails or {})
    end)

    MessagePage:RegisterElement('button', {
        label = _U('ReplyButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        OpenSendMessagePageWithReply(mail)
    end)

    MessagePage:RegisterElement('button', {
        label = _U('DeleteMailButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        Mailbox.State.suppressMailNotify = true
        BccUtils.RPC:CallAsync("bcc-mailbox:DeleteMail", { mailId = mail.id })
        fetchMailList({ skipNotify = true })
    end)

    MessagePage:RegisterElement('bottomline', {
        slot = "footer",
        style = {},
    })

    MessagePage:RouteTo()
end

function OpenSelectRecipientPage()
    devPrint("Creating SelectRecipientPage")
    local function renderList(filter, rawValue)
        local rawInput = rawValue or filter or ''
        local filterLower = (filter or ''):lower()

        SelectRecipientPage = Mailbox.Menu:RegisterPage('selectrecipient:page')
        SelectRecipientPage:RegisterElement('header', {
            value = _U('SelectRecipientHeader'),
            slot = "header",
            style = {}
        })

        SelectRecipientPage:RegisterElement('line', {
            slot = "header",
            style = {}
        })

        SelectRecipientPage:RegisterElement('input', {
            label = _U('SearchRecipientsLabel') or 'Search',
            placeholder = _U('SearchRecipientsPlaceholder') or 'Type to search...',
            persist = false,
            value = rawInput,
            style = {}
        }, function(data)
            local entry = data.value or ''
            renderList(entry, entry)
        end)

        local sortedContacts = {}
        for _, contact in ipairs(State.contacts or {}) do
            sortedContacts[#sortedContacts + 1] = contact
        end
        table.sort(sortedContacts, function(a, b)
            local nameA = (a.displayName or a.postalCode or ''):lower()
            local nameB = (b.displayName or b.postalCode or ''):lower()
            if nameA == nameB then
                return (a.postal_code or '') < (b.postal_code or '')
            end
            return nameA < nameB
        end)

        local hasResults = false
        for _, contact in ipairs(sortedContacts) do
            local displayName = contact.displayName or contact.postalCode
            local label = (displayName or '') .. " (" .. (contact.postalCode or '') .. ")"
            local haystack = label:lower()
            local contactPostal = sanitizePostalCodeInput(contact.postalCode)
            local skipSelf = (contact.mailboxId and contact.mailboxId == State.playermailboxId)
                or (contactPostal ~= '' and contactPostal == sanitizePostalCodeInput(State.playerPostalCode))
            if not skipSelf then
                if filterLower == '' or haystack:find(filterLower, 1, true) then
                    hasResults = true
                    SelectRecipientPage:RegisterElement('button', {
                        label = label,
                        style = {},
                    }, function()
                        devPrint("Recipient selected: " .. label)
                        State.selectedPostalCode = contactPostal
                        State.selectedContactName = displayName
                        OpenSendMessagePage()
                    end)
                end
            end
        end

        if not hasResults then
            SelectRecipientPage:RegisterElement('textdisplay', {
                value = _U('NoContactsWarning'),
                slot = "content",
                style = {}
            })
        end

        SelectRecipientPage:RegisterElement('line', {
            slot = "footer",
            style = {}
        })

        SelectRecipientPage:RegisterElement('button', {
            label = _U('BackButtonLabel'),
            slot = "footer",
            style = {},
        }, function()
            OpenMailboxMenu(true)
        end)

        SelectRecipientPage:RegisterElement('bottomline', {
            slot = "footer",
            style = {}
        })

        SelectRecipientPage:RouteTo()
    end

    renderList('', '')
end

function OpenSendMessagePage(defaults)
    defaults = defaults or {}
    local initialPostal = sanitizePostalCodeInput(defaults.postalCode or State.selectedPostalCode or '')
    if initialPostal ~= '' then
        State.selectedPostalCode = initialPostal
    end
    if defaults.selectedName then
        State.selectedContactName = defaults.selectedName
    end

    devPrint("Creating SendMessagePage")
    SendMessagePage = Mailbox.Menu:RegisterPage('sendmail:page')
    SendMessagePage:RegisterElement('header', {
        value = _U('SendPigeonHeader'),
        slot = "header",
        style = {}
    })

    local mailMessage = defaults.message or ''
    local subjectTitle = defaults.subject or ''
    local recipientCode = State.selectedPostalCode or ''

    SendMessagePage:RegisterElement('line', {
        slot = "header",
        style = {}
    })

    SendMessagePage:RegisterElement('button', {
        label = _U('SelectRecipientButton'),
        style = {}
    }, function()
        devPrint("Select Recipient button pressed")
        OpenSelectRecipientPage()
    end)

    SendMessagePage:RegisterElement('textdisplay', {
        value = _U('SelectedContactLabel') .. (State.selectedContactName or _U('ManualRecipientLabel')),
        slot = "content",
        style = {}
    })

    if defaults.infoHtml then
        SendMessagePage:RegisterElement('html', {
            value = { defaults.infoHtml },
            slot = "content",
            style = {}
        })
    end

    SendMessagePage:RegisterElement('input', {
        persist = false,
        label = _U('PostalCodeLabel'),
        placeholder = _U('PostalCodePlaceholder'),
        value = recipientCode,
        style = {}
    }, function(data)
        local sanitized = sanitizePostalCodeInput(data.value)
        recipientCode = sanitized
        State.selectedPostalCode = sanitized
        if sanitized ~= '' then
            State.selectedContactName = nil
        end
    end)

    SendMessagePage:RegisterElement('input', {
        persist = false,
        label = _U('SubjectPlaceholder'),
        placeholder = _U('SubjectPlaceholder'),
        value = subjectTitle,
        style = {}
    }, function(data)
        subjectTitle = data.value
    end)

    SendMessagePage:RegisterElement('textarea', {
        placeholder = _U('MessagePlaceholder'),
        rows = "6",
        resize = true,
        value = mailMessage,
        style = {}
    }, function(data)
        mailMessage = data.value
    end)

    SendMessagePage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    SendMessagePage:RegisterElement('button', {
        label = _U('SendMailButton'),
        slot = "footer",
        style = {},
    }, function()
        local sendCode = sanitizePostalCodeInput(recipientCode)
        if sendCode == '' then
            Notify(_U('InvalidRecipient'), "error", 5000)
            return
        end
        devPrint("recipientPostalCode:", tostring(sendCode), "subjectTitle:", subjectTitle)
        BccUtils.RPC:CallAsync("bcc-mailbox:SendMail", {
            recipientPostalCode = sendCode,
            subject = subjectTitle,
            message = mailMessage
        })
        if Config.SendPigeon then
            SpawnPigeon()
        end
        OpenMailboxMenu(true)
    end)

    SendMessagePage:RegisterElement('button', {
        label = _U('BackButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        OpenMailboxMenu(true)
    end)

    SendMessagePage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    devPrint("SendMessagePage created")
    SendMessagePage:RouteTo()
end

function OpenSendMessagePageWithReply(originalMail)
    if not originalMail then return end
    local replyCode = sanitizePostalCodeInput(originalMail.from_char or '')
    if replyCode == '' then
        Notify(_U('InvalidRecipient'), "error", 5000)
        return
    end

    State.selectedPostalCode = replyCode
    State.selectedContactName = originalMail.from_name or replyCode

    local replySubject = 'Re: ' .. (originalMail.subject or 'No Subject')

    OpenSendMessagePage({
        postalCode = replyCode,
        subject = replySubject,
        selectedName = State.selectedContactName,
        infoHtml = '<p style="text-align: center; font-size: 16px; margin: 10px 0;">'
            .. (_U('ReplyingToLabel') or 'Replying to:')
            .. ' <b>' .. (originalMail.from_name or 'Unknown') .. '</b></p>'
    })
end

function OpenManageContactsPage()
    devPrint("Opening ManageContactsPage")
    ManageContactsPage = Mailbox.Menu:RegisterPage('managecontacts:page')
    ManageContactsPage:RegisterElement('header', {
        value = _U('ManageContactsHeader'),
        slot = "header",
        style = {}
    })

    ManageContactsPage:RegisterElement('line', {
        slot = "header",
        style = {}
    })

    if #(State.contacts or {}) == 0 then
        ManageContactsPage:RegisterElement('textdisplay', {
            value = _U('NoContactsWarning'),
            slot = "content",
            style = {}
        })
    end

    for _, contact in ipairs(State.contacts or {}) do
        local label = (contact.displayName or contact.postalCode or '') .. " (" .. (contact.postalCode or '') .. ")"
        ManageContactsPage:RegisterElement('button', {
            label = _U('RemoveContactButton') .. label,
            style = {},
        }, function()
            devPrint("Removing contact:", label)
            local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:RemoveContact", { contactId = contact.id })
            if ok and data then
                Mailbox.State.contacts = data.contacts or {}
                OpenManageContactsPage()
            else
                loadContacts(function()
                    OpenManageContactsPage()
                end)
            end
        end)
    end

    ManageContactsPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    ManageContactsPage:RegisterElement('button', {
        label = _U('AddContactButton'),
        slot = "footer",
        style = {}
    }, function()
        OpenAddContactPage()
    end)

    ManageContactsPage:RegisterElement('button', {
        label = _U('BackButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        OpenMailboxMenu(true)
    end)

    ManageContactsPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    ManageContactsPage:RouteTo()
end

function OpenAddContactPage()
    devPrint("Opening AddContactPage")
    AddContactPage = Mailbox.Menu:RegisterPage('addcontact:page')
    AddContactPage:RegisterElement('header', {
        value = _U('AddContactHeader'),
        slot = "header",
        style = {}
    })

    local contactCodeInput = ''
    local contactAliasInput = ''

    AddContactPage:RegisterElement('line', {
        slot = "header",
        style = {}
    })

    AddContactPage:RegisterElement('input', {
        persist = false,
        label = _U('PostalCodeLabel'),
        placeholder = _U('PostalCodePlaceholder'),
        style = {}
    }, function(data)
        contactCodeInput = sanitizePostalCodeInput(data.value)
    end)

    AddContactPage:RegisterElement('input', {
        persist = false,
        label = _U('ContactAliasLabel'),
        placeholder = _U('ContactAliasPlaceholder'),
        style = {}
    }, function(data)
        contactAliasInput = data.value
    end)

    AddContactPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    AddContactPage:RegisterElement('button', {
        label = _U('SaveContactButton'),
        slot = "footer",
        style = {},
    }, function()
        local ok, data = BccUtils.RPC:CallAsync("bcc-mailbox:AddContact", {
            contactCode  = contactCodeInput,
            contactAlias = contactAliasInput
        })
        if ok and data then
            Mailbox.State.contacts = data.contacts or {}
            OpenManageContactsPage()
        else
            loadContacts(function()
                OpenManageContactsPage()
            end)
        end
    end)

    AddContactPage:RegisterElement('button', {
        label = _U('BackButtonLabel'),
        slot = "footer",
        style = {},
    }, function()
        OpenManageContactsPage()
    end)

    AddContactPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    AddContactPage:RouteTo()
end
