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

# Fallback Kaelen lines if LLM is offline or too slow
var fallback_completion_lines = [
	"Credits wired and brokerage fee deducted. Don't get comfortable, Shiny. There's always another contract.",
	"Clean work. My client is satisfied, which means I'm satisfied. Payout transferred.",
	"Done and dusted. That's how you earn a reputation in this sector, Shiny. Credits in your account.",
	"Good. My margins are intact and your account is padded. We both win. Come back soon.",
	"Contract fulfilled. You know, Shiny, you're starting to grow on me. Like a profitable parasite."
]

var fallback_abandon_lines = [
	"Contract dumped. You're costing me credit margins, Shiny. I don't forget when people waste my time.",
	"Walking away? My client is furious and frankly, so am I. Come back when you've found your nerve.",
	"Abandoned. You know what that costs me in reputation? Considerably more than it costs you.",
	"Fine. I'll find someone else who actually finishes what they start. This goes in your file, Shiny.",
	"Contract voided. My brokerage fee is still owed. Consider that a lesson in commitment."
]

func _ready():
	randomize()
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = TIMEOUT_SECONDS
	http_request.request_completed.connect(_on_request_completed)
	
	_discover_ollama_model()

func reset_for_restart():
	# Clear the active callback FIRST — this is the one that crashes if it fires
	# into a freed UIManager node after reload_current_scene()
	active_callback = Callable()
	is_waiting = false
	# Cancel any in-flight main request so the old response is ignored on arrival
	if http_request and is_instance_valid(http_request):
		http_request.cancel_request()
	# Clear chatter caches — new session should generate fresh contextual lines
	for key in chatter_cache:
		chatter_cache[key].clear()
	for key in active_fetches:
		active_fetches[key] = false
	print("[LLMInterface] State reset for new game.")



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
			# Pre-warm ALL chatter caches immediately so static fallback lines
			# are never used during the first combat encounter
			print("[TRACE] [LLMInterface] Pre-warming chatter caches...")
			for chatter_type in chatter_cache.keys():
				fetch_chatter_background(chatter_type)
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
	
	# Pick a faction randomly if "neutral" is passed (neutral = broker picks any client)
	var chosen_faction = agent_faction
	if chosen_faction == "neutral" or chosen_faction == "":
		var factions = ["zenith", "aurelia", "vanguard"]
		chosen_faction = factions[randi() % factions.size()]
	
	# Each faction has a distinct named agent, personality, and player nickname
	var agent_name = "Broker Kaelen"
	var agent_persona = ""
	var player_nickname = "Contractor"
	var agent_role = ""
	var example_dialogue = ""
	var example_response_1 = ""
	var example_response_2 = ""
	var example_response_3 = ""
	var example_faction_key = chosen_faction
	
	match chosen_faction:
		"zenith":
			agent_name = "Director Voss"
			agent_role = "Zenith Corporate Acquisitions Director"
			player_nickname = "Contractor"
			agent_persona = "You are Director Voss, a cold, calculating Zenith corporate officer. " + \
				"You speak in clipped, efficient sentences. You have no patience for failure and treat the pilot as an interchangeable asset. " + \
				"You refer to the pilot exclusively as 'Contractor'. You never use slang or humor. " + \
				"You frame all jobs as 'acquisitions', 'operations', or 'directives'. Zenith's interests are paramount."
			example_dialogue = "Zenith has a resource deficit that requires immediate correction, Contractor. Deliver the required silicate tonnage to the station docking bay. Efficiency is non-negotiable."
			example_response_1 = "Confirmed, Contractor. Your assignment is logged. Do not deviate from the directive."
			example_response_2 = "An advance against operational expenses. Noted. Your compensation adjustment is processed. Expect elevated patrol resistance on your route."
			example_response_3 = "Bold negotiation. Zenith respects leverage, Contractor. Payout is revised upward. However, security escalation protocols are now active in your sector."
		"aurelia":
			agent_name = "Liaison Ryn"
			agent_role = "Aurelia Syndicate Trade Liaison"
			player_nickname = "Ghost"
			agent_persona = "You are Liaison Ryn, a smooth-talking, conniving Aurelia syndicate fixer. " + \
				"You are charming but never fully trustworthy. You speak like someone always running an angle. " + \
				"You refer to the pilot exclusively as 'Ghost'. You use words like 'clean', 'quiet', 'off the books'. " + \
				"Everything is framed as an opportunity, never a risk."
			example_dialogue = "Aurelia's got a clean job for someone with your skills, Ghost. Quiet, low profile. The syndicate needs those hulls cleared before the next shipment window. Easy credits, no records."
			example_response_1 = "Smooth. Ghost keeps it clean, that's why I like working with you. Stay off their sensors."
			example_response_2 = "An advance? Smart move, Ghost. Credits transferred. The Syndicate routes you through a riskier corridor to offset the cost. Stay quiet out there."
			example_response_3 = "Playing hardball? I respect the hustle, Ghost. Payout bumped. But Aurelia's rivals will be watching the sector. Keep your profile low."
		"vanguard":
			agent_name = "Captain Dask"
			agent_role = "Vanguard Military Contract Officer"
			player_nickname = "Merc"
			agent_persona = "You are Captain Dask, a gruff, no-nonsense Vanguard military contract officer. " + \
				"You are direct and have zero tolerance for excuses or negotiation theatre. " + \
				"You refer to the pilot exclusively as 'Merc'. You use military shorthand: 'ROE', 'boots on hull', 'clear the zone'. " + \
				"You respect competence and despise weakness."
			example_dialogue = "Vanguard needs those Aurelia raiders cleared from the shipping lane, Merc. Four contacts, high priority. Take them down and get back to the dock. No theatrics."
			example_response_1 = "Copy that, Merc. ROE is clear: engage and eliminate. Don't make it complicated."
			example_response_2 = "You want an advance, Merc? Fine. But Vanguard doesn't cover operational cowardice. Threat level is escalated. Don't embarrass us."
			example_response_3 = "Renegotiating under fire, Merc. Bold. Payout is adjusted. Don't expect the Vanguard to soften the zone for you."
		_:
			agent_name = "Broker Kaelen"
			agent_role = "Neutral Fixer & Profit Broker"
			player_nickname = "Shiny"
			agent_persona = "You are Broker Kaelen, an independent, politically neutral space broker and fixer. " + \
				"You operate out of a space station and negotiate contracts with all factions for personal profit. " + \
				"You are cynical, sharp, and opportunistic. You call the pilot 'Shiny' — treating them like an unscarred greenhorn who is also your most profitable tool. " + \
				"You always mention your broker's cut and how the deal benefits you personally."
			example_dialogue = "Zenith needs ore, I need my cut, and you need credits, Shiny. Bring me 25 cubic metres and I'll keep my brokerage fee reasonable. Don't dawdle."
			example_response_1 = "Excellent, Shiny. My client is watching the clock, so don't waste my time."
			example_response_2 = "Taking a bite out of my margins, Shiny? Fine. Credits wired. But I'm routing you through a contested lane to cover the difference."
			example_response_3 = "Hustling a hustler? I respect the nerve, Shiny. Payout is bumped. But enemies will be expecting you."
	
	# Randomly pick which objective type to demonstrate in the example (50/50)
	# so the LLM sees both formats equally and generates a mix
	var example_obj_block = ""
	var example_title = ""
	var kill_target_constraint = ""
	
	if randi() % 2 == 0:
		# Show a DELIVER_ORE example
		example_title = "Silicate Run"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"DELIVER_ORE\",\n" + \
			"    \"amount_required\": 25.0,\n" + \
			"    \"reward_credits\": 160\n" + \
			"  },"
	else:
		# Show a KILL_SHIPS example
		var kill_targets = ["zenith", "aurelia", "vanguard"]
		kill_targets.erase(chosen_faction)
		var kill_target = kill_targets[randi() % kill_targets.size()]
		example_title = "Clear the Lane"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"KILL_SHIPS\",\n" + \
			"    \"target_faction\": \"" + kill_target + "\",\n" + \
			"    \"count_required\": 3,\n" + \
			"    \"reward_credits\": 200\n" + \
			"  },"


	var system_prompt = agent_persona + "\n\n" + \
		"Current pilot stats:\n" + \
		"- Credits: " + str(player_credits) + " SC\n" + \
		"- Zenith reputation: " + str(player_reps.get("zenith", 50.0)) + "\n" + \
		"- Aurelia reputation: " + str(player_reps.get("aurelia", -20.0)) + "\n" + \
		"- Vanguard reputation: " + str(player_reps.get("vanguard", -20.0)) + "\n\n" + \
		"### COMPLETED MISSION HISTORY:\n" + \
		"Reference past contracts naturally in your dialogue if the list is not empty:\n" + \
		history_text + "\n\n" + \
		"### QUEST COMPLICATION:\n" + \
		rand_comp + "\n\n" + \
		"Generate a unique space quest. You MUST respond strictly in valid JSON format. Do not output notes, markdown, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"title\": \"" + example_title + "\",\n" + \
		"  \"faction\": \"" + chosen_faction + "\",\n" + \
		"  \"agent_name\": \"" + agent_name + "\",\n" + \
		"  \"dialogue\": \"" + example_dialogue + "\",\n" + \
		example_obj_block + "\n" + \
		"  \"choices\": [\n" + \
		"    {\n" + \
		"      \"text\": \"I'll take the job.\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 0,\n" + \
		"        \"reputation_change\": {\"" + chosen_faction + "\": 3},\n" + \
		"        \"combat_multiplier\": 1.0,\n" + \
		"        \"reward_credits_multiplier\": 1.0,\n" + \
		"        \"dialogue_response\": \"" + example_response_1 + "\"\n" + \
		"      }\n" + \
		"    },\n" + \
		"    {\n" + \
		"      \"text\": \"I need a credit advance first.\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 40,\n" + \
		"        \"reputation_change\": {\"" + chosen_faction + "\": -2},\n" + \
		"        \"combat_multiplier\": 1.3,\n" + \
		"        \"reward_credits_multiplier\": 1.2,\n" + \
		"        \"dialogue_response\": \"" + example_response_2 + "\"\n" + \
		"      }\n" + \
		"    },\n" + \
		"    {\n" + \
		"      \"text\": \"The payout isn't worth the risk. Increase it.\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 0,\n" + \
		"        \"reputation_change\": {\"" + chosen_faction + "\": -5},\n" + \
		"        \"combat_multiplier\": 1.7,\n" + \
		"        \"reward_credits_multiplier\": 1.6,\n" + \
		"        \"dialogue_response\": \"" + example_response_3 + "\"\n" + \
		"      }\n" + \
		"    }\n" + \
		"  ]\n" + \
		"}\n\n" + \
		"Now generate a COMPLETELY DIFFERENT quest with a unique title and all-new dialogue written in your character's voice. " + \
		"The faction must be \"" + chosen_faction + "\". The agent_name must be \"" + agent_name + "\". " + \
		"The objective type must be either 'DELIVER_ORE' or 'KILL_SHIPS' — choose whichever fits the story best. " + \
		kill_target_constraint + \
		"For KILL_SHIPS include 'target_faction' and 'count_required'. For DELIVER_ORE include 'amount_required'. " + \
		"Always call the pilot '" + player_nickname + "' — never use any other nickname. " + \
		"Output only the raw JSON object."
	
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
	
	print("[LLMInterface] Sending request to Ollama for faction: ", chosen_faction, " agent: ", agent_name)
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

