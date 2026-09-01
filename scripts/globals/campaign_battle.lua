-----------------------------------
-- Campaign Battle System
-- Manages the lifecycle of Campaign Battles in Wings of the Goddess zones.
-- Handles spawning of fortifications, allied NPCs, and beastman attackers.
-----------------------------------
require('scripts/globals/campaign_battle_data')
-----------------------------------
xi = xi or {}
xi.campaignBattle = xi.campaignBattle or {}

-----------------------------------
-- Battle State Constants
-----------------------------------
xi.campaignBattle.state =
{
    IDLE       = 0, -- No battle active
    STARTING   = 1, -- Battle is initializing (spawning forts/NPCs)
    ACTIVE     = 2, -- Battle is in progress
    ENDING     = 3, -- Battle is wrapping up (despawning, tallying)
}

-----------------------------------
-- Per-zone runtime state (not persisted across server restarts)
-----------------------------------
local activeBattles = {} -- [zoneId] = battleInstance

-----------------------------------
-- Battle Instance Structure
-----------------------------------
local function createBattleInstance(zoneId)
    return {
        zoneId          = zoneId,
        state           = xi.campaignBattle.state.IDLE,
        startTime       = 0,
        fortifications  = {},  -- table of the fort's target-point MOB entity IDs
        alliedNpcs      = {},  -- table of spawned allied NPC entity IDs
        beastmanMobs    = {},  -- table of spawned beastman mob entity IDs
        waveCount       = 0,   -- current wave of beastman attackers
        maxWaves        = 3,   -- total waves before battle ends
        deadAllies      = 0,   -- count of allied NPCs killed
        deadBeastmen    = 0,   -- count of beastman mobs killed
        fortHp          = 0,   -- current fortification HP (aggregate, derived from live fort mobs)
        maxFortHp       = 0,   -- max fortification HP
        fortPoints      = 0,   -- fortification POINTS this battle was seeded with
        fortFromRegion  = false, -- true when fortPoints came from real region state (see spawnFortifications)
        fortsDestroyed  = 0,   -- count of the fort's target points destroyed
        fortAllegiance  = nil, -- who OWNS the forts this battle (xi.allegiance.MOB = beastman-held)
    }
end

-----------------------------------
-- Utility: Get zone data from campaign_battle_data
-----------------------------------
local function getZoneData(zoneId)
    return xi.campaignBattle.zoneData[zoneId]
end

-----------------------------------
-- Utility: Get the beastman faction for a zone
-- Returns the CampaignArmy index (3=Orc, 4=Quadav, 5=Yagudo, 6=Kindred)
-----------------------------------
local function getBeastmanFaction(zoneId)
    local data = getZoneData(zoneId)
    if data then
        return data.beastmanFaction
    end

    return xi.campaign.army.ORCISH -- default fallback
end

-----------------------------------
-- Utility: Get the controlling nation for a zone from campaign state
-- The GetCampaignStatus() returns campaignId (sequential 0-25), not zone IDs.
-- We maintain a mapping from zone ID to campaign ID.
-----------------------------------
local zoneToCampaignId =
{
    [80] = 0,  [81] = 1,  [82] = 2,  [83] = 3,  [84] = 4,  [85] = 5,
    [175] = 6, [87] = 7,  [88] = 8,  [89] = 9,  [90] = 10, [91] = 11,
    [92] = 12, [171] = 13,[94] = 14, [95] = 15, [96] = 16, [97] = 17,
    [98] = 18, [99] = 19, [164] = 20,[136] = 21,[137] = 22,[138] = 23,
    [155] = 24,[156] = 25,
}

-- Exposed so sibling campaign modules (e.g. campaign_ops) can map a zone id to
-- the campaignId that GetCampaignStatus() keys its rows by.
xi.campaignBattle.zoneToCampaignId = zoneToCampaignId

local function getZoneControlNation(zone)
    -- Returns: 2=Sandy, 4=Bastok, 6=Windy, 8=Beastmen
    local zoneId     = zone:getID()
    local campaignId = zoneToCampaignId[zoneId]

    if campaignId == nil then
        return xi.campaign.control.BEASTMEN
    end

    local status = GetCampaignStatus()
    if status then
        for _, z in ipairs(status) do
            if z.zoneId == campaignId then
                return z.nation
            end
        end
    end

    return xi.campaign.control.BEASTMEN
