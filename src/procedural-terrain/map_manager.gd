extends RefCounted
class_name MapManager

# Map Manager for GPU-based derived map generation
# Handles compute shader execution for Phase 2 maps

var rd: RenderingDevice
var map_size: Vector2i

# Shader resources
var slope_shader: RID
var mean_height_shader: RID
var relative_height_shader: RID
var water_spread_shader: RID
var moisture_shader: RID

# Map textures (RIDs)
var height_map_texture: RID
var water_map_texture: RID
var slope_map_texture: RID
var mean_height_map_texture: RID
var relative_height_map_texture: RID
var water_spread_map_texture: RID
var moisture_map_texture: RID

# Samplers
var linear_sampler: RID

# Parameters
var height_scale: float = 20.0
var slope_distance: float = 12.0  # pixels
var mean_height_radius: float = 32.0  # pixels
var water_spread_radius: float = 32.0  # pixels
var water_spread_factor: float = 0.1

# Moisture map weights (from paper)
var moisture_weight_height: float = 0.3
var moisture_weight_slope: float = 0.3
var moisture_weight_relative_height: float = 0.2
var moisture_omega: float = 0.2  # Attenuation factor for relative height

func _init():
	rd = RenderingServer.create_local_rendering_device()
	_create_sampler()

func _create_sampler():
	# Create a linear sampler for reading textures
	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler = rd.sampler_create(sampler_state)

func load_shaders():
	# Load all compute shaders
	var slope_file := load("res://shaders/slope_map.glsl") as RDShaderFile
	if slope_file:
		var spirv := slope_file.get_spirv()
		if spirv:
			slope_shader = rd.shader_create_from_spirv(spirv)
			if not slope_shader.is_valid():
				push_error("Failed to create slope shader from SPIR-V")
	
	var mean_height_file := load("res://shaders/mean_height_map.glsl") as RDShaderFile
	if mean_height_file:
		var spirv := mean_height_file.get_spirv()
		if spirv:
			mean_height_shader = rd.shader_create_from_spirv(spirv)
			if not mean_height_shader.is_valid():
				push_error("Failed to create mean_height shader from SPIR-V")
	
	var relative_height_file := load("res://shaders/relative_height_map.glsl") as RDShaderFile
	if relative_height_file:
		var spirv := relative_height_file.get_spirv()
		if spirv:
			relative_height_shader = rd.shader_create_from_spirv(spirv)
			if not relative_height_shader.is_valid():
				push_error("Failed to create relative_height shader from SPIR-V")
	
	var water_spread_file := load("res://shaders/water_spread_map.glsl") as RDShaderFile
	if water_spread_file:
		var spirv := water_spread_file.get_spirv()
		if spirv:
			water_spread_shader = rd.shader_create_from_spirv(spirv)
			if not water_spread_shader.is_valid():
				push_error("Failed to create water_spread shader from SPIR-V")
	
	var moisture_file := load("res://shaders/moisture_map.glsl") as RDShaderFile
	if moisture_file:
		var spirv := moisture_file.get_spirv()
		if spirv:
			moisture_shader = rd.shader_create_from_spirv(spirv)
			if not moisture_shader.is_valid():
				push_error("Failed to create moisture shader from SPIR-V")

func create_texture_from_image(image: Image, format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R8_UNORM) -> RID:
	# Convert Image to texture format for GPU
	# For compute shader sampling, we need SAMPLING_BIT but NOT STORAGE_BIT
	var image_format := RDTextureFormat.new()
	image_format.width = image.get_width()
	image_format.height = image.get_height()
	image_format.format = format
	image_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	# Input textures need sampling and copy capability if we want to read them back
	image_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var image_data := image.get_data()
	var texture_view := RDTextureView.new()
	var texture := rd.texture_create(image_format, texture_view, [image_data])
	if not texture.is_valid():
		push_error("Failed to create texture from image")
	return texture

func create_storage_texture(width: int, height: int, format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R32_SFLOAT) -> RID:
	# Create a writable storage texture for compute shader output
	var texture_format := RDTextureFormat.new()
	texture_format.width = width
	texture_format.height = height
	texture_format.format = format
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	# Add COPY_SRC so we can read the texture back
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var texture_view := RDTextureView.new()
	var texture := rd.texture_create(texture_format, texture_view, [])
	return texture

