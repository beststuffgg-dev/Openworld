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

## How many chunks (radius, in chunk units) to keep loaded around the player.
var view_distance_chunks: int = 8

## Maximum chunk meshes to build per frame. Spreading mesh work across frames
## keeps the main thread responsive while chunks stream in.
var max_meshes_per_frame: int = 2

func set_seed(value: int) -> void:
	world_seed = value
	seed_changed.emit(value)

func randomize_seed() -> void:
	set_seed(randi())
