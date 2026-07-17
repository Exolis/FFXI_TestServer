/*
===========================================================================

  Copyright (c) 2023 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#pragma once

#include "world_engine.h"

#include "common/regional_event.h"

#include <array>
#include <vector>

// Zone adjacency entry
struct CampaignAdjacency
{
    uint8              zoneId;
    std::vector<uint8> neighbors;
    uint8              beastmanFaction; // Which beastman faction pressures this zone (3=Orc, 4=Quadav, 5=Yagudo, 6=Kindred)
    bool               isCity;         // Immune to control change
    bool               isStronghold;   // Beastman stronghold (immune for now)
};

class CampaignSystem
{
public:
    CampaignSystem(WorldEngine& worldServer);
    ~CampaignSystem() = default;

    bool handleMessage(uint8 messageType, IPPMessage&& message);

    // Called by time_server or GM command to run the tally (ownership resolution)
    void runTally();

    // Called by time_server or GM command to run a simulation tick (influence/fort/resource changes)
    void runUpdate();

    // Broadcast current state to all map servers
    void broadcastState();

private:
    // Load current state from DB
    void loadState();

    // Tally sub-steps
    void resolveZoneControl();
    void updateNationStats();

    // DB persistence
    void saveZoneState(const CampaignZoneState& zone);
    void saveNationState(uint8 nationId, const CampaignNationState& nation);

    // Helpers
    auto getAdjacency(uint8 zoneId) const -> const CampaignAdjacency*;
    auto getZoneState(uint8 zoneId) -> CampaignZoneState*;
    bool isControlledBy(uint8 zoneId, uint8 army) const;
    auto getInfluenceForArmy(const CampaignZoneState& zone, uint8 army) const -> uint8;
    void setInfluenceForArmy(CampaignZoneState& zone, uint8 army, uint8 value);
    auto getHighestInfluenceArmy(const CampaignZoneState& zone) const -> uint8;

    WorldEngine& worldServer_;

    // Cached state
    std::vector<CampaignZoneState>   zones_;
    std::vector<CampaignNationState> nations_;

    // Static adjacency data
    static const std::vector<CampaignAdjacency> adjacencyMap_;

    // Tuning parameters
    static constexpr uint8 INFLUENCE_DECAY_PERCENT = 5;
    static constexpr uint8 FLIP_THRESHOLD          = 50;
    static constexpr uint8 MAX_INFLUENCE           = 250;
};
