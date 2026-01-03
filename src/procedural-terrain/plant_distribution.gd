extends RefCounted
class_name PlantDistribution

# Plant Distribution Manager
# Handles position evaluation and plant placement for Phase 3 and Phase 4 (multi-layer)

var rd: RenderingDevice
var map_manager: MapManager
var map_size: Vector2i

# Shader resources
var evaluate_shader: RID
var distance_field_shader: RID
var linear_sampler: RID

# Position tile parameters
var tile_size: int = 64  # Size of each position tile
var min_distance: float = 8.0  # Minimum distance between positions in Poisson Disk (increased to reduce clustering)

# Plant type (single type for Phase 3, selected per position for Phase 4)
var plant_type: PlantType

# Position buffers
var position_tile_buffer: RID
var valid_positions_buffer: RID
var num_positions: int = 0

# Density maps (Phase 4: multi-layer support)
var density_map_texture: RID  # Current layer binary density map (0 or 1)
var density_field_texture: RID  # Current layer distance field map
var density_map_upper_texture: RID  # Accumulated density map from upper layers (for input to lower layers)

# Results (Phase 4: stores positions per layer)
var valid_positions: Array[Vector2] = []  # All valid positions across all layers
var layer_positions: Dictionary = {}  # {layer: [positions]} for Phase 4

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
	
	# Load distance field shader for Phase 4
	var distance_shader_file := load("res://shaders/distance_field.glsl") as RDShaderFile
	if distance_shader_file:
		var spirv := distance_shader_file.get_spirv()
		if spirv:
			distance_field_shader = rd.shader_create_from_spirv(spirv)
			if not distance_field_shader.is_valid():
				push_error("Failed to create distance field shader from SPIR-V")
		else:
			push_error("Failed to get SPIR-V from distance field shader file!")
	else:
		push_error("Failed to load distance field shader file: res://shaders/distance_field.glsl")

func generate_position_tile() -> Array[Vector2]:
	# Generate a Poisson Disk position tile
	var tile_size_vec := Vector2i(tile_size, tile_size)
	return PoissonDisk.generate(tile_size_vec, min_distance)

func distribute_plants(_plant: PlantType, threshold: float = 0.5, _layer: int = 1):
	# Phase 3: Single layer distribution (backward compatibility)
	# Note: plant and layer parameters kept for API compatibility but not used
	distribute_ecosystem(null, threshold)

