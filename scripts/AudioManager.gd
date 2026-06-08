extends Node

var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_channels: int = 8

var music_volume_percent: float = 0.5
var sfx_volume_percent: float = 1.0
var is_ducked: bool = false

# Audio Streams
var bgm_track1 = preload("res://sound/BackgroundMusic/Iron Lullaby1.mp3")
var bgm_track2 = preload("res://sound/BackgroundMusic/Iron Lullaby2.mp3")
var sfx_laser1 = preload("res://sound/WeaponFire/Laser Weapon Firing1.mp3")
var sfx_laser2 = preload("res://sound/WeaponFire/Laser Weapon Firing2.mp3")
var sfx_explosion1 = preload("res://sound/SpaceShipExplosion/Spaceship Explosion1.mp3")
var sfx_explosion2 = preload("res://sound/SpaceShipExplosion/Spaceship Explosion2.mp3")
var sfx_cargo_full = preload("res://assets/Cargo Full.mp3")
var sfx_repair: AudioStream = null
var sfx_sell_ore: AudioStream = null
var sfx_align: AudioStream = null

var tracks: Array = []
var current_track_idx: int = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Ensure Music and SFX buses exist in AudioServer
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx == -1:
		AudioServer.add_bus()
		music_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(music_bus_idx, "Music")
		
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx == -1:
		AudioServer.add_bus()
		sfx_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(sfx_bus_idx, "SFX")
	
	# Setup BGM Player
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Music"
	add_child(bgm_player)
	bgm_player.finished.connect(_on_bgm_finished)
	
	tracks = [bgm_track1, bgm_track2]
	
	# Setup SFX Players pool
	for i in range(max_sfx_channels):
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)
		
	# Set default music volume to 50%
	set_music_volume(0.5)
	
	# Start playing music
	play_next_bgm()

func play_next_bgm():
	if tracks.size() == 0: return
	bgm_player.stream = tracks[current_track_idx]
	bgm_player.play()
	current_track_idx = (current_track_idx + 1) % tracks.size()

func _on_bgm_finished():
	play_next_bgm()

func play_sfx(stream: AudioStream, volume_db: float = 0.0):
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	# If all busy, steal the first channel
	var p = sfx_players[0]
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func play_sfx_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0):
	var p = AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = "SFX"
	
	# Configure 3D attenuation settings
	p.unit_size = 15.0 # Distance where the sound begins to fade
	p.max_db = 3.0
	p.max_distance = 350.0 # Beyond this, completely silent
	
	var main = get_tree().current_scene
	if main:
		main.add_child(p)
		p.global_position = position
		p.play()
		p.finished.connect(p.queue_free)

func play_laser(pos: Variant = null):
	var laser = sfx_laser1 if randf() > 0.5 else sfx_laser2
	if pos is Vector3:
		play_sfx_3d(laser, pos, -6.0)
	else:
		play_sfx(laser, -6.0)

func play_explosion(pos: Variant = null):
	var expl = sfx_explosion1 if randf() > 0.5 else sfx_explosion2
	if pos is Vector3:
		play_sfx_3d(expl, pos, -3.0)
	else:
		play_sfx(expl, -3.0)

func play_cargo_full():
	play_sfx(sfx_cargo_full, 0.0)

func set_music_volume(value: float):
	music_volume_percent = value
	_update_bus_volumes()

func get_music_volume() -> float:
	return music_volume_percent

func set_sfx_volume(value: float):
	sfx_volume_percent = value
	_update_bus_volumes()

func get_sfx_volume() -> float:
	return sfx_volume_percent

func _update_bus_volumes():
	var music_idx = AudioServer.get_bus_index("Music")
	if music_idx != -1:
		var target_db = linear_to_db(music_volume_percent)
		if is_ducked:
			target_db -= 18.0 # Duck music by 18dB
		AudioServer.set_bus_volume_db(music_idx, target_db)
		AudioServer.set_bus_mute(music_idx, music_volume_percent <= 0.0001)
		
	var sfx_idx = AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		var target_db = linear_to_db(sfx_volume_percent)
		if is_ducked:
			target_db -= 12.0 # Duck game sound by 12dB
		AudioServer.set_bus_volume_db(sfx_idx, target_db)
		AudioServer.set_bus_mute(sfx_idx, sfx_volume_percent <= 0.0001)

func duck_audio():
	if not is_ducked:
		is_ducked = true
		_update_bus_volumes()
		print("[TRACE] [AudioManager] Audio ducked (Music -18dB, SFX -12dB)")

func unduck_audio():
	if is_ducked:
		is_ducked = false
		_update_bus_volumes()
		print("[TRACE] [AudioManager] Audio unducked")

func play_align():
	if sfx_align == null:
		sfx_align = load("res://sound/ShipSounds/ShipAlignSound.mp3")
	if sfx_align:
		play_sfx(sfx_align, -4.0)

func play_repair():
	if sfx_repair == null:
		sfx_repair = load("res://sound/spaceStationSoundFX/RepairShip.wav")
	if sfx_repair:
		play_sfx(sfx_repair, 0.0)

func play_sell_ore():
	if sfx_sell_ore == null:
		sfx_sell_ore = load("res://sound/spaceStationSoundFX/sellOre.mp3")
	if sfx_sell_ore:
		play_sfx(sfx_sell_ore, -2.0)
