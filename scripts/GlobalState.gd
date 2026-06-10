extends Node

# ── Ship Upgrade Caps ─────────────────────────────────────────────────────────
# Per-ship-class hard caps for every upgradeable stat. The current values are
# the starter-ship (INDYMiner) caps. If you add a heavier hauler ship class
# later, give it a different caps table.
#
# "max_level" is computed from cap vs base — change the cap and the upgrade
# list auto-extends. The maintenance bay UI reads these to render level text
# and disable buttons when maxed.
const SHIP_BASE_STATS = {
	"cargo_max_m3":       100.0,
	"mining_laser_yield": 2.0,
	"shield_capacity":    0.0,
	"engine_speed_mult":  1.0,
	"hull_armor":         0.0,
	"max_health":         100.0,
}
const SHIP_MAX_STATS = {
	"cargo_max_m3":       200.0,
	"mining_laser_yield": 5.0,
	"shield_capacity":    100.0,
	"engine_speed_mult":  1.5,
	"hull_armor":         50.0,
	"max_health":         200.0,
}
# Per-upgrade increment applied per level. Together with caps above, this
# defines the number of upgrade levels available.
const SHIP_UPGRADE_INCREMENT = {
	"cargo_max_m3":       25.0,
	"mining_laser_yield": 1.0,
	"shield_capacity":    25.0,
	"engine_speed_mult":  0.1,
	"hull_armor":         10.0,
	"max_health":         25.0,
}
# Quadratic cost curve: cost at level N = base_cost * 2^(N-1)
# (so 100, 200, 400, 800, 1600...). Stops 'buy everything on day 2' and
# makes each upgrade feel like a milestone.
const SHIP_UPGRADE_BASE_COST = {
	"cargo_max_m3":       100,
	"mining_laser_yield": 150,
	"shield_capacity":    800,
	"engine_speed_mult":  250,
	"hull_armor":         200,
	"max_health":         300,
}
# Which other upgrade level a given upgrade is GATED behind. Empty = no gate.
# Gating is a soft tutorial — you can't buy shields until you've expanded
# cargo once. Once you have the prerequisite level, the upgrade unlocks.
const SHIP_UPGRADE_GATES = {
	"shield_capacity":    { "requires_stat": "cargo_max_m3", "requires_level": 1 },
}

# ── Minor Faction Registry ────────────────────────────────────────────────────
# Data-driven: adding a new minor faction = one dict entry. No match arms needed.
# model: "faction1" | "faction2" | "aurelia" — which GLB to use
# tint: Color applied to hull meshes to visually distinguish from major factions
const MINOR_FACTIONS = {
	"reavers":  { "color": Color(0.9, 0.1, 0.15),  "projectile": Color(0.9, 0.15, 0.15), "model": "faction1", "tint": Color(0.85, 0.1, 0.1) },
	"obsidian": { "color": Color(0.5, 0.15, 0.8),   "projectile": Color(0.6, 0.2, 0.9),  "model": "faction1", "tint": Color(0.45, 0.1, 0.7) },
	"dustborn": { "color": Color(0.85, 0.65, 0.2),  "projectile": Color(0.9, 0.6, 0.1),  "model": "faction2", "tint": Color(0.8, 0.6, 0.15) },
	"wraiths":  { "color": Color(0.3, 0.9, 0.3),    "projectile": Color(0.3, 0.85, 0.3), "model": "faction2", "tint": Color(0.2, 0.75, 0.2) },
	"ironclad": { "color": Color(0.6, 0.6, 0.65),   "projectile": Color(0.8, 0.8, 0.85), "model": "aurelia",  "tint": Color(0.5, 0.5, 0.55) },
}

