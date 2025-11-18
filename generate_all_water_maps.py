#!/usr/bin/env python3
"""
Batch process all height maps in the heightmaps folder.
"""

import argparse
import subprocess
import sys
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(
        description="Batch process all height maps in the heightmaps folder"
    )
    parser.add_argument(
        "-t", "--threshold",
        type=int,
        default=None,
        help="Pixel value threshold (0-255). If not specified, uses default from generate_water_map.py"
    )
    parser.add_argument(
        "-s", "--smooth",
        action="store_true",
        help="Apply Gaussian smoothing to water maps"
    )
    parser.add_argument(
        "--sigma",
        type=float,
        default=2.0,
        help="Gaussian blur sigma for smoothing (default: 2.0)"
    )
    
    args = parser.parse_args()
    
    heightmaps_dir = Path("maps/heightmaps")
    if not heightmaps_dir.exists():
        print(f"Error: {heightmaps_dir} not found")
        sys.exit(1)
    
    heightmaps = list(heightmaps_dir.glob("*.png"))
    if not heightmaps:
        print(f"No PNG files found in {heightmaps_dir}")
        sys.exit(1)
    
    print(f"Found {len(heightmaps)} height maps to process")
    if args.smooth:
        print(f"Smoothing enabled (sigma: {args.sigma})")
    if args.threshold:
        print(f"Threshold: {args.threshold}")
    print()
    
    for heightmap in heightmaps:
        print(f"\n{'='*60}")
        print(f"Processing: {heightmap.name}")
        print(f"{'='*60}")
        
        cmd = [
            sys.executable,
            "generate_water_map.py",
            str(heightmap)
        ]
        
        if args.threshold:
            cmd.extend(["-t", str(args.threshold)])
        
        if args.smooth:
            cmd.append("-s")
            cmd.extend(["--sigma", str(args.sigma)])
        
        subprocess.run(cmd)
    
    print(f"\n{'='*60}")
    print("All done! Check maps/derived-watermaps/ for results")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()