func distribute_ecosystem(ecosystem: Resource, threshold: float = 0.5):
	# Phase 4: Multi-layer ecosystem distribution
	# ecosystem: Ecosystem resource (typed as Resource for compatibility)
	# threshold: Base threshold (will be adjusted per layer)
	# Phase 4: Multi-layer ecosystem distribution
	# Processes layers sequentially from top to bottom (L1 → L2 → L3)
	# Uses layer-specific thresholds: L1 is more selective (higher threshold) to leave room for lower layers
	
	if not evaluate_shader.is_valid():
		push_error("Position evaluation shader not loaded!")
		return
	
	# Initialize density map for upper layers (starts empty for L1)
	_create_density_map_upper()
	
	# Generate position tile (reused for all layers)
	var positions := generate_position_tile()
	num_positions = positions.size()
	
	if num_positions == 0:
		push_error("No positions generated in tile!")
		return
	
	# Calculate number of tiles needed to cover the map
	var tiles_x := int(ceil(float(map_size.x) / float(tile_size)))
	var tiles_y := int(ceil(float(map_size.y) / float(tile_size)))
	
	valid_positions.clear()
	layer_positions.clear()
	
	# Process layers sequentially (L1 → L2 → L3)
	for layer in range(1, 4):
		var layer_plants := []
		if ecosystem:
			layer_plants = ecosystem.get_layer_plants(layer)
		else:
			# Phase 3 fallback: use single plant type for layer 1 only
			if layer == 1 and plant_type:
				layer_plants = [plant_type]
			else:
				continue  # Skip empty layers
		
		if layer_plants.is_empty():
			continue  # Skip empty layers
		
		# Create density map textures for current layer
		_create_density_map()
		_create_density_field_map()
		
		# Check upper layer density map validity
		if layer > 1 and not density_map_upper_texture.is_valid():
			push_warning("Layer ", layer, ": Upper layer density map is invalid! Lower layers won't avoid upper layers.")
		
		# Process each tile for this layer
		var layer_valid_positions: Array[Vector2] = []
		
		# Use layer-specific thresholds: L1 is more selective to leave room for lower layers
		# L1: higher threshold (more selective, fewer plants)
		# L2: medium threshold
		# L3: lower threshold (less selective, more plants can fit in gaps)
		var layer_threshold: float
		match layer:
			1:
				layer_threshold = threshold + 0.3  # L1: more selective (e.g., 0.5 if base is 0.2)
			2:
				layer_threshold = threshold + 0.1  # L2: slightly more selective (e.g., 0.3 if base is 0.2)
			3:
				layer_threshold = threshold  # L3: use base threshold (e.g., 0.2)
			_:
				layer_threshold = threshold
		
		for tile_y in range(tiles_y):
			for tile_x in range(tiles_x):
				# Select plant type for this tile based on predominance (simplified: one type per tile)
				# In a full implementation, this would be per-position, but we simplify for performance
				var selected_plant: PlantType
				if ecosystem:
					selected_plant = ecosystem.select_plant_type(layer)
				else:
					selected_plant = layer_plants[0]  # Single type fallback
				
				if not selected_plant:
					push_warning("No plant selected for tile (", tile_x, ", ", tile_y, ")")
					continue
				
				# Evaluate all positions in tile with selected plant type
				var tile_valid: Array[Vector2] = []
				tile_valid = _evaluate_tile(tile_x, tile_y, positions, layer_threshold, layer, selected_plant)
				if tile_valid.size() > 0:
					layer_valid_positions.append_array(tile_valid)
		
		# Merge binary density map (where plants were placed) into upper layer
		# This is essential for lower layers to avoid placing plants where upper layers have plants
		# We dilate the binary map to approximate the ZOI (Zone of Influence) without expensive distance field calculation
		# Get the maximum ZOI from all plants in this layer for dilation radius
		# ZOI is in world units, and since terrain_scale = 1.0, 1 world unit = 1 pixel
		var max_zoi: float = 0.0
		for plant in layer_plants:
			if plant and plant.zone_of_influence > max_zoi:
				max_zoi = plant.zone_of_influence
		_merge_binary_density_map(max_zoi)
		
		# Calculate distance field from binary density map (only if shader is loaded)
		# NOTE: Distance field calculation is computationally expensive and may crash on weaker GPUs
		# For now, skip it - we're already merging the binary density map in _merge_binary_density_map()
		# which dilates it to approximate the ZOI, so we don't need the distance field
		_create_dummy_distance_field()
		
		# Uncomment below to enable distance field calculation (may crash on weaker GPUs):
		# print("  Checking distance field shader...")
		# if not distance_field_shader.is_valid():
		# 	push_warning("Distance field shader not loaded! Skipping distance field calculation for layer ", layer)
		# 	_create_dummy_distance_field()
		# else:
		# 	print("  Distance field shader is valid. Checking textures...")
		# 	if not density_map_texture.is_valid():
		# 		push_error("Density map texture invalid before distance field calculation!")
		# 		_create_dummy_distance_field()
		# 	elif not density_field_texture.is_valid():
		# 		push_error("Density field texture invalid before distance field calculation!")
		# 		_create_dummy_distance_field()
		# 	else:
		# 		print("  Textures valid. Calling _calculate_distance_field...")
		# 		_calculate_distance_field(layer_plants[0])  # Use first plant's ZOI/trunk radius
		# 		print("  Distance field calculation complete. Merging density maps...")
		# 		_merge_density_maps()
		# 		print("  Density map merge complete.")
		
		# Store layer results
		layer_positions[layer] = layer_valid_positions
		valid_positions.append_array(layer_valid_positions)
		
		print("Layer ", layer, ": ", layer_valid_positions.size(), " plants placed")
	
	print("Multi-layer distribution complete: ", valid_positions.size(), " total plants")

