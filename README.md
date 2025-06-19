# Factorio Replay Analysis Tool

A comprehensive tool for analyzing Factorio replay data by extracting player actions and game events into structured JSON logs.

## Overview

This tool allows you to:
- Extract detailed player actions and game events from Factorio replay files
- Log all interactions to structured JSONL format for analysis
- Analyze replay data using Python/pandas for insights into player behavior

## Prerequisites

- **Factorio** installed on macOS
- **Python 3.8+** with pandas for data analysis
- **Bash** shell (scripts are macOS-specific for now)

## Workflow

### 1. Prepare Factorio Saves

Download Factorio saves to the `./saves/` directory. The saves must:
- Be extracted as directories (not zip files)
- Contain a `replay.dat` file for replay functionality

**Example structure:**
```
./saves/
├── my_save_1/
│   ├── replay.dat
│   ├── level.dat
│   └── ...
└── my_save_2/
    ├── replay.dat
    ├── level.dat
    └── ...
```

### 2. Setup Logging for a Save

Use the helper script to prepare a save for replay logging:

```bash
./replay-lab/setup-logging-on-save.sh ./saves/your_save_name
```

This script will:
- Copy the logging `control.lua` file to your save directory
- Zip the save with the correct directory structure
- Copy the zip to Factorio's saves directory (`~/Library/Application Support/factorio/saves/`)

**Note:** This script currently only works on macOS.

### 3. Run the Replay in Factorio

1. Open Factorio
2. Go to **Main Menu** → **Single Player** → **Load Game**
3. Select the save you prepared in step 2
4. You'll see a **play icon** (▶️) in the top-right corner of the GUI
5. Click the play icon to start the replay
6. **Important:** Speed up the replay to **64x** to hasten the logging process

The replay will automatically log all player actions and game events to:
```
~/Library/Application Support/factorio/script-output/factorio_replays/replay-log.jsonl
```

### 4. Copy Replay Data

When the replay finishes (for now you'll need to manually detect this), copy the replay data:

```bash
# Copy with timestamp-based naming (recommended)
./replay-lab/copy-replay.sh

# Or force overwrite existing file
./replay-lab/copy-replay.sh --force
```

This copies the replay log to `./factorio_replays/` with a timestamp-based filename or as `replay-log.jsonl`.

### 5. Analyze the Data (Optional)

Load and analyze the JSONL data using pandas:

```python
import pandas as pd

# Load the replay data
df = pd.read_json('./factorio_replays/factorio_replay_YYYYMMDD_HHMMSS.jsonl', lines=True)

# Explore the data
print(df.head())
print(df.columns)
print(df['action'].value_counts())
```

## File Structure

```
factorio-rnd/
├── saves/                          # Factorio save directories
├── factorio_replays/               # Extracted replay logs
├── replay-lab/
│   ├── control.lua                 # Factorio mod for logging
│   ├── setup-logging-on-save.sh    # Setup script for saves
│   └── copy-replay.sh              # Copy replay data script
└── README.md
```

## Logged Data

The replay logging captures various player actions and game events including:

- **Building actions**: Placing/removing entities
- **Mining actions**: Mining resources and entities
- **Inventory operations**: Moving items, crafting
- **Blueprint operations**: Creating, using, and managing blueprints
- **Player movement**: Position changes and context
- **GUI interactions**: Opening/closing interfaces
- **Research**: Technology research actions

Each log entry includes:
- Timestamp and tick number
- Player information
- Action type and details
- Entity/item information
- Player context (position, selected items, etc.)

## WIP

This project is still a work in progress, it does not guarantee that the complete set of logs needed to confirm all gameplay activity are logged, doing this comprehensively is the actual intent of the repo. 

## Troubleshooting

### Common Issues

1. **"replay.dat not found"**: Ensure your save directory contains a `replay.dat` file
2. **Script permission errors**: Make scripts executable with `chmod +x replay-lab/*.sh`
3. **Factorio not finding save**: Check that the save was properly copied to Factorio's saves directory
4. **No play button**: Ensure the save contains replay data and was properly prepared

### Manual Steps

- **Detecting replay completion**: Currently manual - watch for the replay to finish
- **Multiple replays**: Each replay will overwrite the previous log file unless you copy it first

## Development

The logging system is implemented as a Factorio psuedo-mod in `replay-lab/control.lua`. It hooks into various game events and logs them to JSONL format for easy analysis.
