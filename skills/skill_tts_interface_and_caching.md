# Skill: TTS Interface and Caching Strategy

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
