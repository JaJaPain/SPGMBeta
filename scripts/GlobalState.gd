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
