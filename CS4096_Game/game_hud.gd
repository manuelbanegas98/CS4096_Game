extends CanvasLayer
class_name GameHUD

signal start_requested(chosen_name: String)

var player_name := "Ghost"

var title_label: Label
var score_label: Label
var lives_label: Label
var level_label: Label
var crystal_label: Label
var bait_label: Label
var power_label: Label
var message_label: Label
var debug_panel: ColorRect
var debug_label: Label

var menu_border: ColorRect
var menu_box: ColorRect
var menu_title: Label
var name_prompt_label: Label
var name_input: LineEdit
var menu_abstract: Label
var menu_controls: Label
var menu_prompt: Label


func _ready() -> void:
	_ensure_ui()


func _ensure_ui() -> void:
	if score_label != null:
		return
	# top bar labels
	title_label = _make_label("GHOST", Vector2(24, 13), Vector2(200, 34), 19, Color("eafaff"))
	score_label = _make_label("SCORE 00000", Vector2(215, 19), Vector2(135, 26), 16, Color("7ce8ff"))
	lives_label = _make_label("LIVES 3", Vector2(360, 19), Vector2(90, 26), 16, Color("ff7b91"))
	level_label = _make_label("LVL 1: PAC-MAN", Vector2(460, 19), Vector2(175, 26), 16, Color("ffe066"))
	crystal_label = _make_label("CRYSTALS 0/5", Vector2(645, 19), Vector2(145, 26), 16, Color("a5f3ff"))
	bait_label = _make_label("BAIT 3/3", Vector2(800, 19), Vector2(145, 26), 16, Color("ff9f68"))
	power_label = _make_label("WASD/ARROWS: MOVE   SPACE: DROP BAIT   P: PAUSE   F3: AI TRACE", Vector2(24, 52), Vector2(910, 22), 13, Color("9ab4c7"))
	message_label = _make_label("", Vector2(176, 265), Vector2(608, 95), 23, Color("f4fbff"))
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.visible = false

	# F3 debug overlay
	debug_panel = ColorRect.new()
	debug_panel.position = Vector2(792, 102)
	debug_panel.size = Vector2(158, 200)
	debug_panel.color = Color(0.025, 0.055, 0.09, 0.92)
	debug_panel.visible = false
	add_child(debug_panel)
	debug_label = _make_label("", Vector2(800, 110), Vector2(144, 185), 12, Color("9defff"))
	debug_label.visible = false

	# start menu panel
	menu_border = ColorRect.new()
	menu_border.position = Vector2(168, 98)
	menu_border.size = Vector2(624, 456)
	menu_border.color = Color("3abef6")
	add_child(menu_border)

	menu_box = ColorRect.new()
	menu_box.position = Vector2(171, 101)
	menu_box.size = Vector2(618, 450)
	menu_box.color = Color(0.03, 0.07, 0.13, 0.96)
	add_child(menu_box)

	menu_title = _make_label("GHOST", Vector2(190, 112), Vector2(580, 34), 25, Color("7ce8ff"))
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	name_prompt_label = _make_label("ENTER YOUR NAME:", Vector2(240, 156), Vector2(175, 30), 15, Color("ffe066"))
	name_input = LineEdit.new()
	name_input.position = Vector2(415, 151)
	name_input.size = Vector2(240, 32)
	name_input.placeholder_text = "Type name..."
	name_input.max_length = 14
	name_input.add_theme_font_size_override("font_size", 15)
	name_input.text_changed.connect(_on_name_text_changed)
	name_input.text_submitted.connect(_on_name_text_submitted)
	add_child(name_input)

	var abstract_text := (
		"You must escape three arcade worlds by collecting 5 Memory Crystals\n"
		+ "to open the Edge Portal. Each level's hunter uses a distinct AI system:\n\n"
		+ "- Lvl 1 - Pac-Man: Predictive Pursuit Steering (Bait: Power Cherries)\n"
		+ "- Lvl 2 - Scooby-Doo: Scent Radius & Arrive Steering (Bait: Scooby Snacks)\n"
		+ "- Lvl 3 - Luigi: Flashlight Vision Cone & Search (Bait: Ghost Dummy)"
	)
	menu_abstract = _make_label(abstract_text, Vector2(204, 198), Vector2(552, 150), 15, Color("eafaff"))

	var controls_text := (
		"CONTROLS\n"
		+ "- WASD / ARROWS : Move Ghost\n"
		+ "- SPACEBAR : Drop Bait (3 per level, 2s distraction)\n"
		+ "- P / ESC : Pause Game     - F3 : AI Trace"
	)
	menu_controls = _make_label(controls_text, Vector2(204, 358), Vector2(552, 110), 15, Color("ffe066"))

	menu_prompt = _make_label("[ PRESS ENTER TO ESCAPE ]", Vector2(190, 496), Vector2(580, 34), 19, Color("6bff95"))
	menu_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_refresh_name_texts()


