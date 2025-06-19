#!/bin/bash

# Default source path
SOURCE_PATH="$HOME/Library/Application Support/factorio/script-output/factorio_replays/replay-log.jsonl"
TARGET_DIR="./factorio_replays"

# Function to show usage
show_usage() {
    echo "Usage: $0 [-f|--force]"
    echo "  -f, --force    Overwrite existing replay-log.jsonl without renaming"
    echo "  -h, --help     Show this help message"
}

# Function to extract timestamp from replay-log.jsonl
extract_timestamp() {
    local file_path="$1"
    
    # Try to get the first timestamp from the JSONL file
    # Look for "timestamp" field in the first few lines
    local timestamp=$(head -n 10 "$file_path" | grep -o '"timestamp":[0-9]*' | head -n 1 | cut -d':' -f2)
    
    if [ -n "$timestamp" ]; then
        # Convert Unix timestamp to YYYYMMDD_HHMMSS format
        date -r "$timestamp" "+%Y%m%d_%H%M%S" 2>/dev/null
    else
        # Fallback to current timestamp if no timestamp found in file
        date "+%Y%m%d_%H%M%S"
    fi
}

# Parse command line arguments
FORCE_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_OVERWRITE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if source file exists
if [ ! -f "$SOURCE_PATH" ]; then
    echo "Error: Source file not found: $SOURCE_PATH"
    exit 1
fi

# Create target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# Determine target filename
if [ "$FORCE_OVERWRITE" = true ]; then
    TARGET_FILE="$TARGET_DIR/replay-log.jsonl"
    echo "Copying with force overwrite to: $TARGET_FILE"
    cp "$SOURCE_PATH" "$TARGET_FILE"
    echo "Successfully copied replay-log.jsonl (overwritten)"
else
    # Extract timestamp and create unique filename
    TIMESTAMP=$(extract_timestamp "$SOURCE_PATH")
    TARGET_FILE="$TARGET_DIR/factorio_replay_${TIMESTAMP}.jsonl"
    
    # Ensure unique filename by adding counter if needed
    COUNTER=1
    ORIGINAL_TARGET_FILE="$TARGET_FILE"
    while [ -f "$TARGET_FILE" ]; do
        TARGET_FILE="${ORIGINAL_TARGET_FILE%.jsonl}_${COUNTER}.jsonl"
        ((COUNTER++))
    done
    
    echo "Copying to: $TARGET_FILE"
    cp "$SOURCE_PATH" "$TARGET_FILE"
    echo "Successfully copied replay-log.jsonl as: $(basename "$TARGET_FILE")"
fi
