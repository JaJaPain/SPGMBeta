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

var dock_panel: Panel
var dock_label: Label
var sell_btn: Button
var upgrade_cargo_btn: Button
var upgrade_laser_btn: Button

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

func _ready():
	# Configure layout
	anchors_preset = Control.PRESET_FULL_RECT
	
	# Connect GlobalState signals
	GlobalState.credits_changed.connect(_on_credits_changed)
	GlobalState.cargo_changed.connect(_on_cargo_changed)
	GlobalState.target_changed.connect(_on_target_changed)
	GlobalState.game_paused.connect(_on_pause_changed)
	
	_create_hud()
	_create_target_panel()
	_create_overview()
	_create_dock_menu()
	_create_context_menu()
	_create_pause_menu()
	_create_death_screen()
	
	# Initial UI state
	_on_credits_changed(GlobalState.player_credits)
	_on_cargo_changed(GlobalState.cargo)
	_on_target_changed(GlobalState.active_target)

func _process(_delta):
	if GlobalState.paused: return
	
	# Update overview list item distances
	_update_overview_distances()
	
	# Handle drag to resize
	_handle_resize_hover()

func _create_hud():
	hud_panel = Panel.new()
	hud_panel.custom_minimum_size = Vector2(350, 80)
	hud_panel.position = Vector2(20, 20)
	add_child(hud_panel)
	
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(10, 10)
	vbox.custom_minimum_size = Vector2(330, 60)
	hud_panel.add_child(vbox)
	
	credits_label = Label.new()
	credits_label.text = "Credits: 50 ISK"
	vbox.add_child(credits_label)
	
	cargo_label = Label.new()
	cargo_label.text = "Cargo: 0 / 100 m³"
	vbox.add_child(cargo_label)
	
	cargo_bar = ProgressBar.new()
	cargo_bar.max_value = GlobalState.cargo_max
	cargo_bar.value = 0
	cargo_bar.custom_minimum_size = Vector2(300, 15)
	vbox.add_child(cargo_bar)