# ── Minor NPCs (quest givers, station contacts) ──────────────────────────────
# 8 portrait slots across 2 source images. Each source image is a 2x2 grid:
#   ┌───────────┬───────────┐
#   │ top_left  │ top_right │
#   ├───────────┼───────────┤
#   │ bot_left  │ bot_right │
#   └───────────┴───────────┘
# Left column = male, right column = female. Bottom-right of NPC02 is the
# Grease Monkeys mechanic (Jenna Kross).
# Keys are display names — the same string the LLM quest-gen puts in
# `agent_name`. Lookup by name returns image path + cell position.
# 8 portrait slots across 2 source images. Each source image is a 2x2 grid:
#   MinorNPC01.png: top-left=Cassen, top-right=Mariska, bottom-left=Korvin, bottom-right=Hana
#   MinorNPC02.png: top-left=Oleg,   top-right=Dasha,   bottom-left=Alaric, bottom-right=Jenna
# Each NPC has a `voice_id` (Kokoro voice) and `voice_speed` (slight modifier
# 0.85-1.10) for unique TTS voices — see skills/skill_using_tts_in_spacegame.md.
const MINOR_NPCS = {
	"Cassen Vane":   { "image": "res://assets/MinorNPC01.png", "position": "top_left",     "vibe": "grizzled mercenary, scars and salt-and-pepper hair", "outpost": "kova",       "voice_id": "am_onyx",   "voice_speed": 0.92, "flavor_color": Color(1.0, 0.6, 0.55), "flavor_lines": [
		"Kova's got no rules, Shiny. Just people with guns and people without.",
		"Vanguard patrols hit Sector 7 hard last week. Someone's paying them to.",
		"Aurelia tried to recruit me once. I declined. Politely. With a knife.",
	] },
	"Mariska Vonn":  { "image": "res://assets/MinorNPC01.png", "position": "top_right",    "vibe": "young blonde corporate fixer, white-and-gold outfit", "outpost": "iron_reach", "voice_id": "af_nicole", "voice_speed": 1.05, "flavor_color": Color(0.55, 0.85, 1.0), "flavor_lines": [
		"Zenith's been running the numbers on you, Shiny. Try not to disappoint the spreadsheet.",
		"Iron Reach's market is... complicated. Keep your credits close and your questions closer.",
		"Aurelia's been sniffing our freight lanes again. Don't ask what they're moving.",
	] },
	"Korvin Shaw":   { "image": "res://assets/MinorNPC01.png", "position": "bottom_left",  "vibe": "military veteran, mohawk and full plate armor", "outpost": "kova",       "voice_id": "am_michael", "voice_speed": 0.95, "flavor_color": Color(0.9, 0.85, 0.5), "flavor_lines": [
		"Vanguard trained me to follow orders. Kova taught me which orders to break.",
		"The frontier doesn't need heroes. It needs survivors.",
		"Zenith, Aurelia, Vanguard — pick your side, Shiny. Or pick none and die quietly.",
	] },
	"Hana Quill":    { "image": "res://assets/MinorNPC01.png", "position": "bottom_right", "vibe": "tech analyst, glasses and dark teal jacket", "outpost": "iron_reach", "voice_id": "af_kore",   "voice_speed": 1.0,  "flavor_color": Color(0.5, 0.95, 0.9), "flavor_lines": [
		"Vanguard's nav buoys are drifting. Either sloppy or probing. Neither's comforting.",
		"Aurelia's encrypted traffic spiked 40% last cycle. Something's moving.",
		"Need a firmware update? I can help. Need a favor? That costs more.",
	] },
	"Oleg Stroud":   { "image": "res://assets/MinorNPC02.png", "position": "top_left",     "vibe": "syndicate accountant, bald with a monocle", "outpost": "iron_reach", "voice_id": "am_fenrir", "voice_speed": 0.88, "flavor_color": Color(0.6, 1.0, 0.6), "flavor_lines": [
		"Books don't lie, Shiny. The credits tell the whole story.",
		"I keep the ledgers for half the brokers in this sector. Don't ask which half.",
		"You want a receipt? That'll be extra. Aurelia taught me that.",
	] },
	"Dasha Invar":   { "image": "res://assets/MinorNPC02.png", "position": "top_right",    "vibe": "edgy mercenary, undercut and blue leather", "outpost": "kova",       "voice_id": "af_nova",   "voice_speed": 1.08, "flavor_color": Color(1.0, 0.55, 0.7), "flavor_lines": [
		"Don't stare, Shiny. The tattoos have stories and none of them are short.",
		"Kova's where the contracts go when everywhere else gets too hot.",
		"You look like trouble. Good. Trouble pays well.",
	] },
	"Alaric Venn":   { "image": "res://assets/MinorNPC02.png", "position": "bottom_left",  "vibe": "corporate strategist, slicked hair and goatee", "outpost": "iron_reach", "voice_id": "am_liam",   "voice_speed": 0.98, "flavor_color": Color(0.7, 0.75, 1.0), "flavor_lines": [
		"Iron Reach runs clean. Mostly. Don't dig into the manifest logs.",
		"Zenith and Vanguard keep circling each other. We take notes and bill both sides.",
		"You ever wonder who really runs this sector? Follow the supply contracts.",
	] },
	"Jenna Kross":   { "image": "res://assets/MinorNPC02.png", "position": "bottom_right", "vibe": "mechanic with red hair, goggles, and tattoos", "role": "Grease Monkeys mechanic", "voice_id": "af_aoede", "voice_speed": 1.0, "flavor_color": Color(1.0, 0.85, 0.4), "flavor_lines": [
		"If it flies, I can fix it. If it doesn't fly, I can make it fly. Hand me the part.",
		"Your thruster's running hot. I can hear it from here. Pay me now or pay me later.",
		"The INDY Miner — classic chassis. Easy to work on, hard to keep running.",
	] },
}

# ── Station Safe Zones ────────────────────────────────────────────────────────
# NPCs won't initiate attacks on the player within safe zones if rep is above threshold.
# Minor factions ignore safe zones — they're outlaws.
const SAFE_ZONES = [
	{ "position": Vector3(0, 0, 180), "radius": 250.0 },  # Main Station
]
const SAFE_ZONE_REP_THRESHOLD = -40.0

static func is_minor_faction(faction_name: String) -> bool:
	return MINOR_FACTIONS.has(faction_name)

static func is_in_safe_zone(world_pos: Vector3) -> bool:
	for zone in SAFE_ZONES:
		if world_pos.distance_to(zone["position"]) <= zone["radius"]:
			return true
	return false

