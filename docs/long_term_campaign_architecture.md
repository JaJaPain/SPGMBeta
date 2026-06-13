# Long-Term Campaign Architecture

## Purpose

This is the living master plan for turning the current SpaceGame prototype into
an ongoing, procedurally authored campaign. It records approved design rules,
technical boundaries, implementation order, and decisions that can wait until
their dependent systems are ready.

The goal is not to generate everything at runtime with one prompt. The goal is
to let a local LLM direct an evolving story while deterministic game systems
protect continuity, performance, balance, saves, and player freedom.

## Hardware And Model Budget

- The target consumer GPU has **8 GB of VRAM**.
- The complete game must remain usable within that target, including gameplay
  rendering and local AI workloads.
- AI services may not assume that the story LLM, text-to-image model, vision
  reviewer, and every supporting model are resident in VRAM simultaneously.
- Background generation must use a model scheduler that loads, unloads, or
  swaps models by job type.
- Interactive gameplay receives priority over background generation.
- Asset jobs may pause between stages when the game needs GPU memory.
- Every model integration requires measured peak VRAM, system RAM, load time,
  generation time, output quality, and license compatibility.
- Open-source supporting models may be added when they provide a needed
  capability and fit the total 8 GB target.
- CPU or system-RAM fallback is acceptable for non-interactive jobs when it
  prevents gameplay stalls, even if generation takes longer.
- Quantization, reduced image resolution, staged upscaling, and cached outputs
  are preferred to raising the minimum hardware requirement.

The initial performance budget should reserve most VRAM for Godot rendering and
load only one major AI model at a time. Exact allocations must be based on
measurements from representative gameplay scenes rather than advertised model
sizes.

## Approved Experience Rules

### The Player

- The player has no canonical name, gender, body, or spoken voice.
- Kaelen calls the player **Shiny**.
- Everyone else calls the player **Indy**, meaning an independent pilot.
- "Indy" may also be used for other unaffiliated pilots.
- Shiny begins in the handcrafted first system with the existing ship.
- The game does not explain where Shiny came from or how the ship was acquired.

### Campaign Shape

- The first system, its principal locations, and its starting cast are
  handcrafted and consistent between campaigns.
- The central story is newly generated for each campaign.
- The campaign has no required final ending. Story arcs may end, overlap, and
  lead to new arcs for as long as Shiny remains alive and the player continues.
- The player may ignore the main story indefinitely to trade, mine, fight,
  improve the ship, build relationships, or remain in a favored system.
- Story pressure should remind and tempt the player, not force departure.
- The tone may vary between space opera, political drama, adventure, and
  mystery, but all generated content must remain PG-13.

### Kaelen

- Kaelen can never be killed, permanently removed, or made unavailable by the
  generated story.
- Kaelen is the only character guaranteed to appear at every system's main
  station.
- Her appearance and presentation remain consistent for now.
- Her method of travel is never confirmed. She mocks or deflects direct
  questions.
- She knows a great deal, but she cannot see the future and can be surprised.
- She originates from an unknown final system and is observing earlier systems
  for an unrevealed purpose.
- Kaelen's deals are the primary story mechanism for revealing gates and
  encouraging travel.
- Kaelen may retain faint memories of discarded save timelines. These references
  must be rare, funny or unsettling, and never mechanically punish reloading.

### World Permanence

- Generated systems, gate routes, factions, NPC identities, ship designs,
  portraits, and established canon are permanent for that campaign.
- Generated assets are cached and referenced by stable IDs and generation
  seeds.
- Loading an earlier checkpoint rewinds mutable gameplay state but does not
  regenerate an already created place into a different place.
- Information learned after the loaded checkpoint may become hidden from the
  player UI again, while the cached physical content remains available to the
  campaign.
- Major NPCs connected to the player cannot die off-screen. Their deaths require
  a storyline in which the player is involved.

### Systems And Travel

- Systems are places to inhabit, not levels to clear.
- Gate locations should not be revealed immediately after arrival.
- The player should have time to learn local factions, work, trade, form
  relationships, and become involved before Kaelen offers a path onward.
- The map must eventually branch. At least some systems offer two viable onward
  routes so one disastrous relationship or region cannot trap the campaign.
- All offered destinations must be fully generated before the player can choose
  them.
- Temporary gate damage, blockades, missing coordinates, or political access
  requirements may delay travel when justified by existing game rules.
