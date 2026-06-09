extends Control

# UI Nodes created dynamically
var hud_panel: Panel
var credits_label: Label
var cargo_label: Label
var cargo_bar: ProgressBar

var target_panel: PanelContainer
var target_label: Label
var target_icon: TextureRect
var target_action_box: HBoxContainer
var icons_sheet = preload("res://assets/icons.png")

var overview_panel: Panel
var overview_list: VBoxContainer
var overview_collapsed: bool = false
var collapse_btn: Button

var dock_panel: Panel
var dock_label: Label
# Background image for the dock panel — shown only when docked at a
# repair_shop station, set to RepairShop.png for thematic flavor.
var dock_background: TextureRect
var sell_btn: Button
var upgrade_cargo_btn: Button
var upgrade_laser_btn: Button
var repair_btn: Button
var agent_service_btn: Button

var agent_panel: Panel
var agent_name_label: Label
var agent_dialogue_label: Label
var agent_choices_container: VBoxContainer
var agent_back_btn: Button

var quest_tracker_panel: Panel
var quest_tracker_title: Label
var quest_tracker_progress: Label
var quest_tracker_logo: TextureRect

# Systems Comms Chat Window
var chat_window_panel: Panel
var chat_scroll: ScrollContainer
var chat_vbox: VBoxContainer
var max_chat_messages: int = 50
var agent_click_time: float = 0.0

# Preloaded assets
var quest_givers_sheet = preload("res://assets/QuestGivers.png")
var faction_branding_sheet = preload("res://assets/factionBranding.png")

# Sliced elements inside Agent Panel
var agent_portrait: TextureRect
var agent_client_logo: TextureRect

var pause_panel: Panel
var death_panel: Panel
var context_panel: Panel
var context_action_btn: Button

var current_station: Node3D = null

var cached_quest_data: Dictionary = {}
var cached_quest_is_fallback: bool = false
var is_waiting_for_agent_board: bool = false

# LLM-generated Kaelen handoff line for the currently-cached quest.
# Empty string means "not yet fetched" or "fetch failed — fall back to canned 5".
var cached_unique_intro: String = ""

# Dynamic Kaelen reaction lines — unique per quest, generated on acceptance
var cached_completion_line: String = ""
var cached_abandon_line: String = ""

var loading_panel: Panel
var loading_bar: ProgressBar
var loading_status_label: Label

var is_llm_ready: bool = false
var is_tts_ready: bool = false
var last_llm_attempt: int = 0
var last_tts_attempt: int = 0

# Sorting parameters
var sort_column: String = "distance"
var sort_ascending: bool = true
var btn_name: Button
var btn_dist: Button
var btn_type: Button

# Resize parameters
var is_resizing: bool = false
const RESIZE_BORDER_WIDTH := 6.0
var resize_handle: Control
var drag_start_mouse_x: float = 0.0
var drag_start_anchor_left: float = 0.0
var sort_timer: float = 0.0
const SORT_INTERVAL := 0.2

var target_marker: Control
var marker_active: bool = false
var marker_timer: float = 0.0
var marker_pos_3d: Vector3 = Vector3.ZERO
var selection_marker: Control
var selected_row_style: StyleBoxFlat

func _ready():
	# Configure selected row highlight stylebox
	selected_row_style = StyleBoxFlat.new()
	selected_row_style.bg_color = Color(0.0, 0.35, 0.55, 0.45) # Glowing semi-transparent cyan background
	selected_row_style.border_width_left = 2
	selected_row_style.border_width_top = 2
	selected_row_style.border_width_right = 2
	selected_row_style.border_width_bottom = 2
	selected_row_style.border_color = Color(0.0, 0.85, 1.0, 1.0) # Bright neon cyan border
	selected_row_style.corner_radius_top_left = 4
	selected_row_style.corner_radius_top_right = 4
	selected_row_style.corner_radius_bottom_right = 4
	selected_row_style.corner_radius_bottom_left = 4

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Configure layout
	anchors_preset = Control.PRESET_FULL_RECT
	
	# Connect GlobalState signals
	GlobalState.credits_changed.connect(_on_credits_changed)
	GlobalState.cargo_changed.connect(_on_cargo_changed)
	GlobalState.target_changed.connect(_on_target_changed)
	GlobalState.game_paused.connect(_on_pause_changed)
	GlobalState.entities_changed.connect(refresh_overview)
	
	# Connect QuestManager signals
	QuestManager.quest_accepted.connect(_on_quest_accepted)
	QuestManager.quest_progress_updated.connect(_on_quest_progress_updated)
	QuestManager.quest_completed.connect(_on_quest_completed)
	QuestManager.quest_abandoned.connect(_on_quest_abandoned)
	
	_create_hud()
	_create_target_panel()
	_create_overview()
	_create_dock_menu()
	_create_context_menu()
	_create_death_screen()
	_create_pause_menu()
	
	# Create target indicator marker
	target_marker = Control.new()
	target_marker.name = "TargetMarker"
	add_child(target_marker)
	target_marker.draw.connect(_on_target_marker_draw)
	target_marker.visible = false
	
	# Create selection indicator marker
	selection_marker = Control.new()
	selection_marker.name = "SelectionMarker"
	add_child(selection_marker)
	selection_marker.draw.connect(_on_selection_marker_draw)
	selection_marker.visible = false
	
	# Initial UI state
	_on_credits_changed(GlobalState.player_credits)
	_on_cargo_changed(GlobalState.cargo)
	_on_target_changed(GlobalState.active_target)
	
	# Initialize startup loading screen to pre-cache the first quest & TTS
	_create_loading_screen()
	GlobalState.paused = true
	
	LLMInterface.llm_connection_attempt.connect(_on_llm_connection_attempt)
	LLMInterface.llm_connection_established.connect(_on_llm_connected)
	TTSInterface.tts_connection_attempt.connect(_on_tts_connection_attempt)
	TTSInterface.tts_connection_established.connect(_on_tts_connected)

func _process(delta):
	if GlobalState.paused: return
	
	# Update overview list item distances
	_update_overview_distances(delta)
	
	# Update target indicator marker
	if marker_active:
		marker_timer -= delta
		if marker_timer <= 0.0:
			marker_active = false
			target_marker.visible = false
		else:
			_update_target_marker_position()
			
	# Update HUD player health and reputations
	_update_hud_health()
	_update_hud_reputations()
			
	# Update selection marker position
	_update_selection_marker_position()

func _create_hud():
	hud_panel = Panel.new()
	hud_panel.custom_minimum_size = Vector2(350, 160) # Fit credits, cargo, health, and rep components
	hud_panel.position = Vector2(20, 20)
	add_child(hud_panel)
	
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(10, 10)
	vbox.custom_minimum_size = Vector2(330, 140)
	hud_panel.add_child(vbox)
	
	credits_label = Label.new()
	credits_label.text = "Credits: 50 SC"
	vbox.add_child(credits_label)
	
	cargo_label = Label.new()
	cargo_label.text = "Cargo: 0 / 100 m³"
	vbox.add_child(cargo_label)
	
	cargo_bar = ProgressBar.new()
	cargo_bar.max_value = GlobalState.cargo_max
	cargo_bar.value = 0
	cargo_bar.custom_minimum_size = Vector2(300, 12)
	vbox.add_child(cargo_bar)
	
	var hp_lbl = Label.new()
	hp_lbl.name = "HPLabel"
	hp_lbl.text = "HP: 100 / 100"
	vbox.add_child(hp_lbl)
	
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.max_value = 100.0
	hp_bar.value = 100.0
	hp_bar.custom_minimum_size = Vector2(300, 12)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.9, 0.4, 1.0) # Green fill by default
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	sb.corner_radius_bottom_left = 3
	hp_bar.add_theme_stylebox_override("fill", sb)
	vbox.add_child(hp_bar)
	
	var rep_lbl = Label.new()
	rep_lbl.name = "RepLabel"
	rep_lbl.text = "Rep: ZEN 50 | AUR -20 | VAN -20"
	vbox.add_child(rep_lbl)
	
	# Quest Tracker HUD Panel (positioned at Vector2(20, 220) with horizontal layout)
	quest_tracker_panel = Panel.new()
	quest_tracker_panel.custom_minimum_size = Vector2(360, 80)
	quest_tracker_panel.position = Vector2(20, 220)
	add_child(quest_tracker_panel)
	
	var tracker_style = StyleBoxFlat.new()
	tracker_style.bg_color = Color(0.1, 0.1, 0.12, 0.6)
	tracker_style.border_width_left = 1
	tracker_style.border_width_top = 1
	tracker_style.border_width_right = 1
	tracker_style.border_width_bottom = 1
	tracker_style.border_color = Color(0.0, 0.8, 0.8, 0.5)
	tracker_style.corner_radius_top_left = 4
	tracker_style.corner_radius_top_right = 4
	tracker_style.corner_radius_bottom_right = 4
	tracker_style.corner_radius_bottom_left = 4
	quest_tracker_panel.add_theme_stylebox_override("panel", tracker_style)
	
	var tracker_hbox = HBoxContainer.new()
	tracker_hbox.position = Vector2(8, 8)
	tracker_hbox.custom_minimum_size = Vector2(344, 64)
	quest_tracker_panel.add_child(tracker_hbox)
	
	# Faction branding logo on the left of tracker
	quest_tracker_logo = TextureRect.new()
	quest_tracker_logo.custom_minimum_size = Vector2(48, 48)
	quest_tracker_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quest_tracker_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	quest_tracker_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tracker_hbox.add_child(quest_tracker_logo)
	
	var tracker_vbox = VBoxContainer.new()
	tracker_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracker_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tracker_hbox.add_child(tracker_vbox)
	
	var tracker_header = Label.new()
	tracker_header.text = "ACTIVE CONTRACT"
	tracker_header.add_theme_font_size_override("font_size", 10)
	tracker_header.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	tracker_vbox.add_child(tracker_header)
	
	quest_tracker_title = Label.new()
	quest_tracker_title.text = "Contract Title"
	quest_tracker_title.add_theme_font_size_override("font_size", 13)
	tracker_vbox.add_child(quest_tracker_title)
	
	quest_tracker_progress = Label.new()
	quest_tracker_progress.text = "Progress: 0 / 0"
	quest_tracker_progress.add_theme_font_size_override("font_size", 12)
	tracker_vbox.add_child(quest_tracker_progress)
	
	quest_tracker_panel.visible = false

	# Systems Comms Chat Window (positioned at the bottom-left corner using anchors for responsiveness)
	chat_window_panel = Panel.new()
	chat_window_panel.custom_minimum_size = Vector2(400, 200)
	chat_window_panel.anchor_top = 1.0
	chat_window_panel.anchor_bottom = 1.0
	chat_window_panel.offset_left = 20
	chat_window_panel.offset_top = -220
	chat_window_panel.offset_right = 420
	chat_window_panel.offset_bottom = -20
	add_child(chat_window_panel)
	
	var chat_style = StyleBoxFlat.new()
	chat_style.bg_color = Color(0.08, 0.08, 0.1, 0.6) # Translucent dark background
	chat_style.border_width_left = 1
	chat_style.border_width_top = 1
	chat_style.border_width_right = 1
	chat_style.border_width_bottom = 1
	chat_style.border_color = Color(0.0, 0.85, 1.0, 0.35) # Glowing cyan border
	chat_style.corner_radius_top_left = 6
	chat_style.corner_radius_top_right = 6
	chat_style.corner_radius_bottom_right = 6
	chat_style.corner_radius_bottom_left = 6
	chat_window_panel.add_theme_stylebox_override("panel", chat_style)
	
	var chat_layout = VBoxContainer.new()
	chat_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	chat_layout.offset_left = 10
	chat_layout.offset_right = -10
	chat_layout.offset_top = 8
	chat_layout.offset_bottom = -8
	chat_window_panel.add_child(chat_layout)
	
	var chat_header = Label.new()
	chat_header.text = "SYSTEM COMMS RADIO"
	chat_header.add_theme_font_size_override("font_size", 10)
	chat_header.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0, 0.8))
	chat_layout.add_child(chat_header)
	
	chat_scroll = ScrollContainer.new()
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_layout.add_child(chat_scroll)
	
	chat_vbox = VBoxContainer.new()
	chat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_vbox)
	
	# Connect signal to print system chatter
	GlobalState.system_chatter_received.connect(add_chat_message)
	
	# Initial welcome message
	add_chat_message("SYSTEM", "Radio channels open. Encryption secure.", Color(0.0, 0.9, 0.9))