# Convert a numeric reputation value to a semantic tier label.
# 1.5b models understand semantic labels far better than raw numbers
# in the same token budget — they skip the "what does -50 mean" step.
# 9 tiers, symmetric around 0, with boundaries at 0 / ±25 / ±50 / ±75:
#   -100..-75   sworn enemy
#    -74..-50   hostile
#    -49..-25   unfriendly
#    -24..-1    wary
#         0     neutral
#      1..24    cordial
#     25..49    friendly
#     50..74    trusted
#     75..100   allied
static func reputation_tier(rep: float) -> String:
	if rep <= -75.0: return "sworn enemy"
	elif rep <= -50.0: return "hostile"
	elif rep <= -25.0: return "unfriendly"
	elif rep < 0.0: return "wary"
	elif rep == 0.0: return "neutral"
	elif rep <= 25.0: return "cordial"
	elif rep <= 50.0: return "friendly"
	elif rep <= 75.0: return "trusted"
	else: return "allied"

# Returns a UI color for the given reputation value, mapped to a
# red → amber → neutral → green gradient. Pairs with reputation_tier()
# so the tier label and the color always agree (same boundary values).
# Tier colors:
#   sworn enemy: deep red       Color(0.80, 0.10, 0.10)
#   hostile:     red            Color(1.00, 0.20, 0.20)
#   unfriendly:  orange-red     Color(1.00, 0.50, 0.20)
#   wary:        amber          Color(1.00, 0.80, 0.30)
#   neutral:     light gray     Color(0.80, 0.80, 0.80)
#   cordial:     yellow-green   Color(0.70, 1.00, 0.40)
#   friendly:    light green    Color(0.40, 0.90, 0.30)
#   trusted:     green          Color(0.20, 0.80, 0.20)
#   allied:      bright green   Color(0.10, 1.00, 0.40)
static func reputation_color(rep: float) -> Color:
	if rep <= -75.0: return Color(0.80, 0.10, 0.10)
	elif rep <= -50.0: return Color(1.00, 0.20, 0.20)
	elif rep <= -25.0: return Color(1.00, 0.50, 0.20)
	elif rep < 0.0: return Color(1.00, 0.80, 0.30)
	elif rep == 0.0: return Color(0.80, 0.80, 0.80)
	elif rep <= 25.0: return Color(0.70, 1.00, 0.40)
	elif rep <= 50.0: return Color(0.40, 0.90, 0.30)
	elif rep <= 75.0: return Color(0.20, 0.80, 0.20)
	else: return Color(0.10, 1.00, 0.40)

# Returns the display info for a major faction.
# Used to build the HUD rep tooltips ("Zenith (Corporate) — trusted (50)").
# Returns a dict with: name (full display name), descriptor (e.g. "Corporate"),
# abbrev (3-letter HUD abbreviation).
static func faction_info(faction_id: String) -> Dictionary:
	match faction_id.to_lower():
		"zenith":   return {"name": "Zenith",   "descriptor": "Corporate", "abbrev": "ZEN"}
		"aurelia":  return {"name": "Aurelia",  "descriptor": "Syndicate", "abbrev": "AUR"}
		"vanguard": return {"name": "Vanguard", "descriptor": "Military",  "abbrev": "VAN"}
		_:          return {"name": faction_id.capitalize(), "descriptor": "Unknown", "abbrev": faction_id.substr(0, 3).to_upper()}

# Returns the AtlasTexture for a minor NPC's portrait, sliced from its 2x2
# source image at the cell position stored in MINOR_NPCS.
# Returns null if the name isn't recognized or the image fails to load.
static func get_minor_npc_portrait(npc_name: String) -> AtlasTexture:
	if not MINOR_NPCS.has(npc_name):
		return null
	var npc: Dictionary = MINOR_NPCS[npc_name]
	var image = load(npc["image"]) as Texture2D
	if not image:
		return null
	var size: Vector2 = image.get_size()
	var cell_w: float = size.x / 2.0
	var cell_h: float = size.y / 2.0
	var x: float = 0.0
	var y: float = 0.0
	match npc["position"]:
		"top_left":     pass  # 0, 0
		"top_right":    x = cell_w
		"bottom_left":  y = cell_h
		"bottom_right":
			x = cell_w
			y = cell_h
	var atlas := AtlasTexture.new()
	atlas.atlas = image
	atlas.region = Rect2(x, y, cell_w, cell_h)
	return atlas

# Returns the list of minor NPC names stationed at a given outpost id
# (e.g. "iron_reach", "kova"). Returns an empty array if no NPCs are
# assigned. The mechanic (Jenna Kross) is excluded — she's at Grease Monkeys.
static func get_minor_npcs_at_outpost(outpost_id: String) -> Array:
	var result: Array = []
	for npc_name in MINOR_NPCS:
		if MINOR_NPCS[npc_name].get("outpost", "") == outpost_id:
			result.append(npc_name)
	return result

# Returns the outpost id for a minor NPC, or "" if they aren't outpost-based
# (e.g. the mechanic, who lives at Grease Monkeys).
static func get_minor_npc_outpost(npc_name: String) -> String:
	if not MINOR_NPCS.has(npc_name):
		return ""
	return MINOR_NPCS[npc_name].get("outpost", "")