func initialize_maps(height_image: Image, water_image: Image):
	# Initialize input maps and create output textures
	map_size = height_image.get_size()
	
	# Create input textures
	height_map_texture = create_texture_from_image(height_image)
	water_map_texture = create_texture_from_image(water_image)
	
	# Create output storage textures (R32F for floating point precision)
	slope_map_texture = create_storage_texture(map_size.x, map_size.y)
	mean_height_map_texture = create_storage_texture(map_size.x, map_size.y)
	relative_height_map_texture = create_storage_texture(map_size.x, map_size.y)
	water_spread_map_texture = create_storage_texture(map_size.x, map_size.y)
	moisture_map_texture = create_storage_texture(map_size.x, map_size.y)

func generate_slope_map():
	if not slope_shader.is_valid():
		push_error("Slope shader not loaded!")
		return
	
	# Create uniform set
	var uniforms := []
	
	# Height map texture + sampler
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	height_uniform.binding = 0
	height_uniform.add_id(height_map_texture)
	uniforms.append(height_uniform)
	
	var sampler_uniform := RDUniform.new()
	sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler_uniform.binding = 1
	sampler_uniform.add_id(linear_sampler)
	uniforms.append(sampler_uniform)
	
	# Output slope map
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 2
	output_uniform.add_id(slope_map_texture)
	uniforms.append(output_uniform)
	
	# Parameters - use uniform buffer for std140 uniform blocks
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y),
		slope_distance,
		height_scale
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
	params_uniform.binding = 3
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, slope_shader, 0)
	if not uniform_set.is_valid():
		push_error("Failed to create uniform set for slope map")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		return
	
	var pipeline := rd.compute_pipeline_create(slope_shader)
	if not pipeline.is_valid():
		push_error("Failed to create compute pipeline for slope map")
		if params_buffer.is_valid():
			rd.free_rid(params_buffer)
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		return
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int(ceil(float(map_size.x) / 8.0))
	var y_groups := int(ceil(float(map_size.y) / 8.0))
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Free resources (uniform buffers are managed by uniform set)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)