func _create_target_panel():
	target_panel = PanelContainer.new()
	add_child(target_panel)
	target_panel.anchor_left = 0.35
	target_panel.anchor_right = 0.65
	target_panel.anchor_top = 0.02
	target_panel.anchor_bottom = 0.02
	target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	target_panel.grow_vertical = Control.GROW_DIRECTION_END
	
	var margin_container = MarginContainer.new()
	target_panel.add_child(margin_container)
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	
	var vbox = VBoxContainer.new()
	margin_container.add_child(vbox)
	
	var target_info_box = HBoxContainer.new()
	target_info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(target_info_box)
	
	target_icon = TextureRect.new()
	target_icon.custom_minimum_size = Vector2(40, 40)
	target_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	target_icon.gui_input.connect(_on_target_icon_gui_input)
	target_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target_info_box.add_child(target_icon)
	
	target_label = Label.new()
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	target_label.text = "No Target Selected"
	target_info_box.add_child(target_label)
	
	target_action_box = HBoxContainer.new()
	target_action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(target_action_box)
	
	var app_btn = Button.new()
	app_btn.text = "Fly to"
	app_btn.pressed.connect(func():
		if GlobalState.player:
			GlobalState.player.set("nav_mode", "APPROACH")
			var t = GlobalState.active_target
			if t and is_instance_valid(t):
				show_target_marker(t.global_position)
	)
	target_action_box.add_child(app_btn)
	
	var orb_btn = Button.new()
	orb_btn.text = "Orbit"
	orb_btn.pressed.connect(func():
		if GlobalState.player:
			GlobalState.player.set("nav_mode", "ORBIT")
			var t = GlobalState.active_target
			if t and is_instance_valid(t):
				show_target_marker(t.global_position)
	)
	target_action_box.add_child(orb_btn)
	
	target_panel.visible = false

func _create_overview():
	overview_panel = Panel.new()
	add_child(overview_panel)
	overview_panel.anchor_left = 0.78
	overview_panel.anchor_right = 0.98
	overview_panel.anchor_top = 0.05
	overview_panel.anchor_bottom = 0.65
	overview_panel.offset_left = 0
	overview_panel.offset_right = 0
	overview_panel.offset_top = 0
	overview_panel.offset_bottom = 0
	
	var vbox = VBoxContainer.new()
	overview_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	
	# Create a dedicated resize handle on the left edge
	resize_handle = Control.new()
	resize_handle.name = "ResizeHandle"
	overview_panel.add_child(resize_handle)
	resize_handle.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	resize_handle.offset_left = 0
	resize_handle.offset_right = 8
	resize_handle.offset_top = 0
	resize_handle.offset_bottom = 0
	resize_handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	resize_handle.gui_input.connect(_on_resize_handle_input)
	
	var title_hbox = HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_hbox)
	
	# Spacer for centering title
	var title_spacer = Control.new()
	title_spacer.custom_minimum_size = Vector2(25, 0)
	title_hbox.add_child(title_spacer)
	
	var title = Label.new()
	title.text = "OVERVIEW"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_hbox.add_child(title)
	
	collapse_btn = Button.new()
	collapse_btn.text = " ▲ "
	collapse_btn.flat = true
	collapse_btn.pressed.connect(func(): set_overview_collapsed(not overview_collapsed))
	title_hbox.add_child(collapse_btn)
	
	# Create Header HBox for sorting
	var header_hbox = HBoxContainer.new()
	header_hbox.custom_minimum_size = Vector2(0, 25)
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_hbox)
	
	btn_name = Button.new()
	btn_name.text = "Name"
	btn_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_name.pressed.connect(func(): _on_header_clicked("name"))
	header_hbox.add_child(btn_name)
	
	btn_dist = Button.new()
	btn_dist.text = "Distance"
	btn_dist.custom_minimum_size = Vector2(110, 0)
	btn_dist.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_dist.pressed.connect(func(): _on_header_clicked("distance"))
	header_hbox.add_child(btn_dist)
	
	btn_type = Button.new()
	btn_type.text = "Type"
	btn_type.custom_minimum_size = Vector2(160, 0)
	btn_type.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_type.pressed.connect(func(): _on_header_clicked("type"))
	header_hbox.add_child(btn_type)
	
	var header_spacer = Control.new()
	header_spacer.custom_minimum_size = Vector2(8, 0)
	header_hbox.add_child(header_spacer)
	
	_update_header_labels()
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	overview_list = VBoxContainer.new()
	overview_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(overview_list)

func _on_header_clicked(column: String):
	if sort_column == column:
		sort_ascending = not sort_ascending
	else:
		sort_column = column
		sort_ascending = true
	_update_header_labels()
	_update_overview_distances()

func _update_header_labels():
	btn_name.text = "Name" + (" ▲" if sort_column == "name" and sort_ascending else " ▼" if sort_column == "name" else "")
	btn_dist.text = "Distance" + (" ▲" if sort_column == "distance" and sort_ascending else " ▼" if sort_column == "distance" else "")
	btn_type.text = "Type" + (" ▲" if sort_column == "type" and sort_ascending else " ▼" if sort_column == "type" else "")

func _create_dock_menu():
	dock_panel = Panel.new()
	add_child(dock_panel)
	dock_panel.anchor_left = 0.3
	dock_panel.anchor_right = 0.7
	dock_panel.anchor_top = 0.25
	dock_panel.anchor_bottom = 0.75
	dock_panel.offset_left = 0
	dock_panel.offset_right = 0
	dock_panel.offset_top = 0
	dock_panel.offset_bottom = 0

	# Dark panel background so the dock menu is readable over busy space backdrops
	var dock_style = StyleBoxFlat.new()
	dock_style.bg_color = Color(0.08, 0.08, 0.10, 0.92)
	dock_style.border_width_left = 2
	dock_style.border_width_top = 2
	dock_style.border_width_right = 2
	dock_style.border_width_bottom = 2
	dock_style.border_color = Color(0.0, 0.6, 0.6, 1.0)
	dock_style.corner_radius_top_left = 4
	dock_style.corner_radius_top_right = 4
	dock_style.corner_radius_bottom_right = 4
	dock_style.corner_radius_bottom_left = 4
	dock_panel.add_theme_stylebox_override("panel", dock_style)

	# Background image (RepairShop.png) — only shown when docked at a repair_shop.
	# Sized to fill the panel and tinted dark so the foreground buttons stay readable.
	dock_background = TextureRect.new()
	dock_background.name = "DockBackground"
	dock_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	dock_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dock_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	dock_background.modulate = Color(0.35, 0.30, 0.28, 0.65)  # Darken so buttons read on top
	dock_background.visible = false
	dock_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block button clicks
	dock_panel.add_child(dock_background)
	# Move background behind the vbox that holds the buttons
	dock_background.move_to_front = false

	var vbox = VBoxContainer.new()
	dock_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	dock_label = Label.new()
	dock_label.text = "STATION SERVICES"
	dock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dock_label)
	
	sell_btn = Button.new()
	sell_btn.text = "Sell Ore (1 SC per m³)"
	sell_btn.pressed.connect(_sell_ore)
	vbox.add_child(sell_btn)
	
	upgrade_cargo_btn = Button.new()
	upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - 100 SC"
	upgrade_cargo_btn.pressed.connect(_upgrade_cargo)
	vbox.add_child(upgrade_cargo_btn)
	
	upgrade_laser_btn = Button.new()
	upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - 150 SC"
	upgrade_laser_btn.pressed.connect(_upgrade_laser)
	vbox.add_child(upgrade_laser_btn)
	
	repair_btn = Button.new()
	repair_btn.text = "Repair Ship"
	repair_btn.pressed.connect(_repair_ship)
	vbox.add_child(repair_btn)
	
	agent_service_btn = Button.new()
	agent_service_btn.text = "Talk to Agent"
	agent_service_btn.pressed.connect(_on_talk_to_agent_pressed)
	vbox.add_child(agent_service_btn)
	
	var undock_btn = Button.new()
	undock_btn.text = "Undock Ship"
	undock_btn.pressed.connect(undock_player)
	vbox.add_child(undock_btn)
	
	dock_panel.visible = false
	
	# Construct Agent Panel
	agent_panel = Panel.new()
	add_child(agent_panel)
	agent_panel.anchor_left = 0.25
	agent_panel.anchor_right = 0.75
	agent_panel.anchor_top = 0.2
	agent_panel.anchor_bottom = 0.8
	agent_panel.offset_left = 0
	agent_panel.offset_right = 0
	agent_panel.offset_top = 0
	agent_panel.offset_bottom = 0
	agent_panel.visible = false
	
	var agent_style = StyleBoxFlat.new()
	agent_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	agent_style.border_width_left = 2
	agent_style.border_width_top = 2
	agent_style.border_width_right = 2
	agent_style.border_width_bottom = 2
	agent_style.border_color = Color(0.0, 0.8, 0.8, 1.0)
	agent_style.corner_radius_top_left = 4
	agent_style.corner_radius_top_right = 4
	agent_style.corner_radius_bottom_right = 4
	agent_style.corner_radius_bottom_left = 4
	agent_panel.add_theme_stylebox_override("panel", agent_style)
	
	var agent_hbox = HBoxContainer.new()
	agent_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	agent_hbox.offset_left = 15
	agent_hbox.offset_right = -15
	agent_hbox.offset_top = 15
	agent_hbox.offset_bottom = -15
	agent_panel.add_child(agent_hbox)
	
	# Left Side: Agent Portrait
	var portrait_vbox = VBoxContainer.new()
	portrait_vbox.custom_minimum_size = Vector2(180, 0)
	portrait_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	agent_hbox.add_child(portrait_vbox)
	
	agent_portrait = TextureRect.new()
	agent_portrait.custom_minimum_size = Vector2(180, 180)
	agent_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	agent_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_vbox.add_child(agent_portrait)
	
	var col_spacer = Control.new()
	col_spacer.custom_minimum_size = Vector2(20, 0)
	agent_hbox.add_child(col_spacer)
	
	# Right Side: Text details and choice menus
	var avbox = VBoxContainer.new()
	avbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avbox.alignment = BoxContainer.ALIGNMENT_CENTER
	agent_hbox.add_child(avbox)
	
	# Header Layout containing title, subtitle, and faction branding logo on the right
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avbox.add_child(header_hbox)
	
	var name_vbox = VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(name_vbox)
	
	agent_name_label = Label.new()
	agent_name_label.text = "BROKER KAELEN"
	agent_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	agent_name_label.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	agent_name_label.add_theme_font_size_override("font_size", 18)
	name_vbox.add_child(agent_name_label)
	
	var agent_subtitle = Label.new()
	agent_subtitle.text = "Neutral Fixer & Profit Broker"
	agent_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	agent_subtitle.add_theme_font_size_override("font_size", 11)
	agent_subtitle.modulate = Color(0.7, 0.7, 0.7)
	name_vbox.add_child(agent_subtitle)
	
	agent_client_logo = TextureRect.new()
	agent_client_logo.custom_minimum_size = Vector2(64, 64)
	agent_client_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	agent_client_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	agent_client_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_hbox.add_child(agent_client_logo)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	avbox.add_child(spacer)
	
	var dialogue_scroll = ScrollContainer.new()
	dialogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	avbox.add_child(dialogue_scroll)
	
	agent_dialogue_label = Label.new()
	agent_dialogue_label.text = "What is your business here, pilot? If it doesn't make credits, it's not my concern."
	agent_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	agent_dialogue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agent_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_scroll.add_child(agent_dialogue_label)
	
	agent_choices_container = VBoxContainer.new()
	agent_choices_container.alignment = BoxContainer.ALIGNMENT_CENTER
	avbox.add_child(agent_choices_container)
	
	agent_back_btn = Button.new()
	agent_back_btn.text = "Back to Services"
	agent_back_btn.pressed.connect(_on_agent_back_pressed)
	avbox.add_child(agent_back_btn)