# Returns a random minor NPC name. Used for picking a quest-board contact
# at an outpost when the player asks "who's hiring?"
static func random_minor_npc_name() -> String:
	var keys: Array = MINOR_NPCS.keys()
	return keys[randi() % keys.size()]

# Returns a random flavor line from a random NPC stationed at the given
# outpost, along with the NPC's name, chat-color, and TTS voice data.
# Drives the "Hear Gossip" button at outpost docks — each click rotates to
# a different NPC and a different line, so the player can keep clicking
# for variety. Returns an empty dict if the outpost has no NPCs assigned.
# Returned shape:
#   { "npc_name": String, "line": String, "color": Color,
#     "voice_id": String, "voice_speed": float }
# `voice_id` is a Kokoro voice name (e.g. "am_onyx", "af_nicole"). The
# default fallback is "af_bella" if an NPC has no voice data assigned.
# `voice_speed` is a 0.85-1.10 modifier that subtly differentiates
# voices that share an underlying voice family.
static func get_random_npc_flavor_line(outpost_id: String) -> Dictionary:
	var npcs: Array = get_minor_npcs_at_outpost(outpost_id)
	if npcs.is_empty():
		return {}
	var npc_name: String = npcs[randi() % npcs.size()]
	var npc: Dictionary = MINOR_NPCS[npc_name]
	var lines: Array = npc.get("flavor_lines", [])
	if lines.is_empty():
		return {}
	var line: String = lines[randi() % lines.size()]
	return {
		"npc_name": npc_name,
		"line": line,
		"color": npc.get("flavor_color", Color.WHITE),
		"voice_id": npc.get("voice_id", "af_bella"),
		"voice_speed": float(npc.get("voice_speed", 1.0)),
	}

# Returns the full set of (npc_name, line) pairs for every NPC at the
# given outpost, across all NPCs and all flavor lines. Used by the
# dock-time pre-cache so the first Hear Gossip click plays instantly
# in each NPC's unique voice. Returns an empty array if the outpost
# has no NPCs. Each entry is a Dictionary with the same shape as
# get_random_npc_flavor_line plus a redundant `outpost_id` for
# downstream logging.
static func get_outpost_flavor_tts_lines(outpost_id: String) -> Array:
	var result: Array = []
	var npcs: Array = get_minor_npcs_at_outpost(outpost_id)
	for npc_name in npcs:
		var npc: Dictionary = MINOR_NPCS[npc_name]
		var lines: Array = npc.get("flavor_lines", [])
		var voice_id: String = npc.get("voice_id", "af_bella")
		var voice_speed: float = float(npc.get("voice_speed", 1.0))
		for line in lines:
			result.append({
				"npc_name": npc_name,
				"line": line,
				"color": npc.get("flavor_color", Color.WHITE),
				"voice_id": voice_id,
				"voice_speed": voice_speed,
				"outpost_id": outpost_id,
			})
	return result

# Returns the remaining flavor lines for one NPC (excluding the line that
# was just played). Used by the "refresh-on-use" pre-cache: when a player
# hears a line and the cache miss path runs, we want the *next* click to
# hit cache, so we re-warm the NPC's other lines in the background.
# If `just_played` is empty or not in the list, returns every line.
static func get_other_flavor_lines_for_npc(npc_name: String, just_played: String) -> Array:
	if not MINOR_NPCS.has(npc_name):
		return []
	var npc: Dictionary = MINOR_NPCS[npc_name]
	var lines: Array = npc.get("flavor_lines", [])
	var result: Array = []
	for line in lines:
		if line == just_played:
			continue
		result.append({
			"npc_name": npc_name,
			"line": line,
			"color": npc.get("flavor_color", Color.WHITE),
			"voice_id": npc.get("voice_id", "af_bella"),
			"voice_speed": float(npc.get("voice_speed", 1.0)),
		})
	return result

signal target_changed(new_target: Node3D)
signal cargo_changed(new_cargo: float)
signal credits_changed(new_credits: int)
signal game_paused(paused: bool)

# Ship-upgrade signals. Emitted when a stat changes (via an upgrade) so
# the maintenance bay UI can refresh its display.
signal ship_stat_changed(stat_name: String, new_value: float)

# Player stats
var player_credits: int = 50:
	set(val):
		player_credits = val
		credits_changed.emit(player_credits)

var cargo: float = 0.0:
	set(val):
		cargo = clamp(val, 0.0, cargo_max)
		cargo_changed.emit(cargo)

# ── Cargo type system ──────────────────────────────────────────────────────
# The cargo hold is mutually exclusive: it holds EITHER ore (tracked by
# `cargo: float` in m³) OR a single special item (tracked by
# `cargo_special: Dictionary`), never both. This lets the mechanic and
# major agents hand the player a "pickup mission" part while still
# preserving ore as the standard minable resource.
#   EMPTY   — hold is empty, can accept either ore or a special item
#   ORE     — carrying ore (no special); player can keep mining
#   SPECIAL — carrying a single non-ore item; mining laser refuses to fire
enum CargoType { EMPTY, ORE, SPECIAL }

# What kind of cargo is currently in the hold.
var cargo_type: int = CargoType.EMPTY

