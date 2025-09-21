local VORPcore = exports.vorp_core:GetCore()
local FeatherMenu = exports['feather-menu'].initiate()

Mailbox = Mailbox or {}
local State = Mailbox.State or {}
local devPrint = Mailbox.devPrint or function() end
local sanitizePostalCodeInput = Mailbox.sanitizePostalCodeInput or function(v) return v end

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

    if not State.playermailboxId then
        State.playermailboxId = _U('MailNotRegistered')
    end

    -- Only update display when menu is active to avoid feather-menu internal nils
    if State.menuOpen and State.MailboxDisplay ~= nil then
        State.MailboxDisplay:update({ value = _U('PostalCodeLabel') .. (State.playerPostalCode or _U('MailNotRegistered')) })
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
            TriggerServerEvent("bcc-mailbox:registerMailbox")
        end)
        devPrint("RegisterPage created")
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
            State.pendingContactsAction = function()
                OpenSendMessagePage()
            end
            TriggerServerEvent('bcc-mailbox:getContacts')
        end)

        MailActionPage:RegisterElement('button', {
            label = _U('CheckMailButton'),
            style = {}
        }, function()
            devPrint("Check Mail button pressed")
            TriggerServerEvent("bcc-mailbox:checkMail")
        end)

        MailActionPage:RegisterElement('button', {
            label = _U('ManageContactsButton'),
            style = {}
        }, function()
            devPrint("Manage Contacts button pressed")
            State.pendingContactsAction = function()
                OpenManageContactsPage()
            end
            TriggerServerEvent('bcc-mailbox:getContacts')
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
        State.MailboxDisplay:update({ value = _U('PostalCodeLabel') .. (State.playerPostalCode or _U('MailNotRegistered')) })
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
        local buttonLabel = string.format("%d. %s %s (%s) — %s", index, _U('mailFrom'), fromName, fromCode, subject)

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

    MessagePage:RegisterElement('header', {
        value = _U('MessageContentHeader'),
        slot = "header",
        style = {}
    })

    local fromName = mail.from_name or _U('UnknownSender')
    local fromCode = mail.from_char and tostring(mail.from_char) or _U('UnknownPostalCode')
    local messageHTML = string.format([[        
        <div style="width: 80%%; margin: 40px auto; padding: 20px; font-family: 'Bookman Old Style', serif; border: 1px solid #8B4513; border-radius: 5px;">
            <p style="font-size:18px; margin-bottom: 6px; text-align:left;">
                %s
            </p>
            <p style="font-size:22px; font-weight:bold; margin-bottom: 10px; text-align:center; text-shadow: 1px 1px 2px #000;">
                %s
            </p>
            <p style="font-size:18px; line-height: 1.7; text-align:left; white-space:pre-wrap; border: 1px solid #8B4513; border-radius: 3px; padding: 10px;">
                %s
            </p>
        </div>
    ]],
        string.format('%s %s (%s)', _U('mailFrom'), fromName, fromCode),
        mail.subject or "No Subject",
        mail.message or "No message content"
    )

    MessagePage:RegisterElement('html', {
        value = { messageHTML },
        style = {}
    })

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
        TriggerServerEvent("bcc-mailbox:deleteMail", mail.id)
        TriggerServerEvent("bcc-mailbox:checkMail")
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
            local nameA = (a.displayName or a.postal_code or ''):lower()
            local nameB = (b.displayName or b.postal_code or ''):lower()
            if nameA == nameB then
                return (a.postal_code or '') < (b.postal_code or '')
            end
            return nameA < nameB
        end)

        local hasResults = false
        for _, contact in ipairs(sortedContacts) do
            local displayName = contact.displayName or contact.postal_code
            local label = string.format("%s (%s)", displayName, contact.postal_code)
            local haystack = label:lower()
            local contactPostal = sanitizePostalCodeInput(contact.postal_code)
            local skipSelf = (contact.mailbox_id and contact.mailbox_id == State.playermailboxId)
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
            VORPcore.NotifyObjective(_U('InvalidRecipient'), 5000)
            return
        end
        devPrint("recipientPostalCode:", tostring(sendCode), "subjectTitle:", subjectTitle)
        TriggerServerEvent("bcc-mailbox:sendMail", sendCode, subjectTitle, mailMessage)
        if Config.SendPigeon then
            TriggerEvent('spawnPigeon')
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
        VORPcore.NotifyObjective(_U('InvalidRecipient'), 5000)
        return
    end

    State.selectedPostalCode = replyCode
    State.selectedContactName = originalMail.from_name or replyCode

    local replySubject = 'Re: ' .. (originalMail.subject or 'No Subject')

    OpenSendMessagePage({
        postalCode = replyCode,
        subject = replySubject,
        selectedName = State.selectedContactName,
        infoHtml = string.format('<p style="text-align: center; font-size: 16px; margin: 10px 0;">%s <b>%s</b></p>',
            _U('ReplyingToLabel') or 'Replying to:', originalMail.from_name or 'Unknown')
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
        local label = string.format("%s (%s)", contact.displayName or contact.postal_code, contact.postal_code)
        ManageContactsPage:RegisterElement('button', {
            label = _U('RemoveContactButton') .. label,
            style = {},
        }, function()
            devPrint("Removing contact:", label)
            State.pendingContactsAction = function()
                OpenManageContactsPage()
            end
            TriggerServerEvent('bcc-mailbox:removeContact', contact.id)
        end)
    end

    ManageContactsPage:RegisterElement('line', {
        slot = "content",
        style = {}
    })

    ManageContactsPage:RegisterElement('button', {
        label = _U('AddContactButton'),
        style = {}
    }, function()
        OpenAddContactPage()
    end)

    ManageContactsPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

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
        State.pendingContactsAction = function()
            OpenManageContactsPage()
        end
        TriggerServerEvent('bcc-mailbox:addContact', contactCodeInput, contactAliasInput)
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
