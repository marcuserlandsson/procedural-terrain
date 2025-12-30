extends Resource
class_name PlantType

# Plant type definition with adaptability parameters
# Each parameter uses a curve to define probability based on map value

@export var name: String = "Plant"
@export var predominance: float = 1.0  # Relative probability of this plant type (for multi-type layers)

# Adaptability curves (Curve resources)
# Each curve maps map value (0-1) to probability multiplier (0-1)
@export var height_curve: Curve  # Height map -> probability
@export var slope_curve: Curve    # Slope map -> probability
@export var moisture_curve: Curve # Moisture map -> probability
@export var interaction_curve: Curve  # Density map -> probability (for multi-layer)

# Plant properties
@export var trunk_radius: float = 0.5  # Trunk radius for collision detection
@export var zone_of_influence: float = 2.0  # Zone of Influence (ZOI) for density calculation

func evaluate_height(height_value: float) -> float:
	# Evaluate height adaptability curve
	if height_curve:
		return height_curve.sample(height_value)
	return 1.0

func evaluate_slope(slope_value: float) -> float:
	# Evaluate slope adaptability curve
	if slope_curve:
		return slope_curve.sample(slope_value)
	return 1.0

func evaluate_moisture(moisture_value: float) -> float:
	# Evaluate moisture adaptability curve
	if moisture_curve:
		return moisture_curve.sample(moisture_value)
	return 1.0

func evaluate_interaction(density_value: float) -> float:
	# Evaluate interaction adaptability curve
	if interaction_curve:
		return interaction_curve.sample(density_value)
	return 1.0

