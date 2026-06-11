# Skill: Adding Minor NPCs and Routing Gossip

## The "all flavor lines speak" rule

`GlobalState.emit_chatter(sender, message, color)` is a **generic
helper** for any chatter that should appear in the corner log —
including SYSTEM sensor alerts and other LLM-generated chatter that
the user does *not* want spoken. Don't use it for flavor lines.

Use `GlobalState.emit_npc_flavor(flavor)` instead. It does two
things:

1. Emits `system_chatter_received` (so the corner log updates —
   same as the generic helper).
2. Emits `npc_flavor_spoken(flavor)` (a dedicated signal that
   carries the TTS voice data). `UIManager._on_npc_flavor_spoken`
   is connected to it in `_create_chat_window_panel` and fires
   `TTSInterface.play_dialogue_audio(line, voice_id, speed)`.

The expected `flavor` shape (matches what
`GlobalState.get_random_npc_flavor_line` and
`get_outpost_flavor_tts_lines` return):

```gdscript
{
    "npc_name": String,    # display name, e.g. "Cassen Vane"
    "line": String,        # the spoken line
    "color": Color,        # chatter tint
    "voice_id": String,    # Kokoro voice id
    "voice_speed": float,  # 0.85-1.10
}
```

If you add a new speaker (e.g. a new minor NPC, a quest-giver
bot), follow this pattern: include `voice_id` + `voice_speed` in
the flavor dict and route it through `emit_npc_flavor`. Don't
bypass the helper and call `play_dialogue_audio` directly from
the corner log — that would also speak system alerts.

## How the dock-time flow works end-to-end

1. **Player docks at outpost** → `UIManager.toggle_dock_menu` runs
   the `is_outpost` branch.
2. **Pre-cache** calls `GlobalState.get_outpost_flavor_tts_lines(outpost_id)`
   → returns an array of flavor dicts (one per line across all
   NPCs at that outpost). For each, `TTSInterface.cache_dialogue_audio`
   fires a background HTTP request per line. Returns immediately;
   does not block the dock UI.
3. **Player clicks "Hear Gossip"** → `_on_hear_gossip_pressed` runs.
4. `GlobalState.get_random_npc_flavor_line(outpost_id)` returns one
   random flavor dict for a random NPC at the outpost.
5. `show_npc_dialogue_popup(line, npc_name, color, portrait)` shows
   the portrait + name + line chip in the NPC's color, centered
   near the top of the screen, auto-dismisses after 4.0s + 1.5s fade.
6. `GlobalState.emit_npc_flavor(flavor)` appends the line to the
   corner log AND fires the `npc_flavor_spoken` signal.
7. `UIManager._on_npc_flavor_spoken(flavor)` calls
   `TTSInterface.play_dialogue_audio(line, voice_id, speed)`.
8. The cache check: if the line was in the dock-time pre-cache
   (or already in cache from a prior click), the WAV plays
   immediately. Otherwise the HTTP request fires and the line
   plays 1-2s later.
9. **Refresh-on-use** queues the NPC's other flavor lines for
   background pre-cache.
10. **The cycle repeats** — by the second click on the same NPC,
    the next line is cached and plays instantly.

## Quick recipe: add a new NPC

```gdscript
# 1. Add the entry to GlobalState.MINOR_NPCS (in scripts/GlobalState.gd):
"Mira Soraya": {
    "image": "res://assets/MinorNPC02.png",  # pick a free cell or extend the atlas
    "position": "top_right",                  # free slot in the 2x2
    "vibe": "trader with short red hair and a flight suit",
    "outpost": "iron_reach",
    "voice_id": "af_sky",     # NEW unique voice (not used by any other NPC)
    "voice_speed": 1.0,
    "flavor_color": Color(0.9, 0.7, 1.0),
    "flavor_lines": [
        "Credits talk, Shiny. Mine are talking right now.",
        "Ever been to the rim? Don't. The cargo's not worth the paperwork.",
        "I trade in parts. If it bolts, glues, or welds, I move it.",
    ],
},
```

```gdscript
# 2. Use it. The flavor line helper, the dock pre-cache, and the
# gossip handler all read from MINOR_NPCS — no other changes needed.
var flavor: Dictionary = GlobalState.get_random_npc_flavor_line("iron_reach")
# flavor["voice_id"] == "af_sky", flavor["voice_speed"] == 1.0
```

```gdscript
# 3. If you want her to also appear in the dock chatter feed or
# fire ambient lines, route through emit_npc_flavor:
GlobalState.emit_npc_flavor(flavor)
```

Done. The voice routing, cache, and refresh-on-use are all wired.
