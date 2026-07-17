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

#include "http_server.h"

#include "campaign_system.h"
#include "common/database.h"
#include "common/logging.h"
#include "common/settings.h"
#include "common/utils.h"
#include "common/xi.h"

#include <unordered_set>

#include <nlohmann/json.hpp>
using json = nlohmann::json;

HTTPServer::HTTPServer(Scheduler& scheduler)
: scheduler_(scheduler)
, apiDataCache_(APIDataCache{})
{
    // NOTE: Everything registered in here happens off the main thread, so lock any global resources
    //     : you might be using.

    LockingUpdate();

    auto host = settings::get<std::string>("network.HTTP_HOST");
    auto port = settings::get<uint16>("network.HTTP_PORT");

    ShowInfoFmt("Starting HTTP Server on http://{}:{}/api", host, port);

    scheduler_.postToWorkerThread(
        [this, host, port]()
        {
            httpServer_.Get(
                "/api",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    res.set_content("Hello LSB API", "text/plain");
                });

            httpServer_.Get(
                "/api/sessions",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    LockingUpdate();
                    apiDataCache_.read([&](const auto& apiDataCache)
                                       {
                                           json j = apiDataCache.activeSessionCount;
                                           res.set_content(j.dump(), "application/json");
                                       });
                });

            httpServer_.Get(
                "/api/ips",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    LockingUpdate();
                    apiDataCache_.read(
                        [&](const auto& apiDataCache)
                        {
                            json j = apiDataCache.activeUniqueIPCount;
                            res.set_content(j.dump(), "application/json");
                        });
                });

            httpServer_.Get(
                "/api/zones",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    LockingUpdate();
                    apiDataCache_.read(
                        [&](const auto& apiDataCache)
                        {
                            json j = apiDataCache.zonePlayerCounts;
                            res.set_content(j.dump(), "application/json");
                        });
                });

            httpServer_.Get(
                R"(/api/zones/(\d+))",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    auto   maybeZoneId = req.matches[1].str();
                    uint16 zoneId      = std::strtol(maybeZoneId.c_str(), nullptr, 10);
                    if (zoneId && zoneId < ZONEID::MAX_ZONEID)
                    {
                        LockingUpdate();
                        apiDataCache_.read(
                            [&](const auto& apiDataCache)
                            {
                                json j = apiDataCache.zonePlayerCounts[zoneId];
                                res.set_content(j.dump(), "application/json");
                            });
                    }
                    else
                    {
                        res.status = 404;
                    }
                });

            httpServer_.Get(
                "/api/settings",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    // TODO: Cache these
                    json j{};

                    // Filter out settings we don't want to expose
                    std::unordered_set<std::string> textToOmit{
                        "logging.",
                        "network.",
                        "password", // Just in case
                    };

                    settings::visit(
                        [&](const auto& key, const auto& variant)
                        {
                            for (const auto& text : textToOmit)
                            {
                                // NOTE: Remember that keys are stored as uppercase
                                if (key.find(to_upper(text)) != std::string::npos)
                                {
                                    return;
                                }
                            }

                            std::visit(
                                xi::overload{
                                    [&](const bool& arg)
                                    {
                                        j[key] = arg;
                                    },
                                    [&](const double& arg)
                                    {
                                        j[key] = arg;
                                    },
                                    [&](const std::string& arg)
                                    {
                                        // JSON can't handle non-ASCII characters, so strip them out
                                        j[key] = utils::toASCII(arg, '?');
                                    },
                                },
                                variant);
                        });

                    res.set_content(j.dump(), "application/json");
                });

            httpServer_.Get(
                "/api/campaign/map",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    json j = json::array();
                    auto rset = db::preparedStmt("SELECT * FROM campaign_map");
                    if (rset && rset->rowsCount() > 0)
                    {
                        while (rset->next())
                        {
                            json obj;
                            obj["id"]                    = rset->get<uint8>("id");
                            obj["zoneid"]                = rset->get<uint16>("zoneid");
                            obj["isbattle"]              = rset->get<uint8>("isbattle");
                            obj["nation"]                = rset->get<uint8>("nation");
                            obj["heroism"]               = rset->get<uint8>("heroism");
                            obj["influence_sandoria"]    = rset->get<uint8>("influence_sandoria");
                            obj["influence_bastok"]      = rset->get<uint8>("influence_bastok");
                            obj["influence_windurst"]    = rset->get<uint8>("influence_windurst");
                            obj["influence_beastman"]    = rset->get<uint8>("influence_beastman");
                            obj["current_fortifications"] = rset->get<uint16>("current_fortifications");
                            obj["current_resources"]      = rset->get<uint16>("current_resources");
                            obj["max_fortifications"]     = rset->get<uint16>("max_fortifications");
                            obj["max_resources"]          = rset->get<uint16>("max_resources");
                            j.push_back(obj);
                        }
                    }
                    res.set_content(j.dump(), "application/json");
                });

            httpServer_.Get(
                "/api/campaign/nation",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    json j = json::array();
                    auto rset = db::preparedStmt("SELECT * FROM campaign_nation");
                    if (rset && rset->rowsCount() > 0)
                    {
                        while (rset->next())
                        {
                            json obj;
                            obj["id"]              = rset->get<uint8>("id");
                            obj["reconnaissance"]  = rset->get<uint8>("reconnaissance");
                            obj["morale"]          = rset->get<uint16>("morale");
                            obj["prosperity"]      = rset->get<uint8>("prosperity");
                            j.push_back(obj);
                        }
                    }
                    res.set_content(j.dump(), "application/json");
                });

            // Trigger a campaign state refresh: reload from DB and broadcast
            // to all map servers. Used by external tools (e.g., ServerManager)
            // after directly editing the campaign_map / campaign_nation tables.
            httpServer_.Post(
                "/api/campaign/refresh",
                [&](const httplib::Request& req, httplib::Response& res)
                {
                    if (!campaignSystem_)
                    {
                        res.status = 503;
                        res.set_content(R"({"error":"CampaignSystem not available"})", "application/json");
                        return;
                    }

                    ShowInfo("HTTP: /api/campaign/refresh requested — reloading campaign state from DB and broadcasting to map servers.");
                    scheduler_.postToWorkerThread(
                        [this]()
                        {
                            campaignSystem_->broadcastState();
                        });

                    res.set_content(R"({"status":"refresh queued"})", "application/json");
                });

            httpServer_.set_error_handler(
                [](const httplib::Request& /*req*/, httplib::Response& res)
                {
                    auto str = fmt::format("<p>Error Status: <span style='color:red;'>{} ({})</span></p>",
                                           res.status,
                                           httplib::status_message(res.status));

                    for (const auto& [key, val] : res.headers)
                    {
                        str += fmt::format("<p>{}: {}</p>", key, val);
                    }

                    res.set_content(str, "text/html");
                });

            httpServer_.set_logger(
                [](const httplib::Request& req, const httplib::Response& res)
                {
                    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
                    if (res.status >= 500)
                    {
                        ShowErrorFmt("Server Error: {} ({})", res.status, httplib::status_message(res.status));
                        return;
                    }
                    else if (res.status >= 400)
                    {
                        ShowErrorFmt("Client Error: {} ({})", res.status, httplib::status_message(res.status));
                        return;
                    }
                });

            httpServer_.listen(host, port); // blocks
        });
}

