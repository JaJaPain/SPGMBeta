extends Node

const OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
const MODEL_NAME = "qwen2.5:1.5b-instruct-q4_K_M"
const TIMEOUT_SECONDS = 15.0

var http_request: HTTPRequest
var active_callback: Callable
var is_waiting: bool = false
var request_start_time: float = 0.0
var last_history_text: String = ""
var active_model_name: String = MODEL_NAME

signal model_discovered(model_name: String)
signal llm_connection_attempt(attempt: int)
signal llm_connection_established(model_name: String)

var llm_connected: bool = false
var connection_attempts: int = 0

# Politically neutral, profit-driven fallback templates
var fallback_templates = [
	{
		"title": "Silicate Brokerage",
		"faction": "zenith",
		"agent_name": "Broker Kaelen",
		"dialogue": "Alright, Shiny. Zenith needs a shipment of silicate ore to rebuild their station shields. They're paying standard rates, but I negotiated a 15% brokerage cut for us. Bring me 30 m³ of ore, and we split the profit. Go fetch it.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 30.0,
			"reward_credits": 150
		},
		"choices": [
			{
				"text": "Sounds like easy money. I'll get to mining.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": 3},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Excellent, Shiny. Make it quick; time is credits."
				}
			},
			{
				"text": "Fuel isn't free, Kaelen. I need a 40 credits advance.",
				"consequence": {
					"credits_immediate": 40,
					"reputation_change": {"zenith": -2},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Taking a bite out of my margins, Shiny? Fine, credits wired. But I have to route you through a more contested lane to cover my costs. Watch out for Aurelia patrols."
				}
			},
			{
				"text": "150 is garbage. Double the payout or mine it yourself.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -5},
					"combat_multiplier": 1.7,
					"reward_credits_multiplier": 1.6,
					"dialogue_response": "Hustling a hustler? I respect the gall, Shiny. Payout is bumped, but expect Aurelia interceptors on your tail. Good luck."
				}
			}
		]
	},
	{
		"title": "Thinning the Patrols",
		"faction": "aurelia",
		"agent_name": "Broker Kaelen",
		"dialogue": "Listen up, Shiny. An Aurelia smuggler contact wants Zenith's patrol ships thinned out to ease their transport runs. They're paying top credits. Go blow up 3 Zenith ships. I don't care about their war, I just care about my finder's fee. What do you say?",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "zenith",
			"count_required": 3,
			"reward_credits": 200
		},
		"choices": [
			{
				"text": "A job's a job. I'll clear them.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -4, "aurelia": 4},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Splendid, Shiny. Keep it clean and don't mention my name."
				}
			},
			{
				"text": "I'll need 50 credits up front for ammunition.",
				"consequence": {
					"credits_immediate": 50,
					"reputation_change": {"zenith": -5, "aurelia": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Fine, here's your advance, Shiny. But don't mess this up; my smuggling client doesn't like loose ends. Expect tougher Zenith escorts."
				}
			},
			{
				"text": "Zenith will put a price on my head. Payout is too low.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -8, "aurelia": 2},
					"combat_multiplier": 1.6,
					"reward_credits_multiplier": 1.5,
					"dialogue_response": "Fair point, Shiny. Payout is increased, but Zenith patrol command will send interceptors directly after you once you open fire. Watch your back."
				}
			}
		]
	},
	{
		"title": "Aurelia Ore Run",
		"faction": "aurelia",
		"agent_name": "Broker Kaelen",
		"dialogue": "Aurelia scrap merchants need refined silicate for their hull repairs, Shiny. They pay well, and they don't ask questions. Deliver 20 m³ of ore to my dock. I'll handle the laundering, we both get rich. Simple.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 20.0,
			"reward_credits": 120
		},
		"choices": [
			{
				"text": "No questions asked. I'll go mine it.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"aurelia": 3},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Excellent, Shiny. Keep your scanners peeled while mining."
				}
			},
			{
				"text": "I want 30 credits advance to cover dock fees.",
				"consequence": {
					"credits_immediate": 30,
					"reputation_change": {"aurelia": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Greedy, aren't we, Shiny? Done. But Vanguard patrols are sweeping the belts today. Keep your lasers cold."
				}
			},
			{
				"text": "Smuggling is risky. Payout needs a boost.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"aurelia": -3},
					"combat_multiplier": 1.6,
					"reward_credits_multiplier": 1.5,
					"dialogue_response": "Smuggling tax, right, Shiny? Payout is up. But Vanguard security forces will be actively scanning cargo holds in the area. Stay alert."
				}
			}
		]
	},
	{
		"title": "Clearing the Lanes",
		"faction": "vanguard",
		"agent_name": "Broker Kaelen",
		"dialogue": "A Vanguard shipping corp is losing cargo to Aurelia raiders in the belt, Shiny. They've offered a bounty to clear the lane. Eliminate 4 Aurelia ships. They get their trade route back, I get my broker commission, you get paid. Win-win-win.",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "aurelia",
			"count_required": 4,
			"reward_credits": 220
		},
		"choices": [
			{
				"text": "I'll clear the raiders.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": 4, "aurelia": -4},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Good, Shiny. Make sure the lanes are clear."
				}
			},
			{
				"text": "I need 60 credits advance to tune my lasers.",
				"consequence": {
					"credits_immediate": 60,
					"reputation_change": {"vanguard": -2, "aurelia": -5},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Expensive tastes, Shiny. Credits transferred. But the raiders will be hunting in packs now. Be prepared."
				}
			},
			{
				"text": "Vanguard dirty work is premium work. Make it worth it.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": -4, "aurelia": -8},
					"combat_multiplier": 1.7,
					"reward_credits_multiplier": 1.6,
					"dialogue_response": "Bold play, Shiny. I'll adjust the contract, but you're going to face Aurelia heavy sentinels out there. Don't get blown to scrap."
				}
			}
		]
	}
]

