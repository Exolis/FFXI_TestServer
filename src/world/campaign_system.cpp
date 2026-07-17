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

#include "campaign_system.h"

#include "ipc_server.h"

#include "common/database.h"
#include "common/ipp.h"

// ============================================================================
// Zone Adjacency Map
// ============================================================================
// Each entry defines a zone, its neighbors, which beastman faction pressures it,
// and whether it's a city or stronghold (immune to control change).
//
// Nation control values in DB:
//   2 = San d'Oria, 4 = Bastok, 6 = Windurst, 8 = Beastman
//
// CampaignArmy enum:
//   0 = Sandoria, 1 = Bastok, 2 = Windurst, 3 = Orcish, 4 = Quadav, 5 = Yagudo, 6 = Kindred

// clang-format off
const std::vector<CampaignAdjacency> CampaignSystem::adjacencyMap_ =
{
    // San d'Oria Front
    { 80,  { 81 },              3, true,  false }, // Southern San d'Oria [S] (city)
    { 81,  { 80, 82 },         3, false, false }, // East Ronfaure [S]
    { 82,  { 81, 83, 84, 136 }, 3, false, false }, // Jugner Forest [S]
    { 83,  { 82 },             3, false, false }, // Vunkerl Inlet [S]
    { 84,  { 82, 85, 175 },    3, false, false }, // Batallia Downs [S]
    { 85,  { 84 },             3, false, true  }, // La Vaule [S] (Orc stronghold)

    // Bastok Front
    { 87,  { 88 },              4, true,  false }, // Bastok Markets [S] (city)
    { 88,  { 87, 89, 90 },     4, false, false }, // North Gustaberg [S]
    { 89,  { 88 },             4, false, false }, // Grauberg [S]
    { 90,  { 88, 91, 171, 136 }, 4, false, false }, // Pashhow Marshlands [S]
    { 91,  { 90, 92 },         4, false, false }, // Rolanberry Fields [S]
    { 92,  { 91 },             4, false, true  }, // Beadeaux [S] (Quadav stronghold)

    // Windurst Front
    { 94,  { 95 },              5, true,  false }, // Windurst Waters [S] (city)
    { 95,  { 94, 96, 97 },     5, false, false }, // West Sarutabaruta [S]
    { 96,  { 95 },             5, false, false }, // Fort Karugo-Narugo [S]
    { 97,  { 95, 98, 164, 136 }, 5, false, false }, // Meriphataud Mountains [S]
    { 98,  { 97, 99 },         5, false, false }, // Sauromugue Champaign [S]
    { 99,  { 98 },             5, false, true  }, // Castle Oztroja [S] (Yagudo stronghold)

    // Northlands
    { 136, { 82, 90, 97, 137 }, 6, false, false }, // Beaucedine Glacier [S] (crossroads)
    { 137, { 136, 138 },       6, false, false }, // Xarcabard [S]
    { 138, { 137, 155 },       6, false, false }, // Castle Zvahl Baileys [S]
    { 155, { 138, 156 },       6, false, false }, // Castle Zvahl Keep [S]
    { 156, { 155 },            6, false, true  }, // Throne Room [S] (Kindred stronghold)

    // Dungeons (independent)
    { 175, { 84 },             3, false, false }, // The Eldieme Necropolis [S]
    { 171, { 90 },             4, false, false }, // Crawlers' Nest [S]
    { 164, { 97 },             5, false, false }, // Garlaige Citadel [S]
};
// clang-format on

// ============================================================================
// Construction
// ============================================================================

CampaignSystem::CampaignSystem(WorldEngine& worldServer)
: worldServer_(worldServer)
{
    loadState();
}

// ============================================================================
// Message Handling
// ============================================================================

