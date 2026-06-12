extends StaticBody3D

@export var gate_id: String = ""
@export var display_name: String = "HYPERGATE"
@export var destination_system_id: String = ""
@export var destination_gate_id: String = ""
@export var destination_display_name: String = "UNKNOWN SYSTEM"
@export var activation_range: float = 130.0
@export var model_scale: float = 0.5

@onready var model_anchor: Node3D = $ModelAnchor
@onready var arrival_marker: Marker3D = $ArrivalMarker

func _ready() -> void:
	add_to_group("jumpgate")
	if not GlobalState.active_system_entities.has(self):
		GlobalState.active_system_entities.append(self)
	_center_and_scale_model()
	GlobalState.entities_changed.emit()

func _exit_tree() -> void:
	GlobalState.active_system_entities.erase(self)

func get_arrival_transform() -> Transform3D:
	return arrival_marker.global_transform

func is_player_in_activation_range() -> bool:
	var player := GlobalState.player
	return player != null and is_instance_valid(player) and global_position.distance_to(player.global_position) <= activation_range

func _center_and_scale_model() -> void:
	var model_root := model_anchor.get_child(0) as Node3D
	if not model_root:
		push_warning("[JumpGate] Missing hypergate model instance for gate '%s'." % gate_id)
		return
	model_root.scale = Vector3.ONE * model_scale

	var meshes: Array[MeshInstance3D] = []
	_find_meshes(model_root, meshes)
	if meshes.is_empty():
		push_warning("[JumpGate] Hypergate model contains no meshes.")
		return

	var combined := AABB()
	var first := true
	for mesh in meshes:
		var relative := model_root.global_transform.affine_inverse() * mesh.global_transform
		var mesh_aabb := relative * mesh.get_aabb()
		if first:
			combined = mesh_aabb
			first = false
		else:
			combined = combined.merge(mesh_aabb)

	model_root.position = -combined.get_center() * model_scale

func _find_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_find_meshes(child, meshes)
