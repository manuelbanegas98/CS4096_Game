extends RefCounted
class_name MazeGrid

const WALL := 0
const FLOOR := 1

signal crystal_collected(cell: Vector2i)

var width := 19
var height := 15
var tile_size := 32
var origin := Vector2(176, 96)
var tiles: Array = []
var crystals: Dictionary = {}
var distractions: Dictionary = {}
var player_start := Vector2i(1, 1)
var ghost_home := Vector2i(9, 7)
var total_crystals := 5
var portal_active := false
var portal_tile := Vector2i(-1, -1)


func build(level: int) -> void:
	tiles.clear()
	crystals.clear()
	distractions.clear()
	portal_active = false
	portal_tile = Vector2i(-1, -1)

	for y in range(height):
		var row: Array[int] = []
		for x in range(width):
			row.append(WALL if x == 0 or y == 0 or x == width - 1 or y == height - 1 else FLOOR)
		tiles.append(row)

	var layout_index := posmod(level - 1, 3) + 1
	if layout_index == 1:
		_build_level_1_arcade()
	elif layout_index == 2:
		_build_level_2_castle()
	else:
		_build_level_3_mansion()

	# keep center spawn area and portal exits clear
	for y in range(6, 9):
		for x in range(8, 11):
			_set_floor(Vector2i(x, y))
	for open_cell in [
		Vector2i(9, 5), Vector2i(9, 9), Vector2i(7, 7), Vector2i(11, 7),
		Vector2i(9, 1), Vector2i(9, 13), Vector2i(1, 7), Vector2i(17, 7),
	]:
		_set_floor(open_cell)

	var crystal_cells: Array[Vector2i] = [
		Vector2i(17, 1),
		Vector2i(1, 13),
		Vector2i(17, 13),
		Vector2i(9, 2),
		Vector2i(9, 12),
	]
	for cell in crystal_cells:
		_set_floor(cell)

	_set_floor(player_start)
	_set_floor(ghost_home)
	_ensure_connected(player_start)

	total_crystals = crystal_cells.size()
	for cell in crystal_cells:
		crystals[cell] = true


func _build_level_1_arcade() -> void:
	var horizontal_bars := [
		{"y": 3, "holes": [1, 5, 9, 13, 17]},
		{"y": 6, "holes": [3, 7, 9, 11, 15]},
		{"y": 8, "holes": [3, 7, 9, 11, 15]},
		{"y": 11, "holes": [1, 5, 9, 13, 17]},
	]
	for bar in horizontal_bars:
		for x in range(2, width - 2):
			if not bar["holes"].has(x):
				_set_wall(Vector2i(x, bar["y"]))

	var vertical_bars := [
		{"x": 4, "holes": [1, 4, 7, 10, 13]},
		{"x": 14, "holes": [1, 4, 7, 10, 13]},
	]
	for bar in vertical_bars:
		for y in range(2, height - 2):
			if not bar["holes"].has(y):
				_set_wall(Vector2i(bar["x"], y))


func _build_level_2_castle() -> void:
	for x in [3, 5, 13, 15]:
		for y in [2, 3, 4, 10, 11, 12]:
			_set_wall(Vector2i(x, y))
		_set_floor(Vector2i(x, 3))
		_set_floor(Vector2i(x, 11))

	for x in range(6, 13):
		if x != 9:
			_set_wall(Vector2i(x, 4))
			_set_wall(Vector2i(x, 10))

	for y in [5, 6, 8, 9]:
		_set_wall(Vector2i(6, y))
		_set_wall(Vector2i(12, y))

	for x in [2, 3, 15, 16]:
		_set_wall(Vector2i(x, 6))
		_set_wall(Vector2i(x, 8))


func _build_level_3_mansion() -> void:
	for y in [2, 4, 10, 12]:
		for x in range(2, width - 2):
			if not [4, 9, 14].has(x):
				_set_wall(Vector2i(x, y))

	for x in [3, 6, 12, 15]:
		for y in [6, 7, 8]:
			if y != 7:
				_set_wall(Vector2i(x, y))

	for x in [6, 12]:
		_set_wall(Vector2i(x, 3))
		_set_wall(Vector2i(x, 11))