bool CampaignSystem::handleMessage(uint8 messageType, IPPMessage&& message)
{
    const auto campaignMsgType = static_cast<CampaignMessage>(messageType);
    switch (campaignMsgType)
    {
        case CampaignMessage::Campaign_M2W_GM_Tally:
        {
            runTally();
            return true;
        }
        case CampaignMessage::Campaign_M2W_GM_Update:
        {
            runUpdate();
            return true;
        }
        case CampaignMessage::Campaign_M2W_GM_Refresh:
        {
            broadcastState();
            return true;
        }
        case CampaignMessage::Campaign_M2W_AddInfluence:
        {
            if (const auto object = ipc::fromBytes<CampaignAddInfluence>(message.payload))
            {
                auto* zone = getZoneState((*object).zoneId);
                if (zone)
                {
                    uint8 current = getInfluenceForArmy(*zone, (*object).army);
                    int16 newVal  = std::clamp<int16>(static_cast<int16>(current) + (*object).amount, 0, MAX_INFLUENCE);
                    setInfluenceForArmy(*zone, (*object).army, static_cast<uint8>(newVal));
                    saveZoneState(*zone);
                    broadcastState();
                }
            }
            return true;
        }
        case CampaignMessage::Campaign_M2W_SetFortification:
        {
            if (const auto object = ipc::fromBytes<CampaignSetFortification>(message.payload))
            {
                auto* zone = getZoneState((*object).zoneId);
                if (zone)
                {
                    zone->currentFortifications = std::clamp<int16>((*object).amount, 0, zone->maxFortifications);
                    saveZoneState(*zone);
                    broadcastState();
                }
            }
            return true;
        }
        case CampaignMessage::Campaign_M2W_SetZoneControl:
        {
            if (const auto object = ipc::fromBytes<CampaignSetZoneControl>(message.payload))
            {
                auto* zone = getZoneState((*object).zoneId);
                if (zone)
                {
                    zone->controllingNation = (*object).nation;
                    saveZoneState(*zone);
                    broadcastState();
                }
            }
            return true;
        }
        case CampaignMessage::Campaign_M2W_SetBattleStatus:
        {
            if (const auto object = ipc::fromBytes<CampaignSetBattleStatus>(message.payload))
            {
                auto* zone = getZoneState((*object).zoneId);
                if (zone)
                {
                    zone->battleStatus = (*object).status;
                    saveZoneState(*zone);
                    broadcastState();
                }
            }
            return true;
        }
        default:
        {
            ShowWarningFmt("CampaignSystem: unknown message type received: {}", messageType);
        }
        break;
    }

    return false;
}

// ============================================================================
// Tally
// ============================================================================

void CampaignSystem::runTally()
{
    TracyZoneScoped;

    ShowInfo("Campaign: Running tally (ownership resolution)...");

    loadState(); // Refresh from DB

    resolveZoneControl();
    updateNationStats();

    // Save all zone states
    for (const auto& zone : zones_)
    {
        saveZoneState(zone);
    }

    // Save all nation states
    for (uint8 i = 0; i < nations_.size(); ++i)
    {
        saveNationState(i, nations_[i]);
    }

    ShowInfo("Campaign: Tally complete.");

    broadcastState();
}

void CampaignSystem::runUpdate()
{
    TracyZoneScoped;

    ShowInfo("Campaign: Running update (decay tick)...");

    loadState(); // Refresh from DB

    // Simple natural decay on all values for non-immune zones
    for (auto& zone : zones_)
    {
        const auto* adj = getAdjacency(zone.zoneId);
        if (!adj)
        {
            continue;
        }

        // Cities and strongholds are immune to decay
        if (adj->isCity || adj->isStronghold)
        {
            continue;
        }

        // Influence decay — all armies lose influence naturally
        // On retail, influence erodes without player action
        auto decayInfluence = [](uint8 value) -> uint8
        {
            if (value == 0)
            {
                return 0;
            }
            uint8 loss = std::max<uint8>(value * INFLUENCE_DECAY_PERCENT / 100, 1);
            return (value > loss) ? (value - loss) : 0;
        };

        zone.influenceSandoria = decayInfluence(zone.influenceSandoria);
        zone.influenceBastok   = decayInfluence(zone.influenceBastok);
        zone.influenceWindurst = decayInfluence(zone.influenceWindurst);
        zone.influenceBeastman = decayInfluence(zone.influenceBeastman);

        // Fortifications and resources do NOT decay passively.
        // They only change through active gameplay:
        // - Players attacking beastman forts (reduces beastman fortification)
        // - Beastmen attacking allied forts during Campaign Battles (reduces allied fortification)
        // - Campaign Ops (rebuilds resources/fortifications)
        // For now, these are only changed via GM commands.
    }

    // Save all zone states
    for (const auto& zone : zones_)
    {
        saveZoneState(zone);
    }

    ShowInfo("Campaign: Update complete.");

    broadcastState();
}

void CampaignSystem::broadcastState()
{
    loadState(); // Ensure fresh data

    CampaignFullState fullState;
    fullState.zones   = zones_;
    fullState.nations = nations_;

    worldServer_.ipcServer_->broadcastMessage(ipc::CampaignEvent{
        .type    = CampaignMessage::Campaign_W2M_BroadcastState,
        .payload = ipc::toBytes(fullState),
    });
}

// ============================================================================
// Tally Sub-Steps
// ============================================================================

