-----------------------------------
-- Campaign Ops Data
-- Op definitions for all Campaign Operations.
-- Each op is keyed by a unique numeric ID.
--
-- Template Fields:
--   name              : Display name of the operation
--   opType            : xi.campaignOps.type enum
--   nation            : Which nation offers this op (xi.campaign.control value)
--   requiredMedalRank : Minimum medal rank to accept (0 = Bronze Ribbon, nil = none)
--   description       : Short text description for the player
--   targetCount       : Number of times objective must be met (e.g., 1 trade = 1 count)
--   tradeItems        : For procurement/manufacture ops: items to trade (npcUtil format)
--   expReward         : EXP granted on completion
--   notesReward       : Allied Notes granted on completion
--   onComplete        : Optional function called on completion for side effects
-----------------------------------
require('scripts/globals/campaign')
-----------------------------------
xi = xi or {}
xi.campaignOps = xi.campaignOps or {}

-----------------------------------
-- Op Definitions
-- IDs: 1000-1099 = Bastok, 2000-2099 = San d'Oria, 3000-3099 = Windurst
-----------------------------------
xi.campaignOps.ops =
{
    -----------------------------------
    -- BASTOK OPS (1000-1099)
    -----------------------------------

    -----------------------------------------------------------------------
    -- 1. Resource Procurement: Stock and Awe I
    --    Deliver 12x Copper Ore to contribute to Bastok's war supplies.
    --    On completion, adds resources to Bastok-controlled zones.
    -----------------------------------------------------------------------
    [1001] =
    {
        name              = 'Stock and Awe I',
        opType            = xi.campaignOps.type.RESOURCE_PROCUREMENT,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 1,
        description       = 'Deliver 12 chunks of copper ore to bolster supply reserves.',
        targetCount       = 1, -- 1 successful trade of the full set
        tradeItems        = { { xi.item.CHUNK_OF_COPPER_ORE, 12 } },
        expReward         = 500,
        notesReward       = 200,

        onComplete = function(player, opData)
            -- Supply ops feed FORTIFICATIONS rather than influence.
            -- Must go through addFortification: CampaignSetFortification sets an
            -- absolute value, so a bare +50 would overwrite the zone's total.
            xi.campaignOps.addFortification(xi.zone.NORTH_GUSTABERG_S, 50)
            player:printToPlayer('Supply reserves bolstered. Nation resources increased.')
        end,
    },

    -----------------------------------------------------------------------
    -- 2. Supply Transport: Vanguard I
    --    Travel to North Gustaberg [S] and speak to the Campaign NPC there
    --    to deliver supplies. Progress is set to 1 when the player talks
    --    to the field NPC (handled via a zone NPC script check).
    --    For now, players can set progress via the field or GM command.
    -----------------------------------------------------------------------
    [1002] =
    {
        name              = 'Vanguard I',
        opType            = xi.campaignOps.type.SUPPLY_TRANSPORT,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 1,
        description       = 'Travel to North Gustaberg [S] and deliver supplies to the field officer.',
        targetCount       = 1,
        -- Supply transport: player must reach the destination zone and interact
        -- with the Campaign NPC there. The field NPC checks for this op and
        -- sets progress to 1. For testing, use: !campaign ops progress 1
        deliveryZone      = xi.zone.NORTH_GUSTABERG_S,
        expReward         = 600,
        notesReward       = 250,
        -- Reinforcing the front nudges the region our way. Resolved against
        -- deliveryZone by applyOpInfluence().
        influenceReward   = 5,

        onComplete = function(player, opData)
            player:printToPlayer('Supplies delivered successfully. Morale boosted.')
        end,
    },

    -----------------------------------------------------------------------
    -- 3. Security: Streetsweeper I
    --    Defeat 5 designated enemies in Bastok Markets [S].
    --    Uses a kill-count tracker similar to Dominion Ops.
    -----------------------------------------------------------------------
    [1003] =
    {
        name              = 'Streetsweeper I',
        opType            = xi.campaignOps.type.SECURITY,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 1,
        description       = 'Eliminate 5 suspicious creatures lurking near the city.',
        targetCount       = 5,
        -- Kill tracking is handled via mob death listeners
        targetZone        = xi.zone.NORTH_GUSTABERG_S,
        targetMobs        = { 'Quadav' }, -- family name filter
        expReward         = 700,
        notesReward       = 300,
        influenceReward   = 6,

        onComplete = function(player, opData)
            player:printToPlayer('Area secured. Threats neutralized.')
        end,
    },

    -----------------------------------------------------------------------
    -- 4. Supply Manufacture: Crystal Fist I
    --    Trade 8x Fire Crystals to contribute to munitions production.
    -----------------------------------------------------------------------
    [1004] =
    {
        name              = 'Crystal Fist I',
        opType            = xi.campaignOps.type.SUPPLY_MANUFACTURE,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 1,
        description       = 'Deliver 8 fire crystals to support munitions crafting.',
        targetCount       = 1,
        tradeItems        = { { xi.item.FIRE_CRYSTAL, 8 } },
        expReward         = 500,
        notesReward       = 200,
        -- No influenceReward by design: manufacture/procurement ops (1001, 1004)
        -- feed production and fortifications, not the region's influence bar.

        onComplete = function(player, opData)
            player:printToPlayer('Crystals delivered to the forge. Production continues.')
        end,
    },

    -----------------------------------------------------------------------
    -- 5. Offensive Operations: Smokescreen I
    --    Defeat 3 beastmen in Pashhow Marshlands [S] to disrupt supply lines.
    -----------------------------------------------------------------------
    [1005] =
    {
        name              = 'Smokescreen I',
        opType            = xi.campaignOps.type.OFFENSIVE,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 2,
        description       = 'Ambush 3 beastman troops in Pashhow Marshlands [S].',
        targetCount       = 3,
        targetZone        = xi.zone.PASHHOW_MARSHLANDS_S,
        targetMobs        = { 'Quadav' },
        expReward         = 800,
        notesReward       = 350,
        -- Offensive op: disrupting supply lines shifts the region toward us.
        -- Applied by xi.campaignOps.applyOpInfluence() against targetZone.
        influenceReward   = 10,

        onComplete = function(player, opData)
            player:printToPlayer('Enemy supply line disrupted. Bastok influence grows.')
        end,
    },

    -----------------------------------------------------------------------
    -- 6. Defensive Operations: Aegis Scream I
    --    Defeat 4 beastmen attacking North Gustaberg [S] fortifications.
    -----------------------------------------------------------------------
    [1006] =
    {
        name              = 'Aegis Scream I',
        opType            = xi.campaignOps.type.DEFENSIVE,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 2,
        description       = 'Defend North Gustaberg [S] from 4 beastman attackers.',
        targetCount       = 4,
        targetZone        = xi.zone.NORTH_GUSTABERG_S,
        targetMobs        = { 'Quadav' },
        expReward         = 800,
        notesReward       = 350,
        -- Holding the line keeps the region ours.
        influenceReward   = 8,

        onComplete = function(player, opData)
            -- Restore fortifications (+30). addFortification reads the current
            -- value first; CampaignSetFortification alone would SET it to 30.
            xi.campaignOps.addFortification(xi.zone.NORTH_GUSTABERG_S, 30)
            player:printToPlayer('Fortifications held. Defenses restored.')
        end,
    },

    -----------------------------------------------------------------------
    -- 7. Intel Gathering: Hawk Eye I
    --    Travel to Pashhow Marshlands [S] and examine a specified location
    --    to gather intelligence. Uses a zone-in + trigger area check.
    -----------------------------------------------------------------------
    [1007] =
    {
        name              = 'Hawk Eye I',
        opType            = xi.campaignOps.type.INTEL_GATHERING,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 1,
        description       = 'Scout enemy positions in Pashhow Marshlands [S].',
        targetCount       = 1,
        -- Intel ops: player must reach a location and interact with a ??? NPC
        targetZone        = xi.zone.PASHHOW_MARSHLANDS_S,
        expReward         = 600,
        notesReward       = 250,
        influenceReward   = 5,

        onComplete = function(player, opData)
            player:printToPlayer('Intelligence gathered. Report filed.')
        end,
    },

    -----------------------------------------------------------------------
    -- 8. Military Training: Brave Dawn I
    --    Defeat 3 training dummies (any mob in North Gustaberg [S]).
    --    Represents training new recruits in combat.
    -----------------------------------------------------------------------
    [1008] =
    {
        name              = 'Brave Dawn I',
        opType            = xi.campaignOps.type.MILITARY_TRAINING,
        nation            = xi.campaign.control.BASTOK,
        requiredMedalRank = 1,
        description       = 'Assist in training recruits by defeating 3 enemies.',
        targetCount       = 3,
        targetZone        = xi.zone.NORTH_GUSTABERG_S,
        targetMobs        = {}, -- Any mob in the zone counts
        expReward         = 500,
        notesReward       = 200,
        -- Training is rear-echelon work: real but minor war contribution.
        influenceReward   = 3,

        onComplete = function(player, opData)
            player:printToPlayer('Training session complete. Recruits show improvement.')
        end,
    },
}