func _create_density_map():
	# Create density map texture for current layer (R32F format)
	# Free old one if it exists
	if density_map_texture.is_valid():
		rd.free_rid(density_map_texture)
	
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

func _create_density_map_upper():
	# Create/initialize upper layer density map (accumulated from previous layers)
	# Starts empty for L1, accumulates for L2 and L3
	if density_map_upper_texture.is_valid():
		rd.free_rid(density_map_upper_texture)
	
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	var data := PackedByteArray()
	data.resize(map_size.x * map_size.y * 4)  # All zeros initially
	density_map_upper_texture = rd.texture_create(format, view, [data])

func _create_density_field_map():
	# Create distance field texture for current layer
	if density_field_texture.is_valid():
		rd.free_rid(density_field_texture)
	
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	var data := PackedByteArray()
	data.resize(map_size.x * map_size.y * 4)  # Initialize to zeros
	density_field_texture = rd.texture_create(format, view, [data])
	
	if not density_field_texture.is_valid():
		push_error("Failed to create density field texture!")

func _merge_binary_density_map(dilation_radius: float = 0.0):
	# Merge the binary density map (where plants were placed) into the upper layer density map
	# This is essential so lower layers can see where upper layers have plants
	# We dilate the binary map to approximate the ZOI (Zone of Influence) without expensive distance field calculation
	# dilation_radius: radius in pixels to expand around each plant (approximates ZOI)
	
	if not density_map_texture.is_valid():
		push_error("Density map texture is invalid, cannot merge!")
		return
	
	# Note: No need to sync here - each tile evaluation already syncs after submit()
	# All tiles have been evaluated, so the density map is ready to read
	
	# Read current layer's binary density map data
	var current_density_data := rd.texture_get_data(density_map_texture, 0)
	
	if current_density_data.is_empty():
		push_error("Failed to read binary density map data!")
		return
	
	# Read upper layer density map data (if it exists)
	var upper_density_data := PackedByteArray()
	if density_map_upper_texture.is_valid():
		upper_density_data = rd.texture_get_data(density_map_upper_texture, 0)
		if upper_density_data.is_empty():
			push_warning("Upper layer texture is valid but returned empty data!")
	
	# Convert to float arrays for processing
	var current_floats: PackedFloat32Array = current_density_data.to_float32_array()
	var upper_floats: PackedFloat32Array = PackedFloat32Array()
	if not upper_density_data.is_empty():
		upper_floats = upper_density_data.to_float32_array()
	
	# Dilate the current layer's density map to approximate ZOI
	# This creates a simple circular "exclusion zone" around each plant
	var dilated_floats: PackedFloat32Array = PackedFloat32Array()
	dilated_floats.resize(map_size.x * map_size.y)
	
	if dilation_radius > 0.0:
		# Dilate: for each pixel, if any neighbor within dilation_radius has a plant, mark this pixel
		var radius_pixels := int(ceil(dilation_radius))
		for y in range(map_size.y):
			for x in range(map_size.x):
				var idx := y * map_size.x + x
				var dilated_val: float = current_floats[idx]  # Start with original value
				
				# Check neighbors within dilation radius
				for dy in range(-radius_pixels, radius_pixels + 1):
					for dx in range(-radius_pixels, radius_pixels + 1):
						var nx := x + dx
						var ny := y + dy
						
						# Check bounds
						if nx < 0 or nx >= map_size.x or ny < 0 or ny >= map_size.y:
							continue
						
						# Check if within circular radius
						var dist_sq := float(dx * dx + dy * dy)
						if dist_sq <= dilation_radius * dilation_radius:
							var neighbor_idx := ny * map_size.x + nx
							if neighbor_idx < current_floats.size() and current_floats[neighbor_idx] > 0.5:
								dilated_val = 1.0
								break
					
					if dilated_val >= 1.0:
						break
				
				dilated_floats[idx] = dilated_val
	else:
		# No dilation, just copy
		dilated_floats = current_floats.duplicate()
	
	# Merge pixel by pixel: take maximum (if either is 1.0, result is 1.0)
	var merged_data := PackedByteArray()
	merged_data.resize(map_size.x * map_size.y * 4)  # R32F = 4 bytes per pixel
	
	# Merge pixel by pixel: take maximum (if either is 1.0, result is 1.0)
	for i in range(map_size.x * map_size.y):
		var current_val: float = dilated_floats[i] if i < dilated_floats.size() else 0.0
		var upper_val: float = upper_floats[i] if i < upper_floats.size() else 0.0
		var merged_val: float = max(current_val, upper_val)  # If either layer has a plant, merged has it
		
		# Write merged value (4 bytes per float)
		var float_array: PackedFloat32Array = PackedFloat32Array([merged_val])
		var float_bytes: PackedByteArray = float_array.to_byte_array()
		for j in range(4):
			merged_data[i * 4 + j] = float_bytes[j]
	
	# Free old upper layer texture
	if density_map_upper_texture.is_valid():
		rd.free_rid(density_map_upper_texture)
	
	# Create new upper layer texture with merged density map data
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	density_map_upper_texture = rd.texture_create(format, view, [merged_data])
	
	if not density_map_upper_texture.is_valid():
		push_error("Failed to create merged upper layer density map!")

