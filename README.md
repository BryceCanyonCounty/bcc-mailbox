# bcc-mailbox

# Description

This script implements an in-game mailbox system for RedM servers, allowing players to send and receive messages through mailboxes. Mailboxes can be placed at customizable locations, and players can register their mailboxes and communicate with others.

# Features
- Players can register and manage their mailboxes.
- Send and receive messages in-game via mailboxes.
- Customizable mailbox locations.
- Optional pigeon animation when sending messages.
- Fully integrated with VORP and FeatherMenu.
- Customizable fees for registration and sending messages.

# Dependencies
- [vorp_core](https://github.com/VORPCORE/vorp-core-lua)
- [vorp_inventory](https://github.com/VORPCORE/vorp_inventory-lua)
- [vorp_character](https://github.com/VORPCORE/vorp_character-lua)
- [feather-menu](https://github.com/feather-framework/feather-menu)
- [bcc-utils](https://github.com/BryceCanyonCounty/bcc-utils)
- [oxmysql](https://github.com/overextended/oxmysql)

# Installation
1. Add the `bcc-mailbox` folder to your server's `resources` directory.
2. Add `ensure bcc-mailbox` to your `server.cfg`.
3. Ensure all dependencies (VORP, oxmysql, feather-menu, etc.) are correctly installed.
4. Customize mailbox settings by editing the `config.lua` file.
5. The database setup is automatic, no manual database work is needed.
6. Restart the server.

# Usage
- **Register Mailbox**: Players can register a mailbox by using the specified item and paying the registration fee.
- **Send/Receive Messages**: Players can send and receive messages at mailbox locations.


# Side Notes
- Need more help? Join the bcc discord here: https://discord.gg/VrZEEpBgZJ