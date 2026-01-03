extends Node3D
class_name PlantRenderer

# Simple plant renderer using basic shapes (cylinders, spheres, etc.)
# Phase 5: Basic rendering before proper 3D models

@export var render_plants: bool = true  # Enable/disable rendering

# Shape types for different plant types
enum ShapeType {
	CYLINDER,  # For trees
	SPHERE,    # For shrubs/bushes
	CUBE,      # For ground plants
	CYLINDER_THIN  # For tall thin plants
}

# Create a simple shape mesh
static func create_shape_mesh(shape_type: ShapeType, size: float = 1.0) -> Mesh:
	var mesh: Mesh
	
	match shape_type:
		ShapeType.CYLINDER:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size * 0.3
			cylinder.bottom_radius = size * 0.3
			cylinder.height = size * 2.0
			mesh = cylinder
		ShapeType.CYLINDER_THIN:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size * 0.15
			cylinder.bottom_radius = size * 0.15
			cylinder.height = size * 3.0
			mesh = cylinder
		ShapeType.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = size * 0.5
			sphere.height = size
			mesh = sphere
		ShapeType.CUBE:
			var cube := BoxMesh.new()
			cube.size = Vector3(size * 0.4, size * 0.6, size * 0.4)
			mesh = cube
		_:
			var cube := BoxMesh.new()
			cube.size = Vector3(size, size, size)
			mesh = cube
	
	return mesh

# Render plants from distribution results
func render_plants_from_distribution(
	plant_distribution: PlantDistribution,
	height_map: Image,
	map_size: Vector2i,
	terrain_scale: float,
	height_scale: float,
	ecosystem: Resource = null
):
	if not render_plants:
		return
	
	# Clear existing plants
	_clear_plants()
	
	if not plant_distribution or plant_distribution.valid_positions.is_empty():
		return
	
	# Get layer positions if ecosystem is provided (Phase 4)
	var has_layers := ecosystem != null and ecosystem.has_method("get_layer_plants")
	var layer_positions: Dictionary = {}
	if has_layers:
		layer_positions = plant_distribution.layer_positions
	
	# Render all positions, grouped by layer if available
	if has_layers and not layer_positions.is_empty():
		# Render layer by layer to ensure correct shape assignment
		for layer_num in range(1, 4):
			if layer_positions.has(layer_num):
				var layer_pos_array: Array = layer_positions[layer_num]
				for pos in layer_pos_array:
					if pos is Vector2:
						_render_single_plant(
							pos as Vector2,
							height_map,
							map_size,
							terrain_scale,
							height_scale,
							ecosystem,
							true,  # has_layers
							layer_positions,
							layer_num  # Pass layer directly
						)
	else:
		# Fallback: render all positions (Phase 3 or no layer info)
		for i in range(plant_distribution.valid_positions.size()):
			var map_pos := plant_distribution.valid_positions[i]
			_render_single_plant(
				map_pos,
				height_map,
				map_size,
				terrain_scale,
				height_scale,
				ecosystem,
				has_layers,
				layer_positions,
				1  # Default to layer 1
			)
	
	print("Rendered ", plant_distribution.valid_positions.size(), " plants")

func _render_single_plant(
	map_pos: Vector2,
	height_map: Image,
	map_size: Vector2i,
	terrain_scale: float,
	height_scale: float,
	_ecosystem: Resource,
	_has_layers: bool,
	_layer_positions: Dictionary,
	layer: int = 1  # Layer number (1, 2, or 3)
):
	# Convert map position (pixels) to world position
	var u := map_pos.x / float(map_size.x)
	var v := map_pos.y / float(map_size.y)
	
	# Sample height map
	var pixel_x := int(clamp(map_pos.x, 0, map_size.x - 1))
	var pixel_y := int(clamp(map_pos.y, 0, map_size.y - 1))
	var height_value := height_map.get_pixel(pixel_x, pixel_y).r
	var world_height := height_value * height_scale
	
	# Calculate world position (centered at origin)
	var terrain_size_x := map_size.x * terrain_scale
	var terrain_size_z := map_size.y * terrain_scale
	var world_x := (u - 0.5) * terrain_size_x
	var world_z := (v - 0.5) * terrain_size_z
	var world_y := world_height
	
	# Determine shape type and size based on layer
	var shape_type: ShapeType = ShapeType.CYLINDER
	var size: float = 1.0
	
	# Set shape and size based on layer (passed as parameter)
	match layer:
		1:  # Large trees
			shape_type = ShapeType.CYLINDER
			size = 3.0
		2:  # Shrubs
			shape_type = ShapeType.SPHERE
			size = 1.5
		3:  # Ground plants
			shape_type = ShapeType.CUBE
			size = 0.5
		_:
			# Default/fallback: single layer (Phase 3)
			shape_type = ShapeType.CYLINDER
			size = 2.0
	
	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = create_shape_mesh(shape_type, size)
	
	# Position the plant
	mesh_instance.position = Vector3(world_x, world_y, world_z)
	
	# Create material with color based on layer
	var material := StandardMaterial3D.new()
	match shape_type:
		ShapeType.CYLINDER:
			material.albedo_color = Color(0.2, 0.4, 0.1)  # Dark green for trees
		ShapeType.SPHERE:
			material.albedo_color = Color(0.3, 0.5, 0.2)  # Medium green for shrubs
		ShapeType.CUBE:
			material.albedo_color = Color(0.4, 0.6, 0.3)  # Light green for ground plants
		_:
			material.albedo_color = Color(0.3, 0.5, 0.2)
	
	mesh_instance.set_surface_override_material(0, material)
	
	# Add to scene
	add_child(mesh_instance)

func _clear_plants():
	# Remove all existing plant meshes
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()
