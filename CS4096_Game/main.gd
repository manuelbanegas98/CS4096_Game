extends Node2D

const MAZE_SCRIPT = preload("res://maze.gd")
const PLAYER_SCRIPT = preload("res://player.gd")
const GHOST_SCRIPT = preload("res://ghost_ai.gd")
const HUD_SCRIPT = preload("res://game_hud.gd")
const AUDIO_SCRIPT = preload("res://audio_manager.gd")

const MAX_LEVELS := 3

var maze
var player
var ghost
var hud
var audio_manager
var score := 0
var lives := 3
var level := 1
var game_state := &"menu"
var death_timer := 0.0
var level_timer := 0.0
var banner_timer := 0.0
var animation_clock := 0.0
var debug_visible := false
var particles: Array[Dictionary] = []


func _ready() -> void:
	randomize()
	hud = HUD_SCRIPT.new()
	add_child(hud)
	hud.start_requested.connect(_on_menu_start_requested)
	audio_manager = AUDIO_SCRIPT.new()
	add_child(audio_manager)
	_setup_level(false)
	game_state = &"menu"
	hud.set_menu_visible(true)
	_update_hud()


func _on_menu_start_requested(_chosen_name: String) -> void:
	if game_state != &"menu":
		return
	hud.set_menu_visible(false)
	game_state = &"playing"
	audio_manager.play_effect(&"collect")
	hud.show_message(_level_banner_text(level))
	banner_timer = 1.6
	_update_hud()


func _process(delta: float) -> void:
	animation_clock += delta
	_update_particles(delta)
	if game_state == &"dying":
		death_timer -= delta
		if death_timer <= 0.0:
			if lives <= 0:
				game_state = &"game_over"
				hud.show_message("CAPTURED!\nPress SPACE to restart")
			else:
				player.reset_to(maze.player_start, maze)
				ghost.reset_ai(maze, level)
				game_state = &"playing"
				hud.show_message("")
		_update_hud()
		queue_redraw()
		return
	if game_state == &"level_clear":
		level_timer -= delta
		if level_timer <= 0.0:
			if level >= MAX_LEVELS:
				game_state = &"victory"
				hud.show_message("FREEDOM ACHIEVED!\nYou escaped Pac-Man, Scooby-Doo & Luigi!\nPress SPACE to play again")
			else:
				level += 1
				_setup_level(true)
		queue_redraw()
		return
	if banner_timer > 0.0:
		banner_timer = maxf(0.0, banner_timer - delta)
		if banner_timer == 0.0 and game_state == &"playing":
			hud.show_message("")
	if game_state != &"playing":
		queue_redraw()
		return

	var input_direction := _read_direction()
	if input_direction != Vector2i.ZERO:
		player.set_movement_input(input_direction)
	player.move_player(delta, maze)
	ghost.update_brain(delta, maze, player.tile, player.direction, level)

	# check if player reached the open exit portal
	if maze.portal_active and player.tile == maze.portal_tile:
		_complete_level()
		queue_redraw()
		return

	# check collision with hunter (ignored while enemy is eating bait)
	if game_state == &"playing" and ghost.ai_state != &"DISTRACTED" and player.position.distance_to(ghost.position) < 21.0:
		_lose_life()

	_update_hud()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		debug_visible = not debug_visible
		hud.set_debug_visible(debug_visible)
	elif event.keycode == KEY_P or event.keycode == KEY_ESCAPE:
		if game_state == &"playing":
			game_state = &"paused"
			hud.show_message("PAUSED\nPress P or ESC to resume")
		elif game_state == &"paused":
			game_state = &"playing"
			hud.show_message("")
	elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if game_state == &"menu" and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
			_on_menu_start_requested(hud.get_player_name())
		elif game_state == &"playing" and event.keycode == KEY_SPACE:
			if player.try_drop_distraction(maze, level):
				audio_manager.play_effect(&"power")
				_spawn_sparks(player.position, Color("ffbe55"), 14)
				_update_hud()
		elif game_state == &"game_over" or game_state == &"victory":
			score = 0
			lives = 3
			level = 1
			_setup_level(true)
		elif game_state == &"level_clear":
			level_timer = 0.0