func _create_target_panel():
	target_panel = Panel.new()
	target_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 10)
	target_panel.anchor_left = 0.35
	target_panel.anchor_right = 0.65
	target_panel.anchor_top = 0.02
	target_panel.anchor_bottom = 0.15
	target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(target_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	target_panel.add_child(vbox)
	
	target_label = Label.new()
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.text = "No Target Selected"
	vbox.add_child(target_label)
	
	target_action_box = HBoxContainer.new()
	target_action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(target_action_box)
	
	var app_btn = Button.new()
	app_btn.text = "Fly to"
	app_btn.pressed.connect(func(): if GlobalState.player: GlobalState.player.set("nav_mode", "APPROACH"))
	target_action_box.add_child(app_btn)
	
	var orb_btn = Button.new()
	orb_btn.text = "Orbit"
	orb_btn.pressed.connect(func(): if GlobalState.player: GlobalState.player.set("nav_mode", "ORBIT"))
	target_action_box.add_child(orb_btn)
	
	target_panel.visible = false

func _create_overview():
	overview_panel = Panel.new()
	overview_panel.anchor_left = 0.78
	overview_panel.anchor_right = 0.98
	overview_panel.anchor_top = 0.05
	overview_panel.anchor_bottom = 0.65
	add_child(overview_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	overview_panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "OVERVIEW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Create Header HBox for sorting
	var header_hbox = HBoxContainer.new()
	header_hbox.custom_minimum_size = Vector2(0, 25)
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
	
	_update_header_labels()
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	dock_panel.anchor_left = 0.3
	dock_panel.anchor_right = 0.7
	dock_panel.anchor_top = 0.25
	dock_panel.anchor_bottom = 0.75
	add_child(dock_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_panel.add_child(vbox)
	
	dock_label = Label.new()
	dock_label.text = "STATION SERVICES"
	dock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dock_label)
	
	sell_btn = Button.new()
	sell_btn.text = "Sell Ore (1 ISK per m³)"
	sell_btn.pressed.connect(_sell_ore)
	vbox.add_child(sell_btn)
	
	upgrade_cargo_btn = Button.new()
	upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - 100 ISK"
	upgrade_cargo_btn.pressed.connect(_upgrade_cargo)
	vbox.add_child(upgrade_cargo_btn)
	
	upgrade_laser_btn = Button.new()
	upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - 150 ISK"
	upgrade_laser_btn.pressed.connect(_upgrade_laser)
	vbox.add_child(upgrade_laser_btn)
	
	var undock_btn = Button.new()
	undock_btn.text = "Undock Ship"
	undock_btn.pressed.connect(undock_player)
	vbox.add_child(undock_btn)
	
	dock_panel.visible = false

func _create_context_menu():
	context_panel = Panel.new()
	context_panel.custom_minimum_size = Vector2(150, 160)
	add_child(context_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	context_panel.add_child(vbox)
	
	var action_app = Button.new()
	action_app.text = "Fly to"
	action_app.pressed.connect(func():
		if GlobalState.player: GlobalState.player.set("nav_mode", "APPROACH")
		context_panel.visible = false
	)
	vbox.add_child(action_app)
	
	var action_orb = Button.new()
	action_orb.text = "Orbit"
	action_orb.pressed.connect(func():
		if GlobalState.player: GlobalState.player.set("nav_mode", "ORBIT")
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
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pause_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_panel.add_child(vbox)
	
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
	
	pause_panel.visible = false

func _create_death_screen():
	death_panel = Panel.new()
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(death_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	death_panel.add_child(vbox)
	
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
		
	for entity in entities:
		if entity and is_instance_valid(entity) and entity != GlobalState.player:
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 30)
			btn.pressed.connect(func(): GlobalState.active_target = entity)
			
			# HBox inside the button for spreadsheet column layout
			var hbox = HBoxContainer.new()
			hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(hbox)
			
			var name_lbl = Label.new()
			name_lbl.text = "  " + entity.name # Add a little padding space
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			hbox.add_child(type_lbl)
			
			# Meta parameters for sorting and updating
			btn.set_meta("entity_ref", entity)
			btn.set_meta("entity_name", entity.name)
			btn.set_meta("type_str", type_str)
			btn.set_meta("distance_val", 0.0) # Updated dynamically in _update_overview_distances
			btn.set_meta("dist_label_ref", dist_lbl)
			
			overview_list.add_child(btn)

func _update_overview_distances():
	if not GlobalState.player or not is_instance_valid(GlobalState.player): return
	var p_pos = GlobalState.player.global_position
	
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
			else:
				btn.queue_free()
				
	# Now sort children
	var children = overview_list.get_children()
	children.sort_custom(func(a, b):
		if sort_column == "name":
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			return name_a < name_b if sort_ascending else name_a > name_b
		elif sort_column == "type":
			var type_a = a.get_meta("type_str").to_lower()
			var type_b = b.get_meta("type_str").to_lower()
			return type_a < type_b if sort_ascending else type_a > type_b
		else: # distance
			var dist_a = a.get_meta("distance_val")
			var dist_b = b.get_meta("distance_val")
			return dist_a < dist_b if sort_ascending else dist_a > dist_b
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

func _on_credits_changed(new_credits: int):
	if credits_label:
		credits_label.text = "Credits: " + str(new_credits) + " ISK"

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

# Station services methods
func toggle_dock_menu(station: Node3D):
	current_station = station
	dock_panel.visible = not dock_panel.visible
	if dock_panel.visible:
		# Update upgrade buttons prices/labels
		upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - 100 ISK"
		upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - 150 ISK"

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

func _upgrade_cargo():
	if GlobalState.player_credits >= 100:
		GlobalState.player_credits -= 100
		GlobalState.cargo_max += 25.0
		_on_cargo_changed(GlobalState.cargo) # Update HUD bar
		upgrade_cargo_btn.text = "Upgrade Cargo Hold (+25 m³) - Purchased!"

func _upgrade_laser():
	if GlobalState.player_credits >= 150:
		GlobalState.player_credits -= 150
		GlobalState.mining_yield += 1.0
		upgrade_laser_btn.text = "Upgrade Mining Laser (+1 yield) - Purchased!"

func show_context_menu(entity: Node3D):
	if not entity or not is_instance_valid(entity): return
	context_panel.visible = true
	context_panel.global_position = get_viewport().get_mouse_position()
	
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

func _handle_resize_hover():
	if is_resizing:
		var mouse_x = get_viewport().get_mouse_position().x
		var viewport_w = get_viewport().get_visible_rect().size.x
		
		# Allow resize from 250px to 800px width
		var min_x = viewport_w - 800.0
		var max_x = viewport_w - 250.0
		var target_x = clamp(mouse_x, min_x, max_x)
		
		overview_panel.anchor_left = target_x / viewport_w
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var panel_rect = overview_panel.get_global_rect()
	
	# Detect mouse near the left border of the panel
	var on_left_edge = (
		mouse_pos.x >= panel_rect.position.x - RESIZE_BORDER_WIDTH / 2.0 and
		mouse_pos.x <= panel_rect.position.x + RESIZE_BORDER_WIDTH / 2.0 and
		mouse_pos.y >= panel_rect.position.y and
		mouse_pos.y <= panel_rect.position.y + panel_rect.size.y
	)
	
	if on_left_edge:
		overview_panel.mouse_default_cursor_shape = Control.CURSOR_HSIZE
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_resizing = true
	else:
		overview_panel.mouse_default_cursor_shape = Control.CURSOR_ARROW
