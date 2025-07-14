# Factorio Replay Analysis Tool

A specialized module for extracting comprehensive player actions and game events from Factorio replay files into structured JSONL logs for detailed behavioral analysis.

## What This Module Does

This tool transforms Factorio replay files into structured event data using **four different logging approaches**:

### 1. **Action-Based Logging** (Default - FLE Compatible)
- **Semantic actions** designed for compatibility with [factorio-learning-environment](https://github.com/JackHopkins/factorio-learning-environment)
- High-level action abstractions: `craft_item_collated`, `place_entity`, `harvest_resource_collated`, `move_to_collated`
- Session-aware action grouping (e.g., collated crafting sessions)
- Observation actions: `get_entities`, `get_research_progress`, `inspect_inventory`
- **Use case**: Machine learning research, agent training, behavioral modeling

### 2. **Simple Category-Based Logging**
- Events split into focused categories: `movement`, `logistics`, `construction`, `gui`
- **Inventory state-diff tracking**: Deterministic inventory change detection
- **State-driven construction tracking**: Context-aware building with blueprint sessions
- **Periodic world snapshots**: Complete item counts every N ticks
- **Use case**: Human behavior analysis, gameplay pattern studies

### 3. **State-Based Domain Logging**
- **Domain-focused modules**: `map`, `entity`, `player`, `player_inventory`, `research`
- Pure state mutations tracked per domain
- Cross-domain event correlation
- **Use case**: Game state analysis, progression tracking, research studies

### 4. **Raw Event Logging**
- **Complete Factorio 1.1.110 event stream**: All game events logged as-is
- Minimal processing overhead
- Comprehensive event coverage with full context
- **Use case**: Low-level game engine analysis, debugging, complete data capture

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

### 2. Choose Your Logging Type

Select the appropriate logger based on your analysis needs:

| Logger Type | Best For | Output Files | File Size | Processing |
|-------------|----------|--------------|-----------|------------|
| **action** (default) | AI/ML research, agent training | 13+ semantic action files | Medium | High-level abstractions |
| **simple** | Human behavior analysis | 5 category files + snapshots | Large | Category-focused |
| **state** | Game state research | 5 domain files | Medium | Domain-focused |
| **raw** | Complete data capture, debugging | 1 comprehensive file | Very Large | Minimal |

```bash
# Action-based logging (default) - FLE compatible semantic actions
./replay-dump-setup.sh ../saves/your_save_name action

# Simple category-based logging - human behavior analysis
./replay-dump-setup.sh ../saves/your_save_name simple

# State-based domain logging - game state analysis  
./replay-dump-setup.sh ../saves/your_save_name state

# Raw event logging - complete event stream
./replay-dump-setup.sh ../saves/your_save_name raw
```

#### Choosing Guidelines:
- **Use `action`** for machine learning research, especially if working with [factorio-learning-environment](https://github.com/deepmind/lab2d/tree/main/dmlab2d/environments/factorio)
- **Use `simple`** for analyzing human gameplay patterns and behaviors
- **Use `state`** for studying game progression and state transitions  
- **Use `raw`** when you need complete event data or are unsure what you'll analyze

This script:
- Copies the selected logging scripts to your save directory
- Zips the save with proper structure
- Copies to Factorio's saves directory (`~/Library/Application Support/factorio/saves/`)

### 3. Run the Replay in Factorio

1. Open Factorio → **Single Player** → **Load Game**
2. Select your prepared save (look for the ▶️ play icon)
3. Click play icon to start replay
4. **Speed up to 64x** for faster logging

The replay automatically logs to different files based on the selected logger type:

#### Action-Based Logging Output (FLE Compatible)
```
~/Library/Application Support/factorio/script-output/replay-logs/
├── craft_item_collated.jsonl        # Collated crafting sessions
├── harvest_resource_collated.jsonl  # Resource mining sessions  
├── place_entity.jsonl               # Entity placement actions
├── pickup_entity.jsonl              # Entity removal actions
├── rotate_entity.jsonl              # Entity rotation actions
├── move_to_collated.jsonl           # Movement actions with pathfinding
├── set_entity_recipe.jsonl          # Machine recipe configuration
├── set_research.jsonl               # Technology research changes
├── launch_rocket.jsonl              # Rocket launches
├── send_message.jsonl               # Chat messages
├── player_inventory_transfers.jsonl # Inventory management
├── get_entities.jsonl               # Entity observations
├── get_research_progress.jsonl      # Research state observations
└── score.jsonl                      # Game score tracking
```

#### Simple Category-Based Logging Output  
```
~/Library/Application Support/factorio/script-output/replay-logs/
├── core-meta.jsonl     # Player join/leave events
├── movement.jsonl      # Player movement tracking
├── logistics.jsonl     # Inventory changes and transfers
├── construction.jsonl  # Building placement/removal
├── gui.jsonl          # Interface interactions
├── snapshot.jsonl     # Periodic world state snapshots
└── snapshot-*.json    # Detailed snapshot files
```

#### State-Based Domain Logging Output
```
~/Library/Application Support/factorio/script-output/replay-logs/
├── map.jsonl            # Map-related events
├── entity.jsonl         # Entity state changes
├── player.jsonl         # Player actions and state
├── player_inventory.jsonl # Player inventory changes
└── research.jsonl       # Research progression
```

#### Raw Event Logging Output
```
~/Library/Application Support/factorio/script-output/replay-logs/
└── raw_events.jsonl     # Complete Factorio event stream
```

### 4. Copy Replay Data

```bash
# Copy with timestamp-based naming
./replay-dump-setup.sh

# Or force overwrite
./replay-dump-setup.sh --force
```

This copies the logged data to `../factorio_replays/replay-logs/` for analysis.

## Logger Type Details

### Action-Based Logging (FLE Compatible)

Designed for compatibility with [factorio-learning-environment](https://github.com/deepmind/lab2d/tree/main/dmlab2d/environments/factorio), providing semantic action abstractions:

#### Collated Actions
**`craft_item_collated.jsonl`** - Groups crafting into sessions:
```json
{
  "tick": 5678,
  "action": "craft_item_collated", 
  "recipe": "iron-plate",
  "start_tick": 1234,
  "end_tick": 5678,
  "duration_ticks": 4444,
  "total_queued": 50,
  "total_crafted": 50,
  "total_cancelled": 0
}
```

**`move_to_collated.jsonl`** - Movement with pathfinding context:
```json
{
  "tick": 1234,
  "action": "move_to_collated",
  "start_position": {"x": 10.0, "y": 5.0},
  "end_position": {"x": 15.5, "y": 8.2},
  "path_length": 7.2,
  "movement_type": "walk"
}
```

#### Observation Actions
**`get_entities.jsonl`** - Entity queries for AI observation:
```json
{
  "tick": 1234,
  "action": "get_entities",
  "area": {"left_top": {"x": 0, "y": 0}, "right_bottom": {"x": 32, "y": 32}},
  "filter": "all"
}
```

### Simple Category-Based Logging

Traditional event categorization for human behavior analysis:

**`movement.jsonl`** - Player position tracking:
```json
{
  "tick": 1234,
  "player": 1,
  "position": {"x": 12.5, "y": 8.0},
  "context": {"action": "walk", "direction": "north"}
}
```

**`logistics.jsonl`** - Inventory change detection:
```json
{
  "tick": 1234,
  "player": 1,
  "item": "iron-plate",
  "delta": -50,
  "source": "player",
  "destination": "iron-chest"
}
```

### State-Based Domain Logging

Domain-focused event tracking for state analysis:

**`entity.jsonl`** - Entity state mutations:
```json
{
  "tick": 1234,
  "domain": "entity",
  "event": "on_built_entity",
  "entity_name": "assembling-machine-1",
  "position": {"x": 12.5, "y": 8.0}
}
```

### Raw Event Logging

Complete Factorio event stream with minimal processing:

**`raw_events.jsonl`** - All game events:
```json
{
  "tick": 1234,
  "event_name": "on_built_entity",
  "player_index": 1,
  "entity": {...},
  "raw_data": {...}
}
```

## Module File Structure

```
replay-lab/
├── action-based-logs/             # FLE-compatible semantic actions
│   ├── control.lua               # Action dispatcher and collation
│   └── script/
│       ├── shared-utils.lua      # Common utilities
│       ├── actions/              # Individual action modules
│       │   ├── craft_item_collated.lua
│       │   ├── place_entity.lua
│       │   ├── move_to_collated.lua
│       │   ├── get_entities.lua
│       │   └── ... (many action types)
│       └── tick_overlay.lua      # Debug overlay
├── simple-logs/                  # Category-based logging
│   ├── control.lua               # Event dispatcher
│   └── script/
│       ├── shared-utils.lua      # Common utilities  
│       ├── movement.lua          # Movement tracking
│       ├── logistics.lua         # Inventory changes
│       ├── construction.lua      # Building operations
│       ├── gui.lua              # Interface interactions
│       ├── snapshot.lua         # World state snapshots
│       └── tick_overlay.lua     # Debug overlay
├── state-based-logs/             # Domain-focused logging
│   ├── control.lua               # Domain dispatcher
│   └── script/
│       ├── shared-utils.lua      # Common utilities
│       ├── map.lua               # Map domain events
│       ├── entity.lua            # Entity domain events
│       ├── player.lua            # Player domain events
│       ├── player_inventory.lua  # Inventory domain events
│       ├── research.lua          # Research domain events
│       └── tick_overlay.lua      # Debug overlay
├── raw-logs/                     # Complete event logging
│   ├── control.lua               # Raw event dispatcher
│   └── script/
│       ├── shared-utils.lua      # Common utilities
│       └── tick_overlay.lua      # Debug overlay
├── replay-dump-setup.sh          # Logger setup script
├── replay-dump-copy.sh           # Data extraction utility
└── README.md                     # This documentation
```

## Configuration

All logging types share common configuration options that can be modified in their respective `control.lua` files:

### Buffer Settings (All Loggers)
Adjust flush frequency to control memory usage vs. disk I/O:
```lua
-- In any control.lua
local FLUSH_EVERY = 600  -- Every 10 seconds at 60 UPS (default)
local FLUSH_EVERY = 300  -- More frequent for memory-constrained systems
local FLUSH_EVERY = 1200 -- Less frequent for high-performance systems
```

### Logger-Specific Configuration

#### Action-Based Logging
Configure collation timeouts and session management:
```lua
-- In action-based-logs/script/actions/craft_item_collated.lua  
local COLLATION_TIMEOUT_TICKS = 600  -- 10 seconds timeout
local MAX_SESSION_GAP_TICKS = 300    -- 5 seconds max gap
```

#### Simple Category-Based Logging  
Configure snapshot frequency and memory limits:
```lua
-- In simple-logs/script/snapshot.lua
local SNAPSHOT_INTERVAL = 100000     -- Every ~28 minutes at 60 UPS
local MAX_INVENTORY_SNAPSHOTS = 1000 -- Memory cleanup threshold
```

#### Raw Event Logging
Configure event filtering to reduce file size:
```lua
-- In raw-logs/control.lua
local EXCLUDE_EVENTS = {
  [defines.events.on_tick] = true,           -- Skip high-frequency events
  [defines.events.on_gui_hover] = true,      -- Skip mouse hover events
}
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
   ./replay-dump-setup.sh ../saves/your_save_name
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
