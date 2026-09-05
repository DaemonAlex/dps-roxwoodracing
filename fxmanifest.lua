fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-roxwoodracing'
author 'DPS Development (base: max_rox_speedway by MaxSuperTech, rox_speedway by DrCannabis/DaemonAlex)'
description 'Roxwood Raceway: lobbies, Spec and Open races, pit crews, LED leaderboard, society-funded purses'
version '3.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config/*.lua',
  'locales/en.lua',
  'shared/*.lua',
  'bridge/init.lua',
}

client_scripts {
  'bridge/client.lua',
  'integrations/notify.lua',
  'integrations/target.lua',
  'integrations/keys.lua',
  'integrations/fuel.lua',
  'integrations/bossmenu.lua',
  'client/util.lua',
  'client/customs.lua',
  'client/hud.lua',
  'client/ghost.lua',
  'client/main.lua',
  'client/pit.lua',
  'client/leaderboard.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'bridge/server.lua',
  'integrations/banking.lua',
  'integrations/garages.lua',
  'integrations/bossmenu.lua',
  'server/stats.lua',
  'server/rewards.lua',
  'server/lobbies.lua',
  'server/race.lua',
  'server/staff.lua',
  'server/leaderboard.lua',
}

ui_page 'html/index.html'

files {
  'locales/en.lua',
  'html/index.html',
  'html/led.html',
  'html/LCDMB___.TTF',
  'html/ads/*.png',
}

file 'stream/def_amir_speedway.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/def_amir_speedway.ytyp'
this_is_a_map 'yes'

dependencies { 'ox_lib', 'oxmysql' }