func get_player_name() -> String:
	return player_name


func _on_name_text_changed(new_text: String) -> void:
	var cleaned := new_text.strip_edges()
	player_name = cleaned if not cleaned.is_empty() else "Ghost"
	_refresh_name_texts()


func _on_name_text_submitted(_submitted_text: String) -> void:
	_on_name_text_changed(name_input.text)
	start_requested.emit(player_name)


func _refresh_name_texts() -> void:
	var upper_name := player_name.to_upper()
	title_label.text = upper_name
	menu_title.text = upper_name


func set_menu_visible(is_visible: bool) -> void:
	_ensure_ui()
	menu_border.visible = is_visible
	menu_box.visible = is_visible
	menu_title.visible = is_visible
	name_prompt_label.visible = is_visible
	name_input.visible = is_visible
	menu_abstract.visible = is_visible
	menu_controls.visible = is_visible
	menu_prompt.visible = is_visible
	if is_visible:
		name_input.grab_focus()
	else:
		name_input.release_focus()


func update_status(
	score: int,
	lives: int,
	level: int,
	collected_crystals: int,
	total_crystals: int,
	portal_open: bool,
	bait_left: int,
	max_bait: int,
	bait_name: String,
	enemy_name: String,
	ai_state: StringName,
	target_name: String,
	path_length: int,
	prediction: int,
	distract_timer: float
) -> void:
	_ensure_ui()
	title_label.text = player_name.to_upper()
	score_label.text = "SCORE %05d" % score
	lives_label.text = "LIVES %d" % lives
	level_label.text = "LVL %d: %s" % [level, enemy_name]
	if portal_open:
		crystal_label.text = "PORTAL OPEN!"
		crystal_label.add_theme_color_override("font_color", Color("6bff95"))
	else:
		crystal_label.text = "CRYSTALS %d/%d" % [collected_crystals, total_crystals]
		crystal_label.add_theme_color_override("font_color", Color("a5f3ff"))

	bait_label.text = "BAIT %d/%d" % [bait_left, max_bait]
	power_label.text = "MOVE: WASD/ARROWS   SPACE: DROP %s (%d/%d)   ENEMY AI: %s" % [bait_name, bait_left, max_bait, ai_state]
	if distract_timer > 0.0:
		power_label.text += " (%.1fs)" % distract_timer

	if debug_panel.visible:
		debug_label.text = "HUNTER: %s\n\nFSM STATE:\n%s\n\nTARGET:\n%s\n\nA* PATH:\n%d tiles\n\nLOOKAHEAD:\n%d tiles" % [
			enemy_name,
			ai_state,
			target_name,
			path_length,
			prediction
		]


func set_debug_visible(is_visible: bool) -> void:
	_ensure_ui()
	debug_panel.visible = is_visible
	debug_label.visible = is_visible


func show_message(text: String) -> void:
	_ensure_ui()
	message_label.text = text
	message_label.visible = not text.is_empty()


func _make_label(text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