# pick the edge portal farthest from the enemy's current position
func spawn_escape_portal(avoid_cell: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if portal_active:
		return portal_tile
	var candidates := [
		{"edge": Vector2i(18, 7), "access": Vector2i(17, 7)},
		{"edge": Vector2i(9, 0), "access": Vector2i(9, 1)},
		{"edge": Vector2i(9, 14), "access": Vector2i(9, 13)},
		{"edge": Vector2i(0, 7), "access": Vector2i(1, 7)},
	]
	var best_edge := Vector2i(18, 7)
	var best_dist := -1
	for entry in candidates:
		var edge: Vector2i = entry["edge"]
		var access: Vector2i = entry["access"]
		_set_floor(access)
		var dist := _manhattan(access, avoid_cell) if avoid_cell != Vector2i(-1, -1) else 10
		if dist > best_dist:
			best_dist = dist
			best_edge = edge
	portal_tile = best_edge
	_set_floor(portal_tile)
	portal_active = true
	return portal_tile


func place_distraction(cell: Vector2i, kind: StringName) -> bool:
	if not is_open(cell) or distractions.has(cell) or cell == portal_tile:
		return false
	distractions[cell] = {"tile": cell, "kind": kind}
	return true


func consume_distraction(cell: Vector2i) -> void:
	distractions.erase(cell)


func get_nearest_distraction(from_cell: Vector2i, max_radius: float = INF) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_dist := INF
	for cell in distractions:
		var d := float(_manhattan(from_cell, cell))
		if d <= max_radius and d < best_dist:
			best_dist = d
			best_cell = cell
	return best_cell


func collect_at(cell: Vector2i) -> bool:
	if not crystals.has(cell):
		return false
	crystals.erase(cell)
	crystal_collected.emit(cell)
	return true


# make sure no open tiles are completely walled off from player_start
func _ensure_connected(start: Vector2i) -> void:
	var reachable := _reachable_cells(start)
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var cell := Vector2i(x, y)
			if not is_open(cell) or reachable.has(cell):
				continue
			var cursor := cell
			while cursor.y > 1 and not reachable.has(cursor):
				cursor = Vector2i(cursor.x, cursor.y - 1)
				_set_floor(cursor)
			if not reachable.has(cursor):
				_set_floor(cursor)
			reachable = _reachable_cells(start)


func _reachable_cells(start: Vector2i) -> Dictionary:
	var reachable: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for neighbor in open_neighbors(current):
			if not reachable.has(neighbor):
				reachable[neighbor] = true
				frontier.append(neighbor)
	return reachable


func _set_wall(cell: Vector2i) -> void:
	if _inside(cell):
		tiles[cell.y][cell.x] = WALL


func _set_floor(cell: Vector2i) -> void:
	if _inside(cell):
		tiles[cell.y][cell.x] = FLOOR


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_open(cell: Vector2i) -> bool:
	return _inside(cell) and tiles[cell.y][cell.x] == FLOOR


func cell_center(cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local := (world_pos - origin) / float(tile_size)
	return Vector2i(floori(local.x), floori(local.y))


func open_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for step in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var candidate: Vector2i = cell + step
		if is_open(candidate):
			result.append(candidate)
	return result


# A* pathfinding on the tile grid using Manhattan distance heuristic
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_open(start) or not is_open(goal):
		return result
	if start == goal:
		result.append(start)
		return result

	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var cost_so_far: Dictionary = {start: 0}
	var estimated_total: Dictionary = {start: _manhattan(start, goal)}
	var visited: Dictionary = {}
	while not frontier.is_empty():
		var best_index := 0
		var best_score := float(estimated_total.get(frontier[0], INF))
		for index in range(1, frontier.size()):
			var score := float(estimated_total.get(frontier[index], INF))
			if score < best_score:
				best_score = score
				best_index = index
		var current: Vector2i = frontier.pop_at(best_index)
		if current == goal:
			var step := goal
			result.append(step)
			while step != start:
				step = came_from[step]
				result.push_front(step)
			return result
		visited[current] = true
		for neighbor in open_neighbors(current):
			if visited.has(neighbor):
				continue
			var new_cost := int(cost_so_far[current]) + 1
			if not cost_so_far.has(neighbor) or new_cost < int(cost_so_far[neighbor]):
				came_from[neighbor] = current
				cost_so_far[neighbor] = new_cost
				estimated_total[neighbor] = new_cost + _manhattan(neighbor, goal)
				if not frontier.has(neighbor):
					frontier.append(neighbor)
	return result


# step along the segment to check if any wall blocks line of sight
func has_ray_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
	var diff := to_pos - from_pos
	var distance := diff.length()
	if distance <= 1.0:
		return true
	var steps := maxi(4, int(ceil(distance / (float(tile_size) * 0.25))))
	for i in range(1, steps):
		var sample := from_pos.lerp(to_pos, float(i) / float(steps))
		var cell := world_to_cell(sample)
		if not is_open(cell):
			return false
	return true


func _manhattan(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)
