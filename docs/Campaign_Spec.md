# Campaign System — Design & Implementation Spec

> **Status:** Living document. Combines (1) an audit of the current `FFXI_TestServer` implementation,
> (2) a game-mechanics reference derived from BG-Wiki, and (3) design decisions for the parts the
> game never publicly documented.
>
> **Critical framing:** Upstream **LandSandBoat/server has NO Campaign system.** The entire Campaign
> feature set in this repo is original work. **This fork is the reference implementation.** There is
> no upstream Campaign code to cross-reference or merge from. Monitor upstream only for *core engine*
> changes (Lua API, dynamic-entity spawning, world↔map IPC) that could conflict with Campaign code on merge.

---

## 1. Architecture (as built)

Two-process design:

- **World server** (`src/world/campaign_system.cpp`) — authoritative tally / decay / zone-control logic + DB. Talks to map servers over IPC.
- **Map server** (`src/map/campaign_system.cpp` + `campaign_handler.cpp`) — per-zone cache, sends GM requests to world, pushes influence packets (`0x071`) to players.
- **Lua gameplay** (`scripts/globals/campaign*.lua`) — reaches C++ through a small global binding surface.

### Lua ↔ C++ binding surface (complete)
Globals (registered `src/map/lua/luautils.cpp:267–274`):
`CampaignTally()`, `CampaignUpdate()`, `CampaignRefresh()`, `CampaignSetInfluence(zoneId, army, amount)`,
`CampaignSetFortification(zoneId, amount)`, `CampaignSetZoneControl(zoneId, nation)`,
`CampaignSetBattleStatus(zoneId, status)`, `GetCampaignStatus()`.
Entity methods (`src/map/lua/lua_base_entity.cpp`): `player:getCampaignAllegiance()`, `targ:setCampaignAllegiance(a)`.

---

## 2. Implementation state (audit)

### Working
- **Region model** — 26 regions (`sql/campaign_map.sql`), 7 armies (`sql/campaign_nation.sql`); adjacency + city/stronghold immunity hardcoded (`src/world/campaign_system.cpp:39`).
- **Influence engine** — weekly `runTally` (`:150`) → `resolveZoneControl` (`:210`, flips on `FLIP_THRESHOLD`) → `updateNationStats` (`:260`); decay `runUpdate` (`:230`); add/clamp over IPC (`handleMessage`, `:80`).
- **Campaign Battle** — full lifecycle in `scripts/globals/campaign_battle.lua`; per-zone data for 12 zones in `campaign_battle_data.lua`; `onGameHour` wired into all 12 battle-zone `Zone.lua` files. Auto-starts.
- **Sigil + Allied Notes shop** — working (`scripts/globals/campaign.lua`).
- **GM control** — `scripts/commands/campaign.lua`.

