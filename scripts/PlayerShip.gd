extends CharacterBody3D

@export var max_speed: float = 25.0
@export var rotation_speed: float = 3.5

# Navigation variables
var target_position: Variant = null # null or Vector3
var nav_mode: String = "MANUAL"     # MANUAL, APPROACH, APPROACH_1K, ORBIT, MINE, ATTACK, DOCK
var fire_cooldown: float = 0.0

# Camera controls
var camera_aligned: bool = true
var last_nav_mode: String = "MANUAL"
var rmb_down_time: float = 0.0

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

func _on_target_changed(new_target: Node3D):
	if new_target == null:
		mining_laser.visible = false
		if nav_mode in ["APPROACH", "APPROACH_1K", "ORBIT", "MINE", "ATTACK", "DOCK"]:
			nav_mode = "MANUAL"
			target_position = null

func _input(event: InputEvent):
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
		
	# Follow player position
	camera_pivot.global_position = global_position
	
	# Autopilot Camera Auto-facing
	if nav_mode != last_nav_mode:
		if nav_mode != "MANUAL":
			camera_aligned = false
		last_nav_mode = nav_mode
		
	if nav_mode != "MANUAL" and target_position != null and not camera_aligned:
		# Target camera rotation should follow ship heading
		var target_rot_y = rotation.y # Look from behind
		var target_rot_x = rotation.x - deg_to_rad(15) # Tilt down slightly
		
		var diff_y = fposmod(target_rot_y - camera_pivot.rotation.y + PI, TAU) - PI
		var diff_x = fposmod(target_rot_x - camera_pivot.rotation.x + PI, TAU) - PI
		
		if abs(diff_y) < 0.02 and abs(diff_x) < 0.02:
			camera_aligned = true
		else:
			camera_pivot.rotation.y += diff_y * delta * 4.0
			camera_pivot.rotation.x += diff_x * delta * 4.0
			
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
				if dist < 12.0:
					target_position = null
					nav_mode = "MANUAL"
					
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
				elif dist >= 75.0:
					target_position = active_target.global_position
					mining_laser.visible = false
				else:
					target_position = null
					steer_towards(active_target.global_position, delta)
					perform_action(active_target, delta)
					
			"ATTACK":
				if dist >= 75.0:
					target_position = active_target.global_position
				else:
					target_position = null
					steer_towards(active_target.global_position, delta)
					perform_action(active_target, delta)
					
			"DOCK":
				if dist >= 40.0:
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
		steer_towards(dest, delta)
		
		var speed = max_speed * GlobalState.speed_mult
		var forward_dir = -global_transform.basis.z
		velocity = forward_dir * speed
		move_and_slide()
		
		if global_position.distance_to(dest) < 2.0:
			if nav_mode == "MANUAL":
				target_position = null
	else:
		velocity = Vector3.ZERO

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
			AudioManager.play_laser()
			if target_node.has_method("mine"):
				target_node.mine()
	
	elif target_node.has_method("take_damage") and target_node.get("faction") != "player":
		mining_laser.visible = false
		if fire_cooldown <= 0.0:
			fire_cooldown = 0.22
			AudioManager.play_laser()
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
	target_position = click_pos
	nav_mode = "MANUAL"

func die():
	AudioManager.play_explosion()
	var ui = get_node_or_null("../CanvasLayer/UIManager")
	if ui and ui.has_method("show_death_screen"):
		ui.show_death_screen()
	queue_free()