- The current gate implementation remains the default travel model.
- Rare stories may introduce unexplained ships that apparently travel without
  gates. The game does not need to explain how.
- Planets remain spaceborne landmarks and destinations. Surface landing is out
  of scope.

### Factions And Reputation

- Returning factions carry their established opinion of Indy into new systems.
- New factions form their own opinion unless information plausibly reaches them.
- Reputation may spread through shared organizations, allies, enemies, news, or
  direct communication.
- Gaining high reputation with one faction should concern its enemies.
- A player should not be able to become universally loved without difficult,
  exceptional choices and tradeoffs.
- Systems may change control, experience shortages, blockades, coups, or wars
  after long absences.
- Political change must use in-game time and believable rates. A brief return
  trip cannot completely transform a system without a specific active event.

### Missions

- Abandoning a mission removes it and causes a small reputation loss, normally
  2-3 points.
- Accepted untimed missions remain available until completed or abandoned.
- Timed missions use in-game universal time, never wall-clock time.
- A minor NPC becomes narratively major when Kaelen or a significant story arc
  starts routing important work through that character.
- The long-term mission system must support multiple active missions rather than
  the prototype's single active quest.

### Economy And Return Value

- Main stations provide persistent storage.
- Trading should support profitable regional price differences.
- Repeated buying and selling changes local supply and demand so a single route
  cannot produce infinite risk-free profit.
- Old systems remain useful through allies, stored goods, rare stock, local
  opportunities, faction rewards, expensive high-reputation upgrades, and
  Kaelen's callbacks to previous characters.
- Economy controls should prevent mechanical exploits without punishing
  legitimate planning and merchant play.

## Core Architecture Principle

The LLM is a **story planner and writer**, not the authoritative game engine.

The LLM may propose:

- Themes, mysteries, conflicts, and story arcs.
- Faction and NPC concepts.
- Connections between established people and events.
- Mission intent selected from supported mission mechanics.
- Dialogue, rumors, descriptions, summaries, and eulogies.
- Candidate future systems and reasons to travel there.

Deterministic code must own:

- Stable IDs, schemas, saves, and migration.
- Whether an action is legal under game rules.
- Reputation arithmetic and faction relationship effects.
- Prices, supply, demand, rewards, and anti-exploit limits.
- Universal time and simulation rates.
- Mission objectives, timers, completion, failure, and abandonment.
- System topology and gate validity.
- Asset generation jobs, file paths, caching, retries, and fallbacks.
- PG-13 filtering and Kaelen's protected status.
- Applying world changes after validation.

The LLM never writes directly into a save file, Godot scene, economy table, or
live faction state.

## Campaign Data Model

The current `GlobalState` and `GameRoot` save are useful prototypes, but the
campaign needs explicit ownership boundaries before procedural generation.

### Campaign Manifest

Permanent identity and canon:

- Campaign ID and campaign seed.
- Creation version and schema version.
- Approved story premise and current long-range threads.
- Generated system registry.
- Stable gate graph.
- Faction registry and cross-system identities.
- NPC registry.
- Ship design registry.
- Portrait and voice registry.
- Canon facts that later generation is not allowed to contradict.
- Content-generation versions and original generation seeds.

### Timeline State

Mutable state at a save checkpoint:

- Universal date and time.
- Player location, ship condition, inventory, credits, and upgrades.
- Active and available missions.
- Reputation and known relationships.
- System political, security, and economic state.
- NPC current status and location.
- Pending simulation events.
- Current story beats and unresolved hooks.
- Player-visible map knowledge.

### Chronicle

Append-only significant events:

- Conversations and important choices.
- Mission offers, acceptance, completion, failure, and abandonment.
- Reputation changes with reasons.
- Favors, debts, betrayals, rescues, discoveries, and major purchases.
- Gate discoveries and first arrivals.
- Political changes witnessed or caused by Indy.
- Important NPC promotions and relationship turning points.
- Death details and the evidence used for Kaelen's eulogy.

Events should use structured records, not prose alone. Prose summaries are
derived and cached for LLM prompts.

### Kaelen Meta-Memory

A small campaign-adjacent record may survive checkpoint loading:

- Previous death category.
- A few prior-timeline phrases or facts.
- Number of timeline reversals.

This record must never alter balance, reveal future outcomes, or make ordinary
NPCs remember discarded events.

### Asset Registry

Each generated asset record includes:

