extends "res://grid_mover.gd"
class_name HunterGhost

# FSM states
const PATROL: StringName = &"PATROL"
const CHASE: StringName = &"CHASE"
const PURSUIT: StringName = &"PURSUIT"
const SEARCH: StringName = &"SEARCH"
const SEEK_DISTRACTION: StringName = &"SEEK_BAIT"
const DISTRACTED: StringName = &"DISTRACTED"

# Enemy type per level
const ENEMY_PACMAN := 1
const ENEMY_SCOOBY := 2
const ENEMY_LUIGI := 3

@export var base_speed := 112.0
@export var prediction_distance := 2.0
@export var distraction_duration := 2.0
@export var search_duration := 1.8
@export var scent_radius_tiles := 9.5
@export var vision_range_tiles := 8.5
@export var vision_fov_degrees := 78.0

var ai_state: StringName = PATROL
var enemy_type: int = ENEMY_PACMAN
var home_tile := Vector2i(9, 7)
var route: Array[Vector2i] = []
var state_clock := 0.0
var scent_update_clock := 0.0
var last_seen_tile := Vector2i(1, 1)
var patrol_target := Vector2i(1, 1)
var distraction_target := Vector2i(-1, -1)
var prediction_tiles := 0
var facing_vector := Vector2.LEFT

# cached refs for when we enter a new tile mid-frame
var _cached_maze = null
var _cached_player_tile := Vector2i(1, 1)
var _cached_player_dir := Vector2i.ZERO

# steering vectors
var current_velocity := Vector2.ZERO
var desired_velocity := Vector2.ZERO
var steering_force := Vector2.ZERO
var last_dot_product := 0.0
var player_perceived := false


func _init() -> void:
	tile_entered.connect(_on_tile_entered_step)


func setup(start: Vector2i, maze, level: int = 1) -> void:
	super.setup(start, maze)
	_cached_maze = maze
	home_tile = start
	enemy_type = clampi(level, 1, 3)
	ai_state = PURSUIT if enemy_type == ENEMY_PACMAN else PATROL
	route.clear()
	state_clock = 0.0
	scent_update_clock = 0.0
	last_seen_tile = maze.player_start
	patrol_target = maze.player_start
	distraction_target = Vector2i(-1, -1)
	facing_vector = Vector2.LEFT
	current_velocity = Vector2.ZERO
	desired_velocity = Vector2.ZERO
	steering_force = Vector2.ZERO


func reset_ai(maze, level: int = 1) -> void:
	setup(home_tile, maze, level)


func get_enemy_name() -> String:
	if enemy_type == ENEMY_PACMAN:
		return "PAC-MAN"
	elif enemy_type == ENEMY_SCOOBY:
		return "SCOOBY-DOO"
	return "LUIGI"


func update_brain(delta: float, maze, player_tile: Vector2i, player_direction: Vector2i, level: int) -> void:
	_cached_maze = maze
	_cached_player_tile = player_tile
	_cached_player_dir = player_direction
	enemy_type = clampi(level, 1, 3)

	if direction != Vector2i.ZERO:
		facing_vector = Vector2(direction).normalized()

	# wait out distraction timer before going back to patrol
	if ai_state == DISTRACTED:
		state_clock -= delta
		current_velocity = Vector2.ZERO
		desired_velocity = Vector2.ZERO
		steering_force = Vector2.ZERO
		if state_clock <= 0.0:
			if distraction_target != Vector2i(-1, -1):
				maze.consume_distraction(distraction_target)
				distraction_target = Vector2i(-1, -1)
			ai_state = PATROL
			route.clear()
		return

	# check if player dropped bait on the map
	var detected_bait: Vector2i = _perceive_distraction(maze)
	if detected_bait != Vector2i(-1, -1):
		distraction_target = detected_bait
		if tile == distraction_target and progress <= 0.05:
			ai_state = DISTRACTED
			state_clock = distraction_duration
			route.clear()
			return
		elif ai_state != SEEK_DISTRACTION:
			ai_state = SEEK_DISTRACTION
			_recalculate_route(maze, player_tile, player_direction)
	elif ai_state == SEEK_DISTRACTION:
		distraction_target = Vector2i(-1, -1)
		ai_state = PURSUIT if enemy_type == ENEMY_PACMAN else PATROL

	# update perception and state transitions if not going after bait
	if ai_state != SEEK_DISTRACTION:
		player_perceived = _perceive_player(maze, player_tile)
		if enemy_type == ENEMY_PACMAN:
			ai_state = PURSUIT
			last_seen_tile = player_tile
		elif enemy_type == ENEMY_SCOOBY:
			if player_perceived:
				last_seen_tile = player_tile
				ai_state = CHASE
			elif ai_state == CHASE:
				ai_state = SEARCH
				state_clock = search_duration
			else:
				scent_update_clock -= delta
				if scent_update_clock <= 0.0:
					last_seen_tile = player_tile
					patrol_target = player_tile
					scent_update_clock = 0.85
		else:
			if player_perceived:
				last_seen_tile = player_tile
				ai_state = CHASE
			elif ai_state == CHASE:
				ai_state = SEARCH
				state_clock = search_duration
			else:
				scent_update_clock -= delta
				if scent_update_clock <= 0.0:
					patrol_target = player_tile
					scent_update_clock = 0.9

	# if searching and timer runs out (or reached last seen spot), go back to patrol
	if ai_state == SEARCH:
		state_clock -= delta
		if state_clock <= 0.0 or (tile == last_seen_tile and progress <= 0.02):
			ai_state = PATROL
			patrol_target = player_tile

	# rebuild A* path and queue next step
	_recalculate_route(maze, player_tile, player_direction)
	_queue_next_route_step()

	# update steering velocity and move along grid
	var move_speed := _compute_steering_speed(maze)
	var move_dir := Vector2(direction) if direction != Vector2i.ZERO else facing_vector
	desired_velocity = move_dir * move_speed
	steering_force = desired_velocity - current_velocity
	current_velocity = desired_velocity

	advance(delta, move_speed, maze)

	if ai_state == SEEK_DISTRACTION and distraction_target != Vector2i(-1, -1) and tile == distraction_target:
		ai_state = DISTRACTED
		state_clock = distraction_duration
		route.clear()


