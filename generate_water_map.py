#!/usr/bin/env python3
"""
Simple Water Map Generator
Creates water maps from height maps by thresholding pixel values.
"""

import argparse
from PIL import Image
import numpy as np
from pathlib import Path

# Change this to adjust the water threshold
pixel_threshold = 40


def apply_water_smoothing(water_map, sigma=2.0):
    """
    Apply Gaussian smoothing to water map for more natural water bodies.
    
    Args:
        water_map: Binary water map (0 or 255)
        sigma: Gaussian blur sigma (higher = more smoothing)
    
    Returns:
        Smoothed water map
    """
    try:
        from scipy import ndimage
        
        # Convert to float for processing
        result = water_map.astype(np.float32) / 255.0
        
        # Apply Gaussian blur
        result = ndimage.gaussian_filter(result, sigma=sigma)
        
        # Convert back to 0-255 range
        result = (np.clip(result, 0, 1) * 255).astype(np.uint8)
        
        return result
    except ImportError:
        print("Warning: scipy not available, skipping smoothing")
        print("Install with: pip install scipy")
        return water_map


def generate_water_map(heightmap_path, threshold, output_path=None, smooth=False, sigma=2.0):
    """
    Generate water map from height map.
    
    Args:
        heightmap_path: Path to input height map image
        threshold: Pixel value threshold (0-255). Pixels below this = water
        output_path: Output path (default: same name in derived-watermaps folder)
        smooth: Whether to apply Gaussian smoothing (default: False)
        sigma: Gaussian blur sigma for smoothing (default: 2.0)
    """
    # Load image
    img = Image.open(heightmap_path)
    
    # Handle different image formats
    if img.mode == 'I' or img.mode == 'I;16':
        # Load 16-bit data directly and convert to 8-bit
        pixels_16bit = np.array(img, dtype=np.uint16)
        if pixels_16bit.max() > 0:
            pixels = (pixels_16bit.astype(np.float32) / pixels_16bit.max() * 255).astype(np.uint8)
        else:
            pixels = pixels_16bit.astype(np.uint8)
    elif img.mode != 'L':
        img = img.convert('L')
        pixels = np.array(img, dtype=np.uint8)
    else:
        pixels = np.array(img, dtype=np.uint8)
    
    # Create water map: pixels below threshold = water (white), else = land (black)
    water_map = (pixels < threshold).astype(np.uint8) * 255
    
    # Apply smoothing if requested
    if smooth:
        water_map = apply_water_smoothing(water_map, sigma)
    
    # Determine output path
    if output_path is None:
        heightmap_path = Path(heightmap_path)
        output_dir = heightmap_path.parent.parent / "derived-watermaps"
        output_dir.mkdir(exist_ok=True)
        output_path = output_dir / heightmap_path.name
    
    # Save water map
    output_img = Image.fromarray(water_map, mode='L')
    output_img.save(output_path)
    
    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Generate water maps from height maps"
    )
    parser.add_argument(
        "heightmap",
        type=str,
        help="Path to input height map image"
    )
    parser.add_argument(
        "-t", "--threshold",
        type=int,
        default=pixel_threshold,
        help="Pixel value threshold (0-255, default: 76). Lower values = water"
    )
    parser.add_argument(
        "-o", "--output",
        type=str,
        default=None,
        help="Output path (default: same name in derived-watermaps folder)"
    )
    parser.add_argument(
        "-s", "--smooth",
        action="store_true",
        help="Apply Gaussian smoothing to water map"
    )
    parser.add_argument(
        "--sigma",
        type=float,
        default=2.0,
        help="Gaussian blur sigma for smoothing (default: 2.0, higher = more smoothing)"
    )
    
    args = parser.parse_args()
    
    generate_water_map(args.heightmap, args.threshold, args.output, args.smooth, args.sigma)


if __name__ == "__main__":
    main()
