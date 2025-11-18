# Procedural Terrain
Project for the course DD2470, Advanced Topics in Visualization and Computer Graphics, at KTH

# Implementation plan

## Phase 1: Foundation — Map loading and basic terrain
1. Load Height and Water maps (from image files)
2. Basic terrain mesh from Height map (simple plane with vertex displacement)
3. Visualize the maps (debug view to see what we're working with)

## Phase 2: Derived maps (GPU compute)
4. Slope map (from Height map)
5. Mean Height map (weighted average)
6. Relative Height map (Height - Mean Height)
7. Water Spread map (moisture diffusion from water)
8. Moisture map (combine all factors)

## Phase 3: Simple plant distribution
9. Single layer distribution (start with one plant type)
10. Adaptability curves (Height, Slope, Moisture parameters)
11. Poisson Disk position tiles (pre-generated)
12. Position evaluation (GPU compute shader that evaluates each position)

## Phase 4: Multi-layer ecosystem
13. Layer system (L1, L2, L3)
14. Predominance values (multiple plant types per layer)
15. Density map (distance field for interaction)
16. Layer-by-layer distribution (top to bottom)

## Phase 5: Rendering
17. GPU instancing setup
18. Basic plant models (simple meshes)
19. Render all instances from position buffer

## Phase 6: Optimization (if needed)
20. Simple quadtree/culling (only if performance requires it)
21. View distance limits


# Heightmaps

https://manticorp.github.io/unrealheightmap/

https://www.motionforgepictures.com/height-maps/