# SPACE GRID INTRUSION — World Lore

<!--
==========================================================================
  CONTEXT BUDGET GUIDE — READ THIS BEFORE EDITING
==========================================================================

This file is injected into every LLM quest-generation prompt.
More text = slower response times and higher chance of the model
forgetting instructions or clipping important details.

CURRENT BUDGET:
  The quest prompt already uses ~600-800 tokens for persona, player
  stats, mission history, JSON examples, and generation rules.
  The model also needs ~500-800 tokens to write its JSON response.

  Model context windows (common Ollama models):
    qwen2.5:1.5b    →  ~4,096 tokens  (budget: ~400 words of lore)
    qwen3:8b         →  ~8,192 tokens  (budget: ~1,200 words of lore)
    gemma4:12b       → ~32,768 tokens  (budget: ~3,000+ words of lore)

  A WARNING will print in the Godot console if this file exceeds
  a safe threshold for your active model.

TIPS:
  • Keep it under 500 words for small models (1.5b–3b).
  • Every sentence should earn its place — if the LLM won't use it
    to write better quests, cut it.
  • Bullet points are more token-efficient than prose paragraphs.
  • Don't duplicate info already in the agent persona prompts
    (character voice, nickname rules — those are handled in code).
  • Faction *relationships* and *motivations* matter most for quests.
    Ship stats, UI colors, and engine details do NOT — leave those out.

CURRENT WORD COUNT: ~480 words (safe for all models)
==========================================================================
-->

## Setting

The year is unspecified. Humanity has expanded into deep space. The player operates in a contested sector containing one main station, two outposts (Iron Reach and Kova Station), a gas giant with an asteroid belt, and a rocky planet with its own belt. Shipping lanes connect these locations but are frequently raided.

## The Player

An independent mining pilot flying a modified hauler called the INDY Miner. New to the sector, unaligned with any faction, scraping together credits through ore runs and mercenary contracts brokered through Kaelen. Everyone calls them "Indy" — short for independent. Kaelen calls them "Shiny" — her word for unscarred greenhorns.

## Factions

### Zenith (Corporate)
- A profit-driven megacorporation focused on resource extraction and logistics.
- Controls mining operations, station infrastructure, and shipping networks.
- Cold, efficient, treats contractors as expendable assets.
- The player starts on relatively good terms with Zenith.

### Aurelia (Syndicate)
- A shadowy criminal syndicate running smuggling, piracy, and black market trade.
- Operates through front companies and off-the-books deals.
- Charming on the surface, ruthless underneath. Everything is "an opportunity."
- Hostile to the player initially — trust must be earned through jobs.

### Vanguard (Military)
- A militaristic faction enforcing order through firepower.
- Protects shipping lanes but also runs aggressive patrols and blockades.
- Gruff, professional, respects competence. Uses military shorthand.
- Hostile to the player initially. Both Zenith and Aurelia dislike them.

### Faction Tensions
- Zenith and Aurelia compete for trade dominance but cooperate against Vanguard.
- Vanguard considers both Zenith and Aurelia threats to sector stability.
- Killing Vanguard ships earns favor with both Zenith and Aurelia.
- Working for one faction often angers another.

## Minor Factions

Minor factions are hostile outlaws with no diplomatic ties. They serve as primary targets for elimination contracts.

- **Reavers** — Violent pirates who raid shipping lanes. No allegiance, no mercy. Known for aggressive hit-and-run attacks on cargo haulers.
- **Obsidian** — Shadow operatives and saboteurs. They target infrastructure and supply lines. Nobody knows who funds them.
- **Dustborn** — Belt scavenger bandits who ambush miners in asteroid fields. They strip ships for parts and sell the scrap.
- **Wraiths** — Ghost raiders that appear without warning and vanish just as fast. Favor guerrilla tactics and sensor jamming.
- **Ironclad** — Remnants of a dissolved military unit gone rogue. Well-armed and disciplined but answer to no faction.

## Economy

- Currency: Space Credits (SC). The player starts nearly broke.
- Primary resource: Silicate Ore: Sold per m³. Permit required; legal stations buy unpermitted ore at a steep discount, while black markets pay a high premium. 
- Upgrades: cargo hold expansions, mining laser improvements, ship repairs.
- All contracts go through Broker Kaelen, who always takes her cut.

## Tone

Cynical, profit-driven, darkly humorous. Everyone has an angle. Credits are king. The sector is dangerous but opportunity is everywhere for pilots willing to get their hands dirty. Think freelance mercenary in a corporate-criminal warzone — not heroic space opera.