# Random complications to vary prompts
var complications = [
	"A rival broker wants this cargo intercepted to sabotage my client's logistics.",
	"Zenith intelligence believes a double-agent has leaked shipping logs in the area.",
	"Aurelia pirates have set up a localized gravity snare. Expect heavier escorts.",
	"A logistics emergency has pushed resource demands to critical levels."
]

# Radio chatter pre-fetch cache
var chatter_cache = {
	"hostile_taunt": [],
	"death_cry": [],
	"system_alert": [],
	"industrial_banter": []
}

var generic_banter = {
	"hostile_taunt": [
		"Your shields won't save you, pilot!",
		"Hand over your cargo or prepare to be space dust!",
		"You picked the wrong sector to fly through!",
		"Threat locked. Engaging targets."
	],
	"death_cry": [
		"Engine core breaching! AAAARGH!",
		"Mayday, mayday! Ejection systems offline...",
		"Tell my crew... I almost made it...",
		"No! The reactor... it's going critical!"
	],
	"system_alert": [
		"SYSTEM ALERT: High-energy signatures detected nearby.",
		"SYSTEM ALERT: Localized gravity snare activated. Danger high.",
		"SYSTEM ALERT: Faction reinforcements are entering the grid.",
		"SYSTEM ALERT: Combat warning. Hostile interceptors incoming."
	],
	"industrial_banter": [
		"Scanning scrap pile. Looks like high-yield debris.",
		"Commencing salvage sweep. Keep those lasers focused.",
		"Another ship's misfortune is our bonus margin.",
		"Secure the perimeter, let's scrape this hull clean."
	]
}

var active_fetches = {
	"hostile_taunt": false,
	"death_cry": false,
	"system_alert": false,
	"industrial_banter": false
}

func _ready():
	randomize()
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = TIMEOUT_SECONDS
	http_request.request_completed.connect(_on_request_completed)
	
	_discover_ollama_model()

