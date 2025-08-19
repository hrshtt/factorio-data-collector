import json
import re
import ast
import time
import threading
from pathlib import Path
from typing import Dict, Any, List
from fle.env import FactorioInstance
from fle.env.entities import Direction, Position
from fle.commons.cluster_ips import get_local_container_ips
from log_analyzer import analyze_logs_example


class TickScheduler:
    """Handles real-time tick scheduling at 60 ticks per second."""
    
    def __init__(self, speed: float = 1.0):
        self.start_time = None
        self.tick_duration = 1.0 / 60.0 / speed  # 60 ticks per second
        
    def start(self):
        """Start the tick timer."""
        self.start_time = time.time()
        
    def wait_for_tick(self, target_tick: int):
        """Wait until the specified tick time has arrived."""
        if self.start_time is None:
            raise ValueError("Scheduler not started. Call start() first.")
            
        target_time = self.start_time + (target_tick * self.tick_duration)
        current_time = time.time()
        
        if target_time > current_time:
            sleep_duration = target_time - current_time
            print(f"\033[92mWaiting {sleep_duration:.3f}s for tick {target_tick}\033[0m")
            time.sleep(sleep_duration)
        else:
            # If we're behind schedule, note it but don't wait
            delay = current_time - target_time
            print(f"\033[94mWarning: Tick {target_tick} is {delay:.3f}s behind schedule\033[0m")
            
    def get_current_tick(self) -> int:
        """Get the current tick based on elapsed time."""
        if self.start_time is None:
            return 0
        elapsed = time.time() - self.start_time
        return int(elapsed / self.tick_duration)


# Global file handles for logging
entities_log_file = None
inventory_log_file = None


def initialize_logging(log_dir: str = "logs"):
    """Initialize logging files for entities and inventory data."""
    global entities_log_file, inventory_log_file
    
    # Create logs directory if it doesn't exist
    log_path = Path(log_dir)
    log_path.mkdir(exist_ok=True)
    
    # Initialize log files
    entities_log_file = open(log_path / "entities_log.jsonl", "w")
    inventory_log_file = open(log_path / "inventory_log.jsonl", "w")
    
    print(f"Initialized logging to {log_path}/entities_log.jsonl and {log_path}/inventory_log.jsonl")


def cleanup_logging():
    """Close logging files."""
    global entities_log_file, inventory_log_file
    
    if entities_log_file:
        entities_log_file.close()
        entities_log_file = None
    
    if inventory_log_file:
        inventory_log_file.close()
        inventory_log_file = None


def log_data(log_file, tick: int, data: Any):
    """Log data to a file in JSONL format for pandas reading."""
    if log_file:
        log_entry = {
            "tick": tick,
            "data": data
        }
        log_file.write(json.dumps(log_entry) + "\n")
        log_file.flush()  # Ensure data is written immediately


def parse_function_call(call_string: str) -> tuple[str, Dict[str, Any]]:
    """Parse a function call string into function name and arguments."""
    # Extract function name and arguments using regex
    match = re.match(r'(\w+)\((.*)\)', call_string)
    if not match:
        raise ValueError(f"Invalid function call format: {call_string}")
    
    func_name = match.group(1)
    args_string = match.group(2)
    
    # Parse arguments
    args = {}
    if args_string.strip():
        # Split arguments by comma, but handle nested structures
        arg_pairs = []
        paren_count = 0
        bracket_count = 0
        brace_count = 0
        current_arg = ""
        
        for char in args_string:
            if char in '([{':
                if char == '(':
                    paren_count += 1
                elif char == '[':
                    bracket_count += 1
                elif char == '{':
                    brace_count += 1
            elif char in ')]}':
                if char == ')':
                    paren_count -= 1
                elif char == ']':
                    bracket_count -= 1
                elif char == '}':
                    brace_count -= 1
            elif char == ',' and paren_count == 0 and bracket_count == 0 and brace_count == 0:
                arg_pairs.append(current_arg.strip())
                current_arg = ""
                continue
            
            current_arg += char
        
        if current_arg.strip():
            arg_pairs.append(current_arg.strip())
        
        # Parse each argument pair
        for arg_pair in arg_pairs:
            if '=' in arg_pair:
                key, value = arg_pair.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                # Try to evaluate the value safely
                try:
                    # Handle string literals
                    if value.startswith("'") and value.endswith("'"):
                        args[key] = value[1:-1]
                    elif value.startswith('"') and value.endswith('"'):
                        args[key] = value[1:-1]
                    # Handle lists and dicts (for items parameter)
                    elif value.startswith('[') or value.startswith('{'):
                        args[key] = ast.literal_eval(value)
                    # Handle numbers
                    elif value.replace('.', '').replace('-', '').isdigit():
                        if '.' in value:
                            args[key] = float(value)
                        else:
                            args[key] = int(value)
                    else:
                        # Default to string
                        args[key] = value
                except (ValueError, SyntaxError):
                    # If evaluation fails, keep as string
                    args[key] = value
    
    return func_name, args


