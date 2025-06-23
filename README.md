# Factorio Replay Analysis Tool

A comprehensive tool for analyzing Factorio replay data by extracting player actions and game events into categorized JSONL logs for detailed behavioral analysis.

## Overview

This tool provides:
- **Category-based logging**: Events split into focused categories (movement, logistics, construction, GUI, etc.)
- **Inventory state-diff tracking**: Deterministic inventory change detection using before/after snapshots
- **Periodic world snapshots**: Complete item counts across all entities every N ticks
- **Robust analysis tools**: Python scripts for mining replay data and generating process models
- **Memory-efficient buffering**: Smart buffer management with automatic cleanup

## New Architecture (v0.2)

### Modular Logging System
The logging system has been completely refactored into specialized modules:

- **`core-meta.jsonl`**: Player join/leave events and replay markers
- **`movement.jsonl`**: Player position changes and movement patterns
- **`logistics.jsonl`**: Unified inventory change tracking with diff-based detection and precise item deltas
- **`construction.jsonl`**: Building placement, mining, blueprint operations
- **`gui.jsonl`**: Interface interactions and menu usage
- **`snapshot.jsonl`**: Periodic complete world state snapshots

### Unified Inventory Change Tracking
The new logistics system uses a hybrid approach:
- **GUI diff listener**: Detects manual transfers through inventory GUIs
- **Direct event logging**: Captures fast-transfers, crafting, mining immediately
- **Context tracking**: Prevents double-logging and provides rich action metadata
- **Single log function**: All inventory changes flow through `log_inventory_change()`

## Prerequisites

- **Factorio** installed on macOS
- **Python 3.8+** with pandas, pm4py for process mining analysis
- **Bash** shell (scripts are macOS-specific for now)

## Quick Start

### 1. Prepare Factorio Saves

Download Factorio saves to the `./saves/` directory:

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

```bash
./replay-lab/setup-logging-on-save.sh ./saves/your_save_name
```

This script:
- Copies all modular logging scripts to your save directory
- Zips the save with proper structure
- Copies to Factorio's saves directory (`~/Library/Application Support/factorio/saves/`)

### 3. Run the Replay in Factorio

1. Open Factorio → **Single Player** → **Load Game**
2. Select your prepared save (look for the ▶️ play icon)
3. Click play icon to start replay
4. **Speed up to 64x** for faster logging

The replay automatically logs to categorized files:
```
~/Library/Application Support/factorio/script-output/replay-logs/
├── core-meta.jsonl
├── movement.jsonl
├── logistics.jsonl
├── construction.jsonl
├── gui.jsonl
├── snapshot.jsonl
└── snapshot-*.json
```

### 4. Copy Replay Data

```bash
# Copy with timestamp-based naming
./replay-lab/copy-replay.sh

# Or force overwrite
./replay-lab/copy-replay.sh --force
```

### 5. Analyze the Data

#### Load Categorized Data
```python
import pandas as pd

# Load specific categories
movement_df = pd.read_json('./factorio_replays/replay-logs/movement.jsonl', lines=True)
logistics_df = pd.read_json('./factorio_replays/replay-logs/logistics.jsonl', lines=True)
construction_df = pd.read_json('./factorio_replays/replay-logs/construction.jsonl', lines=True)

# Explore movement patterns
print("Movement events:", len(movement_df))
print("Construction events:", len(construction_df))
print("Logistics events:", len(logistics_df))
```

#### Process Mining Analysis
```bash
# Mine behavioral patterns from replay data
python analysis/factorio_mining.py ./factorio_replays/replay-logs/construction.jsonl --outdir results/

# Mine movement traces
python analysis/mine_factorio_traces.py --category movement --outdir movement_analysis/
```

## Category Details

### Movement (`movement.jsonl`)
- Player position changes
- Walking patterns and pathfinding
- Position context for other events

### Logistics (`logistics.jsonl`)
- Unified inventory change detection with single `log_inventory_change()` function
- GUI diff listener for manual transfers (drag, drop, arrow buttons)
- Direct event logging for fast-transfers, crafting, mining, building
- One log entry per item type per change (no double-logging)
- Context tracking prevents missed transfers

Example logistics event:
```json
{
  "tick": 1234,
  "player": 1,
  "item": "iron-plate",
  "delta": -50,
  "source": "player",
  "destination": "iron-chest",
  "context": {
    "action": "gui_transfer",
    "entity": "iron-chest",
    "position": {"x": 12.5, "y": 8.0}
  }
}
```

