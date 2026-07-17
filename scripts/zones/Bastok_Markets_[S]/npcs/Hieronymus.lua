-----------------------------------
-- Area: Bastok Markets [S]
--  NPC: Hieronymus
-- Type: Campaign Ops NPC
-- !pos -230.0 -10.0 -56.0 87
-----------------------------------
require('scripts/globals/campaign_ops')
local ID = zones[xi.zone.BASTOK_MARKETS_S]
-----------------------------------
---@type TNpcEntity
local entity = {}

-----------------------------------
-- Helper: Display available ops to player
-----------------------------------
local function showAvailableOps(player)
    local ops = xi.campaignOps.getAvailableOps(xi.campaign.control.BASTOK)
    local credits = xi.campaignOps.getCredits(player)
    local medalRank = xi.campaign.getMedalRank(player)

    player:printToPlayer('=== Campaign Operations (Bastok) ===')
    player:printToPlayer(string.format('Op Credits: %d/%d | Medal Rank: %d',
        credits, xi.campaignOps.MAX_OP_CREDITS, medalRank))
    player:printToPlayer('---')

    local shown = 0
    for _, entry in ipairs(ops) do
        local opData = entry.data
        local rankOk = (opData.requiredMedalRank or 0) <= medalRank

        if rankOk then
            local typeLabel = ''
            if opData.opType == xi.campaignOps.type.RESOURCE_PROCUREMENT then
                typeLabel = '[Procurement]'
            elseif opData.opType == xi.campaignOps.type.SUPPLY_TRANSPORT then
                typeLabel = '[Transport]'
            elseif opData.opType == xi.campaignOps.type.SECURITY then
                typeLabel = '[Security]'
            elseif opData.opType == xi.campaignOps.type.SUPPLY_MANUFACTURE then
                typeLabel = '[Manufacture]'
            elseif opData.opType == xi.campaignOps.type.OFFENSIVE then
                typeLabel = '[Offensive]'
            elseif opData.opType == xi.campaignOps.type.DEFENSIVE then
                typeLabel = '[Defensive]'
            elseif opData.opType == xi.campaignOps.type.INTEL_GATHERING then
                typeLabel = '[Intel]'
            elseif opData.opType == xi.campaignOps.type.MILITARY_TRAINING then
                typeLabel = '[Training]'
            end

            player:printToPlayer(string.format('  %d: %s %s', entry.id, typeLabel, opData.name))
            player:printToPlayer(string.format('       %s', opData.description))
            player:printToPlayer(string.format('       Reward: %d EXP / %d Allied Notes', opData.expReward, opData.notesReward))
            shown = shown + 1
        end
    end

    if shown == 0 then
        player:printToPlayer('  No operations available at your current rank.')
    end

    player:printToPlayer('---')
    player:printToPlayer('To accept: Trade the OP ID number as gil to this NPC.')
    player:printToPlayer('  Example: Trade 1001 gil to accept "Stock and Awe I".')
    player:printToPlayer('To complete procurement ops: Trade required items.')
    player:printToPlayer('To report kill ops: Speak to me after kills are done.')
end

-----------------------------------
-- Helper: Show active op status
-----------------------------------
local function showActiveOpStatus(player)
    local opId    = xi.campaignOps.getActiveOp(player)
    local opData  = xi.campaignOps.getOpData(opId)
    local progress = xi.campaignOps.getProgress(player)

    player:printToPlayer('=== Active Operation ===')
    player:printToPlayer(string.format('  %s (ID: %d)', opData.name, opId))
    player:printToPlayer(string.format('  %s', opData.description))
    player:printToPlayer(string.format('  Progress: %d/%d', progress, opData.targetCount))

    if xi.campaignOps.isObjectiveMet(player) then
        player:printToPlayer('  Status: OBJECTIVE COMPLETE - Speak to me to collect reward!')
    else
        if opData.opType == xi.campaignOps.type.RESOURCE_PROCUREMENT or
           opData.opType == xi.campaignOps.type.SUPPLY_MANUFACTURE then
            player:printToPlayer('  Status: Trade the required items to me.')
        elseif opData.opType == xi.campaignOps.type.SECURITY or
               opData.opType == xi.campaignOps.type.OFFENSIVE or
               opData.opType == xi.campaignOps.type.DEFENSIVE or
               opData.opType == xi.campaignOps.type.MILITARY_TRAINING then
            player:printToPlayer('  Status: Defeat targets in the field, then report back.')
        elseif opData.opType == xi.campaignOps.type.SUPPLY_TRANSPORT or
               opData.opType == xi.campaignOps.type.INTEL_GATHERING then
            player:printToPlayer('  Status: Complete the objective in the field, then report back.')
        end
    end

    player:printToPlayer('---')
    player:printToPlayer('To cancel this op: Trade 1 gil to me.')