func _read_direction() -> Vector2i:
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		return Vector2i.UP
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		return Vector2i.RIGHT
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		return Vector2i.DOWN
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		return Vector2i.LEFT
	return Vector2i.ZERO


func _setup_level(announce: bool) -> void:
	game_state = &"playing"
	hud.set_menu_visible(false)
	particles.clear()
	maze = MAZE_SCRIPT.new()
	maze.build(level)
	maze.crystal_collected.connect(_on_crystal_collected)
	if player == null:
		player = PLAYER_SCRIPT.new()
		add_child(player)
		player.tile_entered.connect(_on_player_tile_entered)
	player.setup(maze.player_start, maze)
	player.reset_distractions()
	if ghost == null:
		ghost = GHOST_SCRIPT.new()
		add_child(ghost)
	ghost.setup(maze.ghost_home, maze, level)
	if announce:
		hud.show_message(_level_banner_text(level))
		banner_timer = 1.6
	else:
		banner_timer = 0.0
		hud.show_message("")
	_update_hud()


func _level_banner_text(lvl: int) -> String:
	if lvl == 1:
		return "LEVEL 1: ESCAPE PAC-MAN\nCollect 5 Memory Crystals!"
	elif lvl == 2:
		return "LEVEL 2: ESCAPE SCOOBY-DOO\nUse Scooby Snacks to distract him!"
	return "LEVEL 3: ESCAPE LUIGI\nAvoid his Flashlight Cone!"


func _on_player_tile_entered(cell: Vector2i) -> void:
	maze.collect_at(cell)
	if maze.portal_active and cell == maze.portal_tile:
		_complete_level()


func _on_crystal_collected(cell: Vector2i) -> void:
	score += 100
	audio_manager.play_effect(&"collect")
	_spawn_sparks(maze.cell_center(cell), Color("7ce8ff"), 18)
	if maze.crystals.is_empty() and not maze.portal_active:
		var portal_cell: Vector2i = maze.spawn_escape_portal(ghost.tile)
		audio_manager.play_effect(&"power")
		_spawn_sparks(maze.cell_center(portal_cell), Color("6bff95"), 26)
		hud.show_message("ALL CRYSTALS COLLECTED!\nEnter the Escape Portal on the edge!")
		banner_timer = 2.0
	_update_hud()


func _complete_level() -> void:
	if game_state != &"playing":
		return
	score += 300
	game_state = &"level_clear"
	level_timer = 1.5
	audio_manager.play_effect(&"catch")
	_spawn_sparks(player.position, Color("6bff95"), 28)
	if level < MAX_LEVELS:
		hud.show_message("LEVEL %d ESCAPED!" % level)
	else:
		hud.show_message("FINAL MAZE ESCAPED!")
	_update_hud()


func _lose_life() -> void:
	if game_state != &"playing":
		return
	lives -= 1
	game_state = &"dying"
	death_timer = 0.85
	player.direction = Vector2i.ZERO
	player.queued_direction = Vector2i.ZERO
	audio_manager.play_effect(&"hit")
	_spawn_sparks(player.position, Color("ff607d"), 18)
	hud.show_message("CAUGHT BY %s!" % ghost.get_enemy_name())


