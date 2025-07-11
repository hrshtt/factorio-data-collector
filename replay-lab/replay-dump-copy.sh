#!/bin/bash

# Default source path - now points to the replay-logs directory
SOURCE_PATH="$HOME/Library/Application Support/factorio/script-output/replay-logs"
TARGET_DIR="./factorio_replays"

# Function to show usage
show_usage() {
    echo "Usage: $0 [-f|--force]"
    echo "  -f, --force    Overwrite existing replay-logs directory without renaming"
    echo "  -h, --help     Show this help message"
}

# Function to extract timestamp from any JSONL file in the directory
extract_timestamp() {
    local dir_path="$1"
    
    # Find the first JSONL file and try to get timestamp from it
    local first_jsonl=$(find "$dir_path" -name "*.jsonl" | head -n 1)
    
    if [ -n "$first_jsonl" ] && [ -f "$first_jsonl" ]; then
        # Try to get the first timestamp from the JSONL file
        # Look for "timestamp" field in the first few lines
        local timestamp=$(head -n 10 "$first_jsonl" | grep -o '"timestamp":[0-9]*' | head -n 1 | cut -d':' -f2)
        
        if [ -n "$timestamp" ]; then
            # Convert Unix timestamp to YYYYMMDD_HHMMSS format
            date -r "$timestamp" "+%Y%m%d_%H%M%S" 2>/dev/null
        else
            # Fallback to current timestamp if no timestamp found in file
            date "+%Y%m%d_%H%M%S"
        fi
    else
        # Fallback to current timestamp if no JSONL files found
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

# Check if source directory exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Error: Source directory not found: $SOURCE_PATH"
    exit 1
fi

# Create target directory if it doesn't exist
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# Determine target directory name
if [ "$FORCE_OVERWRITE" = true ]; then
    TARGET_REPLAY_DIR="$TARGET_DIR/replay-logs"
    echo "Copying with force overwrite to: $TARGET_REPLAY_DIR"
    
    # Remove existing directory if it exists
    if [ -d "$TARGET_REPLAY_DIR" ]; then
        rm -rf "$TARGET_REPLAY_DIR"
    fi
    
    cp -r "$SOURCE_PATH" "$TARGET_REPLAY_DIR"
    echo "Successfully copied replay-logs directory (overwritten)"
else
    # Extract timestamp and create unique directory name
    TIMESTAMP=$(extract_timestamp "$SOURCE_PATH")
    TARGET_REPLAY_DIR="$TARGET_DIR/factorio_replay_${TIMESTAMP}"
    
    # Ensure unique directory name by adding counter if needed
    COUNTER=1
    ORIGINAL_TARGET_DIR="$TARGET_REPLAY_DIR"
    while [ -d "$TARGET_REPLAY_DIR" ]; do
        TARGET_REPLAY_DIR="${ORIGINAL_TARGET_DIR}_${COUNTER}"
        ((COUNTER++))
    done
    
    echo "Copying to: $TARGET_REPLAY_DIR"
    cp -r "$SOURCE_PATH" "$TARGET_REPLAY_DIR"
    echo "Successfully copied replay-logs directory as: $(basename "$TARGET_REPLAY_DIR")"
fi
