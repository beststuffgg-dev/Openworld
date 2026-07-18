class_name Chunk
extends RefCounted
## Raw voxel storage for one column of the world.
##
## A chunk is CHUNK_SIZE x CHUNK_SIZE wide and CHUNK_HEIGHT tall. Voxels are
## packed into a single PackedByteArray (one byte per block id) for cache-friendly
## access and cheap serialisation. The chunk holds only data — meshing lives in
## ChunkMesher and scene-tree nodes live in VoxelWorld — so a chunk can be created
## and filled entirely on a background thread.

const CHUNK_SIZE := 16
## 2048 voxels * VOXEL_SCALE (0.5 m) = a 1024 m tall world, enough for ~1 km
## mountains. Deep solid rock is kept affordable by the "buried section" skip
## (section_full_solid + the mesher) rather than by limiting height.
const CHUNK_HEIGHT := 2048
const VOLUME := CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT

## A column is meshed as a stack of vertical SECTIONS, each SECTION_H voxels
## tall. Empty (all-air) sections build no mesh, each section is a separate
## MeshInstance for independent frustum culling and future per-section LOD, and
## an edit only re-meshes the section(s) it touches — the "vertical chunk
## sections" of the roadmap. Storage stays a single column array so face culling
## between sections is automatic.
const SECTION_H := 32
## 64 sections; this is also the max, since section flags pack into a 64-bit int.
const SECTIONS := CHUNK_HEIGHT / SECTION_H  # 2048 / 32 = 64

## Physical size of one voxel in world units (metres). Minecraft blocks are 1.0;
## this makes each block 0.5 — half Minecraft's size — for finer building detail.
## Greedy meshing (ChunkMesher) keeps the extra block density cheap. Change this
## one constant to rescale the whole world; everything else derives from it.
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
var voxels: PackedByteArray

## Set true once the mesh/collision for this chunk is dirty and needs rebuilding.
var dirty: bool = false

# Bit `s` is set once section `s` has had any non-air block written, so empty
# sections can skip meshing entirely. Digging never clears a bit (a since-emptied
# section just meshes to null once); that's a negligible, self-correcting cost.
var _section_nonair: int = 0

# Bit `s` set when section `s` is entirely solid blocks. Combined with its
# neighbours (VoxelWorld), a fully-solid section surrounded by fully-solid
# sections has no visible faces and is skipped — this is what makes a 2048-tall
# world of mostly-buried rock affordable. Computed once after generation; digging
# clears the bit so the section re-meshes.
var _section_full: int = 0

func _init(p_cx: int, p_cz: int) -> void:
	cx = p_cx
	cz = p_cz
	voxels = PackedByteArray()
	voxels.resize(VOLUME)  # PackedByteArray initialises to zero == AIR

static func index(lx: int, ly: int, lz: int) -> int:
	return lx + lz * CHUNK_SIZE + ly * CHUNK_SIZE * CHUNK_SIZE

static func in_bounds(lx: int, ly: int, lz: int) -> bool:
	return lx >= 0 and lx < CHUNK_SIZE \
		and lz >= 0 and lz < CHUNK_SIZE \
		and ly >= 0 and ly < CHUNK_HEIGHT

func get_local(lx: int, ly: int, lz: int) -> int:
	if not in_bounds(lx, ly, lz):
		return BlockDB.Type.AIR
	return voxels[index(lx, ly, lz)]

func set_local(lx: int, ly: int, lz: int, id: int) -> void:
	if not in_bounds(lx, ly, lz):
		return
	voxels[index(lx, ly, lz)] = id
	@warning_ignore("integer_division")
	var sec := ly / SECTION_H
	if id != BlockDB.Type.AIR:
		_section_nonair |= 1 << sec
	else:
		# Digging punches a hole, so the section is no longer fully solid.
		_section_full &= ~(1 << sec)

## True if section `sec` has ever had a non-air block (so it's worth meshing).
func section_has_content(sec: int) -> bool:
	return (_section_nonair & (1 << sec)) != 0

## True if every voxel in section `sec` is a solid block.
func section_full_solid(sec: int) -> bool:
	return (_section_full & (1 << sec)) != 0

## Recomputes the fully-solid flags. Call once after generation fills the column
## (safe on a worker thread — reads only the block registry).
func compute_section_flags() -> void:
	_section_full = 0
	var vol := SECTION_H * CHUNK_SIZE * CHUNK_SIZE
	for sec in SECTIONS:
		if not section_has_content(sec):
			continue  # all air -> not solid
		var start := sec * SECTION_H * CHUNK_SIZE * CHUNK_SIZE
		var full := true
		for i in vol:
			if not BlockDB.is_solid(voxels[start + i]):
				full = false
				break
		if full:
			_section_full |= 1 << sec

func world_origin() -> Vector3:
	return Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