# Special-cargo metadata. Empty dict when cargo_type != SPECIAL.
# Keys:
#   "name"        — short display string (e.g. "Replacement Plasma Coupler")
#   "description" — longer text for tooltips / chatter
#   "source"      — where the player picked it up (e.g. "Outpost Iron Reach")
#   "destination" — where it needs to be delivered (e.g. "Grease Monkeys")
var cargo_special: Dictionary = {}

# Active test pickup-quest state. Empty dict when no test quest is active.
# Used by the Grease Monkeys maintenance-bay debug buttons. Keys:
#   "outpost_id"     — "iron_reach" or "kova"
#   "outpost_display"— e.g. "Outpost Iron Reach"
#   "npc_name"       — which minor NPC at that outpost
#   "part_name"      — what to pick up
#   "picked_up"      — false until the player clicks Pickup at the outpost,
#                     then true (and the part is loaded into cargo_special)
var test_quest: Dictionary = {}

# Returns true if the hold can accept more ore (empty, or already ore with
# room left). Returns false if a special item is loaded.
func can_accept_ore() -> bool:
	return cargo_type == CargoType.EMPTY or cargo_type == CargoType.ORE

# Returns true if the hold can accept a special cargo item. Only valid
# when the hold is empty — can't swap out ore for a part.
func can_accept_special() -> bool:
	return cargo_type == CargoType.EMPTY

# Add ore to the hold. Returns the amount actually added (capped at
# cargo_max). Returns 0 if the hold can't accept ore (i.e. a special
# item is loaded).
func add_ore(amount: float) -> float:
	if not can_accept_ore():
		return 0.0
	var available = cargo_max - cargo
	var added = min(amount, available)
	if added <= 0.0:
		return 0.0
	cargo += added
	cargo_type = CargoType.ORE
	cargo_changed.emit(cargo)
	return added

# Accept a special cargo item. Only valid when the hold is empty.
# Returns true if accepted, false if the hold wasn't empty.
func accept_special(item_name: String, description: String, source: String, destination: String = "") -> bool:
	if not can_accept_special():
		return false
	cargo_special = {
		"name": item_name,
		"description": description,
		"source": source,
		"destination": destination,
	}
	cargo_type = CargoType.SPECIAL
	cargo_changed.emit(cargo)
	return true

# Remove a specific amount of ore. Returns the amount actually removed.
# If ore drops to 0, the hold auto-returns to EMPTY. Does nothing if the
# hold is carrying a special item.
func remove_ore(amount: float) -> float:
	if cargo_type != CargoType.ORE:
		return 0.0
	var removed = min(amount, cargo)
	removed = max(0.0, removed)
	cargo -= removed
	if cargo <= 0.0:
		clear_cargo()
	else:
		cargo_changed.emit(cargo)
	return removed

# Reset the hold to EMPTY. Used after quest delivery, sell-ore, and when
# the player jettisons or delivers a special item.
func clear_cargo() -> void:
	cargo = 0.0
	cargo_special = {}
	cargo_type = CargoType.EMPTY
	cargo_changed.emit(cargo)

# Returns a short display string for the HUD: "EMPTY", "ORE: 15 / 30 m³",
# or "SPECIAL: Replacement Plasma Coupler".
func cargo_display_text() -> String:
	match cargo_type:
		CargoType.EMPTY:
			return "EMPTY"
		CargoType.ORE:
			return "ORE: %d / %d m³" % [int(cargo), int(cargo_max)]
		CargoType.SPECIAL:
			return "SPECIAL: " + cargo_special.get("name", "(unnamed)")
	return ""

# Upgradeable ship stats — defaults sourced from SHIP_BASE_STATS so the
# starter ship is internally consistent with the cap table.
var cargo_max: float = SHIP_BASE_STATS["cargo_max_m3"]
var mining_yield: float = SHIP_BASE_STATS["mining_laser_yield"]
var shield_capacity: float = SHIP_BASE_STATS["shield_capacity"]
var engine_speed_mult: float = SHIP_BASE_STATS["engine_speed_mult"]
var hull_armor: float = SHIP_BASE_STATS["hull_armor"]
var player_max_health: float = SHIP_BASE_STATS["max_health"]

# Non-upgradeable baseline
var damage: float = 5.0
var laser_range: float = 80.0
var destroyed_ships_pool: int = 0

# Game references
var player: Node3D = null
var active_target: Node3D = null:
	set(val):
		active_target = val
		target_changed.emit(active_target)

var active_system_entities: Array[Node3D] = []
var paused: bool = false:
	set(val):
		paused = val
		game_paused.emit(paused)

# Reputation system
var reputations: Dictionary = {
	"zenith": 50.0,
	"aurelia": -20.0,
	"vanguard": -20.0
}
signal reputation_changed(faction_name: String, new_rep: float)
signal ship_destroyed(faction_name: String)
signal entities_changed()
signal system_chatter_received(sender: String, message: String, color: Color)

var faction_kills: Dictionary = {
	"zenith": 0,
	"aurelia": 0,
	"vanguard": 0
}