func _create_dummy_distance_field():
	# Create a dummy distance field (all zeros) when shader isn't available
	# This allows Phase 4 to continue without distance field calculation
	if density_field_texture.is_valid():
		rd.free_rid(density_field_texture)
	
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	var data := PackedByteArray()
	data.resize(map_size.x * map_size.y * 4)  # All zeros
	density_field_texture = rd.texture_create(format, view, [data])
	
	# Note: We don't call _merge_density_maps() here because we're already merging
	# the binary density map in _merge_binary_density_map(), which dilates it to
	# approximate the ZOI. The distance field is only needed for the full distance
	# field calculation, which we're skipping for performance.

func _evaluate_tile(tile_x: int, tile_y: int, tile_positions: Array[Vector2], threshold: float, layer: int, selected_plant: PlantType = null) -> Array[Vector2]:
	# Evaluate positions in a single tile
	# selected_plant: Plant type to use for this tile (for Phase 4 predominance)
	# Returns: Array of valid positions from this tile
	if selected_plant:
		plant_type = selected_plant
	
	# Free old buffers if they exist (reuse for each tile to avoid memory leaks)
	# Note: Only free if valid to avoid "Attempted to free invalid ID" errors
	if position_tile_buffer.is_valid():
		rd.free_rid(position_tile_buffer)
		position_tile_buffer = RID()  # Clear immediately after freeing
	if valid_positions_buffer.is_valid():
		rd.free_rid(valid_positions_buffer)
		valid_positions_buffer = RID()  # Clear immediately after freeing
	
	# Create position tile buffer
	var position_data := PackedFloat32Array()
	for pos in tile_positions:
		position_data.append(pos.x)
		position_data.append(pos.y)
	
	var position_bytes := position_data.to_byte_array()
	position_tile_buffer = rd.storage_buffer_create(position_bytes.size(), position_bytes)
	if not position_tile_buffer.is_valid():
		push_error("Failed to create position tile buffer!")
		return []
	
	# Create valid positions buffer (output)
	var valid_positions_size := num_positions * 4 * 4  # vec4 per position
	var valid_positions_data := PackedByteArray()
	valid_positions_data.resize(valid_positions_size)
	valid_positions_buffer = rd.storage_buffer_create(valid_positions_size, valid_positions_data)
	if not valid_positions_buffer.is_valid():
		push_error("Failed to create valid positions buffer!")
		if position_tile_buffer.is_valid():
			rd.free_rid(position_tile_buffer)
		return []
	
	# Validate textures are valid
	if not map_manager.height_map_texture.is_valid():
		push_error("Height map texture is invalid!")
		return []
	if not map_manager.water_map_texture.is_valid():
		push_error("Water map texture is invalid!")
		return []
	if not map_manager.slope_map_texture.is_valid():
		push_error("Slope map texture is invalid!")
		return []
	if not map_manager.moisture_map_texture.is_valid():
		push_error("Moisture map texture is invalid!")
		return []
	
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
	# For Layer 1, this is empty/invalid, but we still bind it (shader checks l > 1)
	var density_upper_uniform := RDUniform.new()
	density_upper_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	density_upper_uniform.binding = 5
	if density_map_upper_texture.is_valid():
		density_upper_uniform.add_id(density_map_upper_texture)
	else:
		# Create a dummy empty texture for Layer 1 (shader won't use it anyway)
		# But we need to bind something to avoid errors
		if not map_manager.height_map_texture.is_valid():
			push_error("Cannot create dummy upper layer texture - height map invalid!")
			return []
		# Use height map as dummy (shader checks l > 1, so won't sample it for Layer 1)
		density_upper_uniform.add_id(map_manager.height_map_texture)
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
		return []
	
	var pipeline := rd.compute_pipeline_create(evaluate_shader)
	if not pipeline.is_valid():
		push_error("Failed to create compute pipeline for position evaluation")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		return []
	
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
	if not valid_positions_buffer.is_valid():
		push_error("Valid positions buffer is invalid after compute dispatch!")
		return []
	
	var result_data := rd.buffer_get_data(valid_positions_buffer)
	if result_data.is_empty():
		push_error("Failed to read back valid positions buffer data!")
		return []
	
	var result_floats := result_data.to_float32_array()
	if result_floats.is_empty():
		push_error("Failed to convert buffer data to float array!")
		return []
	
	# Extract valid positions (return them for layer tracking)
	var tile_valid_positions: Array[Vector2] = []
	for i in range(num_positions):
		var idx := i * 4
		if idx + 2 < result_floats.size():
			var plant_type_id := result_floats[idx + 2]
			if plant_type_id >= 0.0:  # Valid position
				var pos := Vector2(result_floats[idx], result_floats[idx + 1])
				tile_valid_positions.append(pos)
				valid_positions.append(pos)
	
	# Cleanup (uniform sets and pipelines are per-tile, buffers are reused)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	# Note: Don't free buffers here - they're freed at the start of the next _evaluate_tile() call
	# This avoids double-free errors when buffers are reused
	
	return tile_valid_positions