- Stable asset ID.
- Owning campaign and entity ID.
- Generator type and version.
- Deterministic seed.
- Input specification.
- Output path and content hash.
- Validation status.
- Fallback status.

This registry allows portraits, ships, and future visual assets to remain stable
even when an older checkpoint is loaded.

## System Content Model

A typical generated system should use ranges rather than a rigid template:

- 1 main inhabited station.
- 1-3 secondary stations, outposts, or industrial locations.
- 2-5 visually important planets.
- 0-4 notable moons.
- Selective asteroid fields and resource regions.
- Several navigation, trade, patrol, and encounter zones.
- 0-2 environmental hazards.
- 2-4 major local factions.
- Several minor organizations.
- 6-12 initially important recurring NPCs.

Sparse and crowded systems should feel different. Not every planet requires an
asteroid field. Visual compositions such as a moon orbiting a huge planet should
be expressible by the system specification.

Hazards such as radiation, gravity anomalies, storms, or black-hole proximity
should influence routes, resources, and politics. They should support the
system's internal power struggle rather than replace it.

## Background Generation Pipeline

Generation runs outside the live gameplay frame and communicates through a
persistent job queue.

1. **Story Director Proposal**
   - Produces a compact plan for likely future branches.
   - Uses only known canon and structured campaign summaries.
   - Proposes two destinations when the upcoming map branch requires choice.

2. **Rule Validation**
   - Rejects non-PG-13 content.
   - Rejects any plan that kills or removes Kaelen.
   - Rejects unsupported mechanics and contradictory canon.
   - Checks system size and content budgets.

3. **System Specification**
   - Deterministic code converts approved intent into a complete schema:
     locations, factions, NPC slots, encounters, economy profile, gates, and
     required mission capabilities.

4. **Specialized Build Jobs**
   - Ship jobs call the procedural Blender generator with stable seeds.
   - Portrait jobs call the future text-to-image service.
   - Vision validation checks portraits for severe defects.
   - Dialogue and biography jobs create constrained text records.
   - Godot content jobs build data resources and placement manifests.

5. **Technical Validation**
   - Verifies required files, schemas, model importability, bounds, collision
     expectations, missing references, and performance budgets.

6. **Narrative Validation**
   - Verifies names, faction ties, gate links, protected characters, tone, and
     contradictions against campaign canon.

7. **Fallback And Retry**
   - Retries only the failed component with a bounded attempt count.
   - Uses curated fallback portraits, ships, names, or missions when necessary.
   - Never blocks the main game indefinitely waiting for generation.

8. **Commit**
   - Atomically adds the completed system and assets to the campaign manifest.
   - A destination is not advertised to the player until this commit succeeds.

9. **Activation**
   - Kaelen or another valid source reveals the route after the player has spent
     sufficient time and engaged with the current system.

The first implementation should use a separate local worker process rather than
threads inside Godot for Blender, image generation, or long LLM jobs. Godot
submits jobs, polls status, and imports completed outputs. This isolates crashes
and keeps the render loop responsive. A model scheduler inside the worker must
serialize GPU-heavy stages under the 8 GB VRAM budget.

## Small-LLM Strategy

The current local model is capable of focused structured tasks, but the existing
all-purpose prompting approach will not scale to campaign direction.

Use several short roles with narrow schemas:

- **Story Director:** proposes arcs and next-system motives.
- **Continuity Editor:** checks proposals against relevant canon.
- **Mission Writer:** adds flavor to a mechanic selected by game code.
- **Dialogue Writer:** writes one speaker turn using retrieved memories.
- **Summarizer:** compresses events and relationships.
- **Eulogy Writer:** writes from selected verified chronicle facts.

Code should choose the task, retrieve only relevant context, and validate every
response. Important creative plans use propose, critique, revise, validate rather
than one-shot generation.

## NPC Memory Model

Broad NPC memory is practical if it is retrieval-based.

Each NPC stores:

- Identity, role, faction, personality traits, and voice.
- Current opinion of Indy and confidence in that opinion.
- Relationships with other important NPCs.
- A small set of pinned significant memories.
- Unresolved promises, debts, threats, favors, and missions.
- A compressed relationship summary.
- References to chronicle event IDs.

Routine interactions are periodically summarized. Major moments stay as
individual events. Dialogue generation receives only the NPC profile, current
situation, relationship summary, unresolved obligations, and a few relevant
events.