func record_kill(faction_name: String):
	# Track kills for ANY faction — including LLM-generated custom ones
	if not faction_kills.has(faction_name):
		faction_kills[faction_name] = 0
	faction_kills[faction_name] += 1
	# NOTE: ship_destroyed signal is now emitted by NPCShip.die() itself,
	# not here, so NPC-on-NPC kills also count toward quest progress.
	# Only call in reinforcements for the three main factions (they have matching ship scenes)
	if faction_name in ["zenith", "aurelia", "vanguard"] and faction_kills[faction_name] % 3 == 0:
		spawn_reinforcement(faction_name)

func spawn_reinforcement(faction_name: String):
	var player_node = player
	if not player_node or not is_instance_valid(player_node) or player_node.get("destroyed"):
		return
		
	# Find a random position around the player (e.g., 85m away)
	var angle = randf() * TAU
	var spawn_dist = 85.0
	var offset = Vector3(cos(angle), 0, sin(angle)) * spawn_dist
	var spawn_pos = player_node.global_position + offset
	
	# Load the NPC ship scene
	var npc_scene = load("res://scenes/npc_ship.tscn")
	if npc_scene:
		var npc = npc_scene.instantiate()
		npc.faction = faction_name
		npc.is_reinforcement = true
		npc.speed = 11.0
		npc.name = faction_name.to_upper() + "_EliteReinforcement_" + str(randi() % 1000)
		
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.add_child(npc)
			npc.global_position = spawn_pos
			
			# Trigger warning on HUD
			var ui = current_scene.get_node_or_null("CanvasLayer/UIManager")
			if ui and ui.has_method("show_hud_warning"):
				ui.show_hud_warning("WARNING: " + faction_name.to_upper() + " Elite Reinforcement has entered the area!")
			
			# Trigger system alert in chatter
			var alert = LLMInterface.get_chatter_line("system_alert")
			emit_chatter("SYSTEM", alert, Color(0.0, 0.9, 0.9))

func spawn_mission_targets(faction_name: String, count: int):
	var player_node = player
	if not player_node or not is_instance_valid(player_node) or player_node.get("destroyed"):
		return
	
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
	
	var npc_scene = load("res://scenes/npc_ship.tscn")
	if not npc_scene:
		print("[GlobalState] ERROR: Could not load npc_ship.tscn for mission targets.")
		return
	
	# Use the station as the spawn anchor so targets appear in open space,
	# not on top of the dock where the player accepted the quest
	var spawn_anchor: Vector3 = player_node.global_position
	var station_node = current_scene.get_node_or_null("Station")
	if station_node and is_instance_valid(station_node):
		spawn_anchor = station_node.global_position
	
	print("[GlobalState] Spawning ", count, " mission targets for faction: ", faction_name, " at distance from station")
	
	# Spread ships evenly in a ring 550-900m from the station — far enough
	# that the player has to fly out to engage, close enough to feel immediate
	for i in range(count):
		var angle = (TAU / count) * i + randf_range(-0.4, 0.4)
		var dist = randf_range(550.0, 900.0)
		var offset = Vector3(cos(angle), randf_range(-0.05, 0.05), sin(angle)) * dist
		var spawn_pos = spawn_anchor + offset
		
		var npc = npc_scene.instantiate()
		npc.faction = faction_name
		npc.is_reinforcement = false
		npc.name = faction_name.to_upper() + "_MissionTarget_" + str(randi() % 1000)
		# Mark as a quest target so QuestManager can count survivors and
		# decide when to spawn replacements after NPC kills.
		npc.set_meta("is_quest_target", true)
		current_scene.add_child(npc)
		npc.global_position = spawn_pos
	
	# HUD warning + chatter so the arrival feels like an event
	var ui = current_scene.get_node_or_null("CanvasLayer/UIManager")
	if ui and ui.has_method("show_hud_warning"):
		ui.show_hud_warning("CONTRACT ACTIVE: " + str(count) + " " + faction_name.to_upper() + " targets have entered the sector.")
	emit_chatter("SYSTEM", "Sensor sweep: " + str(count) + " " + faction_name.to_upper() + " signatures detected in open space.", Color(0.0, 0.9, 0.9))




func emit_chatter(sender: String, message: String, color: Color):
	system_chatter_received.emit(sender, message, color)

# Emits an NPC flavor line to the corner chatter panel AND a dedicated
# `npc_flavor_spoken` signal that carries the TTS routing data (voice
# ID + speed). UIManager listens on `npc_flavor_spoken` to fire TTS
# playback — system chatter (alerts, sensor sweeps) goes through
# `emit_chatter` and stays text-only. Use this for any line that should
# be spoken in the NPC's unique voice.
# Expected flavor shape: { "npc_name", "line", "color", "voice_id", "voice_speed" }
# (matches get_random_npc_flavor_line and get_outpost_flavor_tts_lines).
signal npc_flavor_spoken(flavor: Dictionary)
func emit_npc_flavor(flavor: Dictionary) -> void:
	if flavor.is_empty():
		return
	var sender: String = flavor.get("npc_name", "Local")
	var line: String = flavor.get("line", "")
	var color: Color = flavor.get("color", Color.WHITE)
	system_chatter_received.emit(sender, line, color)
	npc_flavor_spoken.emit(flavor)