def load_events(file_path: str) -> List[Dict[str, Any]]:
    """Load events from a JSONL file."""
    events = []
    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return events


def create_factorio_instance() -> FactorioInstance:
    """Create and configure a Factorio instance."""
    ips, udp_ports, tcp_ports = get_local_container_ips()
    
    instance = FactorioInstance(
        address="localhost",
        bounding_box=200,
        tcp_port=tcp_ports[-1],
        cache_scripts=True,
        fast=True,
        inventory={
            'iron-plate': 8,
            'stone-furnace': 1,
            'burner-mining-drill': 1,
        }
    )
    
    return instance


def execute_action(instance: FactorioInstance, func_name: str, args: Dict[str, Any], tick: int, enable_logging: bool = False) -> Any:
    """Execute an action on the FLE instance namespace."""
    namespace = instance.namespace
    
    # Get the function from the namespace
    if not hasattr(namespace, func_name):
        print(f"Warning: Function '{func_name}' not found in namespace")
        return None
    
    func = getattr(namespace, func_name)
    
    try:
        # Remove timing-related arguments that are only used for scheduling
        filtered_args = {k: v for k, v in args.items() 
                        if k not in ['start_tick', 'end_tick', 'tick']}
        
        # Special handling for extract_item with multiple items - return multiple calls
        if func_name == 'extract_item' and 'items' in filtered_args:
            import json
            items_str = filtered_args['items']
            if isinstance(items_str, str):
                # Check for empty string and skip execution
                if not items_str.strip():
                    print(f"Skipping {func_name} - empty items string")
                    return None
                    
                # Fix JSON format - replace single quotes with double quotes
                items_str = items_str.replace("'", '"')
                items_list = json.loads(items_str)
                
                if len(items_list) > 0:
                    # Multiple items - return list of calls to execute
                    calls_to_execute = []
                    source_position = Position(filtered_args['entity_x'], filtered_args['entity_y'])
                    
                    for item_info in items_list[:1]:
                        item_name = item_info['item']
                        quantity = item_info.get('count', 1)
                        
                        # Convert item name to Prototype
                        from fle.env.game_types import prototype_by_name
                        if item_name in prototype_by_name:
                            entity = prototype_by_name[item_name]
                        else:
                            print(f"Warning: No Prototype found for '{item_name}', using string")
                            entity = item_name
                        
                        call_args = {
                            'entity': entity,
                            'source': source_position,
                            'quantity': quantity
                        }
                        calls_to_execute.append((func, call_args))
                    
                    # Execute all calls
                    results = []
                    for call_func, call_args in calls_to_execute:
                        result = call_func(**call_args)
                        results.append(result)
                        print(f"Executed {func_name} with args {call_args}")
                    return results
        
        # Handle special argument transformations for single calls
        if func_name == 'move_to':
            # For move_to, use end_x and end_y as Position object, discard other args
            if 'end_x' in filtered_args and 'end_y' in filtered_args:
                filtered_args = {
                    'position': Position(filtered_args['end_x'], filtered_args['end_y'])
                }
        
        elif func_name == 'harvest_resource':
            # For harvest_resource, create Position object from x and y, discard other args
            if 'x' in filtered_args and 'y' in filtered_args:
                filtered_args = {
                    'position': Position(filtered_args['x'], filtered_args['y'])
                }
        
        elif func_name == 'place_entity':
            # For place_entity, rename 'item' to 'entity' and create Position from x,y
            new_args = {}
            if 'item' in filtered_args:
                # Convert item name to Prototype enum instance
                from fle.env.game_types import prototype_by_name
                item_name = filtered_args['item']
                if item_name in prototype_by_name:
                    new_args['entity'] = prototype_by_name[item_name]
                else:
                    # Fallback: pass the item name directly if prototype lookup fails
                    print(f"Warning: No Prototype found for '{item_name}', using string")
                    new_args['entity'] = item_name
            if 'x' in filtered_args and 'y' in filtered_args:
                new_args['position'] = Position(filtered_args['x'], filtered_args['y'])
            if 'direction' in filtered_args:
                new_args['direction'] = Direction.from_int(int(filtered_args['direction']))
            filtered_args = new_args
        
        elif func_name == 'craft_item':
            # For craft_item, rename 'recipe' to 'entity'
            if 'recipe' in filtered_args:
                filtered_args['entity'] = filtered_args.pop('recipe')
            # Rename 'count' to 'quantity'
            if 'count' in filtered_args:
                filtered_args['quantity'] = filtered_args.pop('count')
        
        elif func_name == 'insert_item':
            # For insert_item, need entity (from items), target (entity + position), quantity
            new_args = {}
            
            # Parse items to get the entity to insert
            if 'items' in filtered_args:
                import json
                items_str = filtered_args['items']
                if isinstance(items_str, str):
                    # Fix JSON format - replace single quotes with double quotes
                    items_str = items_str.replace("'", '"')
                    items_list = json.loads(items_str)
                    if items_list and len(items_list) > 0:
                        # Get first item as the entity to insert
                        item_info = items_list[0]
                        item_name = item_info['item']
                        
                        # Convert item name to Prototype
                        from fle.env.game_types import prototype_by_name
                        if item_name in prototype_by_name:
                            new_args['entity'] = prototype_by_name[item_name]
                        else:
                            print(f"Warning: No Prototype found for '{item_name}', using string")
                            new_args['entity'] = item_name
                        
                        # Get quantity from the item info
                        new_args['quantity'] = item_info.get('count', 1)
            
            # Create target entity from position - need to find actual entity at that position
            if 'entity_x' in filtered_args and 'entity_y' in filtered_args:
                target_position = Position(filtered_args['entity_x'], filtered_args['entity_y'])
                
                # Get the target entity type from the 'entity' parameter (which is actually the target type)
                target_entity_name = filtered_args.get('entity')  # This is 'stone-furnace' in the example
                if target_entity_name and target_entity_name in prototype_by_name:
                    target_prototype = prototype_by_name[target_entity_name]
                    # Get entities of that type at the specified position
                    target_entities = namespace.get_entities({target_prototype}, position=target_position, radius=0.5)
                    if target_entities and len(target_entities) > 0:
                        new_args['target'] = target_entities[0]
                    else:
                        print(f"Warning: No {target_entity_name} found at position {target_position}")
                        # Fallback to position if entity not found
                        new_args['target'] = target_position
                else:
                    # Fallback to position if we can't identify the target entity type
                    print(f"Warning: Unknown target entity type '{target_entity_name}', using position")
                    new_args['target'] = target_position
            
            filtered_args = new_args
        
        elif func_name == 'extract_item':
            # For extract_item, need entity (from items), source (Position from entity_x, entity_y), quantity
            # If multiple items, this will be handled by decomposing into multiple calls
            new_args = {}
            
            # Parse items to get the entity to extract
            if 'items' in filtered_args:
                import json
                items_str = filtered_args['items']
                if isinstance(items_str, str):
                    # Fix JSON format - replace single quotes with double quotes
                    items_str = items_str.replace("'", '"')
                    items_list = json.loads(items_str)
                    if items_list and len(items_list) > 0:
                        # Get first item as the entity to extract
                        item_info = items_list[0]
                        item_name = item_info['item']
                        
                        # Convert item name to Prototype
                        from fle.env.game_types import prototype_by_name
                        if item_name in prototype_by_name:
                            new_args['entity'] = prototype_by_name[item_name]
                        else:
                            print(f"Warning: No Prototype found for '{item_name}', using string")
                            new_args['entity'] = item_name
                        
                        # Get quantity from the item info
                        new_args['quantity'] = item_info.get('count', 1)
            
            # Use Position(entity_x, entity_y) as the source
            if 'entity_x' in filtered_args and 'entity_y' in filtered_args:
                new_args['source'] = Position(filtered_args['entity_x'], filtered_args['entity_y'])
            
            filtered_args = new_args
        
        elif func_name == 'pickup_entity':
            # For pickup_entity, need entity (Prototype) and position (Position object)
            new_args = {}
            
            # Convert entity name to Prototype
            if 'entity' in filtered_args:
                from fle.env.game_types import prototype_by_name
                entity_name = filtered_args['entity']
                if entity_name in prototype_by_name:
                    new_args['entity'] = prototype_by_name[entity_name]
                else:
                    print(f"Warning: No Prototype found for '{entity_name}', using string")
                    new_args['entity'] = entity_name
            
            # Create Position object from x, y coordinates
            if 'x' in filtered_args and 'y' in filtered_args:
                new_args['position'] = Position(filtered_args['x'], filtered_args['y'])
            
            filtered_args = new_args
        
        elif func_name == 'set_research':
            # For set_research, convert technology name to Technology object
            new_args = {}
            
            if 'technology' in filtered_args:
                from fle.env.game_types import Technology
                technology_name = filtered_args['technology']
                
                # Try to convert string to Technology enum
                try:
                    # Check if it's already a Technology object
                    if hasattr(technology_name, 'value'):
                        new_args['technology'] = technology_name
                    else:
                        # Convert string to Technology enum by name
                        new_args['technology'] = Technology(technology_name)
                except (ValueError, AttributeError):
                    # Fallback: pass the technology name directly if enum conversion fails
                    print(f"Warning: No Technology enum found for '{technology_name}', using string")
                    new_args['technology'] = technology_name
            
            filtered_args = new_args
        
        # Log entities and inventory data before action execution (only if logging is enabled)
        if enable_logging:
            global entities_log_file, inventory_log_file
            
            # Get updated state after action
            updated_entities = namespace.get_entities(radius=100)
            updated_inventory = namespace.inspect_inventory().__dict__
            
            serializable_entities = [str(entity) for entity in updated_entities]
            # Log the data
            log_data(entities_log_file, tick, serializable_entities)
            log_data(inventory_log_file, tick, updated_inventory)

        # Execute the action
        result = func(**filtered_args)
        print(f"Executed {func_name} with args {filtered_args}")
        
        return result
    except Exception as e:
        if 'Could not harvest. LuaEntity' in str(e):
            pass
        else:
            print(f"\033[91mError executing {func_name} with args {filtered_args}: {e}\033[0m")
            raise e


