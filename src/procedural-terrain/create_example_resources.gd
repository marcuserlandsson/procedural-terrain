@tool
extends EditorScript

# Helper script to create example PlantType and Ecosystem resources
# Run this from Godot's Script menu: Script > Run Script

func _run():
	print("Creating example plant resources...")
	
	# Create resources directory if it doesn't exist
	var resources_dir := "res://resources/"
	if not DirAccess.dir_exists_absolute(resources_dir):
		DirAccess.make_dir_recursive_absolute(resources_dir)
	
	# Create Layer 1 plant: Large Tree
	var large_tree := PlantType.new()
	large_tree.name = "Large Tree"
	large_tree.predominance = 1.0
	large_tree.trunk_radius = 1.0
	large_tree.zone_of_influence = 5.0
	var large_tree_path := resources_dir + "plant_type_large_tree.tres"
	ResourceSaver.save(large_tree, large_tree_path)
	print("Created: ", large_tree_path)
	
	# Create Layer 2 plant: Shrub
	var shrub := PlantType.new()
	shrub.name = "Shrub"
	shrub.predominance = 1.0
	shrub.trunk_radius = 0.5
	shrub.zone_of_influence = 2.0
	var shrub_path := resources_dir + "plant_type_shrub.tres"
	ResourceSaver.save(shrub, shrub_path)
	print("Created: ", shrub_path)
	
	# Create Layer 3 plant: Grass
	var grass := PlantType.new()
	grass.name = "Grass"
	grass.predominance = 1.0
	grass.trunk_radius = 0.1
	grass.zone_of_influence = 0.5
	var grass_path := resources_dir + "plant_type_grass.tres"
	ResourceSaver.save(grass, grass_path)
	print("Created: ", grass_path)
	
	# Create Ecosystem with all three layers
	var ecosystem := Ecosystem.new()
	
	# Load plant types
	var large_tree_res := load(large_tree_path) as PlantType
	var shrub_res := load(shrub_path) as PlantType
	var grass_res := load(grass_path) as PlantType
	
	if large_tree_res:
		ecosystem.layer1_plants = [large_tree_res]
	if shrub_res:
		ecosystem.layer2_plants = [shrub_res]
	if grass_res:
		ecosystem.layer3_plants = [grass_res]
	
	var ecosystem_path := resources_dir + "ecosystem_forest.tres"
	ResourceSaver.save(ecosystem, ecosystem_path)
	print("Created: ", ecosystem_path)
	
	print("\nExample resources created successfully!")
	print("Assign 'ecosystem_forest.tres' to the Terrain node's Ecosystem Resource field.")
