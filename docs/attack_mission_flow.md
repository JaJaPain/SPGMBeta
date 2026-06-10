# Attack Mission Flow (Quest: KILL_SHIPS)

Reference doc for the end-to-end flow of an attack-type quest (kill X ships) in SpaceGame.

> **Heads up:** in this codebase, "attack mission" = a `KILL_SHIPS` quest. The broker/quest board is built procedurally inside `UIManager.gd` — there is no dedicated mission-selection scene file.

---

## Terminology

| User-facing term       | Code term                                |
| ---------------------- | ---------------------------------------- |
| Attack mission         | `objective_type == "KILL_SHIPS"`         |
| Ore mission            | `objective_type == "DELIVER_ORE"`        |
| Mission selection UI   | `agent_panel` (created in code, no .tscn) |
| Mission log / tracker  | `quest_tracker_panel`                    |
| Active mission list    | `QuestManager.active_quest` (single Dictionary, not a list) |

---

## Data Model

A quest is a plain `Dictionary` — **no Godot `Resource`, no `enum`**. The type discriminator is a string field:

- `objective.type` (or `objective_type`) — `"KILL_SHIPS"` or `"DELIVER_ORE"`
- `objective.target_faction` (KILL_SHIPS only)
- `objective.count_required` (KILL_SHIPS only, clamped 2–4)
- `objective.amount_required` (DELIVER_ORE only)

There is **only one active quest at a time** (`QuestManager.active_quest: Dictionary`).

After `accept_quest` runs, the singleton holds:

```gdscript
active_quest = {
    "title": quest_data.get("title", "Unnamed Contract"),
    "faction": quest_data.get("faction", "zenith"),
    "agent_name": quest_data.get("agent_name", "Broker Kaelen"),
    "dialogue": quest_data.get("dialogue", ""),
    "objective_type": type,                          # "KILL_SHIPS" or "DELIVER_ORE"
    "combat_multiplier": combat_mult,
    "reward_credits_multiplier": reward_mult,
    "reward_credits": reward_credits,
    "choice_text_selected": selected_choice.get("text", ""),
    "agent_response": consequence.get("dialogue_response", "")
}
# + type-specific fields (target_faction, count_required, current_count for KILL_SHIPS)
```

---

## Generator

- **`LLMInterface.request_quest_generation()`** at `scripts/LLMInterface.gd:576`
- **Pre-decides the type 50/50** with `randi() % 2 == 0` (line 657)
- If `KILL_SHIPS`, picks **target faction 90% minor / 10% major** (lines 672–682)
- Sends a prompt to local Ollama at `http://127.0.0.1:11434/api/generate`
- On response, `_validate_quest_data` (line 855) clamps count to 2–4 and reconciles dialogue
- If LLM offline, falls back to hand-written `fallback_templates` (line 40+) via `_trigger_fallback` (line 1034)

The pre-LLM type choice is the key bit: the LLM is told what type to write, so it can't drift.

---

## The Full Chain (top to bottom)

### 1. Player at the agent panel sees the new quest offer
- `UIManager._on_quest_generated_received()` (line 1982)
- Kaelen's handoff line is on screen, "Bring them in" button visible

### 2. Player clicks "Bring them in" → briefing screen
- `UIManager._show_quest_briefing()` (line 2039) writes the **Contract Details** block
- For an attack quest, this is where `"Destroy N FACTION ships"` first appears (line 2061)
- One **Button per choice** is created from `quest_data["choices"]` (line 2068) — this is the LLM-generated "Attack" vs "Ore" choice

### 3. Player clicks the attack choice
- `UIManager._on_choice_selected(quest_data, choice)` (line 2078)
- Calls `QuestManager.accept_quest(...)` and adds an "Undock & Begin Mission" button

### 4. `QuestManager.accept_quest` makes the attack mission "real"
- `QuestManager.accept_quest()` (line 119)
- For KILL_SHIPS, populates:
  - `target_faction`
  - `count_required` (clamped, then multiplied by `combat_multiplier`)
  - `current_count = 0`
- Schedules a 3-second timer → `GlobalState.spawn_mission_targets(faction, count)`

### 5. The `quest_accepted` signal fires → HUD tracker appears
- Signal hookup: `UIManager.gd:144` — `QuestManager.quest_accepted → _on_quest_accepted`
- `_on_quest_accepted()` (line 2243) sets `quest_tracker_panel.visible = true` and calls `_update_quest_tracker()`

### 6. The tracker label is built
- `_update_quest_tracker()` (line 2256) reads `QuestManager.active_quest`
- For KILL_SHIPS: `quest_tracker_progress.text = "Kills: 0 / 3 (REAVERS)"` (line 2269)

### 7. Player undocks → targets spawn 3s later
- `GlobalState.spawn_mission_targets(faction_name, count)` (line 193)
- Spawns `count` NPCs in a 550–900m ring around the station
- Tags each NPC: `npc.set_meta("is_quest_target", true)` (line 230)
- Pushes HUD warning: `"CONTRACT ACTIVE: 3 REAVERS targets have entered the sector."` (line 237)
- Emits system chatter

