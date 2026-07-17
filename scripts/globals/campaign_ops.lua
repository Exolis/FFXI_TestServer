-----------------------------------
-- Campaign Ops System
-- Manages Campaign Operations (Special Operations) for Wings of the Goddess.
-- Players accept ops from Campaign Ops NPCs, complete objectives, and earn
-- EXP + Allied Notes. Uses an Op Credit system to gate how many ops
-- a player can do per cycle.
-----------------------------------
require('scripts/globals/campaign_ops_data')
require('scripts/globals/npc_util')
-----------------------------------
xi = xi or {}
xi.campaignOps = xi.campaignOps or {}

-----------------------------------
-- Op Type Constants
-----------------------------------
xi.campaignOps.type =
{
    RESOURCE_PROCUREMENT = 1, -- Stock and Awe, Materiel Storm, etc.
    SUPPLY_TRANSPORT     = 2, -- Vanguard, Crimson Domino, etc.
    SECURITY             = 3, -- Streetsweeper, Delta Strike, etc.
    SUPPLY_MANUFACTURE   = 4, -- Crystal Fist, Iron Anvil, etc.
    OFFENSIVE            = 5, -- Smokescreen, Pit Spider, etc.
    DEFENSIVE            = 6, -- Aegis Scream, Granite Rose, etc.
    INTEL_GATHERING      = 7, -- Hawk Eye, Deep Cover, etc.
    MILITARY_TRAINING    = 8, -- Brave Dawn, Cut and Cauterize, etc.
}

-----------------------------------
-- Op Status Constants
-----------------------------------
xi.campaignOps.status =
{
    AVAILABLE  = 0, -- Op can be accepted
    ACTIVE     = 1, -- Op is currently in progress
    COMPLETE   = 2, -- Op objective met, awaiting turn-in
}

-----------------------------------
-- Op Credit Management
-- Players get 1 credit per Vana'diel day (max 7).
-- With Rhapsody in Mauve: 1 credit per 10 Earth minutes (max 7).
-----------------------------------
xi.campaignOps.MAX_OP_CREDITS = 7

-- Get the player's current op credits
xi.campaignOps.getCredits = function(player)
    return player:getCharVar('CampaignOp_Credits')
end

-- Set the player's op credits
xi.campaignOps.setCredits = function(player, amount)
    local clamped = math.max(0, math.min(amount, xi.campaignOps.MAX_OP_CREDITS))
    player:setCharVar('CampaignOp_Credits', clamped)
end

-- Consume 1 op credit. Returns true if successful, false if no credits.
xi.campaignOps.useCredit = function(player)
    local credits = xi.campaignOps.getCredits(player)
    if credits <= 0 then
        return false
    end

    xi.campaignOps.setCredits(player, credits - 1)
    return true
end

