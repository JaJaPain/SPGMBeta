extends StaticBody3D

@export var display_name: String = ""
@export var station_type: String = "full_service"  # "full_service" or "outpost"
@export var model_path: String = ""                # GLB path, e.g. "res://assets/space_station1.glb"
@export var model_instance_scale: float = 1.0      # Extra scale applied to the GLB model itself

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
			model_instance.scale = Vector3.ONE * model_instance_scale
			add_child(model_instance)
			
			# Auto-center: compute the AABB of the loaded model and shift
			# it so the visual center sits at the node origin (otherwise
			# the targeting reticle ends up at the model's feet/bottom).
			_center_model(model_instance)
			
			# Hide the default procedural Core + Ring meshes
			var core_node = get_node_or_null("Core")
			var ring_node = get_node_or_null("Ring")
			if core_node:
				core_node.visible = false
			if ring_node:
				ring_node.visible = false
				ring = null  # Don't try to spin the hidden ring
			print("[Station] GLB model loaded: ", model_path, " for '", name, "' scale=", model_instance_scale)
		else:
			push_warning("[Station] Could not load GLB: %s — using default mesh" % model_path)
	
	# Emit so overview refreshes with this station included
	GlobalState.entities_changed.emit()

func _center_model(model_root: Node3D) -> void:
	# Walk all MeshInstance3D descendants and build a merged AABB
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(model_root, meshes)
	if meshes.is_empty():
		return
	
	var combined_aabb: AABB = meshes[0].get_aabb()
	# Transform each mesh's local AABB into model_root-local space
	combined_aabb = meshes[0].transform * combined_aabb
	for i in range(1, meshes.size()):
		var mesh_aabb = meshes[i].transform * meshes[i].get_aabb()
		combined_aabb = combined_aabb.merge(mesh_aabb)
	
	# The center of the AABB (in model_root local space, pre-scale)
	var center = combined_aabb.get_center()
	# Shift the model so that center lands at the parent's origin
	model_root.position -= center * model_instance_scale
	print("[Station] Auto-centered '", name, "': AABB center offset = ", center)

func _find_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_meshes(child, out)

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
