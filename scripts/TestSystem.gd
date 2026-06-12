extends Node3D

func _ready() -> void:
	GlobalState.active_system_root = self
	GlobalState.current_system_id = "test_system"
	call_deferred("_refresh_overview")

func _refresh_overview() -> void:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("refresh_overview"):
		ui.refresh_overview()
