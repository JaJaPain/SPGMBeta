# Handoff: Test Pickup Quest + Outpost Flavor/Lore

**Last good commit:** `731c965` (working tree clean)
**Project:** `C:\CodingProjects\SpaceGame` (Godot 4.6)
**Session ended:** 2026-06-10

This handoff covers the last 4 items the previous session left unfinished. The data layer (NPC portraits, flavor lines, QuestManager support for a new `PICKUP_SPECIAL` objective type) is already in `731c965` — the work below is UI wiring on top of that data.

---

## What's already done (don't re-do)

### GlobalState (`scripts/GlobalState.gd`)

- **`MINOR_NPCS` const** (around line 78) — all 8 NPCs have `flavor_lines: Array` (3 short lines each, total 24) and `flavor_color: Color` for chatter tinting. Sample:
  - Mariska Vonn (corporate fixer, Iron Reach): *"Zenith's been running the numbers on you, Shiny. Try not to disappoint the spreadsheet."*
  - Cassen Vane (mercenary, Kova): *"Aurelia tried to recruit me once. I declined. Politely. With a knife."*
  - Jenna Kross (mechanic, Grease Monkeys): *"If it flies, I can fix it. If it doesn't fly, I can make it fly. Hand me the part."*
- **`get_random_npc_flavor_line(outpost_id)`** (around line 247) — picks a random NPC at the outpost + random line. Returns `{npc_name, line, color}`. Empty dict if no NPCs.

### QuestManager (`scripts/QuestManager.gd`)

Full `PICKUP_SPECIAL` objective support (additive, no breaking changes):
- **`accept_quest`** — when `objective.type == "PICKUP_SPECIAL"`, populates `active_quest` with `target_outpost`, `target_outpost_display`, `target_npc`, `part_name`, `destination`, `picked_up=false`.
- **`mark_pickup_complete()`** — new method. Flips `picked_up=true` and loads the part into cargo via `GlobalState.accept_special(...)`. Emits `quest_progress_updated`. Returns false if quest isn't `PICKUP_SPECIAL` or already picked up.
- **`is_quest_completed`** — for `PICKUP_SPECIAL`, returns `active_quest.picked_up`.
- **`complete_quest`** — for `PICKUP_SPECIAL`, verifies the cargo_special name matches `active_quest.part_name`, then calls `GlobalState.clear_cargo()`. Also gives reward + history log + rep bump like other types.

### UIManager (`scripts/UIManager.gd`)

- **`_update_quest_tracker`** (around line 2405) — added a `PICKUP_SPECIAL` branch. Shows:
  - Before pickup: `Pickup: <part_name> from <target_npc> @ <target_outpost_display>`
  - After pickup: `Deliver: <part_name> to <destination>`

### Auto-generated Godot import metadata

`assets/MinorNPC01.png.import` and `assets/MinorNPC02.png.import` are committed. The portraits load via `res://assets/MinorNPC01.png` etc.

---

## What needs to be finished (4 items)

The previous session started refactoring the test buttons to use `QuestManager.accept_quest` (PICKUP_SPECIAL flow) but ran out of time. The two main issues the user reported are still unfixed:

1. The current "Test: Start Outpost Pickup" button at Grease Monkeys immediately loads the special cargo at Grease Monkeys (wrong — it should just *set up the quest*, and the cargo should only load when the player actually picks it up at the outpost).
2. The outpost dock menu still shows "Sell Ore" / "Talk to Agent" / "Grease Monkeys" buttons it shouldn't.

### Item 1: Refactor the two existing test handlers at Grease Monkeys

**File:** `scripts/UIManager.gd` — the existing functions are around lines 1520–1558 (search for `_on_test_pickup_pressed` and `_on_test_deliver_pressed`).

**Current (buggy) behavior:**
- `_on_test_pickup_pressed` calls `GlobalState.clear_cargo()` then `GlobalState.accept_special(...)` directly. The cargo loads at Grease Monkeys.
- `_on_test_deliver_pressed` checks `cargo_type == SPECIAL`, then clears cargo + adds credits manually.

**Replace with:**
- `_on_test_pickup_pressed`:
  - Pick random `outpost_id`, `outpost_display`, `npc_name`, `part_name` (existing constants `TEST_OUTPOST_IDS`, `TEST_OUTPOST_DISPLAY`, `TEST_PART_NAMES` are right above the handlers).
  - Build a quest dict with the shape QuestManager accepts. Required fields: `title`, `faction` ("neutral"), `agent_name` ("Jenna Kross"), `dialogue`, `objective.type` ("PICKUP_SPECIAL"), `objective.target_outpost`, `objective.target_outpost_display`, `objective.target_npc`, `objective.part_name`, `objective.destination` ("Grease Monkeys"), `objective.reward_credits` (`TEST_PICKUP_REWARD`).
  - Build a `selected_choice` dict — `{"text": "I'll take it.", "consequence": {}}` is enough (no credits_immediate, no reputation_change).
  - Call `GlobalState.clear_cargo()` first (clean slate).
  - Call `QuestManager.accept_quest(quest_data, selected_choice)`.
  - Show a `show_hud_warning(...)` flash with the quest instructions (look around line 1750 for the existing function).