func _update_hud() -> void:
	if hud == null or maze == null or ghost == null or player == null:
		return
	var current_name: String = hud.get_player_name().to_upper()
	var target_name := current_name
	if ghost.ai_state == &"PURSUIT":
		target_name = "PREDICTED PATH"
	elif ghost.ai_state == &"SEARCH":
		target_name = "LAST SEEN TILE"
	elif ghost.ai_state == &"PATROL":
		target_name = "WAYPOINT"
	elif ghost.ai_state == &"SEEK_BAIT" or ghost.ai_state == &"DISTRACTED":
		target_name = player.get_distraction_label(level)

	var collected: int = maze.total_crystals - maze.crystals.size()
	var distract_time: float = ghost.state_clock if ghost.ai_state == &"DISTRACTED" else 0.0
	hud.update_status(
		score,
		lives,
		level,
		collected,
		maze.total_crystals,
		maze.portal_active,
		player.distractions_left,
		player.max_distractions,
		player.get_distraction_label(level),
		ghost.get_enemy_name(),
		ghost.ai_state,
		target_name,
		ghost.path_length(),
		ghost.prediction_tiles,
		distract_time
	)


func _spawn_sparks(at: Vector2, color: Color, count: int) -> void:
	for _index in range(count):
		var angle := randf() * TAU
		var speed := randf_range(24.0, 95.0)
		particles.append({"position": at, "velocity": Vector2(cos(angle), sin(angle)) * speed, "life": randf_range(0.22, 0.55), "color": color})


func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["position"] += particle["velocity"] * delta
		particle["life"] -= delta
		if particle["life"] <= 0.0:
			particles.remove_at(index)
		else:
			particles[index] = particle


# color palette per level (arcade, castle, mansion)
func _get_theme_colors(lvl: int) -> Dictionary:
	if lvl == 1:
		return {
			"bg": Color("060d1a"),
			"header": Color("0b1930"),
			"board_border": Color("1e50d6"),
			"board_fill": Color("081226"),
			"wall_fill": Color("153e75"),
			"wall_stroke": Color("3abef6"),
			"grid_line": Color(0.22, 0.74, 0.97, 0.07),
		}
	elif lvl == 2:
		return {
			"bg": Color("0d0914"),
			"header": Color("191124"),
			"board_border": Color("5b3e85"),
			"board_fill": Color("120d1c"),
			"wall_fill": Color("2e2240"),
			"wall_stroke": Color("74a15e"),
			"grid_line": Color(0.45, 0.63, 0.37, 0.08),
		}
	else:
		return {
			"bg": Color("09070a"),
			"header": Color("171014"),
			"board_border": Color("78352b"),
			"board_fill": Color("100b0e"),
			"wall_fill": Color("381d1a"),
			"wall_stroke": Color("9e5847"),
			"grid_line": Color(0.62, 0.35, 0.28, 0.07),
		}


func _draw() -> void:
	var theme := _get_theme_colors(level)
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 600)), theme["bg"])
	draw_rect(Rect2(Vector2(0, 0), Vector2(960, 82)), theme["header"])
	draw_line(Vector2(24, 81), Vector2(936, 81), theme["wall_stroke"], 1.2)
	if maze != null:
		_draw_maze(theme)
		_draw_perception_overlay()
		_draw_crystals()
		_draw_distractions()
		_draw_portal()
		if player != null:
			_draw_sentient_ghost()
		if ghost != null:
			_draw_pursuer()
		if debug_visible:
			_draw_debug_ai_gizmos()
	_draw_particles()


func _draw_maze(theme: Dictionary) -> void:
	var board := Rect2(maze.origin, Vector2(maze.width, maze.height) * maze.tile_size)
	draw_rect(board.grow(5.0), theme["board_border"])
	draw_rect(board, theme["board_fill"])
	for y in range(maze.height):
		for x in range(maze.width):
			var cell := Vector2i(x, y)
			var rect := Rect2(maze.origin + Vector2(x, y) * maze.tile_size, Vector2.ONE * maze.tile_size)
			if not maze.is_open(cell):
				draw_rect(rect.grow(-1.0), theme["wall_fill"])
				draw_rect(rect.grow(-3.0), theme["wall_stroke"], false, 1.3, true)
			else:
				draw_rect(rect, theme["grid_line"], false, 1.0)


