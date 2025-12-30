extends RefCounted
class_name PlantDistribution

# Plant Distribution Manager
# Handles position evaluation and plant placement for Phase 3

var rd: RenderingDevice
var map_manager: MapManager
var map_size: Vector2i

# Shader resources
var evaluate_shader: RID
var linear_sampler: RID

# Position tile parameters
var tile_size: int = 64  # Size of each position tile
var min_distance: float = 8.0  # Minimum distance between positions in Poisson Disk (increased to reduce clustering)

# Plant type (single type for Phase 3)
var plant_type: PlantType

# Position buffers
var position_tile_buffer: RID
var valid_positions_buffer: RID
var num_positions: int = 0

# Density map (output for current layer)
var density_map_texture: RID
var density_map_upper_texture: RID  # For multi-layer (Phase 4), dummy for Phase 3

# Results
var valid_positions: Array[Vector2] = []

# Debug: Save plant positions to a visualization image
func save_positions_debug(output_path: String = ""):
	# Create a visualization image showing plant positions
	if valid_positions.size() == 0:
		return
	
	if output_path.is_empty():
		var project_root := ProjectSettings.globalize_path("res://")
		output_path = project_root + "maps/gpu-derived-maps/plant_positions.png"
	
	# Create image same size as map
	var image := Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 255))  # Black background
	
	# Draw plant positions as white dots
	for pos in valid_positions:
		var x := int(pos.x)
		var y := int(pos.y)
		if x >= 0 and x < map_size.x and y >= 0 and y < map_size.y:
			# Draw a small cross/plus shape for visibility
			for offset_x in range(-1, 2):
				for offset_y in range(-1, 2):
					var px := x + offset_x
					var py := y + offset_y
					if px >= 0 and px < map_size.x and py >= 0 and py < map_size.y:
						image.set_pixel(px, py, Color.WHITE)
	
	# Save image
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Failed to save plant positions visualization: " + str(error))

func _init(map_mgr: MapManager):
	# Use the same RenderingDevice as MapManager to share textures
	rd = map_mgr.rd
	map_manager = map_mgr
	map_size = map_mgr.map_size
	_create_sampler()

func _create_sampler():
	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler = rd.sampler_create(sampler_state)

func load_shader():
	var shader_file := load("res://shaders/evaluate_positions.glsl") as RDShaderFile
	if shader_file:
		var spirv := shader_file.get_spirv()
		if spirv:
			evaluate_shader = rd.shader_create_from_spirv(spirv)
			if not evaluate_shader.is_valid():
				push_error("Failed to create position evaluation shader from SPIR-V")

func generate_position_tile() -> Array[Vector2]:
	# Generate a Poisson Disk position tile
	var tile_size_vec := Vector2i(tile_size, tile_size)
	return PoissonDisk.generate(tile_size_vec, min_distance)

func distribute_plants(plant: PlantType, threshold: float = 0.5, layer: int = 1):
	# Main distribution function
	# For Phase 3, we'll evaluate positions for the entire map using tiles
	# layer: current layer index (1 = top layer, Phase 3 uses layer 1)
	plant_type = plant
	
	if not evaluate_shader.is_valid():
		push_error("Position evaluation shader not loaded!")
		return
	
	# Create density map texture for current layer
	_create_density_map()
	
	# Create dummy upper layer density map (empty for Phase 3, single layer)
	_create_dummy_upper_density_map()
	
	# Generate position tile
	var positions := generate_position_tile()
	num_positions = positions.size()
	
	if num_positions == 0:
		push_error("No positions generated in tile!")
		return
	
	# Calculate number of tiles needed to cover the map
	var tiles_x := int(ceil(float(map_size.x) / float(tile_size)))
	var tiles_y := int(ceil(float(map_size.y) / float(tile_size)))
	
	valid_positions.clear()
	
	# Process each tile
	for tile_y in range(tiles_y):
		for tile_x in range(tiles_x):
			_evaluate_tile(tile_x, tile_y, positions, threshold, layer)
	
	print("Plant distribution complete: ", valid_positions.size(), " plants placed")

func _create_density_map():
	# Create density map texture for current layer (R32F format)
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	var data := PackedByteArray()
	data.resize(map_size.x * map_size.y * 4)  # R32F = 4 bytes per pixel
	density_map_texture = rd.texture_create(format, view, [data])

func _create_dummy_upper_density_map():
	# Create dummy upper layer density map (all zeros for Phase 3)
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	var view := RDTextureView.new()
	var data := PackedByteArray()
	data.resize(map_size.x * map_size.y * 4)  # All zeros
	density_map_upper_texture = rd.texture_create(format, view, [data])

