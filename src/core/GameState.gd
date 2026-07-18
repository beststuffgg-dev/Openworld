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

## How many chunks (radius, in chunk units) to keep loaded at FULL detail around
## the player. A chunk spans 16 * Chunk.VOXEL_SCALE = 8 m. Kept modest because
## columns are now 2048 voxels tall; the LOD system extends the visible range
## beyond this with cheap coarse chunks.
var view_distance_chunks: int = 6
## Additional rings (beyond view_distance_chunks) kept as lower-detail LOD chunks.
var lod_distance_chunks: int = 18

## Maximum chunk columns to (re)mesh per frame. Building a column now means
## meshing its handful of non-buried vertical sections plus re-culling neighbours,
## so this is kept low to stay responsive while the tall world streams in.
var max_meshes_per_frame: int = 1

func set_seed(value: int) -> void:
	world_seed = value
	seed_changed.emit(value)

func randomize_seed() -> void:
	set_seed(randi())