# draw Scooby's scent ring (lvl 2) or Luigi's flashlight cone (lvl 3)
func _draw_perception_overlay() -> void:
	if ghost == null:
		return
	if level == 2:
		var radius: float = ghost.scent_radius_tiles * float(maze.tile_size)
		var ring_color := Color(0.45, 0.85, 0.45, 0.16) if ghost.ai_state != &"CHASE" else Color(1.0, 0.65, 0.25, 0.24)
		draw_arc(ghost.position, radius, 0.0, TAU, 48, ring_color, 1.5, true)
	elif level == 3:
		var cone_len: float = ghost.vision_range_tiles * float(maze.tile_size)
		var half_rad: float = deg_to_rad(ghost.vision_fov_degrees * 0.5)
		var base_angle: float = ghost.facing_vector.angle()
		var rays := 18
		var poly := PackedVector2Array([ghost.position])
		for i in range(rays + 1):
			var t := float(i) / float(rays)
			var ang := lerpf(base_angle - half_rad, base_angle + half_rad, t)
			var dir := Vector2(cos(ang), sin(ang))
			var hit_pos: Vector2 = ghost.position + dir * cone_len
			for step in range(1, 24):
				var sample: Vector2 = ghost.position + dir * (cone_len * float(step) / 24.0)
				if not maze.is_open(maze.world_to_cell(sample)):
					hit_pos = sample
					break
			poly.append(hit_pos)
		var beam_color := Color(1.0, 0.95, 0.45, 0.20)
		if ghost.ai_state == &"CHASE":
			beam_color = Color(1.0, 0.38, 0.32, 0.26)
		draw_colored_polygon(poly, beam_color)


func _draw_crystals() -> void:
	for cell in maze.crystals:
		var center: Vector2 = maze.cell_center(cell)
		var pulse := 1.0 + 0.15 * sin(animation_clock * 4.8 + float(cell.x + cell.y))
		draw_circle(center, 11.5 * pulse, Color(0.32, 0.92, 1.0, 0.18))
		var r := 8.5 * pulse
		var diamond := PackedVector2Array([
			center + Vector2(0, -r),
			center + Vector2(r * 0.78, 0),
			center + Vector2(0, r),
			center + Vector2(-r * 0.78, 0),
		])
		draw_colored_polygon(diamond, Color("66e6f7"))
		var core := PackedVector2Array([
			center + Vector2(0, -r * 0.5),
			center + Vector2(r * 0.4, 0),
			center + Vector2(0, r * 0.5),
			center + Vector2(-r * 0.4, 0),
		])
		draw_colored_polygon(core, Color("ffffff"))


func _draw_distractions() -> void:
	for cell in maze.distractions:
		var entry: Dictionary = maze.distractions[cell]
		var kind: StringName = entry["kind"]
		var center: Vector2 = maze.cell_center(cell)
		var bounce := sin(animation_clock * 6.0) * 1.8
		var pos := center + Vector2(0, bounce)
		if kind == &"cherries":
			draw_line(pos + Vector2(-4, 2), pos + Vector2(1, -8), Color("65d654"), 2.0)
			draw_line(pos + Vector2(5, 3), pos + Vector2(1, -8), Color("65d654"), 2.0)
			draw_circle(pos + Vector2(-5, 4), 5.0, Color("ff2e55"))
			draw_circle(pos + Vector2(5, 5), 5.0, Color("ff2e55"))
			draw_circle(pos + Vector2(-6, 2), 1.5, Color("ffffff"))
			draw_circle(pos + Vector2(4, 3), 1.5, Color("ffffff"))
		elif kind == &"scooby_snack":
			draw_circle(pos + Vector2(-7, -3), 4.0, Color("e6a145"))
			draw_circle(pos + Vector2(-7, 3), 4.0, Color("e6a145"))
			draw_circle(pos + Vector2(7, -3), 4.0, Color("e6a145"))
			draw_circle(pos + Vector2(7, 3), 4.0, Color("e6a145"))
			draw_rect(Rect2(pos + Vector2(-7, -3.5), Vector2(14, 7)), Color("f4b860"))
			draw_circle(pos, 2.5, Color("2ed2bd"))
		else:
			draw_line(pos + Vector2(0, 4), pos + Vector2(0, 11), Color("b08968"), 3.0)
			draw_line(pos + Vector2(-6, 11), pos + Vector2(6, 11), Color("b08968"), 2.5)
			var dummy := PackedVector2Array([
				pos + Vector2(-9, 6), pos + Vector2(-9, -3),
				pos + Vector2(-4, -9), pos + Vector2(4, -9),
				pos + Vector2(9, -3), pos + Vector2(9, 6)
			])
			draw_colored_polygon(dummy, Color(0.75, 0.92, 1.0, 0.85))
			draw_circle(pos + Vector2(-3, -3), 1.8, Color("121926"))
			draw_circle(pos + Vector2(3, -3), 1.8, Color("121926"))