Importance is dynamic. A minor shopkeeper or repair technician can be promoted
when Kaelen or the player's choices make that character central.

## Universal Time And Simulation

Introduce one campaign-wide clock before timed missions or off-screen change.

The exact calendar presentation can be chosen later, but it must expose:

- Date.
- Universal time on a 24-hour clock.
- Time remaining for timed missions.
- Time elapsed since leaving a system.

Time advances through travel, repairs, upgrades, mission actions, waiting,
docking services, and gate transit when the current gate story requires it.

Off-screen simulation runs in coarse steps, not frame by frame:

- Short absence: price drift, patrol changes, mission updates.
- Medium absence: shortages, faction pressure, leadership tension.
- Long absence: control changes, blockades, coups, or wars.

Protected major NPCs may be displaced, injured, imprisoned, or endangered
off-screen, but not killed without player participation.

## Story Pressure And Gate Revelation

Kaelen's deal follows a reusable rhythm:

1. Indy arrives and establishes a foothold.
2. Local work reveals factions, people, and tensions.
3. The player invests through missions, trade, allies, or conflict.
4. A local thread points toward something beyond the system.
5. Kaelen offers a profitable deal tied to a hidden or restricted gate.
6. The deal reveals coordinates, access, equipment, cargo, or a contact.
7. The player may accept, delay, refuse, or choose another generated branch.
8. The opportunity remains present or evolves without forcing departure.

Gate offers should be eligibility-driven, not based on a fixed quest count.
Possible inputs include in-game time in the system, local familiarity, number of
meaningful contacts, completed work, story readiness, and destination build
status.

## Evolving Map

The map unlocks after the first gate jump and represents player knowledge:

- Visited systems.
- Confirmed gates.
- Known but unvisited systems.
- Rumored or uncertain routes.
- Current known faction influence.
- Known hazards, wars, shortages, or blockades.
- Kaelen opportunities.
- Player notes and bookmarks.

Confirmed permanent routes do not randomly vanish. Access may be temporarily
blocked. Rumors may be inaccurate or stale.

## Procedural Ship Integration

The external ship generator already supports:

- Stable string seeds.
- Hauler and fighter classes.
- Hull textures.
- Normal-map variants.
- Faction emblems.
- Metallic settings.
- `.glb` export.

The first integration contract should be a command-line worker request:

```json
{
  "job_id": "ship_job_001",
  "asset_id": "ship_design_zenith_scout_01",
  "seed": "campaign-system-faction-role-variant",
  "ship_class": "fighter",
  "texture": "NavyBlueMetal.png",
  "emblem": "emblem_1.png",
  "normal": "hull_normal_var_3.png",
  "metallic": 0.85
}
```

The worker returns a manifest containing output path, hash, bounds, mesh count,
and validation errors. Godot should never infer a ship's combat stats from its
generated geometry. The visual design and gameplay archetype share an ID but
remain separate data.

## Implementation Order

### Phase 0: Preserve The Prototype

Purpose: establish a trustworthy baseline before foundational refactoring.

- Finish the current jump-gate branch and hands-on regression pass.
- Document current game loops and known defects.
- Add repeatable startup, jump, save, docking, quest, and upgrade checks.
- Record performance baselines and save representative prototype saves.
- Do not begin procedural campaign generation during this phase.

Exit gate:

- Existing mining, combat, docking, upgrades, quests, TTS, LLM fallback,
  two-way gates, and saves are reproducibly testable.

### Phase 1: Typed Domain Data And IDs

Purpose: stop future systems from depending on loose dictionaries and node names.

- Define schemas or Resources for systems, gates, factions, NPCs, ships,
  missions, relationships, events, assets, and generation jobs.
- Introduce stable IDs for all persistent entities.
- Split immutable definitions from mutable runtime state.
- Replace hard-coded system registry assumptions with a data-driven registry.
- Keep adapters so current gameplay continues to work.

Exit gate:

- The handcrafted first and test systems load through the new registry.
- Existing saves migrate or fail with a clear compatibility message.

### Phase 2: Campaign Store And Save Architecture

Purpose: make permanence reliable before creating more content.

- Create separate campaign manifest, timeline checkpoint, chronicle, map
  knowledge, asset registry, and Kaelen meta-memory stores.
