# Using TTS in SpaceGame (Kokoro + per-NPC voices)

## Overview

SpaceGame runs **Kokoro TTS** locally for all spoken dialogue — Kaelen
the broker, ambient chatter, and the eight minor NPC flavor lines at
outpost docks. Each NPC has a **unique Kokoro voice** so the player can
tell Cassen from Mariska from Hana without looking at the corner
chatter log. This skill explains how to use the TTS interface, how
voices are routed, and how to add or change a voice for any speaker.

- **TTS server:** `scripts/tts_server.py` (FastAPI + Kokoro-82M, `lang_code='a'`)
- **TTS client:** `scripts/TTSInterface.gd` (autoload, in-memory WAV cache)
- **Voice routing:** per-NPC `voice_id` + `voice_speed` in `GlobalState.MINOR_NPCS`
- **Pipeline:** speaker (broker / flavor) → `play_dialogue_audio` → cache hit/miss → Kokoro HTTP `/tts` → `AudioStreamWAV` → `Voice` bus

---

## How voices are selected

Kokoro exposes two parameters in the `/tts` endpoint:

| Param  | What it does                                              | Notes                                                              |
| ------ | --------------------------------------------------------- | ------------------------------------------------------------------ |
| `voice` | Picks a speaker (e.g. `am_onyx`, `af_nicole`)            | **The primary identity axis.** Different voices always sound different. |
| `speed` | 0.5 – 2.0 rate modifier (we use 0.85 – 1.10)            | Subtle variation only — Kokoro has no `pitch` parameter in the wrapper we use. To get a "new" voice, **change `voice_id`, not speed.** |

Kokoro's American English catalog (`lang_code='a'`, which SpaceGame
uses) has 20 voices — 11 female (`af_*`) and 9 male (`am_*`). Full
list with quality grades:
[huggingface.co/hexgrad/Kokoro-82M/VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).

> **Pitch is not a parameter in our wrapper.** The Kokoro pipeline
> call in `tts_server.py` is
> `pipeline(text, voice=voice, speed=speed, split_pattern=r'\n+')`.
> If you want a higher- or lower-pitched voice, pick a different
> `voice_id` from the catalog. `speed` only changes tempo, which
> perceptually *sounds* like a slight pitch shift at extremes — a
> side-effect, not a control. The voices I chose for the 8 minor
> NPCs are intentionally distinct enough that no two share a family.

---

## How the 8 minor NPCs are voiced

Every entry in `GlobalState.MINOR_NPCS` (see `scripts/GlobalState.gd`)
has a `voice_id` (Kokoro voice name) and a `voice_speed` (subtle
modifier, 0.85–1.10):

| NPC              | Vibe                            | `voice_id`   | `voice_speed` |
| ---------------- | ------------------------------- | ------------ | ------------- |
| Cassen Vane      | grizzled mercenary              | `am_onyx`    | 0.92          |
| Mariska Vonn     | corporate fixer                 | `af_nicole`  | 1.05          |
| Korvin Shaw      | military veteran                | `am_michael` | 0.95          |
| Hana Quill       | tech analyst                    | `af_kore`    | 1.0           |
| Oleg Stroud      | syndicate accountant            | `am_fenrir`  | 0.88          |
| Dasha Invar      | edgy mercenary                  | `af_nova`    | 1.08          |
| Alaric Venn      | corporate strategist            | `am_liam`    | 0.98          |
| Jenna Kross      | Grease Monkeys mechanic         | `af_aoede`   | 1.0           |

Pick rules I followed:
- **8 distinct voices**, no two NPCs share `voice_id`. Otherwise lines
  from different speakers sound identical.
- **`voice_speed` is in 0.85–1.10.** Below 0.85 the audio gets
  noticeably muddy; above 1.10 it sounds rushed and loses warmth.
- **Match the vibe loosely:** older/menacing/serious → low male
  voices at <1.0 speed; sharp/young/fast-talking → female voices at
  >1.0 speed. The voice catalogue's "Traits" column (🚺 / 🚹 / 🎧 / 🔥)
  is just a hint, not a contract.

To change an NPC's voice: edit the `voice_id` and/or `voice_speed`
fields in their dict inside `GlobalState.MINOR_NPCS`. No other code
needs to change — the dock pre-cache, the gossip handler, and the
chatter signal all read the data from the dict.

---

## Two TTS call shapes (legacy + per-NPC)

`TTSInterface` exposes both shapes, used in different contexts:

```gdscript
# LEGACY: faction-based. Used by the Kaelen broker dialogue path.
# Resolves faction -> voice via get_voice_for_faction(), speed=1.0.
TTSInterface.play_dialogue_audio(line, "neutral")   # af_bella
TTSInterface.play_dialogue_audio(line, "zenith")    # am_adam
TTSInterface.play_dialogue_audio(line, "aurelia")   # af_sarah
TTSInterface.play_dialogue_audio(line, "vanguard")  # am_michael

# NEW: per-NPC. Used by flavor chatter. Voice id is the Kokoro
# voice name (e.g. "am_onyx"). Speed is a 0.85-1.10 modifier.
TTSInterface.play_dialogue_audio(line, voice_id, voice_speed)
TTSInterface.cache_dialogue_audio(line, voice_id, voice_speed)
```

How the disambiguation works: the TTS interface checks the second
argument against a known-faction list (`_is_known_faction`). If it's
a faction name, the legacy path runs. If it's anything else (a
Kokoro voice id), the per-NPC path runs. **Don't pass an empty
string** unless you want the default faction (`"neutral"` →
`af_bella`) — the empty string is also treated as a faction.

---

## Cache key shape

