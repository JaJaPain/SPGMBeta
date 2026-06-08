extends Node

const TTS_URL = "http://127.0.0.1:5000/tts"
var http_request: HTTPRequest
var audio_player: AudioStreamPlayer
var is_requesting: bool = false
var tts_request_time: float = 0.0

var last_interaction_time: float = 0.0
var last_interaction_name: String = ""
var tts_audio_cache: Dictionary = {}

signal cache_queue_completed()
var active_cache_requests: int = 0

signal tts_connection_attempt(attempt: int)
signal tts_connection_established()

var tts_connected: bool = false
var tts_connection_attempts: int = 0
var cache_queue: Array[String] = []

func start_interaction(interaction_name: String):
	last_interaction_time = Time.get_ticks_msec()
	last_interaction_name = interaction_name
	print("[TRACE] [TTSInterface] start_interaction: '", interaction_name, "' at system time: ", last_interaction_time, " ms")


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = 10.0
	http_request.request_completed.connect(_on_request_completed)
	
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "SFX"
	add_child(audio_player)
	
	_discover_and_verify_tts()
	
	# Pre-cache static completion and abandon messages
	cache_dialogue_audio("Pleasure doing business with you, pilot. Payout transferred and brokerage fee deducted. Check back soon.")
	cache_dialogue_audio("Contract dumped? You're costing me credit margins. I don't forget when people waste my time.")

