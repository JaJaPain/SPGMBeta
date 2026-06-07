extends CharacterBody3D

@export var faction: String = "zenith" # zenith, aurelia, vanguard
@export var max_health: float = 50.0
@export var speed: float = 10.0
@export var rotation_speed: float = 2.2
@export var is_reinforcement: bool = false

var health: float = 50.0
var patrol_center: Vector3
var target: Node3D = null
var fire_cooldown: float = 0.0
var destroyed: bool = false
var last_attacker_faction: String = ""

var hardpoints: Array[Node3D] = []
var current_hp_index: int = 0
var hull_instance: Node3D = null

@onready var visual: Node3D = $Visual

# Preloads
var mesh_zenith = preload("res://assets/faction2.glb")
var mesh_aurelia = preload("res://assets/F1HP.glb")
var mesh_vanguard = preload("res://assets/faction2.glb")

func _ready():
	if is_reinforcement:
		max_health = 100.0
		scale = Vector3(1.5, 1.5, 1.5)
		
	health = max_health
	patrol_center = global_position
	
	# Add to entities list
	GlobalState.active_system_entities.append(self)
	GlobalState.entities_changed.emit()
	
	# Load hull based on faction
	_setup_hull()

func _setup_hull():
	var hull_scene: PackedScene = null
	match faction:
		"zenith":
			hull_scene = mesh_zenith
		"aurelia":
			hull_scene = mesh_aurelia
		"vanguard":
			hull_scene = mesh_vanguard
			
	if hull_scene:
		hull_instance = hull_scene.instantiate()
		visual.add_child(hull_instance)
		
		# Set scale 6.0 and rotation Y 180 degrees (mirroring Ursina logic)
		hull_instance.scale = Vector3(6.0, 6.0, 6.0)
		hull_instance.rotation.y = PI
		
		# Set custom material color for Vanguard
		if faction == "vanguard":
			_apply_brown_tint(hull_instance)
			
		# Setup Aurelia weapon hardpoint nodes
		if faction == "aurelia":
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
		
	# Check target distance leash
	if target and is_instance_valid(target):
		var dist = global_position.distance_to(target.global_position)
		if dist > 150.0:
			target = null
		
	# Scanning and targeting
	if target == null or not is_instance_valid(target) or target.get("destroyed"):
		target = null
		
		# Elite reinforcements target the player immediately
		if is_reinforcement:
			var p = GlobalState.player
			if p and is_instance_valid(p) and not p.get("destroyed"):
				target = p
				
		if target == null:
			# Find closest enemy within range (could be player or other NPC)
			var min_dist = 130.0
			var best_target: Node3D = null
			
			# 1. Check if player is an enemy and in range
			var p = GlobalState.player
			if p and is_instance_valid(p) and not p.get("destroyed"):
				var is_player_enemy = false
				if GlobalState.reputations.has(faction) and GlobalState.reputations[faction] < -10.0:
					is_player_enemy = true
					
				if is_player_enemy:
					var dist_to_player = global_position.distance_to(p.global_position)
					if dist_to_player < min_dist:
						min_dist = dist_to_player
						best_target = p
						
			# 2. Check other active system entities (NPC ships)
			for entity in GlobalState.active_system_entities:
				if entity and is_instance_valid(entity) and entity != self and not entity.get("destroyed"):
					if entity.get("faction") != faction:
						var dist = global_position.distance_to(entity.global_position)
						if dist < min_dist:
							min_dist = dist
							best_target = entity
							
			if best_target:
				target = best_target
							
	# Movement & Combat Logic
	if target:
		steer_towards(target.global_position, delta)
		var dist = global_position.distance_to(target.global_position)
		
		# Move towards target if we are beyond our stopping cushion
		if dist > 30.0:
			velocity = -global_transform.basis.z * speed
			move_and_slide()
		else:
			velocity = Vector3.ZERO
			
		# Fire at the target if within weapon range (60.0m) and aligned (within 30 degrees)
		if dist <= 60.0:
			var to_target = (target.global_position - global_position).normalized()
			var forward = -global_transform.basis.z.normalized()
			var angle = forward.angle_to(to_target)
			if angle < deg_to_rad(30.0):
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
	var to_target = target_pos - global_position
	if to_target.length() > 1.0:
		var target_dir = to_target.normalized()
		if abs(target_dir.dot(Vector3.UP)) < 0.99:
			var target_basis = Basis.looking_at(target_dir, Vector3.UP)
			var target_rot = target_basis.get_euler()
			
			var diff_y = fposmod(target_rot.y - rotation.y + PI, TAU) - PI
			var diff_x = fposmod(target_rot.x - rotation.x + PI, TAU) - PI
			
			rotation.y += diff_y * delta * rotation_speed
			rotation.x += diff_x * delta * rotation_speed

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
		p.damage = 12.0 if is_reinforcement else 6.0
		p.faction = faction
		
		# Projectile color
		if faction == "zenith":
			p.color = Color.BLUE
		elif faction == "aurelia":
			p.color = Color.GOLD
		else:
			p.color = Color.RED
			
		get_parent().add_child(p)
		p.global_position = spawn_pos

func take_damage(amount: float, attacker_faction: String = ""):
	if destroyed: return
	health -= amount
	if attacker_faction == "player":
		GlobalState.adjust_reputation(faction, -2.0) # Aggro drop rep on hit
		last_attacker_faction = "player"
		
		# Immediately target the player to defend itself!
		var p = GlobalState.player
		if p and is_instance_valid(p) and not p.get("destroyed"):
			target = p
	elif attacker_faction != "":
		last_attacker_faction = attacker_faction
		
	if health <= 0.0:
		die()

func die():
	destroyed = true
	AudioManager.play_explosion()
	
	# Award credits and apply reputation changes if killed by player
	if last_attacker_faction == "player":
		GlobalState.player_credits += 15
		_apply_reputation_changes()
		GlobalState.record_kill(faction)
	
	# Remove from entities list
	GlobalState.active_system_entities.erase(self)
	GlobalState.entities_changed.emit()
	
	# Play explosion FX here if desired
	queue_free()

func _apply_reputation_changes():
	# Decrease reputation with the killed faction
	GlobalState.adjust_reputation(faction, -20.0)
	
	# Increase reputation with enemies
	match faction:
		"zenith":
			GlobalState.adjust_reputation("vanguard", 10.0)
		"aurelia":
			GlobalState.adjust_reputation("vanguard", 10.0)
		"vanguard":
			GlobalState.adjust_reputation("zenith", 10.0)
			GlobalState.adjust_reputation("aurelia", 10.0)