The TTS cache is keyed on **`<voice_id>|<cleaned_text>`**, not just
text. This means:

- The same flavor line spoken by two NPCs (with different
  `voice_id`s) is cached separately — switching speakers means a
  different WAV.
- Legacy `"neutral"` callers key under `af_bella|<text>`, which
  matches the resolved voice and behaves the same as the old
  text-only key on the lookup side.
- The cache is **in-memory only** — it does not persist between
  game sessions. Each fresh launch re-caches from scratch.

Why the change: with 8 distinct voices, two NPCs could realistically
share a flavor line in the future, and the per-voice key is the only
way to keep them from clobbering each other.

---

## Pre-cache strategy (dock-time + refresh-on-use)

The first time the player docks at an outpost, all 9–12 flavor
lines for that outpost's NPCs are pre-cached in the background
(`UIManager.toggle_dock_menu`, the `is_outpost` branch). The
existing TTS infrastructure handles the queueing, parallelism, and
the TTS-not-ready path automatically.

For the case where the player ignores the dock and the
background pre-cache hasn't finished (or the TTS server wasn't
ready), the **refresh-on-use** rule kicks in inside
`_on_hear_gossip_pressed`:

```gdscript
# After picking a flavor line and showing the popup, pre-cache
# the NPC's OTHER flavor lines in the background. By the next
# click, those lines are likely cached.
var other_lines: Array = GlobalState.get_other_flavor_lines_for_npc(npc_name, line)
for entry in other_lines:
    TTSInterface.cache_dialogue_audio(entry["line"], entry["voice_id"], entry["voice_speed"])
```

The cache dedupes via the key, so this is a no-op for lines that
were already pre-cached on dock. The cost is just a dictionary
lookup and a `queue` skip.

---

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

---

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

---

## Verifying TTS works in the editor

The cheapest end-to-end check (no manual listening required):

1. Open the project in Godot, play the main scene.
2. Fly to an outpost (e.g. Iron Reach).
3. Dock → click "Hear Gossip from the Locals".
4. Watch the editor log (`Output` panel): you should see something
   like
   ```
   [TTSInterface] Requesting speech for: <line> using voice: af_nicole speed: 1.05
   ```
   followed within ~1-2s by
   ```
   [TRACE] [TTSInterface] Playing speech audio stream
   ```
5. Click Hear Gossip again. The second click should hit cache
   (look for `CACHE HIT at: ... voice=af_nicole. Playing immediately!`
   in the log).
6. Switch to a different NPC by clicking again — you should see a
   different `voice=` in the request line (e.g. `am_onyx` for
   Cassen Vane at Kova).

If you see `CACHE MISS` on every click, the dock-time pre-cache
isn't running — usually a sign that `is_outpost` is false because
the station's `station_type` export isn't `"outpost"`, or the TTS
server wasn't ready when you docked (the cache_queue flush should
handle this, but check the log for `Queueing cache request`).

---

## Common gotchas

- **The flavor dict must have `voice_id` and `voice_speed`.** If
  either is missing, the TTS interface falls back to
  `af_bella` / speed 1.0 — so the NPC will still speak, but in
  the default voice. This is the right behavior for system
  alerts, not for an NPC whose identity should be consistent.

- **Don't strip `voice_id` when copying flavor data.** When you
  build a new dict for `emit_npc_flavor`, copy the voice fields
  through. The two helpers (`get_random_npc_flavor_line`,
  `get_outpost_flavor_tts_lines`) already do this; if you write a
  new helper, follow the same shape.

- **Don't use `play_dialogue_audio("")` to test the new path.**
  The empty string short-circuits with `Cleaned text is empty,
  skipping speech.` before voice_id is ever inspected. Use a real
  line. (`play_dialogue_audio("")` is still safe to use as a
  "stop voice" signal during undock — see `UIManager.undock_player`
  and `_on_agent_back_pressed`.)

- **Voices outside the American English catalog are not
  available** unless you also change `KPipeline(lang_code='a')` in
  `scripts/tts_server.py` and add a fallback for the language
  code. British, Japanese, etc. need a separate server pipeline.
  Don't try to use `bf_*` or `jm_*` voice ids on the current
  server — the request will fail.

- **Kokoro's TTS server runs on port 5000.** If the port is in
  use, the server fails to launch and all pre-caches queue up
  forever. Check the editor log for `Background cache request
  failed. Code: 0` or `Connection refused` — that means the
  server didn't start.

- **Audio ducking.** When the TTS plays, `AudioManager.duck_audio`
  lowers the music + SFX bus. When it finishes, the `finished`
  signal on `AudioStreamPlayer` restores them. If a flavor line
  is interrupted by a new line (e.g. player mashes the button),
  the unduck can be missed — `TTSInterface` always re-ducks at
  the start of the next line, so it's a transient volume blip
  at worst.

---

## Reference: file map

| File                                                  | What it owns                                                                 |
| ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| `scripts/tts_server.py`                               | FastAPI wrapper around Kokoro. `POST /tts` accepts `text/voice/speed`.       |
| `scripts/TTSInterface.gd`                             | Autoload. `play_dialogue_audio`, `cache_dialogue_audio`, WAV cache, queue.   |
| `scripts/GlobalState.gd`                              | `MINOR_NPCS` data, `emit_npc_flavor`, `npc_flavor_spoken` signal.            |
| `scripts/UIManager.gd`                                | `_on_hear_gossip_pressed`, `show_npc_dialogue_popup`, dock-time pre-cache.   |
| `assets/MinorNPC01.png` / `MinorNPC02.png`            | 2x2 source portraits, sliced at runtime by `GlobalState.get_minor_npc_portrait`. |

---

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
