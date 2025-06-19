#!/bin/bash

# Script to copy control.lua to target directory and zip it and copy to Factorio saves
# Usage: ./setup-logging-on-save.sh <target_directory>

set -e  # Exit on any error

# Function to print usage
usage() {
    echo "Usage: $0 <target_directory>"
    echo "Example: $0 ./saves/4_12_54"
    exit 1
}

# Check if target directory is provided
if [ $# -eq 0 ]; then
    echo "Error: No target directory specified"
    usage
fi

TARGET_DIR="$1"

# Remove trailing slash if present
TARGET_DIR="${TARGET_DIR%/}"

# Check if target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory '$TARGET_DIR' does not exist"
    exit 1
fi

# Check if target directory contains replay.dat
if [ ! -f "$TARGET_DIR/replay.dat" ]; then
    echo "Error: Target directory '$TARGET_DIR' does not contain replay.dat"
    echo "This script only runs when the target directory contains replay.dat"
    exit 1
fi

echo "✓ Found replay.dat in target directory"

# Check if control.lua exists in the project root
CONTROL_LUA_SOURCE="./replay-lab/control.lua"
if [ ! -f "$CONTROL_LUA_SOURCE" ]; then
    echo "Error: control.lua not found in current directory"
    exit 1
fi

# Copy control.lua to the target directory
echo "Copying control.lua to target directory..."
cp "$CONTROL_LUA_SOURCE" "$TARGET_DIR/"
echo "✓ Copied control.lua to $TARGET_DIR"

# Get the parent directory and basename
PARENT_DIR="$(dirname "$TARGET_DIR")"
BASE_NAME="$(basename "$TARGET_DIR")"
ZIP_NAME="$BASE_NAME.zip"

# Remove existing zip file if it exists
if [ -f "$ZIP_NAME" ]; then
    rm "$ZIP_NAME"
    echo "Removed existing $ZIP_NAME"
fi

# Change to parent directory and zip just the basename
echo "Creating zip file: $ZIP_NAME"
(cd "$PARENT_DIR" && zip -q -r "../$ZIP_NAME" "./$BASE_NAME/")
echo "✓ Created zip file: $ZIP_NAME"

# Calculate and display hash of the zip file
ZIP_HASH=$(shasum -a 256 "$ZIP_NAME" | cut -d' ' -f1)
echo "📋 ZIP Hash (SHA256): $ZIP_HASH"

# Define factorio saves directory
FACTORIO_SAVES="$HOME/Library/Application Support/factorio/saves/"

# Create factorio saves directory if it doesn't exist
mkdir -p "$FACTORIO_SAVES"
echo "✓ Ensured Factorio saves directory exists"

# Copy zip to factorio saves directory
echo "Copying $ZIP_NAME to Factorio saves directory..."
cp "./$ZIP_NAME" "$FACTORIO_SAVES"
echo "✓ Copied $ZIP_NAME to $FACTORIO_SAVES"

# Clean up local zip file
rm "$ZIP_NAME"
echo "✓ Cleaned up local zip file"

echo ""
echo "🎉 Operation completed successfully!"
echo "   - Copied control.lua to save directory"
echo "   - Zipped $BASE_NAME as $ZIP_NAME with correct directory structure"
echo "   - ZIP Hash: $ZIP_HASH"
echo "   - Deployed to Factorio saves directory"