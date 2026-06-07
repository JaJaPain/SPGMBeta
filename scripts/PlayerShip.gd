extends CharacterBody3D

@export var max_speed: float = 25.0
@export var max_health: float = 100.0
var health: float = 100.0
var faction: String = "player"
var destroyed: bool = false
var is_docked: bool = false
@export var rotation_speed: float = 3.5

# Navigation variables
var target_position: Variant = null # null or Vector3
var is_aligning: bool = false:
	set(val):
		if val != is_aligning:
			is_aligning = val
			if is_aligning:
				AudioManager.play_align()

var nav_mode: String = "MANUAL":
	set(val):
		if val != nav_mode:
			nav_mode = val
			if val in ["APPROACH", "APPROACH_1K", "ORBIT", "MINE", "ATTACK", "DOCK"]:
				is_aligning = false
				is_aligning = true

var fire_cooldown: float = 0.0

# Camera controls
var camera_aligned: bool = true
var last_nav_mode: String = "MANUAL"
var rmb_down_time: float = 0.0
var last_target: Node3D = null
var drones: Array[Node3D] = []
var drone_rotations: Array[Vector3] = []

@onready var visual: Node3D = $Visual
@onready var mining_laser: MeshInstance3D = $MiningLaser
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

func _ready():
	GlobalState.player = self
	mining_laser.visible = false
	
	# Decouple camera pivot transform from player's parent transform
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position
	camera_pivot.rotation_degrees = Vector3(-15, 0, 0) # Pitch down, looking at player
	
	# Connect to target change signal
	GlobalState.target_changed.connect(_on_target_changed)
	
	# Create two orbiting drones
	_create_drones()

func _on_target_changed(new_target: Node3D):
	if new_target == null:
		mining_laser.visible = false
		if nav_mode in ["APPROACH", "APPROACH_1K", "ORBIT", "MINE", "ATTACK", "DOCK"]:
			nav_mode = "MANUAL"
			target_position = null

func _unhandled_input(event: InputEvent):
	# Autopilot override keys
	if event.is_action_pressed("override_approach"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			nav_mode = "APPROACH"
			var ui = get_node_or_null("../CanvasLayer/UIManager")
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)
	elif event.is_action_pressed("override_orbit"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			nav_mode = "ORBIT"
			var ui = get_node_or_null("../CanvasLayer/UIManager")
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)
	elif event.is_action_pressed("override_action"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			if t.is_in_group("asteroid"):
				nav_mode = "MINE"
			elif t.is_in_group("station"):
				nav_mode = "DOCK"
			else:
				nav_mode = "ATTACK"
			var ui = get_node_or_null("../CanvasLayer/UIManager")
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)

	# Handle Mouse Zoom
	if event.is_action_pressed("zoom_in"):
		camera.position.z = max(camera.position.z - 1.5, 6.0)
	elif event.is_action_pressed("zoom_out"):
		camera.position.z = min(camera.position.z + 1.5, 50.0)
		
	# RMB Click vs Drag detection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			rmb_down_time = Time.get_unix_time_from_system()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			var hold_duration = Time.get_unix_time_from_system() - rmb_down_time
			if hold_duration < 0.25:
				# Short RMB click: Try targeting / open context menu
				var hit = get_mouse_raycast_hit()
				if hit.has("collider"):
					var entity = hit.collider
					while entity and entity.get_parent() != get_parent():
						entity = entity.get_parent()
					if entity and entity != self:
						GlobalState.active_target = entity
						var ui = get_node_or_null("../CanvasLayer/UIManager")
						if ui and ui.has_method("show_context_menu"):
							ui.show_context_menu(entity)
							
	# Drag Camera Orbit
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * 0.003
		camera_pivot.rotation.x -= event.relative.y * 0.003
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -deg_to_rad(80), deg_to_rad(80))
		camera_aligned = true # Release camera alignment control
		
	# Left Click & Double-click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			# Free space movement steering
			var hit = get_mouse_raycast_hit()
			if hit.has("position"):
				double_click_move(hit.position)
			else:
				# Clicked into deep space, project a point in forward depth
				var mouse_pos = get_viewport().get_mouse_position()
				var ray_normal = camera.project_ray_normal(mouse_pos)
				double_click_move(camera.global_position + ray_normal * 150.0)
		else:
			# Single click selection
			var hit = get_mouse_raycast_hit()
			if hit.has("collider"):
				var entity = hit.collider
				while entity and entity.get_parent() != get_parent():
					entity = entity.get_parent()
				if entity and entity != self:
					GlobalState.active_target = entity