func _calculate_distance_field(plant: PlantType):
	# Calculate distance field from binary density map using equation (7) from paper
	# φ = 1 - saturate((δ - τ) / (ZOI - τ))
	
	if not distance_field_shader.is_valid():
		push_error("Distance field shader not loaded!")
		return
	
	if not plant:
		push_error("Plant type required for distance field calculation!")
		return
	
	if not density_map_texture.is_valid():
		push_error("Density map texture is invalid!")
		return
	
	if not density_field_texture.is_valid():
		push_error("Density field texture is invalid!")
		return
	
	if not plant:
		push_error("Plant type required for distance field calculation!")
		return
	
	# Create uniform set for distance field shader
	var uniforms := []
	
	# Binary density map (input)
	var binary_uniform := RDUniform.new()
	binary_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	binary_uniform.binding = 0
	binary_uniform.add_id(density_map_texture)
	uniforms.append(binary_uniform)
	
	# Distance field map (output)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 1
	output_uniform.add_id(density_field_texture)
	uniforms.append(output_uniform)
	
	# Parameters
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y),
		plant.trunk_radius,
		plant.zone_of_influence,
		float(int(plant.zone_of_influence) + 5)  # search_radius: ZOI + small buffer
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
	params_uniform.binding = 2
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, distance_field_shader, 0)
	if not uniform_set.is_valid():
		push_error("Failed to create uniform set for distance field")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		return
	
	var pipeline := rd.compute_pipeline_create(distance_field_shader)
	if not pipeline.is_valid():
		push_error("Failed to create compute pipeline for distance field")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		return
	
	# Dispatch compute shader
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int(ceil(float(map_size.x) / 8.0))
	var y_groups := int(ceil(float(map_size.y) / 8.0))
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Cleanup
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)

