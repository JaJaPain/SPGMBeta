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
signal entities_changed()

var faction_kills: Dictionary = {
	"zenith": 0,
	"aurelia": 0,
	"vanguard": 0
}

func record_kill(faction_name: String):
	if faction_kills.has(faction_name):
		faction_kills[faction_name] += 1
		# If the player has killed a multiple of 3 ships of this faction, call in a "big gun"
		if faction_kills[faction_name] % 3 == 0:
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

func adjust_reputation(faction_name: String, amount: float):
	if reputations.has(faction_name):
		reputations[faction_name] = clamp(reputations[faction_name] + amount, -100.0, 100.0)
		reputation_changed.emit(faction_name, reputations[faction_name])

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()

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
