Config = Config or {}


--- VEHICLE OPTIONS (Best version of each car line - no duplicates)
Config.SpecFallbackVehicles = {
    -- Super Cars (Top Tier)
    { label = "Krieger",           model = "krieger"     },  -- Best all-rounder super
    { label = "Emerus",            model = "emerus"      },  -- Top lap time
    { label = "Deveste Eight",     model = "deveste"     },  -- Fastest top speed
    { label = "Vagner",            model = "vagner"      },  -- Best handling super
    { label = "Thrax",             model = "thrax"       },  -- Bugatti style
    { label = "Cyclone",           model = "cyclone"     },  -- Best acceleration (electric)
    { label = "Ignus",             model = "ignus"       },  -- The Contract DLC
    { label = "Zeno",              model = "zeno"        },  -- The Contract DLC
    { label = "Turismo Omaggio",   model = "turismo3"    },  -- Best Turismo version

    -- Los Santos Tuners (JDM/Street)
    { label = "Calico GTF",        model = "calico"      },  -- Fastest tuner
    { label = "Jester RR",         model = "jester4"     },  -- Best Jester version
    { label = "Vectre",            model = "vectre"      },  -- Great handling
    { label = "Comet S2",          model = "comet6"      },  -- Best Comet version
    { label = "Euros",             model = "euros"       },  -- 350Z style
    { label = "ZR350",             model = "zr350"       },  -- RX-7 style
    { label = "Cypher",            model = "cypher"      },  -- BMW M2 style
    { label = "Sultan RS Classic", model = "sultan3"     },  -- Best Sultan version
    { label = "Futo GTX",          model = "futo2"       },  -- Best Futo version

    -- Sports Cars (Top Performers)
    { label = "Pariah",            model = "pariah"      },  -- Fastest sports car
    { label = "Itali GTO",         model = "italigto"    },  -- Ferrari 812 style
    { label = "Neon",              model = "neon"        },  -- Tesla style (electric)
    { label = "Schlagen GT",       model = "schlagen"    },  -- AMG GT style

    -- Muscle (American Power)
    { label = "Dominator GT",      model = "dominator9"  },  -- Best Dominator version
    { label = "Gauntlet Hellfire", model = "gauntlet4"   },  -- Best Gauntlet version
    { label = "Buffalo STX",       model = "buffalo4"    },  -- Best Buffalo version

    -- Rally (Dirt/Mixed Surface)
    { label = "Omnis",             model = "omnis"       },  -- Lancia Delta style
    { label = "GB200",             model = "gb200"       },  -- Ford RS200 style
    { label = "Tropos Rallye",     model = "tropos"      },  -- Stratos style

    -- Vans (Best versions only)
    { label = "Youga Custom",      model = "youga4"      },  -- Best Youga version
    { label = "Speedo Custom",     model = "speedo5"     },  -- Best Speedo version
    { label = "Moonbeam Custom",   model = "moonbeam2"   },  -- Lowrider van
    { label = "Surfer Custom",     model = "surfer3"     },  -- Best VW bus style
    { label = "Paradise",          model = "paradise"    },  -- Hippie van

    -- Trucks (Best versions only)
    { label = "Yosemite 1500",     model = "yosemite1500"},  -- Best Yosemite version
    { label = "Sandking XL",       model = "sandking"    },  -- Lifted monster truck
    { label = "Kamacho",           model = "kamacho"     },  -- Jeep Gladiator style
    { label = "Riata",             model = "riata"       },  -- Ford Raptor style
    { label = "Contender",         model = "contender"   },  -- Sport utility truck
    { label = "Guardian",          model = "guardian"    },  -- Heavy duty truck

    -- Motorcycles - Sport Bikes (Best versions only)
    { label = "Hakuchou Drag",     model = "hakuchou2"   },  -- Fastest bike in game
    { label = "Bati 801RR",        model = "bati2"       },  -- Best Bati version
    { label = "Shinobi",           model = "shinobi"     },  -- The Contract DLC
    { label = "Reever",            model = "reever"      },  -- The Contract DLC
    { label = "Akuma",             model = "akuma"       },  -- Classic fast bike
    { label = "Double T",          model = "double"      },  -- Sport bike
    { label = "Carbon RS",         model = "carbonrs"    },  -- Ducati style
    { label = "PCJ-600",           model = "pcj"         },  -- Classic sport
    { label = "Nemesis",           model = "nemesis"     },  -- Lightweight sport
    { label = "Vindicator",        model = "vindicator"  },  -- Electric sport
    { label = "Thrust",            model = "thrust"      },  -- Sport bike
    { label = "Vortex",            model = "vortex"      },  -- Sport bike
    { label = "Ruffian",           model = "ruffian"     },  -- Naked bike

    -- Motorcycles - Cruisers/Choppers (Best versions only)
    { label = "Daemon Custom",     model = "daemon2"     },  -- Best Daemon version
    { label = "Hexer",             model = "hexer"       },  -- Classic chopper
    { label = "Nightblade",        model = "nightblade"  },  -- Cruiser
    { label = "Innovation",        model = "innovation"  },  -- Bobber style
    { label = "Wolfsbane",         model = "wolfsbane"   },  -- Chopper
    { label = "Gargoyle",          model = "gargoyle"    },  -- Rat chopper
    { label = "Avarus",            model = "avarus"      },  -- Classic chopper
    { label = "Zombie Chopper",    model = "zombieb"     },  -- Best Zombie version
    { label = "Sanctus",           model = "sanctus"     },  -- Skull chopper
    { label = "Diablous Custom",   model = "diablous2"   },  -- Best Diablous version

    -- Motorcycles - Dirt/Off-road (Best versions only)
    { label = "Manchez Scout",     model = "manchez3"    },  -- Best Manchez version
    { label = "BF400",             model = "bf400"       },  -- Dirt bike
    { label = "Enduro",            model = "enduro"      },  -- Enduro bike
    { label = "Cliffhanger",       model = "cliffhanger" },  -- Trials bike

    -- Motorcycles - Other
    { label = "Bagger",            model = "bagger"      },  -- Touring bike
    { label = "Sovereign",         model = "sovereign"   },  -- Police cruiser style
    { label = "FCR Custom",        model = "fcr2"        },  -- Best FCR version (scrambler)
    { label = "Chimera",           model = "chimera"     },  -- Trike
    { label = "Esskey",            model = "esskey"      },  -- Classic/vintage
    { label = "Powersurge",        model = "powersurge"  },  -- Electric bike
}


