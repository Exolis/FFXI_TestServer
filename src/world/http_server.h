/*
===========================================================================

  Copyright (c) 2022 LandSandBoat Dev Teams

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

#include "common/logging.h"
#include "common/synchronized.h"
#include "common/timer.h"

#include "map/zone.h"

#include <mutex>

#include <httplib.h>

class CampaignSystem;

class HTTPServer
{
public:
    HTTPServer(Scheduler& scheduler);
    ~HTTPServer();

    void LockingUpdate();

    // Wire in the CampaignSystem so the HTTP API can trigger a state refresh
    // after external DB changes (e.g., from ServerManager).
    void setCampaignSystem(CampaignSystem* campaignSystem)
    {
        campaignSystem_ = campaignSystem;
    }

private:
    Scheduler&                     scheduler_;
    httplib::Server                httpServer_;
    std::atomic<timer::time_point> lastUpdate_;
    CampaignSystem*                campaignSystem_ = nullptr;

    struct APIDataCache
    {
        uint32                                 activeSessionCount;
        uint32                                 activeUniqueIPCount;
        std::array<uint32, ZONEID::MAX_ZONEID> zonePlayerCounts;
    };

    SynchronizedShared<APIDataCache> apiDataCache_;
};