func _evaluate_tile(tile_x: int, tile_y: int, tile_positions: Array[Vector2], threshold: float, layer: int):
	# Evaluate positions in a single tile
	
	# Create position tile buffer
	var position_data := PackedFloat32Array()
	for pos in tile_positions:
		position_data.append(pos.x)
		position_data.append(pos.y)
	
	var position_bytes := position_data.to_byte_array()
	position_tile_buffer = rd.storage_buffer_create(position_bytes.size(), position_bytes)
	
	# Create valid positions buffer (output)
	var valid_positions_size := num_positions * 4 * 4  # vec4 per position
	var valid_positions_data := PackedByteArray()
	valid_positions_data.resize(valid_positions_size)
	valid_positions_buffer = rd.storage_buffer_create(valid_positions_size, valid_positions_data)
	
	# Validate textures are valid
	if not map_manager.height_map_texture.is_valid():
		push_error("Height map texture is invalid!")
		return
	if not map_manager.water_map_texture.is_valid():
		push_error("Water map texture is invalid!")
		return
	if not map_manager.slope_map_texture.is_valid():
		push_error("Slope map texture is invalid!")
		return
	if not map_manager.moisture_map_texture.is_valid():
		push_error("Moisture map texture is invalid!")
		return
	
	# Create uniform set
	var uniforms := []
	
	# Input maps (bindings match shader)
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	height_uniform.binding = 0
	height_uniform.add_id(map_manager.height_map_texture)
	uniforms.append(height_uniform)
	
	var water_uniform := RDUniform.new()
	water_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	water_uniform.binding = 1
	water_uniform.add_id(map_manager.water_map_texture)
	uniforms.append(water_uniform)
	
	var slope_uniform := RDUniform.new()
	slope_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	slope_uniform.binding = 2
	slope_uniform.add_id(map_manager.slope_map_texture)
	uniforms.append(slope_uniform)
	
	var moisture_uniform := RDUniform.new()
	moisture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	moisture_uniform.binding = 3
	moisture_uniform.add_id(map_manager.moisture_map_texture)
	uniforms.append(moisture_uniform)
	
	var sampler_uniform := RDUniform.new()
	sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler_uniform.binding = 4
	sampler_uniform.add_id(linear_sampler)
	uniforms.append(sampler_uniform)
	
	# Density map from upper layer (binding 5)
	var density_upper_uniform := RDUniform.new()
	density_upper_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	density_upper_uniform.binding = 5
	density_upper_uniform.add_id(density_map_upper_texture)
	uniforms.append(density_upper_uniform)
	
	# Position tile buffer (binding 6)
	var position_buffer_uniform := RDUniform.new()
	position_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	position_buffer_uniform.binding = 6
	position_buffer_uniform.add_id(position_tile_buffer)
	uniforms.append(position_buffer_uniform)
	
	# Valid positions buffer (binding 7)
	var valid_buffer_uniform := RDUniform.new()
	valid_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	valid_buffer_uniform.binding = 7
	valid_buffer_uniform.add_id(valid_positions_buffer)
	uniforms.append(valid_buffer_uniform)
	
	# Density map output (binding 8)
	var density_output_uniform := RDUniform.new()
	density_output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	density_output_uniform.binding = 8
	density_output_uniform.add_id(density_map_texture)
	uniforms.append(density_output_uniform)
	
	# Parameters (binding 9)
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y),
		float(tile_x * tile_size), float(tile_y * tile_size),
		float(tile_size),
		float(num_positions),
		0.0,  # plant_type (for now, single type)
		float(layer),  # current_layer
		threshold,
		map_manager.height_scale
	])
	var params_bytes := params.to_byte_array()
	var aligned_size := int(((float(params_bytes.size()) + 15.0) / 16.0)) * 16
	if params_bytes.size() < aligned_size:
		var padded_bytes := PackedByteArray()
		padded_bytes.resize(aligned_size)
		for i in range(params_bytes.size()):
			padded_bytes[i] = params_bytes[i]
		params_bytes = padded_bytes
	var params_buffer := rd.uniform_buffer_create(aligned_size, params_bytes)
	var params_uniform := RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	params_uniform.binding = 9
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, evaluate_shader, 0)
	if not uniform_set.is_valid():
		push_error("Failed to create uniform set for position evaluation")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		return
	
	var pipeline := rd.compute_pipeline_create(evaluate_shader)
	if not pipeline.is_valid():
		push_error("Failed to create compute pipeline for position evaluation")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		return
	
	# Dispatch compute shader
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int(ceil(float(num_positions) / 8.0))
	rd.compute_list_dispatch(compute_list, x_groups, 1, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Read back valid positions
	var result_data := rd.buffer_get_data(valid_positions_buffer)
	var result_floats := result_data.to_float32_array()
	
	# Debug: Check some sample values
	var valid_count := 0
	var invalid_count := 0
	var max_probability := 0.0
	var min_probability := 1.0
	
	# Extract valid positions
	for i in range(num_positions):
		var idx := i * 4
		if idx + 2 < result_floats.size():
			var plant_type_id := result_floats[idx + 2]
			if plant_type_id >= 0.0:  # Valid position
				var pos := Vector2(result_floats[idx], result_floats[idx + 1])
				valid_positions.append(pos)
	
	# Cleanup
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if position_tile_buffer.is_valid():
		rd.free_rid(position_tile_buffer)
	if valid_positions_buffer.is_valid():
		rd.free_rid(valid_positions_buffer)

func cleanup():
	if position_tile_buffer.is_valid():
		rd.free_rid(position_tile_buffer)
	if valid_positions_buffer.is_valid():
		rd.free_rid(valid_positions_buffer)
	if density_map_texture.is_valid():
		rd.free_rid(density_map_texture)
	if density_map_upper_texture.is_valid():
		rd.free_rid(density_map_upper_texture)
	if evaluate_shader.is_valid():
		rd.free_rid(evaluate_shader)
	if linear_sampler.is_valid():
		rd.free_rid(linear_sampler)
