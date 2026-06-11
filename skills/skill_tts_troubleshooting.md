# Skill: TTS Troubleshooting and Reference

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

## Reference: file map

| File                                                  | What it owns                                                                 |
| ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| `scripts/tts_server.py`                               | FastAPI wrapper around Kokoro. `POST /tts` accepts `text/voice/speed`.       |
| `scripts/TTSInterface.gd`                             | Autoload. `play_dialogue_audio`, `cache_dialogue_audio`, WAV cache, queue.   |
| `scripts/GlobalState.gd`                              | `MINOR_NPCS` data, `emit_npc_flavor`, `npc_flavor_spoken` signal.            |
| `scripts/UIManager.gd`                                | `_on_hear_gossip_pressed`, `show_npc_dialogue_popup`, dock-time pre-cache.   |
| `assets/MinorNPC01.png` / `MinorNPC02.png`            | 2x2 source portraits, sliced at runtime by `GlobalState.get_minor_npc_portrait`. |
