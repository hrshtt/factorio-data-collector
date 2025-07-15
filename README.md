# Factorio Gameplay Data Collection

A comprehensive toolkit for collecting and analyzing Factorio gameplay data through multiple approaches including replay analysis, blueprint extraction, and live gameplay monitoring.

## Overview

This repository provides a modular approach to Factorio data collection with different specialized tools:

- **`replay-lab/`**: Comprehensive replay analysis tool for extracting player actions and game events
- **Additional modules** (planned): Blueprint analysis, live gameplay monitoring, level data extraction

## Key Features

- **Multi-category event logging**: Split events into focused categories (movement, logistics, construction, GUI)
- **Inventory state tracking**: Deterministic inventory change detection with precise deltas
- **Blueprint analysis**: Session tracking and pattern recognition TBD for actions
- **Time-series analysis**: Behavioral modeling and trend detection TBD

## Quick Start

### Prerequisites

- **Factorio** installed on macOS
- **Bash** shell (scripts are macOS-specific for now)

### Basic Workflow

1. **Prepare data source** (currently supports replay files)
2. **Extract events** using appropriate module
3. **Analyze patterns** with provided analysis tools

For detailed instructions, see the specific module documentation:
- [Replay Analysis Guide](./replay-lab/README.md)

## Future Modules

Planned extensions to the data collection toolkit:
- **Blueprint analyzer**: Static blueprint pattern analysis
- **Live monitor**: Real-time gameplay event capture
- **Mod integration**: Custom event logging for modded gameplay
- **Multiplayer tracker**: Multi-player interaction analysis

