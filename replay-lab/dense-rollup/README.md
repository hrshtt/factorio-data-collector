
1.  Guiding principles
---

P-1  One deterministic write-point per game-tick  
P-2  All state lives in `global.*`  (Factorio desync safety)  
P-3  Action modules *own* only:
      • their event handlers  
      • their private session state  
      • a `poll(player, tick) → table|nil`  hook that exports data for
        the current tick (or retro information)  
P-4  **No module writes files directly** – the *Tick-Logger* does.

---
2.  High-level component map
---
```
   ┌────────────────────────┐
   │   control.lua          │   – still the entry-point
   │  (dispatcher registration)│
   └────────────┬───────────┘
                │ calls
   ┌────────────▼───────────┐
   │  tick_logger.lua       │   – NEW, owns script.on_tick
   │  • builds one record / player / tick
   │  • flushes buffers (uses shared_utils)         P-1
   └────────────┬───────────┘
        poll()  │ per tick
   ┌────────────▼───────────┐
   │ action modules (*n*)   │   – craft_item_collated.lua etc.
   │  • event handlers (unchanged)                  P-2
   │  • poll() implementations                     P-3
   └────────────────────────┘
```

---
3.  Tick-Logger contract
---
Tick-Logger maintains `global.tick_record[player_index] = { … }`  
At every `on_tick(t)` it:

1.  Creates a fresh minimal skeleton  
    ```
    rec = {t = t, p = i, act = 0, rew = 0}
    ```
2.  Iterates **once** over the registered action modules calling  
    ```
    local update = module.poll(player, t)
    ```
    • If `update` is non-nil, shallow-merge into `rec`.  
    • If multiple modules set the same field, later ones win
      (choose deterministic order - module list is fixed).  
3.  Writes the joined record to the category buffer
    ```
    shared_utils.buffer_event("tick_dense", game.table_to_json(rec))
    ```
4.  Every `N` ticks (and on `on_player_left_game`) calls
    `shared_utils.flush_all_buffers()`.

Why not write via `on_nth_tick(1)`?  Because `on_tick` is already “nth=1”.
Single registration is cheaper than many.

---
4.  Action module refactor pattern
---
For **each** existing action module:

A.  Keep **all** event handlers and session code – they mutate `global.*`.

B.  Add a `poll(player, tick)` method. Examples:

• Move to collated  
```lua
function move_to_collated.poll(player, tick)
  local s = get_movement_state()[player.index]
  if not s then return nil end         -- no active segment
  if s.direction then
    return {move_dir = s.direction_name}   -- 8-way direction
  else
    return nil
  end
end
```

• Craft item collated  
```lua
-- session finalisation still happens in event handler
-- poll only injects "crafting = 1" flag while crafting is active
function craft_item_collated.poll(player, tick)
  local key = player.index .. ":" .. (player.crafting_queue[1] and player.crafting_queue[1].recipe.name or "")
  local session = crafting_sessions[key]
  if session then return {crafting = 1} end
end
```

C.  **Remove** any direct call to `shared_utils.buffer_event` in the module.
   Instead, finalisation handlers should simply:  
   ```
   shared_utils.enqueue_retrospective("craft_item_done", {...}, session.start_tick)
   ```
   (see §5 Retro-tagging).

---
5.  Retro-tagging (sessions that finish later)
---
We cannot rewrite files during the run, so we queue “patches”.

Extend `shared_utils` with:

```
function shared_utils.enqueue_retrospective(tag, payload, target_tick)
  if not global.retros then global.retros = {} end
  local bucket = global.retros[target_tick]
  if not bucket then bucket = {}; global.retros[target_tick] = bucket end
  table.insert(bucket, {tag = tag, data = payload})
end
```

Tick-Logger step 2½:

```
-- after polling modules
local retro = global.retros[tick]
if retro then
  for _, patch in pairs(retro) do
     for k,v in pairs(patch.data) do rec[k] = v end
  end
  global.retros[tick] = nil
end
```

Thus a crafting session can retro-inject `craft_done=1`, `qty=50`,
`recipe="green_science"` into the tick where it began.

---
6.  Canonical top-down schema  (single source of truth)
---
Create `schema.lua` that exports two tables:

```
-- Observation vector layout
OBS = {
  t   = "uint32",       -- tick
  p   = "uint8",        -- player
  act = "uint8",        -- discrete action id (optional)
  rew = "int8",         -- shaped reward per tick
  -- spatial
  px  = "float32", py = "float32",
  dir = "enum8:N,NE,E,SE,S,SW,W,NW",
  -- crafting
  crafting = "bool",
  craft_done = "bool",
  craft_recipe = "string16",
  -- inventory transfers
  inv_in  = "dict:item->int16",
  inv_out = "dict:item->int16",
  -- ... extend as needed
}
ACTIONS = {
  idle = 0, walk = 1, mine = 2, build = 3,
  craft = 4, inv_transfer = 5, chat = 6,
  -- ≤255
}
```

•  Tick-Logger initialises record with field defaults based on `schema.OBS`.  
•  Each module only sets fields already defined there (fail-fast if not).

Benefits: data contract is explicit, easy to encode to fixed tensors.

---
7.  Performance / determinism notes
---
1.  The only *per-tick* loop touches `global` and cheap tables – no heavy API.  
2.  Modules still rely on *event-driven* updates for expensive diffs
    (inventory scans are only triggered on `on_player_fast_transferred`, etc.).  
3.  All random / math libs stay deterministic; avoid `math.random`.  
4.  File writes happen *outside* gameplay critical path (buffer flush ≥1 MB).  
5.  Retro-tagging uses in-memory `global.retros`; memory footprint:
    `(#sessions) * (avg patches) << 16 MiB` for 100 long WR runs.

---
8.  Migration checklist
---
1.  new file `tick_logger.lua` + registration in `control.lua`.  
2.  `schema.lua` with OBS/ACTIONS tables.  
3.  Modify **every** action module:  
    • delete direct `buffer_event` calls,  
    • add `poll`,  
    • use `enqueue_retrospective` where needed.  
4.  Remove FLUSH_EVERY constant from `control.lua`; flushing is Tick-Logger’s job.  
5.  Update README examples to note `tick_dense.jsonl` output.  
6.  Test: a) run sandbox save, b) assert `len(jsonl)==game.ticks`.

---
9.  Things easy to overlook
---
•  Multiple players in multiplayer replays – tick records are *per-player*.  
•  A player can disconnect mid-replay; Tick-Logger should skip if
   `not player or not player.valid or not player.connected`.  
•  Buffered file writes must specify `append = true` **except** first write.  
•  `script.on_tick` handler must be registered only once; avoid accidental
   multiple registrations when mods reload.  
•  Retro-patches must survive save/load → handle in `on_load()`.

---
This architecture keeps every existing session algorithm intact, adds a single
deterministic aggregation point, and produces the dense tick-level dataset you
need for offline state-representation learning without risking Factorio
desyncs.