local VORPcore = exports.vorp_core:GetCore()
local FeatherMenu = exports['feather-menu'].initiate()
local BccUtils = exports['bcc-utils'].initiate()

Config = Config or {}
Config.Notify = Config.Notify or "feather-menu"

function Notify(message, typeOrDuration, maybeDuration)
    if not message then return end

    local notifyType = "info"
    local notifyDuration = 6000

    if type(typeOrDuration) == "string" then
        notifyType = typeOrDuration
        notifyDuration = tonumber(maybeDuration) or notifyDuration
    elseif type(typeOrDuration) == "number" then
        notifyDuration = typeOrDuration
    end

    if Config.Notify == "feather-menu" and FeatherMenu and FeatherMenu.Notify then
        FeatherMenu:Notify({
            message = message,
            type = notifyType,
            autoClose = notifyDuration,
            position = "top-center",
            transition = "slide",
            icon = true,
            hideProgressBar = false,
            rtl = false,
            style = {},
            toastStyle = {},
            progressStyle = {}
        })
    elseif Config.Notify == "vorp-core" and VORPcore and VORPcore.NotifyRightTip then
        VORPcore.NotifyRightTip(message, notifyDuration)
    else
        print("^1[bcc-mailbox] Notify called with invalid Config.Notify: " .. tostring(Config.Notify))
    end
end

BccUtils.RPC:Register("bcc-mailbox:NotifyClient", function(data)
    if not data then return end
    Notify(data.message, data.type, data.duration)
end)
