# Procedural Terrain - Vegetation Distribution Research Project

Project for the course DD2470, Advanced Topics in Visualization and Computer Graphics, at KTH

## Research Question

**"How does procedurally generated environments affect the perceived realism of GPU-Based procedural distribution of vegetation?"**

This project implements a simplified version of the GPU-based procedural vegetation distribution framework from the research paper, with the goal of comparing vegetation distribution on:

- **Input maps**: Real-world height and water maps (baseline)
- **Procedurally generated maps**: Algorithmically generated height and water maps (for comparison)

The comparison will evaluate how the source of terrain data affects the perceived realism of the vegetation distribution.

## Project Overview

This project implements a GPU-based procedural vegetation distribution system based on the paper's framework. The system uses:

- **Height maps** and **Water maps** as input
- **Ecosystem layers** (L1: large trees, L2: shrubs, L3: ground plants)
- **Adaptability Parameters** (Height, Slope, Moisture, Interaction)
- **GPU compute shaders** for map generation and plant distribution
- **GPU instancing** for efficient rendering

## Current Implementation Status

### ✅ Phase 1: Foundation - COMPLETED

1. **Map Loading and Terrain Visualization** ✅

   - Loads height maps (16-bit PNG support)
   - Loads water maps (derived from height maps)
   - Creates procedural terrain mesh from height map
   - Visualizes water as blue semi-transparent mesh
   - Terrain mesh resolution matches image size (1:1 pixel-to-vertex)

2. **Water Map Generation** ✅

   - Python script to derive water maps from height maps
   - Threshold-based water detection (dark pixels = water)
   - Optional Gaussian smoothing for natural water bodies
   - Handles 16-bit height maps correctly

3. **Camera System** ✅
   - Fly camera with mouse look
   - WASD movement controls
   - Space/Ctrl for vertical movement
   - Shift for faster movement

### ✅ Phase 2: Derived Maps - COMPLETED

1. **GPU Compute Shader Infrastructure** ✅

   - MapManager class for managing compute shader execution
   - RenderingDevice setup for GPU computation
   - Shader loading and pipeline management

2. **Derived Map Generation** ✅

   - **Slope Map**: Local terrain height variation (parameterized distance: 12px)
   - **Mean Height Map**: Weighted average of surrounding heights (radius: 32px)
   - **Relative Height Map**: Height - Mean Height (depressions vs elevations)
   - **Water Spread Map**: Moisture infiltration from water bodies (radius: 32px)
   - **Moisture Map**: Final soil moisture compiled from all factors

3. **Integration** ✅
   - Maps generated on GPU using compute shaders
   - All maps stored as single-channel textures (0-1 normalized)
   - Maps never transferred to RAM (stay in VRAM for Phase 3)
   - Debug visualization: Maps can be saved as PNG files for inspection

### Debugging Generated Maps and Plant Distribution

To verify that the generated maps and plant distribution are correct:

1. **Enable map generation**: Set `should_generate_derived_maps = true` in the Terrain node
2. **Enable plant distribution**: Set `should_distribute_plants = true` in the Terrain node (requires Phase 2)
3. **Enable debug saving**: Set `save_debug_maps = true` in the Terrain node
4. **Run the scene**: Maps and plant positions will be saved to `maps/gpu-derived-maps/` directory in the project root
5. **Check the output**: Look in `maps/gpu-derived-maps/` folder in your project directory

The saved maps will be:

- `02_slope_map.png` - Generated slope map (white = steep, black = flat)
- `03_mean_height_map.png` - Generated mean height map (smoothed height)
- `04_relative_height_map.png` - Generated relative height (0.5 = average, <0.5 = depressions, >0.5 = elevations)
- `05_water_spread_map.png` - Generated water spread (moisture from water bodies)
- `06_moisture_map.png` - Final moisture map (compiled from all factors)
- `plant_positions.png` - Plant positions visualization (when Phase 3 is enabled)

### ✅ Phase 3: Plant Distribution - COMPLETED

