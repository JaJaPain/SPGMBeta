extends Node

signal target_changed(new_target: Node3D)
signal cargo_changed(new_cargo: float)
signal credits_changed(new_credits: int)
signal game_paused(paused: bool)

# Player stats
var player_credits: int = 50:
	set(val):
		player_credits = val
		credits_changed.emit(player_credits)

var cargo: float = 0.0:
	set(val):
		cargo = clamp(val, 0.0, cargo_max)
		cargo_changed.emit(cargo)

var cargo_max: float = 100.0
var mining_yield: float = 2.0
var damage: float = 5.0
var speed_mult: float = 1.0
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
	ship_destroyed.emit(faction_name)
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
	cargo_max = 100.0
	mining_yield = 2.0
	damage = 5.0
	speed_mult = 1.0
	laser_range = 80.0
	destroyed_ships_pool = 0
	# Reset reputations
	reputations = { "zenith": 50.0, "aurelia": -20.0, "vanguard": -20.0 }
	# Reset kill tracking
	faction_kills = { "zenith": 0, "aurelia": 0, "vanguard": 0 }
	print("[GlobalState] State reset for new game.")


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