func get_mouse_raycast_hit() -> Dictionary:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 1000.0)
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	return result

func _physics_process(delta: float):
	if GlobalState.paused:
		mining_laser.visible = false
		return
		
	# Animate orbiting drones
	for i in range(drones.size()):
		var pivot = drones[i]
		if is_instance_valid(pivot):
			var rot_speed = drone_rotations[i]
			pivot.rotate_x(rot_speed.x * delta)
			pivot.rotate_y(rot_speed.y * delta)
			pivot.rotate_z(rot_speed.z * delta)
			
	# Update drone colors based on health
	_update_drone_colors()
			
	# Follow player position
	camera_pivot.global_position = global_position
	
	# Autopilot Camera Auto-facing
	var current_target = GlobalState.active_target
	if current_target != last_target:
		if nav_mode != "MANUAL" and current_target != null:
			camera_aligned = false
		last_target = current_target
		
	if nav_mode != last_nav_mode:
		if nav_mode != "MANUAL":
			camera_aligned = false
		last_nav_mode = nav_mode
		
	if nav_mode != "MANUAL" and not camera_aligned:
		# Target camera rotation should follow ship heading (looking from behind)
		var target_rot_y = rotation.y
		var target_rot_x = rotation.x - deg_to_rad(15) # Tilt down slightly
		
		var diff_y = fposmod(target_rot_y - camera_pivot.rotation.y + PI, TAU) - PI
		var diff_x = fposmod(target_rot_x - camera_pivot.rotation.x + PI, TAU) - PI
		
		camera_pivot.rotation.y += diff_y * delta * 4.0
		camera_pivot.rotation.x += diff_x * delta * 4.0
		
		# Check if the ship itself has successfully aligned with the target
		var look_target_pos = Vector3.ZERO
		var has_look_target = false
		
		if target_position != null:
			look_target_pos = target_position
			has_look_target = true
		elif current_target and is_instance_valid(current_target):
			look_target_pos = current_target.global_position
			has_look_target = true
			
		if has_look_target:
			var to_target = look_target_pos - global_position
			if to_target.length() > 1.0:
				var target_dir = to_target.normalized()
				var ship_forward = -global_transform.basis.z
				var angle_to_target = ship_forward.angle_to(target_dir)
				
				# If the ship is facing the target (within ~5 degrees) and the camera is behind the ship
				if angle_to_target < 0.08:
					var cam_diff_y = fposmod(rotation.y - camera_pivot.rotation.y + PI, TAU) - PI
					var cam_diff_x = fposmod(rotation.x - deg_to_rad(15) - camera_pivot.rotation.x + PI, TAU) - PI
					if abs(cam_diff_y) < 0.08 and abs(cam_diff_x) < 0.08:
						camera_aligned = true
			else:
				camera_aligned = true
		else:
			camera_aligned = true
			
	# Check if cargo filled up
	if GlobalState.cargo >= GlobalState.cargo_max:
		mining_laser.visible = false
		if nav_mode == "MINE":
			nav_mode = "MANUAL"
			target_position = null
			
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
		
	# Autopilot updates
	var active_target = GlobalState.active_target
	if active_target and is_instance_valid(active_target) and not active_target.get("destroyed"):
		var dist = global_position.distance_to(active_target.global_position)
		
		# Autopilot modes
		match nav_mode:
			"APPROACH":
				target_position = active_target.global_position
					
			"APPROACH_1K":
				target_position = active_target.global_position
				if dist < 1000.0:
					target_position = null
					nav_mode = "MANUAL"
					
			"MINE":
				if GlobalState.cargo >= GlobalState.cargo_max:
					nav_mode = "MANUAL"
					target_position = null
					mining_laser.visible = false
				else:
					target_position = active_target.global_position
					if dist < 75.0:
						steer_towards(active_target.global_position, delta)
						perform_action(active_target, delta)
					else:
						mining_laser.visible = false
					
			"ATTACK":
				target_position = active_target.global_position
				if dist < 75.0:
					steer_towards(active_target.global_position, delta)
					perform_action(active_target, delta)
					
			"DOCK":
				var dock_dist = 100.0 if active_target.is_in_group("station") else 40.0
				if dist >= dock_dist:
					target_position = active_target.global_position
				else:
					target_position = null
					nav_mode = "MANUAL"
					if active_target.has_method("dock_player"):
						active_target.dock_player()
						
			"ORBIT":
				var to_target = global_position - active_target.global_position
				var orbit_radius = 25.0
				var tangent = Vector3(-to_target.z, 0, to_target.x).normalized()
				var radial = to_target.normalized()
				
				var des_dir: Vector3
				if dist > orbit_radius:
					des_dir = (tangent * 0.7 - radial * 0.3).normalized()
				else:
					des_dir = (tangent * 0.7 + radial * 0.3).normalized()
				
				target_position = global_position + des_dir * 10.0
	else:
		mining_laser.visible = false
		if nav_mode in ["APPROACH", "APPROACH_1K", "ORBIT", "MINE", "ATTACK", "DOCK"]:
			nav_mode = "MANUAL"
			target_position = null

	# Move and steer
	if target_position != null:
		var dest = target_position as Vector3
		
		# Raycast to detect if a large celestial body blocks the path
		var final_steer_target = dest
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(global_position, dest)
		query.exclude = [self.get_rid()]
		var result = space_state.intersect_ray(query)
		
		if result and is_instance_valid(result.collider):
			var collider = result.collider
			# Do not avoid the target we are actively trying to reach
			if collider != active_target:
				if collider.is_in_group("station") or collider.is_in_group("asteroid") or collider.name == "GasGiant" or collider.name == "RockyPlanet":
					var obstacle_pos = collider.global_position
					var ray_vec = dest - global_position
					var ray_dir = ray_vec.normalized()
					
					var to_obstacle = obstacle_pos - global_position
					var proj = to_obstacle.project(ray_dir)
					var perp = to_obstacle - proj
					
					var avoid_dir = Vector3.ZERO
					if perp.length() < 0.5:
						# If perfectly aligned, steer horizontally relative to the ray
						avoid_dir = Vector3(-ray_dir.z, 0, ray_dir.x).normalized()
					else:
						avoid_dir = -perp.normalized()
						
					# Determine radius and safety buffer for detour
					var radius = 50.0
					var safety_margin = 40.0
					
					var shape_owner = collider.find_child("CollisionShape3D", true, false)
					if shape_owner and shape_owner is CollisionShape3D and shape_owner.shape:
						var shape = shape_owner.shape
						var obj_scale = collider.scale.x
						if shape is SphereShape3D:
							radius = shape.radius * obj_scale
						elif shape is BoxShape3D:
							radius = (shape.size.length() * 0.5) * obj_scale
							
					if collider.name == "GasGiant":
						safety_margin = 150.0
					elif collider.name == "RockyPlanet":
						safety_margin = 80.0
					elif collider.is_in_group("station"):
						safety_margin = 35.0
					elif collider.is_in_group("asteroid"):
						safety_margin = 12.0
						
					final_steer_target = obstacle_pos + avoid_dir * (radius + safety_margin)
					
		steer_towards(final_steer_target, delta)
		
		var speed = max_speed * GlobalState.speed_mult
		
		# Proportional speed controller to maintain safe distance from targets
		if active_target and is_instance_valid(active_target):
			var dist = global_position.distance_to(active_target.global_position)
			var speed_limit = max_speed * GlobalState.speed_mult
			
			if nav_mode == "APPROACH":
				var target_stop_dist = 60.0
				if active_target.name == "GasGiant":
					target_stop_dist = 750.0
				elif active_target.name == "RockyPlanet":
					target_stop_dist = 350.0
				elif active_target.is_in_group("station"):
					target_stop_dist = 110.0
				elif active_target.is_in_group("asteroid") or active_target.is_in_group("ship"):
					target_stop_dist = 60.0
				speed = clamp((dist - target_stop_dist) * 4.0, -speed_limit, speed_limit)
			elif nav_mode == "MINE" and active_target.is_in_group("asteroid"):
				# Keep 35m from mined asteroids to prevent crashing
				speed = clamp((dist - 35.0) * 3.0, -speed_limit, speed_limit)
			elif nav_mode == "ATTACK" and active_target.is_in_group("ship"):
				# Keep 45m from attacked hostile NPC ships
				speed = clamp((dist - 45.0) * 3.0, -speed_limit, speed_limit)
			
		var forward_dir = -global_transform.basis.z
		velocity = forward_dir * speed
		move_and_slide()
		
		if global_position.distance_to(dest) < 2.0:
			if nav_mode == "MANUAL":
				target_position = null
	else:
		velocity = Vector3.ZERO
		
	# Check alignment completion
	if is_aligning:
		var look_target_pos = Vector3.ZERO
		var has_look_target = false
		
		if target_position != null:
			look_target_pos = target_position
			has_look_target = true
		elif active_target and is_instance_valid(active_target):
			look_target_pos = active_target.global_position
			has_look_target = true
			
		if has_look_target:
			var to_target = look_target_pos - global_position
			if to_target.length() > 1.0:
				var target_dir = to_target.normalized()
				var ship_forward = -global_transform.basis.z
				var angle_to_target = ship_forward.angle_to(target_dir)
				if angle_to_target < 0.08:
					is_aligning = false
			else:
				is_aligning = false
		else:
			is_aligning = false

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

