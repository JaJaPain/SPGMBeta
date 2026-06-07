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
var taunted_player: bool = false

var hardpoints: Array[Node3D] = []
var current_hp_index: int = 0
var hull_instance: Node3D = null

# Archetype attributes
var archetype: String = "Balanced"
var fire_cooldown_min: float = 1.3
var fire_cooldown_max: float = 1.5
var damage_min: float = 5.5
var damage_max: float = 6.5

@onready var visual: Node3D = $Visual

# Preloads
var mesh_zenith = preload("res://assets/faction2.glb")
var mesh_aurelia = preload("res://assets/F1HP.glb")
var mesh_vanguard = preload("res://assets/faction2.glb")

func _generate_archetype():
	var roll = randf()
	var visual_scale_mult: float = 1.0
	
	if roll < 0.25:
		# Balanced (Patrol)
		archetype = "Patrol"
		max_health = randf_range(45.0, 55.0)
		speed = randf_range(9.0, 11.0)
		rotation_speed = 2.2
		fire_cooldown_min = 1.3
		fire_cooldown_max = 1.5
		damage_min = 5.5
		damage_max = 6.5
		visual_scale_mult = 1.0
	elif roll < 0.50:
		# Heavy Tank (Sentinel)
		archetype = "Sentinel"
		max_health = randf_range(85.0, 95.0)
		speed = randf_range(6.5, 7.5)
		rotation_speed = 1.6
		fire_cooldown_min = 1.6
		fire_cooldown_max = 2.0
		damage_min = 3.5
		damage_max = 4.5
		visual_scale_mult = 1.3
	elif roll < 0.75:
		# Glass Cannon (Raider)
		archetype = "Raider"
		max_health = randf_range(20.0, 25.0)
		speed = randf_range(9.5, 10.5)
		rotation_speed = 2.4
		fire_cooldown_min = 1.0
		fire_cooldown_max = 1.2
		damage_min = 11.0
		damage_max = 13.0
		visual_scale_mult = 0.9
	else:
		# Swift Interceptor (Interceptor)
		archetype = "Interceptor"
		max_health = randf_range(30.0, 40.0)
		speed = randf_range(15.0, 17.0)
		rotation_speed = 3.0
		fire_cooldown_min = 0.7
		fire_cooldown_max = 0.9
		damage_min = 3.0
		damage_max = 4.0
		visual_scale_mult = 0.8
		
	# Apply Elite Reinforcement Multiplier if applicable
	if is_reinforcement:
		max_health = max_health * 2.0
		damage_min = damage_min * 1.5
		damage_max = damage_max * 1.5
		visual_scale_mult = visual_scale_mult * 1.5
		archetype = "Elite " + archetype
		
	# Apply Quest Combat Multiplier if target of active combat quest
	if QuestManager.is_quest_active() and QuestManager.active_quest["objective_type"] == "KILL_SHIPS" and QuestManager.active_quest["target_faction"] == faction:
		var q_mult = QuestManager.active_quest["combat_multiplier"]
		if q_mult > 1.0:
			max_health *= q_mult
			damage_min *= q_mult
			damage_max *= q_mult
			visual_scale_mult *= (1.0 + (q_mult - 1.0) * 0.4)
			archetype = "Target " + archetype
			
	health = max_health
	
	# Apply visual/collision scaling
	scale = Vector3(visual_scale_mult, visual_scale_mult, visual_scale_mult)
	
	# Override name to display archetype in UI
	name = faction.to_upper() + " " + archetype + " " + str(randi() % 1000)

func _ready():
	_generate_archetype()
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
	if target == null or not is_instance_valid(target) or target.get("destroyed") or (target == GlobalState.player and GlobalState.player.get("is_docked")):
		target = null
		
		# Elite reinforcements target the player immediately
		if is_reinforcement:
			var p = GlobalState.player
			if p and is_instance_valid(p) and not p.get("destroyed") and not p.get("is_docked"):
				target = p
				
		if target == null:
			# Find closest enemy within range (could be player or other NPC)
			var min_dist = 130.0
			var best_target: Node3D = null
			
			# 1. Check if player is an enemy and in range
			var p = GlobalState.player
			if p and is_instance_valid(p) and not p.get("destroyed") and not p.get("is_docked"):
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
		
		# Move forward at full speed if far from patrol center, otherwise slowly
		var speed_factor = 1.0 if dist_to_center > 150.0 else 0.5
		velocity = -global_transform.basis.z * (speed * speed_factor)
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
	fire_cooldown = randf_range(fire_cooldown_min, fire_cooldown_max)
	AudioManager.play_laser(global_position)
	
	# If targeting the player, trigger hostile taunt
	if target == GlobalState.player:
		if not taunted_player:
			taunted_player = true
			var taunt = LLMInterface.get_chatter_line("hostile_taunt")
			var fac_color = Color(1.0, 1.0, 1.0)
			match faction:
				"zenith": fac_color = Color(1.0, 0.6, 0.1) # Orange
				"aurelia": fac_color = Color(0.85, 0.2, 0.2) # Red
				"vanguard": fac_color = Color(0.2, 0.7, 1.0) # Cyan/Blue
			GlobalState.emit_chatter(name, taunt, fac_color)
	
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
		p.damage = randf_range(damage_min, damage_max)
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
	AudioManager.play_explosion(global_position)
	
	# Spawn wreckage
	var wreck_script = load("res://scripts/Wreckage.gd")
	if wreck_script:
		var wreck = StaticBody3D.new()
		wreck.set_script(wreck_script)
		wreck.name = name + "_Wreck"
		get_parent().add_child(wreck)
		wreck.global_position = global_position
		wreck.global_rotation = global_rotation
		wreck.add_to_group("wreckage")
		wreck.call("initialize", visual)
		
	GlobalState.destroyed_ships_pool += 1
	
	# Award credits and apply reputation changes if killed by player
	if last_attacker_faction == "player":
		GlobalState.player_credits += 15
		_apply_reputation_changes()
		
		# Trigger death cry chatter
		var cry = LLMInterface.get_chatter_line("death_cry")
		var fac_color = Color(1.0, 1.0, 1.0)
		match faction:
			"zenith": fac_color = Color(1.0, 0.6, 0.1)
			"aurelia": fac_color = Color(0.85, 0.2, 0.2)
			"vanguard": fac_color = Color(0.2, 0.7, 1.0)
		GlobalState.emit_chatter(name, cry, fac_color)
		
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
