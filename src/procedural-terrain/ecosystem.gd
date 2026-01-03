extends Resource
class_name Ecosystem

# Ecosystem definition for multi-layer plant distribution
# Defines plant types per layer with predominance values

# Layer definitions (L1 = large trees, L2 = shrubs, L3 = ground plants)
@export var layer1_plants: Array[PlantType] = []  # Large trees (h > 6m)
@export var layer2_plants: Array[PlantType] = []  # Small trees, shrubs (1.5m ≤ h ≤ 6m)
@export var layer3_plants: Array[PlantType] = []  # Ground plants, herbs (h < 1.5m)

func get_layer_plants(layer: int) -> Array[PlantType]:
	# Get plant types for a specific layer (1, 2, or 3)
	match layer:
		1:
			return layer1_plants
		2:
			return layer2_plants
		3:
			return layer3_plants
		_:
			return []

func select_plant_type(layer: int) -> PlantType:
	# Select a plant type from the layer based on predominance values
	# Returns null if layer is empty
	var plants := get_layer_plants(layer)
	if plants.is_empty():
		return null
	
	# Calculate total predominance (should be 1.0, but handle edge cases)
	var total_predominance := 0.0
	for plant in plants:
		total_predominance += plant.predominance
	
	if total_predominance <= 0.0:
		# Fallback: equal probability
		return plants[randi() % plants.size()]
	
	# Select based on predominance (stochastic selection)
	var random_value := randf() * total_predominance
	var cumulative := 0.0
	
	for plant in plants:
		cumulative += plant.predominance
		if random_value <= cumulative:
			return plant
	
	# Fallback (shouldn't happen)
	return plants[0]

func validate_predominance(layer: int) -> bool:
	# Check if predominance values sum to approximately 1.0 for a layer
	var plants := get_layer_plants(layer)
	if plants.is_empty():
		return true  # Empty layer is valid
	
	var total := 0.0
	for plant in plants:
		total += plant.predominance
	
	# Allow some tolerance (0.95 to 1.05)
	return total >= 0.95 and total <= 1.05