func adjust_reputation(faction_name: String, amount: float):
	if reputations.has(faction_name):
		reputations[faction_name] = clamp(reputations[faction_name] + amount, -100.0, 100.0)
		reputation_changed.emit(faction_name, reputations[faction_name])

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()

# Called before reload_current_scene() to avoid dangling references into the freed scene.
func reset_for_restart():
	# Null out all node references first
	player = null
	active_system_entities.clear()
	# Directly set paused to avoid emitting game_paused into freed UIManager
	paused = false
	# Silently clear active_target without emitting target_changed
	active_target = null
	# Reset gameplay stats
	player_credits = 50
	cargo = 0.0
	cargo_max = SHIP_BASE_STATS["cargo_max_m3"]
	mining_yield = SHIP_BASE_STATS["mining_laser_yield"]
	shield_capacity = SHIP_BASE_STATS["shield_capacity"]
	engine_speed_mult = SHIP_BASE_STATS["engine_speed_mult"]
	hull_armor = SHIP_BASE_STATS["hull_armor"]
	player_max_health = SHIP_BASE_STATS["max_health"]
	damage = 5.0
	laser_range = 80.0
	destroyed_ships_pool = 0
	# Reset reputations
	reputations = { "zenith": 50.0, "aurelia": -20.0, "vanguard": -20.0 }
	# Reset kill tracking
	faction_kills = { "zenith": 0, "aurelia": 0, "vanguard": 0 }
	print("[GlobalState] State reset for new game.")


# ── Ship Upgrade Helpers ──────────────────────────────────────────────────────
# All these read from the cap tables above. The maintenance bay UI calls
# these to render button states; the apply functions call _apply_stat_upgrade
# to do the actual work.

# Returns the current level (0 = base, N = bought N upgrades) for a given stat.
# Level is derived from the current value, so the source of truth stays
# in the SHIP_BASE_STATS / SHIP_MAX_STATS tables.
func _get_stat_level(stat_name: String) -> int:
	if not SHIP_BASE_STATS.has(stat_name):
		return 0
	var base_val = SHIP_BASE_STATS[stat_name]
	var increment = SHIP_UPGRADE_INCREMENT.get(stat_name, 1.0)
	var current_val = _read_current_stat(stat_name)
	# How many increments above base?
	var diff = current_val - base_val
	if increment <= 0.0:
		return 0
	return int(round(diff / increment))

func _get_stat_max_level(stat_name: String) -> int:
	if not SHIP_BASE_STATS.has(stat_name):
		return 0
	var base_val = SHIP_BASE_STATS[stat_name]
	var cap_val = SHIP_MAX_STATS.get(stat_name, base_val)
	var increment = SHIP_UPGRADE_INCREMENT.get(stat_name, 1.0)
	var total_increments = cap_val - base_val
	if increment <= 0.0:
		return 0
	return int(round(total_increments / increment))

func _get_stat_current_value(stat_name: String) -> float:
	return _read_current_stat(stat_name)

func _get_stat_cap(stat_name: String) -> float:
	return SHIP_MAX_STATS.get(stat_name, _read_current_stat(stat_name))

# Quadratic cost: base_cost * 2^(current_level). So 100, 200, 400, 800...
func _get_upgrade_cost(stat_name: String) -> int:
	var base = SHIP_UPGRADE_BASE_COST.get(stat_name, 999999)
	var level = _get_stat_level(stat_name)
	return base * (1 << level)  # bit-shift = pow(2, level)

# Returns true if the upgrade is unlocked (passes any gates).
func _is_upgrade_unlocked(stat_name: String) -> bool:
	if not SHIP_UPGRADE_GATES.has(stat_name):
		return true
	var gate = SHIP_UPGRADE_GATES[stat_name]
	var prereq_level = _get_stat_level(gate["requires_stat"])
	return prereq_level >= int(gate["requires_level"])

# Returns true if the upgrade is maxed (level == max_level).
func _is_upgrade_maxed(stat_name: String) -> bool:
	return _get_stat_level(stat_name) >= _get_stat_max_level(stat_name)

# Apply the upgrade: bump the stat by one increment, deduct credits, emit signal.
# Returns true on success, false on failure (already maxed, gated, or broke).
func _apply_stat_upgrade(stat_name: String) -> bool:
	if _is_upgrade_maxed(stat_name):
		return false
	if not _is_upgrade_unlocked(stat_name):
		return false
	var cost = _get_upgrade_cost(stat_name)
	if player_credits < cost:
		return false
	player_credits -= cost
	var increment = SHIP_UPGRADE_INCREMENT[stat_name]
	var new_val = _read_current_stat(stat_name) + increment
	_write_current_stat(stat_name, new_val)
	ship_stat_changed.emit(stat_name, new_val)
	print("[GlobalState] Upgraded %s to %.1f for %d SC" % [stat_name, new_val, cost])
	return true

# Internal helpers — map the SHIP_BASE_STATS key to the live var name.
func _read_current_stat(stat_name: String) -> float:
	match stat_name:
		"cargo_max_m3":       return cargo_max
		"mining_laser_yield": return mining_yield
		"shield_capacity":    return shield_capacity
		"engine_speed_mult":  return engine_speed_mult
		"hull_armor":         return hull_armor
		"max_health":         return player_max_health
	return 0.0

