class_name TerrainGenerator
extends RefCounted
## Deterministic procedural terrain generator.
##
## Combines several layers of FastNoiseLite to shape the world, then classifies
## each surface column into a biome from temperature + moisture maps. This is the
## foundation the spec's richer generation (erosion, rivers, caverns, structures)
## plugs into later — see docs/ROADMAP.md phase 2.
##
## The generator is intentionally free of any scene-tree access so it can run on
## a WorkerThreadPool background thread without touching Godot objects.

const CHUNK_SIZE := Chunk.CHUNK_SIZE
const CHUNK_HEIGHT := Chunk.CHUNK_HEIGHT
const SEA_LEVEL := 40
const DIRT_DEPTH := 4

enum Biome { OCEAN, BEACH, DESERT, PLAINS, FOREST, JUNGLE, TUNDRA, SNOW_MOUNTAIN, SWAMP, MOUNTAIN }

var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _mountains: FastNoiseLite
var _detail: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite
var _caves: FastNoiseLite
var _tree_noise: FastNoiseLite

func _init(world_seed: int) -> void:
	_continent = _make_noise(world_seed + 1, FastNoiseLite.TYPE_PERLIN, 0.0025, 4)
	_hills = _make_noise(world_seed + 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 4)
	_mountains = _make_noise(world_seed + 3, FastNoiseLite.TYPE_SIMPLEX, 0.006, 5)
	_detail = _make_noise(world_seed + 4, FastNoiseLite.TYPE_PERLIN, 0.05, 3)
	_temperature = _make_noise(world_seed + 5, FastNoiseLite.TYPE_PERLIN, 0.0015, 2)
	_moisture = _make_noise(world_seed + 6, FastNoiseLite.TYPE_PERLIN, 0.0018, 2)
	_caves = _make_noise(world_seed + 7, FastNoiseLite.TYPE_PERLIN, 0.045, 2)
	_tree_noise = _make_noise(world_seed + 8, FastNoiseLite.TYPE_VALUE, 1.0, 1)

