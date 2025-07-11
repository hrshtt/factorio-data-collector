# Factorio Replay Analysis Tool

A specialized module for extracting comprehensive player actions and game events from Factorio replay files into categorized JSONL logs for detailed behavioral analysis.

## What This Module Does

This tool transforms Factorio replay files into structured event data by:
- **Category-based logging**: Events split into focused categories (movement, logistics, construction, GUI, etc.)
- **Inventory state-diff tracking**: Deterministic inventory change detection using before/after snapshots
- **State-driven construction tracking**: Context-aware construction logging with blueprint session management
- **Periodic world snapshots**: Complete item counts across all entities every N ticks
- **Modular architecture**: Specialized Lua modules for different event types

## Architecture Overview

### Modular Logging System
The logging system consists of specialized modules:

- **`core-meta.jsonl`**: Player join/leave events and replay markers
- **`movement.jsonl`**: Player position changes and movement patterns
- **`logistics.jsonl`**: Unified inventory change tracking with diff-based detection and precise item deltas
- **`construction.jsonl`**: State-driven building placement, mining, blueprint operations with context tracking
- **`gui.jsonl`**: Interface interactions and menu usage
- **`snapshot.jsonl`**: Periodic complete world state snapshots

### State-Driven Construction Tracking
The construction system features:
- **Context tracking**: GUI state and ephemeral contexts provide rich action metadata
- **Event-driven logging**: Direct event capture with contextual enhancement
- **Blueprint session tracking**: Blueprint library/book usage with session duration
- **Unified logging**: All construction actions flow through `log_construction_action()`
- **Memory efficient**: No entity polling - only tracks active construction contexts

### Unified Inventory Change Tracking
The logistics system uses a hybrid approach:
- **GUI diff listener**: Detects manual transfers through inventory GUIs
- **Direct event logging**: Captures fast-transfers, crafting, mining immediately
- **Context tracking**: Prevents double-logging and provides rich action metadata
- **Single log function**: All inventory changes flow through `log_inventory_change()`

## Setup and Usage

### 1. Prepare Factorio Saves

Download or copy Factorio saves to the `../saves/` directory:

```
../saves/
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
./replay-dump-setup.sh ../saves/your_save_name
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
./replay-dump-setup.sh

# Or force overwrite
./replay-dump-setup.sh --force
```

This copies the logged data to `../factorio_replays/replay-logs/` for analysis.

## Event Categories Detail

### Movement (`movement.jsonl`)
Tracks player position changes and movement patterns:
```json
{
  "tick": 1234,
  "player": 1,
  "position": {"x": 12.5, "y": 8.0},
  "context": {
    "action": "walk",
    "direction": "north"
  }
}
```

### Logistics (`logistics.jsonl`)
Unified inventory change detection with single `log_inventory_change()` function:
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
State-driven approach with context tracking:
- Entity placement and removal with context
- Mining operations
- Blueprint creation and deployment with session tracking
- Building rotations and configurations
- Equipment placement/removal
- Context-aware action logging (build zones, blueprint sessions, etc.)

Example construction event:
```json
{
  "tick": 1234,
  "player": 1,
  "action": "build",
  "entity": "assembling-machine-1",
  "context": {
    "action": "build",
    "entity": "assembling-machine-1",
    "position": {"x": 12.5, "y": 8.0},
    "from_blueprint": true,
    "blueprint_digest": "0eNpdy9EKgz..."
  }
}
```

### GUI (`gui.jsonl`)
Interface interactions and menu usage:
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

## Module File Structure

```
replay-lab/
├── lua-scripts/                    # Modular logging system
│   ├── control.lua                # Main controller and event routing
│   ├── shared-utils.lua           # Common utilities and helpers
│   ├── movement.lua               # Movement tracking module
│   ├── logistics.lua              # Inventory & transfer tracking
│   ├── construction.lua           # Building operations module
│   ├── gui.lua                    # Interface interaction tracking
│   ├── snapshot.lua               # World state snapshots
│   └── tick_overlay.lua           # Debug overlay (optional)
├── replay-dump-setup.sh       # Automated save setup
├── replay-dump-setup.sh                 # Data extraction utility
└── README.md                      # This documentation
```

