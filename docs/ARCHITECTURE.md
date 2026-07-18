# Architecture

This document explains how the vertical slice is put together and the principles
that keep it extendable toward the full design.

## Guiding principles

1. **Data and behaviour separated from the scene tree where it helps threading.**
   `Chunk`, `TerrainGenerator` and `ChunkMesher` are plain `RefCounted` objects
   that never touch nodes, so terrain generation can run on background threads
   safely. Only `VoxelWorld` and gameplay nodes live in the tree.
2. **One composition root.** `Bootstrap.gd` builds the whole running scene in
   code. New systems are wired in one place; there is no hidden state buried in
   binary scenes.
3. **Registry-driven content.** Block behaviour (colour, solidity, transparency)
   lives in `BlockRegistry`. Adding a block is a one-line registration, not a
   change to the mesher or generator.
4. **Rate-limit expensive work.** Chunk meshing is capped per frame; terrain
   generation is offloaded to `WorkerThreadPool`. The main thread stays for
   input, physics and rendering.

## The chunk pipeline

```
        player moves
             │
             ▼
   VoxelWorld._update_requested()      picks chunks in view radius, nearest-first
             │  Chunk.new()  + WorkerThreadPool.add_task(generate_chunk)
             ▼
   [ background thread ]  TerrainGenerator.generate_chunk()   fills voxel bytes
             │
             ▼
   VoxelWorld._collect_generated()     main thread, polls task completion
             │  enqueue for meshing
             ▼
   VoxelWorld._drain_mesh_queue()      builds ≤ N meshes / frame
             │  ChunkMesher.build(chunk, sampler)
             ▼
   MeshInstance3D + StaticBody3D trimesh collision added to the tree  → READY
```

Chunks leaving the radius are freed (`_unload_far`), waiting on any in-flight
generation task first so a background thread never writes into a freed chunk.

### Why culled meshing + vertex AO

- **Culled meshing** emits only faces adjacent to a transparent block, so solid
  terrain interiors cost no geometry. Neighbour lookups use a `sampler` callable
  that reads across chunk borders, so seams cull correctly.
- **Ambient occlusion** is baked per vertex (the standard "count solid neighbours
  at each corner" method) and multiplied into the vertex colour. This is what
  softens the hard cubic read the design wants to avoid — no extra geometry, and
  it upgrades cleanly to a texture-atlas material later because the mesher already
  separates opaque and translucent surfaces.

The next efficiency step is **greedy meshing** (merging coplanar faces of the
same block into larger quads); the current per-face approach is deliberately
simple and correct first. See the roadmap.

## Coordinate systems

- **World coordinates**: integer block positions, `Vector3i`.
- **Chunk coordinates**: `Vector2i(cx, cz)`, world = coord × `CHUNK_SIZE`.
- **Local coordinates**: `0..CHUNK_SIZE` / `0..CHUNK_HEIGHT` inside a chunk.

`CHUNK_SIZE = 16`, `CHUNK_HEIGHT = 96`, `SEA_LEVEL = 40` (see `Chunk` /
`TerrainGenerator`). The world is currently a single vertical layer of chunks;
moving to stacked vertical chunk sections is a phase-1 roadmap item and only
touches `Chunk` and `VoxelWorld`.

## Determinism

All terrain derives from `GameState.world_seed`. Each noise layer is seeded from
`world_seed + k`, so the same seed always yields the same world — a prerequisite
for save/load and for multiplayer clients agreeing on generation.

## Extension points

| Want to add… | Touch… |
| --- | --- |
| A new block | `BlockRegistry` (+ `placeable` if hand-placeable) |
| New terrain feature (rivers, ravines) | `TerrainGenerator` |
| Textures / PBR materials | `ChunkMesher` materials + UVs |
| Structures (villages, ruins) | new post-pass over generated chunks in `VoxelWorld` |
| Weather / seasons | extend `DayNightCycle` into an `EnvironmentDirector` |
| Save/load | serialise `Chunk.voxels` (already a `PackedByteArray`) |
| Multiplayer | authoritative `VoxelWorld` + replicate block edits |

Each of these is scoped so it can be built without rewriting the others — which
is the whole point of the layering.