func _merge_density_maps(skip_sync: bool = false):
	# Merge current layer's distance field with upper layer's accumulated density map
	# This creates the accumulated density map for the next layer
	# For Phase 4 simplicity, we'll use the distance field as the new upper layer
	# (Proper merge would combine both: upper = max(upper, current_distance_field))
	
	# Check if distance field texture is valid and has data
	if not density_field_texture.is_valid():
		push_error("Distance field texture is invalid, cannot merge!")
		return
	
	# Only sync if there was GPU work submitted (skip for dummy distance fields)
	if not skip_sync:
		rd.sync()
	
	# Free old upper layer texture
	if density_map_upper_texture.is_valid() and density_map_upper_texture != density_field_texture:
		rd.free_rid(density_map_upper_texture)
	
	# Check if distance field texture is valid and has data
	if not density_field_texture.is_valid():
		push_error("Distance field texture is invalid, cannot merge!")
		return
	
	# Create new upper layer texture with SAMPLING_BIT for next layer's input
	var format := RDTextureFormat.new()
	format.width = map_size.x
	format.height = map_size.y
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	
	# Copy distance field data to new upper layer texture
	# For Phase 4 MVP, we'll read back the distance field and recreate as upper layer
	# TODO: Use GPU copy/blit operation for better performance
	
	# Read distance field data (requires CAN_COPY_FROM_BIT which we set in _create_density_field_map)
	var distance_data := PackedByteArray()
	
	# Try to read texture data with error handling
	var read_error := false
	distance_data = rd.texture_get_data(density_field_texture, 0)
	
	if distance_data.is_empty():
		push_error("Failed to read distance field data! Creating empty texture as fallback.")
		read_error = true
	
	if read_error or distance_data.size() != map_size.x * map_size.y * 4:
		# Create empty texture as fallback
		var empty_data := PackedByteArray()
		empty_data.resize(map_size.x * map_size.y * 4)
		density_map_upper_texture = rd.texture_create(format, view, [empty_data])
		if not density_map_upper_texture.is_valid():
			push_error("Failed to create fallback upper layer texture!")
		return
	
	# Create new upper layer texture with the distance field data
	density_map_upper_texture = rd.texture_create(format, view, [distance_data])
	
	# Free old distance field texture (will be recreated for next layer)
	if density_field_texture.is_valid():
		rd.free_rid(density_field_texture)
		density_field_texture = RID()

func cleanup():
	if position_tile_buffer.is_valid():
		rd.free_rid(position_tile_buffer)
	if valid_positions_buffer.is_valid():
		rd.free_rid(valid_positions_buffer)
	if density_map_texture.is_valid():
		rd.free_rid(density_map_texture)
	if density_field_texture.is_valid():
		rd.free_rid(density_field_texture)
	if density_map_upper_texture.is_valid():
		rd.free_rid(density_map_upper_texture)
	if evaluate_shader.is_valid():
		rd.free_rid(evaluate_shader)
	if distance_field_shader.is_valid():
		rd.free_rid(distance_field_shader)
	if linear_sampler.is_valid():
		rd.free_rid(linear_sampler)
