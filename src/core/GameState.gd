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
## column now costs ~50-80 KB, so a decent radius is affordable at full detail.
var view_distance_chunks: int = 10
## Total loaded radius. LOD is disabled while its boundary cracks are unsolved
## (set > view_distance_chunks to re-enable coarse far chunks). Full detail is
## cheap enough now that this equals the view distance for a seam-free image.
var lod_distance_chunks: int = 10

## Maximum chunk columns to (re)mesh per frame. Sparse storage + the buried-rock
## skip keep each column to a handful of sections, so a small budget streams the
## world in smoothly.
var max_meshes_per_frame: int = 2

func set_seed(value: int) -> void:
	world_seed = value
	seed_changed.emit(value)

func randomize_seed() -> void:
	set_seed(randi())