func get_chatter_line(type: String, context: Dictionary = {}) -> String:
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
		fetch_chatter_background(type, context)
		
	return line

# Build a context dict from current GlobalState for use in chatter prompts
func _build_chatter_context(extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {}
	ctx["player_credits"] = GlobalState.player_credits
	ctx["cargo"] = int(GlobalState.cargo)
	ctx["cargo_max"] = int(GlobalState.cargo_max)
	var reps = GlobalState.reputations
	ctx["rep_zenith"]   = int(reps.get("zenith",   50.0))
	ctx["rep_aurelia"]  = int(reps.get("aurelia", -20.0))
	ctx["rep_vanguard"] = int(reps.get("vanguard", -20.0))
	var qm = Engine.get_singleton("QuestManager") if Engine.has_singleton("QuestManager") else null
	if qm == null:
		var tree = Engine.get_main_loop()
		if tree and tree.root:
			qm = tree.root.get_node_or_null("/root/QuestManager")
	if qm and qm.is_quest_active():
		ctx["active_quest_title"] = qm.active_quest.get("title", "")
		ctx["active_quest_type"]  = qm.active_quest.get("objective_type", "")
	for k in extra:
		ctx[k] = extra[k]
	return ctx


func fetch_chatter_background(type: String, context: Dictionary = {}):
	active_fetches[type] = true
	
	# Merge in live GlobalState context
	var ctx = _build_chatter_context(context)
	
	var credits_str  = str(ctx.get("player_credits", 0)) + " SC"
	var cargo_str    = str(ctx.get("cargo", 0)) + "/" + str(ctx.get("cargo_max", 100)) + " m³"
	var rep_str      = "Zenith " + str(ctx.get("rep_zenith", 50)) + \
		", Aurelia " + str(ctx.get("rep_aurelia", -20)) + \
		", Vanguard " + str(ctx.get("rep_vanguard", -20))
	var quest_str    = ctx.get("active_quest_title", "none")
	var attacker_fac = ctx.get("attacker_faction", "unknown")
	var wreck_name   = ctx.get("wreck_name", "")
	var killed_by_player = ctx.get("killed_by_player", false)
	
	var context_block = "\nCurrent game context:\n" + \
		"- Pilot credits: " + credits_str + "\n" + \
		"- Cargo hold: " + cargo_str + "\n" + \
		"- Faction reputations: " + rep_str + "\n" + \
		"- Active contract: " + quest_str + "\n"
	
	# Describe the generation task to Ollama based on type
	var description = ""
	match type:
		"hostile_taunt":
			var faction_hint = ""
			if attacker_fac != "unknown":
				faction_hint = "The attacker is a " + attacker_fac.to_upper() + " pilot. "
			var cargo_hint = ""
			if ctx.get("cargo", 0) > 10:
				cargo_hint = "The target is hauling " + cargo_str + " of cargo — taunt them about it. "
			var rep_hint = ""
			if ctx.get("rep_zenith", 50) < -30:
				rep_hint = "The pilot has burned bridges with Zenith — reference this enmity. "
			elif ctx.get("rep_aurelia", 0) < -30:
				rep_hint = "The pilot is despised by Aurelia — use this in the taunt. "
			var mission_hint = ""
			if quest_str != "none":
				mission_hint = "The target is on a contract called '" + quest_str + "' — mock them for it. "
			description = "3 unique, aggressive radio taunts (under 12 words each) from a " + \
				attacker_fac.to_upper() + " enemy pilot targeting the player ship. " + \
				faction_hint + cargo_hint + rep_hint + mission_hint + \
				"Be creative, threatening, and faction-flavoured. No generic lines."
		"death_cry":
			var ship_hint = ""
			if attacker_fac != "unknown":
				ship_hint = "The dying pilot flew for " + attacker_fac.to_upper() + ". "
			description = "3 unique dramatic death radio transmissions (under 12 words each) from a " + \
				attacker_fac.to_upper() + " pilot as their ship explodes. " + ship_hint + \
				"Include static markers like '[static]' or '...'. Vary tone: some defiant, some fearful, some darkly funny."
		"system_alert":
			description = "3 unique cold robotic system announcements or sector warnings (under 12 words each). " + \
				"Vary the threat type — gravitational, faction, radiation, debris field."
		"industrial_banter":
			var wreck_hint = ""
			if wreck_name != "":
				# Parse faction and ship type out of the node name (e.g. AURELIA_Raider_512_Wreck)
				var upper = wreck_name.to_upper()
				var faction_found = ""
				for f in ["ZENITH", "AURELIA", "VANGUARD"]:
					if f in upper:
						faction_found = f
						break
				var ship_class = ""
				for c in ["PATROL", "RAIDER", "SENTINEL", "INTERCEPTOR", "ELITE"]:
					if c in upper:
						ship_class = c
						break
				if killed_by_player:
					wreck_hint = "The salvager is cutting up a " + faction_found + " " + ship_class + \
						" wreck left by the player pilot. Comment on the battle damage, " + \
						"the hull condition, the pilot who must have done this, or what they can salvage. " + \
						"Be colourful — e.g. 'whoever hit this thing wasn't messing around'. "
				else:
					wreck_hint = "The salvager is approaching a " + faction_found + " " + ship_class + \
						" wreck. Comment on the expected salvage value or the faction's gear quality. "
			description = "3 unique radio chatter lines (under 15 words each) from a scrapper salvage crew. " + \
				wreck_hint + \
				"They are pragmatic, slightly world-weary, always thinking about credits. Avoid clichés."
		
	var system_prompt = "You are writing radio chatter dialogue lines for a space simulation game rated PG-13. " + \
		"Colourful language, mild swearing, dark humour, and sharp insults are encouraged where they fit the character. " + \
		"Do NOT use explicit sexual content or slurs. Everything else is fair game — be creative and unpredictable. " + \
		"Generate " + description + context_block + \
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
			"temperature": 0.9,
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

func request_kaelen_reaction(quest_data: Dictionary, callback: Callable):
	# Build a minimal context summary for Kaelen to react to
	var title = quest_data.get("title", "the contract")
	var faction = quest_data.get("faction", "neutral").capitalize()
	var obj = quest_data.get("objective", {})
	var obj_type = obj.get("type", "")
	var task_desc = ""
	if obj_type == "DELIVER_ORE":
		task_desc = "deliver %s m³ of ore for %s credits" % [str(int(obj.get("amount_required", 20))), str(obj.get("reward_credits", 150))]
	elif obj_type == "KILL_SHIPS":
		task_desc = "destroy %d %s ships for %s credits" % [obj.get("count_required", 3), obj.get("target_faction", "enemy").capitalize(), str(obj.get("reward_credits", 200))]
	else:
		task_desc = "complete the contract"

	var prompt = "You are Broker Kaelen, a cynical, profit-driven, politically neutral space broker. " + \
		"You call the pilot 'Shiny'. You just brokered a contract named '" + title + "' for the " + faction + " faction — the task was to " + task_desc + ". " + \
		"Generate TWO short unique lines of dialogue from Kaelen (under 25 words each): " + \
		"one she says when the pilot successfully completes and hands in the contract (satisfied but still self-interested), " + \
		"and one she says when the pilot abandons mid-contract (annoyed, sharp, but keeps it professional). " + \
		"Reference the specific quest task or faction naturally. Do NOT use generic lines. " + \
		"You MUST respond strictly in valid JSON format. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"completion\": \"[Kaelen's unique completion line]\",\n" + \
		"  \"abandon\": \"[Kaelen's unique abandon line]\"\n" + \
		"}"

	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 12.0

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[LLMInterface] Kaelen reaction fetch failed. Using fallback lines.")
			_trigger_kaelen_reaction_fallback(callback)
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			_trigger_kaelen_reaction_fallback(callback)
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_trigger_kaelen_reaction_fallback(callback)
			return

		var inner_json_str = outer_data["response"].strip_edges()
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()

		var inner_json = JSON.new()
		if inner_json.parse(inner_json_str) != OK:
			_trigger_kaelen_reaction_fallback(callback)
			return

		var reaction_data = inner_json.get_data()
		if reaction_data is Dictionary and reaction_data.has("completion") and reaction_data.has("abandon"):
			print("[LLMInterface] Kaelen reaction lines generated for quest: ", title)
			callback.call(reaction_data["completion"], reaction_data["abandon"])
		else:
			_trigger_kaelen_reaction_fallback(callback)
	)

	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.9,
			"seed": randi()
		}
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_kaelen_reaction_fallback(callback)