- `_on_test_deliver_pressed`:
  - If `not QuestManager.is_quest_active()` → return (or show a "no quest to deliver" warning).
  - If `not QuestManager.is_quest_completed()` → show a "you haven't picked up the part yet" warning and return.
  - Otherwise: call `QuestManager.complete_quest()` (it handles reward + history + cargo clear).
  - Show a `show_hud_warning(...)` confirming delivery + reward.
- The `TEST_PICKUP_REWARD` constant is still used — but it's now the quest's `reward_credits` value, not something `+ GlobalState.player_credits`'d manually. Leave the constant.

**Gotcha:** the existing button labels say "Test: Start Outpost Pickup (random)" and "Test: Deliver Special Cargo". Consider renaming to "Test: Start Pickup Quest" and "Test: Deliver Part" to match the new flow. Up to taste.

**Test:** click Start at Grease Monkeys → no cargo loads, but the quest tracker shows the pickup instructions. Fly to the assigned outpost.

### Item 2: Add the "Test: Pickup Part" button at outposts

**File:** `scripts/UIManager.gd` — dock submenu setup around line 638.

**What to do:**
- Add a member variable: `var test_pickup_part_btn: Button` (alongside `test_pickup_btn` and `test_deliver_btn` around line 33).
- Create the button after `test_deliver_btn` in `_create_dock_menu`. Label: `"Test: Pickup Part"`. Connect `pressed` to `_on_test_pickup_part_pressed`.
- Add a new handler `_on_test_pickup_part_pressed` that:
  - Checks `QuestManager.is_quest_active()` and that the active quest is `PICKUP_SPECIAL` and not yet picked up. If not, show a warning ("wrong state") and return.
  - Determines the current outpost's id from `current_station.name`. The outpost scene nodes are named `"IronReachOutpost"` and `"KovaStation"`. Map these to `"iron_reach"` and `"kova"`. (Or use a property on the station node if there's a cleaner one — `current_station.get("display_name")` or `current_station.get("station_type")` may also work.)
  - Compares against `QuestManager.active_quest.target_outpost`. If mismatch, show "wrong outpost, check the quest tracker" and return.
  - Calls `QuestManager.mark_pickup_complete()`. If it returns true, show a confirmation warning and play a sound if there is one (look for similar `AudioManager.play_*` calls in the existing handlers).
  - If false, just push a warning to the console.

**Gotcha:** the existing button creation lives inside `_create_dock_menu` which is called once at startup. All the maintenance-bay buttons are created in a single block. Put the new outpost button in the same block for consistency.

### Item 3: Fix the outpost dock submenu so it doesn't show the wrong buttons

**File:** `scripts/UIManager.gd` — `_render_dock_submenu` function around line 1446.