void CampaignSystem::resolveZoneControl()
{
    for (auto& zone : zones_)
    {
        const auto* adj = getAdjacency(zone.zoneId);
        if (!adj || adj->isCity || adj->isStronghold)
        {
            continue;
        }

        uint8 highestArmy      = getHighestInfluenceArmy(zone);
        uint8 highestInfluence = getInfluenceForArmy(zone, highestArmy);
        uint8 currentControl   = zone.controllingNation;

        // Convert current controller to army index for comparison
        uint8 currentArmyIndex = 255;
        if (currentControl == 2)
        {
            currentArmyIndex = 0;
        }
        else if (currentControl == 4)
        {
            currentArmyIndex = 1;
        }
        else if (currentControl == 6)
        {
            currentArmyIndex = 2;
        }
        else if (currentControl == 8)
        {
            currentArmyIndex = 3; // Treat all beastmen as one for control purposes
        }

        uint8 currentInfluence = 0;
        if (currentArmyIndex == 3)
        {
            currentInfluence = zone.influenceBeastman;
        }
        else if (currentArmyIndex <= 2)
        {
            currentInfluence = getInfluenceForArmy(zone, currentArmyIndex);
        }

        // Check if highest exceeds current controller by threshold
        if (highestArmy != currentArmyIndex && highestInfluence > currentInfluence + FLIP_THRESHOLD)
        {
            // Flip control
            uint8 newControl = 8; // default beastman
            if (highestArmy == 0)
            {
                newControl = 2;
            }
            else if (highestArmy == 1)
            {
                newControl = 4;
            }
            else if (highestArmy == 2)
            {
                newControl = 6;
            }

            ShowInfoFmt("Campaign: Zone {} control changed from {} to {}", zone.zoneId, currentControl, newControl);
            zone.controllingNation     = newControl;
            zone.currentFortifications = 0; // Reset fortifications on flip
        }
    }
}

void CampaignSystem::updateNationStats()
{
    // Count zones controlled by each nation
    uint8 sandyZones   = 0;
    uint8 bastokZones  = 0;
    uint8 windyZones   = 0;
    uint8 beastZones   = 0;

    for (const auto& zone : zones_)
    {
        switch (zone.controllingNation)
        {
            case 2: sandyZones++;  break;
            case 4: bastokZones++; break;
            case 6: windyZones++;  break;
            case 8: beastZones++;  break;
        }
    }

    // Update prosperity based on zone count (more zones = more prosperity)
    auto updateProsperity = [](CampaignNationState& nation, uint8 zones)
    {
        uint8 target = std::min<uint8>(zones * 12, 100);
        if (nation.prosperity < target)
        {
            nation.prosperity = std::min<uint8>(nation.prosperity + 5, target);
        }
        else if (nation.prosperity > target)
        {
            nation.prosperity = (nation.prosperity > 5) ? nation.prosperity - 5 : 0;
        }
    };

    if (nations_.size() >= 7)
    {
        updateProsperity(nations_[0], sandyZones);
        updateProsperity(nations_[1], bastokZones);
        updateProsperity(nations_[2], windyZones);

        // Beastman morale increases when they hold more territory
        uint8 beastTarget = std::min<uint8>(beastZones * 5, 100);
        for (uint8 i = 3; i <= 6; ++i)
        {
            if (nations_[i].morale < beastTarget)
            {
                nations_[i].morale = std::min<uint8>(nations_[i].morale + 3, beastTarget);
            }
            else if (nations_[i].morale > beastTarget)
            {
                nations_[i].morale = (nations_[i].morale > 3) ? nations_[i].morale - 3 : 0;
            }
        }
    }
}

// ============================================================================
// DB Operations
// ============================================================================

