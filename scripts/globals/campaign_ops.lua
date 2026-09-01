-----------------------------------
-- Campaign Ops System
-- Manages Campaign Operations (Special Operations) for Wings of the Goddess.
-- Players accept ops from Campaign Ops NPCs, complete objectives, and earn
-- EXP + Allied Notes. Uses an Op Credit system to gate how many ops
-- a player can do per cycle.
-----------------------------------
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
-- Load op data (must come after type/status constants are defined)
-----------------------------------
require('scripts/globals/campaign_ops_data')

-----------------------------------
-- Op Credit Management
-- Players get 1 credit per Vana'diel day (max 7).
-- With Rhapsody in Mauve: 1 credit per 10 Earth minutes (max 7).
-----------------------------------
xi.campaignOps.MAX_OP_CREDITS = 7

-- Credit regeneration timing.
-- 1 Vana'diel hour = 144 real seconds (the same conversion campaign_battle.lua
-- uses for its cooldown), so a Vana'diel day is 24 * 144 = 3456 real seconds.
-- With Rhapsody in Mauve, retail refreshes a credit every 10 Earth minutes.
-- Source: https://www.bg-wiki.com/ffxi/Category:Campaign_Ops
xi.campaignOps.CREDIT_SECONDS          = 3456
xi.campaignOps.CREDIT_SECONDS_RHAPSODY = 600

-- How often this player earns one credit, in real seconds.
local function creditInterval(player)
    if player:hasKeyItem(xi.ki.RHAPSODY_IN_MAUVE) then
        return xi.campaignOps.CREDIT_SECONDS_RHAPSODY
    end

    return xi.campaignOps.CREDIT_SECONDS
end

-- Bring a player's credits up to date.
--
-- Credits accrue LAZILY: rather than a scheduler ticking every player every
-- Vana'diel day, we store the timestamp of the last accrual and settle the
-- difference whenever credits are read. This needs no hook (there is no
-- per-player onGameDay in this codebase), costs nothing for offline players,
-- and still credits time spent logged out.
local function accrueCredits(player)
    local stored = player:getCharVar('CampaignOp_Credits')
    local stamp  = player:getCharVar('CampaignOp_CreditsStamp')
    local now    = os.time()

    -- First ever read: start the clock, don't grant anything retroactively.
    if stamp == 0 then
        player:setCharVar('CampaignOp_CreditsStamp', now)

        return stored
    end

    -- Already capped: hold the clock at "now" so time does not bank up while
    -- full and then dump a pile of credits after one is spent.
    if stored >= xi.campaignOps.MAX_OP_CREDITS then
        player:setCharVar('CampaignOp_CreditsStamp', now)

        return stored
    end

    local interval = creditInterval(player)
    local gained   = math.floor((now - stamp) / interval)

    if gained <= 0 then
        return stored
    end

    local updated = math.min(stored + gained, xi.campaignOps.MAX_OP_CREDITS)

    player:setCharVar('CampaignOp_Credits', updated)

    -- Advance by whole intervals only, so the remainder carries forward
    -- instead of being discarded on every read.
    player:setCharVar('CampaignOp_CreditsStamp', stamp + (gained * interval))

    return updated
end

-- Get the player's current op credits.
-- NOTE: this settles pending regeneration first, so it may write charvars.
xi.campaignOps.getCredits = function(player)
    return accrueCredits(player)
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
        player:setCharVar('CampaignOp_CreditsStamp', os.time())
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
-- Influence Coupling (see docs/Campaign_Spec.md section 4)
--
-- DESIGN: model (a) - a completed op grants a DIRECT influence delta to the
-- player's nation in the op's target region. This is the SINGLE place influence
-- is granted for ops; per-op amounts live in campaign_ops_data.lua as data
-- (influenceReward / influenceZone) so tuning never touches this engine code.
--
-- To move to a weekly-aggregate model later, change ONLY this function.
--
-- NOTE: three different enums are in play, do not mix them up:
--   player:getCampaignAllegiance() -> 0 none, 1 SANDORIA, 2 BASTOK, 3 WINDURST
--   xi.campaign.control            -> 2 SANDORIA, 4 BASTOK, 6 WINDURST, 8 BEASTMEN
--   xi.campaign.army               -> 0 SANDORIA, 1 BASTOK, 2 WINDURST (+3..6 beastmen)
-- CampaignSetInfluence() expects an xi.campaign.army value.
-----------------------------------

