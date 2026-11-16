extends "res://grid_mover.gd"
class_name MazePlayer

@export var player_speed := 142.0

var max_distractions := 3
var distractions_left := 3
var facing := Vector2i.RIGHT


func setup(start: Vector2i, maze) -> void:
	super.setup(start, maze)
	facing = Vector2i.RIGHT


func reset_distractions() -> void:
	distractions_left = max_distractions


func set_movement_input(next_direction: Vector2i) -> void:
	queue_direction(next_direction)
	if next_direction != Vector2i.ZERO:
		facing = next_direction


func move_player(delta: float, maze) -> void:
	advance(delta, player_speed, maze)
	if direction != Vector2i.ZERO:
		facing = direction


# each level uses a different bait item to distract the enemy
func get_distraction_kind(level: int) -> StringName:
	if level == 1:
		return &"cherries"
	elif level == 2:
		return &"scooby_snack"
	return &"ghost_dummy"


func get_distraction_label(level: int) -> String:
	if level == 1:
		return "POWER CHERRIES"
	elif level == 2:
		return "SCOOBY SNACKS"
	return "GHOST DUMMY"


func try_drop_distraction(maze, level: int) -> bool:
	if distractions_left <= 0:
		return false
	var kind := get_distraction_kind(level)
	if maze.place_distraction(tile, kind):
		distractions_left -= 1
		return true
	return false