### Campaign Ops — engine complete, ~10% wired
`scripts/globals/campaign_ops.lua` is a full framework: credits (max 7), accept/complete/cancel,
`onMobDeath` + `handleTrade` progress drivers, EXP + Allied Notes rewards. **Gaps:**
- Wired to **one NPC only** (Bastok's Hieronymus). San d'Oria (Rasdinice) & Windurst (Emhi Tchaoryo) not wired.
- Only **8 ops** exist (Bastok 1001–1008); San d'Oria (2000s) & Windurst (3000s) empty.
- ~~`onMobDeath` **not called by any mob**~~ **WIRED** — dispatched from `xi.mob.onMobDeathEx`
  (`scripts/globals/mobs.lua`), the core's global per-alliance-member death hook. Credit goes to every
  participating member in the killer's zone (retail does not require the killing blow), not just the killer.
- ~~No Op Credit regeneration~~ **DONE (lazy accrual).** `getCredits()` settles pending regeneration on
  read via `accrueCredits()`: it stores `CampaignOp_CreditsStamp` and grants one credit per elapsed
  interval (3456s = one Vana'diel day; 600s with Rhapsody in Mauve). No scheduler needed — there is no
  per-player `onGameDay` hook in this codebase — and offline time still counts. The clock is pinned to
  "now" while at the 7 cap so time cannot bank up and dump credits after one is spent.
- **Fortification ops fixed.** Ops 1001/1006 called `CampaignSetFortification(88, 50/30)` with
  "add/restore" comments, but that function SETS an absolute value — against North Gustaberg's max of
  300 those ops *reduced* fortifications. They now use `xi.campaignOps.addFortification(zone, delta)`,
  which reads current state first. Magic zone id 88 replaced with `xi.zone.NORTH_GUSTABERG_S`.
- **`influenceReward` set** on ops 1002 (5), 1003 (6), 1005 (10), 1006 (8), 1007 (5), 1008 (3).
  Ops 1001/1004 deliberately grant none — supply/manufacture feeds fortifications, not influence.
- No timer regenerates Op Credits per Vana'day.

### Spec-only (unbuilt)
Allied Tags / performance assessment, Tactical Assessment, Campaign Medals evaluation, War Conditions /
Battle Strategies, weekly policy cycle. Influence is effectively **GM-fed** until a tag/assessment layer exists.

---

## 3. Game mechanics reference (BG-Wiki)

Sources: [Category:Campaign](https://www.bg-wiki.com/ffxi/Category:Campaign),
[Campaign Ops](https://www.bg-wiki.com/ffxi/Category:Campaign_Ops),
[Campaign Battle](https://www.bg-wiki.com/ffxi/Campaign_Battle),
[How to Gain Influence](https://www.bg-wiki.com/ffxi/How_to_Gain_Influence_in_Campaign),
[Campaign Point Calculation](https://www.bg-wiki.com/ffxi/Campaign_Point_Calculation),
[Allied Notes](https://www.bg-wiki.com/ffxi/Allied_Notes).

### High level
WotG region-control war: Allied Forces (San d'Oria / Bastok / Windurst) vs Beastman Confederate across
`(S)` zones. Weekly loop: Determine Policy → Implement Strategy (battles, ops, assessments) → Tactical
Assessment → **Tally** (once/week, JST midnight Sun→Mon) assigning each area a Dominant/Minor force.

### Campaign Ops
- **Op Credits** gate participation: 1 per Vana'diel day, max 7 stored; Rhapsody in Mauve → 1 per 10 Earth min. Under lvl 10 = no EXP but still Allied Notes.
- Nation NPCs: Rasdinice (Southern San d'Oria S), Hieronymus (Bastok Markets S), Emhi Tchaoryo (Windurst Waters S). Quartermaster/Adjutant for resource/manufacture ops. Some ops run in instances (Everbloom Hollow / Ruhotz Silvermines / Ghoyu's Reverie).
- Faction join quests: Steamed Rams (S), The Fighting Fourth (B), Snake on the Plains (W).
- **8 categories:** Resource procurement, Supply transport, Security, Supply manufacture, Offensive, Defensive, Intel, Military training. Tiers I→IV/V; each tier unlocks after prior ×16, or gated by medal rank / control state.
- Reward: EXP on objective complete; Allied Notes on return to issuing NPC. Leaving an instance early = failure.

### Influence & Allied Notes economy
- **Direct influence = Campaign Battle kills.** Kill flagged troupes in a beastman area → bar shifts within minutes. "A handful of troupes" flips a fully-beastman area. Allied influence **decays over time**. Weekly tally: highest influence wins the area's fortification.
- Adjacency: beastmen taking a zone next to a city can sack the city; allies holding a zone next to a beastman stronghold expose it to battles.
- **Allied Notes** = Campaign currency (like Conquest Points). Earned via battle assessment (Notes ≈ 50% of EXP), ops completion, chocobo digging. Spent at Campaign Officials (cross-nation markup), teleports, Sigil, 300 AN to change allegiance. Vendor price tables and control gates (e.g. Allied Ring needs Throne Room (S)) are in the wiki.
- **Medals:** 5 families × 4 tiers (Ribbons→Stars→Emblems→Wings→Medals); evaluated by a Campaign Evaluation Official; 120h cooldown (1h w/ Rhapsody); 30-day validity; allegiance change costs 2 ranks.

### Campaign Battle scoring (concrete)
Per-action points (buff self 20/cap150, buff other 10/cap300, debuff 15/cap300, auto-attack 5/cap150,
crit 10/cap50, skillchain 20/cap300, phys & magic dmg 10% of dmg, cure 10%/cap500, death −30).
Per-minute cap by rank = `60 + 2×rank_index`. Total EXP floored to nearest 5; AN not rounded (≈50% of EXP).
Level penalty: 1–15 → 20%, 16–30 → 40%, 31–45 → 60%, 46–60 → 80%, 61–75 → 100%. Default tag cap 600 EXP / 300 AN.

---

## 4. Design decisions (OURS to make — no upstream, wiki silent)

The wiki gives **no number** for how completing an Op changes a region's influence. In retail there are
effectively **two systems**: Campaign Battle moves the influence bar in real time; Campaign Ops feed the
weekly aggregate (completion counts + assessments) shaping next-week strategy, prosperity, and op availability.
Since we are the reference implementation, we define the coupling:

- **[DECIDED — model (a)] Ops grant a DIRECT per-op influence delta.** On successful op completion, apply an
  influence gain for the player's nation to the op's target region. Chosen over (b) weekly-aggregate-only and
  (c) hybrid because a direct delta is **immediately observable in-game** — we can watch the influence bar move
  while testing and tune the constants from evidence.
  - *Rejected for now:* (b) weekly aggregate only — closest to retail, but invisible during development;
    (c) hybrid — more faithful, but adds a second tuning surface before we understand the first.
  - **Reversibility requirement:** keep this cheap to change later.
    1. Store the amount as **data**, not logic: an `influenceReward` (and optional `influenceZone`) field per op
       entry in `campaign_ops_data.lua`, so tuning never touches engine code.
    2. Route every grant through **one helper** (e.g. `xi.campaignOps.applyOpInfluence(player, opData)`) called
       from `completeOp`. That helper is the single swap point — moving to (b) or (c) later means changing one
       function, not every op.
    3. Default to a **small** delta relative to battle kills, so Campaign Battle stays the dominant real-time
       lever (matching retail's feel) while ops still register.

Still open:

- **[DECIDE] Influence scale/units, per-kill increment, decay rate, control threshold.** Wiki gives none.
  Pick concrete constants and record them here once chosen. (Needed to size the op delta sensibly.)
- **[DECIDE] Fortifications & Resources formulas** (wiki: numeric but no scale).
- **[DECIDE] Whether to build the Allied Tag / assessment layer** (required before player combat can feed influence without GM commands).

---

## 5. Recommended build order

1. **Wire the existing Ops engine** (lowest risk — engine already written).
   - [x] `onMobDeath` — dispatched from `xi.mob.onMobDeathEx` in `scripts/globals/mobs.lua`.
         Guarded with a nil check rather than a `require` to avoid a global load-order dependency.
   - [ ] `onTrade` — only Hieronymus routes trades today; other Ops NPCs need it.
   - [ ] San d'Oria (Rasdinice) + Windurst (Emhi Tchaoryo) Ops NPCs.
   - [ ] Per-Vana'day Op Credit regen timer calling `xi.campaignOps.onNewVanaDay`.
2. **Author Ops content** for all 3 nations from the §3 taxonomy (tier ×16 unlocks).
3. **Ops→influence coupling — model (a) MECHANISM IMPLEMENTED.**
   `xi.campaignOps.applyOpInfluence()` in `scripts/globals/campaign_ops.lua` is the single grant path,
   called from `completeOp()`; per-op amounts are data (`influenceReward` / `influenceZone`) in
   `campaign_ops_data.lua`. Op 1005 (Smokescreen I) migrated off its ad-hoc `CampaignSetInfluence` call.
   *Remaining:* set `influenceReward` on the other ops, and pick the influence constants in §4.
4. **Fortification combat — IMPLEMENTED.** A zone has ONE fort, presented as several
   attackable target points (retail: 4). Target points are passive MOBs, not NPCs.
   - `spawnFortifications()` resolves the fort's anchor (`fortPosition`, or `fortPositions[1]`
     for existing data) and places a target point at each `fortTargetOffsets` entry — default
     4 points in a 3-yalm cross. Each is `xi.objType.MOB` with allegiance following zone
     control (beastman-held → players attack; allied-held → beastmen attack). They are inert:
     no move, no aggro, no auto-attack, no casting, no abilities, no drops, no exp.
   - HP scale: `FORT_HP_PER_POINT` (20) HP per region fortification point, seeded from
     `GetCampaignStatus().fort`, then **split evenly across the target points** — so razing the
     fort costs the same total damage regardless of how many points it presents.
   - `getFortificationHp()` derives `battle.fortHp` by summing live target-point HP — the mobs are
     the source of truth, so no damage hook is needed.
   - `endBattle()` writes the surviving points back with `CampaignSetFortification` (absolute set,
     clamped in the world server). A battle bootstrapped because the region reported 0 does NOT
     persist, so fortifications are never invented.
   - `checkBattleEnd()` ends the battle once every target point is down, reporting the victor by
     fort ownership.
   *Remaining:* `GetCampaignStatus()` still does not expose `max_fortifications` to Lua (would need
   a C++ field + rebuild); attacking a target point does not yet award the wiki's 20 campaign
   points (max 200) — that belongs with the Allied Tag scoring layer.

5. **(Optional, larger) Allied Tag / assessment layer** so battles feed influence without GM commands.

7. **Medal reward system — IMPLEMENTED.** `scripts/globals/campaign_medals.lua`, built ON TOP of the
   existing 20-key-item ladder (xi.ki 924–943: Ribbons/Stars/Emblems/Wings/Medals ×4), not a parallel rank.
   - `getRank()` = highest medal KI held (0 = none). Authoritative; `campaign.lua`'s `getMedalRank()` counts
     held KIs and agrees while medals are awarded cumulatively, which `promote()` does.
   - `evaluate()` returns Promotion / Status quo / Demotion: score ≥ `scoreForPromotion(rank)` promotes
     (surplus carries forward), score 0 demotes (never below `getMinimumRank()`, currently 0), else holds.
   - Validity: a medal lasts 30 Earth days (`CampaignMedal_Issued`); `isValid()` gates medal services.
   - Eval cooldown: 120 Earth hours, 1 hour with Rhapsody in Mauve.
   - `onAllegianceChange()` strips 2 ranks and resets score+eval (retail rule); call from the nation switch.
   - `getPointsPerMinute(rank)` = 60 + 2×(rank−1), the future Allied Tag capacity table.
   - Op completion feeds `addScore(notesReward)` (guarded, no load-order dependency).
   - GM: `!campaign medal [evaluate|force|promote|demote|score|renew]`.
   *Tunable constants are OURS* (§4) — the wiki never published promotion thresholds.
   *Remaining:* `getMinimumRank()` returns 0 until the WotG-mission → rank-floor map is wired;
   `onAllegianceChange()` has no caller yet (nothing performs a nation switch in-code).

6. **ServerManager (Python UI) integration — IMPLEMENTED.**
   The MAP server owns battles but has no HTTP surface (only the WORLD server does, and its
   only campaign write route is `POST /api/campaign/refresh`). So the UI uses the DB-backed
   `server_variables` table as a control/telemetry channel — `GetServerVar()` issues a fresh
   SELECT per call, so an externally written row is visible to Lua with no C++ change.
   - **Start/Stop battle:** UI upserts `CampaignBattleReq_<zoneId>` (1 = start, 2 = stop);
     `xi.campaignBattle.onGameHour` polls it, consumes it (clears to 0), and bypasses the
     cooldown / start-hour / random gates. Latency: up to one Vana'diel hour (~144s).
   - **Fort health:** Lua publishes `CampaignFortHp_<zoneId>` / `CampaignFortMax_<zoneId>` on
     spawn, on each target point destroyed, and zeroes them on battle end. The UI joins these
     against `campaign_map` for persistent region fort values.
   - **Campaign Ops monitor:** read from `char_vars` (`CampaignOp_ActiveOp` / `_Progress` /
     `_Credits`) pivoted to one row per character, joined to `chars.charname`.
   - Battle zones (14): 81, 82, 83, 84, 88, 89, 90, 91, 95, 96, 97, 98, 136, 137 — the keys of
     `xi.campaignBattle.zoneData`; all 14 call `onGameHour` from their `Zone.lua`.
   *Fixed along the way:* `HTTPClient.trigger_campaign_refresh()` posted to `/api/campaign/refresh`
   on a base URL already ending in `/api`, producing `/api/api/...` (404).
   *Remaining:* Start/Stop is a queued request, not instant — an immediate path would need a
   world→map IPC message plus a C++ HTTP route and a rebuild.