def execute_events_from_file(events_file_path: str, enable_logging: bool = False, speed: float = 1.0, diff_thread: bool = False):
    """Main function to load and execute events from a JSONL file with real-time tick scheduling."""
    # Load events
    events = load_events(events_file_path)
    print(f"Loaded {len(events)} events from {events_file_path}")
    
    # Sort events by tick to ensure proper order
    events.sort(key=lambda x: x.get('tick', 0))
    
    # Create Factorio instance
    instance = create_factorio_instance()
    instance.reset()
    print("Factorio instance created and reset")
    
    # Initialize logging only if enabled
    if enable_logging:
        initialize_logging()
        print("Logging enabled - data will be saved to logs/")
    else:
        print("Logging disabled - no data will be saved")
    
    # Create tick scheduler with specified speed
    scheduler = TickScheduler(speed)
    instance.rcon_client.send_command('/c game.speed = ' + str(speed))
    
    try:
        # Start the real-time scheduler
        scheduler.start()
        print(f"Started real-time execution at {scheduler.tick_duration*1000:.1f}ms per tick ({60 * speed:.1f} TPS)")
        print(f"Execution mode: {'Separate threads' if diff_thread else 'Same thread'}")
        
        # Execute events in order with proper timing
        for i, event in enumerate(events):
            tick = event.get('tick', 0)
            call = event.get('call', '')
            
            # Wait for the appropriate tick time
            scheduler.wait_for_tick(tick)
            
            # Show current status
            current_tick = scheduler.get_current_tick()
            print(f"\n--- Event {i+1}/{len(events)} (tick {tick}, actual tick {current_tick}) ---")
            print(f"Call: {call}")
            
            # Parse and execute the function call
            try:
                func_name, args = parse_function_call(call)
                
                # Execute the action based on threading preference
                if diff_thread:
                    # Execute in a separate thread to avoid blocking the scheduler
                    # for long-running operations
                    def execute_async():
                        execute_action(instance, func_name, args, tick, enable_logging)
                    
                    thread = threading.Thread(target=execute_async)
                    thread.start()
                    # For most actions, we don't need to wait for completion
                    # But for critical actions, you might want to join the thread
                    #thread.join()
                else:
                    # Execute directly in the same thread (default)
                    execute_action(instance, func_name, args, tick, enable_logging)
                
            except Exception as e:
                print(f"\033[91mError processing event {i+1}: {e}\033[0m")
                continue
        
        # Wait a bit for any remaining async actions to complete
        print("\nWaiting for final actions to complete...")
        time.sleep(2.0)
        
        final_tick = scheduler.get_current_tick()
        total_duration = time.time() - scheduler.start_time
        print(f"\nCompleted execution of {len(events)} events")
        print(f"Total duration: {total_duration:.2f}s (equivalent to {final_tick} ticks)")
        
    except KeyboardInterrupt:
        print("\nExecution interrupted by user")
    except Exception as e:
        print(f"Error during execution: {e}")
    finally:
        # Cleanup logging only if it was enabled
        if enable_logging:
            cleanup_logging()
        instance.cleanup()
        print("Instance and logging cleaned up")


if __name__ == "__main__":
    # Add command line option for log analysis
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--max-time', type=int, default=10000,
                       help='Maximum tick time to include in events file')
    parser.add_argument('--analyze-logs', action='store_true',
                       help='Analyze existing log files instead of running simulation')
    parser.add_argument('--enable-logging', action='store_true',
                       help='Enable logging of entities and inventory data to files')
    parser.add_argument('--speed', type=float, default=1.0,
                       help='Game speed multiplier (default: 1.0, higher = faster)')
    parser.add_argument('--diff-thread', action='store_true',
                       help='Execute actions in separate threads instead of same thread (may cause timing issues)')
    args = parser.parse_args()

    if args.analyze_logs:
        analyze_logs_example()
    else:
        # Default to the combined_events_py.jsonl file in the same directory
        current_dir = Path(__file__).parent
        events_file = current_dir / "_runnable_actions" / f"combined_events_py_{args.max_time}.jsonl"
        
        if events_file.exists():
            execute_events_from_file(str(events_file), enable_logging=args.enable_logging, speed=args.speed, diff_thread=args.diff_thread)
        else:
            print(f"Events file not found: {events_file}")
            print("Please provide the path to your events JSONL file")
