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
## 16 * Chunk.VOXEL_SCALE = 8 m, so 8 chunks ≈ 64 m). Each loaded section is its
## own draw call, so this trades view distance against frame rate — raise it on a
## strong GPU, lower it on a weak one.
var view_distance_chunks: int = 8
## Total loaded radius. LOD is disabled while its boundary cracks are unsolved
## (set > view_distance_chunks to re-enable coarse far chunks).
var lod_distance_chunks: int = 8

## Maximum chunk columns to (re)mesh per frame. Sparse storage + the buried-rock
## skip keep each column to a handful of sections, so a small budget streams the
## world in smoothly.
var max_meshes_per_frame: int = 2

func set_seed(value: int) -> void:
	world_seed = value
	seed_changed.emit(value)

func randomize_seed() -> void:
	set_seed(randi())
