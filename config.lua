Config = {
    -- Language settings
    defaultlang = "en_lang", -- Set Your Language (Current Languages: "en_lang" English, "ro_lang" Romanian)
    RegistrationFee = 10,     -- Cost to register
    SendMessageFee = 15,     --Cost to send messages
    TimePerMile = 0.1,       -- Time in seconds per mile
    SendPigeon = false,       -- If you want the Pigeon or not

    devMode = false,
    MailboxItem = "letter", -- Name of the item to use for opening the mailbox
    MailboxLocations = {
        { name = "Annesburg",   coords = vector3(2939.24, 1286.93, 44.65) },
        { name = "Armadillo",   coords = vector3(-3732.36, -2597.82, -12.94) },
        { name = "Blackwater",  coords = vector3(-874.91, -1328.74, 43.96) },
        { name = "Rhodes",      coords = vector3(1225.58, -1293.97, 76.91) },
        { name = "Saint Denis", coords = vector3(2731.46, -1402.37, 46.18) },
        { name = "Strawberry",  coords = vector3(-1765.2, -384.26, 157.74) },
        { name = "Valentine",   coords = vector3(-177.97, 628.17, 114.09) },
    },
}
