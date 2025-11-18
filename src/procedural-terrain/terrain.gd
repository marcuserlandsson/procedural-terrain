extends Node3D
class_name Terrain

var image_name = "Aborrvattnet"

@export var height_map_path: String = "res://maps/heightmaps/" + image_name + ".png"
@export var water_map_path: String = "res://maps/watermaps/" + image_name + ".png"
@export var terrain_scale: float = 1.0  # Scale factor for terrain size (1.0 = 1 unit per pixel)
@export var height_scale: float = 20.0    # How much to scale height values
@export var resolution: int = -1        # Mesh resolution (vertices per side). -1 = match image size

var height_map: Image
var water_map: Image
var actual_resolution: int = 256

func _ready():
	load_maps()
	create_terrain()
	if water_map:
		create_water()

func load_maps():
	# Load height map
	if ResourceLoader.exists(height_map_path):
		var texture = load(height_map_path) as Texture2D
		if texture:
			height_map = texture.get_image()
			print("Loaded height map: ", height_map_path)
			print("  Size: ", height_map.get_size())
		else:
			push_error("Failed to load height map: " + height_map_path)
	else:
		push_error("Height map not found: " + height_map_path)
	
	# Load water map
	if ResourceLoader.exists(water_map_path):
		var texture = load(water_map_path) as Texture2D
		if texture:
			water_map = texture.get_image()
			print("Loaded water map: ", water_map_path)
			print("  Size: ", water_map.get_size())
		else:
			push_error("Failed to load water map: " + water_map_path)
	else:
		push_warning("Water map not found: " + water_map_path)

func create_terrain():
	if not height_map:
		push_error("No height map loaded!")
		return
	
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var map_size = height_map.get_size()
	
	# Set resolution to match image if not specified
	if resolution <= 0:
		actual_resolution = max(map_size.x, map_size.y)
		print("Resolution set to match image: ", actual_resolution)
	else:
		actual_resolution = resolution
		print("Using custom resolution: ", actual_resolution)
	
	# Calculate terrain dimensions based on image size, maintaining aspect ratio
	var terrain_size_x = map_size.x * terrain_scale
	var terrain_size_z = map_size.y * terrain_scale
	
	print("Terrain dimensions: ", terrain_size_x, " x ", terrain_size_z, " units")
	
	# Generate vertices
	for z in range(actual_resolution + 1):
		for x in range(actual_resolution + 1):
			# Get UV coordinates (0-1)
			var u = float(x) / actual_resolution
			var v = float(z) / actual_resolution
			
			# Sample height map
			var pixel_x = int(u * map_size.x)
			var pixel_y = int(v * map_size.y)
			pixel_x = clamp(pixel_x, 0, map_size.x - 1)
			pixel_y = clamp(pixel_y, 0, map_size.y - 1)
			
			var height_value = height_map.get_pixel(pixel_x, pixel_y).r
			var height = height_value * height_scale
			
			# Calculate world position (centered at origin)
			var pos_x = (u - 0.5) * terrain_size_x
			var pos_z = (v - 0.5) * terrain_size_z
			var pos_y = height
			
			# Add vertex
			surface_tool.set_uv(Vector2(u, v))
			surface_tool.add_vertex(Vector3(pos_x, pos_y, pos_z))
	
	# Generate indices for triangles (reversed winding order to face up)
	for z in range(actual_resolution):
		for x in range(actual_resolution):
			var i = z * (actual_resolution + 1) + x
			
			# First triangle
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + actual_resolution + 1)
			
			# Second triangle
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + actual_resolution + 2)
			surface_tool.add_index(i + actual_resolution + 1)
	
	# Generate normals
	surface_tool.generate_normals()
	
	# Create mesh
	var mesh = surface_tool.commit()
	mesh_instance.mesh = mesh
	
	# Create a simple material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.6, 0.3)  # Green terrain color
	material.roughness = 0.8
	mesh_instance.set_surface_override_material(0, material)
	
	print("Terrain created with ", actual_resolution + 1, "x", actual_resolution + 1, " vertices")

