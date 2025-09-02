#!/usr/bin/env python3
"""
iOS App Icon Generator for MyArea App

This script generates all required iOS app icon sizes from a source image.
Place your source image (preferably 1024x1024 or larger) in the same directory
and run this script to generate all the required icon files.
"""

import os
from PIL import Image
import sys

# iOS App Icon sizes required (from Contents.json)
ICON_SIZES = [
    # iPhone icons
    {"size": 20, "scale": 2, "filename": "Icon-App-20x20@2x.png"},
    {"size": 20, "scale": 3, "filename": "Icon-App-20x20@3x.png"},
    {"size": 29, "scale": 1, "filename": "Icon-App-29x29@1x.png"},
    {"size": 29, "scale": 2, "filename": "Icon-App-29x29@2x.png"},
    {"size": 29, "scale": 3, "filename": "Icon-App-29x29@3x.png"},
    {"size": 40, "scale": 2, "filename": "Icon-App-40x40@2x.png"},
    {"size": 40, "scale": 3, "filename": "Icon-App-40x40@3x.png"},
    {"size": 60, "scale": 2, "filename": "Icon-App-60x60@2x.png"},
    {"size": 60, "scale": 3, "filename": "Icon-App-60x60@3x.png"},
    
    # iPad icons
    {"size": 20, "scale": 1, "filename": "Icon-App-20x20@1x.png"},
    {"size": 29, "scale": 1, "filename": "Icon-App-29x29@1x.png"},
    {"size": 40, "scale": 1, "filename": "Icon-App-40x40@1x.png"},
    {"size": 76, "scale": 1, "filename": "Icon-App-76x76@1x.png"},
    {"size": 76, "scale": 2, "filename": "Icon-App-76x76@2x.png"},
    {"size": 83.5, "scale": 2, "filename": "Icon-App-83.5x83.5@2x.png"},
    
    # App Store icon
    {"size": 1024, "scale": 1, "filename": "Icon-App-1024x1024@1x.png"},
]

def find_source_image():
    """Find the source image file in the current directory"""
    image_extensions = ['.png', '.jpg', '.jpeg', '.tiff', '.bmp']
    
    for file in os.listdir('.'):
        if any(file.lower().endswith(ext) for ext in image_extensions):
            return file
    
    return None

def generate_icons(source_image_path, output_dir):
    """Generate all iOS app icon sizes from source image"""
    try:
        # Open the source image
        with Image.open(source_image_path) as img:
            # Convert to RGBA if necessary
            if img.mode != 'RGBA':
                img = img.convert('RGBA')
            
            print(f"Source image: {source_image_path}")
            print(f"Original size: {img.size}")
            print(f"Mode: {img.mode}")
            print()
            
            # Create output directory if it doesn't exist
            os.makedirs(output_dir, exist_ok=True)
            
            # Generate each icon size
            for icon_spec in ICON_SIZES:
                size = icon_spec["size"]
                scale = icon_spec["scale"]
                filename = icon_spec["filename"]
                
                # Calculate actual pixel dimensions
                actual_size = int(size * scale)
                
                # Resize the image
                resized_img = img.resize((actual_size, actual_size), Image.Resampling.LANCZOS)
                
                # Save the icon
                output_path = os.path.join(output_dir, filename)
                resized_img.save(output_path, 'PNG', optimize=True)
                
                print(f"Generated: {filename} ({actual_size}x{actual_size}px)")
            
            print(f"\nAll icons generated successfully in: {output_dir}")
            
    except Exception as e:
        print(f"Error generating icons: {e}")
        return False
    
    return True

def main():
    print("MyArea iOS App Icon Generator")
    print("=" * 40)
    
    # Find source image
    source_image = find_source_image()
    if not source_image:
        print("No source image found!")
        print("Please place your source image (PNG, JPG, etc.) in this directory.")
        print("Recommended size: 1024x1024 pixels or larger.")
        return
    
    # Set output directory
    output_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    
    print(f"Source image found: {source_image}")
    print(f"Output directory: {output_dir}")
    print()
    
    # Confirm before proceeding
    response = input("Proceed with generating icons? (y/N): ").strip().lower()
    if response not in ['y', 'yes']:
        print("Operation cancelled.")
        return
    
    # Generate icons
    if generate_icons(source_image, output_dir):
        print("\n✅ Success! Your iOS app icons have been generated.")
        print("You can now build your iOS app with the new icons.")
    else:
        print("\n❌ Failed to generate icons. Please check the error messages above.")

if __name__ == "__main__":
    main()