func _draw_portal() -> void:
	if not maze.portal_active:
		return
	var center: Vector2 = maze.cell_center(maze.portal_tile)
	var pulse := 1.0 + 0.16 * sin(animation_clock * 7.0)
	draw_circle(center, 15.0 * pulse, Color(0.25, 1.0, 0.58, 0.25))
	draw_arc(center, 12.0 * pulse, animation_clock * 3.0, animation_clock * 3.0 + TAU * 0.75, 28, Color("6bff95"), 3.0, true)
	draw_circle(center, 7.5, Color("12b880"))
	draw_circle(center, 3.8, Color("eafcf4"))


func _draw_sentient_ghost() -> void:
	var center: Vector2 = player.position
	center.y += sin(animation_clock * 8.0) * 1.6
	var scale_factor := 1.0
	if game_state == &"dying":
		scale_factor = clampf(death_timer / 0.85, 0.1, 1.0)

	draw_circle(center, 15.0 * scale_factor, Color(0.45, 0.95, 1.0, 0.16))
	draw_arc(center + Vector2(0, -15.5) * scale_factor, 5.5 * scale_factor, 0.0, TAU, 24, Color("fce046"), 1.6, true)

	var body := PackedVector2Array([
		center + Vector2(-12, 10) * scale_factor,
		center + Vector2(-12, -2) * scale_factor,
		center + Vector2(-9, -9) * scale_factor,
		center + Vector2(-4, -12) * scale_factor,
		center + Vector2(4, -12) * scale_factor,
		center + Vector2(9, -9) * scale_factor,
		center + Vector2(12, -2) * scale_factor,
		center + Vector2(12, 10) * scale_factor,
		center + Vector2(7, 6) * scale_factor,
		center + Vector2(2, 10) * scale_factor,
		center + Vector2(-2, 10) * scale_factor,
		center + Vector2(-7, 6) * scale_factor,
	])
	draw_colored_polygon(body, Color("7ce8ff"))

	var look := Vector2(player.facing) * 1.6
	draw_circle(center + Vector2(-4.2, -2.5) * scale_factor, 3.6 * scale_factor, Color("ffffff"))
	draw_circle(center + Vector2(4.2, -2.5) * scale_factor, 3.6 * scale_factor, Color("ffffff"))
	draw_circle(center + (Vector2(-4.2, -2.5) + look) * scale_factor, 1.8 * scale_factor, Color("101829"))
	draw_circle(center + (Vector2(4.2, -2.5) + look) * scale_factor, 1.8 * scale_factor, Color("101829"))


func _draw_pursuer() -> void:
	var center: Vector2 = ghost.position
	if level == 1:
		_draw_pacman_enemy(center)
	elif level == 2:
		_draw_scooby_enemy(center)
	else:
		_draw_luigi_enemy(center)

	if ghost.ai_state == &"DISTRACTED":
		var ratio := clampf(ghost.state_clock / ghost.distraction_duration, 0.0, 1.0)
		draw_arc(center + Vector2(0, -19), 6.5, -PI * 0.5, -PI * 0.5 + TAU * ratio, 24, Color("6bff95"), 2.5, true)


