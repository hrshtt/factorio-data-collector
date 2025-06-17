#!/usr/bin/env python3
import subprocess
import json
import re
import os
from datetime import datetime
from pathlib import Path

class FactorioLogProcessor:
    def __init__(
        self,
        log_path="/Users/harshitsharma/Library/Application Support/Factorio/factorio-current.log",
        output_dir="/Users/harshitsharma/Code/exp/factorio-rnd/factorio_replays/",
        immediate_start=True
    ):
        self.log_path = log_path
        self.output_dir = Path(output_dir).resolve()
        
        # Create output directory with better error handling
        print(self.output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Pattern to match script log lines with JSON
        self.script_pattern = re.compile(r'^\d+\.\d+ Script @.*?control\.lua:\d+: (.+)$')
        
        # Pattern to match checksum lines
        self.checksum_pattern = re.compile(r'^\d+\.\d+ Checksum for script .*/control\.lua: \d+$')
        
        # State tracking
        self.recording = False
        self.current_replay_file = None
        self.replay_start_time = None
        self.checksum_detected = False
        self.immediate_start = immediate_start
        
    def is_replay_start(self, line):
        """Detect if this line indicates a replay is starting"""
        line = line.strip()
        
        # Check for checksum line - this indicates a replay is about to start
        if self.checksum_pattern.match(line):
            self.checksum_detected = True
            return "checksum"
        
        # Check for the first game event (t:0 with on_player_joined_game)
        # This should come shortly after the checksum
        match = self.script_pattern.match(line)
        if match and self.checksum_detected:
            try:
                data = json.loads(match.group(1))
                # Look for the specific pattern: t:0, p:1, ev:on_player_joined_game
                if (data.get("t") == 0 and 
                    data.get("p") == 1 and 
                    data.get("ev") == "on_player_joined_game"):
                    self.checksum_detected = False  # Reset the flag
                    return "game_start"
            except (json.JSONDecodeError, KeyError):
                pass
        
        return False
    
    def extract_json_data(self, line):
        """Extract and clean JSON data from script log line"""
        match = self.script_pattern.match(line.strip())
        if not match:
            return None
            
        try:
            json_str = match.group(1)
            data = json.loads(json_str)
            return data
        except json.JSONDecodeError:
            return None
    
    def start_new_replay_file(self):
        """Start recording to a new replay file"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"factorio_replay_{timestamp}.jsonl"
        filepath = self.output_dir / filename
        
        if self.current_replay_file:
            self.current_replay_file.close()
        
        self.current_replay_file = open(filepath, 'w')
        self.replay_start_time = datetime.now()
        self.recording = True
        
        print(f"🎬 Started recording replay: {filename}")
        return filepath
    
    def stop_recording(self):
        """Stop recording current replay"""
        if self.current_replay_file:
            self.current_replay_file.close()
            self.current_replay_file = None
        
        if self.replay_start_time:
            duration = datetime.now() - self.replay_start_time
            print(f"⏹️  Stopped recording (duration: {duration})")
        
        self.recording = False
        self.replay_start_time = None
    
    def process_log_line(self, line):
        """Process a single log line"""
        line = line.strip()
        if not line:
            return
        
        # If immediate_start is True, start recording on first script event
        if self.immediate_start and not self.recording:
            json_data = self.extract_json_data(line)
            if json_data:
                print("🚀 Starting immediate recording from ongoing game...")
                self.start_new_replay_file()
        
        # Check if this is the start of a new replay
        replay_start = self.is_replay_start(line)
        if replay_start:
            if replay_start == "checksum":
                if self.recording:
                    print("🔄 New replay detected, stopping previous recording")
                    self.stop_recording()
                print("📋 Checksum detected, waiting for game start...")
                return
            elif replay_start == "game_start":
                print("🎮 Game start detected (t:0, on_player_joined_game)")
                self.start_new_replay_file()
        
        # If we're recording, extract and save JSON data
        if self.recording:
            json_data = self.extract_json_data(line)
            if json_data:
                # Write the cleaned JSON data
                json.dump(json_data, self.current_replay_file)
                self.current_replay_file.write('\n')
                self.current_replay_file.flush()  # Ensure data is written immediately
                
                # Print progress occasionally
                tick = json_data.get('t', 0)
                if tick % 3600 == 0:  # Every 60 seconds of game time (60 ticks/sec)
                    print(f"⏱️  Recording... tick {tick} ({tick/60:.1f}s game time)")
    
    def tail_log(self):
        """Tail the Factorio log file and process lines in real-time"""
        print(f"👀 Monitoring Factorio log: {self.log_path}")
        print(f"💾 Output directory: {self.output_dir}")
        print("🚀 Waiting for replay to start...")
        
        try:
            # Use tail -f to follow the log file
            process = subprocess.Popen(
                ['tail', '-f', self.log_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                bufsize=1
            )
            
            for line in process.stdout:
                self.process_log_line(line)
                
        except KeyboardInterrupt:
            print("\n🛑 Stopping log processor...")
            if self.recording:
                self.stop_recording()
            process.terminate()
        except FileNotFoundError:
            print(f"❌ Error: Log file not found at {self.log_path}")
        except Exception as e:
            print(f"❌ Error: {e}")
            if self.recording:
                self.stop_recording()

def main():
    import sys
    
    # Optional command line arguments
    # log_path = sys.argv[1] if len(sys.argv) > 1 else None
    # output_dir = sys.argv[2] if len(sys.argv) > 2 else "./factorio_replays"
    
    processor = FactorioLogProcessor()
    processor.tail_log()

if __name__ == "__main__":
    main()