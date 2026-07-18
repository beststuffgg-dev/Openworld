class_name MobSpawner
extends Node3D
## Spawns and manages wildlife around the player.
##
## Keeps a capped population of animals on loaded, dry land near the player,
## despawns them when they drift too far, and shifts both the population cap and
## the species mix by season. When a season turns it nudges existing animals into
## a seasonal migration. This is the foundation the roadmap's breeding/taming and
## biome-specific fauna build on.

enum Species { CHICKEN, COW, BULL }

@export var max_animals: int = 12
@export var spawn_interval: float = 3.0
# Distances are in world metres (voxels are 0.5 m; a chunk is 8 m).
@export var spawn_min_dist: float = 8.0
@export var spawn_max_dist: float = 24.0
@export var despawn_dist: float = 40.0

var _world: VoxelWorld
var _player: Node3D
var _seasons: SeasonManager
var _animals: Array[Animal] = []
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# Per-season spawn weights for [chicken, cow, bull] and a population cap factor.
const SEASON_TABLE := {
	SeasonManager.Season.SPRING: {"weights": [5, 3, 1], "cap": 1.0},
	SeasonManager.Season.SUMMER: {"weights": [3, 4, 2], "cap": 1.0},
	SeasonManager.Season.AUTUMN: {"weights": [2, 4, 3], "cap": 0.85},
	SeasonManager.Season.WINTER: {"weights": [1, 2, 3], "cap": 0.55},
}

func setup(world: VoxelWorld, player: Node3D, seasons: SeasonManager) -> void:
	_world = world
	_player = player
	_seasons = seasons
	_rng.randomize()
	if _seasons:
		_seasons.season_changed.connect(_on_season_changed)

func _process(delta: float) -> void:
	_prune()
	if not is_instance_valid(_player) or _world == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_try_spawn()

func _prune() -> void:
	var kept: Array[Animal] = []
	for a in _animals:
		if not is_instance_valid(a):
			continue
		if a.global_position.y < -8.0:
			a.queue_free()
			continue
		if is_instance_valid(_player) and a.global_position.distance_to(_player.global_position) > despawn_dist:
			a.queue_free()
			continue
		kept.append(a)
	_animals = kept

func _current_cap() -> int:
	if _seasons == null:
		return max_animals
	return int(round(max_animals * SEASON_TABLE[_seasons.current]["cap"]))

func _try_spawn() -> void:
	if _animals.size() >= _current_cap():
		return
	# Pick a spot (world metres) in a ring around the player.
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(spawn_min_dist, spawn_max_dist)
	var probe := _player.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	if not _world.is_ready_at(probe):
		return

	var v := Chunk.world_to_voxel(probe)
	var surface := _find_surface(v.x, v.z)
	if surface < 0:
		return

	var animal := _make_animal(_choose_species())
	animal.player = _player
	add_child(animal)
	# Place on top of the surface voxel, converting voxel coords back to metres.
	animal.global_position = Vector3(
		(v.x + 0.5) * Chunk.VOXEL_SCALE,
		(surface + 1) * Chunk.VOXEL_SCALE + 0.2,
		(v.z + 0.5) * Chunk.VOXEL_SCALE)
	_animals.append(animal)

## Returns the voxel y of the top solid, dry-land block in this column, or -1.
func _find_surface(wx: int, wz: int) -> int:
	for y in range(Chunk.CHUNK_HEIGHT - 2, 0, -1):
		var b := _world.get_block_world(Vector3i(wx, y, wz))
		if not BlockDB.is_solid(b):
			continue
		# Must be walkable ground with open air above (not an underwater floor).
		if b != BlockDB.Type.GRASS and b != BlockDB.Type.DIRT and b != BlockDB.Type.SAND:
			return -1
		if _world.get_block_world(Vector3i(wx, y + 1, wz)) != BlockDB.Type.AIR:
			return -1
		return y
	return -1

func _choose_species() -> int:
	var weights: Array = SEASON_TABLE[_seasons.current]["weights"] if _seasons else [3, 3, 2]
	var total := 0
	for w in weights:
		total += w
	var roll := _rng.randi_range(1, total)
	var acc := 0
	for i in weights.size():
		acc += weights[i]
		if roll <= acc:
			return i
	return Species.COW

func _make_animal(species: int) -> Animal:
	match species:
		Species.CHICKEN: return Chicken.new()
		Species.BULL: return Bull.new()
		_: return Cow.new()

func _on_season_changed(_season: int) -> void:
	# Turn of season sends the herd drifting in the seasonal direction.
	var dir := _seasons.migration_direction()
	for a in _animals:
		if is_instance_valid(a) and _rng.randf() < 0.7:
			a.migrate(dir)