### 8. Each kill updates the tracker live
- `NPCShip.die()` → emits `GlobalState.ship_destroyed(faction)` (line 409)
- `QuestManager._on_ship_destroyed()` (line 225) matches `target_faction`, increments `current_count`, emits `quest_progress_updated`
- `UIManager._on_quest_progress_updated()` (line 2247) → `_update_quest_tracker()` re-renders
- Player sees `Kills: 0 / 3 (REAVERS)` → `1 / 3` → `2 / 3` → `3 / 3` in real time
- At 3/3, `quest_completed` fires

---

## Key File/Function Index

| Concept                              | File                              | Line(s)        |
| ------------------------------------ | --------------------------------- | -------------- |
| Mission data model                   | `scripts/QuestManager.gd`         | 10, 139–164    |
| Quest acceptance                     | `scripts/QuestManager.gd`         | 119–167        |
| Type pre-decision (50/50)            | `scripts/LLMInterface.gd`         | 657            |
| Target faction picker (90/10)        | `scripts/LLMInterface.gd`         | 672–682        |
| Count validator + clamp 2–4          | `scripts/LLMInterface.gd`         | 855–927        |
| Dialogue-count reconciliation        | `scripts/LLMInterface.gd`         | 929–990        |
| Fallback templates                   | `scripts/LLMInterface.gd`         | 40–300+        |
| Fallback trigger                     | `scripts/LLMInterface.gd`         | 1034           |
| Agent panel (UI)                     | `scripts/UIManager.gd`            | 638–661        |
| Briefing dialog (Contract Details)   | `scripts/UIManager.gd`            | 2039–2074      |
| Kill label in briefing               | `scripts/UIManager.gd`            | 2061           |
| Choice buttons (Attack/Ore)          | `scripts/UIManager.gd`            | 2068–2074      |
| Choice click handler                 | `scripts/UIManager.gd`            | 2078           |
| Quest tracker panel                  | `scripts/UIManager.gd`            | 259–311        |
| Tracker update function              | `scripts/UIManager.gd`            | 2256–2279      |
| Kill label in tracker                | `scripts/UIManager.gd`            | 2269           |
| Quest signal hookup                  | `scripts/UIManager.gd`            | 144–148        |
| Quest accepted handler               | `scripts/UIManager.gd`            | 2243           |
| Quest progress handler               | `scripts/UIManager.gd`            | 2247           |
| NPC spawn on accept                  | `scripts/GlobalState.gd`          | 193–238        |
| HUD warning on spawn                 | `scripts/GlobalState.gd`          | 237            |
| NPC kill → signal                    | `scripts/NPCShip.gd`              | 409            |
| Quest death tracking                 | `scripts/QuestManager.gd`         | 225–263        |
| Combat multiplier on NPCs            | `scripts/NPCShip.gd`              | 94–101         |

---

## Signal Flow

```
QuestManager (signals)
  ├── quest_accepted         → UIManager._on_quest_accepted
  ├── quest_progress_updated → UIManager._on_quest_progress_updated
  ├── quest_completed        → UIManager._on_quest_completed
  └── quest_abandoned        → UIManager._on_quest_abandoned

GlobalState
  └── ship_destroyed(faction) → QuestManager._on_ship_destroyed
```

---

## Notes for Future Work

1. **No separate "mission selection" scene exists** — the quest board is built procedurally in `UIManager.gd`.
2. **KILL_SHIPS vs DELIVER_ORE is a string, not an enum** — easy to typo. QuestManager is defensive (line 122).
3. **Attack targets are 90% minor factions, 10% major** — major-faction attack missions are rare and only happen when the LLM quest giver is from a different major faction.
4. **Kill count is decided by the LLM but clamped to 2–4** by `_validate_quest_data`.
5. **Only one active quest at a time** — `active_quest` is a single Dictionary, not a collection.
6. **The "Kill X ships" label appears in 3 places**:
   - Briefing: `"Destroy N FACTION ships"` (UIManager:2061)
   - HUD tracker: `"Kills: N / M (FACTION)"` (UIManager:2269)
   - HUD warning on spawn: `"CONTRACT ACTIVE: N FACTION targets..."` (GlobalState:237)
7. **The flow is event-driven via Godot signals** — UI never polls, it reacts.

---

## TL;DR for the User-Facing Flow

> **Dock → Talk to Agent → Quest board shows offer → "Bring them in" → Briefing shows "Destroy 3 REAVERS ships" → Player picks the attack option → "Undock & Begin Mission" → leave station → 3 seconds later, HUD warns "CONTRACT ACTIVE: 3 REAVERS targets" and the top-left tracker shows "Kills: 0 / 3 (REAVERS)" → each kill bumps the counter → 3/3 triggers `quest_completed`.**