--- RACE CLASSES
Config.SpecPresets = {
    All = {
        label = "Open Class",
        description = "Any vehicle allowed",
        vehicles = nil,                -- nil = use full Config.RaceVehicles list
    },
    Super = {
        label = "Super Cars",
        description = "Top tier supercars only",
        vehicles = { "krieger", "emerus", "deveste", "vagner", "thrax", "cyclone", "ignus", "zeno", "turismo3" },
    },
    Tuner = {
        label = "Tuners / JDM",
        description = "Los Santos Tuners class",
        vehicles = { "calico", "jester4", "vectre", "comet6", "euros", "zr350", "cypher", "sultan3", "futo2" },
    },
    Muscle = {
        label = "Muscle Cars",
        description = "American muscle only",
        vehicles = { "dominator9", "gauntlet4", "buffalo4" },
    },
    Bikes = {
        label = "Motorcycles",
        description = "Two wheels only",
        vehicles = { "hakuchou2", "bati2", "shinobi", "reever", "akuma", "double", "carbonrs" },
    },
    Vans = {
        label = "Vans & Trucks",
        description = "Big vehicle chaos",
        vehicles = { "youga4", "speedo5", "moonbeam2", "surfer3", "yosemite1500", "sandking", "kamacho", "riata" },
    },
    Rally = {
        label = "Rally",
        description = "Dirt and mixed surface specialists",
        vehicles = { "omnis", "gb200", "tropos" },
    },
}


-- Open lobbies: host picks one of these; joiners must be in a vehicle of that class.
-- Numbers are GetVehicleClass() ids.
Config.OpenClasses = {
  Any      = { label = 'Any vehicle',   classes = nil },
  Super    = { label = 'Super',         classes = { [7] = true } },
  Sports   = { label = 'Sports',        classes = { [6] = true, [5] = true } },
  Muscle   = { label = 'Muscle',        classes = { [4] = true } },
  Offroad  = { label = 'Off-road',      classes = { [9] = true } },
  Bikes    = { label = 'Motorcycles',   classes = { [8] = true } },
}

-- Spec lobbies: the lobby-wide tune applied to every spawned car.
-- mods = { [modType] = index }, 'max' = highest available; toggles = { [modType] = bool }
Config.Tune = {
  Stock  = { label = 'Stock',  mods = {}, toggles = {} },
  Street = { label = 'Street', mods = { [11] = 2, [12] = 2, [13] = 2 }, toggles = {} },
  Race   = { label = 'Race',   mods = { [11] = 'max', [12] = 'max', [13] = 'max' }, toggles = { [18] = true } },
}
Config.TuneOrder = { 'Stock', 'Street', 'Race' }

-- Spec menu grouping: game class id -> label. Any registered vehicle whose class is
-- not listed falls under 'Other'.
Config.SpecClassLabels = {
  [0] = 'Compacts', [1] = 'Sedans', [2] = 'SUVs', [3] = 'Coupes', [4] = 'Muscle',
  [5] = 'Sports Classics', [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycles',
  [9] = 'Off-road', [12] = 'Vans', [22] = 'Open Wheel',
}
