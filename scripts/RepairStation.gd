extends StaticBody3D

## Dockable repair shop — a separate station that owns the repair + upgrade
## menus. The main station's dock menu no longer shows those; you dock here
## to access them. Visually themed as a grimy industrial hangar (Grease Monkeys).
##
## Use OutpostStation.gd as the structural template — same docking + entity
## registration pattern. Difference: this one sets station_type="repair_shop"
## so UIManager can branch the dock menu accordingly.

@export var display_name: String = "GREASE MONKEYS REPAIR SHOP"
@export var station_type: String = "repair_shop"   # UIManager reads this to show repair/upgrade UI only
@export var model_path: String = ""                 # Optional GLB. Falls back to procedural mesh if absent.
@export var model_instance_scale: float = 1.0       # Extra scale applied to the GLB model itself
@export var dock_offset: Vector3 = Vector3(0, 0, 25.0)  # World-relative offset where the player snaps when docking

var _model_loaded: bool = false

func _ready() -> void:
	add_to_group("station")

	# Register in the global entity list so distance checks / NPC targeting work
	if not GlobalState.active_system_entities.has(self):
		GlobalState.active_system_entities.append(self)

	# Try loading the GLB model
	if model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			model_instance.scale = Vector3.ONE * model_instance_scale
			add_child(model_instance)
			_model_loaded = true
		else:
			push_warning("[RepairStation] GLB not imported yet (%s). Using procedural fallback." % model_path)

	# Procedural fallback — visible until the GLB is imported and loaded
	if not _model_loaded:
		_build_fallback_mesh()

	# Collision shape — a generous box so the player can bump into the dock safely
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(30, 30, 30)
	col.shape = shape
	add_child(col)

	# Notify overview to refresh
	GlobalState.entities_changed.emit()
	print("[RepairStation] '", display_name, "' ready.")

func _build_fallback_mesh() -> void:
	# Industrial material — warm rust orange matching the Grease Monkeys palette
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.18, 0.10)
	mat.roughness = 0.85
	mat.metallic = 0.6

	# Lower hangar bay — wider than the outpost so the player reads it as different
	var core_mesh = BoxMesh.new()
	core_mesh.size = Vector3(18, 12, 22)
	core_mesh.material = mat
	var core = MeshInstance3D.new()
	core.mesh = core_mesh
	core.position = Vector3(0, 6, 0)
	add_child(core)

	# Catwalk truss on top
	var truss_mesh = CylinderMesh.new()
	truss_mesh.top_radius = 1.0
	truss_mesh.bottom_radius = 1.5
	truss_mesh.height = 4.0
	truss_mesh.material = mat
	var truss = MeshInstance3D.new()
	truss.mesh = truss_mesh
	truss.position = Vector3(0, 14, 0)
	add_child(truss)

	# Signpost light — bright orange to read as "open for business"
	var sign_mat = StandardMaterial3D.new()
	sign_mat.albedo_color = Color(1.0, 0.5, 0.1)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(1.0, 0.4, 0.05)
	sign_mat.emission_energy_multiplier = 2.0
	var sign_mesh = SphereMesh.new()
	sign_mesh.radius = 0.6
	sign_mesh.height = 1.2
	sign_mesh.material = sign_mat
	var sign = MeshInstance3D.new()
	sign.mesh = sign_mesh
	sign.position = Vector3(0, 16, 11)
	add_child(sign)

func _exit_tree() -> void:
	# Clean up entity registration when removed from scene
	GlobalState.active_system_entities.erase(self)

func _physics_process(delta: float) -> void:
	if GlobalState.paused:
		return
	# Gentle slow rotation so the station feels alive in space
	rotate_y(0.025 * delta)

func dock_player() -> void:
	# Walk up to MainScene, then find UIManager through the CanvasLayer
	var main = get_tree().current_scene
	var ui: Node = null
	if main:
		var canvas = main.get_node_or_null("CanvasLayer")
		if canvas:
			ui = canvas.get_node_or_null("UIManager")
	if ui and ui.has_method("toggle_dock_menu"):
		ui.toggle_dock_menu(self)
	else:
		push_warning("[RepairStation] dock_player(): Could not find UIManager node.")
