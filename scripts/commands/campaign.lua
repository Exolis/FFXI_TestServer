-----------------------------------
-- func: campaign <subcommand> [args...]
-- desc: Campaign system GM tools
-----------------------------------
require('scripts/globals/campaign_battle')
require('scripts/globals/campaign_ops')
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 1,
    parameters = 'sssss'
}

local function printHelp(player)
    player:printToPlayer('Campaign GM Commands:')
    player:printToPlayer('  !campaign tally                         - Resolve zone ownership based on influence')
    player:printToPlayer('  !campaign update                        - Run simulation tick (influence/fort/resource changes)')
    player:printToPlayer('  !campaign refresh                       - Broadcast current state to all players')
    player:printToPlayer('  !campaign influence <zoneId> <army> <amount> - Set influence (army: 0=San,1=Bas,2=Win,3=Beast)')
    player:printToPlayer('  !campaign fort <zoneId> <amount>        - Set fortifications')
    player:printToPlayer('  !campaign control <zoneId> <nation>     - Set zone control (2=San,4=Bas,6=Win,8=Beast)')
    player:printToPlayer('  !campaign battle <zoneId> <0|1>         - Set battle status')
    player:printToPlayer('  !campaign status                        - Show all zone states')
    player:printToPlayer('  --- Campaign Ops ---')
    player:printToPlayer('  !campaign ops                           - Show your active op and credits')
    player:printToPlayer('  !campaign ops credits [amount]          - Set op credits (default: max)')
    player:printToPlayer('  !campaign ops accept <opId>             - Force-accept an op (no credit cost)')
    player:printToPlayer('  !campaign ops complete                  - Force-complete active op')
    player:printToPlayer('  !campaign ops cancel                    - Cancel active op')
    player:printToPlayer('  !campaign ops progress <amount>         - Set op progress')
    player:printToPlayer('  !campaign ops list                      - List all defined ops')
end

local nationNames =
{
    [2] = 'San d\'Oria',
    [4] = 'Bastok',
    [6] = 'Windurst',
    [8] = 'Beastmen',
}

local armyNames =
{
    [0] = 'Sandoria',
    [1] = 'Bastok',
    [2] = 'Windurst',
    [3] = 'Orcish',
    [4] = 'Quadav',
    [5] = 'Yagudo',
    [6] = 'Kindred',
}