end

-----------------------------------
-- Fortification Spawning
-----------------------------------

-- A zone has ONE fort, presented as several attackable TARGET POINTS. Each target
-- point is a MOB so it can be attacked and has real HP, but they are inert
-- structures: they never move, never aggro, never attack, cast, or use abilities,
-- and award no exp or drops.
-- (On retail, Campaign kills give no exp/drops/crystals - only campaign points.)
-- The fort is razed when every one of its target points is destroyed.
-- Source: https://www.bg-wiki.com/ffxi/Campaign_Battle
--
-- HP SCALE: a fort's HP is derived from the region's fortification POINTS at
-- FORT_HP_PER_POINT HP each. Deriving HP from points (rather than a fraction of
-- some max) means damage converts straight back into fortification points when
-- the battle ends, and needs no max_fortifications value - which GetCampaignStatus()
-- does not currently expose to Lua.
local FORT_HP_PER_POINT = 20

-- Used only when the region reports 0 fortifications, so battles remain testable
-- while the fortification economy is unpopulated. A battle seeded this way does
-- NOT write its result back to the region (that would invent fortifications).
local FORT_BOOTSTRAP_POINTS = 100

-- A zone has ONE fort, and that fort presents several attackable TARGET POINTS
-- (retail: 4). Target points are placed at these {dx, dy, dz, rot?} offsets from
-- the fort's anchor position. dx/dz are the horizontal plane; dy is height.
-- Override per zone with data.fortTargetOffsets.
-- Source: https://www.bg-wiki.com/ffxi/Campaign_Battle
local FORT_DEFAULT_TARGET_OFFSETS =
{
    {  3.0, 0.0,  0.0 },
    { -3.0, 0.0,  0.0 },
    {  0.0, 0.0,  3.0 },
    {  0.0, 0.0, -3.0 },
}

-- Read a zone's current fortification points from live campaign state.
-- Returns nil when the zone is not part of the campaign map.
local function getZoneFortificationPoints(zone)
    local campaignId = zoneToCampaignId[zone:getID()]

    if campaignId == nil then
        return nil
    end

    local status = GetCampaignStatus()

    if status then
        for _, z in ipairs(status) do
            if z.zoneId == campaignId then
                return z.fort
            end
        end
    end

    return nil
end

-----------------------------------
-- External control / telemetry channel (ServerManager UI)
--
-- The map server has no HTTP surface, so the Python ServerManager talks to this
-- system through the DB-backed `server_variables` table. GetServerVariable()
-- does a fresh SELECT on every call (see serverutils::GetServerVar), so a row
-- written externally is picked up without any C++ change or rebuild.
--
--   CampaignBattleReq_<zoneId>  written BY the UI: 1 = start battle, 2 = end battle.
--                               Cleared back to 0 by onGameHour once handled.
--   CampaignFortHp_<zoneId>     written BY us: current aggregate fort HP (0 when idle).
--   CampaignFortMax_<zoneId>    written BY us: fort HP pool for the running battle.
--
-- Requests are polled in onGameHour, so a start takes effect within one
-- Vana'diel hour (144 real seconds).
-----------------------------------
xi.campaignBattle.request =
{
    NONE  = 0,
    START = 1,
    STOP  = 2,
}

local function battleRequestVar(zoneId)
    return string.format('CampaignBattleReq_%d', zoneId)
end

-- Publish fort health so the ServerManager UI can display it live.
local function publishFortHp(zoneId, hp, maxHp)
    SetServerVariable(string.format('CampaignFortHp_%d', zoneId), hp)
    SetServerVariable(string.format('CampaignFortMax_%d', zoneId), maxHp)
end

-- Sum the HP of every fortification still standing, refresh battle.fortHp, and
-- return it. The fort mobs' own HP is the single source of truth, so nothing has
-- to hook damage events to keep this accurate.
xi.campaignBattle.getFortificationHp = function(battle)
    local total = 0

    for _, entityId in ipairs(battle.fortifications) do
        local fort = GetMobByID(entityId)

        if fort ~= nil and fort:isAlive() then
            total = total + fort:getHP()
        end
    end

    battle.fortHp = total

    return total
