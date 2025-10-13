if Config.devMode then
    function DevPrint(message)
        print("^1[DEV MODE] ^4" .. message .. "^0")
    end
else
    function DevPrint(message) end -- No-op if DevMode is disabled
end

function NotifyClient(src, message, type, duration)
    BccUtils.RPC:Notify("bcc-mailbox:NotifyClient", {
        message = message,
        type = type or "info",
        duration = duration or 4000
    }, src)
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

function GenerateUniquePostalCode()
    while true do
        local candidate = generatePostalCode()
        local exists = MySQL.scalar.await('SELECT 1 FROM bcc_mailboxes WHERE postal_code = ? LIMIT 1', { candidate })
        if not exists then
            return candidate
        end
    end
end

function NormalizePostalCode(code)
    if not code then return nil end
    local raw = tostring(code)
    local parts = {}
    for i = 1, #raw do
        local ch = raw:sub(i, i)
        if ch ~= ' ' and ch ~= '\t' and ch ~= '\n' and ch ~= '\r' then
            parts[#parts + 1] = ch
        end
    end
    local collapsed = table.concat(parts)
    if collapsed == '' then return nil end
    return string.upper(collapsed)
end

function TrimWhitespace(value)
    local str = value or ''
    local first = 1
    local last = #str

    while first <= last do
        local c = str:sub(first, first)
        if c ~= ' ' and c ~= '\t' and c ~= '\n' and c ~= '\r' then
            break
        end
        first = first + 1
    end

    while last >= first do
        local c = str:sub(last, last)
        if c ~= ' ' and c ~= '\t' and c ~= '\n' and c ~= '\r' then
            break
        end
        last = last - 1
    end

    if first > last then
        return ''
    end

    return str:sub(first, last)
end
