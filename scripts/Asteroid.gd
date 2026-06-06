extends StaticBody3D

@export var max_resources: float = 300.0
var resources: float = 300.0
var destroyed: bool = false

# Orbiting variables
var orbit_center: Vector3 = Vector3.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.0
var current_angle: float = 0.0
var orbit_y: float = 0.0
var is_orbiting: bool = false

func _ready():
	add_to_group("asteroid")
	resources = max_resources
	# Add slight random scale variation to asteroid
	var r_scale = randf_range(0.85, 1.4)
	scale = Vector3(r_scale, r_scale, r_scale)

func _physics_process(delta: float):
	if is_orbiting and not destroyed and not GlobalState.paused:
		current_angle += orbit_speed * delta
		var x = orbit_center.x + cos(current_angle) * orbit_radius
		var z = orbit_center.z + sin(current_angle) * orbit_radius
		global_position = Vector3(x, orbit_y, z)

func mine():
	if destroyed: return
	
	# Calculate how much space is left in player's cargo
	var space_left = GlobalState.cargo_max - GlobalState.cargo
	if space_left <= 0.0:
		return
		
	# Mined amount is the minimum of:
	# 1. Player's mining yield
	# 2. Remaining asteroid resources
	# 3. Space left in cargo (Top-off logic!)
	var amount_to_mine = min(GlobalState.mining_yield, resources)
	amount_to_mine = min(amount_to_mine, space_left)
	
	if amount_to_mine > 0.0:
		GlobalState.cargo += amount_to_mine
		resources -= amount_to_mine
		
		# Visual/text popups could be spawned here
		
		if resources <= 0.0:
			deplete()

func deplete():
	destroyed = true
	AudioManager.play_explosion()
	# Remove from entities list if it was targeted
	if GlobalState.active_target == self:
		GlobalState.active_target = null
	queue_free()
