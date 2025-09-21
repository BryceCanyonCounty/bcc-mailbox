Mailbox = Mailbox or {}

-- shared client state, safe to load multiple times
Mailbox.State = Mailbox.State or {
    playermailboxId = nil,
    playerPostalCode = nil,
    selectedPostalCode = nil,
    selectedContactName = nil,
    contacts = {},
    pendingContactsAction = nil,
    lastMails = {},
    MailboxDisplay = nil,
}

-- helpers (no side effects)
function Mailbox.sanitizePostalCodeInput(value)
    if not value then return '' end
    local sanitized = tostring(value):gsub('%s+', '')
    return sanitized:upper()
end

if Config and Config.devMode then
    function Mailbox.devPrint(...)
        local parts = {}
        for i = 1, select('#', ...) do
            local v = select(i, ...)
            if type(v) == 'table' then v = json.encode(v) end
            parts[#parts+1] = tostring(v)
        end
        print(table.concat(parts, ' '))
    end
else
    function Mailbox.devPrint(...) end
end

function Mailbox.FormatDate(timestamp)
    return timestamp
end

