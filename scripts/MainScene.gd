extends Node3D

@onready var ui_manager: Control = $CanvasLayer/UIManager
@onready var gas_giant: Node3D = $GasGiant
@onready var rocky_planet: Node3D = $RockyPlanet
@onready var station: StaticBody3D = $Station

var asteroid_scene = preload("res://scenes/asteroid.tscn")
var npc_ship_scene = preload("res://scenes/npc_ship.tscn")

func _ready():
	# Seed random number generator
	randomize()
	
	# Spawn Asteroid rings around Gas Giant (radius 600, ring at 850, width 150)
	_spawn_asteroid_ring(gas_giant.global_position, 850.0, 150.0, 75, "GasGiantBelt")
	
	# Spawn Asteroid rings around Rocky Planet (radius 250, ring at 370, width 80)
	_spawn_asteroid_ring(rocky_planet.global_position, 370.0, 80.0, 45, "RockyBelt")
	
	# Spawn NPC Ships
	_spawn_npc("zenith", Vector3(120, 0, 180), 12.0)
	_spawn_npc("zenith", Vector3(-120, 0, 190), 12.0)
	
	# Close hostiles for easy testing near start area
	_spawn_npc("aurelia", Vector3(90, 0, 80), 14.0)
	_spawn_npc("vanguard", Vector3(-90, 0, 80), 15.0)
	
	# Hostiles around Rocky Planet
	_spawn_npc("aurelia", rocky_planet.global_position + Vector3(40, 0, 40), 14.0)
	_spawn_npc("aurelia", rocky_planet.global_position + Vector3(-50, 0, -40), 14.0)
	_spawn_npc("aurelia", rocky_planet.global_position + Vector3(0, 0, -80), 14.0)
	
	# Hostiles around Gas Giant
	_spawn_npc("vanguard", gas_giant.global_position + Vector3(50, 0, 50), 15.0)
	_spawn_npc("vanguard", gas_giant.global_position + Vector3(-60, 0, -60), 15.0)
	_spawn_npc("vanguard", gas_giant.global_position + Vector3(80, 0, 0), 15.0)

	
	# Populating Overview list
	_populate_overview()

func _spawn_asteroid_ring(center: Vector3, radius: float, width: float, count: int, prefix: String):
	for i in range(count):
		var angle = randf() * TAU
		var offset_r = randf_range(-width / 2.0, width / 2.0)
		var r = radius + offset_r
		
		# Ring coordinates on horizontal XZ plane
		var x = center.x + cos(angle) * r
		var y = center.y + randf_range(-4.0, 4.0) # Slight vertical dispersion
		var z = center.z + sin(angle) * r
		
		var ast = asteroid_scene.instantiate()
		ast.name = prefix + "_Asteroid_" + str(i)
		
		# Setup orbiting variables on the asteroid
		ast.orbit_center = center
		ast.orbit_radius = r
		ast.orbit_speed = randf_range(0.005, 0.015) # Slow, majestic orbital speed
		ast.current_angle = angle
		ast.orbit_y = y
		ast.is_orbiting = true
		
		add_child(ast)
		ast.global_position = Vector3(x, y, z)

func _spawn_npc(faction_name: String, pos: Vector3, npc_speed: float):
	var npc = npc_ship_scene.instantiate()
	npc.faction = faction_name
	npc.speed = npc_speed
	npc.name = faction_name.to_upper() + "_Patrol_" + str(randi() % 1000)
	add_child(npc)
	npc.global_position = pos

func _populate_overview():
	if ui_manager and ui_manager.has_method("refresh_overview"):
		ui_manager.refresh_overview()
