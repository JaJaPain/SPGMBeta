extends CharacterBody3D

@export var faction: String = "caldari" # caldari, amarr, minmatar
@export var max_health: float = 50.0
@export var speed: float = 10.0
@export var rotation_speed: float = 2.2

var health: float = 50.0
var patrol_center: Vector3
var target: Node3D = null
var fire_cooldown: float = 0.0
var destroyed: bool = false

var hardpoints: Array[Node3D] = []
var current_hp_index: int = 0
var hull_instance: Node3D = null

@onready var visual: Node3D = $Visual

# Preloads
var mesh_caldari = preload("res://assets/faction2.glb")
var mesh_amarr = preload("res://assets/F1HP.glb")
var mesh_minmatar = preload("res://assets/faction2.glb")

func _ready():
	health = max_health
	patrol_center = global_position
	
	# Add to entities list
	GlobalState.active_system_entities.append(self)
	
	# Load hull based on faction
	_setup_hull()

func _setup_hull():
	var hull_scene: PackedScene = null
	match faction:
		"caldari":
			hull_scene = mesh_caldari
		"amarr":
			hull_scene = mesh_amarr
		"minmatar":
			hull_scene = mesh_minmatar
			
	if hull_scene:
		hull_instance = hull_scene.instantiate()
		visual.add_child(hull_instance)
		
		# Set scale 6.0 and rotation Y 180 degrees (mirroring Ursina logic)
		hull_instance.scale = Vector3(6.0, 6.0, 6.0)
		hull_instance.rotation.y = PI
		
		# Set custom material color for Minmatar
		if faction == "minmatar":
			_apply_brown_tint(hull_instance)
			
		# Setup Amarr weapon hardpoint nodes
		if faction == "amarr":
			_setup_amarr_hardpoints(hull_instance)

func _apply_brown_tint(node: Node):
	if node is MeshInstance3D:
		var mat = node.get_active_material(0)
		if mat:
			var new_mat = mat.duplicate()
			new_mat.albedo_color = Color(0.55, 0.27, 0.07, 1.0) # Rust/brown
			node.set_surface_override_material(0, new_mat)
	for child in node.get_children():
		_apply_brown_tint(child)

func _setup_amarr_hardpoints(node: Node):
	var gun_names = ["TopRightGun", "BottomRightGun.001", "TopLeftGun", "BottomLeftGun.001"]
	if gun_names.has(node.name) and node is Node3D:
		hardpoints.append(node)
		# Hide the placeholder cube
		node.visible = false
	for child in node.get_children():
		_setup_amarr_hardpoints(child)

func _physics_process(delta: float):
	if GlobalState.paused or destroyed:
		return
		
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
		
	# Scanning and targeting
	if target == null or not is_instance_valid(target) or target.get("destroyed"):
		target = null
		# Find closest enemy ship within range
		var min_dist = 130.0
		for entity in GlobalState.active_system_entities + [GlobalState.player]:
			if entity and is_instance_valid(entity) and entity != self and not entity.get("destroyed"):
				# Caldari is friendly to player in starting Core Sec
				if faction == "caldari" and entity.is_in_group("player"):
					continue
				if entity.get("faction") != faction:
					var dist = global_position.distance_to(entity.global_position)
					if dist < min_dist:
						min_dist = dist
						target = entity
						
	# Movement Logic
	if target:
		steer_towards(target.global_position, delta)
		var dist = global_position.distance_to(target.global_position)
		if dist > 28.0:
			# Move towards target
			velocity = -global_transform.basis.z * speed
			move_and_slide()
		else:
			# In range: Fire!
			velocity = Vector3.ZERO
			if fire_cooldown <= 0.0:
				fire()
	else:
		# Patrol center behavior
		var dist_to_center = global_position.distance_to(patrol_center)
		if dist_to_center > 70.0:
			steer_towards(patrol_center, delta)
		else:
			# Orbit around patrol center
			rotation.y += 0.2 * delta
		
		# Move forward slowly
		velocity = -global_transform.basis.z * (speed * 0.5)
		move_and_slide()

func steer_towards(target_pos: Vector3, delta: float):
	var dummy = Node3D.new()
	add_child(dummy)
	dummy.global_position = global_position
	dummy.look_at(target_pos, Vector3.UP)
	
	var target_rot_y = dummy.rotation.y
	var diff_y = fposmod(target_rot_y - rotation.y + PI, TAU) - PI
	rotation.y += diff_y * delta * rotation_speed
	
	var target_rot_x = dummy.rotation.x
	var diff_x = fposmod(target_rot_x - rotation.x + PI, TAU) - PI
	rotation.x += diff_x * delta * rotation_speed
	
	dummy.queue_free()

func fire():
	fire_cooldown = 1.4
	AudioManager.play_laser()
	
	# Determine laser start position
	var spawn_pos = global_position + (-global_transform.basis.z * 1.8)
	if hardpoints.size() > 0:
		var hp = hardpoints[current_hp_index]
		if is_instance_valid(hp):
			spawn_pos = hp.global_position
		current_hp_index = (current_hp_index + 1) % hardpoints.size()
		
	# Spawn projectile
	var proj_scene = load("res://scenes/projectile.tscn")
	if proj_scene:
		var p = proj_scene.instantiate()
		p.direction = -global_transform.basis.z
		p.damage = 6.0
		p.faction = faction
		
		# Projectile color
		if faction == "caldari":
			p.color = Color.BLUE
		elif faction == "amarr":
			p.color = Color.GOLD
		else:
			p.color = Color.RED
			
		get_parent().add_child(p)
		p.global_position = spawn_pos

func take_damage(amount: float):
	if destroyed: return
	health -= amount
	if health <= 0.0:
		die()

func die():
	destroyed = true
	AudioManager.play_explosion()
	
	# Award credits to player if hit by player
	GlobalState.player_credits += 15
	
	# Remove from entities list
	GlobalState.active_system_entities.erase(self)
	
	# Play explosion FX here if desired
	queue_free()
