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
const CHUNK_HEIGHT := 96
const VOLUME := CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT

## Chunk grid coordinates (world position = coord * CHUNK_SIZE).
var cx: int
var cz: int
var voxels: PackedByteArray

## Set true once the mesh/collision for this chunk is dirty and needs rebuilding.
var dirty: bool = false

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

func world_origin() -> Vector3:
	return Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