func _draw_pacman_enemy(center: Vector2) -> void:
	var radius := 13.0
	var mouth_open := 0.12 + 0.26 * absf(sin(animation_clock * 11.0))
	var facing_angle: float = ghost.facing_vector.angle()
	var start_angle := facing_angle + mouth_open * PI
	var end_angle := facing_angle + TAU - mouth_open * PI
	var points := PackedVector2Array([center])
	var steps := 24
	for i in range(steps + 1):
		var ang := lerpf(start_angle, end_angle, float(i) / float(steps))
		points.append(center + Vector2(cos(ang), sin(ang)) * radius)
	draw_colored_polygon(points, Color("f8ca16"))
	var eye_ang := facing_angle - 0.9 if cos(facing_angle) >= -0.1 else facing_angle + 0.9
	draw_circle(center + Vector2(cos(eye_ang), sin(eye_ang)) * 6.5, 2.0, Color("121926"))


func _draw_scooby_enemy(center: Vector2) -> void:
	draw_circle(center + Vector2(-11, -3), 5.0, Color("763610"))
	draw_circle(center + Vector2(11, -3), 5.0, Color("763610"))
	draw_circle(center, 11.5, Color("b2540a"))
	draw_circle(center + Vector2(0, 4), 6.5, Color("d87608"))
	draw_circle(center + Vector2(0, 2.5), 2.8, Color("121926"))
	draw_circle(center + Vector2(-4, -3.5), 2.8, Color("ffffff"))
	draw_circle(center + Vector2(4, -3.5), 2.8, Color("ffffff"))
	draw_circle(center + Vector2(-4, -3.5), 1.4, Color("121926"))
	draw_circle(center + Vector2(4, -3.5), 1.4, Color("121926"))
	draw_line(center + Vector2(-8, 10), center + Vector2(8, 10), Color("16b6a4"), 3.0)
	draw_circle(center + Vector2(0, 13), 3.2, Color("f8ca16"))


func _draw_luigi_enemy(center: Vector2) -> void:
	draw_circle(center + Vector2(0, 1), 10.5, Color("fcd6a8"))
	draw_arc(center + Vector2(0, -3), 10.5, PI, TAU, 20, Color("18a148"), 7.0, true)
	var brim_dir: Vector2 = ghost.facing_vector.normalized() * 5.0
	draw_line(center + Vector2(-9, -4) + brim_dir * 0.4, center + Vector2(9, -4) + brim_dir * 0.4, Color("167e3c"), 3.5)
	draw_circle(center + Vector2(-3.5, 0), 1.8, Color("121926"))
	draw_circle(center + Vector2(3.5, 0), 1.8, Color("121926"))
	draw_line(center + Vector2(-6, 4.5), center + Vector2(6, 4.5), Color("461b04"), 2.6)
	var hand_pos: Vector2 = center + ghost.facing_vector.normalized() * 11.0
	draw_circle(hand_pos, 3.2, Color("92a2b6"))
	draw_circle(hand_pos, 1.8, Color("fcf088"))


# draw A* path and velocity vector when F3 debug mode is enabled
func _draw_debug_ai_gizmos() -> void:
	if ghost == null or maze == null:
		return
	for i in range(ghost.route.size() - 1):
		var a: Vector2 = maze.cell_center(ghost.route[i])
		var b: Vector2 = maze.cell_center(ghost.route[i + 1])
		draw_line(a, b, Color(1.0, 0.35, 0.55, 0.65), 2.0)
	if ghost.desired_velocity.length() > 1.0:
		draw_line(ghost.position, ghost.position + ghost.desired_velocity * 0.25, Color("3abef6"), 2.2)


func _draw_particles() -> void:
	for particle in particles:
		var color: Color = particle["color"]
		color.a = clampf(float(particle["life"]) * 2.2, 0.0, 1.0)
		draw_circle(particle["position"], 2.2, color)