func _on_tile_entered_step(_new_tile: Vector2i) -> void:
	if _cached_maze == null or ai_state == DISTRACTED:
		return
	_recalculate_route(_cached_maze, _cached_player_tile, _cached_player_dir)
	_queue_next_route_step()


func _queue_next_route_step() -> void:
	while route.size() > 1 and route[0] != tile:
		route.pop_front()
	if route.size() > 1:
		var step_dir: Vector2i = route[1] - tile
		if step_dir != Vector2i.ZERO:
			queue_direction(step_dir)


func _perceive_distraction(maze) -> Vector2i:
	if maze.distractions.is_empty():
		return Vector2i(-1, -1)
	return maze.get_nearest_distraction(tile, 40.0)


func _perceive_player(maze, player_tile: Vector2i) -> bool:
	var player_pos: Vector2 = maze.cell_center(player_tile)
	if enemy_type == ENEMY_PACMAN:
		return true
	elif enemy_type == ENEMY_SCOOBY:
		# Scooby detects player within scent radius (distance squared)
		var max_dist := scent_radius_tiles * float(maze.tile_size)
		return position.distance_squared_to(player_pos) <= max_dist * max_dist
	else:
		# Luigi uses flashlight vision cone + line of sight
		return _is_in_vision_cone(maze, player_pos, vision_range_tiles)


func _is_in_vision_cone(maze, target_pos: Vector2, range_tiles: float) -> bool:
	var to_target := target_pos - position
	var max_dist := range_tiles * float(maze.tile_size)
	var dist_sq := to_target.length_squared()
	if dist_sq <= float(maze.tile_size * maze.tile_size) * 2.25:
		last_dot_product = 1.0
		return maze.has_ray_line_of_sight(position, target_pos)
	if dist_sq > max_dist * max_dist:
		last_dot_product = -1.0
		return false
	# check angle using dot product against facing direction
	var dir_to_target := to_target.normalized()
	var forward := facing_vector.normalized()
	last_dot_product = forward.dot(dir_to_target)
	var half_angle_rad := deg_to_rad(vision_fov_degrees * 0.5)
	if last_dot_product < cos(half_angle_rad):
		return false
	# make sure walls don't block view
	return maze.has_ray_line_of_sight(position, target_pos)


func _compute_steering_speed(maze) -> float:
	var max_speed := base_speed
	if enemy_type == ENEMY_PACMAN:
		max_speed = base_speed * 1.04
	elif enemy_type == ENEMY_SCOOBY:
		max_speed = base_speed * 1.06 if ai_state == CHASE or ai_state == SEEK_DISTRACTION else base_speed * 0.94
		# arrive behavior: slow down when getting close to the snack
		if ai_state == SEEK_DISTRACTION and distraction_target != Vector2i(-1, -1):
			var target_pos: Vector2 = maze.cell_center(distraction_target)
			var distance := position.distance_to(target_pos)
			var slowing_radius := float(maze.tile_size) * 2.5
			var arrive_factor := clampf(distance / slowing_radius, 0.45, 1.0)
			max_speed *= arrive_factor
	elif enemy_type == ENEMY_LUIGI:
		if ai_state == CHASE:
			max_speed = base_speed * 1.12
		elif ai_state == SEARCH:
			max_speed = base_speed * 0.92
		else:
			max_speed = base_speed * 0.95
	return max_speed


func _recalculate_route(maze, player_tile: Vector2i, player_direction: Vector2i) -> void:
	var target := player_tile
	prediction_tiles = 0

	if ai_state == SEEK_DISTRACTION and distraction_target != Vector2i(-1, -1):
		target = distraction_target
	elif ai_state == PURSUIT:
		target = _predicted_tile(maze, player_tile, player_direction)
	elif ai_state == CHASE:
		target = player_tile
	elif ai_state == SEARCH:
		target = last_seen_tile
	else:
		if not maze.is_open(patrol_target) or patrol_target == tile:
			patrol_target = player_tile
		target = patrol_target

	route = maze.find_path(tile, target)
	if route.is_empty():
		route = maze.find_path(tile, player_tile)


func _predicted_tile(maze, player_tile: Vector2i, player_direction: Vector2i) -> Vector2i:
	var dist: int = maze._manhattan(tile, player_tile)
	if player_direction == Vector2i.ZERO or dist <= 3 or dist > 6:
		prediction_tiles = 0
		return player_tile
	var lookahead := clampi(roundi(prediction_distance), 1, 2)
	prediction_tiles = lookahead
	var predicted := player_tile
	for _step in range(lookahead):
		var next_cell: Vector2i = predicted + player_direction
		if not maze.is_open(next_cell):
			break
		predicted = next_cell
	return predicted


func path_length() -> int:
	return maxi(0, route.size() - 1)
