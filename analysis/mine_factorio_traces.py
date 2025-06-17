import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
import re
from collections import defaultdict

# Professional Process Mining Libraries
import pm4py
from pm4py.objects.log.importer.xes import importer as xes_importer
from pm4py.objects.conversion.log import converter as log_converter
from pm4py.algo.discovery.alpha import algorithm as alpha_miner
from pm4py.algo.discovery.inductive import algorithm as inductive_miner
from pm4py.algo.discovery.heuristics import algorithm as heuristics_miner
from pm4py.algo.discovery.dfg import algorithm as dfg_discovery
from pm4py.visualization.dfg import visualizer as dfg_visualization
from pm4py.visualization.petri_net import visualizer as pn_visualizer
from pm4py.visualization.process_tree import visualizer as pt_visualizer
from pm4py.statistics.traces.generic.log import case_statistics
from pm4py.algo.conformance.tokenreplay import algorithm as token_replay
from pm4py.algo.filtering.log.variants import variants_filter
from pm4py.algo.filtering.log.cases import case_filter
from pm4py.statistics.variants.log import get as variants_get
from pm4py.algo.discovery.minimum_self_distance import algorithm as msd_algorithm

class ProfessionalFactorioProcessMiner:
    def __init__(self, lua_file_path=None):
        self.raw_events = []
        self.event_log = None
        self.dfg = None
        self.petri_net = None
        self.initial_marking = None
        self.final_marking = None
        
        if lua_file_path:
            self.load_and_process_lua(lua_file_path)
    
    def parse_lua_to_events(self, lua_content):
        """Parse Lua file into structured events"""
        events = []
        lines = lua_content.strip().split('\n')
        
        for line in lines:
            line = line.strip()
            if not line.startswith('task[') or not line.endswith('}'):
                continue
                
            # Extract task number
            task_match = re.match(r'task\[(\d+)\]', line)
            if not task_match:
                continue
                
            task_id = int(task_match.group(1))
            
            # Extract content between braces
            content_match = re.search(r'{(.+)}$', line)
            if not content_match:
                continue
                
            content = content_match.group(1)
            
            # Parse parameters - handle nested structures
            params = self._parse_parameters(content)
            
            if params:
                event = {
                    'case:concept:name': 'factorio_session_1',
                    'concept:name': params[0].strip('"'),  # Activity name
                    'time:timestamp': pd.Timestamp('2024-01-01') + pd.Timedelta(seconds=task_id),
                    'task_id': task_id,
                    'org:resource': 'player_1'
                }
                
                # Add domain-specific attributes
                self._add_domain_attributes(event, params)
                events.append(event)
        
        return events
    
    def _parse_parameters(self, content):
        """Robust parameter parsing for Lua tables"""
        params = []
        current_param = ""
        brace_level = 0
        in_quotes = False
        
        i = 0
        while i < len(content):
            char = content[i]
            
            if char == '"' and (i == 0 or content[i-1] != '\\'):
                in_quotes = not in_quotes
                current_param += char
            elif char == '{' and not in_quotes:
                brace_level += 1
                current_param += char
            elif char == '}' and not in_quotes:
                brace_level -= 1
                current_param += char
            elif char == ',' and brace_level == 0 and not in_quotes:
                params.append(current_param.strip())
                current_param = ""
            else:
                current_param += char
            
            i += 1
        
        if current_param.strip():
            params.append(current_param.strip())
        
        return params
    
    def _add_domain_attributes(self, event, params):
        """Add Factorio-specific attributes to events"""
        activity = event['concept:name']
        
        # Spatial activities
        if activity in ['walk', 'move', 'build', 'mine', 'put', 'take'] and len(params) > 1:
            coords = self._extract_coordinates(params[1])
            if coords:
                event['x_coordinate'] = coords[0]
                event['y_coordinate'] = coords[1]
        
        # Resource/Item activities
        if activity in ['craft', 'build', 'put', 'take']:
            if len(params) > 2:
                event['item_type'] = params[2].strip('"')
            if len(params) > 3 and params[3].isdigit():
                event['quantity'] = int(params[3])
        
        # Building direction
        if activity == 'build' and 'defines.direction' in str(params):
            for param in params:
                if 'defines.direction' in str(param):
                    direction = param.split('.')[-1]
                    event['direction'] = direction
        
        # Speed settings
        if activity == 'speed' and len(params) > 1:
            try:
                event['speed_value'] = float(params[1])
            except ValueError:
                pass
        
        # Inventory operations
        if 'defines.inventory' in str(params):
            for param in params:
                if 'defines.inventory' in str(param):
                    inventory_type = param.split('.')[-1]
                    event['inventory_type'] = inventory_type
    
    def _extract_coordinates(self, coord_str):
        """Extract x,y coordinates from various formats"""
        # Handle {x,y} format
        coords = re.findall(r'[-\d.]+', coord_str)
        if len(coords) >= 2:
            try:
                return float(coords[0]), float(coords[1])
            except ValueError:
                pass
        return None
    
    def load_and_process_lua(self, lua_file_path):
        """Load Lua file and convert to PM4Py event log"""
        with open(lua_file_path, 'r') as f:
            lua_content = f.read()
        
        # Parse to events
        events = self.parse_lua_to_events(lua_content)
        
        # Convert to pandas DataFrame
        df = pd.DataFrame(events)
        
        # Convert to PM4Py event log
        self.event_log = log_converter.apply(df)
        
        print(f"Loaded {len(events)} events from {lua_file_path}")
        print(f"Activities: {sorted(df['concept:name'].unique())}")
        
        return self.event_log
    
    def discover_process_models(self):
        """Apply multiple process discovery algorithms"""
        print("=== PROCESS DISCOVERY WITH MULTIPLE ALGORITHMS ===\n")
        
        results = {}
        
        # 1. Directly-Follows Graph (DFG)
        print("1. Discovering Directly-Follows Graph...")
        dfg = dfg_discovery.apply(self.event_log)
        
        # Get start and end activities separately
        from pm4py.statistics.start_activities.log import get as start_activities_get
        from pm4py.statistics.end_activities.log import get as end_activities_get
        
        start_activities = start_activities_get.get_start_activities(self.event_log)
        end_activities = end_activities_get.get_end_activities(self.event_log)
        
        self.dfg = dfg
        results['dfg'] = {
            'graph': dfg,
            'start_activities': start_activities,
            'end_activities': end_activities
        }
        
        # 2. Alpha Miner Algorithm
        print("2. Applying Alpha Miner Algorithm...")
        try:
            net, initial_marking, final_marking = alpha_miner.apply(self.event_log)
            self.petri_net = net
            self.initial_marking = initial_marking
            self.final_marking = final_marking
            results['alpha'] = {
                'net': net,
                'initial_marking': initial_marking,
                'final_marking': final_marking
            }
            print(f"   Alpha Miner: {len(net.places)} places, {len(net.transitions)} transitions")
        except Exception as e:
            print(f"   Alpha Miner failed: {e}")
            results['alpha'] = None
        
        # 3. Inductive Miner Algorithm
        print("3. Applying Inductive Miner Algorithm...")
        try:
            tree = inductive_miner.apply_tree(self.event_log)
            net, initial_marking, final_marking = inductive_miner.apply(self.event_log)
            results['inductive'] = {
                'tree': tree,
                'net': net,
                'initial_marking': initial_marking,
                'final_marking': final_marking
            }
            print(f"   Inductive Miner: Process tree with {len(net.places)} places")
        except Exception as e:
            print(f"   Inductive Miner failed: {e}")
            results['inductive'] = None
        
        # 4. Heuristics Miner Algorithm
        print("4. Applying Heuristics Miner Algorithm...")
        try:
            heu_net = heuristics_miner.apply_heu(self.event_log)
            results['heuristics'] = {'heuristics_net': heu_net}
            print(f"   Heuristics Miner: Generated heuristics net")
        except Exception as e:
            print(f"   Heuristics Miner failed: {e}")
            results['heuristics'] = None
        
        return results
    
    def analyze_variants(self):
        """Analyze process variants and their frequencies"""
        print("\n=== PROCESS VARIANT ANALYSIS ===\n")
        
        # Get variants
        variants = variants_get.get_variants(self.event_log)
        
        print(f"Total number of variants: {len(variants)}")
        print(f"Total cases: {len(self.event_log)}")
        
        # Sort variants by frequency
        sorted_variants = sorted(variants.items(), key=lambda x: len(x[1]), reverse=True)
        
        print("\nTop 10 most frequent variants:")
        for i, (variant, cases) in enumerate(sorted_variants[:10], 1):
            activities = ' -> '.join(variant)
            print(f"{i:2d}. [{len(cases):3d} cases] {activities[:100]}{'...' if len(activities) > 100 else ''}")
        
        # Variant distribution analysis
        variant_frequencies = [len(cases) for variant, cases in variants.items()]
        
        plt.figure(figsize=(12, 6))
        plt.subplot(1, 2, 1)
        plt.hist(variant_frequencies, bins=min(50, len(variant_frequencies)), alpha=0.7)
        plt.xlabel('Variant Frequency')
        plt.ylabel('Number of Variants')
        plt.title('Distribution of Variant Frequencies')
        plt.yscale('log')
        
        plt.subplot(1, 2, 2)
        cumulative_freq = np.cumsum(sorted(variant_frequencies, reverse=True))
        cumulative_freq = cumulative_freq / cumulative_freq[-1] * 100
        plt.plot(range(1, len(cumulative_freq) + 1), cumulative_freq)
        plt.xlabel('Variant Rank')
        plt.ylabel('Cumulative Frequency (%)')
        plt.title('Cumulative Variant Distribution')
        plt.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.show()
        
        return variants
    
    def conformance_checking(self):
        """Perform conformance checking against discovered model"""
        if not self.petri_net:
            print("No Petri net available for conformance checking")
            return None
        
        print("\n=== CONFORMANCE CHECKING ===\n")
        
        # Token-based replay
        replayed_traces = token_replay.apply(self.event_log, self.petri_net, 
                                           self.initial_marking, self.final_marking)
        
        # Calculate fitness statistics
        fitness_values = [trace['trace_fitness'] for trace in replayed_traces]
        avg_fitness = np.mean(fitness_values)
        
        print(f"Average trace fitness: {avg_fitness:.3f}")
        print(f"Fitness std deviation: {np.std(fitness_values):.3f}")
        print(f"Perfect traces: {sum(f == 1.0 for f in fitness_values)}/{len(fitness_values)}")
        
        # Fitness distribution
        plt.figure(figsize=(10, 5))
        plt.subplot(1, 2, 1)
        plt.hist(fitness_values, bins=20, alpha=0.7, edgecolor='black')
        plt.xlabel('Trace Fitness')
        plt.ylabel('Frequency')
        plt.title('Distribution of Trace Fitness')
        
        plt.subplot(1, 2, 2)
        missing_tokens = [trace['missing_tokens'] for trace in replayed_traces]
        remaining_tokens = [trace['remaining_tokens'] for trace in replayed_traces]
        
        plt.scatter(missing_tokens, remaining_tokens, alpha=0.6)
        plt.xlabel('Missing Tokens')
        plt.ylabel('Remaining Tokens')
        plt.title('Token Analysis')
        
        plt.tight_layout()
        plt.show()
        
        return replayed_traces
    
    def performance_analysis(self):
        """Analyze temporal performance patterns"""
        print("\n=== PERFORMANCE ANALYSIS ===\n")
        
        # Case duration analysis
        # case_statistics
        case_durations = case_statistics.get_all_case_durations(self.event_log)
        
        print(f"Average case duration: {np.mean(case_durations):.2f} seconds")
        print(f"Median case duration: {np.median(case_durations):.2f} seconds")
        print(f"Case duration std dev: {np.std(case_durations):.2f} seconds")
        
        # Activity frequency analysis
        activity_freq = defaultdict(int)
        activity_durations = defaultdict(list)
        
        for trace in self.event_log:
            prev_timestamp = None
            for event in trace:
                activity = event['concept:name']
                timestamp = event['time:timestamp']
                activity_freq[activity] += 1
                
                if prev_timestamp:
                    duration = (timestamp - prev_timestamp).total_seconds()
                    activity_durations[activity].append(duration)
                prev_timestamp = timestamp
        
        # Plot performance metrics
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Activity frequency
        activities = list(activity_freq.keys())[:15]  # Top 15
        frequencies = [activity_freq[act] for act in activities]
        
        axes[0, 0].bar(range(len(activities)), frequencies)
        axes[0, 0].set_xticks(range(len(activities)))
        axes[0, 0].set_xticklabels(activities, rotation=45, ha='right')
        axes[0, 0].set_title('Activity Frequencies')
        axes[0, 0].set_ylabel('Count')
        
        # Case duration distribution
        axes[0, 1].hist(case_durations, bins=30, alpha=0.7)
        axes[0, 1].set_title('Case Duration Distribution')
        axes[0, 1].set_xlabel('Duration (seconds)')
        axes[0, 1].set_ylabel('Frequency')
        
        # Activity duration boxplot
        duration_data = []
        duration_labels = []
        for act in activities[:10]:  # Top 10 for readability
            if activity_durations[act]:
                duration_data.append(activity_durations[act])
                duration_labels.append(act)
        
        if duration_data:
            axes[1, 0].boxplot(duration_data, labels=duration_labels)
            axes[1, 0].set_title('Activity Duration Distributions')
            axes[1, 0].set_ylabel('Duration (seconds)')
            axes[1, 0].tick_params(axis='x', rotation=45)
        
        # Timeline view (sample)
        sample_trace = self.event_log[0] if len(self.event_log) > 0 else []
        if sample_trace:
            timestamps = [event['time:timestamp'] for event in sample_trace[:100]]  # First 100 events
            activities = [event['concept:name'] for event in sample_trace[:100]]
            
            axes[1, 1].scatter(range(len(timestamps)), 
                             [hash(act) % 100 for act in activities], 
                             alpha=0.6)
            axes[1, 1].set_title('Activity Timeline (Sample Trace)')
            axes[1, 1].set_xlabel('Event Index')
            axes[1, 1].set_ylabel('Activity (Hashed)')
        
        plt.tight_layout()
        plt.show()
        
        return {
            'case_durations': case_durations,
            'activity_frequencies': dict(activity_freq),
            'activity_durations': dict(activity_durations)
        }
    
    def spatial_process_analysis(self):
        """Analyze spatial patterns in the process"""
        print("\n=== SPATIAL PROCESS ANALYSIS ===\n")
        
        spatial_events = []
        for trace in self.event_log:
            for event in trace:
                if 'x_coordinate' in event and 'y_coordinate' in event:
                    spatial_events.append({
                        'activity': event['concept:name'],
                        'x': event['x_coordinate'],
                        'y': event['y_coordinate'],
                        'timestamp': event['time:timestamp']
                    })
        
        if not spatial_events:
            print("No spatial data found in the event log")
            return None
        
        spatial_df = pd.DataFrame(spatial_events)
        
        # Spatial clustering by activity
        fig, axes = plt.subplots(2, 2, figsize=(15, 12))
        
        # All activities scatter plot
        unique_activities = spatial_df['activity'].unique()
        colors = plt.cm.tab20(np.linspace(0, 1, len(unique_activities)))
        
        for activity, color in zip(unique_activities, colors):
            activity_data = spatial_df[spatial_df['activity'] == activity]
            axes[0, 0].scatter(activity_data['x'], activity_data['y'], 
                             c=[color], label=activity, alpha=0.6, s=20)
        
        axes[0, 0].set_title('Spatial Distribution by Activity')
        axes[0, 0].set_xlabel('X Coordinate')
        axes[0, 0].set_ylabel('Y Coordinate')
        axes[0, 0].legend(bbox_to_anchor=(1.05, 1), loc='upper left')
        
        # Movement trajectory
        movement_activities = ['walk', 'move']
        movement_data = spatial_df[spatial_df['activity'].isin(movement_activities)]
        if len(movement_data) > 1:
            movement_data = movement_data.sort_values('timestamp')
            axes[0, 1].plot(movement_data['x'], movement_data['y'], 
                           alpha=0.7, linewidth=1, marker='o', markersize=3)
            axes[0, 1].set_title('Movement Trajectory')
            axes[0, 1].set_xlabel('X Coordinate')
            axes[0, 1].set_ylabel('Y Coordinate')
        
        # Spatial density heatmap
        axes[1, 0].hist2d(spatial_df['x'], spatial_df['y'], bins=30, cmap='Blues')
        axes[1, 0].set_title('Spatial Activity Density')
        axes[1, 0].set_xlabel('X Coordinate')
        axes[1, 0].set_ylabel('Y Coordinate')
        
        # Distance analysis
        if len(spatial_df) > 1:
            distances = []
            for i in range(1, len(spatial_df)):
                prev_x, prev_y = spatial_df.iloc[i-1][['x', 'y']]
                curr_x, curr_y = spatial_df.iloc[i][['x', 'y']]
                dist = np.sqrt((curr_x - prev_x)**2 + (curr_y - prev_y)**2)
                distances.append(dist)
            
            axes[1, 1].hist(distances, bins=30, alpha=0.7)
            axes[1, 1].set_title('Distribution of Movement Distances')
            axes[1, 1].set_xlabel('Distance')
            axes[1, 1].set_ylabel('Frequency')
        
        plt.tight_layout()
        plt.show()
        
        return spatial_df
    
    def generate_comprehensive_report(self):
        """Generate a comprehensive process mining report"""
        print("\n" + "="*60)
        print("COMPREHENSIVE FACTORIO PROCESS MINING REPORT")
        print("="*60)
        
        # Basic statistics
        print(f"\nBASIC STATISTICS:")
        print(f"- Total traces: {len(self.event_log)}")
        print(f"- Total events: {sum(len(trace) for trace in self.event_log)}")
        
        activities = set()
        for trace in self.event_log:
            for event in trace:
                activities.add(event['concept:name'])
        print(f"- Unique activities: {len(activities)}")
        print(f"- Activity set: {sorted(activities)}")
        
        # Run all analyses
        print(f"\nRUNNING COMPREHENSIVE ANALYSIS...")
        
        models = self.discover_process_models()
        variants = self.analyze_variants()
        performance = self.performance_analysis()
        spatial = self.spatial_process_analysis()
        
        if models.get('alpha'):
            conformance = self.conformance_checking()
        
        print(f"\n" + "="*60)
        print("ANALYSIS COMPLETE")
        print("="*60)

# Usage example
def main():
    # Initialize with your Lua file
    miner = ProfessionalFactorioProcessMiner('tasks.lua.txt')  # Replace with your file path
    
    # Run comprehensive analysis
    miner.generate_comprehensive_report()

if __name__ == "__main__":
    main()