-- Grant a credit (called by Vana'diel day timer or Rhapsody timer)
xi.campaignOps.grantCredit = function(player)
    local credits = xi.campaignOps.getCredits(player)
    if credits < xi.campaignOps.MAX_OP_CREDITS then
        xi.campaignOps.setCredits(player, credits + 1)
    end
end

-- Initialize credits for a new player (give them max to start)
xi.campaignOps.initCredits = function(player)
    if player:getCharVar('CampaignOp_CreditsInit') == 0 then
        xi.campaignOps.setCredits(player, xi.campaignOps.MAX_OP_CREDITS)
        player:setCharVar('CampaignOp_CreditsInit', 1)
    end
end

-----------------------------------
-- Active Op Management
-----------------------------------

-- Get the player's currently active op ID (0 = none)
xi.campaignOps.getActiveOp = function(player)
    return player:getCharVar('CampaignOp_ActiveOp')
end

-- Set the player's active op
xi.campaignOps.setActiveOp = function(player, opId)
    player:setCharVar('CampaignOp_ActiveOp', opId)
end

-- Get progress on the current op (generic progress counter)
xi.campaignOps.getProgress = function(player)
    return player:getCharVar('CampaignOp_Progress')
end

-- Set progress on the current op
xi.campaignOps.setProgress = function(player, value)
    player:setCharVar('CampaignOp_Progress', value)
end

-- Clear all op-related vars for the player
xi.campaignOps.clearOpVars = function(player)
    player:setCharVar('CampaignOp_ActiveOp', 0)
    player:setCharVar('CampaignOp_Progress', 0)
end

-----------------------------------
-- Op Acceptance
-----------------------------------

-- Attempt to accept an op. Returns true/false and a message reason.
xi.campaignOps.acceptOp = function(player, opId)
    -- Check if player already has an active op
    if xi.campaignOps.getActiveOp(player) ~= 0 then
        return false, 'You already have an active Campaign Op.'
    end

    -- Validate op exists
    local opData = xi.campaignOps.getOpData(opId)
    if not opData then
        return false, 'Invalid operation.'
    end

    -- Check medal rank requirement
    if opData.requiredMedalRank then
        local rank = xi.campaign.getMedalRank(player)
        if rank < opData.requiredMedalRank then
            return false, 'Your medal rank is insufficient for this operation.'
        end
    end

    -- Check allegiance
    if player:getCampaignAllegiance() == 0 then
        return false, 'You must be enlisted in a nation to accept Campaign Ops.'
    end

    -- Check op credits
    if not xi.campaignOps.useCredit(player) then
        return false, 'You do not have enough Op Credits.'
    end

    -- Accept the op
    xi.campaignOps.setActiveOp(player, opId)
    xi.campaignOps.setProgress(player, 0)

    printf('[CampaignOps] Player %s accepted op %d (%s)', player:getName(), opId, opData.name)
    return true, nil
end

-----------------------------------
-- Op Completion
-----------------------------------

-- Check if the active op's objective is met
xi.campaignOps.isObjectiveMet = function(player)
    local opId   = xi.campaignOps.getActiveOp(player)
    local opData = xi.campaignOps.getOpData(opId)

    if not opData then
        return false
    end

    local progress = xi.campaignOps.getProgress(player)
    return progress >= (opData.targetCount or 1)
end

-- Complete the active op and grant rewards.
-- Returns true on success.
xi.campaignOps.completeOp = function(player)
    local opId   = xi.campaignOps.getActiveOp(player)
    local opData = xi.campaignOps.getOpData(opId)

    if not opData then
        return false
    end

    if not xi.campaignOps.isObjectiveMet(player) then
        return false
    end

    -- Grant EXP reward
    local expReward = opData.expReward or 500
    player:addExp(expReward)

    -- Grant Allied Notes reward
    local notesReward = opData.notesReward or 200
    player:addCurrency('allied_notes', notesReward)

    -- Apply op effect (e.g., add resources to a zone)
    if opData.onComplete then
        opData.onComplete(player, opData)
    end

    -- Clear op vars
    xi.campaignOps.clearOpVars(player)

    printf('[CampaignOps] Player %s completed op %d (%s) - EXP: %d, AN: %d',
        player:getName(), opId, opData.name, expReward, notesReward)
    return true
end

-----------------------------------
-- Op Cancellation
-----------------------------------

-- Cancel the active op. Does NOT refund the op credit.
xi.campaignOps.cancelOp = function(player)
    local opId = xi.campaignOps.getActiveOp(player)
    if opId == 0 then
        return false
    end

    xi.campaignOps.clearOpVars(player)
    printf('[CampaignOps] Player %s cancelled op %d', player:getName(), opId)
    return true
end

-----------------------------------
-- Item Trade Handling (Resource Procurement type ops)
-----------------------------------

-- Called when a player trades items to the Campaign Ops NPC.
-- Checks if the trade satisfies the active op's requirements.
-- Returns true if trade was consumed, false otherwise.
xi.campaignOps.handleTrade = function(player, trade)
    local opId   = xi.campaignOps.getActiveOp(player)
    local opData = xi.campaignOps.getOpData(opId)

    if not opData then
        return false
    end

    -- Only resource procurement ops accept trades
    if opData.opType ~= xi.campaignOps.type.RESOURCE_PROCUREMENT and
       opData.opType ~= xi.campaignOps.type.SUPPLY_MANUFACTURE then
        return false
    end

    -- Check if the trade matches the required items
    if not opData.tradeItems then
        return false
    end

    if npcUtil.tradeHasExactly(trade, opData.tradeItems) then
        player:tradeComplete()

        -- Increment progress
        local progress = xi.campaignOps.getProgress(player)
        xi.campaignOps.setProgress(player, progress + 1)

        return true
    end

    return false
end

-----------------------------------
-- Op Data Lookup
-----------------------------------

-- Get op data by ID from the data file
xi.campaignOps.getOpData = function(opId)
    if opId == nil or opId == 0 then
        return nil
    end

    return xi.campaignOps.ops[opId]
end

-- Get list of available ops for a given nation and type
xi.campaignOps.getAvailableOps = function(nation, opType)
    local available = {}

    for opId, opData in pairs(xi.campaignOps.ops) do
        if opData.nation == nation and
           (opType == nil or opData.opType == opType) then
            table.insert(available, { id = opId, data = opData })
        end
    end

    -- Sort by ID for consistent ordering
    table.sort(available, function(a, b) return a.id < b.id end)
    return available
end

-----------------------------------
-- Credit Regeneration (called from onGameHour or similar)
-- On retail: 1 credit per Vana'diel day. With Rhapsody in Mauve: every 10 Earth min.
-- For simplicity, we grant 1 credit per Vana'diel day (every 24 game hours).
-----------------------------------
xi.campaignOps.onNewVanaDay = function(player)
    xi.campaignOps.grantCredit(player)
end

-----------------------------------
-- Mob Death Tracking for kill-based ops
-- Called from mob onMobDeath scripts in campaign zones.
-- Checks if the player has an active op that requires kills in this zone.
-----------------------------------
xi.campaignOps.onMobDeath = function(mob, player)
    if not player then
        return
    end

    local opId   = xi.campaignOps.getActiveOp(player)
    local opData = xi.campaignOps.getOpData(opId)

    if not opData then
        return
    end

    -- Only kill-based op types
    if opData.opType ~= xi.campaignOps.type.SECURITY and
       opData.opType ~= xi.campaignOps.type.OFFENSIVE and
       opData.opType ~= xi.campaignOps.type.DEFENSIVE and
       opData.opType ~= xi.campaignOps.type.MILITARY_TRAINING then
        return
    end

    -- Check if the kill is in the correct zone
    if opData.targetZone and player:getZoneID() ~= opData.targetZone then
        return
    end

    -- Check if the mob family matches (if specified)
    if opData.targetMobs and #opData.targetMobs > 0 then
        local mobName = mob:getName()
        local matches = false

        for _, pattern in ipairs(opData.targetMobs) do
            if string.find(mobName, pattern) then
                matches = true
                break
            end
        end

        if not matches then
            return
        end
    end

    -- Already complete? Don't count more.
    local progress = xi.campaignOps.getProgress(player)
    if progress >= opData.targetCount then
        return
    end

    -- Increment progress
    progress = progress + 1
    xi.campaignOps.setProgress(player, progress)

    player:printToPlayer(string.format('[Campaign Op] Target defeated: %d/%d', progress, opData.targetCount))

    if progress >= opData.targetCount then
        player:printToPlayer('[Campaign Op] Objective complete! Report to the Campaign Ops NPC.')
    end
end
