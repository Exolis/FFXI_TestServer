-----------------------------------
-- Campaign Battle Data
-- Per-zone configuration for Campaign Battle spawns.
-----------------------------------
require('scripts/globals/campaign')
-----------------------------------
xi = xi or {}
xi.campaignBattle = xi.campaignBattle or {}

-----------------------------------
-- Default Allied NPC Data (by nation)
-- Used when zones don't have specific overrides.
-----------------------------------
xi.campaignBattle.allyDefaults =
{
    sandoria =
    {
        name       = 'IronRamKnight',
        packetName = 'Iron Ram Knight',
        groupId    = 1,
        minLevel   = 70,
        maxLevel   = 75,
        looks      =
        {
            '0x010005011D1071201D301D401D50206130700000',
            '0x0100020841107120413041404150036130700000',
            '0x01000E04191019201930194019506B601C700000',
        },
    },

    bastok =
    {
        name       = 'FourthLegion',
        packetName = 'Fourth Legion',
        groupId    = 1,
        minLevel   = 70,
        maxLevel   = 75,
        looks      =
        {
            '0x01000C0133106420433064404350866086700000',
            '0x0100010216104120413041404150CA6000700000',
            '0x0100020260102420603060406050B56000700000',
        },
    },

    windurst =
    {
        name       = 'CobraUnit',
        packetName = 'Cobra Unit',
        groupId    = 1,
        minLevel   = 70,
        maxLevel   = 75,
        looks      =
        {
            '0x0100020600106320633063406350056122700000',
            '0x010004067C102D20193019401950506100700000',
            '0x0100080669106B206B306B406B50FE6000700000',
        },
    },
}

-----------------------------------
-- Default Beastman Data (by faction)
-- Used when zones don't have specific overrides.
-----------------------------------
xi.campaignBattle.beastmanDefaults =
{
    orc =
    {
        pools =
        {
            {
                name       = 'OrcishFighter',
                packetName = 'Orcish Fighter',
                look       = 1567, -- Orc melee model
                groupId    = 1,
                minLevel   = 68,
                maxLevel   = 73,
            },
            {
                name       = 'OrcishArcher',
                packetName = 'Orcish Archer',
                look       = 1568, -- Orc ranged model
                groupId    = 1,
                minLevel   = 68,
                maxLevel   = 73,
            },
        },
    },

    quadav =
    {
        pools =
        {
            {
                name       = 'QuadavGrnd',
                packetName = 'Quadav Grand',
                look       = 1634, -- Quadav melee model
                groupId    = 1,
                minLevel   = 68,
                maxLevel   = 73,
            },
            {
                name       = 'QuadavShaman',
                packetName = 'Quadav Shaman',
                look       = 1635, -- Quadav mage model
                groupId    = 1,
                minLevel   = 68,
                maxLevel   = 73,
            },
        },
    },

    yagudo =
    {
        pools =
        {
            {
                name       = 'YagudoZltr',
                packetName = 'Yagudo Zealot',
                look       = 1701, -- Yagudo melee model
                groupId    = 1,
                minLevel   = 68,
                maxLevel   = 73,
            },
            {
                name       = 'YagudoPrior',
                packetName = 'Yagudo Prior',
                look       = 1702, -- Yagudo mage model
                groupId    = 1,
                minLevel   = 68,
                maxLevel   = 73,
            },
        },
    },

    kindred =
    {
        pools =
        {
            {
                name       = 'DemonKnight',
                packetName = 'Demon Knight',
                look       = 1792, -- Demon melee model
                groupId    = 1,
                minLevel   = 70,
                maxLevel   = 75,
            },
            {
                name       = 'DemonWzrd',
                packetName = 'Demon Wizard',
                look       = 1793, -- Demon mage model
                groupId    = 1,
                minLevel   = 70,
                maxLevel   = 75,
            },
        },
    },
}