func _discover_ollama_model():
	connection_attempts += 1
	llm_connection_attempt.emit(connection_attempts)
	print("[TRACE] [LLMInterface] Discovering Ollama models (attempt %d)..." % connection_attempts)
	
	var tags_http = HTTPRequest.new()
	add_child(tags_http)
	tags_http.timeout = 2.0
	tags_http.request_completed.connect(func(result, response_code, headers, body):
		tags_http.queue_free()
		var success = false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data is Dictionary and data.has("models"):
					var models = data["models"]
					var installed_names = []
					for m in models:
						if m is Dictionary and m.has("name"):
							installed_names.append(m["name"])
							
					print("[TRACE] [LLMInterface] Installed Ollama models: ", installed_names)
					
					var chosen_model = ""
					if MODEL_NAME in installed_names:
						chosen_model = MODEL_NAME
					elif "qwen2.5:1.5b-instruct" in installed_names:
						chosen_model = "qwen2.5:1.5b-instruct"
					elif "qwen2.5:1.5b" in installed_names:
						chosen_model = "qwen2.5:1.5b"
					elif "qwen2.5-coder:7b" in installed_names:
						chosen_model = "qwen2.5-coder:7b"
					elif "qwen3:8b" in installed_names:
						chosen_model = "qwen3:8b"
					elif "gemma4:latest" in installed_names:
						chosen_model = "gemma4:latest"
					elif "gemma4:12b" in installed_names:
						chosen_model = "gemma4:12b"
					else:
						for name in installed_names:
							if "qwen" in name:
								chosen_model = name
								break
						if chosen_model == "":
							for name in installed_names:
								if "gemma" in name:
									chosen_model = name
									break
						if chosen_model == "" and installed_names.size() > 0:
							chosen_model = installed_names[0]
							
					if chosen_model != "":
						active_model_name = chosen_model
						print("[TRACE] [LLMInterface] Dynamic Ollama model selection: USING '", active_model_name, "'")
					else:
						print("[LLMInterface] No models found in Ollama tags. Defaulting to: ", active_model_name)
					
					success = true
					
		if success:
			print("[TRACE] [LLMInterface] Ollama connection successfully verified.")
			llm_connected = true
			llm_connection_established.emit(active_model_name)
			model_discovered.emit(active_model_name)
		else:
			print("[LLMInterface] Connection to Ollama failed (attempt %d). Retrying in 1.5s..." % connection_attempts)
			get_tree().create_timer(1.5).timeout.connect(_discover_ollama_model)
	)
	
	var err = tags_http.request("http://127.0.0.1:11434/api/tags")
	if err != OK:
		tags_http.queue_free()
		print("[LLMInterface] Failed to initiate tags check. Retrying in 1.5s...")
		get_tree().create_timer(1.5).timeout.connect(_discover_ollama_model)