func create_water():
	if not water_map or not height_map:
		return
	
	# Calculate water level based on shoreline height (land adjacent to water)
	var map_size = height_map.get_size()
	var shoreline_heights = []
	
	# Find shoreline pixels: land pixels that are adjacent to water
	for y in range(map_size.y):
		for x in range(map_size.x):
			var water_pixel = water_map.get_pixel(x, y)
			var is_water = water_pixel.r > 0.5
			
			# If this is land, check if it's adjacent to water
			if not is_water:
				var adjacent_to_water = false
				# Check 4 neighbors (up, down, left, right)
				var neighbors = [
					Vector2i(x, y - 1),  # Up
					Vector2i(x, y + 1),  # Down
					Vector2i(x - 1, y),  # Left
					Vector2i(x + 1, y)   # Right
				]
				
				for neighbor in neighbors:
					if neighbor.x >= 0 and neighbor.x < map_size.x and neighbor.y >= 0 and neighbor.y < map_size.y:
						var neighbor_pixel = water_map.get_pixel(neighbor.x, neighbor.y)
						if neighbor_pixel.r > 0.5:  # Neighbor is water
							adjacent_to_water = true
							break
				
				# If this land pixel is on the shoreline, record its height
				if adjacent_to_water:
					var height_value = height_map.get_pixel(x, y).r
					shoreline_heights.append(height_value * height_scale)
	
	var water_level: float = 0.0
	
	if shoreline_heights.is_empty():
		print("No shoreline found in water map, using minimum water area height")
		# Fallback: use minimum height of water areas
		var water_heights = []
		for y in range(map_size.y):
			for x in range(map_size.x):
				var water_pixel = water_map.get_pixel(x, y)
				if water_pixel.r > 0.5:
					var height_value = height_map.get_pixel(x, y).r
					water_heights.append(height_value * height_scale)
		if water_heights.is_empty():
			print("No water areas found in water map")
			return
		var min_height = water_heights[0]
		for h in water_heights:
			if h < min_height:
				min_height = h
		water_level = min_height
		print("Water level set to: ", water_level, " (fallback)")
	else:
		# Calculate average shoreline height
		for h in shoreline_heights:
			water_level += h
		water_level /= shoreline_heights.size()
		print("Water level set to: ", water_level, " (based on ", shoreline_heights.size(), " shoreline pixels)")
	
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var terrain_size_x = map_size.x * terrain_scale
	var terrain_size_z = map_size.y * terrain_scale
	
	# Generate vertices for water (flat surface at constant level)
	for z in range(actual_resolution + 1):
		for x in range(actual_resolution + 1):
			# Get UV coordinates (0-1)
			var u = float(x) / actual_resolution
			var v = float(z) / actual_resolution
			
			# Sample water map to check if this area has water
			var pixel_x = int(u * map_size.x)
			var pixel_y = int(v * map_size.y)
			pixel_x = clamp(pixel_x, 0, map_size.x - 1)
			pixel_y = clamp(pixel_y, 0, map_size.y - 1)
			
			var water_pixel = water_map.get_pixel(pixel_x, pixel_y)
			var has_water = water_pixel.r > 0.5  # White = water
			
			# Calculate world position
			var pos_x = (u - 0.5) * terrain_size_x
			var pos_z = (v - 0.5) * terrain_size_z
			# Use constant water level, or place below terrain if no water
			var pos_y = water_level if has_water else water_level - 10.0
			
			# Add vertex
			surface_tool.set_uv(Vector2(u, v))
			surface_tool.add_vertex(Vector3(pos_x, pos_y, pos_z))
	
	# Generate indices for triangles (same as terrain)
	for z in range(actual_resolution):
		for x in range(actual_resolution):
			var i = z * (actual_resolution + 1) + x
			
			# First triangle
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + actual_resolution + 1)
			
			# Second triangle
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + actual_resolution + 2)
			surface_tool.add_index(i + actual_resolution + 1)
	
	# Generate normals
	surface_tool.generate_normals()
	
	# Create mesh
	var mesh = surface_tool.commit()
	mesh_instance.mesh = mesh
	
	# Create water material (blue, semi-transparent)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.4, 0.8, 0.7)  # Blue water color with transparency
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1  # Shiny water
	material.metallic = 0.1
	mesh_instance.set_surface_override_material(0, material)
	
	print("Water mesh created")
