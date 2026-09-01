# FFXI Server Development Skill

## Description
Assists with developing content for this LandSandBoat-based FFXI private server. Covers Lua scripting for game content (NPCs, quests, zones, mobs), C++ server infrastructure, SQL data management, and the custom Campaign system.

## Capabilities

### Lua Content Development
- Write NPC scripts, mob scripts, zone scripts following LSB patterns
- Implement quests using the interaction framework (sections, check functions, onTrade/onTrigger handlers)
- Create dynamic entity spawning systems (Campaign Battles, Garrison-style events)
- Work with the campaign system APIs (battles, ops, influence, fortifications)
- Use npcUtil helpers for trades, item giving, key items, currency

### C++ Server Development
- Extend the map server (campaign handlers, packet processing, IPC messaging)
- Extend the world server (campaign tally, influence resolution, broadcasting)
- Add Lua bindings via luautils.cpp (set_function pattern)
- Follow Allman brace style, WebKit-based formatting, proper casting

### SQL & Database
- Modify campaign_map, campaign_nation tables
- Work with char_points for currency (allied_notes, op_credits)
- Follow SQL commenting standards for readability
- Create migration scripts for schema changes

### Build & Operations
- CMake build system configuration
- Git workflow: fetch upstream, merge, resolve conflicts
- Module system for non-invasive customization

## Key Files Reference

| Purpose | Location |
|---------|----------|
| Campaign Battle system | `scripts/globals/campaign_battle.lua` |
| Campaign Battle data | `scripts/globals/campaign_battle_data.lua` |
| Campaign Ops system | `scripts/globals/campaign_ops.lua` |
| Campaign Ops data | `scripts/globals/campaign_ops_data.lua` |
| Campaign globals | `scripts/globals/campaign.lua` |
| Campaign GM command | `scripts/commands/campaign.lua` |
| C++ map campaign | `src/map/campaign_system.cpp/.h` |
| C++ world campaign | `src/world/campaign_system.cpp/.h` |
| Campaign handler | `src/map/campaign_handler.cpp/.h` |
| IPC message defs | `src/common/regional_event.h` |
| Zone IDs example | `scripts/zones/East_Ronfaure_[S]/IDs.lua` |
| Garrison (reference) | `scripts/globals/garrison.lua` |
| Dominion Ops (reference) | `scripts/globals/abyssea/dominion.lua` |
| Interaction framework | `documentation/interaction-framework.md` |
| Campaign todo/notes | `TodoList.md` |

## Conventions

- Dynamic mobs use groupId=1 with groupZoneId=xi.zone.GM_HOME
- Allied NPCs: allegiance=xi.allegiance.PLAYER, type=xi.objType.MOB
- Fortification NPCs: type=xi.objType.NPC with onTrigger for status
- Campaign zone IDs: 80-99 (WotG field zones), 136-156 (Northlands)
- Nation control values: 2=Sandy, 4=Bastok, 6=Windy, 8=Beastmen
- Army enum: 0=Sandy, 1=Bastok, 2=Windy, 3=Orc, 4=Quadav, 5=Yagudo, 6=Kindred
- Op IDs: 1000-1099=Bastok, 2000-2099=Sandy, 3000-3099=Windy
- CharVars for player state, ServerVariables for global state, zone:setLocalVar for zone state
