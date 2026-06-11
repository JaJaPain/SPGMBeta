# Skill: Creating Fetch Quests with LLM Dialogue Integration

This document outlines the architecture and steps required to build a "fetch quest" (pickup & deliver) in the SpaceGame project. Fetch quests rely heavily on the dynamic LLM dialogue system and the `QuestManager` singleton to ensure the world reacts appropriately to the player's quest state.

## 1. Rolling the Offer (GlobalState)
Before an NPC can offer a quest, the details need to be generated and cached. 
- In `GlobalState.gd`, create a function like `roll_pickup_offer()` that returns a Dictionary with the quest parameters (e.g., `npc_name`, `outpost_display`, `part_name`, `reward_credits`).
- Use random selection from existing data (like `OUTPOST_IDS.keys()` and `MINOR_NPCS.keys()`) to populate these fields.

## 2. Generating the Offer Dialogue (UIManager)
When the player interacts with the quest-giver (e.g., Jenna the Mechanic), their dialogue should be context-aware.

### The LLM Prompt & Few-Shot Examples
- Build a prompt that passes the `active_quest` state to the LLM. 
- **If no quest is active**: Provide the LLM with the details from `roll_pickup_offer()` and instruct it to offer the job to the player.
- **If the quest is active but the item isn't picked up**: Instruct the LLM to demand the item or tell the player to hurry up.
- **If the item is picked up**: Instruct the LLM to acknowledge the player has the item and ask them to hand it over.
- *Always provide few-shot examples (canned strings) in the prompt to enforce the NPC's specific tone (e.g., sarcastic, professional).*

### The Self-Critique Retry Loop
LLMs hallucinate or ignore constraints. Implement a recursive retry loop (e.g., `_request_mechanic_intro_attempt`) that checks the output against strict rules:
1. Parse the JSON response.
2. Validate it (e.g., "Did it mention the part name?", "Did it mention the ship name?").
3. If it fails, append a `SELF-CRITIQUE` suffix explaining the exact reason for the failure to the prompt and call the LLM again (up to a max of 2-3 attempts).
4. If all attempts fail, gracefully fall back to a predefined canned string.

## 3. Accepting the Quest (UIManager -> QuestManager)
Display "Accept" and "Decline" buttons. When the player accepts:
- Construct the `quest_data` dictionary. Crucially, set the `"objective": { "type": "PICKUP_SPECIAL" }` and include all the target details.
- Call `QuestManager.accept_quest(quest_data, selected_choice)`.
- **Bug Fix / Best Practice:** Immediately clear the locally cached offer (e.g. `_mechanic_pickup_offer = {}`) when the player accepts. This prevents the UI from incorrectly displaying the original offer buttons again when the player returns and completes the quest, since `QuestManager.is_quest_active()` evaluates to false after completion.

## 4. The Outpost Handoff (The Pickup)
When the player docks at the destination outpost to pick up the item:
- Validate that the player is at the correct station (`docked_outpost_id == QuestManager.active_quest.get("target_outpost")`).
- Trigger another LLM call for the outpost contact handing the item *to* the player. Provide the LLM with snarky few-shot examples (e.g., complaining about the quest-giver).
- Once the line is generated (or falls back), call `QuestManager.set_pickup_handoff()` and `QuestManager.mark_pickup_complete()`.
- **UI & Audio Routing:** To match the feel of the standard gossip system, use `show_dock_message()` to display the handoff text and portrait directly in the dock menu background. 
  - *Gotcha:* Ensure you call `_render_dock_submenu()` **before** `show_dock_message()`. Rendering the submenu clears the dock message, so if called after, it will instantly wipe the portrait and text!
  - Emit the text via `GlobalState.emit_npc_flavor(flavor_dict)`. This single call will simultaneously append the line to the persistent corner chat log and play the TTS audio. Do not call `TTSInterface.play_dialogue_audio` manually if you use this helper, otherwise the audio will double-play.
- This sets `picked_up = true` in the `active_quest` dictionary, preventing the player from picking it up twice and altering the origin NPC's dialogue state.

## 5. The Delivery
When the player returns to the origin location:
- In `_render_dock_submenu`, check if `QuestManager.active_quest.get("picked_up", false)` is `true`. If so, reveal the "Deliver Part" button.
- When pressed, call `QuestManager.complete_quest()` to clear the active quest and award credits.
- Display a success message. To keep the UI snappy, you can use a random pre-written "thank you" string (e.g., `FALLBACK_MECHANIC_THANKS`) combined with `TTSInterface.play_dialogue_audio()`, rather than making the player wait for another LLM generation just to collect their reward.
