class_name Chunk
extends RefCounted
## Sparse voxel storage for one column of the world.
##
## A column is CHUNK_SIZE x CHUNK_SIZE wide and CHUNK_HEIGHT tall, divided into
## SECTIONS vertical sections. Each section is stored as EITHER a single block id
## (a uniform section — all air, or all one block, costs one int) OR an 8 KB
## PackedByteArray (a mixed section). This is what makes the 2048-tall world
## affordable: the deep uniform rock and the empty sky above cost almost nothing,
## and only the surface / cave / water bands allocate an array. The chunk holds
## only data (meshing lives in ChunkMesher), so it can be filled on a worker
## thread.

const CHUNK_SIZE := 16
## 2048 voxels * VOXEL_SCALE (0.5 m) = a 1024 m tall world, enough for ~1 km
## mountains. Sparse sections + the "buried section" skip keep it affordable.
const CHUNK_HEIGHT := 2048

## A column is meshed as a stack of vertical SECTIONS, each SECTION_H voxels tall.
## Empty sections build no mesh, each section is a separate MeshInstance for
## independent frustum culling and LOD, and an edit only re-meshes the section(s)
## it touches.
const SECTION_H := 32
## 64 sections; this is also the max, since section flags pack into a 64-bit int.
const SECTIONS := CHUNK_HEIGHT / SECTION_H  # 2048 / 32 = 64
const SECTION_VOLUME := SECTION_H * CHUNK_SIZE * CHUNK_SIZE  # 8192

## Physical size of one voxel in world units (metres). Minecraft blocks are 1.0;
## this makes each block 0.5 — half Minecraft's size — for finer building detail.
## Change this one constant to rescale the whole world; everything derives from it.
const VOXEL_SCALE := 0.5

## Converts world-space metres to integer voxel coordinates.
static func world_to_voxel(w: Vector3) -> Vector3i:
	return Vector3i(floori(w.x / VOXEL_SCALE), floori(w.y / VOXEL_SCALE), floori(w.z / VOXEL_SCALE))

## World-space centre of a voxel.
static func voxel_center(v: Vector3i) -> Vector3:
	return (Vector3(v) + Vector3(0.5, 0.5, 0.5)) * VOXEL_SCALE

## Chunk grid coordinates (world position = coord * CHUNK_SIZE).
var cx: int
var cz: int

# One entry per section: an int (uniform block id) or a PackedByteArray (mixed).
var _sections: Array = []

# Bit `s` set once section `s` has any non-air block — worth meshing.
var _section_nonair: int = 0
# Bit `s` set when section `s` is entirely solid — combined with its neighbours
# (VoxelWorld) it can be skipped as fully buried. Digging clears the bit.
var _section_full: int = 0

func _init(p_cx: int, p_cz: int) -> void:
	cx = p_cx
	cz = p_cz
	_sections.resize(SECTIONS)
	for i in SECTIONS:
		_sections[i] = BlockDB.Type.AIR  # uniform air

static func in_bounds(lx: int, ly: int, lz: int) -> bool:
	return lx >= 0 and lx < CHUNK_SIZE \
		and lz >= 0 and lz < CHUNK_SIZE \
		and ly >= 0 and ly < CHUNK_HEIGHT

## Index of a voxel within its section's byte array.
static func _local_index(lx: int, ly: int, lz: int) -> int:
	return lx + lz * CHUNK_SIZE + (ly % SECTION_H) * CHUNK_SIZE * CHUNK_SIZE

func get_local(lx: int, ly: int, lz: int) -> int:
	if not in_bounds(lx, ly, lz):
		return BlockDB.Type.AIR
	@warning_ignore("integer_division")
	var s = _sections[ly / SECTION_H]
	if typeof(s) == TYPE_INT:
		return s
	return s[_local_index(lx, ly, lz)]

func set_local(lx: int, ly: int, lz: int, id: int) -> void:
	if not in_bounds(lx, ly, lz):
		return
	@warning_ignore("integer_division")
	var sec := ly / SECTION_H
	var li := _local_index(lx, ly, lz)
	var s = _sections[sec]
	if typeof(s) == TYPE_INT:
		if s == id:
			return  # no change to a uniform section
		# Materialise the uniform section into a mutable array (local => in-place).
		var arr := PackedByteArray()
		arr.resize(SECTION_VOLUME)
		arr.fill(s)
		arr[li] = id
		_sections[sec] = arr
	else:
		# PackedByteArray is copy-on-write; drop the container's reference so the
		# write happens in place instead of copying all 8 KB per block.
		_sections[sec] = 0
		s[li] = id
		_sections[sec] = s
	if id != BlockDB.Type.AIR:
		_section_nonair |= 1 << sec
	else:
		_section_full &= ~(1 << sec)  # dug a hole -> no longer fully solid

## Sets a whole section to a single block without allocating an array. Used by
## generation for the deep uniform rock and the empty sky.
func set_section_uniform(sec: int, id: int) -> void:
	_sections[sec] = id
	if id != BlockDB.Type.AIR:
		_section_nonair |= 1 << sec

## True if section `sec` has any non-air block (so it's worth meshing).
func section_has_content(sec: int) -> bool:
	return (_section_nonair & (1 << sec)) != 0

## True if every voxel in section `sec` is a solid block.
func section_full_solid(sec: int) -> bool:
	return (_section_full & (1 << sec)) != 0

## Recomputes the content/solid flags from the section data. Call once after
## generation (safe on a worker thread — reads only the block registry).
func compute_section_flags() -> void:
	_section_nonair = 0
	_section_full = 0
	for sec in SECTIONS:
		var s = _sections[sec]
		if typeof(s) == TYPE_INT:
			if s != BlockDB.Type.AIR:
				_section_nonair |= 1 << sec
			if BlockDB.is_solid(s):
				_section_full |= 1 << sec
		else:
			var nonair := false
			var full := true
			var uniform := true
			var first: int = s[0]
			for i in SECTION_VOLUME:
				var b: int = s[i]
				if b != BlockDB.Type.AIR:
					nonair = true
				if not BlockDB.is_solid(b):
					full = false
				if b != first:
					uniform = false
			if nonair:
				_section_nonair |= 1 << sec
			if full:
				_section_full |= 1 << sec
			# A section that ended up all one block collapses back to an int.
			if uniform:
				_sections[sec] = first

func world_origin() -> Vector3:
	return Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