**Current behavior:** the SERVICES submenu shows `sell_btn`, `agent_service_btn`, `maintenance_bay_btn` everywhere. The user wants outposts to hide all three (outposts have no sell, no agent, no Grease Monkeys — they're remote stations where you just dock and grab the part).

**What to do:**
- At the top of `_render_dock_submenu`, detect whether `current_station` is an outpost. The cleanest way: `var is_outpost = current_station and current_station.get("station_type") == "outpost"` (or fall back to node-name match if `station_type` isn't set on outpost nodes — verify in `scripts/OutpostStation.gd`).
- In the SERVICES submenu branch (the `else:` around line 1464), branch on `is_outpost`:
  - If outpost: hide `sell_btn`, `agent_service_btn`, `maintenance_bay_btn`. Show `test_pickup_part_btn` (always — the button's own `disabled` state handles the "no quest" case) and `hear_gossip_btn` (when Item 4 is done). The "back" button stays hidden (only maintenance uses it).
  - If not outpost: existing behavior (show sell, agent, maintenance_bay).
- The MAINTENANCE submenu branch (around line 1447) is Grease Monkeys only — unchanged.

**Test:** dock at Outpost Iron Reach → see only "Undock" + (test pickup / hear gossip when those exist). Dock at main station → see "Sell Ore" / "Talk to Agent" / "Maintenance Bay" as before.

### Item 4: Add the "Hear Gossip" button UI

**File:** `scripts/UIManager.gd` — same dock submenu setup as Item 2.

**What to do:**
- Add a member variable: `var hear_gossip_btn: Button`.
- Create the button in `_create_dock_menu`. Label: `"Hear Gossip from the Locals"`. Connect `pressed` to `_on_hear_gossip_pressed`.
- Add a handler `_on_hear_gossip_pressed` that:
  - Determines the current outpost id (same logic as Item 2 — read from `current_station.name`).
  - Calls `GlobalState.get_random_npc_flavor_line(outpost_id)`. If the result is empty, show a "no one's around" warning and return.
  - Otherwise: call `show_hud_warning(line)` for a brief flash, AND call `GlobalState.emit_chatter(npc_name, line, color)` so the line also appears in the corner chatter feed (persistent). The `emit_chatter` signature is `func emit_chatter(sender: String, message: String, color: Color)` — search the file to confirm.
- In `_render_dock_submenu` (the same branch from Item 3): at outposts, set `hear_gossip_btn.visible = true`. Elsewhere, hide it.

**Note:** the button is at the outpost dock — it makes sense to have it always available (not gated on a quest), since flavor/lore is the entire point.

---

## End-to-end test cycle (once all 4 are done)

1. Dock at **Grease Monkeys** → click **"Maintenance Bay"** → see the maintenance submenu.
2. Click **"Test: Start Pickup Quest"** — quest tracker appears in the top-left with pickup instructions. Cargo HUD still shows ORE/EMPTY. No cargo loaded.
3. Undock, fly to the outpost shown in the quest tracker (random each time).
4. Dock at the outpost — the menu shows ONLY "Undock", "Hear Gossip", and "Test: Pickup Part" (no Sell Ore / Agent / Grease Monkeys).
5. Click **"Hear Gossip"** once or twice — see a flavor line flash as a HUD warning and appear in the corner chatter. NPC name is the sender.
6. Click **"Test: Pickup Part"** — the part loads into cargo (HUD changes to `SPECIAL: <part name>`). Quest tracker switches to "Deliver: <part> to Grease Monkeys".
7. Undock, fly back to Grease Monkeys. Mining laser is hidden the whole way.
8. Dock at Grease Monkeys → Maintenance Bay → click **"Test: Deliver Part"** — cargo clears, +200 SC, quest tracker disappears, history file gets a `Completed. Payout: 200 SC.` line for the quest title.
9. Click Start again — fresh random quest begins.

---

## Key file / line index (for navigation)

| File | Around line | What's there |
|---|---|---|
| `scripts/GlobalState.gd` | 78 | `MINOR_NPCS` const with flavor_lines |
| `scripts/GlobalState.gd` | 247 | `get_random_npc_flavor_line` helper |
| `scripts/GlobalState.gd` | 327 | `emit_chatter` (for flavor display) |
| `scripts/QuestManager.gd` | 119 | `accept_quest` — handles PICKUP_SPECIAL |
| `scripts/QuestManager.gd` | ~200 | `mark_pickup_complete` (new) |
| `scripts/QuestManager.gd` | ~210 | `is_quest_completed` — handles PICKUP_SPECIAL |
| `scripts/QuestManager.gd` | ~230 | `complete_quest` — handles PICKUP_SPECIAL |
| `scripts/UIManager.gd` | 33 | test button member variables |
| `scripts/UIManager.gd` | 638 | test button creation in dock submenu setup |
| `scripts/UIManager.gd` | 1446 | `_render_dock_submenu` — needs outpost fix (Item 3) |
| `scripts/UIManager.gd` | 1520 | current (buggy) test handlers — needs refactor (Item 1) |
| `scripts/UIManager.gd` | 1750 | `show_hud_warning` — for visual feedback |
| `scripts/UIManager.gd` | 2405 | quest tracker — already has PICKUP_SPECIAL branch |
| `scenes/outpost_iron_reach.tscn` | 5 | node name `IronReachOutpost` |
| `scenes/outpost_kova.tscn` | 5 | node name `KovaStation` |

---

## Notes for the new agent

- The user is a solo dev on this project. They've been moving fast and want results. Don't over-explain — just do the work and report what's done.
- Each commit should be a logical unit. Don't bundle all 4 items into one commit. A natural split:
  1. `refactor(test): move test pickup quest through QuestManager.accept_quest` (Item 1)
  2. `feat(test): add 'Test: Pickup Part' button at outposts` (Item 2)
  3. `fix(outpost): dock submenu only shows undock + relevant buttons` (Item 3)
  4. `feat(npc): add 'Hear Gossip' button consuming flavor_lines` (Item 4)
- Run `git status` first to make sure the working tree is clean before starting.
- The user uses conventional commit style (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`).
- If something doesn't quite work, fix it before committing — don't leave broken state.
- Push to `origin master` when done. The last commit is `731c965`.

Good luck. The data layer is solid — this is just buttons and dispatch.
