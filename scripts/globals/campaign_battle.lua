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
        fortifications  = {},  -- table of spawned fortification NPC entity IDs
        alliedNpcs      = {},  -- table of spawned allied NPC entity IDs
        beastmanMobs    = {},  -- table of spawned beastman mob entity IDs
        waveCount       = 0,   -- current wave of beastman attackers
        maxWaves        = 3,   -- total waves before battle ends
        deadAllies      = 0,   -- count of allied NPCs killed
        deadBeastmen    = 0,   -- count of beastman mobs killed
        fortHp          = 0,   -- current fortification HP (aggregate)
        maxFortHp       = 0,   -- max fortification HP
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

-- Spawn fortification NPCs at the zone's outpost location.
-- These are targetable NPC entities that represent the physical fort.
xi.campaignBattle.spawnFortifications = function(zone, battle)
    local zoneId = zone:getID()
    local data   = getZoneData(zoneId)

    if not data or not data.fortPositions then
        printf('[CampaignBattle] No fortification data for zone %d', zoneId)
        return false
    end

    for i, pos in ipairs(data.fortPositions) do
        local fort = zone:insertDynamicEntity({
            objtype              = xi.objType.NPC,
            name                 = 'Fortification',
            packetName           = 'Fortification',
            look                 = data.fortLook or 2702, -- Default fortification model
            x                    = pos[1],
            y                    = pos[2],
            z                    = pos[3],
            rotation             = pos[4] or 0,
            releaseIdOnDisappear = true,
            entityFlags          = 0x0000,

            onTrigger = function(player, npc)
                -- Players can interact to check fortification status
                player:printToPlayer(string.format(
                    'Fortification HP: %d/%d',
                    battle.fortHp,
                    battle.maxFortHp
                ))
            end,
        })

        if fort then
            fort:setStatus(xi.status.NORMAL)
            table.insert(battle.fortifications, fort:getID())
        end
    end

    -- Set initial fortification HP based on the zone's current fortification value
    battle.maxFortHp = data.maxFortHp or 5000
    battle.fortHp    = battle.maxFortHp

    printf('[CampaignBattle] Zone %d: Spawned %d fortification(s)', zoneId, #battle.fortifications)
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

    -- Despawn all fortification NPCs
    for _, entityId in ipairs(battle.fortifications) do
        local entity = GetNPCByID(entityId)
        if entity then
            entity:setStatus(xi.status.DISAPPEAR)
        end
    end

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
            local timerEntity = nil
            for _, entityId in ipairs(battle.fortifications) do
                local npc = GetNPCByID(entityId)
                if npc then
                    timerEntity = npc
                    break
                end
            end

            if timerEntity then
                timerEntity:timer(15000, function(npcArg)
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

-- Called when an allied NPC dies. Checks if all allies are dead (battle lost).
xi.campaignBattle.checkBattleEnd = function(zone, battle)
    local zoneId = zone:getID()

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