## Configuration

### Snapshot Frequency
Modify `SNAPSHOT_INTERVAL` in `snapshot.lua`:
```lua
local SNAPSHOT_INTERVAL = 100000  -- Every ~28 minutes at 60 UPS
```

### Buffer Settings
Adjust flush frequency in `control.lua`:
```lua
local FLUSH_EVERY = 600  -- Every 10 seconds at 60 UPS
```

### Memory Management
Configure memory limits and cleanup:
```lua
-- In control.lua
local MAX_INVENTORY_SNAPSHOTS = 1000
local MAX_CONSTRUCTION_CONTEXTS = 500
```

## Performance and Memory Management

### Key Improvements in Current Version

1. **State-Driven Construction Logging**
   - Context-aware construction tracking
   - Blueprint session management with duration tracking
   - Ephemeral context for multi-event construction sequences
   - No performance-heavy entity polling

2. **Deterministic Inventory Tracking**
   - State-diff layer eliminates guesswork
   - Exact item deltas for all transfers
   - Robust handling of bulk operations

3. **Memory Management**
   - Automatic buffer flushing every 10 seconds
   - Inventory snapshot cleanup
   - Configurable memory limits

### Performance Tips

- **Speed up replays to 64x** for faster logging
- **Monitor file sizes** - logistics.jsonl can grow large for active players
- **Use snapshots** for long-term analysis instead of full event logs
- **Adjust buffer sizes** based on available memory

## Troubleshooting

### Common Issues

1. **Missing category files**: Check if all lua scripts are copied to save directory
   ```bash
   ls ~/Library/Application\ Support/factorio/saves/your_save_name/
   # Should show all .lua files
   ```

2. **Large file sizes**: Increase snapshot interval for long replays
   ```lua
   -- In snapshot.lua
   local SNAPSHOT_INTERVAL = 200000  -- Longer interval
   ```

3. **Memory issues**: Reduce buffer size or flush frequency
   ```lua
   -- In control.lua
   local FLUSH_EVERY = 300  -- More frequent flushes
   ```

4. **Incomplete logging**: Verify save directory structure
   ```bash
   ./replay-dump-setup.sh ../saves/your_save_name --verbose
   ```

### Debug Options

Enable debug output in `control.lua`:
```lua
local DEBUG_MODE = true  -- Shows logging activity in game console
```

Use tick overlay for visual debugging:
```lua
-- In control.lua, uncomment:
-- require("tick_overlay")
```

## Custom Event Filtering

Modify individual category modules to filter specific events:

```lua
-- In logistics.lua, skip small transfers
if total_transferred < 10 then
  return false  -- Skip logging
end

-- In construction.lua, focus on specific entities
local TRACKED_ENTITIES = {
  ["assembling-machine-1"] = true,
  ["transport-belt"] = true,
  -- Add entities of interest
}

if not TRACKED_ENTITIES[entity_name] then
  return false
end
```

## Integration with Analysis Pipeline

The replay-lab output is designed to integrate seamlessly with the project's analysis tools:

```bash
# After running replay analysis, use main project tools:
cd ..
python analysis/factorio_mining.py ./factorio_replays/replay-logs/construction.jsonl --outdir results/
python analysis/mine_factorio_traces.py --category movement --outdir movement_analysis/
```

For more analysis options, see the main project [README](../README.md).

## Development and Extension

The modular architecture makes it easy to:
- **Add new event categories**: Create new module in `lua-scripts/`
- **Modify existing loggers**: Edit specific category modules
- **Integrate custom events**: Add hooks in `control.lua`
- **Extend snapshot functionality**: Modify `snapshot.lua`

### Adding a New Category

1. Create `lua-scripts/your_category.lua`
2. Implement required functions: `init()`, `log_event()`, etc.
3. Register in `control.lua`:
   ```lua
   local your_category = require("your_category")
   your_category.init()
   ```
4. Add event handlers as needed

### Custom Context Tracking

Follow the logistics/construction pattern for context-aware logging:
```lua
-- Track context state
local active_context = {}

-- Log with context
local function log_with_context(event_data)
  event_data.context = active_context
  shared_utils.write_to_file("your_category.jsonl", event_data)
end
```
