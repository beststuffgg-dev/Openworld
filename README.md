# Project Horizons

A cross-platform **voxel sandbox RPG** — the long-term vision is a living,
procedurally generated world with survival, building, quests, NPC villages,
dungeons and multiplayer, rendered in a soft, less-blocky style.

This repository currently contains a **working vertical slice**: an infinite,
threaded, procedurally generated voxel world you can walk around in, mine and
build in, under a moving day/night sky. It is the foundation the full design
grows from — see [`docs/ROADMAP.md`](docs/ROADMAP.md) for how every system in
the design document maps onto a realistic, phased build order, and
[`docs/DESIGN.md`](docs/DESIGN.md) for the full vision it works toward.

> **Scope honesty.** The original brief describes an AAA-scale game (Minecraft +
> Valheim + Zelda: TotK with high-end shaders and cross-play). That is years of
> studio work, not a single deliverable. This repo is engineered so that work can
> actually be built incrementally instead of faked. What runs today is real and
> playable; what doesn't yet is documented as a roadmap, not pretended into
> existence.

## Engine

**Godot 4.4+** (Forward+ renderer on desktop, Mobile renderer on phones). Godot
was chosen for its open-source, text-based project format and first-class
Windows / Android / iOS export.

## Running

1. Install [Godot 4.4 or newer](https://godotengine.org/download).
2. Open the project: `godot --path . ` or open `project.godot` from the editor.
3. Press **F5** (Play). The world streams in and you drop onto the terrain.

The project is fully code-driven from a one-node entry scene
(`scenes/Main.tscn` → `src/core/Bootstrap.gd`), so there are no fragile binary
scene files to merge.

## Controls

| Action | Input |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Jump | `Space` |
| Sprint | `Shift` |
| Look | Mouse |
| Break block | Left click |
| Place block | Right click |
| Change block | Mouse wheel |
| Release / capture mouse | `Esc` |

## What works today

- **Infinite terrain** from a deterministic seed: continents, hills, mountains,
  oceans and beaches from layered Perlin/Simplex noise.
- **Biomes** from temperature + moisture maps (plains, forest, jungle, desert,
  tundra, snow mountains, swamp, ocean/beach) with soft, noise-driven borders.
- **Caves** carved with 3D noise, **water** to sea level, and scattered **trees**.
- **Threaded chunk streaming** — terrain generation runs on a `WorkerThreadPool`;
  mesh building is rate-limited per frame so movement stays smooth.
- **Culled meshing with ambient-occlusion vertex shading** for the softer,
  less-blocky read, plus a translucent water surface.
- **Mine & build** any block, with correct chunk-seam remeshing.
- **Day/night cycle** with a moving sun, warm sunrises and darkening nights.

## Project layout

```
project.godot            Engine config, autoloads, input map
scenes/Main.tscn         One-node entry scene → Bootstrap
src/
  core/
    Bootstrap.gd         Composition root; builds the running scene
    GameState.gd         Global seed + tunables (autoload)
  world/
    BlockRegistry.gd     Block types & properties (autoload: BlockDB)
    Chunk.gd             Raw voxel storage
    TerrainGenerator.gd  Noise-based terrain + biomes + trees (thread-safe)
    ChunkMesher.gd       Culled meshing + ambient occlusion
    VoxelWorld.gd        Chunk streaming, collision, block editing
  player/Player.gd       First-person controller + block interaction
  environment/DayNightCycle.gd
  ui/HUD.gd
docs/                    Architecture, design vision, roadmap
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how the pieces fit
together and why.
