extends Node
## Lightweight global game state / config singleton (`GameState` autoload).
##
## Holds the world seed and a handful of tunables that multiple systems read.
## In a full build this grows into a proper save-game and settings service; for
## the vertical slice it centralises the seed so terrain generation stays
## deterministic across chunks and sessions.

signal seed_changed(new_seed: int)

const DEFAULT_SEED := 1337

var world_seed: int = DEFAULT_SEED

## Chunk radius kept at FULL detail around the player (a chunk spans
## 16 * Chunk.VOXEL_SCALE = 8 m). LOD reduces the GEOMETRY cost of the outer
## rings, but every loaded column still stores full-resolution voxel data
## (~512 KB at 2048 tall), so the TOTAL radius (lod_distance_chunks) is what
## bounds memory. These are deliberately modest; the real unlock for a far,
## km-scale view is sparse/uniform-section storage — see docs/ROADMAP.md.
var view_distance_chunks: int = 4
## Total loaded radius; rings beyond view_distance render as coarse LOD columns.
var lod_distance_chunks: int = 6

## Maximum chunk columns to (re)mesh per frame. Building a column now means
## meshing its handful of non-buried vertical sections plus re-culling neighbours,
## so this is kept low to stay responsive while the tall world streams in.
var max_meshes_per_frame: int = 1

func set_seed(value: int) -> void:
	world_seed = value
	seed_changed.emit(value)

func randomize_seed() -> void:
	set_seed(randi())
