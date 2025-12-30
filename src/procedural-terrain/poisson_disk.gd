extends RefCounted
class_name PoissonDisk

# Poisson Disk Distribution generator for position tiles
# Ensures minimum distance between positions

static func generate(tile_size: Vector2i, min_distance: float, max_attempts: int = 30, rng: RandomNumberGenerator = null) -> Array[Vector2]:
	# Bridson's algorithm for Poisson Disk Sampling
	var points: Array[Vector2] = []
	var active_list: Array[Vector2] = []
	
	# Use provided RNG or create a new one
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	
	# Grid for spatial hashing (cell size = min_distance / sqrt(2))
	var cell_size := min_distance / sqrt(2.0)
	var grid_width := int(ceil(float(tile_size.x) / cell_size))
	var grid_height := int(ceil(float(tile_size.y) / cell_size))
	var grid: Array[Array] = []
	
	# Initialize grid
	for i in range(grid_width):
		grid.append([])
		for j in range(grid_height):
			grid[i].append(null)
	
	# Helper function to get grid cell
	var get_grid_cell = func(pos: Vector2) -> Vector2i:
		return Vector2i(int(pos.x / cell_size), int(pos.y / cell_size))
	
	# Helper function to check if point is valid
	var is_valid = func(pos: Vector2) -> bool:
		if pos.x < 0 or pos.x >= tile_size.x or pos.y < 0 or pos.y >= tile_size.y:
			return false
		
		var cell: Vector2i = get_grid_cell.call(pos) as Vector2i
		var search_radius: int = 2
		
		# Check neighboring cells
		for i in range(max(0, cell.x - search_radius), min(grid_width, cell.x + search_radius + 1)):
			for j in range(max(0, cell.y - search_radius), min(grid_height, cell.y + search_radius + 1)):
				var existing: Variant = grid[i][j]
				if existing != null:
					var dist: float = pos.distance_to(existing as Vector2)
					if dist < min_distance:
						return false
		
		return true
	
	# Start with a random point
	var first_point := Vector2(
		rng.randf() * tile_size.x,
		rng.randf() * tile_size.y
	)
	points.append(first_point)
	active_list.append(first_point)
	
	var first_cell: Vector2i = get_grid_cell.call(first_point) as Vector2i
	grid[first_cell.x][first_cell.y] = first_point
	
	# Generate points
	while active_list.size() > 0:
		var random_index := rng.randi() % active_list.size()
		var center := active_list[random_index]
		var found := false
		
		# Try to find a valid point around center
		for attempt in range(max_attempts):
			# Random angle and radius
			var angle := rng.randf() * TAU
			var radius := min_distance + rng.randf() * min_distance  # Between min_distance and 2*min_distance
			var candidate := center + Vector2(cos(angle), sin(angle)) * radius
			
			if is_valid.call(candidate):
				points.append(candidate)
				active_list.append(candidate)
				found = true
				
				var cell: Vector2i = get_grid_cell.call(candidate) as Vector2i
				grid[cell.x][cell.y] = candidate
				break
		
		# Remove center from active list if no valid point found
		if not found:
			active_list.remove_at(random_index)
	
	return points