func request_quest_generation(agent_faction: String, history_text: String, player_credits: int, player_reps: Dictionary, callback: Callable):
	if is_waiting:
		return
	
	active_callback = callback
	is_waiting = true
	last_history_text = history_text
	request_start_time = Time.get_ticks_msec()
	print("[TRACE] [LLMInterface] request_quest_generation initiated at: %d ms" % request_start_time)
	
	var rand_comp = complications[randi() % complications.size()]
	
	# Assemble system prompt
	var system_prompt = "You are an independent, politically neutral space broker and fixer named Broker Kaelen. " + \
		"You operate out of a space station and negotiate contracts with all factions (Zenith, Aurelia, Vanguard). " + \
		"You have no political affiliation. You act purely out of personal profit. You are proud of your greed and broker deals solely to make money. " + \
		"Your tone is cynical, sharp, opportunistic, and business-focused. " + \
		"You call the player 'Shiny' as a nickname in your briefings and dialogue responses (treating them like a fresh, unscarred greenhorn, but also a valuable polished tool that makes you credits).\n\n" + \
		"Current player stats:\n" + \
		"- Credits: " + str(player_credits) + " SC\n" + \
		"- Zenith reputation: " + str(player_reps.get("zenith", 50.0)) + "\n" + \
		"- Aurelia reputation: " + str(player_reps.get("aurelia", -20.0)) + "\n" + \
		"- Vanguard reputation: " + str(player_reps.get("vanguard", -20.0)) + "\n\n" + \
		"### COMPLETED MISSION HISTORY:\n" + \
		"You have worked with this pilot on the following contracts. You must reference these past achievements/failures naturally in your dialogue if the list is not empty:\n" + \
		history_text + "\n\n" + \
		"### QUEST COMPLICATION:\n" + \
		rand_comp + "\n\n" + \
		"Generate a unique space quest. You MUST respond strictly in valid JSON format matching this schema exactly. Do not output any notes, markdown codeblock formatting, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"title\": \"[A short, thematic quest name]\",\n" + \
		"  \"faction\": \"[one of 'zenith', 'aurelia', 'vanguard' representing the client]\",\n" + \
		"  \"agent_name\": \"Broker Kaelen\",\n" + \
		"  \"dialogue\": \"[Agent's spoken briefing text. Mention your broker cut/margin and how this profits you personally. Reference the quest complication. Keep it under 120 words.]\",\n" + \
		"  \"objective\": {\n" + \
		"    \"type\": \"[Either 'KILL_SHIPS' or 'DELIVER_ORE']\",\n" + \
		"    \"target_faction\": \"[Only if type is KILL_SHIPS: either 'aurelia', 'zenith', 'vanguard']\",\n" + \
		"    \"count_required\": [Only if type is KILL_SHIPS: integer between 2 and 6],\n" + \
		"    \"amount_required\": [Only if type is DELIVER_ORE: float between 15.0 and 40.0],\n" + \
		"    \"reward_credits\": [integer reward between 100 and 300]\n" + \
		"  },\n" + \
		"  \"choices\": [\n" + \
		"    {\n" + \
		"      \"text\": \"[Player option 1: Professional acceptance]\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 0,\n" + \
		"        \"reputation_change\": {\"[client_faction]\": 3},\n" + \
		"        \"combat_multiplier\": 1.0,\n" + \
		"        \"reward_credits_multiplier\": 1.0,\n" + \
		"        \"dialogue_response\": \"[Agent response if selected. E.g. 'Excellent. Wired to the feed, go get it done.']\"\n" + \
		"      }\n" + \
		"    },\n" + \
		"    {\n" + \
		"      \"text\": \"[Player option 2: Bold / demanding advance credits]\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 40,\n" + \
		"        \"reputation_change\": {\"[client_faction]\": -2},\n" + \
		"        \"combat_multiplier\": 1.3,\n" + \
		"        \"reward_credits_multiplier\": 1.2,\n" + \
		"        \"dialogue_response\": \"[Agent response. Explain how you're routing them to a more dangerous area to cover the advance. E.g. 'Taking a bite out of my margins? Fine, credits wired. But the threat level is scaled up.']\"\n" + \
		"      }\n" + \
		"    },\n" + \
		"    {\n" + \
		"      \"text\": \"[Player option 3: Audacious / extreme risk and reward]\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 0,\n" + \
		"        \"reputation_change\": {\"[client_faction]\": -5},\n" + \
		"        \"combat_multiplier\": 1.7,\n" + \
		"        \"reward_credits_multiplier\": 1.6,\n" + \
		"        \"dialogue_response\": \"[Agent response. Point out how suicidal this is but that you respect their hustle. E.g. 'Hustling a hustler? I like the nerve. Contract payout increased, but expect heavy resistance.']\"\n" + \
		"      }\n" + \
		"    }\n" + \
		"  ]\n" + \
		"}"
	
	var payload = {
		"model": active_model_name,
		"prompt": system_prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.85,
			"seed": randi()
		}
	}
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	print("[LLMInterface] Sending request to Ollama...")
	var err = http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[LLMInterface] HTTP request failed to initiate. Error code: ", err)
		_trigger_fallback()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	is_waiting = false
	var now = Time.get_ticks_msec()
	var elapsed = (now - request_start_time) / 1000.0
	print("[TRACE] [LLMInterface] HTTP request completed in %.3fs. Result: %d, Response code: %d at %d ms" % [elapsed, result, response_code, now])
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[LLMInterface] HTTP request failed or timed out. Response code: ", response_code)
		_trigger_fallback()
		return
		
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(response_text)
	if err != OK:
		print("[LLMInterface] Failed to parse Ollama response envelope JSON.")
		_trigger_fallback()
		return
		
	var outer_data = json.get_data()
	if not outer_data is Dictionary or not outer_data.has("response"):
		print("[LLMInterface] Response envelope missing 'response' field.")
		_trigger_fallback()
		return
		
	var inner_json_str = outer_data["response"].strip_edges()
	
	# Strip markdown wrappers if LLM returned them despite format constraints
	if inner_json_str.begins_with("```"):
		var end_idx = inner_json_str.find("\n", 3)
		if end_idx != -1:
			inner_json_str = inner_json_str.substr(end_idx + 1)
		if inner_json_str.ends_with("```"):
			inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
		inner_json_str = inner_json_str.strip_edges()

	var inner_json = JSON.new()
	var inner_err = inner_json.parse(inner_json_str)
	if inner_err != OK:
		print("[LLMInterface] Failed to parse inner generated JSON dialogue: ", inner_json_str)
		_trigger_fallback()
		return
		
	var quest_data = inner_json.get_data()
	if not quest_data is Dictionary or not quest_data.has("objective") or not quest_data.has("choices"):
		print("[LLMInterface] Parsed quest data is invalid or missing fields.")
		_trigger_fallback()
		return
		
	print("[LLMInterface] LLM Quest successfully generated: ", quest_data["title"])
	if active_callback.is_valid():
		active_callback.call(quest_data, false)