commandObj.onTrigger = function(player, subcommand, arg1, arg2, arg3)
    if subcommand == nil then
        printHelp(player)
        return
    end

    subcommand = string.lower(subcommand)

    if subcommand == 'help' then
        printHelp(player)

    elseif subcommand == 'tally' then
        CampaignTally()
        player:printToPlayer('Campaign tally triggered (ownership resolution).')

    elseif subcommand == 'update' then
        CampaignUpdate()
        player:printToPlayer('Campaign update triggered (simulation tick).')

    elseif subcommand == 'refresh' then
        CampaignRefresh()
        player:printToPlayer('Campaign state broadcast to all players.')

    elseif subcommand == 'influence' then
        local zoneId = tonumber(arg1)
        local army   = tonumber(arg2)
        local amount = tonumber(arg3)

        if zoneId == nil or army == nil or amount == nil then
            player:printToPlayer('Usage: !campaign influence <zoneId> <army> <amount>')
            player:printToPlayer('  army: 0=Sandoria, 1=Bastok, 2=Windurst, 3=Beastman')
            return
        end

        CampaignSetInfluence(zoneId, army, amount)
        player:printToPlayer(string.format('Set zone %d %s influence to %d.', zoneId, armyNames[army] or '?', amount))

    elseif subcommand == 'fort' then
        local zoneId = tonumber(arg1)
        local amount = tonumber(arg2)

        if zoneId == nil or amount == nil then
            player:printToPlayer('Usage: !campaign fort <zoneId> <amount>')
            return
        end

        CampaignSetFortification(zoneId, amount)
        player:printToPlayer(string.format('Set zone %d fortifications to %d.', zoneId, amount))

    elseif subcommand == 'control' then
        local zoneId = tonumber(arg1)
        local nation = tonumber(arg2)

        if zoneId == nil or nation == nil then
            player:printToPlayer('Usage: !campaign control <zoneId> <nation>')
            player:printToPlayer('  nation: 2=Sandy, 4=Bastok, 6=Windy, 8=Beastmen')
            return
        end

        CampaignSetZoneControl(zoneId, nation)
        player:printToPlayer(string.format('Set zone %d control to %s (%d).', zoneId, nationNames[nation] or '?', nation))

    elseif subcommand == 'battle' then
        local zoneId = tonumber(arg1)
        local status = tonumber(arg2)

        if zoneId == nil or status == nil then
            player:printToPlayer('Usage: !campaign battle <zoneId> <0|1>')
            return
        end

        if status == 1 then
            -- Start a full campaign battle with spawns
            local success = xi.campaignBattle.startBattle(zoneId)
            if success then
                player:printToPlayer(string.format('Campaign Battle STARTED in zone %d (forts + NPCs + mobs spawned).', zoneId))
            else
                -- Fallback: just set the flag without spawns
                CampaignSetBattleStatus(zoneId, status)
                player:printToPlayer(string.format('Set zone %d battle status to %d (no spawn data available).', zoneId, status))
            end
        else
            -- End the battle and despawn everything
            local battle = xi.campaignBattle.getBattle(zoneId)
            if battle then
                xi.campaignBattle.endBattle(zoneId)
                player:printToPlayer(string.format('Campaign Battle ENDED in zone %d (all entities despawned).', zoneId))
            else
                CampaignSetBattleStatus(zoneId, status)
                player:printToPlayer(string.format('Set zone %d battle status to %d.', zoneId, status))
            end
        end

    elseif subcommand == 'status' then
        player:printToPlayer('Campaign Zone Status:')
        player:printToPlayer('Zone | Control    | Fort | San | Bas | Win | Bst | Battle')
        player:printToPlayer('-----|------------|------|-----|-----|-----|-----|-------')

        -- This reads directly from the campaign handlers
        local zones = GetCampaignStatus()
        if zones then
            for _, z in ipairs(zones) do
                local ctrl = nationNames[z.nation] or string.format('(%d)', z.nation)
                player:printToPlayer(string.format(' %3d | %-10s | %4d | %3d | %3d | %3d | %3d | %s',
                    z.zoneId, ctrl, z.fort, z.san, z.bas, z.win, z.bst,
                    z.battle == 1 and 'YES' or 'no'))
            end
        else
            player:printToPlayer('Unable to retrieve campaign status.')
        end

    elseif subcommand == 'ops' then
        local opsCmd = arg1 and string.lower(arg1) or nil

        if opsCmd == nil then
            -- Show current op status
            local activeOp = xi.campaignOps.getActiveOp(player)
            local credits  = xi.campaignOps.getCredits(player)

            player:printToPlayer(string.format('Op Credits: %d/%d', credits, xi.campaignOps.MAX_OP_CREDITS))

            if activeOp == 0 then
                player:printToPlayer('Active Op: None')
            else
                local opData   = xi.campaignOps.getOpData(activeOp)
                local progress = xi.campaignOps.getProgress(player)
                player:printToPlayer(string.format('Active Op: %d - %s', activeOp, opData and opData.name or '?'))
                player:printToPlayer(string.format('Progress: %d/%d', progress, opData and opData.targetCount or 0))

                if xi.campaignOps.isObjectiveMet(player) then
                    player:printToPlayer('Status: COMPLETE (ready to turn in)')
                else
                    player:printToPlayer('Status: In Progress')
                end
            end

        elseif opsCmd == 'credits' then
            local amount = tonumber(arg2) or xi.campaignOps.MAX_OP_CREDITS
            xi.campaignOps.setCredits(player, amount)
            player:printToPlayer(string.format('Op credits set to %d.', xi.campaignOps.getCredits(player)))

        elseif opsCmd == 'accept' then
            local opId = tonumber(arg2)
            if opId == nil then
                player:printToPlayer('Usage: !campaign ops accept <opId>')
                return
            end

            local opData = xi.campaignOps.getOpData(opId)
            if not opData then
                player:printToPlayer(string.format('Op ID %d does not exist.', opId))
                return
            end

            -- Force accept without credit check
            xi.campaignOps.clearOpVars(player)
            xi.campaignOps.setActiveOp(player, opId)
            xi.campaignOps.setProgress(player, 0)
            player:printToPlayer(string.format('Force-accepted op %d: %s', opId, opData.name))

        elseif opsCmd == 'complete' then
            local activeOp = xi.campaignOps.getActiveOp(player)
            if activeOp == 0 then
                player:printToPlayer('No active op to complete.')
                return
            end

            -- Force progress to target then complete
            local opData = xi.campaignOps.getOpData(activeOp)
            xi.campaignOps.setProgress(player, opData.targetCount)

            if xi.campaignOps.completeOp(player) then
                player:printToPlayer(string.format('Force-completed op %d: %s', activeOp, opData.name))
                player:printToPlayer(string.format('Rewarded: %d EXP, %d Allied Notes', opData.expReward, opData.notesReward))
            else
                player:printToPlayer('Failed to complete op.')
            end

        elseif opsCmd == 'cancel' then
            local activeOp = xi.campaignOps.getActiveOp(player)
            if activeOp == 0 then
                player:printToPlayer('No active op to cancel.')
                return
            end

            xi.campaignOps.cancelOp(player)
            player:printToPlayer(string.format('Cancelled op %d.', activeOp))

        elseif opsCmd == 'progress' then
            local amount = tonumber(arg2)
            if amount == nil then
                player:printToPlayer('Usage: !campaign ops progress <amount>')
                return
            end

            xi.campaignOps.setProgress(player, amount)
            player:printToPlayer(string.format('Op progress set to %d.', amount))

        elseif opsCmd == 'list' then
            player:printToPlayer('Defined Campaign Ops:')
            local allOps = {}
            for opId, opData in pairs(xi.campaignOps.ops) do
                table.insert(allOps, { id = opId, data = opData })
            end
            table.sort(allOps, function(a, b) return a.id < b.id end)

            for _, entry in ipairs(allOps) do
                local nation = nationNames[entry.data.nation] or '?'
                player:printToPlayer(string.format('  %d: [%s] %s (Rank %d+)',
                    entry.id, nation, entry.data.name, entry.data.requiredMedalRank or 0))
            end

        else
            player:printToPlayer('Unknown ops subcommand. Use: !campaign ops help')
            player:printToPlayer('  credits, accept, complete, cancel, progress, list')
        end

    else
        printHelp(player)
    end
end

return commandObj
