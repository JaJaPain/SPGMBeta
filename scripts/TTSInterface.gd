extends Node

const TTS_URL = "http://localhost:5000/tts"
var http_request: HTTPRequest
var audio_player: AudioStreamPlayer
var is_requesting: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "SFX"
	add_child(audio_player)

func play_dialogue_audio(text: String):
	if is_requesting:
		http_request.cancel_request()
		is_requesting = false
		
	if audio_player.playing:
		audio_player.stop()
		
	text = text.strip_edges()
	# Clean up meta headers, details, options or empty spaces to avoid reading formatting
	var clean_text = _clean_dialogue_text(text)
	if clean_text == "":
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
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[TTSInterface] Kokoro TTS request failed. Response code: ", response_code)
		return
		
	var stream = load_wav_from_buffer(body)
	if stream:
		audio_player.stream = stream
		audio_player.play()
		print("[TTSInterface] Playing speech audio stream.")
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