func play_dialogue_audio(text: String):
	tts_request_time = Time.get_ticks_msec()
	
	if is_requesting:
		http_request.cancel_request()
		is_requesting = false
		
	if audio_player.playing:
		audio_player.stop()
		
	text = text.strip_edges()
	# Clean up meta headers, details, options or empty spaces to avoid reading formatting
	var clean_text = _clean_dialogue_text(text)
	if clean_text == "":
		print("[TRACE] [TTSInterface] Cleaned text is empty, skipping speech.")
		return
		
	var elapsed_str = ""
	if last_interaction_time > 0.0:
		elapsed_str = " (Elapsed since '%s': %.3fs)" % [last_interaction_name, (tts_request_time - last_interaction_time) / 1000.0]
		
	# Check cache first!
	if tts_audio_cache.has(clean_text):
		var stream = tts_audio_cache[clean_text]
		audio_player.stream = stream
		audio_player.play()
		var play_now = Time.get_ticks_msec()
		var total_elapsed_str = ""
		if last_interaction_time > 0.0:
			total_elapsed_str = " (Total since '%s': %.3fs)" % [last_interaction_name, (play_now - last_interaction_time) / 1000.0]
		print("[TRACE] [TTSInterface] play_dialogue_audio CACHE HIT at: %d ms%s. Playing immediately!%s" % [tts_request_time, elapsed_str, total_elapsed_str])
		return
		
	print("[TRACE] [TTSInterface] play_dialogue_audio CACHE MISS at: %d ms%s" % [tts_request_time, elapsed_str])
	
	is_requesting = true
	var payload = {
		"text": clean_text,
		"voice": "af_bella",
		"speed": 1.0
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	# Print statement to help debugging in console
	print("[TTSInterface] Requesting speech for: ", clean_text)
	var err = http_request.request(TTS_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[TTSInterface] Failed to initiate HTTP request. Error code: ", err)
		is_requesting = false

func cache_dialogue_audio(text: String):
	text = text.strip_edges()
	var clean_text = _clean_dialogue_text(text)
	if clean_text == "" or tts_audio_cache.has(clean_text):
		return
		
	if not tts_connected:
		if not cache_queue.has(clean_text):
			cache_queue.append(clean_text)
			print("[TRACE] [TTSInterface] Queueing cache request (TTS not connected): ", clean_text.hash())
		return
		
	# Create a dynamic HTTPRequest node for caching
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 15.0
	
	var payload = {
		"text": clean_text,
		"voice": "af_bella",
		"speed": 1.0
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	active_cache_requests += 1
	print("[TRACE] [TTSInterface] Background caching started for text hash: ", clean_text.hash(), " (len: ", clean_text.length(), "), active: ", active_cache_requests)
	
	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var stream = load_wav_from_buffer(body)
			if stream:
				tts_audio_cache[clean_text] = stream
				print("[TRACE] [TTSInterface] Background caching completed for text hash: ", clean_text.hash())
			else:
				print("[TTSInterface] Background cache parsing failed for text hash: ", clean_text.hash())
		else:
			print("[TTSInterface] Background cache request failed. Code: ", response_code)
			
		active_cache_requests -= 1
		print("[TRACE] [TTSInterface] Active cache requests left: ", active_cache_requests)
		if active_cache_requests <= 0:
			active_cache_requests = 0
			cache_queue_completed.emit()
	)
	
	var err = temp_http.request(TTS_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		active_cache_requests -= 1
		if active_cache_requests <= 0:
			active_cache_requests = 0
			cache_queue_completed.emit()

func _clean_dialogue_text(text: String) -> String:
	# Strip off the "--- Contract Details ---" block or other metadata to only speak narrative
	var details_idx = text.find("--- Contract Details ---")
	if details_idx != -1:
		text = text.substr(0, details_idx).strip_edges()
	
	# Strip off offline backup notes
	text = text.replace(" [Offline Backup]", "")
	return text.strip_edges()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	is_requesting = false
	var now = Time.get_ticks_msec()
	var elapsed = (now - tts_request_time) / 1000.0
	var elapsed_str = ""
	if last_interaction_time > 0.0:
		elapsed_str = " (Total since '%s': %.3fs)" % [last_interaction_name, (now - last_interaction_time) / 1000.0]
	print("[TRACE] [TTSInterface] HTTP response received. Time elapsed since request: %.3fs%s. Result: %d Response code: %d" % [elapsed, elapsed_str, result, response_code])
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[TTSInterface] Kokoro TTS request failed. Response code: ", response_code)
		return
		
	var start_decode = Time.get_ticks_msec()
	var stream = load_wav_from_buffer(body)
	var decode_elapsed = Time.get_ticks_msec() - start_decode
	print("[TRACE] [TTSInterface] WAV decoding completed in: ", decode_elapsed, "ms.")
	
	if stream:
		audio_player.stream = stream
		audio_player.play()
		var play_now = Time.get_ticks_msec()
		var total_elapsed_str = ""
		if last_interaction_time > 0.0:
			total_elapsed_str = " (Total since '%s': %.3fs)" % [last_interaction_name, (play_now - last_interaction_time) / 1000.0]
		print("[TRACE] [TTSInterface] Playing speech audio stream. Total time since play_dialogue_audio called: %.3fs%s" % [(play_now - tts_request_time) / 1000.0, total_elapsed_str])
	else:
		print("[TTSInterface] Failed to parse WAV buffer from TTS response.")

func load_wav_from_buffer(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		print("[TTSInterface] Byte array too small to parse as WAV.")
		return null
		
	var riff_header = bytes.slice(0, 4).get_string_from_ascii()
	var wave_header = bytes.slice(8, 12).get_string_from_ascii()
	if riff_header != "RIFF" or wave_header != "WAVE":
		print("[TTSInterface] Invalid WAV header, expected RIFF and WAVE.")
		return null
		
	var stream = AudioStreamWAV.new()
	stream.mix_rate = 24000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	
	var idx = 12
	var found_data = false
	var data_offset = 44
	var data_length = bytes.size() - 44
	
	while idx < bytes.size() - 8:
		var chunk_name = bytes.slice(idx, idx + 4).get_string_from_ascii()
		var chunk_size = bytes.decode_u32(idx + 4)
		if chunk_name == "fmt ":
			if idx + 20 <= bytes.size():
				var channels = bytes.decode_u16(idx + 10)
				var sample_rate = bytes.decode_u32(idx + 12)
				var bits_per_sample = bytes.decode_u16(idx + 20)
				stream.mix_rate = sample_rate
				stream.stereo = (channels == 2)
				if bits_per_sample == 8:
					stream.format = AudioStreamWAV.FORMAT_8_BITS
				elif bits_per_sample == 16:
					stream.format = AudioStreamWAV.FORMAT_16_BITS
		elif chunk_name == "data":
			data_offset = idx + 8
			data_length = chunk_size
			found_data = true
			break
		idx += 8 + chunk_size
		
	if found_data:
		stream.data = bytes.slice(data_offset, data_offset + data_length)
	else:
		stream.data = bytes.slice(44)
		
	return stream

func _discover_and_verify_tts():
	tts_connection_attempts += 1
	tts_connection_attempt.emit(tts_connection_attempts)
	print("[TRACE] [TTSInterface] Verifying TTS server connection (attempt %d)..." % tts_connection_attempts)
	
	var check_http = HTTPRequest.new()
	add_child(check_http)
	check_http.timeout = 2.0
	check_http.request_completed.connect(func(result, response_code, headers, body):
		check_http.queue_free()
		var success = false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data is Dictionary and data.get("status") == "ok" and data.get("pipeline_ready") == true:
					success = true
					
		if success:
			print("[TRACE] [TTSInterface] TTS server successfully verified and pipeline is ready.")
			tts_connected = true
			tts_connection_established.emit()
			
			# Process queued cache requests
			var queue_copy = cache_queue.duplicate()
			cache_queue.clear()
			for text in queue_copy:
				cache_dialogue_audio(text)
		else:
			# If first attempt failed, start the server process
			if tts_connection_attempts == 1:
				print("[TTSInterface] Local TTS server not detected or not ready. Launching it...")
				_launch_tts_server_process()
				
			# Retry after 1.5 seconds
			get_tree().create_timer(1.5).timeout.connect(_discover_and_verify_tts)
	)
	
	var err = check_http.request("http://127.0.0.1:5000/health")
	if err != OK:
		check_http.queue_free()
		print("[TTSInterface] Failed to check health endpoint. Retrying in 1.5s...")
		if tts_connection_attempts == 1:
			_launch_tts_server_process()
		get_tree().create_timer(1.5).timeout.connect(_discover_and_verify_tts)

func _launch_tts_server_process():
	var global_script_path = ProjectSettings.globalize_path("res://scripts/tts_server.py")
	print("[TTSInterface] Sourced TTS server script path: ", global_script_path)
	
	var pid = OS.create_process("python", [global_script_path])
	if pid > 0:
		print("[TTSInterface] Successfully launched local TTS server background process (PID: ", pid, ")")
	else:
		print("[TTSInterface] Failed to launch local TTS server. Please ensure Python is installed and in PATH.")