-- Maps a player's campaign allegiance to the army whose influence should grow.
-- Resolved at CALL time, not load time: campaign_ops.lua does not require
-- campaign.lua, so xi.campaign.army may not exist yet while this file loads.
xi.campaignOps.getArmyForAllegiance = function(allegiance)
    local allegianceToArmy =
    {
        [1] = xi.campaign.army.SANDORIA,
        [2] = xi.campaign.army.BASTOK,
        [3] = xi.campaign.army.WINDURST,
    }

    return allegianceToArmy[allegiance]
end

-- Fallback delta for an op that opts into influence without naming an amount.
-- Kept deliberately small so Campaign Battle stays the dominant real-time lever.
xi.campaignOps.DEFAULT_OP_INFLUENCE = 5

-- Grant the completing player's nation influence in the op's region.
-- Returns true if influence was applied, false when the op grants none.
xi.campaignOps.applyOpInfluence = function(player, opData)
    -- Ops opt in: no influenceReward field means this op does not move the bar.
    if opData.influenceReward == nil then
        return false
    end

    local amount = opData.influenceReward

    if amount == true then
        amount = xi.campaignOps.DEFAULT_OP_INFLUENCE
    end

    if type(amount) ~= 'number' or amount <= 0 then
        return false
    end

    -- Explicit influenceZone wins; otherwise infer the region the op acted on.
    local zoneId = opData.influenceZone or opData.targetZone or opData.deliveryZone

    if zoneId == nil then
        printf('[CampaignOps] Op "%s" has influenceReward but no resolvable zone; skipping influence.',
            opData.name or '?')

        return false
    end

    local army = xi.campaignOps.getArmyForAllegiance(player:getCampaignAllegiance())

    if army == nil then
        return false
    end

    CampaignSetInfluence(zoneId, army, amount)

    printf('[CampaignOps] Influence +%d for army %d in zone %d (op "%s")',
        amount, army, zoneId, opData.name or '?')

    return true
end

-----------------------------------
-- Fortification Adjustment
--
-- CampaignSetFortification() SETS an absolute value (the world server clamps it
-- to 0..max_fortifications). A caller that means "+30" must therefore read the
-- current value first -- passing a bare delta OVERWRITES the zone's
-- fortifications with that small number, which reduces them instead.
-----------------------------------

-- Read a zone's current fortification points from live campaign state.
local function getZoneFortification(zoneId)
    -- Resolved at call time: campaign_ops does not require campaign_battle, so
    -- the map may not exist yet while this file is loading.
    local zoneMap = xi.campaignBattle ~= nil and xi.campaignBattle.zoneToCampaignId or nil

    if zoneMap == nil then
        return nil
    end

    local campaignId = zoneMap[zoneId]

    if campaignId == nil then
        return nil
    end

    local status = GetCampaignStatus()

    if status then
        for _, z in ipairs(status) do
            if z.zoneId == campaignId then
                return z.fort
            end
        end
    end

    return nil
end

