---
inclusion: auto
---

# LandSandBoat FFXI Private Server - Project Steering

## Project Overview

This is a custom FFXI private server based on the [LandSandBoat](https://github.com/LandSandBoat/server) open-source project. It emulates a Final Fantasy XI server with custom Campaign Battle and Campaign Ops systems built on top of the LSB infrastructure.

## Architecture

- **C++ Core** (`src/`): Game server logic (map server, world server, login server)
- **Lua Scripts** (`scripts/`): Game content (quests, NPCs, mobs, zones, globals)
- **SQL** (`sql/`): Database schema and initial data
- **CMake** build system with presets defined in `CMakePresets.json`

## Key Custom Systems

- `scripts/globals/campaign_battle.lua` + `campaign_battle_data.lua` - Campaign Battle spawning framework
- `scripts/globals/campaign_ops.lua` + `campaign_ops_data.lua` - Campaign Operations system
- `src/world/campaign_system.cpp` - World server campaign tally/influence/IPC
- `src/map/campaign_system.cpp` - Map server campaign state management
- `src/map/campaign_handler.cpp` - Per-zone campaign handler

## Git Workflow

- `origin` = `Exolis/FFXI_TestServer` (our fork)
- `upstream` = `LandSandBoat/server` (upstream source)
- To merge upstream updates: `git fetch upstream` then `git merge upstream/base`
- Always commit custom work before merging upstream
- Never push to upstream

## Reference Documentation

- Campaign system todo: #[[file:TodoList.md]]
- Interaction framework: #[[file:documentation/interaction-framework.md]]