func _write_current_stat(stat_name: String, val: float) -> void:
	match stat_name:
		"cargo_max_m3":       cargo_max = val
		"mining_laser_yield": mining_yield = val
		"shield_capacity":    shield_capacity = val
		"engine_speed_mult":  engine_speed_mult = val
		"hull_armor":         hull_armor = val
		"max_health":
			player_max_health = val
			# If player is currently at full HP, also bump their current HP up
			if player and is_instance_valid(player):
				var p_max = player.get("max_health")
				if player.get("health") >= p_max - 0.01:
					player.set("max_health", val)
					player.set("health", val)


func _setup_inputs():
	# Define EVE-like override autopilot keys
	_add_key_action("override_approach", KEY_Q)
	_add_key_action("override_orbit", KEY_W)
	_add_key_action("override_action", KEY_E)
	_add_key_action("pause_game", KEY_ESCAPE)
	_add_key_action("action_jump", KEY_J)
	
	# Define mouse zoom actions
	_add_mouse_action("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_action("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)

func _add_key_action(action_name: String, keycode: int):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event = InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_name, event)

func _add_mouse_action(action_name: String, button_index: int):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event = InputEventMouseButton.new()
		event.button_index = button_index
		InputMap.action_add_event(action_name, event)

# ── Dialogue Tone Guard ──────────────────────────────────────────────────────
# "Shiny" is Broker Kaelen's vocative for the player pilot. She uses it
# every line. Every other speaker in the game should NOT use it — it
# leaks her voice onto Jenna, minor NPCs, future quest givers, and
# anything else routed through the dialogue pipeline.
#
# This is a pure function — no state, no side effects. Safe to call from
# any thread or signal handler. TTSInterface routes its text through
# here, and any UI code that displays dialogue should too, so the
# on-screen text and the spoken audio stay in sync.
#
# Kaelen's voice after faction resolution is "af_bella" — that's how
# the call path identifies her. Anyone else gets the substitution.
const KAELEN_VOICE_ID: String = "af_bella"

# Substitutions for non-Kaelen speakers. Keyed on the source token
# (case-insensitive, word-boundary aware). Each entry's "to" is tried
# in order — first match wins. Add more rules here as more voice-leak
# bugs show up.
const TONE_REPLACEMENTS: Array = [
	# "Shiny" → "Indy" (preserves the call-out feel; matches the
	# player's ship class name, so it reads as "Indy pilot").
	{ "from": "shiny", "to": ["indy"] },
]

# Returns true if the resolved voice_id is Kaelen's. Cheap pointer
# check against KAELEN_VOICE_ID. Keep in sync with TTSInterface's
# get_voice_for_faction("neutral") — if you add a new broker voice
# for Kaelen, update both.
static func is_kaelen_voice(voice_id: String) -> bool:
	return voice_id == KAELEN_VOICE_ID

# Apply all TONE_REPLACEMENTS rules to `text` for a non-Kaelen speaker.
# Case-insensitive on the source token, but the replacement preserves
# the original casing style of the source (Title Case → "Indy", lower →
# "indy", upper → "INDY"). Word-boundary aware so we don't replace
# "Shiny" inside "Shinyman" or "Mishiny". Pure function.
static func apply_tone_guard(text: String, voice_id: String) -> String:
	# Kaelen keeps her own voice untouched.
	if is_kaelen_voice(voice_id):
		return text
	var out: String = text
	for rule in TONE_REPLACEMENTS:
		var from_token: String = rule["from"]
		var to_options: Array = rule["to"]
		# Build a word-boundary regex. (?i) for case-insensitive.
		# \b on either side keeps it from matching mid-word. We then
		# reconstruct the replacement in the original casing style.
		var regex := RegEx.new()
		regex.compile("(?i)\\b" + from_token + "\\b")
		var matches := regex.search_all(out)
		if matches.is_empty():
			continue
		# Replace from the back so earlier indices stay valid.
		for i in range(matches.size() - 1, -1, -1):
			var m: RegExMatch = matches[i]
			var original: String = m.get_string()
			# Pick the first option as the canonical replacement, then
			# match the original's casing style: ALL CAPS → upper,
			# Title Case → capitalized, else lower. Keeps the line
			# reading naturally in either case.
			var canonical: String = str(to_options[0])
			var replacement: String = _match_tone_casing(canonical, original)
			out = out.substr(0, m.get_start()) + replacement + out.substr(m.get_end())
	return out

# Internal: rebuild `replacement` in the casing style of `original`.
# "SHINY" → "INDY", "Shiny" → "Indy", "shiny" → "indy". Falls back to
# the canonical lowercase if the original's style doesn't match any
# recognized pattern.
static func _match_tone_casing(canonical: String, original: String) -> String:
	if original.length() == 0:
		return canonical
	if original == original.to_upper() and original != original.to_lower():
		return canonical.to_upper()
	if original[0] >= "A" and original[0] <= "Z":
		return canonical.capitalize()
	return canonical
