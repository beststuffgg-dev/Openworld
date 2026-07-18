class_name StructureGenerator
extends RefCounted
## Places abandoned structures (houses, ruined towers, wall ruins) into the world
## during generation.
##
## The world is divided into a grid of CELL-sized cells; each cell deterministically
## may hold one structure at a jittered position. Because placement is a pure
## function of the seed and cell coordinates, every chunk can independently stamp
## the parts of any structure that overlap it — so a building that straddles a
## chunk border is written consistently by both chunks with no cross-chunk state.
## Runs on the generation worker thread (only reads noise + the block registry).

const CELL := 96          # world voxels per structure cell
const OVERLAP := 24       # >= a structure's max horizontal extent
const INSET := 12         # keep structures away from cell edges

var _seed: int
var _height_fn: Callable   # Callable(wx, wz) -> int surface height
var _sea_level: int

func _init(world_seed: int, height_fn: Callable, sea_level: int) -> void:
	_seed = world_seed
	_height_fn = height_fn
	_sea_level = sea_level

## Stamps every structure overlapping the chunk at (base_x, base_z).
func stamp_chunk(chunk: Chunk, base_x: int, base_z: int) -> void:
	var cs := Chunk.CHUNK_SIZE
	var cx0 := floori(float(base_x - OVERLAP) / CELL)
	var cx1 := floori(float(base_x + cs + OVERLAP) / CELL)
	var cz0 := floori(float(base_z - OVERLAP) / CELL)
	var cz1 := floori(float(base_z + cs + OVERLAP) / CELL)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			_try_cell(chunk, base_x, base_z, cx, cz)

func _try_cell(chunk: Chunk, base_x: int, base_z: int, cellx: int, cellz: int) -> void:
	# ~22% of cells have a structure.
	if _hash(cellx, cellz, 1) % 100 >= 22:
		return
	var span := CELL - 2 * INSET
	var ox := cellx * CELL + INSET + _hash(cellx, cellz, 2) % span
	var oz := cellz * CELL + INSET + _hash(cellx, cellz, 3) % span
	var oy := int(_height_fn.call(ox, oz))
	if oy <= _sea_level + 1 or oy > _sea_level + 250:
		return  # underwater or high mountain — no building
	if not _flat_enough(ox, oz, oy):
		return

	match _hash(cellx, cellz, 4) % 3:
		0:
			_house(chunk, base_x, base_z, ox, oy, oz, cellx, cellz)
		1:
			_tower(chunk, base_x, base_z, ox, oy, oz, cellx, cellz)
		_:
			_ruin(chunk, base_x, base_z, ox, oy, oz, cellx, cellz)

# --- Structure shapes ------------------------------------------------------

func _house(chunk: Chunk, bx: int, bz: int, ox: int, oy: int, oz: int, cellx: int, cellz: int) -> void:
	var w := 5 + _hash(cellx, cellz, 5) % 3
	var d := 5 + _hash(cellx, cellz, 6) % 3
	var wall_h := 4
	# Floor.
	for x in range(ox, ox + w):
		for z in range(oz, oz + d):
			_place(chunk, bx, bz, x, oy, z, BlockDB.Type.PLANKS)
	# Walls.
	for yy in range(1, wall_h):
		for x in range(ox, ox + w):
			for z in range(oz, oz + d):
				if x == ox or x == ox + w - 1 or z == oz or z == oz + d - 1:
					_place(chunk, bx, bz, x, oy + yy, z, BlockDB.Type.WOOD)
	# Flat roof.
	for x in range(ox, ox + w):
		for z in range(oz, oz + d):
			_place(chunk, bx, bz, x, oy + wall_h, z, BlockDB.Type.PLANKS)
	# Doorway on the -Z wall.
	var dx := ox + w / 2
	_place(chunk, bx, bz, dx, oy + 1, oz, BlockDB.Type.AIR)
	_place(chunk, bx, bz, dx, oy + 2, oz, BlockDB.Type.AIR)

func _tower(chunk: Chunk, bx: int, bz: int, ox: int, oy: int, oz: int, cellx: int, cellz: int) -> void:
	var r := 2 + _hash(cellx, cellz, 5) % 2
	var th := 10 + _hash(cellx, cellz, 6) % 10
	for yy in range(th):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var dd := dx * dx + dz * dz
				if dd <= r * r and dd > (r - 1) * (r - 1):
					# Crumble the top few rings.
					if yy > th - 4 and _hash(ox + dx, oz + dz + yy, 7) % 3 == 0:
						continue
					_place(chunk, bx, bz, ox + dx, oy + yy, oz + dz, BlockDB.Type.STONE)

func _ruin(chunk: Chunk, bx: int, bz: int, ox: int, oy: int, oz: int, cellx: int, cellz: int) -> void:
	var w := 6 + _hash(cellx, cellz, 5) % 5
	var d := 6 + _hash(cellx, cellz, 6) % 5
	var wall_h := 2 + _hash(cellx, cellz, 7) % 2
	for yy in range(wall_h):
		for x in range(ox, ox + w):
			for z in range(oz, oz + d):
				if x == ox or x == ox + w - 1 or z == oz or z == oz + d - 1:
					# Broken: ~1/3 of blocks are missing.
					if _hash(x, z + yy * 31, 8) % 3 != 0:
						_place(chunk, bx, bz, x, oy + yy, z, BlockDB.Type.STONE)

# --- Helpers ---------------------------------------------------------------

## Writes a voxel only if it falls inside this chunk's columns.
func _place(chunk: Chunk, base_x: int, base_z: int, wx: int, wy: int, wz: int, id: int) -> void:
	var lx := wx - base_x
	var lz := wz - base_z
	if lx >= 0 and lx < Chunk.CHUNK_SIZE and lz >= 0 and lz < Chunk.CHUNK_SIZE and wy >= 0 and wy < Chunk.CHUNK_HEIGHT:
		chunk.set_local(lx, wy, lz, id)

## True when the footprint corners are within a few voxels of the origin height.
func _flat_enough(ox: int, oz: int, oy: int) -> bool:
	var lo := oy
	var hi := oy
	for o in [Vector2i(6, 0), Vector2i(0, 6), Vector2i(6, 6), Vector2i(-2, -2)]:
		var h := int(_height_fn.call(ox + o.x, oz + o.y))
		lo = mini(lo, h)
		hi = maxi(hi, h)
	return hi - lo <= 3

func _hash(a: int, b: int, salt: int) -> int:
	var h: int = (_seed * 6364136 + 1) ^ (a * 73856093) ^ (b * 19349663) ^ (salt * 2654435761)
	return h & 0x7fffffff
