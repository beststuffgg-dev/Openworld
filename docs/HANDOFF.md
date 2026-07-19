# Handoff: local verification for Project Horizons

**Who this is for:** a Claude Code (or any coding agent) running **locally on a
machine with Godot 4.4+ installed**, taking over from the remote agent that built
this project.

**Why it exists:** the entire project so far was written **without ever running
Godot** — the remote build environment has no engine. Everything is
inspection-validated only. Your job is to close that gap: run it, find what's
broken or ugly, fix it, and verify visually. This is high-leverage — one real run
finds in seconds what inspection cannot.

---

## 0. Orientation (read first, ~5 min)

- `README.md` — what the game is, controls, how to run.
- `docs/ARCHITECTURE.md` — how the voxel engine fits together.
- `docs/ROADMAP.md` — what's done (✅/🟡) vs planned, in dependency order.
- Engine: **Godot 4.4+, GDScript** (not C#). Text-based project; everything is
  code-driven from `scenes/Main.tscn` → `src/core/Bootstrap.gd`.
- Git: work on branch **`claude/project-horizons-voxel-rpg-buluev`**. Commit with
  clear messages; push with `git push -u origin <branch>`. Don't open a PR unless
  asked.

## 1. Prerequisites

- Godot **4.4 or newer**, standard build (NOT .NET/Mono). Download:
  https://godotengine.org/download
- Confirm the binary is on PATH (call it `godot` below; adjust as needed):
  ```sh
  godot --version        # expect 4.4.x.stable or newer
  ```
- From the repo root (the folder containing `project.godot`).

## 2. The verify → fix loop

Run these in order every iteration. Fix what they report, re-run, repeat until
clean.

### 2a. Parse / import check (catches script errors)
Opening the project imports resources and parses every script. Autoload parse
errors (like the `get_name()` shadowing bug) show up here immediately.

```sh
godot --headless --editor --quit --path . 2>&1 | tee /tmp/ph_import.log
grep -nE "SCRIPT ERROR|Parse Error|Parser Error|ERROR|error:" /tmp/ph_import.log
```

- Any `Parse Error` / `SCRIPT ERROR` line names a file + line — fix and re-run.
- **Known pattern already hit:** a method that shadows a built-in with a
  different signature (e.g. `func get_name() -> String` clashing with
  `Node.get_name() -> StringName`). If you see "signature doesn't match the
  parent", rename the method and update call sites.

### 2b. Runtime check (headless, catches runtime errors)
Run the actual game headlessly for a few hundred frames — this exercises world
generation, greedy meshing, structure stamping, mob spawning, day/night, etc.
Headless has no rendering, so this catches *script* runtime errors, not visuals.

```sh
godot --headless --path . --quit-after 900 2>&1 | tee /tmp/ph_run.log
grep -nE "SCRIPT ERROR|ERROR|Nil|null instance|out of bounds|Condition .* is true" /tmp/ph_run.log
```

- `--quit-after 900` ≈ 15 s at 60 fps, enough for chunks to stream and a mob
  cycle. Increase if you want more coverage.
- Worker-thread errors (terrain/structure generation) print here too.

### 2c. Visual check (windowed, catches rendering bugs)
This is the payoff: actually see the world. Create this throwaway SceneTree
script, run it, then **read the PNG it saves** (you have vision — look at it).

Create `verify/capture.gd`:
```gdscript
extends SceneTree
## Boots the main scene, waits for the world to stream in, screenshots, quits.
## Run: godot --path . --script verify/capture.gd   (needs a display)
var _frames := 0
func _initialize() -> void:
	root.add_child(load("res://scenes/Main.tscn").instantiate())
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 300:  # ~5 s: let terrain + structures load
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://verify/shot.png"))
		print("saved verify/shot.png")
	if _frames >= 306:
		quit()
	return false
```
Then:
```sh
godot --path . --script verify/capture.gd
# open and LOOK at verify/shot.png
```

If your machine has no display, run under a virtual one, e.g.
`xvfb-run -a godot --path . --script verify/capture.gd` (Linux).

To poke around interactively instead, just `godot --path .` and play (WASD,
mouse, left/right-click, Esc for Settings).

## 3. What to verify (prioritized — most-likely-broken first)

The whole rendering + storage stack is untested. Check in this order:

1. **It launches** — 2a and 2b are clean (no red errors).
2. **Terrain renders solid** — no missing chunks, no holes. Look especially for
   **banding / seams every 32 blocks vertically** (that's the section-boundary
   "owner filter" in `ChunkMesher` — the highest-risk logic).
3. **Collision** — the player lands on the surface and can walk/climb, doesn't
   fall through the world. (Spawn drops from the top; give it a second.)
4. **Editing** — left-click digs, right-click places, the mouse wheel changes
   block, `[`/`]` change brush size, bulk brush works. Sparse storage +
   copy-on-write edits are new; verify no crash and no corruption.
5. **Shape tool** — Settings → pick Cube/Sphere/Slope/Cylinder, then click A,
   click B, scroll, click to place. Ghost preview should track.
6. **Structures** — wander; houses / ruined towers / wall ruins should appear on
   flat land (they were just added and never run).
7. **Settings menu** — Esc opens, Resume and Esc both close it, buttons work.
8. **Atmosphere** — day/night moves the sun; seasons tint foliage; weather
   changes; chickens/cows/bulls spawn and wander.

Note anything visually wrong with a screenshot and the suspected system.

## 4. Known-risky code (where bugs most likely hide)

- `src/world/ChunkMesher.gd` — greedy meshing + the y-face **owner filter**
  (`_owner_filter`) that prevents double faces at section boundaries. If you see
  banding/holes at regular heights, start here.
- `src/world/Chunk.gd` — **sparse sections** (int-or-PackedByteArray) and the
  copy-on-write-safe `set_local`. Corruption on edit would point here.
- `src/world/TerrainGenerator.gd` — uniform-section fast path (deep rock / sky).
  A wrong height-range test could leave holes or over-fill.
- `src/world/StructureGenerator.gd` — brand new, never run.
- LOD (`build_column_lod`, `_lod_for`) is currently **disabled**
  (`view == lod` radius in `GameState`) because of boundary cracks — leave it off
  until stitching is implemented.

## 5. Tuning knobs (in `src/core/GameState.gd` and `src/world/Chunk.gd`)

- `GameState.view_distance_chunks` (8) — view distance vs FPS. Lower for weak
  hardware, raise for strong.
- `GameState.max_meshes_per_frame` (2) — streaming smoothness vs fill speed.
- `Chunk.VOXEL_SCALE` (0.5 m/voxel), `Chunk.CHUNK_HEIGHT` (2048), `SECTION_H`
  (32) — world scale/height. Changing these rescales everything.

## 6. Deeper optimizations left on the table (if perf is poor)

In rough value order; each is riskier, so verify after each:
- **Threaded meshing** — build `ArrayMesh`/collision on a `WorkerThreadPool`
  task, apply on the main thread. Guard: don't free/edit a chunk mid-mesh. This
  is the real fix for streaming hitches.
- **Fewer draw calls** — one mesh per column instead of per-section (loses
  per-section frustum culling; measure first).
- **Collision from solid blocks only** — build the trimesh from the opaque
  surface, not the water surface (also stops the player walking on water).
- **Collision only near the player** — skip trimesh build for distant sections.

## 7. Workflow contract

- Small, focused commits with descriptive messages; push to the branch above.
- After a fix, re-run 2a + 2b (and 2c if visual) before committing.
- Keep `docs/ROADMAP.md` statuses honest as you verify/fix.
- Delete `verify/` (the throwaway capture script) before committing, or keep it
  under a clearly-temporary path — don't ship it as game code.

Good hunting. The foundation is substantial and internally consistent; it mostly
needs a real engine to shake out the last mile.