HTTPServer::~HTTPServer()
{
    httpServer_.stop();
}

void HTTPServer::LockingUpdate()
{
    auto now = timer::now();
    if (now < (lastUpdate_.load() + 60s))
    {
        return;
    }

    apiDataCache_.write(
        [&](auto& apiDataCache)
        {
            ShowInfoFmt("API data is stale. Updating...");

            // Total active sessions
            {
                auto rset = db::preparedStmt("SELECT COUNT(*) AS `count` FROM accounts_sessions");
                if (rset && rset->next())
                {
                    apiDataCache.activeSessionCount = rset->get<uint32>("count");
                }
            }

            // Total active unique IPs
            {
                auto rset = db::preparedStmt("SELECT COUNT(DISTINCT client_addr) AS `count` FROM accounts_sessions");
                if (rset && rset->next())
                {
                    apiDataCache.activeUniqueIPCount = rset->get<uint32>("count");
                }
            }

            // Chars per zone
            {
                auto rset = db::preparedStmt("SELECT chars.pos_zone, COUNT(*) AS `count` "
                                             "FROM chars "
                                             "INNER JOIN accounts_sessions "
                                             "ON chars.charid = accounts_sessions.charid "
                                             "GROUP BY pos_zone");
                if (rset && rset->rowsCount())
                {
                    while (rset->next())
                    {
                        auto zoneId = rset->get<uint16>("pos_zone");
                        auto count  = rset->get<uint32>("count");

                        apiDataCache.zonePlayerCounts[zoneId] = count;
                    }
                }
            }

            lastUpdate_.store(now);
        });
}