func _create_context_menu():
	context_panel = Panel.new()
	add_child(context_panel)
	context_panel.custom_minimum_size = Vector2(150, 160)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 1.0) # Solid, non-translucent dark background
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.35, 0.45, 1.0) # Solid grey-blue border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	context_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	context_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	
	var action_app = Button.new()
	action_app.text = "Fly to"
	action_app.pressed.connect(func():
		if GlobalState.player:
			GlobalState.player.set("nav_mode", "APPROACH")
			var t = GlobalState.active_target
			if t and is_instance_valid(t):
				show_target_marker(t.global_position)
		context_panel.visible = false
	)
	vbox.add_child(action_app)
	
	var action_orb = Button.new()
	action_orb.text = "Orbit"
	action_orb.pressed.connect(func():
		if GlobalState.player:
			GlobalState.player.set("nav_mode", "ORBIT")
			var t = GlobalState.active_target
			if t and is_instance_valid(t):
				show_target_marker(t.global_position)
		context_panel.visible = false
	)
	vbox.add_child(action_orb)
	
	var action_act = Button.new()
	action_act.name = "ActionButton"
	context_action_btn = action_act
	action_act.text = "Mine / Attack"
	action_act.pressed.connect(func():
		var t = GlobalState.active_target
		if t and is_instance_valid(t) and GlobalState.player:
			if t.is_in_group("asteroid"):
				GlobalState.player.set("nav_mode", "MINE")
			elif t.is_in_group("station"):
				GlobalState.player.set("nav_mode", "DOCK")
			else:
				GlobalState.player.set("nav_mode", "ATTACK")
			show_target_marker(t.global_position)
		context_panel.visible = false
	)
	vbox.add_child(action_act)
	
	var action_close = Button.new()
	action_close.text = "Cancel"
	action_close.pressed.connect(func(): context_panel.visible = false)
	vbox.add_child(action_close)
	
	context_panel.visible = false

func _create_pause_menu():
	pause_panel = Panel.new()
	add_child(pause_panel)
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.offset_left = 0
	pause_panel.offset_right = 0
	pause_panel.offset_top = 0
	pause_panel.offset_bottom = 0
	
	var vbox = VBoxContainer.new()
	pause_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var title = Label.new()
	title.text = "GAME PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var bindings = Label.new()
	bindings.text = "KEY BINDINGS / COMMANDS:\n" + \
		"  - Left Click: Select target in space or overview\n" + \
		"  - Double Left Click: Fly to position in space\n" + \
		"  - Hold RMB + Drag: Rotate camera pivot\n" + \
		"  - Scroll Wheel: Zoom camera in / out\n" + \
		"  - Q: Engage APPROACH autopilot\n" + \
		"  - W: Engage ORBIT autopilot\n" + \
		"  - E: Activate Action (MINE asteroid or ATTACK hostile)\n" + \
		"  - ESC: Pause / Resume game"
	bindings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(bindings)
	
	var resume_btn = Button.new()
	resume_btn.text = "Resume Game"
	resume_btn.pressed.connect(func(): GlobalState.paused = false)
	vbox.add_child(resume_btn)
	
	var restart_btn = Button.new()
	restart_btn.text = "Restart Game"
	restart_btn.pressed.connect(_restart_game)

	vbox.add_child(restart_btn)
	
	var quit_btn = Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)
	
	# Spacing before volume controls
	var vol_spacer = Control.new()
	vol_spacer.custom_minimum_size = Vector2(0, 25)
	vbox.add_child(vol_spacer)
	
	# Volume Control panel container
	var vol_panel = PanelContainer.new()
	vol_panel.custom_minimum_size = Vector2(450, 0)
	vol_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(vol_panel)
	
	# Premium dark theme styling for the panel
	var vol_style = StyleBoxFlat.new()
	vol_style.bg_color = Color(0.08, 0.08, 0.12, 0.75) # Translucent dark deep blue-gray
	vol_style.border_width_left = 1
	vol_style.border_width_top = 1
	vol_style.border_width_right = 1
	vol_style.border_width_bottom = 1
	vol_style.border_color = Color(0.0, 0.85, 1.0, 0.35) # Soft glowing cyan border outline
	vol_style.corner_radius_top_left = 8
	vol_style.corner_radius_top_right = 8
	vol_style.corner_radius_bottom_right = 8
	vol_style.corner_radius_bottom_left = 8
	vol_style.content_margin_left = 24
	vol_style.content_margin_right = 24
	vol_style.content_margin_top = 16
	vol_style.content_margin_bottom = 16
	vol_panel.add_theme_stylebox_override("panel", vol_style)
	
	var vol_vbox = VBoxContainer.new()
	vol_panel.add_child(vol_vbox)
	
	# Volume Header
	var vol_title = Label.new()
	vol_title.text = "VOLUME SETTINGS"
	vol_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vol_title.add_theme_font_size_override("font_size", 14)
	vol_title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0, 1.0)) # Bright cyan accent
	vol_vbox.add_child(vol_title)
	
	# Header spacer
	var vol_header_spacer = Control.new()
	vol_header_spacer.custom_minimum_size = Vector2(0, 12)
	vol_vbox.add_child(vol_header_spacer)
	
	# 1. Music Volume Row
	var music_hbox = HBoxContainer.new()
	vol_vbox.add_child(music_hbox)
	
	var music_lbl = Label.new()
	music_lbl.text = "Music"
	music_lbl.custom_minimum_size = Vector2(100, 0)
	music_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	music_hbox.add_child(music_lbl)
	
	var music_slider = HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.value = AudioManager.get_music_volume()
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_hbox.add_child(music_slider)
	
	var music_val = Label.new()
	music_val.text = str(int(music_slider.value * 100)) + "%"
	music_val.custom_minimum_size = Vector2(50, 0)
	music_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	music_hbox.add_child(music_val)
	
	music_slider.value_changed.connect(func(val):
		AudioManager.set_music_volume(val)
		music_val.text = str(int(val * 100)) + "%"
	)
	
	# Row spacer
	var row_spacer = Control.new()
	row_spacer.custom_minimum_size = Vector2(0, 8)
	vol_vbox.add_child(row_spacer)
	
	# 2. SFX Volume Row
	var sfx_hbox = HBoxContainer.new()
	vol_vbox.add_child(sfx_hbox)
	
	var sfx_lbl = Label.new()
	sfx_lbl.text = "Game Sound"
	sfx_lbl.custom_minimum_size = Vector2(100, 0)
	sfx_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sfx_hbox.add_child(sfx_lbl)
	
	var sfx_slider = HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.01
	sfx_slider.value = AudioManager.get_sfx_volume()
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sfx_hbox.add_child(sfx_slider)
	
	var sfx_val = Label.new()
	sfx_val.text = str(int(sfx_slider.value * 100)) + "%"
	sfx_val.custom_minimum_size = Vector2(50, 0)
	sfx_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sfx_hbox.add_child(sfx_val)
	
	sfx_slider.value_changed.connect(func(val):
		AudioManager.set_sfx_volume(val)
		sfx_val.text = str(int(val * 100)) + "%"
	)
	
	pause_panel.visible = false

func _create_death_screen():
	death_panel = Panel.new()
	add_child(death_panel)
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.offset_left = 0
	death_panel.offset_right = 0
	death_panel.offset_top = 0
	death_panel.offset_bottom = 0
	
	var vbox = VBoxContainer.new()
	death_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var msg = Label.new()
	msg.text = "SHIP DESTROYED"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 36)
	msg.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	vbox.add_child(msg)
	
	var sub = Label.new()
	sub.text = "Your ship has been reduced to wreckage."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(sub)
	
	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(btn_spacer)
	
	var restart_btn = Button.new()
	restart_btn.text = "Restart Game"
	restart_btn.custom_minimum_size = Vector2(220, 0)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(_restart_game)

	vbox.add_child(restart_btn)
	
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(gap)
	
	var quit_btn = Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.custom_minimum_size = Vector2(220, 0)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)
	
	death_panel.visible = false

func _restart_game():
	# Reset all autoload state BEFORE reloading — prevents dangling callbacks
	# (e.g. LLMInterface firing into a freed UIManager) from crashing the new session
	LLMInterface.reset_for_restart()
	QuestManager.reset_for_restart()
	GlobalState.reset_for_restart()
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause_game"):
		if loading_panel and is_instance_valid(loading_panel):
			return
		GlobalState.paused = not GlobalState.paused