static func _make_noise(seed: int, type: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = type
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n

## Fills `chunk.voxels` for the chunk at grid coordinate (cx, cz).
func generate_chunk(chunk: Chunk) -> void:
	var base_x := chunk.cx * CHUNK_SIZE
	var base_z := chunk.cz * CHUNK_SIZE
	for lz in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var wx := base_x + lx
			var wz := base_z + lz
			_generate_column(chunk, lx, lz, wx, wz)

func _generate_column(chunk: Chunk, lx: int, lz: int, wx: int, wz: int) -> void:
	var height := _surface_height(wx, wz)
	var temp := _temperature.get_noise_2d(wx, wz)      # -1 (cold) .. 1 (hot)
	var moist := _moisture.get_noise_2d(wx, wz)        # -1 (dry) .. 1 (wet)
	var biome := _classify_biome(height, temp, moist)

	for y in CHUNK_HEIGHT:
		var block := _block_at(y, height, biome, wx, wz)
		if block != BlockDB.Type.AIR:
			chunk.set_local(lx, y, lz, block)

	# Sparse trees on suitable land above sea level.
	if _should_place_tree(wx, wz, height, biome):
		_place_tree(chunk, lx, lz, height + 1)

func _surface_height(wx: int, wz: int) -> int:
	# Continent shapes broad land/ocean masses in [-1, 1].
	var continent := _continent.get_noise_2d(wx, wz)
	# Rolling hills.
	var hills := _hills.get_noise_2d(wx, wz) * 10.0
	# Mountains only rise where the ridged component is positive, squared so the
	# terrain stays mostly gentle with occasional dramatic peaks.
	var m := _mountains.get_noise_2d(wx, wz)
	var mountains := 0.0
	if m > 0.0:
		mountains = m * m * 55.0
	var fine := _detail.get_noise_2d(wx, wz) * 2.0

	var h := SEA_LEVEL + continent * 22.0 + hills + mountains + fine
	return clampi(int(round(h)), 1, CHUNK_HEIGHT - 1)

func _classify_biome(height: int, temp: float, moist: float) -> int:
	if height < SEA_LEVEL - 1:
		return Biome.OCEAN
	if height <= SEA_LEVEL + 1:
		return Biome.BEACH
	if height > SEA_LEVEL + 45:
		return Biome.SNOW_MOUNTAIN if temp < 0.1 else Biome.MOUNTAIN
	if temp > 0.45:
		return Biome.DESERT if moist < 0.0 else Biome.JUNGLE
	if temp < -0.4:
		return Biome.TUNDRA
	if moist > 0.35:
		return Biome.SWAMP if temp > 0.0 else Biome.FOREST
	if moist > 0.05:
		return Biome.FOREST
	return Biome.PLAINS

func _block_at(y: int, height: int, biome: int, wx: int, wz: int) -> int:
	# Carve caves below the surface using 3D noise.
	if y < height - 1 and y > 2:
		if _caves.get_noise_3d(wx, y, wz) > 0.55:
			return BlockDB.Type.AIR

	if y > height:
		# Above the ground: water up to sea level, otherwise air.
		if y <= SEA_LEVEL:
			return BlockDB.Type.WATER
		return BlockDB.Type.AIR

	if y == 0:
		return BlockDB.Type.STONE

	var depth := height - y
	if y == height:
		return _surface_block(biome, height)
	if depth <= DIRT_DEPTH:
		return _subsurface_block(biome)
	return BlockDB.Type.STONE

func _surface_block(biome: int, height: int) -> int:
	match biome:
		Biome.OCEAN, Biome.BEACH, Biome.DESERT:
			return BlockDB.Type.SAND
		Biome.SNOW_MOUNTAIN, Biome.TUNDRA:
			return BlockDB.Type.SNOW
		Biome.MOUNTAIN:
			return BlockDB.Type.STONE if height > SEA_LEVEL + 55 else BlockDB.Type.GRASS
		Biome.SWAMP:
			return BlockDB.Type.CLAY
		_:
			return BlockDB.Type.GRASS

func _subsurface_block(biome: int) -> int:
	match biome:
		Biome.OCEAN, Biome.BEACH, Biome.DESERT:
			return BlockDB.Type.SAND
		Biome.SWAMP:
			return BlockDB.Type.CLAY
		_:
			return BlockDB.Type.DIRT

func _should_place_tree(wx: int, wz: int, height: int, biome: int) -> bool:
	if height <= SEA_LEVEL or height > SEA_LEVEL + 40:
		return false
	if biome != Biome.FOREST and biome != Biome.JUNGLE and biome != Biome.PLAINS:
		return false
	# Value noise gives a stable per-column pseudo-random number.
	var r := (_tree_noise.get_noise_2d(wx * 3, wz * 3) + 1.0) * 0.5
	var chance := 0.06 if biome == Biome.PLAINS else 0.14
	return r > (1.0 - chance)

func _place_tree(chunk: Chunk, lx: int, lz: int, base_y: int) -> void:
	var trunk_h := 4 + int((_tree_noise.get_noise_2d(lx * 7 + chunk.cx, lz * 7 + chunk.cz) + 1.0) * 1.5)
	for i in trunk_h:
		var y := base_y + i
		if y < CHUNK_HEIGHT:
			chunk.set_local(lx, y, lz, BlockDB.Type.WOOD)
	# Simple blob of leaves around the top of the trunk.
	var top := base_y + trunk_h
	for dy in range(-2, 2):
		var radius := 2 if dy < 0 else 1
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if abs(dx) == radius and abs(dz) == radius:
					continue
				var x := lx + dx
				var y := top + dy
				var z := lz + dz
				if x < 0 or x >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE:
					continue
				if y < 0 or y >= CHUNK_HEIGHT:
					continue
				if chunk.get_local(x, y, z) == BlockDB.Type.AIR:
					chunk.set_local(x, y, z, BlockDB.Type.LEAVES)
