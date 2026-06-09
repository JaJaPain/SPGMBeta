# Future Contacts — Design Notes

Kaelen acts as the broker who introduces all contacts to the player.
The pattern is: **Kaelen intro → Contact briefing → Player choice → Mission → Kaelen payout**.

Adding a new contact requires only two file changes:
- `scripts/LLMInterface.gd` — new `match` arm with persona, voice, player nickname, example JSON
- `scripts/UIManager.gd` — new `match` arm with 5 Kaelen handoff intro variations

The `_:` fallback in both files means any new agent works immediately even before
custom lines are written.

---

## Planned Contacts

### 🕵️ The Black Market Contact
- **Faction:** Stateless / Underworld
- **Unlocks:** Only appears after player reputation with any faction drops below -50 (burned bridges = criminal work)
- **Player nickname:** *Indy*
- **Tone:** Cold, transactional, speaks in short clipped sentences. No names, no records.
- **Kaelen's angle:** Visibly uncomfortable introducing them — she owes them a favour
- **Example Kaelen intro:** *"Shiny. This one I can't vouch for. But the credits are real. Don't ask questions."*
- **Mission types:** Smuggling runs (DELIVER_ORE with contraband flavour), assassination contracts (KILL_SHIPS with high bounty)

---

### 🔧 The Salvager Guild Rep
- **Faction:** Independent (ties to Kira Thorne / salvager NPCs already in game)
- **Unlocks:** After player completes 3+ DELIVER_ORE missions (shows up as a regular)
- **Player nickname:** *Indy*
- **Tone:** Cheerful, pragmatic, talks in salvager slang. Treats every job like a treasure hunt.
- **Kaelen's angle:** Fond of them — they bring in reliable low-risk contracts
- **Example Kaelen intro:** *"Oh good timing Shiny, the guild rep's here. Easy work, decent pay. My kind of morning."*
- **Mission types:** Ore delivery, wreckage recovery (could add a new SALVAGE objective type)

---

### ⭐ The Faction Admiral
- **Faction:** Zenith / Aurelia / Vanguard (one per faction, unlocks at rep 80+)
- **Unlocks:** High reputation milestone with that faction — elite pilots only
- **Player nickname:** *Indy*
- **Tone:** Formal, authoritative, treats the player as a proven asset not just a contractor
- **Kaelen's angle:** Clearly impressed — rare for her — makes a point of it
- **Example Kaelen intro:** *"Shiny. I don't say this often — this one's a big deal. Admiral's asking for you personally."*
- **Mission types:** High kill count, elite target ships, much higher rewards and rep stakes

---

### 🃏 The Rival Broker
- **Faction:** Neutral (competitor to Kaelen)
- **Unlocks:** Random chance after 10+ quests — Kaelen is forced to sub-contract
- **Player nickname:** *Indy* (deliberately impersonal — they don't do nicknames)
- **Tone:** Slick, overconfident, subtly undermines Kaelen while being charming to the player
- **Kaelen's angle:** Barely civil — this one visibly irritates her, great comedy potential
- **Example Kaelen intro:** *"So. Turns out I owe a colleague a favour. Don't get comfortable with them, Shiny. I'll be taking you back after this."*
- **Mission types:** Any — but framed as poaching Kaelen's best pilot, higher immediate payout, minor Kaelen rep penalty

---

## Implementation Checklist (per new contact)

- [ ] Add `match` arm in `LLMInterface.request_quest_generation()` with:
  - `agent_name`
  - `agent_role`
  - `player_nickname`
  - `agent_persona` (system prompt identity)
  - 3x `example_response` lines
- [ ] Add `match` arm in `UIManager._on_quest_generated_received()` with 5 Kaelen handoff intro variations
- [ ] Add portrait sprite to `QuestGivers.png` spritesheet (next available cell)
- [ ] Map faction string → portrait atlas region in `_update_agent_portrait()`
- [ ] Add TTS voice assignment in `TTSInterface.get_voice_for_faction()`
- [ ] (Optional) Add unlock condition check before quest generation selects this contact