end

-----------------------------------
-- onTrade: Handles op acceptance (via gil amount = op ID),
--          item turn-ins for procurement ops,
--          and cancellation (trade 1 gil).
-----------------------------------
entity.onTrade = function(player, npc, trade)
    -- Check campaign allegiance
    if player:getCampaignAllegiance() == 0 then
        player:printToPlayer('You must enlist with a nation before undertaking Campaign Operations.')
        return
    end

    -- Initialize credits on first interaction
    xi.campaignOps.initCredits(player)

    local activeOp = xi.campaignOps.getActiveOp(player)

    -- If player has an active op, check for item trade (procurement/manufacture)
    if activeOp ~= 0 then
        local opData = xi.campaignOps.getOpData(activeOp)

        -- Trade exactly 1 gil with no items = cancel the op
        if npcUtil.tradeHasExactly(trade, { { 'gil', 1 } }) then
            xi.campaignOps.cancelOp(player)
            player:tradeComplete()
            player:printToPlayer(string.format('Operation cancelled: %s', opData.name))
            return
        end

        -- Try to handle as item trade for procurement/manufacture ops
        if opData and
           (opData.opType == xi.campaignOps.type.RESOURCE_PROCUREMENT or
            opData.opType == xi.campaignOps.type.SUPPLY_MANUFACTURE) then
            if xi.campaignOps.handleTrade(player, trade) then
                local progress = xi.campaignOps.getProgress(player)
                player:printToPlayer(string.format('Items received. Progress: %d/%d',
                    progress, opData.targetCount))

                if xi.campaignOps.isObjectiveMet(player) then
                    player:printToPlayer('Objective complete! Speak to me to collect your reward.')
                end
                return
            end
        end

        player:printToPlayer('That is not what is required for your current operation.')
        return
    end

    -- No active op: trade gil amount = op ID to accept
    local gilAmount = trade:getGil()
    if gilAmount >= 1001 and gilAmount <= 1099 and trade:getItemCount() == 0 then
        -- Treat the gil amount as an op ID
        local opId = gilAmount
        local success, reason = xi.campaignOps.acceptOp(player, opId)

        if success then
            player:tradeComplete()
            local opData = xi.campaignOps.getOpData(opId)
            player:printToPlayer(string.format('Operation accepted: %s', opData.name))
            player:printToPlayer(string.format('Objective: %s', opData.description))

            -- If it's a supply transport op, give the key item
            if opData.keyItemGiven then
                npcUtil.giveKeyItem(player, opData.keyItemGiven)
            end
        else
            player:printToPlayer(reason or 'Unable to accept operation.')
        end
        return
    end

    player:printToPlayer('I don\'t understand what you\'re offering.')
end

-----------------------------------
-- onTrigger: Show op menu or check status
-----------------------------------
entity.onTrigger = function(player, npc)
    -- Check campaign allegiance
    if player:getCampaignAllegiance() == 0 then
        player:printToPlayer('Enlist with Bastok to access Campaign Operations.')
        player:printToPlayer('Speak to the recruitment NPC to pledge your allegiance.')
        return
    end

    -- Initialize credits on first interaction
    xi.campaignOps.initCredits(player)

    local activeOp = xi.campaignOps.getActiveOp(player)

    if activeOp == 0 then
        -- No active op: show available ops
        showAvailableOps(player)
    else
        -- Has active op: show status or complete
        if xi.campaignOps.isObjectiveMet(player) then
            -- Complete the op
            local opData = xi.campaignOps.getOpData(activeOp)
            if xi.campaignOps.completeOp(player) then
                player:printToPlayer(string.format('Operation complete: %s', opData.name))
                player:printToPlayer(string.format('Earned: %d EXP, %d Allied Notes', opData.expReward, opData.notesReward))
            else
                player:printToPlayer('Unable to complete operation.')
            end
        else
            -- Show current status
            showActiveOpStatus(player)
        end
    end
end

return entity
