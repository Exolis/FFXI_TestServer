---
inclusion: fileMatch
fileMatchPattern: "scripts/**/*.lua"
---

# Lua Script Patterns for FFXI Server

## NPC Entity Script Template
```lua
-----------------------------------
-- Area: Zone_Name
--  NPC: NPC_Name
-- Type: Description
-- !pos x y z zoneId
-----------------------------------
local ID = zones[xi.zone.ZONE_CONSTANT]
-----------------------------------
---@type TNpcEntity
local entity = {}

entity.onTrade = function(player, npc, trade)
end

entity.onTrigger = function(player, npc)
end

entity.onEventUpdate = function(player, csid, option, npc)
end

entity.onEventFinish = function(player, csid, option, npc)
end

return entity
```

## Zone Script Template
```lua
-----------------------------------
-- Zone: Zone_Name (zoneId)
-----------------------------------
local ID = zones[xi.zone.ZONE_CONSTANT]
-----------------------------------
---@type TZone
local zoneObject = {}

zoneObject.onInitialize = function(zone)
end

zoneObject.onGameHour = function(zone)
end

zoneObject.onZoneIn = function(player, prevZone)
    return -1
end

zoneObject.onTriggerAreaEnter = function(player, triggerArea)
end

zoneObject.onEventUpdate = function(player, csid, option, npc)
end

zoneObject.onEventFinish = function(player, csid, option, npc)
end

return zoneObject
```

## Dynamic Entity Spawning (Mobs)
```lua
local mob = zone:insertDynamicEntity({
    objtype               = xi.objType.MOB,
    allegiance            = xi.allegiance.PLAYER, -- or xi.allegiance.MOB
    name                  = 'InternalName',
    packetName            = 'Display Name',
    look                  = 'lookString' or modelId,
    x                     = pos_x,
    y                     = pos_y,
    z                     = pos_z,
    rotation              = rot,
    groupId               = groupId,
    groupZoneId           = xi.zone.GM_HOME,
    minLevel              = minLvl,
    maxLevel              = maxLvl,
    releaseIdOnDisappear  = true,
    specialSpawnAnimation = true,
    isAggroable           = false,

    onMobDeath = function(mob, playerArg, optParams)
    end,
})

mob:setSpawn(x, y, z, rot)
mob:setRoamFlags(xi.roamFlag.SCRIPTED)
mob:spawn()
DisallowRespawn(mob:getID(), true)
```

## Dynamic Entity Spawning (NPCs)
```lua
local npc = zone:insertDynamicEntity({
    objtype              = xi.objType.NPC,
    name                 = 'InternalName',
    packetName           = 'Display Name',
    look                 = modelId,
    x                    = pos_x,
    y                    = pos_y,
    z                    = pos_z,
    rotation             = rot,
    releaseIdOnDisappear = true,

    onTrigger = function(player, npc)
    end,
})
npc:setStatus(xi.status.NORMAL)
```

## Item Trade Checking
```lua
-- Single item with quantity
if npcUtil.tradeHasExactly(trade, { { xi.item.ITEM_ID, quantity } }) then
    player:tradeComplete()
end

-- Gil trade
if npcUtil.tradeHasExactly(trade, { { 'gil', amount } }) then
    player:tradeComplete()
end
```

## Timer/Delayed Execution
```lua
-- entity:timer(delayMs, callback) - works on any entity (NPC, mob, player)
entity:timer(15000, function(entityArg)
    -- runs after 15 seconds
end)
```

## Despawning Dynamic Entities
```lua
-- Mobs
DespawnMob(entityId, zone)

-- NPCs
entity:setStatus(xi.status.DISAPPEAR)
```

## Campaign System Lua API
```lua
CampaignSetBattleStatus(zoneId, 0 or 1)
CampaignSetFortification(zoneId, amount)
CampaignSetInfluence(zoneId, army, amount)
CampaignSetZoneControl(zoneId, nation)
CampaignTally()
CampaignUpdate()
CampaignRefresh()
GetCampaignStatus() -- returns table of zone states
```
