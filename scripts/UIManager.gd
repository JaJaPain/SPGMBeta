extends Control

# UI Nodes created dynamically
var hud_panel: Panel
var credits_label: Label
var cargo_label: Label
var cargo_bar: ProgressBar

var target_panel: Panel
var target_label: Label
var target_action_box: HBoxContainer

var overview_panel: Panel
var overview_list: VBoxContainer
var overview_collapsed: bool = false
var collapse_btn: Button

var dock_panel: Panel
var dock_label: Label
var sell_btn: Button
var upgrade_cargo_btn: Button
var upgrade_laser_btn: Button
var repair_btn: Button

var pause_panel: Panel
var death_panel: Panel
var context_panel: Panel
var context_action_btn: Button

var current_station: Node3D = null

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

func _create_target_panel():
	target_panel = Panel.new()
	add_child(target_panel)
	target_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 10)
	target_panel.anchor_left = 0.35
	target_panel.anchor_right = 0.65
	target_panel.anchor_top = 0.02
	target_panel.anchor_bottom = 0.15
	target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	
	var vbox = VBoxContainer.new()
	target_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	target_label = Label.new()
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.text = "No Target Selected"
	vbox.add_child(target_label)
	
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
	
	var undock_btn = Button.new()
	undock_btn.text = "Undock Ship"
	undock_btn.pressed.connect(undock_player)
	vbox.add_child(undock_btn)
	
	dock_panel.visible = false

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
	msg.text = "SHIP DESTROYED\nPress ESC to Quit"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)
	
	death_panel.visible = false

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause_game"):
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
			name_lbl.text = "  " + entity.name # Add a little padding space
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
				type_str = "Space Station"
			elif entity.is_in_group("ship"):
				type_str = "NPC Ship (" + entity.get("faction").to_upper() + ")"
			
			type_lbl.text = "  " + type_str
			type_lbl.custom_minimum_size = Vector2(160, 0)
			type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			type_lbl.clip_text = true
			hbox.add_child(type_lbl)
			
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
		if new_target.is_in_group("asteroid"):
			type_str = "Asteroid"
		elif new_target.is_in_group("station"):
			type_str = "Station"
		elif new_target.is_in_group("ship"):
			type_str = "Hostile NPCShip"
			
		target_label.text = new_target.name + " [" + type_str + "]"
	else:
		target_panel.visible = false
		target_label.text = "No Target Selected"
		
	if overview_collapsed:
		refresh_overview()

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

func _on_pause_changed(is_paused: bool):
	if pause_panel:
		pause_panel.visible = is_paused
		if is_paused:
			move_child(pause_panel, -1)

# Station services methods
func toggle_dock_menu(station: Node3D):
	current_station = station
	dock_panel.visible = not dock_panel.visible
	if dock_panel.visible:
		# Update upgrade buttons prices/labels
		upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - 100 SC"
		upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - 150 SC"
		_update_repair_button()

func undock_player():
	dock_panel.visible = false
	current_station = null
	# Give player a slight push away from station
	if GlobalState.player:
		GlobalState.player.global_position += Vector3(0, 0, -15.0)

func _sell_ore():
	if GlobalState.cargo > 0.0:
		var earnings = int(GlobalState.cargo)
		GlobalState.player_credits += earnings
		GlobalState.cargo = 0.0
		_update_repair_button()

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
	
	# Add station, planets
	var station = main.get_node_or_null("Station")
	if station: entities.append(station)
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
	
	if GlobalState.player_credits >= total_cost:
		# Full repair
		GlobalState.player_credits -= total_cost
		p.set("health", max_hp)
	else:
		# Partial repair
		var affordable_hp = int(GlobalState.player_credits / cost_per_hp)
		if affordable_hp > 0:
			var cost_paid = int(affordable_hp * cost_per_hp)
			GlobalState.player_credits -= cost_paid
			p.set("health", hp + affordable_hp)
			
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
