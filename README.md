# Factorio Gameplay Data Collection

A comprehensive toolkit for collecting and analyzing Factorio gameplay data through multiple approaches including replay analysis, blueprint extraction, and live gameplay monitoring.

## Overview

This repository provides a modular approach to Factorio data collection with different specialized tools:

- **`replay-lab/`**: Comprehensive replay analysis tool for extracting player actions and game events
- **`analysis/`**: Python analysis scripts for process mining and behavioral pattern detection
- **Additional modules** (planned): Blueprint analysis, live gameplay monitoring, level data extraction

## Key Features

- **Multi-category event logging**: Split events into focused categories (movement, logistics, construction, GUI)
- **Advanced process mining**: Generate process models and perform conformance checking
- **Inventory state tracking**: Deterministic inventory change detection with precise deltas
- **Blueprint analysis**: Session tracking and pattern recognition
- **Time-series analysis**: Behavioral modeling and trend detection

## Quick Start

### Prerequisites

- **Factorio** installed on macOS
- **Python 3.8+** with pandas, pm4py for analysis
- **Bash** shell (scripts are macOS-specific for now)

### Basic Workflow

1. **Prepare data source** (currently supports replay files)
2. **Extract events** using appropriate module
3. **Analyze patterns** with provided analysis tools

For detailed instructions, see the specific module documentation:
- [Replay Analysis Guide](./replay-lab/README.md)

## Analysis Tools

### Process Mining (`analysis/factorio_mining.py`)
Advanced behavioral analysis with PM4Py:
- Segments traces into meaningful cases
- Filters low-frequency variants for cleaner models
- Discovers Petri nets from player behavior
- Performs conformance checking against discovered models

```bash
python analysis/factorio_mining.py ./factorio_replays/replay-logs/construction.jsonl --outdir results/
```

### Trace Analysis (`analysis/mine_factorio_traces.py`)
Specialized pattern detection:
- Category-specific behavioral mining
- Time-series pattern recognition
- Player strategy identification

```bash
python analysis/mine_factorio_traces.py --category movement --outdir movement_analysis/
```

### Legacy Replay Parser (`analysis/mine_factorio_replay.py`)
Direct replay.dat file processing:
- Lightweight event extraction
- PM4Py integration for existing replay files

## Data Categories

All modules generate events in standardized categories:

### Movement
- Player position changes and pathfinding
- Walking patterns and movement efficiency
- Spatial behavior analysis

### Logistics
- Inventory transfers and item management
- Crafting patterns and resource flow
- Storage optimization strategies

### Construction
- Building placement and factory layout
- Blueprint usage and modification patterns
- Infrastructure development strategies

### GUI Interactions
- Interface usage patterns
- Menu navigation behavior
- Settings and configuration preferences

## Project Structure

```
factorio-rnd/
├── saves/                          # Input Factorio save files
├── factorio_replays/               # Extracted replay data
│   └── replay-logs/                # Categorized JSONL event files
├── analysis/                       # Analysis and mining tools
│   ├── factorio_mining.py         # Advanced process mining
│   ├── mine_factorio_traces.py    # Trace pattern analysis
│   ├── mine_factorio_replay.py    # Legacy replay parser
│   └── analyze_unknown_sources.py # Source identification
├── replay-lab/                     # Replay analysis module
│   ├── lua-scripts/               # Factorio logging scripts
│   ├── setup-logging-on-save.sh  # Replay setup automation
│   ├── copy-replay.sh            # Data extraction utility
│   └── README.md                 # Detailed replay guide
├── runtime-api.json               # Factorio API reference
├── events_v1.1.110.md            # Event documentation
└── snapshot-*.json               # World state snapshots
```

## Data Analysis Examples

### Loading Event Data
```python
import pandas as pd

# Load categorized events
movement_df = pd.read_json('./factorio_replays/replay-logs/movement.jsonl', lines=True)
logistics_df = pd.read_json('./factorio_replays/replay-logs/logistics.jsonl', lines=True)
construction_df = pd.read_json('./factorio_replays/replay-logs/construction.jsonl', lines=True)

# Basic analysis
print(f"Movement events: {len(movement_df)}")
print(f"Construction events: {len(construction_df)}")
print(f"Logistics events: {len(logistics_df)}")
```

### Process Discovery
```python
from pm4py import discover_petri_net_inductive
from pm4py.objects.conversion.log import converter as log_converter

# Convert to PM4Py event log format
log = log_converter.apply(construction_df, parameters={
    log_converter.Variants.TO_EVENT_LOG.value.Parameters.CASE_ID_KEY: 'case_id',
    log_converter.Variants.TO_EVENT_LOG.value.Parameters.ACTIVITY_KEY: 'action',
    log_converter.Variants.TO_EVENT_LOG.value.Parameters.TIMESTAMP_KEY: 'tick'
})

# Discover process model
net, initial_marking, final_marking = discover_petri_net_inductive(log)
```

## Configuration

### Python Dependencies
```bash
pip install pandas pm4py matplotlib plotly scikit-learn
```

### Analysis Parameters
Modify analysis scripts for different focus areas:
- **Time windows**: Adjust trace segmentation periods
- **Filtering thresholds**: Set minimum event frequencies
- **Categories**: Enable/disable specific event types

## Contributing

When adding new data collection modules:

1. **Follow category structure**: Use standardized event categories
2. **Maintain JSONL format**: Ensure compatibility with analysis tools
3. **Document thoroughly**: Include setup and usage instructions
4. **Test integration**: Verify compatibility with existing analysis pipeline

## Advanced Usage

### Custom Analysis Pipelines
The modular design supports integration with:
- **Machine learning** frameworks (scikit-learn, TensorFlow)
- **Visualization** libraries (matplotlib, plotly, seaborn)
- **Time-series analysis** tools (statsmodels, Prophet)
- **Network analysis** packages (NetworkX, graph-tool)

### Performance Optimization
For large datasets:
- Use **category filtering** to focus analysis
- Implement **chunked processing** for memory efficiency
- Leverage **parallel processing** for multi-core systems

## Future Modules

Planned extensions to the data collection toolkit:
- **Blueprint analyzer**: Static blueprint pattern analysis
- **Live monitor**: Real-time gameplay event capture
- **Mod integration**: Custom event logging for modded gameplay
- **Multiplayer tracker**: Multi-player interaction analysis

