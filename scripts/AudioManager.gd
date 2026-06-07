extends Node

var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_channels: int = 8

# Audio Streams
var bgm_track1 = preload("res://sound/BackgroundMusic/Iron Lullaby1.mp3")
var bgm_track2 = preload("res://sound/BackgroundMusic/Iron Lullaby2.mp3")
var sfx_laser1 = preload("res://sound/WeaponFire/Laser Weapon Firing1.mp3")
var sfx_laser2 = preload("res://sound/WeaponFire/Laser Weapon Firing2.mp3")
var sfx_explosion1 = preload("res://sound/SpaceShipExplosion/Spaceship Explosion1.mp3")
var sfx_explosion2 = preload("res://sound/SpaceShipExplosion/Spaceship Explosion2.mp3")
var sfx_cargo_full = preload("res://assets/Cargo Full.mp3")
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

func play_laser():
	# Alternate randomly between the two laser sounds
	var laser = sfx_laser1 if randf() > 0.5 else sfx_laser2
	play_sfx(laser, -6.0)

func play_explosion():
	var expl = sfx_explosion1 if randf() > 0.5 else sfx_explosion2
	play_sfx(expl, -3.0)

func play_cargo_full():
	play_sfx(sfx_cargo_full, 0.0)

func set_music_volume(value: float):
	var idx = AudioServer.get_bus_index("Music")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(value))
		AudioServer.set_bus_mute(idx, value <= 0.0001)

func get_music_volume() -> float:
	var idx = AudioServer.get_bus_index("Music")
	if idx != -1:
		if AudioServer.is_bus_mute(idx):
			return 0.0
		return db_to_linear(AudioServer.get_bus_volume_db(idx))
	return 1.0

func set_sfx_volume(value: float):
	var idx = AudioServer.get_bus_index("SFX")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(value))
		AudioServer.set_bus_mute(idx, value <= 0.0001)

func get_sfx_volume() -> float:
	var idx = AudioServer.get_bus_index("SFX")
	if idx != -1:
		if AudioServer.is_bus_mute(idx):
			return 0.0
		return db_to_linear(AudioServer.get_bus_volume_db(idx))
	return 1.0

func play_align():
	if sfx_align == null:
		sfx_align = load("res://sound/ShipSounds/ShipAlignSound.mp3")
	if sfx_align:
		play_sfx(sfx_align, -4.0)