-----------------------------------
-- Per-Zone Campaign Battle Data
-- Each entry is keyed by zone ID.
--
-- Fields:
--   beastmanFaction       : CampaignArmy enum for this zone's beastman attacker
--   fortPosition          : {x, y, z, rot} anchor of the zone's ONE fort.
--                          (fortPositions[1] is still accepted as the anchor.)
--   fortTargetOffsets    : optional table of {dx, dy, dz, rot?} offsets from the anchor,
--                          one per attackable target point. Defaults to 4 points in a
--                          3-yalm cross around the anchor (retail forts have 4).
--                          The fort's HP pool is split evenly across these points.
--   fortLook             : model ID for the fortification mob
--   fortLevel            : level of the fortification mob (default 75)
--   fortGroupId          : mob group id used by insertDynamicEntity (default 1)
--   defaultFortPoints    : fortification points to use ONLY when the region reports 0
--                          (bootstrap for testing; such a battle does not persist its result)
--   maxFortHp            : DEPRECATED - fort HP is now derived from the region's
--                          fortification points (see FORT_HP_PER_POINT in campaign_battle.lua)
--   allySpawnPositions   : table of {x, y, z, rot} for allied NPC spawns
--   allyCount            : number of allied NPCs to spawn
--   beastmanSpawnPositions: table of {x, y, z, rot} for beastman mob spawns
--   mobsPerWave          : number of beastman mobs per wave
--   maxWaves             : number of waves before battle concludes
--   allyOverrides        : optional per-nation ally data overrides
--   beastmanOverrides    : optional per-faction beastman data overrides
-----------------------------------
xi.campaignBattle.zoneData =
{

    -----------------------------------
    -- East Ronfaure [S] (81) - San d'Oria Front
    -- Fort location: (H-8) per retail reference
    -----------------------------------
    [81] =
    {
        beastmanFaction = xi.campaign.army.ORCISH,
        maxWaves        = 3,
        mobsPerWave     = 4,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 5000,

        -- Fortification: central outpost position
        fortPositions =
        {
            { -21.0, -59.0, 237.0, 0 },
        },

        -- Allied NPCs: arranged near the fortification
        allySpawnPositions =
        {
            { -18.0, -59.0, 233.0, 128 },
            { -24.0, -59.0, 233.0, 128 },
            { -15.0, -59.0, 230.0, 128 },
            { -27.0, -59.0, 230.0, 128 },
            { -18.0, -59.0, 227.0, 128 },
            { -24.0, -59.0, 227.0, 128 },
        },

        -- Beastman spawn points: approaching from the south
        beastmanSpawnPositions =
        {
            { -15.0, -59.0, 260.0, 0 },
            { -21.0, -59.0, 263.0, 0 },
            { -27.0, -59.0, 260.0, 0 },
            { -21.0, -59.0, 266.0, 0 },
        },
    },

    -----------------------------------
    -- Jugner Forest [S] (82) - San d'Oria Front
    -- Fort location: (I-8)
    -----------------------------------
    [82] =
    {
        beastmanFaction = xi.campaign.army.ORCISH,
        maxWaves        = 3,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 5000,

        fortPositions =
        {
            { 185.0, -2.0, 62.0, 0 },
        },

        allySpawnPositions =
        {
            { 182.0, -2.0, 58.0, 128 },
            { 188.0, -2.0, 58.0, 128 },
            { 179.0, -2.0, 55.0, 128 },
            { 191.0, -2.0, 55.0, 128 },
            { 182.0, -2.0, 52.0, 128 },
            { 188.0, -2.0, 52.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 179.0, -2.0, 85.0, 0 },
            { 185.0, -2.0, 88.0, 0 },
            { 191.0, -2.0, 85.0, 0 },
            { 185.0, -2.0, 91.0, 0 },
            { 182.0, -2.0, 94.0, 0 },
        },
    },

    -----------------------------------
    -- Vunkerl Inlet [S] (83) - San d'Oria Front
    -- Fort location: (G-10)
    -----------------------------------
    [83] =
    {
        beastmanFaction = xi.campaign.army.ORCISH,
        maxWaves        = 3,
        mobsPerWave     = 4,
        allyCount       = 5,
        fortLook        = 2702,
        maxFortHp       = 4000,

        fortPositions =
        {
            { -260.0, -10.0, 300.0, 0 },
        },

        allySpawnPositions =
        {
            { -257.0, -10.0, 296.0, 128 },
            { -263.0, -10.0, 296.0, 128 },
            { -254.0, -10.0, 293.0, 128 },
            { -266.0, -10.0, 293.0, 128 },
            { -260.0, -10.0, 290.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { -254.0, -10.0, 320.0, 0 },
            { -260.0, -10.0, 323.0, 0 },
            { -266.0, -10.0, 320.0, 0 },
            { -260.0, -10.0, 326.0, 0 },
        },
    },

    -----------------------------------
    -- Batallia Downs [S] (84) - San d'Oria Front
    -- Fort location: (J-7)
    -----------------------------------
    [84] =
    {
        beastmanFaction = xi.campaign.army.ORCISH,
        maxWaves        = 4,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 6000,

        fortPositions =
        {
            { 300.0, -10.0, -150.0, 0 },
        },

        allySpawnPositions =
        {
            { 297.0, -10.0, -154.0, 128 },
            { 303.0, -10.0, -154.0, 128 },
            { 294.0, -10.0, -157.0, 128 },
            { 306.0, -10.0, -157.0, 128 },
            { 297.0, -10.0, -160.0, 128 },
            { 303.0, -10.0, -160.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 294.0, -10.0, -127.0, 0 },
            { 300.0, -10.0, -124.0, 0 },
            { 306.0, -10.0, -127.0, 0 },
            { 300.0, -10.0, -121.0, 0 },
            { 297.0, -10.0, -118.0, 0 },
        },
    },

    -----------------------------------
    -- North Gustaberg [S] (88) - Bastok Front
    -- Fort location: (D-10)
    -----------------------------------
    [88] =
    {
        beastmanFaction = xi.campaign.army.QUADAV,
        maxWaves        = 3,
        mobsPerWave     = 4,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 5000,

        fortPositions =
        {
            { -455.0, 20.0, 355.0, 0 },
        },

        allySpawnPositions =
        {
            { -452.0, 20.0, 351.0, 128 },
            { -458.0, 20.0, 351.0, 128 },
            { -449.0, 20.0, 348.0, 128 },
            { -461.0, 20.0, 348.0, 128 },
            { -452.0, 20.0, 345.0, 128 },
            { -458.0, 20.0, 345.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { -449.0, 20.0, 375.0, 0 },
            { -455.0, 20.0, 378.0, 0 },
            { -461.0, 20.0, 375.0, 0 },
            { -455.0, 20.0, 381.0, 0 },
        },
    },

    -----------------------------------
    -- Grauberg [S] (89) - Bastok Front
    -- Fort location: (I-8)
    -----------------------------------
    [89] =
    {
        beastmanFaction = xi.campaign.army.QUADAV,
        maxWaves        = 3,
        mobsPerWave     = 4,
        allyCount       = 5,
        fortLook        = 2702,
        maxFortHp       = 4000,

        fortPositions =
        {
            { 180.0, -30.0, 60.0, 0 },
        },

        allySpawnPositions =
        {
            { 177.0, -30.0, 56.0, 128 },
            { 183.0, -30.0, 56.0, 128 },
            { 174.0, -30.0, 53.0, 128 },
            { 186.0, -30.0, 53.0, 128 },
            { 180.0, -30.0, 50.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 174.0, -30.0, 80.0, 0 },
            { 180.0, -30.0, 83.0, 0 },
            { 186.0, -30.0, 80.0, 0 },
            { 180.0, -30.0, 86.0, 0 },
        },
    },

    -----------------------------------
    -- Pashhow Marshlands [S] (90) - Bastok Front
    -- Fort location: (K-6)
    -----------------------------------
    [90] =
    {
        beastmanFaction = xi.campaign.army.QUADAV,
        maxWaves        = 3,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 5000,

        fortPositions =
        {
            { 360.0, 24.0, -235.0, 0 },
        },

        allySpawnPositions =
        {
            { 357.0, 24.0, -239.0, 128 },
            { 363.0, 24.0, -239.0, 128 },
            { 354.0, 24.0, -242.0, 128 },
            { 366.0, 24.0, -242.0, 128 },
            { 357.0, 24.0, -245.0, 128 },
            { 363.0, 24.0, -245.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 354.0, 24.0, -215.0, 0 },
            { 360.0, 24.0, -212.0, 0 },
            { 366.0, 24.0, -215.0, 0 },
            { 360.0, 24.0, -209.0, 0 },
            { 357.0, 24.0, -206.0, 0 },
        },
    },

    -----------------------------------
    -- Rolanberry Fields [S] (91) - Bastok Front
    -- Fort location: (J-7)
    -----------------------------------
    [91] =
    {
        beastmanFaction = xi.campaign.army.QUADAV,
        maxWaves        = 4,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 6000,

        fortPositions =
        {
            { 270.0, -5.0, -180.0, 0 },
        },

        allySpawnPositions =
        {
            { 267.0, -5.0, -184.0, 128 },
            { 273.0, -5.0, -184.0, 128 },
            { 264.0, -5.0, -187.0, 128 },
            { 276.0, -5.0, -187.0, 128 },
            { 267.0, -5.0, -190.0, 128 },
            { 273.0, -5.0, -190.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 264.0, -5.0, -160.0, 0 },
            { 270.0, -5.0, -157.0, 0 },
            { 276.0, -5.0, -160.0, 0 },
            { 270.0, -5.0, -154.0, 0 },
            { 267.0, -5.0, -151.0, 0 },
        },
    },

    -----------------------------------
    -- West Sarutabaruta [S] (95) - Windurst Front
    -- Fort location: (H-6)
    -----------------------------------
    [95] =
    {
        beastmanFaction = xi.campaign.army.YAGUDO,
        maxWaves        = 3,
        mobsPerWave     = 4,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 5000,

        fortPositions =
        {
            { -60.0, -16.0, -240.0, 0 },
        },

        allySpawnPositions =
        {
            { -57.0, -16.0, -244.0, 128 },
            { -63.0, -16.0, -244.0, 128 },
            { -54.0, -16.0, -247.0, 128 },
            { -66.0, -16.0, -247.0, 128 },
            { -57.0, -16.0, -250.0, 128 },
            { -63.0, -16.0, -250.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { -54.0, -16.0, -220.0, 0 },
            { -60.0, -16.0, -217.0, 0 },
            { -66.0, -16.0, -220.0, 0 },
            { -60.0, -16.0, -214.0, 0 },
        },
    },

    -----------------------------------
    -- Fort Karugo-Narugo [S] (96) - Windurst Front
    -- Fort location: (H-8)
    -----------------------------------
    [96] =
    {
        beastmanFaction = xi.campaign.army.YAGUDO,
        maxWaves        = 3,
        mobsPerWave     = 4,
        allyCount       = 5,
        fortLook        = 2702,
        maxFortHp       = 4000,

        fortPositions =
        {
            { -20.0, 0.0, 60.0, 0 },
        },

        allySpawnPositions =
        {
            { -17.0, 0.0, 56.0, 128 },
            { -23.0, 0.0, 56.0, 128 },
            { -14.0, 0.0, 53.0, 128 },
            { -26.0, 0.0, 53.0, 128 },
            { -20.0, 0.0, 50.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { -14.0, 0.0, 80.0, 0 },
            { -20.0, 0.0, 83.0, 0 },
            { -26.0, 0.0, 80.0, 0 },
            { -20.0, 0.0, 86.0, 0 },
        },
    },

    -----------------------------------
    -- Meriphataud Mountains [S] (97) - Windurst Front
    -- Fort location: (E-5)
    -----------------------------------
    [97] =
    {
        beastmanFaction = xi.campaign.army.YAGUDO,
        maxWaves        = 3,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 5000,

        fortPositions =
        {
            { -380.0, -30.0, -280.0, 0 },
        },

        allySpawnPositions =
        {
            { -377.0, -30.0, -284.0, 128 },
            { -383.0, -30.0, -284.0, 128 },
            { -374.0, -30.0, -287.0, 128 },
            { -386.0, -30.0, -287.0, 128 },
            { -377.0, -30.0, -290.0, 128 },
            { -383.0, -30.0, -290.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { -374.0, -30.0, -260.0, 0 },
            { -380.0, -30.0, -257.0, 0 },
            { -386.0, -30.0, -260.0, 0 },
            { -380.0, -30.0, -254.0, 0 },
            { -377.0, -30.0, -251.0, 0 },
        },
    },

    -----------------------------------
    -- Sauromugue Champaign [S] (98) - Windurst Front
    -- Fort location: (H-7)
    -----------------------------------
    [98] =
    {
        beastmanFaction = xi.campaign.army.YAGUDO,
        maxWaves        = 4,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 6000,

        fortPositions =
        {
            { -20.0, -35.0, -190.0, 0 },
        },

        allySpawnPositions =
        {
            { -17.0, -35.0, -194.0, 128 },
            { -23.0, -35.0, -194.0, 128 },
            { -14.0, -35.0, -197.0, 128 },
            { -26.0, -35.0, -197.0, 128 },
            { -17.0, -35.0, -200.0, 128 },
            { -23.0, -35.0, -200.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { -14.0, -35.0, -170.0, 0 },
            { -20.0, -35.0, -167.0, 0 },
            { -26.0, -35.0, -170.0, 0 },
            { -20.0, -35.0, -164.0, 0 },
            { -17.0, -35.0, -161.0, 0 },
        },
    },

    -----------------------------------
    -- Beaucedine Glacier [S] (136) - Northlands
    -- Crossroads zone pressured by Kindred
    -----------------------------------
    [136] =
    {
        beastmanFaction = xi.campaign.army.KINDRED,
        maxWaves        = 4,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 6000,

        fortPositions =
        {
            { 0.0, -40.0, 0.0, 0 },
        },

        allySpawnPositions =
        {
            { 3.0, -40.0, -4.0, 128 },
            { -3.0, -40.0, -4.0, 128 },
            { 6.0, -40.0, -7.0, 128 },
            { -6.0, -40.0, -7.0, 128 },
            { 3.0, -40.0, -10.0, 128 },
            { -3.0, -40.0, -10.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 6.0, -40.0, 20.0, 0 },
            { 0.0, -40.0, 23.0, 0 },
            { -6.0, -40.0, 20.0, 0 },
            { 0.0, -40.0, 26.0, 0 },
            { 3.0, -40.0, 29.0, 0 },
        },
    },

    -----------------------------------
    -- Xarcabard [S] (137) - Northlands
    -----------------------------------
    [137] =
    {
        beastmanFaction = xi.campaign.army.KINDRED,
        maxWaves        = 4,
        mobsPerWave     = 5,
        allyCount       = 6,
        fortLook        = 2702,
        maxFortHp       = 6000,

        fortPositions =
        {
            { 50.0, -20.0, -100.0, 0 },
        },

        allySpawnPositions =
        {
            { 53.0, -20.0, -104.0, 128 },
            { 47.0, -20.0, -104.0, 128 },
            { 56.0, -20.0, -107.0, 128 },
            { 44.0, -20.0, -107.0, 128 },
            { 53.0, -20.0, -110.0, 128 },
            { 47.0, -20.0, -110.0, 128 },
        },

        beastmanSpawnPositions =
        {
            { 44.0, -20.0, -80.0, 0 },
            { 50.0, -20.0, -77.0, 0 },
            { 56.0, -20.0, -80.0, 0 },
            { 50.0, -20.0, -74.0, 0 },
            { 47.0, -20.0, -71.0, 0 },
        },
    },
}