-- Add (delta > 0) or remove (delta < 0) fortification points for a zone.
-- Returns true when the change was applied.
xi.campaignOps.addFortification = function(zoneId, delta)
    local current = getZoneFortification(zoneId)

    if current == nil then
        printf('[CampaignOps] Cannot adjust fortifications for zone %d: no live campaign state.', zoneId)

        return false
    end

    local target = math.max(0, current + delta)

    CampaignSetFortification(zoneId, target)

    printf('[CampaignOps] Zone %d fortifications %d -> %d (delta %d)', zoneId, current, target, delta)

    return true
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

    -- Apply the op's influence delta (model (a), see Influence Coupling above).
    -- Runs before onComplete so a per-op hook can still layer extra effects.
    xi.campaignOps.applyOpInfluence(player, opData)

    -- Feed medal evaluation score. Allied Notes are roughly half of campaign
    -- points on retail, so the notes reward is a reasonable contribution proxy
    -- until the Allied Tag scoring layer exists.
    -- Guarded rather than require()d to avoid a load-order dependency.
    if xi.campaign ~= nil and xi.campaign.medal ~= nil then
        xi.campaign.medal.addScore(player, notesReward)
    end

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
    if
        opData.opType ~= xi.campaignOps.type.RESOURCE_PROCUREMENT and
        opData.opType ~= xi.campaignOps.type.SUPPLY_MANUFACTURE
    then
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
        if
            opData.nation == nation and
            (opType == nil or opData.opType == opType)
        then
            table.insert(available, { id = opId, data = opData })
        end
    end

    -- Sort by ID for consistent ordering
    table.sort(available, function(a, b) return a.id < b.id end)
    return available
end

-----------------------------------
-- Credit Regeneration
--
-- Credits regenerate LAZILY inside getCredits() (see accrueCredits above), so
-- nothing needs to be scheduled. This entry point is kept only for callers that
-- want to force a settle -- e.g. a GM command or a login hook.
-----------------------------------
xi.campaignOps.onNewVanaDay = function(player)
    return xi.campaignOps.getCredits(player)
end

-----------------------------------
-- Mob Death Tracking for kill-based ops
--
-- Dispatched from xi.mob.onMobDeathEx (scripts/globals/mobs.lua), which the core
-- calls once per alliance member in the killer's zone.
--
-- isKiller is accepted but deliberately NOT required: on retail, Campaign credit
-- is recorded individually and does not need the killing blow, so every
-- participating member with this op active gets progress.
-- Source: https://www.bg-wiki.com/ffxi/Campaign_Battle
-----------------------------------
xi.campaignOps.onMobDeath = function(mob, player, isKiller)
    if player == nil or mob == nil then
        return
    end

    local opId   = xi.campaignOps.getActiveOp(player)
    local opData = xi.campaignOps.getOpData(opId)

    if not opData then
        return
    end

    -- Only kill-based op types
    if
        opData.opType ~= xi.campaignOps.type.SECURITY and
        opData.opType ~= xi.campaignOps.type.OFFENSIVE and
        opData.opType ~= xi.campaignOps.type.DEFENSIVE and
        opData.opType ~= xi.campaignOps.type.MILITARY_TRAINING
    then
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

        for _, needle in ipairs(opData.targetMobs) do
            -- plain=true: match literal text, NOT a Lua pattern. Family names
            -- containing '-' or '.' would otherwise be interpreted as pattern
            -- metacharacters and silently fail to match.
            if string.find(mobName, needle, 1, true) then
                matches = true
                break
            end
        end

        if not matches then
            return
        end
    end

    -- Default to 1 when an op omits targetCount, matching isObjectiveMet().
    -- Without this, a data entry missing the field would error on comparison
    -- inside a hook that runs on every mob death.
    local targetCount = opData.targetCount or 1

    -- Already complete? Don't count more.
    local progress = xi.campaignOps.getProgress(player)

    if progress >= targetCount then
        return
    end

    -- Increment progress
    progress = progress + 1
    xi.campaignOps.setProgress(player, progress)

    player:printToPlayer(string.format('[Campaign Op] Target defeated: %d/%d', progress, targetCount))

    if progress >= targetCount then
        player:printToPlayer('[Campaign Op] Objective complete! Report to the Campaign Ops NPC.')
    end
end
