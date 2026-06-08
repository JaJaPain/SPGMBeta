extends StaticBody3D

@export var display_name: String = ""
@export var station_type: String = "full_service"  # "full_service" or "outpost"
@export var model_path: String = ""                # GLB path, e.g. "res://assets/space_station1.glb"

@onready var ring: MeshInstance3D = $Ring

func _ready():
	add_to_group("station")
	
	# Register in the global entity list so NPCs / overview can find us
	if not GlobalState.active_system_entities.has(self):
		GlobalState.active_system_entities.append(self)
	
	# If a GLB model path is set, load it and hide the default procedural mesh
	if model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			add_child(model_instance)
			# Hide the default procedural Core + Ring meshes
			var core_node = get_node_or_null("Core")
			var ring_node = get_node_or_null("Ring")
			if core_node:
				core_node.visible = false
			if ring_node:
				ring_node.visible = false
				ring = null  # Don't try to spin the hidden ring
			print("[Station] GLB model loaded: ", model_path, " for '", name, "'")
		else:
			push_warning("[Station] Could not load GLB: %s — using default mesh" % model_path)
	
	# Emit so overview refreshes with this station included
	GlobalState.entities_changed.emit()

func _exit_tree():
	GlobalState.active_system_entities.erase(self)

func _physics_process(delta: float):
	if GlobalState.paused: return
	
	# Spin the station's outer ring (mirroring the Ursina behavior)
	if ring:
		ring.rotate_y(0.12 * delta)
	
	# Gentle slow rotation for outposts (GLB models)
	if model_path != "":
		rotate_y(0.025 * delta)

func dock_player():
	var ui = get_node_or_null("../CanvasLayer/UIManager")
	if ui and ui.has_method("toggle_dock_menu"):
		ui.toggle_dock_menu(self)