- Add atomic writes, backups, schema versions, and migrations.
- Define rewind behavior for older checkpoints.
- Add cache integrity checks and missing-asset recovery.
- Add multiple save slots and autosave rules.

Exit gate:

- Generated identity data survives checkpoint loading unchanged.
- Mutable state rewinds correctly.
- Corrupted or partial writes recover safely.

### Phase 3: Universal Time

Purpose: provide one clock for missions, economy, travel, and simulation.

- Add the universal calendar and HUD/map display.
- Define time costs for existing actions.
- Add pause-safe timers based on campaign time.
- Add timed mission primitives without requiring generated stories yet.

Exit gate:

- Time advances deterministically, saves correctly, and never uses wall-clock
  time for mission outcomes.

### Phase 4: Chronicle, Relationships, And NPC Promotion

Purpose: create the memory substrate before richer dialogue.

- Add structured event recording.
- Add player-to-NPC, player-to-faction, and faction-to-faction relationships.
- Add reputation reasons and propagation rules.
- Add NPC memory retrieval and summary compaction.
- Add dynamic minor-to-major promotion.
- Replace the Markdown-only quest history with chronicle-derived summaries.

Exit gate:

- Existing handcrafted NPCs remember tested interactions after save, travel, and
  return without sending full histories to the LLM.

### Phase 5: Mission Framework

Purpose: give story generation a safe vocabulary of mechanics.

- Replace the single active quest with mission collections.
- Define typed objective components and consequence components.
- Port current kill, ore delivery, and special pickup missions.
- Add abandonment with 2-3 reputation loss.
- Add untimed persistence and timed expiration.
- Add prerequisite, branching, follow-up, and cross-system mission support.
- Keep deterministic validation and curated fallbacks.

Exit gate:

- Multiple authored missions can coexist, expire, branch, and survive travel.

### Phase 6: Faction And Economy Simulation

Purpose: make systems change believably without direct LLM control.

- Create faction influence, resources, goals, relationships, and conflict state.
- Add coarse off-screen simulation using universal time.
- Protect connected major NPCs from off-screen death.
- Add regional supply, demand, stock recovery, taxes, and access controls.
- Add station storage and trade history.
- Add high-reputation stock and enemy-faction suspicion.

Exit gate:

- Leaving and returning after controlled time produces explainable, bounded
  changes.
- Repeating one trade loop cannot generate unlimited risk-free profit.

### Phase 7: Map And Discovery

Purpose: support branching campaigns before procedural branches are activated.

- Build the evolving system map.
- Separate physical campaign topology from player knowledge.
- Support confirmed, hidden, rumored, blocked, and damaged routes.
- Add two handcrafted branch destinations as a test.
- Add Kaelen's delayed gate-reveal eligibility.

Exit gate:

- The player can discover, compare, and choose between two fully authored
  branches without breaking saves or mission state.

### Phase 8: Generation Job Service

Purpose: create a robust background production pipeline.

- Build the persistent job queue and separate worker process.
- Add job states, retries, cancellation, logs, timeouts, and fallbacks.
- Add a GPU budget manager and single-major-model scheduling.
- Pause or defer AI jobs when gameplay VRAM headroom is too low.
- Integrate the procedural ship builder through a stable command contract.
- Add output hashing and asset registry commits.
- Prove background work does not stall gameplay.

Exit gate:

- The game can request, validate, cache, reload, and reuse generated ships while
  the player continues playing.

### Phase 9: Procedural System Builder

Purpose: build playable systems from validated specifications.

- Define the system specification schema.
- Create reusable location, planet, moon, station, outpost, hazard, encounter,
  spawn, and gate components.
- Build deterministic layout from a system seed.
- Add visual composition rules and performance budgets.
- Generate both sides of a branch before advertising either.
- Add automated structural and runtime validation.

Exit gate:

- A generated system can be built, cached, loaded, left, revisited, and restored
  without the LLM being present.

### Phase 10: Story Director

Purpose: introduce campaign-level procedural authorship after the game can
enforce it.

- Generate the opening campaign premise around the fixed first system.
- Maintain active arcs, unresolved hooks, and future branch proposals.
- Use constrained schemas and continuity review.
- Translate approved story intent into supported missions and simulation inputs.
- Add PG-13 and Kaelen-protection validators.
- Add graceful fallback arcs when the LLM is unavailable.

Exit gate:

- Several campaigns produce meaningfully different ongoing stories while using
  the same first system and without contradicting established canon.