func _trigger_kaelen_reaction_fallback(callback: Callable):
	var comp = fallback_completion_lines[randi() % fallback_completion_lines.size()]
	var abn = fallback_abandon_lines[randi() % fallback_abandon_lines.size()]
	callback.call(comp, abn)

func _trigger_salvager_profile_fallback(callback: Callable):
	var rand_name = fallback_salvager_names[randi() % fallback_salvager_names.size()]
	var rand_backstory = fallback_salvager_backstories[randi() % fallback_salvager_backstories.size()]
	var profile = {
		"name": rand_name,
		"backstory": rand_backstory
	}
	callback.call(profile)

# Fallback lines for when Kaelen acknowledges a partial ore drop-off
var fallback_partial_delivery_lines = [
	"I'll set this aside for you, Shiny. But don't get comfortable — my client wants the rest, and they're not patient people.",
	"Noted. I'll log it against your contract. You've still got a haul to finish, so stop wasting time chatting with me.",
	"Banking what you've got. Get the rest of that ore before my client starts asking questions I can't answer.",
	"Partial logged. My client is going to ask when the shipment is complete, and 'almost' isn't a number they recognise.",
	"Fine, I'll hold it. But I'm not a warehouse, Shiny — get out there and finish the run.",
]

# Generate a unique Kaelen line for a partial ore delivery.
# delivered_amount: m³ just dropped off now. total_banked: cumulative m³ banked so far. total_required: full contract amount.
func request_partial_delivery_line(quest_title: String, delivered_amount: float, total_banked: float, total_required: float, callback: Callable):
	var remaining = max(0.0, total_required - total_banked)
	var pct = int(clamp(total_banked / total_required * 100.0, 0.0, 99.0))

	var prompt = "You are Broker Kaelen, a cynical profit-driven space broker. You call the pilot 'Shiny'. " + \
		"The pilot just dropped off %.0f m³ of ore as a partial shipment for the contract '%s'. " % [delivered_amount, quest_title] + \
		"They have now delivered %.0f / %.0f m³ total (%d%% done). They still owe %.0f m³ more. " % [total_banked, total_required, pct, remaining] + \
		"Generate ONE short line of dialogue from Kaelen (under 25 words) reacting to this. " + \
		"She should: acknowledge she's holding it for them, mention the remaining amount or urgency, and be characteristically impatient or wry. " + \
		"Reference the specific numbers. PG-13 tone — she can be sharp. Do NOT use generic lines. " + \
		"You MUST respond strictly in valid JSON format. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"line\": \"[Kaelen's unique partial delivery line]\"\n" + \
		"}"

	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 10.0

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var inner_json_str = outer_data["response"].strip_edges()
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()

		var inner_json = JSON.new()
		if inner_json.parse(inner_json_str) != OK:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var data = inner_json.get_data()
		if data is Dictionary and data.has("line") and data["line"] is String and data["line"].length() > 3:
			callback.call(data["line"])
		else:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
	)

	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.92,
			"seed": randi()
		}
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])

