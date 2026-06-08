extends Node

const HISTORY_FILE_PATH = "user://quest_history.md"

signal quest_accepted()
signal quest_progress_updated()
signal quest_completed()
signal quest_abandoned()

var active_quest: Dictionary = {}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Create history file if it does not exist
	_load_quest_history()
	# Connect to ship destroyed signals to track combat quests
	GlobalState.ship_destroyed.connect(_on_ship_destroyed)

func _load_quest_history() -> String:
	if not FileAccess.file_exists(HISTORY_FILE_PATH):
		var f = FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
		if f:
			f.store_line("# Quest History Log")
			f.close()
		return ""
	
	var f = FileAccess.open(HISTORY_FILE_PATH, FileAccess.READ)
	if f:
		var content = f.get_as_text()
		f.close()
		return content
	return ""

func _log_quest_to_file(quest_title: String, quest_type: String, outcome: String):
	var history = _load_quest_history()
	var f = FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(history)
		f.store_line("- **" + quest_title + "** (" + quest_type + "): " + outcome)
		f.close()

func is_quest_active() -> bool:
	return not active_quest.is_empty()

func is_quest_completed() -> bool:
	if not is_quest_active():
		return false
	
	var type = active_quest["objective_type"]
	if type == "KILL_SHIPS":
		return active_quest["current_count"] >= active_quest["count_required"]
	elif type == "DELIVER_ORE":
		# Count already-banked ore plus what's currently in the hold
		var banked = active_quest.get("partial_delivered", 0.0)
		return (banked + GlobalState.cargo) >= active_quest["amount_required"]
		
	return false


func request_new_quest(agent_faction: String, callback: Callable):
	var history_text = _load_quest_history()
	LLMInterface.request_quest_generation(agent_faction, history_text, GlobalState.player_credits, GlobalState.reputations, callback)

func accept_quest(quest_data: Dictionary, selected_choice: Dictionary):
	# Defensive access — LLM data may be missing keys on malformed output
	var obj_data = quest_data.get("objective", {})
	var type = obj_data.get("type", "DELIVER_ORE")
	var reward_credits = obj_data.get("reward_credits", 100)
	
	var consequence = selected_choice.get("consequence", {})
	var credits_immediate = consequence.get("credits_immediate", 0)
	var rep_change = consequence.get("reputation_change", {})
	var combat_mult = max(0.5, consequence.get("combat_multiplier", 1.0))  # clamp: never 0
	var reward_mult = max(0.5, consequence.get("reward_credits_multiplier", 1.0))
	
	# Apply immediate credit rewards/penalties
	GlobalState.player_credits += credits_immediate
	
	# Apply reputation changes
	for faction in rep_change.keys():
		GlobalState.adjust_reputation(faction, rep_change[faction])
		
	# Populate active quest dictionary
	active_quest = {
		"title": quest_data.get("title", "Unnamed Contract"),
		"faction": quest_data.get("faction", "zenith"),
		"agent_name": quest_data.get("agent_name", "Broker Kaelen"),
		"dialogue": quest_data.get("dialogue", ""),
		"objective_type": type,
		"combat_multiplier": combat_mult,
		"reward_credits_multiplier": reward_mult,
		"reward_credits": reward_credits,
		"choice_text_selected": selected_choice.get("text", ""),
		"agent_response": consequence.get("dialogue_response", "")
	}
	
	if type == "KILL_SHIPS":
		active_quest["target_faction"] = obj_data.get("target_faction", "zenith")
		active_quest["count_required"] = max(1, int(obj_data.get("count_required", 3) * combat_mult))
		active_quest["current_count"] = 0
		# Schedule mission target spawn for shortly after undock (3 seconds gives time to clear the station)
		var spawn_faction = active_quest["target_faction"]
		var spawn_count = active_quest["count_required"]
		get_tree().create_timer(3.0).timeout.connect(func():
			GlobalState.spawn_mission_targets(spawn_faction, spawn_count)
		)
	elif type == "DELIVER_ORE":
		active_quest["amount_required"] = max(1.0, snapped(obj_data.get("amount_required", 20.0), 1.0))
		active_quest["partial_delivered"] = 0.0  # Tracks ore already handed in via partial shipments
		
	print("[QuestManager] Quest accepted: ", active_quest["title"], " type:", type, " (Difficulty multiplier: ", combat_mult, ")")
	quest_accepted.emit()


# Bank a partial ore delivery. Returns the amount actually delivered (capped at remaining need).
func deliver_partial(amount: float) -> float:
	if not is_quest_active() or active_quest["objective_type"] != "DELIVER_ORE":
		return 0.0
	var remaining = active_quest["amount_required"] - active_quest.get("partial_delivered", 0.0)
	var to_deliver = min(amount, remaining, GlobalState.cargo)
	to_deliver = max(0.0, to_deliver)
	if to_deliver <= 0.0:
		return 0.0
	GlobalState.cargo -= to_deliver
	active_quest["partial_delivered"] = active_quest.get("partial_delivered", 0.0) + to_deliver
	print("[QuestManager] Partial delivery: %.1f m³ banked. Total so far: %.1f / %.1f" % [
		to_deliver, active_quest["partial_delivered"], active_quest["amount_required"]])
	quest_progress_updated.emit()
	return to_deliver

func complete_quest():
	if not is_quest_active() or not is_quest_completed():
		return
		
	var final_payout = int(active_quest["reward_credits"] * active_quest["reward_credits_multiplier"])
	GlobalState.player_credits += final_payout
	
	# Adjust faction relationship positive gain
	GlobalState.adjust_reputation(active_quest["faction"], 5.0)
	
	# If delivery quest, deduct only whatever remaining cargo is still in the hold
	# (partial deliveries already deducted cargo when they were banked)
	if active_quest["objective_type"] == "DELIVER_ORE":
		var banked = active_quest.get("partial_delivered", 0.0)
		var remaining_needed = max(0.0, active_quest["amount_required"] - banked)
		GlobalState.cargo -= remaining_needed
		
	# Append to history file log
	var detail = "Completed. Payout: " + str(final_payout) + " SC. Choice selected: '" + active_quest["choice_text_selected"] + "'."
	_log_quest_to_file(active_quest["title"], active_quest["objective_type"], detail)
	
	print("[QuestManager] Quest completed successfully: ", active_quest["title"])
	quest_completed.emit()
	active_quest = {}

func abandon_quest():
	if not is_quest_active():
		return
		
	# Apply standing penalty
	GlobalState.adjust_reputation(active_quest["faction"], -5.0)
	
	# Append to history file log
	_log_quest_to_file(active_quest["title"], active_quest["objective_type"], "Abandoned.")
	
	print("[QuestManager] Quest abandoned: ", active_quest["title"])
	quest_abandoned.emit()
	active_quest = {}

func _on_ship_destroyed(faction_name: String):
	if not is_quest_active():
		return
		
	if active_quest["objective_type"] == "KILL_SHIPS" and active_quest["target_faction"] == faction_name:
		active_quest["current_count"] += 1
		print("[QuestManager] Quest target killed. Progress: ", active_quest["current_count"], "/", active_quest["count_required"])
		quest_progress_updated.emit()