end

-- Called when one of the fort's target points is destroyed.
xi.campaignBattle.onFortificationDestroyed = function(zone, battle)
    battle.fortsDestroyed = battle.fortsDestroyed + 1
    xi.campaignBattle.getFortificationHp(battle)

    printf('[CampaignBattle] Zone %d: Fort target point destroyed (%d/%d down, %d HP left)',
        zone:getID(), battle.fortsDestroyed, #battle.fortifications, battle.fortHp)

    publishFortHp(zone:getID(), battle.fortHp, battle.maxFortHp)

    xi.campaignBattle.checkBattleEnd(zone, battle)
end

-- Spawn the zone's fort as a set of attackable target points.
xi.campaignBattle.spawnFortifications = function(zone, battle)
    local zoneId = zone:getID()
    local data   = getZoneData(zoneId)

    if not data or (not data.fortPosition and not data.fortPositions) then
        printf('[CampaignBattle] No fortification data for zone %d', zoneId)
        return false
    end

    -- Seed the fort's HP from the region's real fortification value.
    local regionPoints = getZoneFortificationPoints(zone)

    if regionPoints ~= nil and regionPoints > 0 then
        battle.fortPoints     = regionPoints
        battle.fortFromRegion = true
    else
        battle.fortPoints     = data.defaultFortPoints or FORT_BOOTSTRAP_POINTS
        battle.fortFromRegion = false

        printf('[CampaignBattle] Zone %d reports %s fortifications; bootstrapping %d point(s). Result will NOT persist.',
            zoneId, tostring(regionPoints), battle.fortPoints)
    end

    -- A fort whose owner is the beastmen is attacked BY players (offensive battle).
    -- A fort owned by an allied nation is attacked BY beastmen (defensive battle).
    local control        = getZoneControlNation(zone)
    local fortAllegiance = control == xi.campaign.control.BEASTMEN and
        xi.allegiance.MOB or
        xi.allegiance.PLAYER

    -- ONE fort. Resolve its anchor, then place a target point at each offset.
    -- data.fortPositions[1] is accepted as the anchor so existing zone data works
    -- unchanged (every zone currently defines a single central outpost position).
    local anchor = data.fortPosition or data.fortPositions[1]

    if anchor == nil then
        printf('[CampaignBattle] Zone %d has fort data but no anchor position', zoneId)
        return false
    end

    local offsets = data.fortTargetOffsets or FORT_DEFAULT_TARGET_OFFSETS

    -- An empty offsets table would divide by zero below and yield infinite HP.
    if #offsets == 0 then
        printf('[CampaignBattle] Zone %d has an empty fortTargetOffsets; using defaults.', zoneId)
        offsets = FORT_DEFAULT_TARGET_OFFSETS
    end

    local targetPositions = {}

    for _, off in ipairs(offsets) do
        table.insert(targetPositions,
        {
            anchor[1] + (off[1] or 0),
            anchor[2] + (off[2] or 0),
            anchor[3] + (off[3] or 0),
            off[4] or anchor[4] or 0,
        })
    end

    -- The fort's HP pool is split evenly across its target points, so razing the
    -- whole fort costs the same damage regardless of how many points it presents.
    local pointCount = #targetPositions
    local hpPerPoint = math.max(1, math.floor(battle.fortPoints * FORT_HP_PER_POINT / pointCount))

    battle.fortAllegiance = fortAllegiance
    battle.maxFortHp      = hpPerPoint * pointCount
    battle.fortHp         = battle.maxFortHp

    for _, pos in ipairs(targetPositions) do
        local fort = zone:insertDynamicEntity({
            objtype              = xi.objType.MOB,
            allegiance           = fortAllegiance,
            name                 = 'Fortification',
            packetName           = 'Fortification',
            look                 = data.fortLook or 2702, -- Default fortification model
            x                    = pos[1],
            y                    = pos[2],
            z                    = pos[3],
            rotation             = pos[4] or 0,
            groupId              = data.fortGroupId or 1,
            groupZoneId          = xi.zone.GM_HOME,
            minLevel             = data.fortLevel or 75,
            maxLevel             = data.fortLevel or 75,
            releaseIdOnDisappear = true,
            isAggroable          = true, -- others may target it; it never aggros back

            onMobDeath = function(mobArg, playerArg, optParams)
                xi.campaignBattle.onFortificationDestroyed(zone, battle)
            end,
        })

        if fort then
            fort:setSpawn(pos[1], pos[2], pos[3], pos[4] or 0)
            fort:setRoamFlags(xi.roamFlag.SCRIPTED)
            fort:spawn()
            DisallowRespawn(fort:getID(), true)

            -- Inert structure: attackable, but takes no action of its own.
            fort:setAutoAttackEnabled(false)
            fort:setMagicCastingEnabled(false)
            fort:setMobAbilityEnabled(false)
            fort:setAggressive(false)
            fort:setMobMod(xi.mobMod.NO_MOVE, 1)
            fort:setMobMod(xi.mobMod.NO_AGGRO, 1)
            fort:setMobMod(xi.mobMod.NO_LINK, 1)
            fort:setMobMod(xi.mobMod.NO_REST, 1)  -- a damaged fort must not self-heal
            fort:setMobMod(xi.mobMod.NO_DROPS, 1)
            fort:setMobMod(xi.mobMod.EXP_BONUS, -100)

            -- HP must be set AFTER spawn(), which initialises stats from the pool.
            fort:setMaxHP(hpPerPoint)
            fort:setHP(hpPerPoint)

            table.insert(battle.fortifications, fort:getID())
        end
    end

    printf('[CampaignBattle] Zone %d: Fort spawned with %d target point(s), %d pts -> %d HP (%d HP each, allegiance %d)',
        zoneId, #battle.fortifications, battle.fortPoints, battle.maxFortHp, hpPerPoint, fortAllegiance)

    publishFortHp(zoneId, battle.fortHp, battle.maxFortHp)

    return true
end

-----------------------------------
-- Allied NPC Spawning
-----------------------------------

-- Spawn allied NPCs around the fortification based on the controlling nation.
-- These fight on the player's side against beastmen.
xi.campaignBattle.spawnAlliedNpcs = function(zone, battle)
    local zoneId  = zone:getID()
    local data    = getZoneData(zoneId)
    local control = getZoneControlNation(zone)

    if not data or not data.allySpawnPositions then
        printf('[CampaignBattle] No ally spawn data for zone %d', zoneId)
        return false
    end

    -- Get nation-specific ally info
    local allyData = xi.campaignBattle.getAllyDataForNation(control, zoneId)
    if not allyData then
        printf('[CampaignBattle] No ally data for nation %d in zone %d', control, zoneId)
        return false
    end

    local spawnCount = data.allyCount or 6

    for i = 1, math.min(spawnCount, #data.allySpawnPositions) do
        local pos  = data.allySpawnPositions[i]
        local look = allyData.looks[((i - 1) % #allyData.looks) + 1]

        local ally = zone:insertDynamicEntity({
            objtype               = xi.objType.MOB,
            allegiance            = xi.allegiance.PLAYER,
            name                  = allyData.name,
            packetName            = allyData.packetName or allyData.name,
            look                  = look,
            x                     = pos[1],
            y                     = pos[2],
            z                     = pos[3],
            rotation              = pos[4] or 0,
            groupId               = allyData.groupId or 1,
            groupZoneId           = xi.zone.GM_HOME,
            minLevel              = allyData.minLevel or 70,
            maxLevel              = allyData.maxLevel or 75,
            releaseIdOnDisappear  = true,
            specialSpawnAnimation = true,

            onMobDeath = function(mob, playerArg, optParams)
                battle.deadAllies = battle.deadAllies + 1
                xi.campaignBattle.checkBattleEnd(zone, battle)
            end,
        })

        if ally then
            ally:setSpawn(pos[1], pos[2], pos[3], pos[4] or 0)
            ally:setMobMod(xi.mobMod.NO_DROPS, 1)
            ally:setRoamFlags(xi.roamFlag.SCRIPTED)
            ally:spawn()
            DisallowRespawn(ally:getID(), true)
            ally:setAllegiance(1)

            table.insert(battle.alliedNpcs, ally:getID())
        end
    end

    printf('[CampaignBattle] Zone %d: Spawned %d allied NPC(s) for nation %d', zoneId, #battle.alliedNpcs, control)
    return true
end

-----------------------------------
-- Beastman Mob Spawning
-----------------------------------

-- Spawn a wave of beastman attackers targeting the fortification/allied NPCs.
xi.campaignBattle.spawnBeastmanWave = function(zone, battle)
    local zoneId  = zone:getID()
    local data    = getZoneData(zoneId)
    local faction = getBeastmanFaction(zoneId)

    if not data or not data.beastmanSpawnPositions then
        printf('[CampaignBattle] No beastman spawn data for zone %d', zoneId)
        return false
    end

    local mobData = xi.campaignBattle.getBeastmanDataForFaction(faction, zoneId)
    if not mobData then
        printf('[CampaignBattle] No beastman data for faction %d in zone %d', faction, zoneId)
        return false
    end

    battle.waveCount = battle.waveCount + 1
    local mobsPerWave = data.mobsPerWave or 4

    for i = 1, math.min(mobsPerWave, #data.beastmanSpawnPositions) do
        local pos  = data.beastmanSpawnPositions[i]
        local pool = mobData.pools[((i - 1) % #mobData.pools) + 1]

        local mob = zone:insertDynamicEntity({
            objtype               = xi.objType.MOB,
            allegiance            = xi.allegiance.MOB,
            name                  = pool.name,
            packetName            = pool.packetName or pool.name,
            look                  = pool.look,
            x                     = pos[1],
            y                     = pos[2],
            z                     = pos[3],
            rotation              = pos[4] or 0,
            groupId               = pool.groupId or 1,
            groupZoneId           = xi.zone.GM_HOME,
            minLevel              = pool.minLevel or 68,
            maxLevel              = pool.maxLevel or 73,
            releaseIdOnDisappear  = true,
            specialSpawnAnimation = true,
            isAggroable           = true,

            onMobDeath = function(mob, playerArg, optParams)
                battle.deadBeastmen = battle.deadBeastmen + 1
                xi.campaignBattle.checkWaveComplete(zone, battle)
            end,
        })

        if mob then
            mob:setSpawn(pos[1], pos[2], pos[3], pos[4] or 0)
            mob:setRoamFlags(xi.roamFlag.SCRIPTED)
            mob:spawn()
            DisallowRespawn(mob:getID(), true)

            table.insert(battle.beastmanMobs, mob:getID())
        end
    end

    printf('[CampaignBattle] Zone %d: Spawned wave %d/%d (%d beastmen)',
        zoneId, battle.waveCount, battle.maxWaves, #battle.beastmanMobs)
    return true
end

-----------------------------------
-- Battle Lifecycle
-----------------------------------

-- Start a Campaign Battle in the given zone.
-- Called by GM command or by the automatic campaign cycle timer.
xi.campaignBattle.startBattle = function(zoneId)
    local zone = GetZone(zoneId)
    if not zone then
        printf('[CampaignBattle] Invalid zone ID: %d', zoneId)
        return false
    end

    -- Check if battle is already active
    if activeBattles[zoneId] and activeBattles[zoneId].state ~= xi.campaignBattle.state.IDLE then
        printf('[CampaignBattle] Zone %d already has an active battle', zoneId)
        return false
    end

    local data = getZoneData(zoneId)
    if not data then
        printf('[CampaignBattle] No campaign battle data configured for zone %d', zoneId)
        return false
    end

    -- Create battle instance
    local battle = createBattleInstance(zoneId)
    battle.state     = xi.campaignBattle.state.STARTING
    battle.startTime = os.time()
    battle.maxWaves  = data.maxWaves or 3
    activeBattles[zoneId] = battle

    -- Set battle status flag on the campaign system (updates map UI)
    CampaignSetBattleStatus(zoneId, 1)

    -- Spawn fortifications
    xi.campaignBattle.spawnFortifications(zone, battle)

    -- Spawn allied NPCs
    xi.campaignBattle.spawnAlliedNpcs(zone, battle)

    -- Spawn first wave of beastmen
    xi.campaignBattle.spawnBeastmanWave(zone, battle)

    -- Transition to active
    battle.state = xi.campaignBattle.state.ACTIVE

    printf('[CampaignBattle] Battle STARTED in zone %d', zoneId)
    return true
end

-- End a Campaign Battle in the given zone.
-- Despawns all dynamic entities and resets state.
xi.campaignBattle.endBattle = function(zoneId)
    local battle = activeBattles[zoneId]
    if not battle then
        return false
    end

    local zone = GetZone(zoneId)
    if not zone then
        return false
    end

    battle.state = xi.campaignBattle.state.ENDING

    -- Persist this battle's fortification damage back to the region.
    -- Read HP BEFORE despawning, while the fort mobs still exist.
    -- CampaignSetFortification sets an ABSOLUTE value (the world server clamps it
    -- to 0..max_fortifications), so write the points still standing.
    if battle.fortFromRegion then
        local remainingHp     = xi.campaignBattle.getFortificationHp(battle)
        local remainingPoints = math.floor(remainingHp / FORT_HP_PER_POINT)

        CampaignSetFortification(zoneId, remainingPoints)

        printf('[CampaignBattle] Zone %d: Fortification %d -> %d points (%d HP left)',
            zoneId, battle.fortPoints, remainingPoints, remainingHp)
    else
        printf('[CampaignBattle] Zone %d: Fortification NOT persisted (battle was bootstrapped, not seeded from region).',
            zoneId)
    end

    -- Despawn all fortification mobs
    for _, entityId in ipairs(battle.fortifications) do
        DespawnMob(entityId, zone)
    end

    -- Clear published fort telemetry (no battle running)
    publishFortHp(zoneId, 0, 0)

    -- Despawn all allied NPCs (dynamic mobs with player allegiance)
    for _, entityId in ipairs(battle.alliedNpcs) do
        DespawnMob(entityId, zone)
    end

    -- Despawn all beastman mobs
    for _, entityId in ipairs(battle.beastmanMobs) do
        DespawnMob(entityId, zone)
    end

    -- Clear battle status on campaign system
    CampaignSetBattleStatus(zoneId, 0)

    -- Record cooldown timestamp
    zone:setLocalVar('CampaignBattle_LastEnd', os.time())

    -- Reset state
    activeBattles[zoneId] = nil

    printf('[CampaignBattle] Battle ENDED in zone %d', zoneId)
    return true
end

-----------------------------------
-- Wave / End Condition Checks
-----------------------------------

-- Called when a beastman mob dies. Checks if the wave is complete.
xi.campaignBattle.checkWaveComplete = function(zone, battle)
    local zoneId = zone:getID()

    -- Count remaining alive beastmen
    local alive = 0
    for _, entityId in ipairs(battle.beastmanMobs) do
        local mob = GetMobByID(entityId)
        if mob and mob:isAlive() then
            alive = alive + 1
        end
    end

    if alive <= 0 then
        -- Wave complete
        if battle.waveCount >= battle.maxWaves then
            -- All waves cleared - allies win
            printf('[CampaignBattle] Zone %d: All waves cleared! Allied victory.', zoneId)
            xi.campaignBattle.endBattle(zoneId)
        else
            -- Spawn next wave after a short delay using a fortification NPC as timer anchor
            printf('[CampaignBattle] Zone %d: Wave %d cleared, next wave incoming...', zoneId, battle.waveCount)

            -- Find a valid entity to attach the timer to (use first fort or surviving ally)
            -- Fortifications are MOBS, so they must be looked up with GetMobByID.
            local timerEntity = nil
            for _, entityId in ipairs(battle.fortifications) do
                local fort = GetMobByID(entityId)
                if fort then
                    timerEntity = fort
                    break
                end
            end

            if timerEntity then
                timerEntity:timer(15000, function(entityArg)
                    if activeBattles[zoneId] and activeBattles[zoneId].state == xi.campaignBattle.state.ACTIVE then
                        -- Clear dead mob references before spawning new wave
                        battle.beastmanMobs = {}
                        xi.campaignBattle.spawnBeastmanWave(zone, battle)
                    end
                end)
            else
                -- No timer anchor available, spawn immediately
                battle.beastmanMobs = {}
                xi.campaignBattle.spawnBeastmanWave(zone, battle)
            end
        end
    end
end

-- Called when an allied NPC dies, or when a fortification is destroyed.
-- Ends the battle if either side has lost its objective.
xi.campaignBattle.checkBattleEnd = function(zone, battle)
    local zoneId = zone:getID()

    -- All fortifications razed? Whoever was attacking them has won.
    if #battle.fortifications > 0 then
        local fortsAlive = 0

        for _, entityId in ipairs(battle.fortifications) do
            local fort = GetMobByID(entityId)

            if fort ~= nil and fort:isAlive() then
                fortsAlive = fortsAlive + 1
            end
        end

        if fortsAlive <= 0 then
            -- Beastman-held forts razed = allies won; allied forts razed = beastmen won.
            if battle.fortAllegiance == xi.allegiance.MOB then
                printf('[CampaignBattle] Zone %d: Beastman fortifications razed! Allied victory.', zoneId)
            else
                printf('[CampaignBattle] Zone %d: Allied fortifications razed! Beastman victory.', zoneId)
            end

            xi.campaignBattle.endBattle(zoneId)

            return
        end
    end

    -- Count remaining alive allies
    local alive = 0
    for _, entityId in ipairs(battle.alliedNpcs) do
        local mob = GetMobByID(entityId)
        if mob and mob:isAlive() then
            alive = alive + 1
        end
    end

    if alive <= 0 then
        -- All allies dead - beastmen win
        printf('[CampaignBattle] Zone %d: All allied NPCs defeated! Beastman victory.', zoneId)
        xi.campaignBattle.endBattle(zoneId)
    end
end

-----------------------------------
-- Query functions
-----------------------------------

-- Check if a zone currently has an active campaign battle
xi.campaignBattle.isBattleActive = function(zoneId)
    local battle = activeBattles[zoneId]
    return battle ~= nil and battle.state == xi.campaignBattle.state.ACTIVE
end

-- Get the active battle instance for a zone (or nil)
xi.campaignBattle.getBattle = function(zoneId)
    return activeBattles[zoneId]
end

-----------------------------------
-- Ally/Beastman Data Lookup
-----------------------------------

-- Get allied NPC data for a given controlling nation
xi.campaignBattle.getAllyDataForNation = function(nationControl, zoneId)
    local nationKey = nil

    if nationControl == xi.campaign.control.SANDORIA then
        nationKey = 'sandoria'
    elseif nationControl == xi.campaign.control.BASTOK then
        nationKey = 'bastok'
    elseif nationControl == xi.campaign.control.WINDURST then
        nationKey = 'windurst'
    end

    if not nationKey then
        return nil
    end

    -- Check zone-specific overrides first
    local data = getZoneData(zoneId)
    if data and data.allyOverrides and data.allyOverrides[nationKey] then
        return data.allyOverrides[nationKey]
    end

    -- Fall back to global defaults
    return xi.campaignBattle.allyDefaults[nationKey]
end

-- Get beastman mob data for a given faction
xi.campaignBattle.getBeastmanDataForFaction = function(faction, zoneId)
    local factionKey = nil

    if faction == xi.campaign.army.ORCISH then
        factionKey = 'orc'
    elseif faction == xi.campaign.army.QUADAV then
        factionKey = 'quadav'
    elseif faction == xi.campaign.army.YAGUDO then
        factionKey = 'yagudo'
    elseif faction == xi.campaign.army.KINDRED then
        factionKey = 'kindred'
    end

    if not factionKey then
        return nil
    end

    -- Check zone-specific overrides first
    local data = getZoneData(zoneId)
    if data and data.beastmanOverrides and data.beastmanOverrides[factionKey] then
        return data.beastmanOverrides[factionKey]
    end

    -- Fall back to global defaults
    return xi.campaignBattle.beastmanDefaults[factionKey]
end

-----------------------------------
-- Battle Lifecycle: Automatic Triggering
-- Called from zone onGameHour hooks to manage battle timing.
-----------------------------------

-- Configuration for automatic battle timing
xi.campaignBattle.config =
{
    -- How often battles can start (in Vana'diel hours between battles)
    BATTLE_COOLDOWN_HOURS = 8,

    -- Minimum duration of a battle (in real seconds) before it can auto-end
    MIN_BATTLE_DURATION = 300,

    -- Maximum duration of a battle (in real seconds) before forced end
    MAX_BATTLE_DURATION = 1800,

    -- Vana'diel hours at which battles can start (retail: roughly every 4-8 hours)
    BATTLE_START_HOURS = { 2, 6, 10, 14, 18, 22 },
}

-- Called from each campaign zone's onGameHour to check if a battle should start/end.
-- This provides automatic battle cycling without GM intervention.
xi.campaignBattle.onGameHour = function(zone)
    local zoneId = zone:getID()
    local data   = getZoneData(zoneId)

    -- Only zones with campaign battle data can have battles
    if not data then
        return
    end

    local hour   = VanadielHour()
    local battle = activeBattles[zoneId]

    -- External request from the ServerManager UI takes priority over the automatic
    -- cycle: it bypasses the cooldown, start-hour, and random-chance gates below.
    local requestVar = battleRequestVar(zoneId)
    local request    = GetServerVariable(requestVar)

    if request ~= xi.campaignBattle.request.NONE then
        -- Always clear first, so a request is consumed exactly once even if it fails.
        SetServerVariable(requestVar, xi.campaignBattle.request.NONE)

        if request == xi.campaignBattle.request.START then
            if battle then
                printf('[CampaignBattle] Zone %d: start requested but a battle is already active; ignoring.', zoneId)
            else
                printf('[CampaignBattle] Zone %d: start requested externally (ServerManager).', zoneId)
                xi.campaignBattle.startBattle(zoneId)

                return
            end
        elseif request == xi.campaignBattle.request.STOP then
            if battle then
                printf('[CampaignBattle] Zone %d: stop requested externally (ServerManager).', zoneId)
                xi.campaignBattle.endBattle(zoneId)
            else
                printf('[CampaignBattle] Zone %d: stop requested but no battle is active; ignoring.', zoneId)
            end

            return
        else
            printf('[CampaignBattle] Zone %d: unknown battle request value %d; ignoring.', zoneId, request)
        end
    end

    -- If battle is active, check for timeout
    if battle and battle.state == xi.campaignBattle.state.ACTIVE then
        local elapsed = os.time() - battle.startTime
        if elapsed >= xi.campaignBattle.config.MAX_BATTLE_DURATION then
            printf('[CampaignBattle] Zone %d: Battle timed out after %d seconds', zoneId, elapsed)
            xi.campaignBattle.endBattle(zoneId)
        end
        return
    end

    -- If no battle active, check if one should start
    if battle then
        return -- Still in STARTING or ENDING state
    end

    -- Check cooldown
    local lastBattleEnd = zone:getLocalVar('CampaignBattle_LastEnd')
    if lastBattleEnd > 0 then
        local cooldownRemaining = lastBattleEnd + (xi.campaignBattle.config.BATTLE_COOLDOWN_HOURS * 144) - os.time()
        if cooldownRemaining > 0 then
            return
        end
    end

    -- Check if current hour is a valid battle start hour
    local canStart = false
    for _, startHour in ipairs(xi.campaignBattle.config.BATTLE_START_HOURS) do
        if hour == startHour then
            canStart = true
            break
        end
    end

    if not canStart then
        return
    end

    -- Random chance to start (not every valid hour triggers a battle)
    -- Approximately 40% chance per valid hour, modified by beastman influence
    local chance = 40
    if math.random(1, 100) > chance then
        return
    end

    -- Start the battle
    printf('[CampaignBattle] Zone %d: Auto-starting battle at Vana\'diel hour %d', zoneId, hour)
    xi.campaignBattle.startBattle(zoneId)
end

-- Called when a battle ends to record the cooldown timestamp
-- (Already handled inside endBattle above via zone:setLocalVar)