func _trigger_fallback():
	var elapsed = (Time.get_ticks_msec() - request_start_time) / 1000.0
	print("[TRACE] [LLMInterface] Triggering local procedural fallback quest (Ollama elapsed: %.3fs)." % elapsed)
	
	# Try to pick a fallback template that hasn't been completed/abandoned recently
	var available_indices = []
	for i in range(fallback_templates.size()):
		var template = fallback_templates[i]
		if last_history_text == "" or last_history_text.find(template["title"]) == -1:
			available_indices.append(i)
			
	var idx = 0
	if available_indices.size() > 0:
		idx = available_indices[randi() % available_indices.size()]
	else:
		idx = randi() % fallback_templates.size()
		
	var selected_quest = fallback_templates[idx].duplicate(true)
	
	# Randomize values slightly to make it feel procedural
	var type = selected_quest["objective"]["type"]
	if type == "DELIVER_ORE":
		var orig_amt = selected_quest["objective"]["amount_required"]
		selected_quest["objective"]["amount_required"] = snapped(orig_amt * randf_range(0.85, 1.25), 1.0)
	elif type == "KILL_SHIPS":
		var orig_cnt = selected_quest["objective"]["count_required"]
		selected_quest["objective"]["count_required"] = max(2, int(orig_cnt + randi_range(-1, 1)))
	
	var orig_reward = selected_quest["objective"]["reward_credits"]
	selected_quest["objective"]["reward_credits"] = int(orig_reward * randf_range(0.9, 1.2))
	
	if active_callback.is_valid():
		active_callback.call(selected_quest, true)

func get_chatter_line(type: String) -> String:
	if not chatter_cache.has(type):
		return "Static on comms..."
		
	var line = ""
	if chatter_cache[type].size() > 0:
		line = chatter_cache[type].pop_front()
	else:
		var templates = generic_banter.get(type, ["Static on comms..."])
		line = templates[randi() % templates.size()]
		
	# Trigger background pre-fetch if cache is running low and not currently fetching
	if chatter_cache[type].size() < 2 and not active_fetches[type]:
		fetch_chatter_background(type)
		
	return line