func perform_action(target_node: Node3D, delta: float):
	if target_node.is_in_group("asteroid"):
		if GlobalState.cargo >= GlobalState.cargo_max:
			mining_laser.visible = false
			return
			
		mining_laser.visible = true
		
		# Position laser beam cylinder
		var ship_front = global_position + (-global_transform.basis.z * 2.0)
		var asteroid_pos = target_node.global_position
		var mid_point = (ship_front + asteroid_pos) / 2.0
		var laser_len = ship_front.distance_to(asteroid_pos)
		
		mining_laser.global_position = mid_point
		mining_laser.look_at(asteroid_pos, Vector3.UP)
		mining_laser.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		
		# Laser Pulse FX
		var pulse = 0.12 + sin(Time.get_ticks_msec() * 0.025) * 0.04
		mining_laser.scale = Vector3(pulse, laser_len / 2.0, pulse)
		
		if fire_cooldown <= 0.0:
			fire_cooldown = 0.5
			AudioManager.play_laser(global_position)
			if target_node.has_method("mine"):
				target_node.mine()
	
	elif target_node.has_method("take_damage") and target_node.get("faction") != "player":
		mining_laser.visible = false
		if fire_cooldown <= 0.0:
			fire_cooldown = 0.75 # Balanced fire rate for mining ship
			AudioManager.play_laser(global_position)
			spawn_projectile(target_node)
	else:
		mining_laser.visible = false

