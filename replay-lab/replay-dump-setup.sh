#!/bin/bash

# Script to copy control.lua and script directory from chosen replay-lab directory to target directory and zip it
# Usage: ./replay-dump-setup.sh <target_directory> [script_type]

set -e  # Exit on any error

# Function to print usage
usage() {
    echo "Usage: $0 <target_directory> [script_type]"
    echo "Script types: simple, state, action (default: action)"
    echo "Example: $0 ./saves/4_12_54 action"
    exit 1
}

# Check if target directory is provided
if [ $# -eq 0 ]; then
    echo "Error: No target directory specified"
    usage
fi

TARGET_DIR="$1"
SCRIPT_TYPE="${2:-action}"  # Default to action if not specified

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

# Set scripts directory based on script type
case "$SCRIPT_TYPE" in
    "simple")
        SCRIPTS_DIR="./replay-lab/simple-logs"
        ;;
    "state")
        SCRIPTS_DIR="./replay-lab/state-based-logs"
        ;;
    "action")
        SCRIPTS_DIR="./replay-lab/action-based-logs"
        ;;
    "observation")
        SCRIPTS_DIR="./replay-lab/observation-logs"
        ;;
    "raw")
        SCRIPTS_DIR="./replay-lab/raw-logs"
        ;;
    *)
        echo "Error: Invalid script type '$SCRIPT_TYPE'. Use: simple, state, action, or raw"
        exit 1
        ;;
esac

# Check if scripts directory exists
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Error: scripts directory not found at $SCRIPTS_DIR"
    exit 1
fi

# Check if control.lua exists in the scripts directory
if [ ! -f "$SCRIPTS_DIR/control.lua" ]; then
    echo "Error: control.lua not found in $SCRIPTS_DIR"
    exit 1
fi

# Check if script directory exists
if [ ! -d "$SCRIPTS_DIR/script" ]; then
    echo "Error: script directory not found in $SCRIPTS_DIR"
    exit 1
fi

# Remove existing script directory from target if it exists
if [ -d "$TARGET_DIR/script" ]; then
    echo "Removing existing script directory from target..."
    rm -rf "$TARGET_DIR/script"
    echo "  ✓ Removed existing script directory"
fi

# Copy control.lua and script directory to target
echo "Copying control.lua and script directory from $SCRIPTS_DIR to $TARGET_DIR..."
cp "$SCRIPTS_DIR/control.lua" "$TARGET_DIR/"
cp -r "$SCRIPTS_DIR/script" "$TARGET_DIR/"
echo "  ✓ Copied control.lua and script directory"

# Get the parent directory and basename for zipping
PARENT_DIR="$(dirname "$TARGET_DIR")"
BASE_NAME="$(basename "$TARGET_DIR")"
ZIP_NAME="$BASE_NAME.zip"

# Remove existing zip file if it exists
if [ -f "$ZIP_NAME" ]; then
    rm "$ZIP_NAME"
    echo "Removed existing $ZIP_NAME"
fi

# Create zip file
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

# Copy zip to factorio saves directory
echo "Copying $ZIP_NAME to Factorio saves directory..."
cp "./$ZIP_NAME" "$FACTORIO_SAVES"
echo "✓ Copied $ZIP_NAME to $FACTORIO_SAVES"

# Clean up local zip file
rm "$ZIP_NAME"
echo "✓ Cleaned up local zip file"

echo ""
echo "🎉 Operation completed successfully!"
echo "   - Used $SCRIPT_TYPE logging scripts from $SCRIPTS_DIR"
echo "   - Copied control.lua and script directory to save directory"
echo "   - Zipped $BASE_NAME as $ZIP_NAME"
echo "   - ZIP Hash: $ZIP_HASH"
echo "   - Deployed to Factorio saves directory"