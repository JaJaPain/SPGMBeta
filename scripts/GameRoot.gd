extends Node3D

signal system_changed(system_id: String, arrival_gate_id: String)

const SYSTEM_SCENES: Dictionary = {
	"start_system": preload("res://scenes/systems/system_start.tscn"),
	"test_system": preload("res://scenes/systems/system_test.tscn"),
}
const ARRIVAL_COOLDOWN_SECONDS := 2.5

@onready var system_container: Node3D = $SystemContainer
@onready var player: CharacterBody3D = $PlayerShip

var transition_in_progress: bool = false
var jump_request_pending: bool = false
var arrival_cooldown_until_msec: int = 0

func _ready() -> void:
	var system_root := system_container.get_child(0) as Node3D
	GlobalState.active_system_root = system_root
	GlobalState.current_system_id = "start_system"
	if "--jump-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_jump_smoke_test")

func get_active_system_root() -> Node3D:
	return GlobalState.get_system_root()

func can_begin_jump() -> bool:
	return not transition_in_progress and not jump_request_pending and Time.get_ticks_msec() >= arrival_cooldown_until_msec

func request_gate_jump(gate: Node3D) -> bool:
	if not gate or not is_instance_valid(gate) or not gate.is_in_group("jumpgate"):
		return false
	if not can_begin_jump():
		return false
	var destination_system: String = gate.get("destination_system_id")
	var destination_gate: String = gate.get("destination_gate_id")
	if destination_system == "" or destination_gate == "":
		push_warning("[GameRoot] Jumpgate is missing destination metadata.")
		return false
	jump_request_pending = true
	call_deferred("_change_system", destination_system, destination_gate)
	return true

func _change_system(destination_system_id: String, arrival_gate_id: String) -> void:
	if transition_in_progress:
		jump_request_pending = false
		return
	var packed_system := SYSTEM_SCENES.get(destination_system_id) as PackedScene
	if not packed_system:
		jump_request_pending = false
		push_warning("[GameRoot] Unknown destination system '%s'." % destination_system_id)
		return

	var new_system := packed_system.instantiate() as Node3D
	var arrival_gate := _find_gate_in_tree(new_system, arrival_gate_id)
	if not arrival_gate:
		new_system.free()
		jump_request_pending = false
		push_error("[GameRoot] Destination gate '%s' was not found in '%s'." % [
			arrival_gate_id, destination_system_id
		])
		return

	jump_request_pending = false
	transition_in_progress = true
	_prepare_player_for_system_change()
	GlobalState.active_target = null
	GlobalState.active_system_entities.clear()

	var old_system := get_active_system_root()
	GlobalState.active_system_root = null
	if old_system and is_instance_valid(old_system):
		old_system.queue_free()
		await get_tree().process_frame

	system_container.add_child(new_system)
	GlobalState.active_system_root = new_system
	GlobalState.current_system_id = destination_system_id
	await get_tree().process_frame

	var arrival_transform: Transform3D = arrival_gate.call("get_arrival_transform")
	player.global_transform = arrival_transform

	_prepare_player_after_system_change()
	arrival_cooldown_until_msec = Time.get_ticks_msec() + int(ARRIVAL_COOLDOWN_SECONDS * 1000.0)
	transition_in_progress = false
	system_changed.emit(destination_system_id, arrival_gate_id)

	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("refresh_overview"):
		ui.call_deferred("refresh_overview")

func _find_gate(system_root: Node3D, gate_id: String) -> Node3D:
	for gate in get_tree().get_nodes_in_group("jumpgate"):
		if gate is Node3D and system_root.is_ancestor_of(gate) and gate.get("gate_id") == gate_id:
			return gate as Node3D
	return null

func _find_gate_in_tree(node: Node, gate_id: String) -> Node3D:
	if node is Node3D and node.is_in_group("jumpgate") and node.get("gate_id") == gate_id:
		return node as Node3D
	for child in node.get_children():
		var found := _find_gate_in_tree(child, gate_id)
		if found:
			return found
	return null

func _prepare_player_for_system_change() -> void:
	player.set("nav_mode", "MANUAL")
	player.set("target_position", null)
	player.set("is_aligning", false)
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)

func _prepare_player_after_system_change() -> void:
	player.velocity = Vector3.ZERO
	player.set("current_speed", 0.0)
	player.set("target_position", null)
	player.set("nav_mode", "MANUAL")
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)

func _run_jump_smoke_test() -> void:
	await get_tree().process_frame
	var starting_health: float = min(73.0, player.get("max_health"))
	var starting_shield: float = min(17.0, GlobalState.shield_capacity)
	player.set("health", starting_health)
	player.set("current_shield", starting_shield)

	var outbound_gate := _find_gate(get_active_system_root(), "start_to_test")
	if not outbound_gate or not request_gate_jump(outbound_gate):
		_fail_jump_smoke_test("Could not request outbound jump.")
		return
	await system_changed
	if GlobalState.current_system_id != "test_system":
		_fail_jump_smoke_test("Outbound jump loaded the wrong system.")
		return
	if not is_equal_approx(player.get("health"), starting_health) or not is_equal_approx(player.get("current_shield"), starting_shield):
		_fail_jump_smoke_test("Player health or shield changed during travel.")
		return

	var return_gate := _find_gate(get_active_system_root(), "test_to_start")
	if not return_gate:
		_fail_jump_smoke_test("Return gate was not found.")
		return
	var expected_arrival: Vector3 = return_gate.call("get_arrival_transform").origin
	if player.global_position.distance_to(expected_arrival) > 0.1:
		_fail_jump_smoke_test("Player did not arrive at the paired gate marker.")
		return

	arrival_cooldown_until_msec = 0
	if not request_gate_jump(return_gate):
		_fail_jump_smoke_test("Could not request return jump.")
		return
	await system_changed
	if GlobalState.current_system_id != "start_system":
		_fail_jump_smoke_test("Return jump loaded the wrong system.")
		return
	if not is_equal_approx(player.get("health"), starting_health) or not is_equal_approx(player.get("current_shield"), starting_shield):
		_fail_jump_smoke_test("Player state changed on the return jump.")
		return

	print("[JumpSmokeTest] PASS: two-way travel and player runtime state verified.")
	get_tree().quit(0)

func _fail_jump_smoke_test(message: String) -> void:
	push_error("[JumpSmokeTest] FAIL: " + message)
	get_tree().quit(1)
