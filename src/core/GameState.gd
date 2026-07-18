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
## 16 * Chunk.VOXEL_SCALE = 8 m). With sparse/uniform-section storage a tall
## column now costs ~50-80 KB (deep rock and sky are uniform), so the loaded
## radius can be much larger than the naive full-array version allowed.
var view_distance_chunks: int = 6
## Total loaded radius; rings beyond view_distance render as coarse LOD columns.
var lod_distance_chunks: int = 12

## Maximum chunk columns to (re)mesh per frame. Sparse storage + the buried-rock
## skip keep each column to a handful of sections, so a small budget streams the
## world in smoothly.
var max_meshes_per_frame: int = 2

func set_seed(value: int) -> void:
	world_seed = value
	seed_changed.emit(value)

func randomize_seed() -> void:
	set_seed(randi())
