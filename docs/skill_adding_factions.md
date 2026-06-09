# Adding Factions to the Game

This guide covers how to add both minor and major factions to the SpaceGame project.

---

## Minor Factions (Kill Targets Only)

Minor factions are hostile outlaws with no reputation tracking. They serve as targets for elimination contracts. Adding one is simple and almost entirely data-driven.

### Step 1: Add to `MINOR_FACTIONS` in `GlobalState.gd`

Add a new entry to the `MINOR_FACTIONS` dictionary. Each entry needs:

| Key              | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| `color`          | The faction's UI/label color (`Color`)                                      |
| `projectile_color` | The color of their projectiles (`Color`)                                 |
| `model`          | Ship model key — must be one of `'faction1'`, `'faction2'`, or `'aurelia'`  |
| `tint`           | Tint color applied to the ship model (`Color`)                              |

Example:
```gdscript
"Reavers": {
    "color": Color(1.0, 0.2, 0.2),
    "projectile_color": Color(1.0, 0.3, 0.1),
    "model": "faction1",
    "tint": Color(0.8, 0.1, 0.1)
},
```

### Step 2: Done

That's it. Everything else — hull setup, ship colors, projectile colors, and aggro behavior — is **data-driven and automatic**. Minor faction ships will spawn, fight, and appear in contracts without any additional code changes.

### Step 3 (Optional): Add Lore

Add a brief description of the faction to `docs/world_lore.md` under the **Minor Factions** section. Keep it to 2–3 sentences to stay within the LLM token budget.

---

## Major Factions (Full Reputation, Quests, Portraits)

Major factions have reputation tracking, quest-giving NPCs, portraits, voice lines, and full diplomatic integration. Adding one requires changes across multiple files.

### Step 1: `GlobalState.gd` — State Tracking

1. **`reputations` dict** (lines 40–44): Add the new faction with a default reputation value (typically `0`).
2. **`faction_kills` dict** (lines 50–54): Add the new faction with a default kill count of `0`.
3. **`reset_for_restart()`** (lines 178–180): Reset the new faction's reputation and kill count to defaults.

### Step 2: `NPCShip.gd` — Ship Visuals & Combat

1. **Ship model preload** (lines 31–33): Add a `preload()` for the new faction's ship model scene.
2. **`_setup_hull()`** (lines 121–145): Add a `match` arm to assign the correct model, scale, and tint.
3. **Chatter colors** (2 locations — lines 278–282 and 358–362): Add `match` arms so chat messages display in the faction's color.
4. **Projectile colors** (lines 302–307): Add a `match` arm to set the faction's projectile color.
5. **`_apply_reputation_changes()`** (lines 373–385): Add a `match` arm defining how killing this faction's ships affects reputation with other factions.

### Step 3: `MainScene.gd` — Spawning

1. **`_ready()`** (lines 21–37): Add initial spawn calls for the new faction's ships.
2. **`_spawn_npc_flying_in()`** (line 145): Add the faction to the respawn faction list so ships are replenished during gameplay.

### Step 4: `LLMInterface.gd` — Quest & Dialogue Integration

1. **Quest faction list** (line ~448): Add the faction so it can appear in generated quests.
2. **Agent persona section**: Add a new `match` arm with:
   - `agent_name` — the NPC's display name
   - `agent_role` — their role/title
   - `player_nickname` — what they call the player
   - `agent_persona` — personality description for LLM prompt
   - `example_dialogue` — sample lines the NPC would say
   - `example_responses` — sample player responses
3. **Kill target list**: Add the faction so it can be referenced in elimination contracts.

### Step 5: `UIManager.gd` — UI & Portraits

1. **`_on_quest_generated_received()`**: Add Kaelen handoff intro lines for the new faction's quest giver.
2. **`_update_agent_portrait()`**: Add the faction's portrait to the `QuestGivers.png` spritesheet and update the function to map the correct sprite region.
3. **`_update_quest_tracker_logo()`**: Add the faction's branding logo to `factionBranding.png` and update the function to select the correct logo region.
4. **`_update_hud_reputations()`**: Update the HUD reputation display to include the new faction.
5. **Initial `RepLabel` text**: Update the default text to include the new faction's name.

### Step 6: `TTSInterface.gd` — Voice

1. **`get_voice_for_faction()`**: Add a voice assignment for the new faction's quest-giving NPC.

---

## Quick-Reference Checklist

### Minor Faction
- [ ] Add entry to `MINOR_FACTIONS` in `GlobalState.gd` (color, projectile_color, model, tint)
- [ ] *(Optional)* Add lore to `docs/world_lore.md`

### Major Faction
- [ ] `GlobalState.gd` — Add to `reputations` dict
- [ ] `GlobalState.gd` — Add to `faction_kills` dict
- [ ] `GlobalState.gd` — Add to `reset_for_restart()`
- [ ] `NPCShip.gd` — Add ship model preload
- [ ] `NPCShip.gd` — Add match arm in `_setup_hull()`
- [ ] `NPCShip.gd` — Add match arms for chatter colors (2 locations)
- [ ] `NPCShip.gd` — Add match arm for projectile colors
- [ ] `NPCShip.gd` — Add match arm in `_apply_reputation_changes()`
- [ ] `MainScene.gd` — Add to initial spawn calls in `_ready()`
- [ ] `MainScene.gd` — Add to respawn faction list in `_spawn_npc_flying_in()`
- [ ] `LLMInterface.gd` — Add to quest faction list
- [ ] `LLMInterface.gd` — Add agent persona match arm
- [ ] `LLMInterface.gd` — Add to kill target list
- [ ] `UIManager.gd` — Add Kaelen handoff intro lines
- [ ] `UIManager.gd` — Add portrait to spritesheet + update `_update_agent_portrait()`
- [ ] `UIManager.gd` — Add branding logo + update `_update_quest_tracker_logo()`
- [ ] `UIManager.gd` — Update `_update_hud_reputations()`
- [ ] `UIManager.gd` — Update initial `RepLabel` text
- [ ] `TTSInterface.gd` — Add voice in `get_voice_for_faction()`
- [ ] *(Optional)* Add lore to `docs/world_lore.md`
