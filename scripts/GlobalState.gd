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
var damage: float = 10.0
var speed_mult: float = 1.0
var laser_range: float = 80.0

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