### Phase 11: NPC, Portrait, Voice, And Dialogue Production

Purpose: populate generated systems with persistent people.

- Generate structured NPC identities and relationships.
- Assign stable voices and create voice fallbacks.
- Integrate text-to-image portrait generation.
- Integrate Gemma vision review and defect scoring.
- Benchmark candidate open-source models on the 8 GB target before selection.
- Add bounded retries and curated fallback portraits.
- Retrieve relevant memories for dialogue.
- Maintain the Shiny/Indy speaker rule in both text and TTS.

Exit gate:

- Generated NPCs retain identity, portrait, voice, and memory across the entire
  campaign.

### Phase 12: Kaelen Travel Deals And Long-Arc Mystery

Purpose: connect free play to forward movement.

- Let the director propose deal motives while code controls readiness.
- Support delayed, refused, revised, and alternate deals.
- Seed rare, non-repeating hints about Kaelen's origin and knowledge.
- Ensure Kaelen is present and usable in every generated main station.
- Add rare discarded-timeline references.

Exit gate:

- Players feel invited toward new systems without being forced, and Kaelen's
  repeated presence becomes intriguing rather than mechanically convenient.

### Phase 13: Death, Chronicle Closure, And Eulogy

Purpose: make a campaign's end reflect what actually happened.

- Freeze the final timeline on death.
- Select verified chronicle facts by importance and theme.
- Generate Kaelen's eulogy from those facts.
- Provide a deterministic fallback eulogy.
- Preserve the campaign as a readable legacy record.
- Allow loading an earlier save while updating only Kaelen's meta-memory.

Exit gate:

- The eulogy accurately references the player's real relationships, choices,
  failures, and accomplishments without inventing contradictory events.

### Phase 14: Long-Run Hardening

Purpose: prove the campaign remains healthy over many systems and many hours.

- Soak-test large chronicles, asset caches, map branches, and old systems.
- Measure prompt sizes, generation latency, memory use, disk growth, and import
  times.
- Measure peak VRAM during gameplay, model loading, portrait generation, vision
  review, and transitions between those workloads.
- Add pruning for disposable logs while preserving canon.
- Add migration tests across released schema versions.
- Balance economy, reputation, travel pacing, and generation lead time.

Exit gate:

- A long campaign can span many systems without save corruption, runaway prompt
  growth, severe loading degradation, or continuity collapse.

## Current Project Fit

Useful foundations already present:

- Persistent `GameRoot` with system swapping.
- Two-way gate travel and transition masking.
- Versioned JSON save prototype.
- Persistent entity capture for selected system objects.
- Handcrafted first system and test system.
- Reputation, upgrades, cargo, mining, combat, docking, and storage foundations.
- Local Ollama integration with validation and fallbacks.
- Kokoro TTS integration and per-voice caching.
- Existing tone guard for Kaelen's "Shiny" versus everyone else's "Indy."
- Procedural ship generator with deterministic seeds and `.glb` export.

Areas that must be restructured before procedural campaigns:

- `GlobalState` currently owns too many unrelated domains.
- `GameRoot.SYSTEM_SCENES` is hard-coded.
- Save version 1 mixes checkpoint state and campaign identity.
- Missions support only one loose dictionary at a time.
- Quest history is prose-first rather than structured event data.
- `LLMInterface` combines many responsibilities and large fallback libraries.
- Much of `UIManager` is generated in one very large script.
- NPC and faction definitions are compiled into code rather than campaign data.
- TTS cache is session-only.
- The ship generator needs a worker manifest and validation contract.

## Deferred Decision Gates

These questions do not block the first architectural phases:

- Exact universal calendar names and starting date.
- Whether normal gate transit consumes time or only story-specific gates do.
- Exact maximum number of active missions.
- Exact system size budgets for low-end hardware.
- Portrait model and Gemma vision model choices.
- The precise truth behind Kaelen's travel and final system.
- Whether non-gate travel ever becomes a player ability.
- The shape of a distant optional campaign finale.
- Any future mature-content mode.
- Planet landing, which remains outside the planned scope.

## Immediate Work Boundary

The next implementation work should stop after Phases 0-2 are designed in more
detail and approved. Procedural story or asset generation should not be wired
into live campaign state until typed IDs, campaign persistence, migrations, and
rewind rules are proven.

This order is intentionally conservative: every later system depends on the
campaign remembering what it created and why.