# Overview list population
func update_overview_list(entities: Array):
	# Clear old list
	for child in overview_list.get_children():
		child.queue_free()
		
	var filtered_entities = entities
	if overview_collapsed:
		filtered_entities = []
		var active = GlobalState.active_target
		if active and is_instance_valid(active) and active in entities:
			filtered_entities.append(active)
		
	for entity in filtered_entities:
		if entity and is_instance_valid(entity) and entity != GlobalState.player:
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 30)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(func(): GlobalState.active_target = entity)
			btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
					btn.accept_event()
					GlobalState.active_target = entity
					show_context_menu(entity)
			)
			overview_list.add_child(btn)
			
			# HBox inside the button for spreadsheet column layout
			var hbox = HBoxContainer.new()
			btn.add_child(hbox)
			hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			hbox.offset_left = 0
			hbox.offset_right = 0
			hbox.offset_top = 0
			hbox.offset_bottom = 0
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var name_lbl = Label.new()
			var label_text = entity.get("display_name") if entity.get("display_name") else entity.name
			name_lbl.text = "  " + label_text # Add a little padding space
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_lbl.clip_text = true
			hbox.add_child(name_lbl)
			
			var dist_lbl = Label.new()
			dist_lbl.text = "  0m"
			dist_lbl.custom_minimum_size = Vector2(110, 0)
			dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			dist_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(dist_lbl)
			
			var type_lbl = Label.new()
			var type_str = "Celestial"
			if entity.is_in_group("asteroid"):
				type_str = "Asteroid"
			elif entity.is_in_group("station"):
				# Outposts show as "Outpost" so the player can tell them apart
				# from the main system space station. station_type defaults to
				# "full_service" on Station.gd, so unspecified stations stay as
				# "Space Station".
				var stype = entity.get("station_type") if entity.get("station_type") else "full_service"
				if stype == "outpost":
					type_str = "Outpost"
				else:
					type_str = "Space Station"
			elif entity.is_in_group("ship"):
				var ship_name_upper = entity.name.to_upper()
				var faction_str = entity.get("faction")
				var faction_upper = faction_str.to_upper() if faction_str else ""
				# Derive ship class from its name — already contains Patrol/Raider/Sentinel etc.
				if "PATROL" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Patrol"
				elif "RAIDER" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Raider"
				elif "SENTINEL" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Sentinel"
				elif "HAULER" in ship_name_upper or "SALVAGER" in ship_name_upper:
					type_str = "Independent Hauler"
				elif "INTERCEPTOR" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Interceptor"
				elif "GUNSHIP" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Gunship"
				else:
					type_str = faction_upper.capitalize() + " Combat Vessel"
			elif entity.is_in_group("wreckage"):
				type_str = "Wreckage"
			
			type_lbl.text = "  " + type_str
			type_lbl.custom_minimum_size = Vector2(160, 0)
			type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			type_lbl.clip_text = true
			hbox.add_child(type_lbl)
			
			# Row text colour by entity class
			# Green = dockable (Space Station / Outpost and future dockables)
			# Blue  = celestial bodies (planets, gas giants, etc.)
			var row_color: Color
			if type_str == "Space Station" or type_str == "Outpost":
				row_color = Color(0.25, 0.95, 0.45)   # Bright docking green
			elif type_str == "Celestial":
				row_color = Color(0.35, 0.65, 1.0)    # Soft celestial blue
			else:
				row_color = Color(1.0, 1.0, 1.0)      # Default white for ships, wreckage etc.
			if row_color != Color(1.0, 1.0, 1.0):
				name_lbl.add_theme_color_override("font_color", row_color)
				dist_lbl.add_theme_color_override("font_color", row_color)
				type_lbl.add_theme_color_override("font_color", row_color)
			
			# Meta parameters for sorting and updating
			btn.set_meta("entity_ref", entity)
			btn.set_meta("entity_name", entity.name)
			btn.set_meta("type_str", type_str)
			btn.set_meta("distance_val", 0.0) # Updated dynamically in _update_overview_distances
			btn.set_meta("dist_label_ref", dist_lbl)
			btn.set_meta("name_label_ref", name_lbl)


func _update_overview_distances(delta: float = 999.0):
	if not GlobalState.player or not is_instance_valid(GlobalState.player): return
	var p_pos = GlobalState.player.global_position
	
	# Check if any NPC ship is targeting the player
	var player_targeted = false
	for entity in GlobalState.active_system_entities:
		if entity and is_instance_valid(entity) and not entity.get("destroyed"):
			if entity.is_in_group("ship") and entity.get("target") == GlobalState.player:
				player_targeted = true
				break
				
	if player_targeted and overview_collapsed:
		set_overview_collapsed(false)
		
	# Update all distances first
	for btn in overview_list.get_children():
		if btn is Button:
			var entity = btn.get_meta("entity_ref")
			if entity and is_instance_valid(entity):
				var dist = p_pos.distance_to(entity.global_position)
				btn.set_meta("distance_val", dist)
				var dist_lbl = btn.get_meta("dist_label_ref")
				if is_instance_valid(dist_lbl):
					dist_lbl.text = "  " + str(int(dist)) + "m"
				
				# Update label color if attacking player
				var name_lbl = btn.get_meta("name_label_ref")
				if is_instance_valid(name_lbl):
					if entity.is_in_group("ship") and entity.get("target") == GlobalState.player:
						name_lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
					else:
						name_lbl.remove_theme_color_override("font_color")
						
				# Highlight selected object in overview spreadsheet
				if GlobalState.active_target == entity:
					btn.self_modulate = Color(1.0, 1.0, 1.0, 1.0) # Reset modulate to avoid tint conflicts
					btn.add_theme_stylebox_override("normal", selected_row_style)
					btn.add_theme_stylebox_override("hover", selected_row_style)
					btn.add_theme_stylebox_override("pressed", selected_row_style)
					btn.add_theme_stylebox_override("focus", selected_row_style)
				else:
					btn.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
					btn.remove_theme_stylebox_override("normal")
					btn.remove_theme_stylebox_override("hover")
					btn.remove_theme_stylebox_override("pressed")
					btn.remove_theme_stylebox_override("focus")
			else:
				btn.queue_free()
				
	# Periodically sort the children list to prevent layout thrashing
	sort_timer += delta
	if sort_timer >= SORT_INTERVAL:
		sort_timer = 0.0
		_sort_overview_list()

func _sort_overview_list():
	var children = overview_list.get_children()
	children.sort_custom(func(a, b):
		if sort_column == "name":
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			if name_a != name_b:
				return name_a < name_b if sort_ascending else name_a > name_b
			return a.get_instance_id() < b.get_instance_id()
		elif sort_column == "type":
			var type_a = a.get_meta("type_str").to_lower()
			var type_b = b.get_meta("type_str").to_lower()
			if type_a != type_b:
				return type_a < type_b if sort_ascending else type_a > type_b
			# Tie breaker: sort by name, then instance ID
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			if name_a != name_b:
				return name_a < name_b
			return a.get_instance_id() < b.get_instance_id()
		else: # distance
			var dist_a = a.get_meta("distance_val")
			var dist_b = b.get_meta("distance_val")
			if abs(dist_a - dist_b) > 0.001:
				return dist_a < dist_b if sort_ascending else dist_a > dist_b
			# Tie breaker: sort by name, then instance ID
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			if name_a != name_b:
				return name_a < name_b
			return a.get_instance_id() < b.get_instance_id()
	)
	
	# Apply sorted order
	for i in range(children.size()):
		overview_list.move_child(children[i], i)

# Target signal callbacks
func _on_target_changed(new_target: Node3D):
	if new_target and is_instance_valid(new_target):
		target_panel.visible = true
		var type_str = "Object"
		var icon_index = 0 # Default to ship icon
		
		if new_target.is_in_group("asteroid"):
			type_str = "Asteroid"
			icon_index = 1
		elif new_target.is_in_group("station"):
			type_str = "Station"
			icon_index = 2
		elif new_target.is_in_group("ship"):
			type_str = "Hostile NPCShip"
			icon_index = 0
		elif new_target.is_in_group("wreckage"):
			type_str = "Wreckage"
			icon_index = 4
		elif new_target.name == "GasGiant" or new_target.name == "RockyPlanet":
			type_str = "Planet"
			icon_index = 3
			
		target_label.text = new_target.name + " [" + type_str + "]"
		
		# Set target icon
		if target_icon and icons_sheet:
			var atlas = AtlasTexture.new()
			atlas.atlas = icons_sheet
			
			var col = icon_index % 4
			var row = icon_index / 4
			atlas.region = Rect2(col * 384, row * 512, 384, 512)
			target_icon.texture = atlas
			target_icon.visible = true
	else:
		target_panel.visible = false
		target_label.text = "No Target Selected"
		if target_icon:
			target_icon.visible = false
		
	if overview_collapsed:
		refresh_overview()

func _on_target_icon_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			show_context_menu(t)

func _on_credits_changed(new_credits: int):
	if credits_label:
		credits_label.text = "Credits: " + str(new_credits) + " SC"

func _on_cargo_changed(new_cargo: float):
	if cargo_label and cargo_bar:
		cargo_label.text = "Cargo: " + str(int(new_cargo)) + " / " + str(int(GlobalState.cargo_max)) + " m³"
		cargo_bar.max_value = GlobalState.cargo_max
		cargo_bar.value = new_cargo
		
		# Play audio warning when cargo reaches max capacity
		if new_cargo >= GlobalState.cargo_max:
			AudioManager.play_cargo_full()
			
		_update_quest_tracker()

func _on_pause_changed(is_paused: bool):
	if pause_panel:
		if is_paused and loading_panel and is_instance_valid(loading_panel):
			pause_panel.visible = false
		else:
			pause_panel.visible = is_paused
			if is_paused:
				move_child(pause_panel, -1)

# Station services methods
func toggle_dock_menu(station: Node3D):
	current_station = station
	if dock_panel.visible or agent_panel.visible:
		dock_panel.visible = false
		agent_panel.visible = false
		if GlobalState.player:
			GlobalState.player.is_docked = false
	else:
		dock_panel.visible = true
		# Collapse overview while docked — station UI takes priority
		set_overview_collapsed(true)
		
		# Determine station capabilities from its type
		var stype = station.get("station_type") if station else "full_service"
		var is_outpost = (stype == "outpost")
		var is_repair_shop = (stype == "repair_shop")
		var sname = station.get("display_name") if station and station.get("display_name") else ""

		# Dock label depends on station kind
		if is_outpost:
			dock_label.text = sname if sname != "" else "OUTPOST SERVICES"
		elif is_repair_shop:
			dock_label.text = sname if sname != "" else "GREASE MONKEYS"
		else:
			dock_label.text = "STATION SERVICES"

		# Show the themed background only at the repair shop. The image is
		# loaded lazily so we don't pay the 2MB texture cost on every boot.
		if dock_background:
			if is_repair_shop:
				if dock_background.texture == null:
					dock_background.texture = load("res://assets/RepairShop.png")
				dock_background.visible = true
			else:
				dock_background.visible = false

		# Service button visibility per station type:
		#   - main station:        sell ore, talk to agent
		#   - repair shop:         repair, upgrade cargo, upgrade laser
		#   - outpost:             (none yet — outposts are visually-present docks with no services)
		sell_btn.visible = not is_outpost and not is_repair_shop
		upgrade_cargo_btn.visible = is_repair_shop
		upgrade_laser_btn.visible = is_repair_shop
		repair_btn.visible = is_repair_shop
		agent_service_btn.visible = not is_outpost and not is_repair_shop

		# Update button labels regardless of visibility
		upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - 100 SC"
		upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - 150 SC"
		_update_repair_button()

		if GlobalState.player:
			GlobalState.player.is_docked = true
			GlobalState.player.velocity = Vector3.ZERO

		# Only pre-cache quests when at the main full-service station
		if not is_outpost and not is_repair_shop and not QuestManager.is_quest_active() and cached_quest_data.is_empty():
			print("[TRACE] [UIManager] Player docked. Pre-caching agent quest in the background.")
			QuestManager.request_new_quest("neutral", _on_background_quest_generated)


