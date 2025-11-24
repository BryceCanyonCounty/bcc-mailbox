fx_version "adamant"
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game "rdr3"

lua54 'yes'
author 'BCC Team'

description 'In-game MailBox System'

shared_scripts {
  'config.lua',
  'shared/locale.lua',
  'languages/*.lua'
}

client_scripts {
  'client/client.lua',
  'client/controllers/*.lua',
  'client/services/*.lua',
  'client/menus/*.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/API.lua',
  'server/controllers.lua',
  'server/helpers.lua',
  'server/dbUpdater.lua',
  'server/server.lua',
}

dependency {
	'vorp_core',
	'vorp_character',
	'vorp_inventory',
  'oxmysql',
	'feather-menu',
	'bcc-utils'
}

version '1.1.0'
