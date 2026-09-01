-----------------------------------
-- Campaign Medal System
--
-- Medals are the Campaign progression ladder. A player's rank gates which
-- Campaign Ops they may accept, how long a Sigil lasts, and (once the Allied Tag
-- layer exists) how many campaign points one tag can hold.
--
-- RANKS ARE KEY ITEMS. The ladder is 20 contiguous key items, xi.ki ids 924-943:
--   Ribbons  (rank  1-4 ) BRONZE_RIBBON_OF_SERVICE .. ALLIED_RIBBON_OF_GLORY
--   Stars    (rank  5-8 ) BRONZE_STAR              .. GOLDEN_STAR
--   Emblems  (rank  9-12) COPPER_EMBLEM_OF_SERVICE .. HOLYKNIGHT_EMBLEM
--   Wings    (rank 13-16) BRASS_WINGS_OF_SERVICE   .. WINGS_OF_HONOR
--   Medals   (rank 17-20) STARLIGHT_MEDAL          .. MEDAL_OF_ALTANA
-- Rank 0 means "no medal" (or an expired one).
--
-- Retail behaviour this models (source: https://www.bg-wiki.com/ffxi/Category:Campaign):
--   * A Campaign Evaluation Official judges performance: Promotion, Status quo,
--     or Demotion.
--   * Evaluation is only possible 120 Earth hours after enlisting, transferring,
--     or the last evaluation -- reduced to 1 Earth hour with Rhapsody in Mauve.
--   * A medal is valid for 30 Earth days; an expired medal disables medal-gated
--     services.
--   * A demotion halves the accumulated evaluation score.
--   * Changing allegiance costs 2 medal ranks and resets evaluation progress.
--   * WotG nation-quest progress guarantees a MINIMUM rank that evaluation will
--     not demote below.
--
-- WHAT THE WIKI DOES NOT PUBLISH: the score thresholds that decide a promotion.
-- The constants below are OURS (see docs/Campaign_Spec.md section 4) and are
-- deliberately data-like so they can be retuned without touching logic.
-----------------------------------
require('scripts/globals/campaign')
require('scripts/globals/npc_util')
-----------------------------------
xi = xi or {}
xi.campaign = xi.campaign or {}
xi.campaign.medal = xi.campaign.medal or {}

-----------------------------------
-- Ladder definition
-----------------------------------

-- Rank 1 is the lowest medal, MAX_RANK the highest.
xi.campaign.medal.MAX_RANK = 20

-- Evaluation outcomes.
xi.campaign.medal.result =
{
    DEMOTION   = -1,
    STATUS_QUO = 0,
    PROMOTION  = 1,
}

-- Display names, indexed by rank. Kept in ladder order.
xi.campaign.medal.names =
{
    [1]  = 'Bronze Ribbon of Service',
    [2]  = 'Brass Ribbon of Service',
    [3]  = 'Allied Ribbon of Bravery',
    [4]  = 'Allied Ribbon of Glory',
    [5]  = 'Bronze Star',
    [6]  = 'Sterling Star',
    [7]  = 'Mythril Star',
    [8]  = 'Golden Star',
    [9]  = 'Copper Emblem of Service',
    [10] = 'Iron Emblem of Service',
    [11] = 'Steelknight Emblem',
    [12] = 'Holyknight Emblem',
    [13] = 'Brass Wings of Service',
    [14] = 'Mythril Wings of Service',
    [15] = 'Wings of Integrity',
    [16] = 'Wings of Honor',
    [17] = 'Starlight Medal',
    [18] = 'Moonlight Medal',
    [19] = 'Dawnlight Medal',
    [20] = 'Medal of Altana',
}

-----------------------------------
-- Tunable constants (ours, not retail-published)
-----------------------------------

-- Evaluation cooldown: 120 Earth hours, or 1 Earth hour with Rhapsody in Mauve.
xi.campaign.medal.EVAL_COOLDOWN          = 120 * 3600
xi.campaign.medal.EVAL_COOLDOWN_RHAPSODY = 3600

-- A medal stays valid for 30 Earth days.
xi.campaign.medal.VALID_DURATION = 30 * 24 * 3600

-- Score needed for a promotion scales with the rank being left behind, so each
-- step up costs more than the last. Rank 0 -> 1 uses the rank-1 cost.
xi.campaign.medal.PROMOTION_BASE_SCORE = 500

-- Ranks lost when a player changes allegiance.
xi.campaign.medal.ALLEGIANCE_RANK_COST = 2

-----------------------------------
-- Charvars
--   CampaignMedal_Score    accumulated evaluation score since the last eval
--   CampaignMedal_LastEval timestamp of the last evaluation (0 = never)
--   CampaignMedal_Issued   timestamp the current medal was awarded (validity)
-----------------------------------

-- Convert a rank (1..MAX_RANK) to its key item id.
xi.campaign.medal.rankToKeyItem = function(rank)
    if rank == nil or rank < 1 or rank > xi.campaign.medal.MAX_RANK then
        return nil
    end

    return xi.ki.BRONZE_RIBBON_OF_SERVICE + (rank - 1)
end

-- The player's current rank: the HIGHEST medal key item held. 0 = none.
--
-- NOTE: xi.campaign.getMedalRank() (campaign.lua) COUNTS held medals instead.
-- Those agree while medals are awarded cumulatively, which promote() does. This
-- function is the authority because it stays correct even if a medal is removed
-- out of order.
xi.campaign.medal.getRank = function(player)
    for rank = xi.campaign.medal.MAX_RANK, 1, -1 do
        local keyItem = xi.campaign.medal.rankToKeyItem(rank)

        if keyItem ~= nil and player:hasKeyItem(keyItem) then
            return rank
        end
    end

    return 0
end

xi.campaign.medal.getRankName = function(rank)
    if rank == nil or rank == 0 then
        return 'None'
    end

    return xi.campaign.medal.names[rank] or string.format('Rank %d', rank)
end

-----------------------------------
-- Minimum rank floor
--
-- Retail guarantees a minimum rank from WotG nation-mission progress, and
-- evaluation never demotes below it. The mission->rank mapping is not
-- implemented yet, so this returns 0 (no floor). Wire it here rather than in
-- evaluate() so there is one place to change.
-----------------------------------
xi.campaign.medal.getMinimumRank = function(player)
    return 0
end

-----------------------------------
-- Medal validity (30 Earth days)
-----------------------------------

-- True when the player holds a medal that has not expired.
xi.campaign.medal.isValid = function(player)
    if xi.campaign.medal.getRank(player) == 0 then
        return false
    end

    local issued = player:getCharVar('CampaignMedal_Issued')

    -- Awarded before validity tracking existed: treat as valid and stamp it now
    -- rather than silently expiring someone's medal.
    if issued == 0 then
        player:setCharVar('CampaignMedal_Issued', os.time())

        return true
    end

    return (os.time() - issued) < xi.campaign.medal.VALID_DURATION
end

-- Seconds until the current medal expires (0 when expired or absent).
xi.campaign.medal.validityRemaining = function(player)
    if xi.campaign.medal.getRank(player) == 0 then
        return 0
    end

    local issued = player:getCharVar('CampaignMedal_Issued')

    if issued == 0 then
        return xi.campaign.medal.VALID_DURATION
    end

    local remaining = xi.campaign.medal.VALID_DURATION - (os.time() - issued)

    return math.max(0, remaining)
end

-- Renew the current medal's validity without changing rank.
xi.campaign.medal.renew = function(player)
    if xi.campaign.medal.getRank(player) == 0 then
        return false
    end

    player:setCharVar('CampaignMedal_Issued', os.time())

    return true
end

-----------------------------------
-- Evaluation score
-----------------------------------

xi.campaign.medal.getScore = function(player)
    return player:getCharVar('CampaignMedal_Score')
end

-- Accumulate evaluation score. Called from Campaign activity (op completion
-- today; battle performance once the Allied Tag layer exists).
xi.campaign.medal.addScore = function(player, amount)
    if amount == nil or amount <= 0 then
        return
    end

    player:setCharVar('CampaignMedal_Score', xi.campaign.medal.getScore(player) + amount)
end

-- Score required to advance FROM the given rank.
xi.campaign.medal.scoreForPromotion = function(rank)
    local step = math.max(1, rank)

    return xi.campaign.medal.PROMOTION_BASE_SCORE * step
end

-----------------------------------
-- Evaluation cooldown
-----------------------------------

local function evalCooldown(player)
    if player:hasKeyItem(xi.ki.RHAPSODY_IN_MAUVE) then
        return xi.campaign.medal.EVAL_COOLDOWN_RHAPSODY
    end

    return xi.campaign.medal.EVAL_COOLDOWN
end

-- Seconds remaining before the player may be evaluated again (0 = ready).
xi.campaign.medal.evalCooldownRemaining = function(player)
    local last = player:getCharVar('CampaignMedal_LastEval')

    if last == 0 then
        return 0
    end

    local remaining = evalCooldown(player) - (os.time() - last)

    return math.max(0, remaining)
end

xi.campaign.medal.canEvaluate = function(player)
    return xi.campaign.medal.evalCooldownRemaining(player) <= 0
end

-----------------------------------
-- Promotion / demotion
-----------------------------------

-- Award the next rank up. Returns the new rank, or nil when already at the top.
xi.campaign.medal.promote = function(player)
    local rank = xi.campaign.medal.getRank(player)

    if rank >= xi.campaign.medal.MAX_RANK then
        return nil
    end

    local newRank = rank + 1
    local keyItem = xi.campaign.medal.rankToKeyItem(newRank)

    if keyItem == nil then
        return nil
    end

    -- npcUtil.giveKeyItem handles the "obtained key item" message for us; the
    -- project's coding standards prefer these helpers over raw add + messageSpecial.
    npcUtil.giveKeyItem(player, keyItem)
    player:setCharVar('CampaignMedal_Issued', os.time())

    return newRank
end

-- Strip the given number of ranks (default 1). Never goes below the player's
-- guaranteed minimum rank. Returns the new rank.
xi.campaign.medal.demote = function(player, steps)
    local rank    = xi.campaign.medal.getRank(player)
    local floor   = xi.campaign.medal.getMinimumRank(player)
    local removes = math.max(1, steps or 1)
    local target  = math.max(floor, rank - removes)

    for lost = rank, target + 1, -1 do
        local keyItem = xi.campaign.medal.rankToKeyItem(lost)

        if keyItem ~= nil and player:hasKeyItem(keyItem) then
            player:delKeyItem(keyItem)
        end
    end

    if target > 0 then
        player:setCharVar('CampaignMedal_Issued', os.time())
    end

    return target
end

-----------------------------------
-- Evaluation
--
-- Outcome rules:
--   score >= threshold for current rank -> PROMOTION (score spent)
--   score == 0 (no contribution at all) -> DEMOTION (score halved per retail)
--   otherwise                           -> STATUS_QUO (score kept, keeps building)
--
-- Returns result, newRank, message.
-----------------------------------
xi.campaign.medal.evaluate = function(player)
    if not xi.campaign.medal.canEvaluate(player) then
        return nil, xi.campaign.medal.getRank(player),
            'You have been evaluated too recently.'
    end

    local rank      = xi.campaign.medal.getRank(player)
    local score     = xi.campaign.medal.getScore(player)
    local threshold = xi.campaign.medal.scoreForPromotion(rank)

    player:setCharVar('CampaignMedal_LastEval', os.time())

    if score >= threshold then
        local newRank = xi.campaign.medal.promote(player)

        if newRank == nil then
            -- Already at the ladder's top: renew instead of promoting, and keep
            -- the score rather than deleting a maxed player's progress.
            xi.campaign.medal.renew(player)

            return xi.campaign.medal.result.STATUS_QUO, rank,
                'Your service is exemplary, but there is no higher honor to bestow.'
        end

        -- Spend the threshold, carry the surplus into the next evaluation.
        player:setCharVar('CampaignMedal_Score', score - threshold)

        return xi.campaign.medal.result.PROMOTION, newRank,
            string.format('Promotion! You are awarded the %s.', xi.campaign.medal.getRankName(newRank))
    end

    if score <= 0 then
        local newRank = xi.campaign.medal.demote(player, 1)

        -- Retail halves the score on demotion; at 0 that is still 0, but keep
        -- the rule explicit so it holds if demotion criteria are loosened later.
        player:setCharVar('CampaignMedal_Score', math.floor(score / 2))

        if newRank < rank then
            return xi.campaign.medal.result.DEMOTION, newRank,
                string.format('Demotion. Your rank is reduced to %s.', xi.campaign.medal.getRankName(newRank))
        end

        return xi.campaign.medal.result.STATUS_QUO, newRank,
            'Your contribution has been lacking, but your rank is protected.'
    end

    xi.campaign.medal.renew(player)

    return xi.campaign.medal.result.STATUS_QUO, rank,
        string.format('Status quo. %d of %d service points toward your next promotion.', score, threshold)
end

-----------------------------------
-- Allegiance change penalty
-- Retail: changing allegiance costs 2 medal ranks and resets evaluation progress.
-- Call this from whatever performs the nation switch.
-----------------------------------
xi.campaign.medal.onAllegianceChange = function(player)
    local newRank = xi.campaign.medal.demote(player, xi.campaign.medal.ALLEGIANCE_RANK_COST)

    player:setCharVar('CampaignMedal_Score', 0)
    player:setCharVar('CampaignMedal_LastEval', os.time())

    return newRank
end

-----------------------------------
-- Allied Tag point capacity by rank
--
-- BG-Wiki's per-minute cap table is a clean progression: 60 points/min at the
-- lowest medal, +2 per rank. Provided now so the Allied Tag scoring layer has
-- one place to read it from. Ranks above Iron Emblem are wiki-flagged
-- "Verification Needed", but the +2 pattern is regular enough to extrapolate.
-----------------------------------
xi.campaign.medal.getPointsPerMinute = function(rank)
    local effective = math.max(1, rank or 1)

    return 60 + (2 * (effective - 1))
end
