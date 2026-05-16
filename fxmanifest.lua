fx_version 'cerulean'
game 'gta5'

author 'DrCannabis'
description '(Original Author Koala) Alternate version of max_rox_speedway edited by DrCannabis'

shared_scripts {
  '@ox_lib/init.lua',
  'config/config.lua',
  'locales/*.lua',           -- load your Lua locale modules
}

client_scripts {
  'client/c_fuel.lua',       -- add custom fuel script here
  'client/c_keys.lua',       -- centralized vehicle-keys support
  'client/c_customs.lua',    -- vehicle cosmetics & paints
  'client/c_function.lua',
  'client/c_main.lua',
  'client/c_pit.lua',        -- pitstop logic
  'leaderboard/cl_leaderboard.lua', -- in-world LED scoreboard (bundled AMIR)
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/sv_bridge.lua',            -- framework bridge (QBCore/QBX + ESX auto-detect)
  'server/s_main.lua',
  'leaderboard/sv_leaderboard.lua', -- leaderboard display logic + idle best-times
}

ui_page 'client/nui/timeout.html'

files {
  'locales/*.lua',
  'client/nui/timeout.html',
  'leaderboard/speedway.html',
  'leaderboard/LCDMB___.TTF',
  'leaderboard/ads/*.png',
}

-- Stream/map data for the physical LED sign (bundled from amir-leaderboard)
file 'stream/def_amir_speedway.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/def_amir_speedway.ytyp'
this_is_a_map 'yes'

dependencies {
    'ox_lib',
    'oxmysql',
    -- Optional: 'qb-core', 'qbx_core', or 'es_extended' (auto-detected; used for rewards, stats, plates)
    -- Optional: target system - 'ox_target' or 'qb-target' (configure in config.lua)
}

lua54 'yes'
