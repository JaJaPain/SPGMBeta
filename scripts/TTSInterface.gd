extends Node

const TTS_URL = "http://localhost:5000/tts"
var http_request: HTTPRequest
var audio_player: AudioStreamPlayer
var is_requesting: bool = false
var tts_request_time: float = 0.0

var last_interaction_time: float = 0.0
var last_interaction_name: String = ""

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
	
	_check_and_start_tts_server()

func play_dialogue_audio(text: String):
	tts_request_time = Time.get_ticks_msec()
	var elapsed_str = ""
	if last_interaction_time > 0.0:
		elapsed_str = " (Elapsed since '%s': %.3fs)" % [last_interaction_name, (tts_request_time - last_interaction_time) / 1000.0]
	print("[TRACE] [TTSInterface] play_dialogue_audio called at: %d ms%s" % [tts_request_time, elapsed_str])

	
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

func _check_and_start_tts_server():
	var check_http = HTTPRequest.new()
	add_child(check_http)
	check_http.timeout = 1.0 # 1 second timeout
	check_http.request_completed.connect(func(result, response_code, headers, body):
		check_http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[TTSInterface] Local TTS server not detected on port 5000. Launching it...")
			_launch_tts_server_process()
		else:
			print("[TTSInterface] Local TTS server is already running on port 5000.")
	)
	
	# Send a check request to the TTS server
	var err = check_http.request(TTS_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}")
	if err != OK:
		check_http.queue_free()
		_launch_tts_server_process()

func _launch_tts_server_process():
	var global_script_path = ProjectSettings.globalize_path("res://scripts/tts_server.py")
	print("[TTSInterface] Sourced TTS server script path: ", global_script_path)
	
	var pid = OS.create_process("python", [global_script_path])
	if pid > 0:
		print("[TTSInterface] Successfully launched local TTS server background process (PID: ", pid, ")")
	else:
		print("[TTSInterface] Failed to launch local TTS server. Please ensure Python is installed and in PATH.")
