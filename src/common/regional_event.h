/*
===========================================================================

  Copyright (c) 2025 LandSandBoat Dev Teams

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

#include "cbasetypes.h"

#include "map/conquest_data.h"

//
// Conquest
//

enum ConquestMessage : uint8
{
    // World map broadcasts weekly update started to all zones
    W2M_WeeklyUpdateStart,

    // World map broadcasts that update is done, with the respective tally
    W2M_WeeklyUpdateEnd,

    // World map broadcasts influence point updates to all zones.
    // Used for periodic updates or initialization.
    W2M_BroadcastInfluencePoints,

    // World map broadcasts region control data to all zones.
    // Used for initialization.
    W2M_BroadcastRegionControls,

    // A GM Triggers a weekly update.
    // World should send W2M_WeeklyUpdateStart and
    // W2M_WeeklyUpdateEnd to all zones when done.
    M2W_GM_WeeklyUpdate,

    // A GM requests hourly conquest data (just influence points).
    // World server should send W2M_BroadcastInfluencePoints to all zones.
    M2W_GM_ConquestUpdate,

    // Influence point update from any zone to world.
    M2W_AddInfluencePoints,
};

DECLARE_FORMAT_AS_UNDERLYING(ConquestMessage);

// W2M_BroadcastInfluencePoints
struct ConquestInfluenceUpdate
{
    bool                     shouldUpdateZones;
    std::vector<influence_t> influences;
};

// W2M_BroadcastRegionControls
struct ConquestRegionControlUpdate
{
    std::vector<region_control_t> regionControls;
};

// M2W_AddInfluencePoints
struct ConquestAddInfluencePoints
{
    int32  points;
    uint32 nation;
    uint8  region;
};

//
// Besieged
//

enum BesiegedMessage : uint8
{
};

DECLARE_FORMAT_AS_UNDERLYING(BesiegedMessage);

//
// Campaign
//

enum CampaignMessage : uint8
{
    // World broadcasts full campaign state to all map servers.
    Campaign_W2M_BroadcastState,

    // World broadcasts that a tally has completed with updated zone controls.
    Campaign_W2M_TallyComplete,

    // A GM triggers a campaign tally from a map server (ownership resolution).
    Campaign_M2W_GM_Tally,

    // A GM triggers a campaign update from a map server (influence/fort/resource simulation tick).
    Campaign_M2W_GM_Update,

    // A GM requests a state broadcast to all map servers (no simulation, just refresh).
    Campaign_M2W_GM_Refresh,

    // A map server sends an influence change to the world server.
    Campaign_M2W_AddInfluence,

    // A map server sends a fortification change to the world server.
    Campaign_M2W_SetFortification,

    // A map server sends a zone control change to the world server.
    Campaign_M2W_SetZoneControl,

    // A map server sends a battle status change to the world server.
    Campaign_M2W_SetBattleStatus,
};

DECLARE_FORMAT_AS_UNDERLYING(CampaignMessage);

// Per-zone campaign data sent in broadcasts
struct CampaignZoneState
{
    uint8  campaignId            = 0;
    uint8  zoneId                = 0;
    uint8  battleStatus          = 0;
    uint8  controllingNation     = 0;
    uint8  heroism               = 0;
    uint8  influenceSandoria     = 0;
    uint8  influenceBastok       = 0;
    uint8  influenceWindurst     = 0;
    uint8  influenceBeastman     = 0;
    uint16 currentFortifications = 0;
    uint16 currentResources      = 0;
    uint16 maxFortifications     = 0;
    uint16 maxResources          = 0;
};

// Per-nation campaign stats sent in broadcasts
struct CampaignNationState
{
    uint8 reconnaissance = 0;
    uint8 morale         = 0;
    uint8 prosperity     = 0;
};

// Campaign_W2M_BroadcastState / Campaign_W2M_TallyComplete
struct CampaignFullState
{
    std::vector<CampaignZoneState>   zones;
    std::vector<CampaignNationState> nations;
};

// Campaign_M2W_AddInfluence
struct CampaignAddInfluence
{
    uint8 zoneId = 0;
    uint8 army   = 0; // CampaignArmy enum value
    int16 amount = 0;
};

// Campaign_M2W_SetFortification
struct CampaignSetFortification
{
    uint8 zoneId = 0;
    int16 amount = 0;
};

// Campaign_M2W_SetZoneControl
struct CampaignSetZoneControl
{
    uint8 zoneId = 0;
    uint8 nation = 0;
};

// Campaign_M2W_SetBattleStatus
struct CampaignSetBattleStatus
{
    uint8 zoneId = 0;
    uint8 status = 0;
};

//
// Colonization
//

enum ColonizationMessage : uint8
{
};

DECLARE_FORMAT_AS_UNDERLYING(ColonizationMessage);
