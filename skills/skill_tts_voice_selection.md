# Skill: TTS Voice Selection (Kokoro + per-NPC voices)

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