void CampaignSystem::loadState()
{
    zones_.clear();
    nations_.clear();

    // Load zones
    const auto zoneRset = db::preparedStmt(
        "SELECT id, zoneid, isbattle, nation, heroism, influence_sandoria, influence_bastok, "
        "influence_windurst, influence_beastman, current_fortifications, current_resources, "
        "max_fortifications, max_resources FROM campaign_map ORDER BY id ASC");

    if (zoneRset && zoneRset->rowsCount())
    {
        while (zoneRset->next())
        {
            CampaignZoneState zone;
            zone.campaignId            = zoneRset->get<uint8>("id");
            zone.zoneId                = zoneRset->get<uint8>("zoneid");
            zone.battleStatus          = zoneRset->get<uint8>("isbattle");
            zone.controllingNation     = zoneRset->get<uint8>("nation");
            zone.heroism               = zoneRset->get<uint8>("heroism");
            zone.influenceSandoria     = zoneRset->get<uint8>("influence_sandoria");
            zone.influenceBastok       = zoneRset->get<uint8>("influence_bastok");
            zone.influenceWindurst     = zoneRset->get<uint8>("influence_windurst");
            zone.influenceBeastman     = zoneRset->get<uint8>("influence_beastman");
            zone.currentFortifications = zoneRset->get<uint16>("current_fortifications");
            zone.currentResources      = zoneRset->get<uint16>("current_resources");
            zone.maxFortifications     = zoneRset->get<uint16>("max_fortifications");
            zone.maxResources          = zoneRset->get<uint16>("max_resources");
            zones_.emplace_back(zone);
        }
    }

    // Load nations
    const auto nationRset = db::preparedStmt(
        "SELECT id, reconnaissance, morale, prosperity FROM campaign_nation ORDER BY id ASC");

    if (nationRset && nationRset->rowsCount())
    {
        while (nationRset->next())
        {
            CampaignNationState nation;
            nation.reconnaissance = nationRset->get<uint8>("reconnaissance");
            nation.morale         = nationRset->get<uint8>("morale");
            nation.prosperity     = nationRset->get<uint8>("prosperity");
            nations_.emplace_back(nation);
        }
    }
}

void CampaignSystem::saveZoneState(const CampaignZoneState& zone)
{
    db::preparedStmt(
        "UPDATE campaign_map SET isbattle = ?, nation = ?, heroism = ?, "
        "influence_sandoria = ?, influence_bastok = ?, influence_windurst = ?, influence_beastman = ?, "
        "current_fortifications = ?, current_resources = ?, max_fortifications = ?, max_resources = ? "
        "WHERE zoneid = ?",
        zone.battleStatus, zone.controllingNation, zone.heroism,
        zone.influenceSandoria, zone.influenceBastok, zone.influenceWindurst, zone.influenceBeastman,
        zone.currentFortifications, zone.currentResources, zone.maxFortifications, zone.maxResources,
        zone.zoneId);
}

void CampaignSystem::saveNationState(uint8 nationId, const CampaignNationState& nation)
{
    db::preparedStmt(
        "UPDATE campaign_nation SET reconnaissance = ?, morale = ?, prosperity = ? WHERE id = ?",
        nation.reconnaissance, nation.morale, nation.prosperity, nationId);
}

// ============================================================================
// Helpers
// ============================================================================

auto CampaignSystem::getAdjacency(uint8 zoneId) const -> const CampaignAdjacency*
{
    for (const auto& adj : adjacencyMap_)
    {
        if (adj.zoneId == zoneId)
        {
            return &adj;
        }
    }
    return nullptr;
}

auto CampaignSystem::getZoneState(uint8 zoneId) -> CampaignZoneState*
{
    for (auto& zone : zones_)
    {
        if (zone.zoneId == zoneId)
        {
            return &zone;
        }
    }
    return nullptr;
}

bool CampaignSystem::isControlledBy(uint8 zoneId, uint8 controlMask) const
{
    for (const auto& zone : zones_)
    {
        if (zone.zoneId == zoneId)
        {
            return zone.controllingNation == controlMask;
        }
    }
    return false;
}

auto CampaignSystem::getInfluenceForArmy(const CampaignZoneState& zone, uint8 army) const -> uint8
{
    switch (army)
    {
        case 0: return zone.influenceSandoria;
        case 1: return zone.influenceBastok;
        case 2: return zone.influenceWindurst;
        case 3: // All beastmen share one influence value
        case 4:
        case 5:
        case 6: return zone.influenceBeastman;
        default: return 0;
    }
}

void CampaignSystem::setInfluenceForArmy(CampaignZoneState& zone, uint8 army, uint8 value)
{
    switch (army)
    {
        case 0: zone.influenceSandoria = value; break;
        case 1: zone.influenceBastok   = value; break;
        case 2: zone.influenceWindurst = value; break;
        case 3:
        case 4:
        case 5:
        case 6: zone.influenceBeastman = value; break;
        default: break;
    }
}

auto CampaignSystem::getHighestInfluenceArmy(const CampaignZoneState& zone) const -> uint8
{
    uint8 highest = 0;
    uint8 army    = 0;

    if (zone.influenceSandoria > highest) { highest = zone.influenceSandoria; army = 0; }
    if (zone.influenceBastok   > highest) { highest = zone.influenceBastok;   army = 1; }
    if (zone.influenceWindurst > highest) { highest = zone.influenceWindurst; army = 2; }
    if (zone.influenceBeastman > highest) { highest = zone.influenceBeastman; army = 3; }

    return army;
}
