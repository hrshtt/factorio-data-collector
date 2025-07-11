#!/bin/bash

# Script to copy all .lua files from replay-lab/scripts to target directory and zip it and copy to Factorio saves
# Usage: ./replay-dump-setup.sh <target_directory>

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

# Check if scripts directory exists
SCRIPTS_DIR="./replay-lab/lua-scripts"
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Error: scripts directory not found at $SCRIPTS_DIR"
    exit 1
fi

# Check if there are any .lua files in the scripts directory
LUA_FILES=$(find "$SCRIPTS_DIR" -name "*.lua" -type f)
if [ -z "$LUA_FILES" ]; then
    echo "Error: No .lua files found in $SCRIPTS_DIR"
    exit 1
fi

# Copy all .lua files from scripts directory to the target directory
echo "Copying .lua files from scripts directory to target directory..."
for lua_file in "$SCRIPTS_DIR"/*.lua; do
    if [ -f "$lua_file" ]; then
        filename=$(basename "$lua_file")
        cp "$lua_file" "$TARGET_DIR/"
        echo "  ✓ Copied $filename"
    fi
done
echo "✓ Copied all .lua files to $TARGET_DIR"

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
echo "   - Copied all .lua files from scripts directory to save directory"
echo "   - Zipped $BASE_NAME as $ZIP_NAME with correct directory structure"
echo "   - ZIP Hash: $ZIP_HASH"
echo "   - Deployed to Factorio saves directory"