### Construction (`construction.jsonl`)
- Entity placement and removal
- Mining operations
- Blueprint creation and deployment
- Building rotations and configurations

### GUI (`gui.jsonl`)
- Interface interactions
- Menu opening/closing
- Inventory panel usage
- Settings changes

### Snapshots (`snapshot.jsonl` + `snapshot-*.json`)
Complete world state every N ticks (default: 100,000 ≈ 28 minutes):
- All player inventories
- All entity inventories (chests, machines, etc.)
- Items on ground
- Fluid storage

## Analysis Tools

### `analysis/factorio_mining.py`
Advanced process mining with PM4Py:
- Segments traces into cases
- Filters low-frequency variants
- Discovers Petri nets
- Performs conformance checking

### `analysis/mine_factorio_traces.py`
Specialized trace analysis:
- Category-specific mining
- Behavioral pattern detection
- Time-series analysis

### `analysis/mine_factorio_replay.py`
Legacy replay.dat parser:
- Direct replay file parsing
- Lightweight event extraction
- PM4Py integration

## File Structure

```
factorio-rnd/
├── saves/                          # Factorio save directories
├── factorio_replays/               # Extracted replay logs
│   └── replay-logs/                # Categorized JSONL files
├── analysis/                       # Python analysis tools
│   ├── factorio_mining.py         # Advanced process mining
│   ├── mine_factorio_traces.py    # Trace analysis
│   └── mine_factorio_replay.py    # Legacy replay parser
├── replay-lab/
│   ├── lua-scripts/               # Modular logging system
│   │   ├── control.lua           # Main controller
│   │   ├── shared-utils.lua      # Common utilities
│   │   ├── movement.lua          # Movement tracking
│   │   ├── logistics.lua         # Inventory & transfers
│   │   ├── construction.lua      # Building operations
│   │   ├── gui.lua              # Interface tracking
│   │   └── snapshot.lua         # World snapshots
│   ├── setup-logging-on-save.sh  # Setup script
│   ├── copy-replay.sh            # Data extraction
│   ├── PRODUCTION_REFACTOR_README.md  # Technical details
│   └── SNAPSHOT_README.md        # Snapshot system docs
└── README.md
```

## Key Improvements in v0.3

### 1. **Deterministic Inventory Tracking**
- State-diff layer eliminates guesswork
- Exact item deltas for all transfers
- Robust handling of bulk operations

### 2. **Category-Based Organization**
- Events logically separated by domain
- Easier analysis of specific behaviors
- Reduced noise in focused datasets

### 3. **Memory Management**
- Automatic buffer flushing every 10 seconds
- Inventory snapshot cleanup
- Configurable memory limits

### 4. **Comprehensive Coverage**
- World snapshots for complete state tracking
- Replay start/end markers
- Enhanced player context

## Configuration

### Snapshot Frequency
Modify `SNAPSHOT_INTERVAL` in `snapshot.lua`:
```lua
local SNAPSHOT_INTERVAL = 100000  -- Every ~28 minutes
```

### Buffer Settings
Adjust flush frequency in `control.lua`:
```lua
local FLUSH_EVERY = 600  -- Every 10 seconds at 60 UPS
```

## Troubleshooting

### Common Issues

1. **Missing category files**: Check if all lua scripts are copied to save directory
2. **Large file sizes**: Increase snapshot interval for long replays
3. **Memory issues**: Reduce buffer size or flush frequency
4. **Analysis errors**: Ensure pandas/pm4py are installed

### Performance Tips

- **Speed up replays to 64x** for faster logging
- **Monitor file sizes** - logistics.jsonl can grow large
- **Use snapshots** for long-term analysis instead of full event logs

## Advanced Usage

### Custom Event Filtering
Modify individual category modules to filter specific events:

```lua
-- In logistics.lua, skip small transfers
if total_transferred < 10 then
  return false  -- Skip logging
end
```

### Integration with External Tools
Category-based logs are designed for:
- **Process mining** with PM4Py
- **Time-series analysis** with pandas
- **Behavioral modeling** with scikit-learn
- **Visualization** with matplotlib/plotly

## Development

The modular architecture makes it easy to:
- Add new event categories
- Modify existing loggers
- Integrate with analysis pipelines
- Extend snapshot functionality

See `PRODUCTION_REFACTOR_README.md` and `SNAPSHOT_README.md` for technical implementation details.