1. **Poisson Disk Distribution** ✅

   - Pre-generated position tiles using Bridson's algorithm
   - Ensures minimum distance between positions (8px default)
   - Tile-based distribution across the entire map

2. **Position Evaluation System** ✅

   - GPU compute shader implementing EVALUATEPOSITION algorithm from paper
   - Evaluates each position against Height, Slope, and Moisture maps
   - Uses adaptability curves to determine placement probability
   - Follows paper's algorithm structure (lines 2-20 from Figure 9)

3. **Adaptability Parameters** ✅

   - **Height**: Prefers mid-range elevations (0.15-0.85 normalized)
   - **Slope**: Prefers flatter areas (rejects slopes > 0.6)
   - **Moisture**: Favors higher moisture (near water) with smooth falloff
   - Balanced distribution: more plants near water, some in drier areas

4. **Integration** ✅
   - PlantDistribution manager orchestrates the distribution process
   - Stores valid plant positions in array for Phase 5 rendering
   - Optional debug visualization saves plant positions as PNG image
   - Density map generation (prepared for Phase 4 multi-layer)

### 🔄 Next Steps (Not Yet Implemented)

- Phase 4: Multi-layer ecosystem
- Phase 5: GPU instancing for rendering
- Phase 6: Procedural terrain generation (for comparison study)

## Setup Instructions

### Prerequisites

- **Godot 4.5** or later
- **Python 3** with packages: `numpy`, `Pillow`, `scipy` (optional, for smoothing)

### Python Dependencies

```bash
pip install -r requirements.txt
```

### Map Files Setup

