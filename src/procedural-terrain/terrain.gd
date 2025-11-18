extends Node3D
class_name Terrain

var image_name = "Vällen"

@export var height_map_path: String = "res://maps/heightmaps/" + image_name + ".png"
@export var water_map_path: String = "res://maps/watermaps/" + image_name + ".png"
@export var terrain_scale: float = 1.0  # Scale factor for terrain size (1.0 = 1 unit per pixel)
@export var height_scale: float = 20.0    # How much to scale height values
@export var resolution: int = 256        # Mesh resolution (vertices per side)

var height_map: Image
var water_map: Image

func _ready():
	load_maps()
	create_terrain()

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
	
	# Calculate terrain dimensions based on image size, maintaining aspect ratio
	var terrain_size_x = map_size.x * terrain_scale
	var terrain_size_z = map_size.y * terrain_scale
	
	print("Terrain dimensions: ", terrain_size_x, " x ", terrain_size_z, " units")
	
	# Generate vertices
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			# Get UV coordinates (0-1)
			var u = float(x) / resolution
			var v = float(z) / resolution
			
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
	for z in range(resolution):
		for x in range(resolution):
			var i = z * (resolution + 1) + x
			
			# First triangle
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + resolution + 1)
			
			# Second triangle
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + resolution + 2)
			surface_tool.add_index(i + resolution + 1)
	
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
	
	print("Terrain created with ", resolution + 1, "x", resolution + 1, " vertices")