func generate_mean_height_map():
	if not mean_height_shader.is_valid():
		push_error("Mean height shader not loaded!")
		return
	
	var uniforms := []
	
	# Height map texture + sampler
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	height_uniform.binding = 0
	height_uniform.add_id(height_map_texture)
	uniforms.append(height_uniform)
	
	var sampler_uniform := RDUniform.new()
	sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler_uniform.binding = 1
	sampler_uniform.add_id(linear_sampler)
	uniforms.append(sampler_uniform)
	
	# Output mean height map
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 2
	output_uniform.add_id(mean_height_map_texture)
	uniforms.append(output_uniform)
	
	# Parameters - use uniform buffer for std140 uniform blocks
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y),  # vec2 (8 bytes)
		mean_height_radius,                    # float (4 bytes)
		height_scale                           # float (4 bytes)
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
	params_uniform.binding = 3
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, mean_height_shader, 0)
	
	# Dispatch
	var pipeline := rd.compute_pipeline_create(mean_height_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int((map_size.x + 7) / 8.0)
	var y_groups := int((map_size.y + 7) / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Free resources (uniform buffers are managed by uniform set)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	# Don't free params_buffer - it's managed by the uniform set
	

func generate_relative_height_map():
	if not relative_height_shader.is_valid():
		push_error("Relative height shader not loaded!")
		return
	
	var uniforms := []
	
	# Height map
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	height_uniform.binding = 0
	height_uniform.add_id(height_map_texture)
	uniforms.append(height_uniform)
	
	var sampler1 := RDUniform.new()
	sampler1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler1.binding = 1
	sampler1.add_id(linear_sampler)
	uniforms.append(sampler1)
	
	# Mean height map
	var mean_uniform := RDUniform.new()
	mean_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	mean_uniform.binding = 2
	mean_uniform.add_id(mean_height_map_texture)
	uniforms.append(mean_uniform)
	
	var sampler2 := RDUniform.new()
	sampler2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler2.binding = 3
	sampler2.add_id(linear_sampler)
	uniforms.append(sampler2)
	
	# Output
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 4
	output_uniform.add_id(relative_height_map_texture)
	uniforms.append(output_uniform)
	
	# Parameters - use uniform buffer for std140 uniform blocks
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y)  # vec2 (8 bytes, padded to 16 for std140)
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
	params_uniform.binding = 5
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, relative_height_shader, 0)
	
	# Dispatch
	var pipeline := rd.compute_pipeline_create(relative_height_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int((map_size.x + 7) / 8.0)
	var y_groups := int((map_size.y + 7) / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Free resources (uniform buffers are managed by uniform set)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	# Don't free params_buffer - it's managed by the uniform set
	

func generate_water_spread_map():
	if not water_spread_shader.is_valid():
		push_error("Water spread shader not loaded!")
		return
	
	var uniforms := []
	
	# Water map
	var water_uniform := RDUniform.new()
	water_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	water_uniform.binding = 0
	water_uniform.add_id(water_map_texture)
	uniforms.append(water_uniform)
	
	var sampler1 := RDUniform.new()
	sampler1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler1.binding = 1
	sampler1.add_id(linear_sampler)
	uniforms.append(sampler1)
	
	# Relative height map
	var rh_uniform := RDUniform.new()
	rh_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	rh_uniform.binding = 2
	rh_uniform.add_id(relative_height_map_texture)
	uniforms.append(rh_uniform)
	
	var sampler2 := RDUniform.new()
	sampler2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler2.binding = 3
	sampler2.add_id(linear_sampler)
	uniforms.append(sampler2)
	
	# Output
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 4
	output_uniform.add_id(water_spread_map_texture)
	uniforms.append(output_uniform)
	
	# Parameters - use uniform buffer for std140 uniform blocks
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y),  # vec2 (8 bytes)
		water_spread_radius,                    # float (4 bytes)
		water_spread_factor                     # float (4 bytes)
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
	params_uniform.binding = 5
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, water_spread_shader, 0)
	
	# Dispatch
	var pipeline := rd.compute_pipeline_create(water_spread_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int((map_size.x + 7) / 8.0)
	var y_groups := int((map_size.y + 7) / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Free resources (uniform buffers are managed by uniform set)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	# Don't free params_buffer - it's managed by the uniform set
	

func generate_moisture_map():
	if not moisture_shader.is_valid():
		push_error("Moisture shader not loaded!")
		return
	
	var uniforms := []
	
	# Height map
	var height_uniform := RDUniform.new()
	height_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	height_uniform.binding = 0
	height_uniform.add_id(height_map_texture)
	uniforms.append(height_uniform)
	
	var sampler1 := RDUniform.new()
	sampler1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler1.binding = 1
	sampler1.add_id(linear_sampler)
	uniforms.append(sampler1)
	
	# Relative height map
	var rh_uniform := RDUniform.new()
	rh_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	rh_uniform.binding = 2
	rh_uniform.add_id(relative_height_map_texture)
	uniforms.append(rh_uniform)
	
	var sampler2 := RDUniform.new()
	sampler2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler2.binding = 3
	sampler2.add_id(linear_sampler)
	uniforms.append(sampler2)
	
	# Slope map
	var slope_uniform := RDUniform.new()
	slope_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	slope_uniform.binding = 4
	slope_uniform.add_id(slope_map_texture)
	uniforms.append(slope_uniform)
	
	var sampler3 := RDUniform.new()
	sampler3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler3.binding = 5
	sampler3.add_id(linear_sampler)
	uniforms.append(sampler3)
	
	# Water map
	var water_uniform := RDUniform.new()
	water_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	water_uniform.binding = 6
	water_uniform.add_id(water_map_texture)
	uniforms.append(water_uniform)
	
	var sampler4 := RDUniform.new()
	sampler4.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler4.binding = 7
	sampler4.add_id(linear_sampler)
	uniforms.append(sampler4)
	
	# Water spread map
	var ws_uniform := RDUniform.new()
	ws_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_TEXTURE
	ws_uniform.binding = 8
	ws_uniform.add_id(water_spread_map_texture)
	uniforms.append(ws_uniform)
	
	var sampler5 := RDUniform.new()
	sampler5.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER
	sampler5.binding = 9
	sampler5.add_id(linear_sampler)
	uniforms.append(sampler5)
	
	# Output
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 10
	output_uniform.add_id(moisture_map_texture)
	uniforms.append(output_uniform)
	
	# Parameters - use uniform buffer for std140 uniform blocks
	var params := PackedFloat32Array([
		float(map_size.x), float(map_size.y),  # vec2 (8 bytes)
		moisture_weight_height,                 # float (4 bytes)
		moisture_weight_slope,                  # float (4 bytes)
		moisture_weight_relative_height,        # float (4 bytes)
		moisture_omega                          # float (4 bytes)
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
	params_uniform.binding = 11
	params_uniform.add_id(params_buffer)
	uniforms.append(params_uniform)
	
	var uniform_set := rd.uniform_set_create(uniforms, moisture_shader, 0)
	
	# Dispatch
	var pipeline := rd.compute_pipeline_create(moisture_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var x_groups := int((map_size.x + 7) / 8.0)
	var y_groups := int((map_size.y + 7) / 8.0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Free resources (uniform buffers are managed by uniform set)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	# Don't free params_buffer - it's managed by the uniform set
	

func generate_all_maps():
	# Generate all maps in the correct order
	generate_slope_map()
	generate_mean_height_map()
	generate_relative_height_map()
	generate_water_spread_map()
	generate_moisture_map()
	print("All derived maps generated successfully")

func get_map_as_image(texture_rid: RID) -> Image:
	# Read back texture data as Image (for debugging/visualization)
	# R32F format stores floats, need to convert to grayscale
	# Note: sync() should already have been called after compute shader execution
	
	# Try to get texture data
	var data := rd.texture_get_data(texture_rid, 0)
	if data.is_empty():
		push_error("Failed to get texture data - texture might not be readable")
		return null
	
	# Create image from R32F data
	var float_image := Image.create_from_data(map_size.x, map_size.y, false, Image.FORMAT_RF, data)
	if float_image == null or float_image.is_empty():
		push_error("Failed to create float image from texture data")
		return null
	
	# Convert to grayscale (R8) for visualization
	var grayscale_image := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
	if grayscale_image == null or grayscale_image.is_empty():
		push_error("Failed to create grayscale image")
		return null
	
	grayscale_image.fill(Color.BLACK)
	
	# Convert float values (0-1) to grayscale
	for y in range(map_size.y):
		for x in range(map_size.x):
			var float_value: float = float_image.get_pixel(x, y).r
			var gray_value: float = clamp(float_value, 0.0, 1.0)
			grayscale_image.set_pixel(x, y, Color(gray_value, gray_value, gray_value, 1.0))
	
	return grayscale_image

func save_map_as_png(texture_rid: RID, filepath: String) -> bool:
	# Save a map texture as a PNG file for inspection
	if not texture_rid.is_valid():
		push_error("Invalid texture RID")
		return false
	
	var image := get_map_as_image(texture_rid)
	if image == null:
		push_error("Failed to get image from texture for: " + filepath)
		return false
	
	var error := image.save_png(filepath)
	if error != OK:
		push_error("Failed to save image to: " + filepath + " (error code: " + str(error) + ")")
		return false
	
	return true

func save_all_maps_debug(output_dir: String = ""):
	# Save all generated maps as PNG files for inspection
	# Default: saves to maps/gpu-derived-maps/ in project root
	if output_dir.is_empty():
		# Get project root directory
		var project_root := ProjectSettings.globalize_path("res://")
		output_dir = project_root + "maps/gpu-derived-maps/"
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute(output_dir):
		var error := DirAccess.make_dir_recursive_absolute(output_dir)
		if error != OK:
			push_error("Failed to create directory: " + output_dir)
			return
	
	# Ensure output_dir is absolute
	if not output_dir.is_absolute_path():
		output_dir = ProjectSettings.globalize_path(output_dir)
	
	# Ensure trailing slash
	if not output_dir.ends_with("/"):
		output_dir += "/"
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute(output_dir):
		var error := DirAccess.make_dir_recursive_absolute(output_dir)
		if error != OK:
			push_error("Failed to create directory: " + output_dir)
			return
	
	# Save derived maps
	if slope_map_texture.is_valid():
		save_map_as_png(slope_map_texture, output_dir + "02_slope_map.png")
	if mean_height_map_texture.is_valid():
		save_map_as_png(mean_height_map_texture, output_dir + "03_mean_height_map.png")
	if relative_height_map_texture.is_valid():
		save_map_as_png(relative_height_map_texture, output_dir + "04_relative_height_map.png")
	if water_spread_map_texture.is_valid():
		save_map_as_png(water_spread_map_texture, output_dir + "05_water_spread_map.png")
	if moisture_map_texture.is_valid():
		save_map_as_png(moisture_map_texture, output_dir + "06_moisture_map.png")

func cleanup():
	# Free all resources
	if height_map_texture.is_valid():
		rd.free_rid(height_map_texture)
	if water_map_texture.is_valid():
		rd.free_rid(water_map_texture)
	if slope_map_texture.is_valid():
		rd.free_rid(slope_map_texture)
	if mean_height_map_texture.is_valid():
		rd.free_rid(mean_height_map_texture)
	if relative_height_map_texture.is_valid():
		rd.free_rid(relative_height_map_texture)
	if water_spread_map_texture.is_valid():
		rd.free_rid(water_spread_map_texture)
	if moisture_map_texture.is_valid():
		rd.free_rid(moisture_map_texture)
	if linear_sampler.is_valid():
		rd.free_rid(linear_sampler)
	if slope_shader.is_valid():
		rd.free_rid(slope_shader)
	if mean_height_shader.is_valid():
		rd.free_rid(mean_height_shader)
	if relative_height_shader.is_valid():
		rd.free_rid(relative_height_shader)
	if water_spread_shader.is_valid():
		rd.free_rid(water_spread_shader)
	if moisture_shader.is_valid():
		rd.free_rid(moisture_shader)
