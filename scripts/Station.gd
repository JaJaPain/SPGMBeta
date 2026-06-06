extends StaticBody3D

@onready var ring: MeshInstance3D = $Ring

func _ready():
	add_to_group("station")

func _physics_process(delta: float):
	if GlobalState.paused: return
	
	# Spin the station's outer ring (mirroring the Ursina behavior)
	if ring:
		ring.rotate_y(0.12 * delta)

func dock_player():
	var ui = get_node_or_null("../CanvasLayer/UIManager")
	if ui and ui.has_method("toggle_dock_menu"):
		ui.toggle_dock_menu(self)