func undock_player():
	dock_panel.visible = false
	agent_panel.visible = false
	current_station = null
	# Restore full overview when heading back into space
	set_overview_collapsed(false)
	
	# Stop voice dialogue audio if playing
	TTSInterface.play_dialogue_audio("")
	
	
	# Give player a slight push away from station
	if GlobalState.player:
		GlobalState.player.global_position += Vector3(0, 0, -15.0)
		GlobalState.player.is_docked = false
		GlobalState.player.nav_mode = "MANUAL"

func _sell_ore():
	if GlobalState.cargo > 0.0:
		var earnings = int(GlobalState.cargo)
		GlobalState.player_credits += earnings
		GlobalState.cargo = 0.0
		_update_repair_button()
		AudioManager.play_sell_ore()

func _upgrade_cargo():
	if GlobalState.player_credits >= 100:
		GlobalState.player_credits -= 100
		GlobalState.cargo_max += 25.0
		_on_cargo_changed(GlobalState.cargo) # Update HUD bar
		upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - Purchased!"
		_update_repair_button()

func _upgrade_laser():
	if GlobalState.player_credits >= 150:
		GlobalState.player_credits -= 150
		GlobalState.mining_yield += 1.0
		upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - Purchased!"
		_update_repair_button()

func show_context_menu(entity: Node3D):
	if not entity or not is_instance_valid(entity): return
	context_panel.visible = true
	
	var mouse_pos = get_global_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var menu_size = context_panel.size
	if menu_size == Vector2.ZERO:
		menu_size = context_panel.custom_minimum_size
		
	var max_x = viewport_size.x - menu_size.x
	var max_y = viewport_size.y - menu_size.y
	mouse_pos.x = clamp(mouse_pos.x, 0.0, max_x)
	mouse_pos.y = clamp(mouse_pos.y, 0.0, max_y)
	
	context_panel.global_position = mouse_pos
	
	# Adjust dynamic button text based on selection type
	if context_action_btn:
		if entity.is_in_group("asteroid"):
			context_action_btn.text = "Mine Asteroid"
			context_action_btn.visible = true
		elif entity.is_in_group("station"):
			context_action_btn.text = "Dock at Station"
			context_action_btn.visible = true
		elif entity.is_in_group("ship"):
			context_action_btn.text = "Attack Hostile"
			context_action_btn.visible = true
		else:
			context_action_btn.visible = false

func show_death_screen():
	death_panel.visible = true

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			is_resizing = false

func _on_resize_handle_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_resizing = true
			drag_start_mouse_x = get_viewport().get_mouse_position().x
			drag_start_anchor_left = overview_panel.anchor_left
		else:
			is_resizing = false
	elif event is InputEventMouseMotion and is_resizing:
		var mouse_x = get_viewport().get_mouse_position().x
		var delta_x = mouse_x - drag_start_mouse_x
		var viewport_w = get_viewport().get_visible_rect().size.x
		if viewport_w > 0:
			var target_anchor_left = drag_start_anchor_left + (delta_x / viewport_w)
			
			# Keep width between 250px and 800px
			var right_pixel = overview_panel.anchor_right * viewport_w
			var min_left_pixel = right_pixel - 800.0
			var max_left_pixel = right_pixel - 250.0
			
			var target_left_pixel = target_anchor_left * viewport_w
			target_left_pixel = clamp(target_left_pixel, min_left_pixel, max_left_pixel)
			
			overview_panel.anchor_left = target_left_pixel / viewport_w

func show_target_marker(pos: Vector3):
	marker_pos_3d = pos
	marker_active = true
	marker_timer = 2.0 # Keep visible for 2 seconds to orient the player
	if target_marker:
		target_marker.visible = true
		target_marker.queue_redraw()

func _update_target_marker_position():
	if not target_marker: return
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		marker_active = false
		target_marker.visible = false
		return
		
	var cam = GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not cam or not is_instance_valid(cam): return
	
	var pos_3d = marker_pos_3d
	var screen_pos = cam.unproject_position(pos_3d)
	var is_behind = cam.is_position_behind(pos_3d)
	
	var viewport_size = get_viewport().get_visible_rect().size
	var margin = 35.0
	
	if is_behind:
		# Mirror coordinates to point to the actual offscreen direction
		var center = viewport_size / 2.0
		var dir = (screen_pos - center).normalized()
		if dir.length() < 0.1:
			dir = Vector2.DOWN
		screen_pos = center - dir * (center.length() - margin)
		
	# Clamp marker position to screen bounds
	screen_pos.x = clamp(screen_pos.x, margin, viewport_size.x - margin)
	screen_pos.y = clamp(screen_pos.y, margin, viewport_size.y - margin)
	
	target_marker.global_position = screen_pos
	target_marker.queue_redraw()

func _on_target_marker_draw():
	if not marker_active: return
	# Draw futuristic green HUD target bracket
	target_marker.draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color.GREEN, 2.5, true)
	target_marker.draw_circle(Vector2.ZERO, 3.0, Color.GREEN)
	target_marker.draw_line(Vector2(-22, 0), Vector2(-16, 0), Color.GREEN, 2.0)
	target_marker.draw_line(Vector2(16, 0), Vector2(22, 0), Color.GREEN, 2.0)
	target_marker.draw_line(Vector2(0, -22), Vector2(0, -16), Color.GREEN, 2.0)
	target_marker.draw_line(Vector2(0, 16), Vector2(0, 22), Color.GREEN, 2.0)

func _update_selection_marker_position():
	if not selection_marker: return
	var target = GlobalState.active_target
	if not target or not is_instance_valid(target) or target.get("destroyed"):
		selection_marker.visible = false
		return
		
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		selection_marker.visible = false
		return
		
	var cam = GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not cam or not is_instance_valid(cam):
		selection_marker.visible = false
		return
		
	var is_behind = cam.is_position_behind(target.global_position)
	if is_behind:
		selection_marker.visible = false
		return
		
	var screen_pos = cam.unproject_position(target.global_position)
	selection_marker.global_position = screen_pos
	selection_marker.visible = true
	selection_marker.queue_redraw()