1. **Height Maps**: Place your height map PNG files in `maps/heightmaps/`

   - Supports 8-bit and 16-bit PNG images
   - Recommended sources:
     - [Terrain.party](https://terrain.party/)
     - [OpenTopography](https://opentopography.org/)
     - [USGS EarthExplorer](https://earthexplorer.usgs.gov/)

2. **Water Maps**: Generate water maps from height maps:

   ```bash
   # Single map
   python generate_water_map.py maps/heightmaps/YourMap.png

   # All maps in batch
   python generate_all_water_maps.py

   # With smoothing
   python generate_all_water_maps.py -s
   ```

   Water maps will be saved to `maps/derived-watermaps/`

3. **Godot Project**: Copy maps to Godot project:
   ```
   src/procedural-terrain/maps/
   ├── heightmaps/    (copy your height maps here)
   └── watermaps/     (copy generated water maps here)
   ```

### Running the Project

1. Open `src/procedural-terrain/project.godot` in Godot 4.5
2. The main scene (`main.tscn`) will load automatically
3. Press F5 or click Play to run
4. Use mouse to look around, WASD to move

## File Structure

```
procedural-terrain/
├── README.md                    # This file
├── requirements.txt             # Python dependencies
├── generate_water_map.py        # Water map generation script
├── generate_all_water_maps.py   # Batch water map generator
├── maps/
│   ├── heightmaps/              # Input height maps
│   └── derived-watermaps/       # Generated water maps
├── Paper/
│   └── Text                     # Research paper text
└── src/procedural-terrain/      # Godot project
    ├── project.godot
    ├── main.tscn                # Main scene
    ├── terrain.gd               # Terrain generation script
    ├── camera_controller.gd     # Camera controls
    ├── map_manager.gd           # Phase 2: Derived map generation
    ├── plant_distribution.gd    # Phase 3: Plant distribution manager
    ├── plant_type.gd            # Plant type resource with adaptability parameters
    ├── poisson_disk.gd          # Poisson Disk Distribution generator
    ├── SETUP.md                 # Additional setup details
    ├── shaders/                 # GPU compute shaders
    │   ├── slope_map.glsl
    │   ├── mean_height_map.glsl
    │   ├── relative_height_map.glsl
    │   ├── water_spread_map.glsl
    │   ├── moisture_map.glsl
    │   └── evaluate_positions.glsl  # Phase 3: Position evaluation
    └── maps/                    # Maps for Godot (copy from root maps/)
        ├── heightmaps/
        ├── watermaps/
        └── gpu-derived-maps/    # Generated maps and debug outputs
```

## Technical Details

### Terrain Generation

- **Mesh Resolution**: Automatically matches image size (1:1 pixel-to-vertex)
  - Can be overridden with `resolution` parameter in Inspector
  - Default: `-1` (auto-match image size)
- **Terrain Scale**: `terrain_scale` parameter (default: 1.0 = 1 unit per pixel)
- **Height Scale**: `height_scale` parameter (default: 20.0)
- **Coordinate System**: Terrain centered at origin (0,0,0)

### Water Map Generation

- **Threshold**: Pixel value threshold (0-255, default: 40)
  - Lower = less water (only very dark areas)
  - Higher = more water (dark + medium areas)
- **Smoothing**: Optional Gaussian blur for natural water bodies
  - Use `-s` flag to enable
  - Adjust with `--sigma` parameter (default: 2.0)

### Water Level Calculation

The water level is calculated based on **shoreline height**:

1. Finds all land pixels adjacent to water pixels (shoreline)
2. Calculates average height of shoreline pixels
3. Uses that as the constant water level
4. This ensures water matches the height of banks/shorelines

### Camera Controls

- **Mouse**: Look around (captured by default)
- **WASD**: Move forward/backward/left/right
- **Space**: Move up
- **Ctrl**: Move down
- **Shift + Movement**: Move faster
- **ESC**: Release/capture mouse cursor

## Implementation Plan (Original)

### Phase 1: Foundation — Map loading and basic terrain ✅

1. ✅ Load Height and Water maps (from image files)
2. ✅ Basic terrain mesh from Height map (simple plane with vertex displacement)
3. ✅ Visualize the maps (debug view to see what we're working with)

### Phase 2: Derived maps (GPU compute) ✅

4. ✅ Slope map (from Height map)
5. ✅ Mean Height map (weighted average)
6. ✅ Relative Height map (Height - Mean Height)
7. ✅ Water Spread map (moisture diffusion from water)
8. ✅ Moisture map (combine all factors)

### Phase 3: Simple plant distribution ✅

9. ✅ Single layer distribution (start with one plant type)
10. ✅ Adaptability curves (Height, Slope, Moisture parameters)
11. ✅ Poisson Disk position tiles (pre-generated)
12. ✅ Position evaluation (GPU compute shader that evaluates each position)

### Phase 4: Multi-layer ecosystem

13. Layer system (L1, L2, L3)
14. Predominance values (multiple plant types per layer)
15. Density map (distance field for interaction)
16. Layer-by-layer distribution (top to bottom)

### Phase 5: Rendering

17. GPU instancing setup
18. Basic plant models (simple meshes or billboards)
19. Render all instances from position buffer

### Phase 6: Optimization (if needed)

20. Simple quadtree/culling (only if performance requires it)
21. View distance limits

### Phase 7: Procedural Generation (for research comparison)

22. Procedural height map generation
23. Procedural water map generation
24. Comparison system between input and procedural maps

## Key Design Decisions

1. **Simplified Implementation**: Not implementing full quadtree/priority queue system initially - keeping it simple
2. **Godot Engine**: Chosen for GPU compute support, open source, and good for research
3. **Map Format**: Using PNG images (supports 16-bit) for height and water maps
4. **Water Level**: Based on shoreline height (not water area height) for realistic water levels
5. **Mesh Resolution**: Matches image size by default for 1:1 pixel accuracy

## Notes

- The paper's full implementation uses a quadtree, priority queues, and fixed-size buffers for large-scale terrains
- Our simplified version focuses on the core vegetation distribution algorithm
- Procedural terrain generation will be added later for the research comparison
- All code follows professional/scientific standards (no casual language in code/comments)

## Resources

- **Height Map Sources**:
  - [Terrain.party](https://terrain.party/)
  - [OpenTopography](https://opentopography.org/)
  - [USGS EarthExplorer](https://earthexplorer.usgs.gov/)
  - [Motion Forge Pictures](https://www.motionforgepictures.com/height-maps/)

## License

This project is for academic research purposes.