func spawn_projectile(target_node: Node3D):
	var proj_scene = load("res://scenes/projectile.tscn")
	if proj_scene:
		var p = proj_scene.instantiate()
		p.direction = -global_transform.basis.z
		p.damage = GlobalState.damage
		p.faction = "player"
		p.color = Color.CYAN
		get_parent().add_child(p)
		p.global_position = global_position + (-global_transform.basis.z * 2.2)

func double_click_move(click_pos: Vector3):
	is_aligning = false
	target_position = click_pos
	nav_mode = "MANUAL"
	is_aligning = true
	var ui = get_node_or_null("../CanvasLayer/UIManager")
	if ui and ui.has_method("show_target_marker"):
		ui.show_target_marker(click_pos)

func die():
	destroyed = true
	AudioManager.play_explosion(global_position)
	var ui = get_node_or_null("../CanvasLayer/UIManager")
	if ui and ui.has_method("show_death_screen"):
		ui.show_death_screen()
	queue_free()

func _create_drones():
	randomize()
	
	var orbit_radius = 6.8
	var sphere_radius = 0.12 # Basketball size relative to ship scale
	
	# Create common glowing green material for both drones
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.4)
	mat.metallic = 0.9
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.4)
	mat.emission_energy_multiplier = 3.0
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = sphere_radius
	sphere_mesh.height = sphere_radius * 2.0
	sphere_mesh.material = mat
	
	# Create Drone 1
	var pivot1 = Node3D.new()
	pivot1.name = "DronePivot1"
	add_child(pivot1)
	
	var mesh1 = MeshInstance3D.new()
	mesh1.name = "DroneMesh1"
	mesh1.mesh = sphere_mesh
	mesh1.position = Vector3(orbit_radius, 0.0, 0.0)
	pivot1.add_child(mesh1)
	
	var light1 = OmniLight3D.new()
	light1.name = "DroneLight1"
	light1.light_color = Color(0.2, 0.9, 0.4)
	light1.light_energy = 3.5
	light1.omni_range = 8.0
	mesh1.add_child(light1)
	
	drones.append(pivot1)
	drone_rotations.append(Vector3(randf_range(0.4, 0.9), randf_range(0.9, 1.6), randf_range(0.1, 0.6)))
	
	# Create Drone 2
	var pivot2 = Node3D.new()
	pivot2.name = "DronePivot2"
	add_child(pivot2)
	pivot2.rotation_degrees = Vector3(50, 0, 50) # Tilted initial plane
	
	var mesh2 = MeshInstance3D.new()
	mesh2.name = "DroneMesh2"
	mesh2.mesh = sphere_mesh
	mesh2.position = Vector3(-orbit_radius, 0.0, 0.0)
	pivot2.add_child(mesh2)
	
	var light2 = OmniLight3D.new()
	light2.name = "DroneLight2"
	light2.light_color = Color(0.2, 0.9, 0.4)
	light2.light_energy = 3.5
	light2.omni_range = 8.0
	mesh2.add_child(light2)
	
	drones.append(pivot2)
	drone_rotations.append(Vector3(randf_range(-0.9, -0.4), randf_range(0.9, 1.6), randf_range(-0.6, -0.1)))

func take_damage(amount: float, attacker_faction: String = ""):
	if is_docked: return
	if health <= 0.0: return
	health -= amount
	if health <= 0.0:
		die()

func _update_drone_colors():
	var health_pct = health / max_health
	var target_color = Color(0.2, 0.9, 0.4) # Green
	if health_pct <= 0.3:
		target_color = Color(1.0, 0.2, 0.2) # Red
	elif health_pct <= 0.6:
		target_color = Color(0.9, 0.8, 0.2) # Yellow
		
	# Update both drones
	for pivot in drones:
		if is_instance_valid(pivot) and pivot.get_child_count() > 0:
			var mesh_inst = pivot.get_child(0) as MeshInstance3D
			if is_instance_valid(mesh_inst):
				var mat = mesh_inst.mesh.material as StandardMaterial3D
				if mat:
					mat.albedo_color = target_color
					mat.emission = target_color
				
				if mesh_inst.get_child_count() > 0:
					var light = mesh_inst.get_child(0) as OmniLight3D
					if is_instance_valid(light):
						light.light_color = target_color