func fetch_chatter_background(type: String):
	active_fetches[type] = true
	
	# Describe the generation task to Ollama based on type
	var description = ""
	match type:
		"hostile_taunt":
			description = "3 unique, short (under 12 words) hostile radio taunts spoken by an enemy NPC pilot attacking the player. Use space theme terminology. Be aggressive or mocking."
		"death_cry":
			description = "3 unique, short (under 12 words) dramatic radio death cries spoken by an NPC pilot as their ship is exploding. Include static or garbled transmission markers like '[static]' or '...'."
		"system_alert":
			description = "3 unique, short (under 12 words) computerized system announcements or sector warnings. Keep it cold, robotic, and technical."
		"industrial_banter":
			description = "3 unique, short (under 12 words) radio chatter lines spoken by a salvager ship crew approaching debris or wreckage. Focus on profit, salvage, scrap, or hauling."
			
	var system_prompt = "You are writing radio chatter dialogue lines for a space simulation game. " + \
		"Generate " + description + " " + \
		"You MUST respond strictly in valid JSON format matching this schema exactly. Do not output any notes, markdown codeblock formatting, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"dialogues\": [\n" + \
		"    \"[Line 1]\",\n" + \
		"    \"[Line 2]\",\n" + \
		"    \"[Line 3]\"\n" + \
		"  ]\n" + \
		"}"
		
	var payload = {
		"model": active_model_name,
		"prompt": system_prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.85,
			"seed": randi()
		}
	}
	
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 12.0 # Give background request plenty of time
	
	temp_http.request_completed.connect(func(result, response_code, headers, body):
		active_fetches[type] = false
		temp_http.queue_free()
		
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[LLMInterface] Background chatter fetch failed for type: ", type, " (unreachable or offline)")
			return
			
		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		var err = json.parse(response_text)
		if err != OK:
			return
			
		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			return
			
		var inner_json_str = outer_data["response"].strip_edges()
		
		# Strip markdown codeblocks
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()
			
		var inner_json = JSON.new()
		var inner_err = inner_json.parse(inner_json_str)
		if inner_err != OK:
			return
			
		var chatter_data = inner_json.get_data()
		if chatter_data is Dictionary and chatter_data.has("dialogues"):
			var dialogues = chatter_data["dialogues"]
			if dialogues is Array:
				for line in dialogues:
					if line is String and line != "":
						chatter_cache[type].append(line.strip_edges())
				print("[LLMInterface] Successfully cached ", dialogues.size(), " lines for background chatter type: ", type)
	)
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		active_fetches[type] = false
		temp_http.queue_free()

var fallback_salvager_names = [
	"Maeve Sterling",
	"Rorik Flint",
	"Tess Torv",
	"Garrick Vance",
	"Sloane Mercer",
	"Jaxom Cruz",
	"Kira Thorne",
	"Caelen Drake"
]

var fallback_salvager_backstories = [
	"A veteran miner from the outer rim who spent years scraping ore from derelict structures. Dislikes corporate faction politics.",
	"A rogue salvager who runs a modified engine loop. Specializes in recovering high-grade alloys from deep space wreckages.",
	"A former Vanguard logistics engineer who went independent. Loves the quiet freedom of the deep belts and black market scrap.",
	"An opportunistic scrapper who believes every piece of debris has a story and a price. Always looking for the next big haul.",
	"A cynical belt-miner who survived a Zenith mine collapse. Now works alone, trusting only their sensors and their lasers.",
	"A young, ambitious pilot who bought a salvaged hauler. Eager to make a name and a fortune in the contested border zones."
]

func fetch_salvager_profile(callback: Callable):
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 10.0
	
	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()
		
		# If request fails or times out, trigger fallback
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			_trigger_salvager_profile_fallback(callback)
			return
			
		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		var err = json.parse(response_text)
		if err != OK:
			_trigger_salvager_profile_fallback(callback)
			return
			
		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_trigger_salvager_profile_fallback(callback)
			return
			
		var inner_json_str = outer_data["response"].strip_edges()
		
		# Strip markdown codeblocks
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()
			
		var inner_json = JSON.new()
		var inner_err = inner_json.parse(inner_json_str)
		if inner_err != OK:
			_trigger_salvager_profile_fallback(callback)
			return
			
		var profile_data = inner_json.get_data()
		if profile_data is Dictionary and profile_data.has("name") and profile_data.has("backstory"):
			callback.call(profile_data)
		else:
			_trigger_salvager_profile_fallback(callback)
	)
	
	var prompt = "Generate a unique sci-fi scrapper/miner pilot name and a short (2-3 sentences) backstory. " + \
		"The pilot operates a salvager ship in the sector. The backstory should detail their origins, their ship name, and their scrapper personality. " + \
		"You MUST respond strictly in valid JSON format matching this schema exactly. Do not output any notes, markdown codeblock formatting, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"name\": \"[Pilot Name]\",\n" + \
		"  \"backstory\": \"[Backstory Text]\"\n" + \
		"}"
		
	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.85,
			"seed": randi()
		}
	}
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_salvager_profile_fallback(callback)

func _trigger_salvager_profile_fallback(callback: Callable):
	var rand_name = fallback_salvager_names[randi() % fallback_salvager_names.size()]
	var rand_backstory = fallback_salvager_backstories[randi() % fallback_salvager_backstories.size()]
	var profile = {
		"name": rand_name,
		"backstory": rand_backstory
	}
	callback.call(profile)
