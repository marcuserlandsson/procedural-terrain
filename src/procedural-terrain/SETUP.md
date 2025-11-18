# Godot Project Setup

## Map Files

To use the terrain visualization, you need to copy your maps into the Godot project:

1. Create the maps directory structure in the Godot project:
   ```
   src/procedural-terrain/maps/
   ├── heightmaps/
   └── watermaps/
   ```

2. Copy your height maps to `src/procedural-terrain/maps/heightmaps/`
3. Copy your water maps to `src/procedural-terrain/maps/watermaps/`

Alternatively, you can create symlinks or adjust the paths in the `terrain.gd` script.

## Usage

1. Open the project in Godot 4.5
2. The main scene (`main.tscn`) should automatically load
3. You can adjust the terrain parameters in the Inspector:
   - `height_map_path`: Path to height map
   - `water_map_path`: Path to water map
   - `terrain_scale`: Scale factor (1.0 = 1 unit per pixel, default: 1.0)
   - `height_scale`: Height multiplier (default: 20)
   - `resolution`: Mesh resolution (default: 256)

## Controls

- **Mouse**: Look around (mouse is captured automatically)
- **WASD**: Move forward/backward/left/right
- **Space**: Move up
- **Ctrl**: Move down
- **Shift + Movement**: Move faster
- **ESC**: Release/capture mouse cursor

The terrain will be generated automatically when the scene loads.