func _on_selection_marker_draw():
	var target = GlobalState.active_target
	if not target or not is_instance_valid(target) or target.get("destroyed"):
		return
		
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		return
		
	var cam = GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not cam or not is_instance_valid(cam):
		return
		
	var radius_3d = 5.0
	if target.is_in_group("asteroid"):
		radius_3d = 5.0 * target.scale.x
	elif target.name == "GasGiant":
		radius_3d = 600.0
	elif target.name == "RockyPlanet":
		radius_3d = 250.0
	elif target.is_in_group("station"):
		radius_3d = 22.0 * target.scale.x
	elif target.is_in_group("ship"):
		radius_3d = 4.0
	elif target.is_in_group("wreckage"):
		radius_3d = 4.0 * target.scale.x
		
	var screen_center = Vector2.ZERO
	var edge_pos_3d = target.global_position + cam.global_transform.basis.x * radius_3d
	var edge_pos_2d = cam.unproject_position(edge_pos_3d)
	var screen_pos = cam.unproject_position(target.global_position)
	
	var screen_radius = screen_pos.distance_to(edge_pos_2d)
	screen_radius = max(screen_radius, 22.0)
	screen_radius = screen_radius * 1.08 + 4.0
	
	# Raycast to check if the target is behind a solar body (GasGiant or RockyPlanet)
	var blocked = false
	var space_state = target.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(cam.global_position, target.global_position)
	query.exclude = [GlobalState.player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var ray_res = space_state.intersect_ray(query)
	if ray_res and is_instance_valid(ray_res.collider):
		var collider = ray_res.collider
		if collider != target and (collider.name == "GasGiant" or collider.name == "RockyPlanet"):
			blocked = true
			
	var marker_color = Color(0.55, 0.55, 0.55, 0.75) if blocked else Color(0.0, 1.0, 0.0, 0.75)
	
	# Draw target brackets around the object
	selection_marker.draw_arc(screen_center, screen_radius, 0.0, TAU, 64, marker_color, 1.5, true)
	
	# Add ticks/notches
	var tick_len = 6.0
	var angles = [0.0, PI/2.0, PI, 3.0*PI/2.0]
	for angle in angles:
		var dir = Vector2(cos(angle), sin(angle))
		var start = dir * screen_radius
		var end = dir * (screen_radius + tick_len)
		selection_marker.draw_line(start, end, marker_color, 2.0, true)

func _update_hud_health():
	if not hud_panel: return
	var p = GlobalState.player
	var hp_label = hud_panel.find_child("HPLabel", true, false) as Label
	var hp_bar = hud_panel.find_child("HPBar", true, false) as ProgressBar
	
	if p and is_instance_valid(p):
		var hp = p.get("health")
		var max_hp = p.get("max_health")
		if hp != null and max_hp != null:
			if hp_label:
				hp_label.text = "HP: " + str(int(hp)) + " / " + str(int(max_hp))
			if hp_bar:
				hp_bar.max_value = max_hp
				hp_bar.value = hp
				
				# Dynamically style health bar color matching drone state!
				var fill_style = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if fill_style:
					var hp_pct = hp / max_hp
					if hp_pct <= 0.3:
						fill_style.bg_color = Color(0.9, 0.2, 0.2, 1.0) # Red
					elif hp_pct <= 0.6:
						fill_style.bg_color = Color(0.9, 0.8, 0.2, 1.0) # Yellow
					else:
						fill_style.bg_color = Color(0.2, 0.9, 0.4, 1.0) # Green

func _update_hud_reputations():
	if not hud_panel: return
	var rep_label = hud_panel.find_child("RepLabel", true, false) as Label
	if rep_label:
		var zen = int(GlobalState.reputations.get("zenith", 0.0))
		var aur = int(GlobalState.reputations.get("aurelia", 0.0))
		var van = int(GlobalState.reputations.get("vanguard", 0.0))
		rep_label.text = "Rep: ZEN %d | AUR %d | VAN %d" % [zen, aur, van]

func refresh_overview():
	var entities: Array = []
	var main = get_tree().current_scene
	if not main: return
	
	# Add ALL stations (main + outposts) by group — never hardcode node names
	for node in get_tree().get_nodes_in_group("station"):
		if is_instance_valid(node):
			entities.append(node)
	var gas_giant = main.get_node_or_null("GasGiant")
	if gas_giant: entities.append(gas_giant)
	var rocky_planet = main.get_node_or_null("RockyPlanet")
	if rocky_planet: entities.append(rocky_planet)

	
	# Add Asteroids
	for node in get_tree().get_nodes_in_group("asteroid"):
		entities.append(node)
		
	# Add NPC Ships
	for node in get_tree().get_nodes_in_group("ship"):
		if node != GlobalState.player and is_instance_valid(node) and not node.get("destroyed"):
			entities.append(node)
			
	# Add Wreckage
	for node in get_tree().get_nodes_in_group("wreckage"):
		if is_instance_valid(node):
			entities.append(node)
			
	update_overview_list(entities)

func show_hud_warning(text: String):
	var warning_label = Label.new()
	warning_label.text = text
	warning_label.modulate = Color(1.0, 0.2, 0.2)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	warning_label.add_theme_font_size_override("font_size", 22)
	warning_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	warning_label.add_theme_constant_override("shadow_outline_size", 4)
	
	warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	warning_label.offset_left = -300
	warning_label.offset_right = 300
	warning_label.offset_top = 100
	warning_label.offset_bottom = 150
	
	add_child(warning_label)
	
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(warning_label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(warning_label.queue_free)

func _update_repair_button():
	if not repair_btn: return
	var p = GlobalState.player
	if not p or not is_instance_valid(p) or p.get("destroyed"):
		repair_btn.text = "Repair Ship (No ship detected)"
		repair_btn.disabled = true
		return
		
	var hp = p.get("health")
	var max_hp = p.get("max_health")
	var missing_hp = max_hp - hp
	
	if missing_hp <= 0.001:
		repair_btn.text = "Repair Ship (Fully Repaired)"
		repair_btn.disabled = true
	else:
		var cost_per_hp = 2.0
		var total_cost = int(missing_hp * cost_per_hp)
		
		if GlobalState.player_credits >= total_cost:
			repair_btn.text = "Repair Ship (Full Heal: %d HP) - %d SC" % [int(missing_hp), total_cost]
			repair_btn.disabled = false
		else:
			# Player cannot afford full heal
			var affordable_hp = int(GlobalState.player_credits / cost_per_hp)
			if affordable_hp > 0:
				repair_btn.text = "Repair Ship (Partial Heal: %d HP) - %d SC" % [affordable_hp, GlobalState.player_credits]
				repair_btn.disabled = false
			else:
				repair_btn.text = "Repair Ship (Insufficient Credits) - Need %d SC" % [total_cost]
				repair_btn.disabled = true

func _repair_ship():
	var p = GlobalState.player
	if not p or not is_instance_valid(p) or p.get("destroyed"):
		return
		
	var hp = p.get("health")
	var max_hp = p.get("max_health")
	var missing_hp = max_hp - hp
	
	if missing_hp <= 0.001:
		return
		
	var cost_per_hp = 2.0
	var total_cost = int(missing_hp * cost_per_hp)
	
	var repaired = false
	if GlobalState.player_credits >= total_cost:
		# Full repair
		GlobalState.player_credits -= total_cost
		p.set("health", max_hp)
		repaired = true
	else:
		# Partial repair
		var affordable_hp = int(GlobalState.player_credits / cost_per_hp)
		if affordable_hp > 0:
			var cost_paid = int(affordable_hp * cost_per_hp)
			GlobalState.player_credits -= cost_paid
			p.set("health", hp + affordable_hp)
			repaired = true
			
	if repaired:
		AudioManager.play_repair()
			
	# Update HUD and button state
	_update_hud_health()
	_update_repair_button()

func set_overview_collapsed(collapsed: bool):
	if overview_collapsed == collapsed: return
	overview_collapsed = collapsed
	
	if collapse_btn:
		collapse_btn.text = " ▼ " if overview_collapsed else " ▲ "
		
	if overview_collapsed:
		overview_panel.anchor_bottom = 0.18
	else:
		overview_panel.anchor_bottom = 0.65
		
	refresh_overview()

# Agent dialogue screen & Quest tracker HUD interactions
func _on_talk_to_agent_pressed():
	TTSInterface.start_interaction("Talk to Agent")
	dock_panel.visible = false
	agent_panel.visible = true
	
	# Clear previous choice buttons
	for child in agent_choices_container.get_children():
		child.queue_free()
		
	if QuestManager.is_quest_active():
		var q = QuestManager.active_quest
		agent_name_label.text = q["agent_name"].to_upper()
		
		# Update portrait and client logo
		_update_agent_portrait(q.get("faction", "neutral"))
		
		var type_str = "Clear Hostiles" if q["objective_type"] == "KILL_SHIPS" else "Deliver Resources"
		agent_dialogue_label.text = "Active Contract: " + q["title"] + " (" + type_str + ")\n\n" + \
			"Briefing: " + q["dialogue"] + "\n\n" + \
			"Response choice accepted: '" + q["choice_text_selected"] + "'\n" + \
			"Agent feedback: '" + q["agent_response"] + "'"
			
		agent_back_btn.visible = true
		
		# Create Complete button (enabled if objectives met)
		var comp_btn = Button.new()
		comp_btn.text = "Hand In Contract"
		comp_btn.disabled = not QuestManager.is_quest_completed()
		comp_btn.pressed.connect(_on_agent_complete_pressed)
		agent_choices_container.add_child(comp_btn)
		
		# Partial shipment button — ore quests only, when player has cargo but isn't done yet
		if q["objective_type"] == "DELIVER_ORE" and GlobalState.cargo > 0.5 and not QuestManager.is_quest_completed():
			var banked = q.get("partial_delivered", 0.0)
			var remaining = q["amount_required"] - banked
			var deliverable = min(GlobalState.cargo, remaining)
			var partial_btn = Button.new()
			partial_btn.text = "Drop Off Partial Shipment (%.0f m³)" % deliverable
			partial_btn.pressed.connect(func(): _on_partial_delivery_pressed(deliverable))
			agent_choices_container.add_child(partial_btn)
		
		# Create Abandon button
		var abn_btn = Button.new()
		abn_btn.text = "Abandon Contract"
		abn_btn.pressed.connect(_on_agent_abandon_pressed)
		agent_choices_container.add_child(abn_btn)

	else:
		_refresh_agent_quest_board()

func _refresh_agent_quest_board():
	agent_name_label.text = "BROKER KAELEN"
	_update_agent_portrait("neutral")
	
	if not cached_quest_data.is_empty():
		# We already have a pre-cached quest! Show it immediately
		print("[TRACE] [UIManager] Pre-cached quest found. Loading board instantly.")
		_on_quest_generated_received(cached_quest_data, cached_quest_is_fallback)
	else:
		# Still loading or not started yet
		print("[TRACE] [UIManager] No pre-cached quest ready. Waiting for background generator...")
		agent_dialogue_label.text = "Broker Kaelen is checking client contract requests..."
		agent_back_btn.visible = false
		is_waiting_for_agent_board = true
		
		# If the background generator hasn't started yet, trigger it now.
		if not LLMInterface.is_waiting:
			QuestManager.request_new_quest("neutral", _on_background_quest_generated)

func _on_background_quest_generated(quest_data: Dictionary, is_fallback: bool):
	cached_quest_data = quest_data
	cached_quest_is_fallback = is_fallback
	cached_unique_intro = ""  # Reset for new quest — old intro no longer applies
	print("[TRACE] [UIManager] Background quest generated. Faction: ", quest_data.get("faction", "neutral"), " is_fallback: ", is_fallback)
	
	if not quest_data.is_empty():
		# Pre-cache main briefing TTS
		var dialogue = quest_data.get("dialogue", "")
		if dialogue != "":
			TTSInterface.cache_dialogue_audio(dialogue, quest_data.get("faction", "neutral"))
			
		# Pre-cache choice response TTS
		var choices = quest_data.get("choices", [])
		for choice in choices:
			var response = choice.get("consequence", {}).get("dialogue_response", "")
			if response != "":
				TTSInterface.cache_dialogue_audio(response, quest_data.get("faction", "neutral"))
		
		# Fire-and-forget LLM call for Kaelen's unique handoff intro. Runs in
		# the background while the player is still docking / loading. If it
		# doesn't return in time, _on_quest_generated_received falls back to
		# the canned 5-line array per agent. Skip in fallback mode — there's
		# no LLM to talk to.
		if not is_fallback:
			var agent_name = quest_data.get("agent_name", "Broker Kaelen")
			var faction = quest_data.get("faction", "neutral")
			var agent_history = QuestManager.filter_history_for_agent(agent_name, faction)
			LLMInterface.request_kaelen_intro(quest_data, agent_history, func(unique_line: String):
				if unique_line.strip_edges() == "":
					print("[TRACE] [UIManager] No unique intro available — will fall back to canned handoff.")
					cached_unique_intro = ""
					return
				cached_unique_intro = unique_line
				print("[TRACE] [UIManager] Cached unique Kaelen intro: ", unique_line.left(60), "...")
				# Pre-cache the TTS so playback is instant when the handoff fires
				TTSInterface.cache_dialogue_audio(unique_line, "neutral")
			)
				
	# Only push to agent board UI if the player is actually waiting for it
	# AND no quest is currently active (avoid replacing UI mid-mission)
	if is_waiting_for_agent_board and not QuestManager.is_quest_active():
		is_waiting_for_agent_board = false
		_on_quest_generated_received(cached_quest_data, cached_quest_is_fallback)
		
	# If loading panel is still visible, wait for TTS cache completion
	if loading_panel and is_instance_valid(loading_panel):
		TTSInterface.cache_queue_completed.connect(_on_tts_cache_completed)
		if TTSInterface.active_cache_requests <= 0:
			_on_tts_cache_completed()
		else:
			loading_bar.value = 80.0
			loading_status_label.text = "Pre-caching synthesized broker voice lines..."


func _on_quest_generated_received(quest_data: Dictionary, is_fallback: bool):
	var now = Time.get_ticks_msec()
	var elapsed_str = ""
	if TTSInterface.last_interaction_time > 0.0:
		elapsed_str = " (Elapsed since '%s': %.3fs)" % [TTSInterface.last_interaction_name, (now - TTSInterface.last_interaction_time) / 1000.0]
	print("[TRACE] [UIManager] _on_quest_generated_received called%s is_fallback: %s" % [elapsed_str, str(is_fallback)])
	
	agent_back_btn.visible = true
	
	for child in agent_choices_container.get_children():
		child.queue_free()
		
	if quest_data.is_empty():
		agent_dialogue_label.text = "No contracts available right now. Check back later."
		return
	
	# ── Step 1: Kaelen introduces the quest giver ─────────────────────────────
	var agent_name = quest_data.get("agent_name", "Broker Kaelen")
	var faction    = quest_data.get("faction", "neutral")
	
	# Per-agent handoff line variations. These are sourced from LLMInterface
	# so the LLM prompt and the runtime fallback stay in sync — same lines
	# serve as few-shot examples for the model and as the offline fallback.
	var handoff_lines: Array = LLMInterface.get_handoff_examples_for_agent(agent_name)
	
	var handoff_line: String
	if cached_unique_intro.strip_edges() != "":
		# LLM successfully generated a unique handoff — use it
		handoff_line = cached_unique_intro
		print("[TRACE] [UIManager] Using unique LLM-generated handoff for: ", agent_name)
	else:
		# No unique intro ready (LLM offline, slow, or this is a fallback quest)
		# — fall back to one of the canned 5 lines for this agent.
		handoff_line = handoff_lines[randi() % handoff_lines.size()]
		print("[TRACE] [UIManager] Using canned handoff fallback for: ", agent_name)
	
	# Show Kaelen with her handoff intro first
	agent_name_label.text = "BROKER KAELEN"
	_update_agent_portrait("neutral")
	agent_dialogue_label.text = handoff_line
	agent_back_btn.visible = true
	
	# Play Kaelen's intro line in her voice
	TTSInterface.play_dialogue_audio(handoff_line, "neutral")
	
	# Add a "Bring them in" button that transitions to the actual quest giver
	var bring_in_btn = Button.new()
	bring_in_btn.text = "[ Bring them in ]"
	bring_in_btn.pressed.connect(func():
		# Clear the handoff button
		for child in agent_choices_container.get_children():
			child.queue_free()
		# Transition to the actual quest giver
		_show_quest_briefing(quest_data, is_fallback)
	)
	agent_choices_container.add_child(bring_in_btn)

func _show_quest_briefing(quest_data: Dictionary, is_fallback: bool):
	# ── Step 2: The quest giver delivers their briefing ───────────────────────
	var raw_dialogue = quest_data.get("dialogue", "")
	var display_dialogue = TTSInterface.clean_dialogue_text(raw_dialogue)
	var note = " [Offline Backup]" if is_fallback else ""
	
	agent_name_label.text = quest_data.get("agent_name", "Broker Kaelen").to_upper()
	_update_agent_portrait(quest_data.get("faction", "neutral"))
	agent_dialogue_label.text = display_dialogue + note
	
	# Play the quest giver's briefing voice
	TTSInterface.play_dialogue_audio(quest_data.get("dialogue", ""), quest_data.get("faction", "neutral"))
	
	# Append contract details block
	var f_client = quest_data.get("faction", "neutral").to_upper()
	var obj = quest_data.get("objective", {})
	var obj_type = obj.get("type", "UNKNOWN")
	var amt_info = ""
	if obj_type == "DELIVER_ORE":
		amt_info = str(int(obj.get("amount_required", 20))) + " m³ Ore"
	elif obj_type == "KILL_SHIPS":
		var target_fac = obj.get("target_faction", "zenith").to_upper()
		amt_info = "Destroy " + str(obj.get("count_required", 3)) + " " + target_fac + " ships"
		
	agent_dialogue_label.text += "\n\n--- Contract Details ---\n" + \
		"Client: " + f_client + "\n" + \
		"Objective: " + amt_info + "\n" + \
		"Base Reward: " + str(obj.get("reward_credits", 150)) + " SC"
	
	# Add player choice buttons
	var choices = quest_data.get("choices", [])
	for choice in choices:
		var choice_btn = Button.new()
		choice_btn.text = choice.get("text", "Accept Option")
		choice_btn.pressed.connect(func(): _on_choice_selected(quest_data, choice))
		agent_choices_container.add_child(choice_btn)



func _on_choice_selected(quest_data: Dictionary, choice: Dictionary):
	TTSInterface.start_interaction("Select Choice: " + choice.get("text", ""))
	
	cached_quest_data = {}
	cached_quest_is_fallback = false
	is_waiting_for_agent_board = false
	
	# Clear choices container
	for child in agent_choices_container.get_children():
		child.queue_free()
		
	# Accept quest
	QuestManager.accept_quest(quest_data, choice)
	
	var consequence = choice.get("consequence", {})
	var raw_response = consequence.get("dialogue_response", "")
	var clean_response = TTSInterface.clean_dialogue_text(raw_response)
	# Safety net: if cleaning stripped everything (entire string was stage direction), use a fallback
	if clean_response.length() < 5:
		clean_response = LLMInterface.fallback_completion_lines[randi() % LLMInterface.fallback_completion_lines.size()]
		print("[TRACE] [UIManager] dialogue_response was empty after cleaning, using fallback.")
	agent_dialogue_label.text = clean_response
	
	# Play choice response voice audio (TTS also cleans internally)
	TTSInterface.play_dialogue_audio(clean_response, quest_data.get("faction", "neutral"))
	
	agent_back_btn.visible = false
	
	# Create undock confirmation button
	var launch_btn = Button.new()
	launch_btn.text = "Undock & Begin Mission"
	launch_btn.pressed.connect(undock_player)
	agent_choices_container.add_child(launch_btn)
	
	# Start pre-caching the NEXT quest immediately in the background
	print("[TRACE] [UIManager] Quest accepted. Starting pre-caching of the next contract.")
	QuestManager.request_new_quest("neutral", _on_background_quest_generated)
	
	# Generate unique Kaelen completion/abandon lines for THIS quest in the background
	cached_completion_line = ""
	cached_abandon_line = ""
	print("[TRACE] [UIManager] Requesting unique Kaelen reaction lines for: ", quest_data.get("title", "quest"))
	LLMInterface.request_kaelen_reaction(quest_data, func(comp_line: String, abn_line: String):
		cached_completion_line = comp_line
		cached_abandon_line = abn_line
		print("[TRACE] [UIManager] Kaelen reactions ready. Caching TTS...")
		# Pre-cache both in the background using neutral (Kaelen's) voice
		TTSInterface.cache_dialogue_audio(comp_line, "neutral")
		TTSInterface.cache_dialogue_audio(abn_line, "neutral")
	)

func _on_agent_back_pressed():
	# Stop voice dialogue audio
	TTSInterface.play_dialogue_audio("")
	agent_panel.visible = false
	dock_panel.visible = true

func _on_agent_complete_pressed():
	TTSInterface.start_interaction("Complete Contract")
	
	is_waiting_for_agent_board = false
	
	for child in agent_choices_container.get_children():
		child.queue_free()
	
	QuestManager.complete_quest()
	
	# Switch to Kaelen's portrait — she's the one paying out, not the quest giver
	agent_name_label.text = "BROKER KAELEN"
	_update_agent_portrait("neutral")
	
	# Use the pre-generated contextual line, fall back to a random one if not ready
	var completion_text = cached_completion_line
	if completion_text == "":
		completion_text = LLMInterface.fallback_completion_lines[randi() % LLMInterface.fallback_completion_lines.size()]
		print("[TRACE] [UIManager] Kaelen completion line not ready, using random fallback.")
	cached_completion_line = ""
	cached_abandon_line = ""
	
	agent_dialogue_label.text = completion_text
	TTSInterface.play_dialogue_audio(completion_text, "neutral")
	agent_back_btn.visible = true
	
	# If for some reason the cache is empty, request one now
	if cached_quest_data.is_empty() and not LLMInterface.is_waiting:
		print("[TRACE] [UIManager] Cache empty on complete. Pre-caching next quest.")
		QuestManager.request_new_quest("neutral", _on_background_quest_generated)

func _on_agent_abandon_pressed():
	TTSInterface.start_interaction("Abandon Contract")
	
	is_waiting_for_agent_board = false
	
	for child in agent_choices_container.get_children():
		child.queue_free()
	
	QuestManager.abandon_quest()
	
	# Switch to Kaelen's portrait — she's the one chewing you out, not the quest giver
	agent_name_label.text = "BROKER KAELEN"
	_update_agent_portrait("neutral")
	
	# Use the pre-generated contextual line, fall back to a random one if not ready
	var abandon_text = cached_abandon_line
	if abandon_text == "":
		abandon_text = LLMInterface.fallback_abandon_lines[randi() % LLMInterface.fallback_abandon_lines.size()]
		print("[TRACE] [UIManager] Kaelen abandon line not ready, using random fallback.")
	cached_completion_line = ""
	cached_abandon_line = ""
	
	agent_dialogue_label.text = abandon_text
	TTSInterface.play_dialogue_audio(abandon_text, "neutral")
	agent_back_btn.visible = true
	
	# If for some reason the cache is empty, request one now
	if cached_quest_data.is_empty() and not LLMInterface.is_waiting:
		print("[TRACE] [UIManager] Cache empty on abandon. Pre-caching next quest.")
		QuestManager.request_new_quest("neutral", _on_background_quest_generated)

func _on_partial_delivery_pressed(deliverable: float):
	TTSInterface.start_interaction("Partial Delivery")
	
	# Clear buttons immediately to prevent double-tap
	for child in agent_choices_container.get_children():
		child.queue_free()
	
	# Bank the ore via QuestManager (deducts cargo, adds to partial_delivered)
	var q = QuestManager.active_quest
	var actually_delivered = QuestManager.deliver_partial(deliverable)
	if actually_delivered <= 0.0:
		_on_talk_to_agent_pressed()
		return
	
	var total_banked = q.get("partial_delivered", 0.0)
	var required = q.get("amount_required", 1.0)
	var quest_title = q.get("title", "the contract")
	
	# Switch to Kaelen portrait while fetching her reaction
	agent_name_label.text = "BROKER KAELEN"
	_update_agent_portrait("neutral")
	agent_dialogue_label.text = "Logging your shipment... stand by."
	agent_back_btn.visible = false
	
	# Request unique Kaelen reaction from LLM
	LLMInterface.request_partial_delivery_line(
		quest_title, actually_delivered, total_banked, required,
		func(line: String):
			var clean = TTSInterface.clean_dialogue_text(line)
			agent_dialogue_label.text = clean
			TTSInterface.play_dialogue_audio(clean, "neutral")
			
			# Add back button so player can undock or check contract
			var back_btn = Button.new()
			back_btn.text = "Back to Services"
			back_btn.pressed.connect(func():
				TTSInterface.play_dialogue_audio("", "neutral")
				agent_panel.visible = false
				dock_panel.visible = true
			)
			agent_choices_container.add_child(back_btn)
			agent_back_btn.visible = true
	)



func _on_quest_accepted():
	quest_tracker_panel.visible = true
	_update_quest_tracker()

func _on_quest_progress_updated():
	_update_quest_tracker()

func _on_quest_completed():
	quest_tracker_panel.visible = false

func _on_quest_abandoned():
	quest_tracker_panel.visible = false

func _update_quest_tracker():
	if not QuestManager.is_quest_active():
		quest_tracker_panel.visible = false
		return
		
	quest_tracker_panel.visible = true
	var q = QuestManager.active_quest
	quest_tracker_title.text = q["title"]
	
	# Update tracker client faction logo
	_update_quest_tracker_logo(q.get("faction", "neutral"))
	
	if q["objective_type"] == "KILL_SHIPS":
		quest_tracker_progress.text = "Kills: " + str(q["current_count"]) + " / " + str(q["count_required"]) + " (" + q["target_faction"].to_upper() + ")"
	elif q["objective_type"] == "DELIVER_ORE":
		var banked = q.get("partial_delivered", 0.0)
		var in_hold = GlobalState.cargo
		var required = q["amount_required"]
		var total_so_far = banked + in_hold
		quest_tracker_progress.text = "Ore: %.0f / %.0f m³" % [total_so_far, required]
		if banked > 0:
			quest_tracker_progress.text += " (%.0f banked)" % banked
		if total_so_far >= required:
			quest_tracker_progress.text += " (Ready)"


func _update_quest_tracker_logo(faction: String):
	if quest_tracker_logo and faction_branding_sheet:
		var atlas = AtlasTexture.new()
		atlas.atlas = faction_branding_sheet
		
		var col = 0
		var show_logo = true
		match faction.to_lower():
			"zenith": col = 0
			"aurelia": col = 1
			"vanguard": col = 2
			_: show_logo = false
			
		if show_logo:
			atlas.region = Rect2(col * 512, 0, 512, 512)
			quest_tracker_logo.texture = atlas
			quest_tracker_logo.visible = true
		else:
			quest_tracker_logo.visible = false

func _update_agent_portrait(faction: String):
	if agent_portrait and quest_givers_sheet:
		var atlas = AtlasTexture.new()
		atlas.atlas = quest_givers_sheet
		
		# Choose portrait index based on faction:
		# Zenith (0), Aurelia (1), Vanguard (2), Neutral (3)
		var index = 3
		match faction.to_lower():
			"zenith": index = 0
			"aurelia": index = 1
			"vanguard": index = 2
			"neutral": index = 3
			
		var col = index % 2
		var row = index / 2
		atlas.region = Rect2(col * 627, row * 627, 627, 627)
		agent_portrait.texture = atlas
		agent_portrait.visible = true
		
	if agent_client_logo and faction_branding_sheet:
		var atlas = AtlasTexture.new()
		atlas.atlas = faction_branding_sheet
		
		var col = 0
		var show_logo = true
		match faction.to_lower():
			"zenith": col = 0
			"aurelia": col = 1
			"vanguard": col = 2
			_: show_logo = false
			
		if show_logo:
			atlas.region = Rect2(col * 512, 0, 512, 512)
			agent_client_logo.texture = atlas
			agent_client_logo.visible = true
		else:
			agent_client_logo.visible = false

func add_chat_message(sender: String, message: String, sender_color: Color):
	if not chat_vbox:
		return
		
	var msg_label = RichTextLabel.new()
	msg_label.bbcode_enabled = true
	msg_label.fit_content = true
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.add_theme_font_size_override("normal_font_size", 12)
	
	var color_hex = sender_color.to_html(false)
	msg_label.text = "[color=#%s][b]%s:[/b][/color] %s" % [color_hex, sender, message]
	
	chat_vbox.add_child(msg_label)
	
	while chat_vbox.get_child_count() > max_chat_messages:
		var first = chat_vbox.get_child(0)
		first.queue_free()
		chat_vbox.remove_child(first)
		
	await get_tree().process_frame
	if chat_scroll:
		chat_scroll.scroll_vertical = int(chat_vbox.size.y)

func _create_loading_screen():
	loading_panel = Panel.new()
	loading_panel.name = "LoadingScreen"
	loading_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(loading_panel)
	
	# Frosted cyber-dark style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.98) # Dark deep space blue-black
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.0, 0.85, 1.0, 0.4) # Neon cyan border accent
	loading_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(500, 250)
	loading_panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "SPACE GRID INTRUSION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0)) # Neon cyan
	vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Syncing Neural Broker Uplink..."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(subtitle)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(450, 16)
	loading_bar.max_value = 100.0
	loading_bar.value = 5.0
	vbox.add_child(loading_bar)
	
	loading_status_label = Label.new()
	loading_status_label.text = "Initializing core connection to local LLM..."
	loading_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_status_label.add_theme_font_size_override("font_size", 11)
	loading_status_label.modulate = Color(0.0, 0.8, 0.8)
	vbox.add_child(loading_status_label)

func _on_llm_connection_attempt(attempt: int):
	last_llm_attempt = attempt
	_update_connection_status_display()

func _on_llm_connected(model_name: String):
	is_llm_ready = true
	_update_connection_status_display()
	_check_both_services_ready()

func _on_tts_connection_attempt(attempt: int):
	last_tts_attempt = attempt
	_update_connection_status_display()

func _on_tts_connected():
	is_tts_ready = true
	_update_connection_status_display()
	_check_both_services_ready()

func _update_connection_status_display():
	if not loading_status_label or not is_instance_valid(loading_status_label):
		return
		
	var llm_status = ""
	if is_llm_ready:
		llm_status = "LLM: Connected"
	else:
		llm_status = "LLM: Connecting... (Attempt %d)" % last_llm_attempt
		
	var tts_status = ""
	if is_tts_ready:
		tts_status = "TTS: Connected"
	else:
		tts_status = "TTS: Connecting... (Attempt %d)" % last_tts_attempt
		
	loading_status_label.text = "%s | %s" % [llm_status, tts_status]
	
	# Initial progress bar increments
	var progress = 5.0
	if is_llm_ready: progress += 10.0
	if is_tts_ready: progress += 10.0
	loading_bar.value = progress

func _check_both_services_ready():
	if is_llm_ready and is_tts_ready:
		print("[TRACE] [UIManager] Both services connected! Starting first quest generation.")
		loading_bar.value = 35.0
		loading_status_label.text = "Syncing Neural Broker Uplink: Generating first contract briefing..."
		
		# Disconnect signals to avoid multiple calls if reconnection happens later
		if LLMInterface.llm_connection_attempt.is_connected(_on_llm_connection_attempt):
			LLMInterface.llm_connection_attempt.disconnect(_on_llm_connection_attempt)
		if LLMInterface.llm_connection_established.is_connected(_on_llm_connected):
			LLMInterface.llm_connection_established.disconnect(_on_llm_connected)
		if TTSInterface.tts_connection_attempt.is_connected(_on_tts_connection_attempt):
			TTSInterface.tts_connection_attempt.disconnect(_on_tts_connection_attempt)
		if TTSInterface.tts_connection_established.is_connected(_on_tts_connected):
			TTSInterface.tts_connection_established.disconnect(_on_tts_connected)
			
		QuestManager.request_new_quest("neutral", _on_background_quest_generated)

func _on_tts_cache_completed():
	# Disconnect to prevent double trigger on future cache events
	if TTSInterface.cache_queue_completed.is_connected(_on_tts_cache_completed):
		TTSInterface.cache_queue_completed.disconnect(_on_tts_cache_completed)
		
	print("[TRACE] [UIManager] Loading Screen: TTS caching fully completed!")
	loading_bar.value = 100.0
	loading_status_label.text = "Uplink fully secured. System Ready."
	
	var tween = create_tween()
	tween.tween_interval(0.8) # Show 100% briefly
	tween.tween_property(loading_panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func():
		loading_panel.queue_free()
		GlobalState.paused = false # Resume gameplay!
		print("[TRACE] [UIManager] Loading Screen completed. Game started!")
		# Trigger Kaelen's intro popup 1s after loading — safely AFTER the overlay is gone
		get_tree().create_timer(1.0).timeout.connect(func():
			show_kaelen_intro()
		)
	)


# ─────────────────────────────────────────────────────────────────────────────
# KAELEN INTRO POPUP
# Called once after the loading screen fades on first entry into the game world.
# ─────────────────────────────────────────────────────────────────────────────

func show_kaelen_intro():
	# Kaelen's greeting variations — picked randomly each session
	var intro_lines = [
		"Hey, Shiny. Fresh hull, empty wallet — you've got that new-pilot smell. Dock up at the station if you want to change that. I've got contracts that pay.",
		"Well, well. Another Shiny shows up in my sector. You look lost. Head to the station — I've got work for anyone with a functioning ship and a low survival instinct.",
		"Shiny. Eyes up. That station on your sensors? That's your new favourite place. Dock in, talk to me, and maybe you won't be flying wreckage by the end of the week.",
		"New to the system? Good. Inexperienced pilots take the risky jobs nobody else wants. Dock at the station, Shiny. I'll make it worth your while — mostly.",
		"I don't do charity, Shiny, but I do do introductions. Station's nearby. Dock up, sit down, and let me explain how this sector works before it kills you.",
		"You've picked an interesting time to show up, Shiny. Lots of factions, lots of credits to be made — if you know who to talk to. That's me. Station. Now.",
	]
	
	var line = intro_lines[randi() % intro_lines.size()]
	
	# ── Dim overlay behind the popup ──────────────────────────────────────────
	var overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# ── Main popup panel (matches agent_panel aesthetic) ──────────────────────
	var popup = Panel.new()
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(680, 260)
	popup.offset_left   = -340
	popup.offset_right  =  340
	popup.offset_top    = -130
	popup.offset_bottom =  130
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 1.0)
	style.border_width_left   = 2
	style.border_width_top    = 2
	style.border_width_right  = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.0, 0.8, 0.8, 1.0)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left  = 6
	popup.add_theme_stylebox_override("panel", style)
	add_child(popup)
	
	# ── Layout ───────────────────────────────────────────────────────────────
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   = 16
	hbox.offset_right  = -16
	hbox.offset_top    = 16
	hbox.offset_bottom = -16
	popup.add_child(hbox)
	
	# Portrait column
	var portrait_vbox = VBoxContainer.new()
	portrait_vbox.custom_minimum_size = Vector2(160, 0)
	portrait_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(portrait_vbox)
	
	var portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(160, 160)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Load Kaelen's portrait slice (neutral = index 3, row 1 col 1)
	var atlas = AtlasTexture.new()
	atlas.atlas = quest_givers_sheet
	var sheet_size = quest_givers_sheet.get_size()
	var cell_w = sheet_size.x / 2.0
	var cell_h = sheet_size.y / 2.0
	atlas.region = Rect2(cell_w, cell_h, cell_w, cell_h)  # col 1, row 1 = neutral/Kaelen
	portrait_rect.texture = atlas
	portrait_vbox.add_child(portrait_rect)
	
	# Spacer
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	hbox.add_child(gap)
	
	# Text column
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "BROKER KAELEN"
	name_lbl.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = "Neutral Fixer & Profit Broker"
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(sub_lbl)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var dialogue_lbl = Label.new()
	dialogue_lbl.text = line
	dialogue_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dialogue_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(dialogue_lbl)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	var dismiss_btn = Button.new()
	dismiss_btn.text = "Got it. Heading to the station."
	dismiss_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.add_child(dismiss_btn)
	
	# ── Fade in ───────────────────────────────────────────────────────────────
	popup.modulate.a = 0.0
	overlay.modulate.a = 0.0
	var fade_in = create_tween()
	fade_in.tween_property(overlay, "modulate:a", 1.0, 0.4)
	fade_in.parallel().tween_property(popup, "modulate:a", 1.0, 0.4)
	
	# ── Dismiss handler ───────────────────────────────────────────────────────
	var _dismiss = func():
		var fade_out = create_tween()
		fade_out.tween_property(popup, "modulate:a", 0.0, 0.35)
		fade_out.parallel().tween_property(overlay, "modulate:a", 0.0, 0.35)
		fade_out.tween_callback(func():
			popup.queue_free()
			overlay.queue_free()
		)
	dismiss_btn.pressed.connect(_dismiss)
	
	# ── Play Kaelen's voice ───────────────────────────────────────────────────
	TTSInterface.play_dialogue_audio(line, "neutral")
	print("[UIManager] Kaelen intro shown: ", line.left(60), "...")
