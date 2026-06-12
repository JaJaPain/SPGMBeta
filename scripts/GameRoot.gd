extends Node3D

@onready var system_container: Node3D = $SystemContainer

func _ready() -> void:
	var system_root := system_container.get_child(0) as Node3D
	GlobalState.active_system_root = system_root
	GlobalState.current_system_id = "start_system"

func get_active_system_root() -> Node3D:
	return GlobalState.get_system_root()
