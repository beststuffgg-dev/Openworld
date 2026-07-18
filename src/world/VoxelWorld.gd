class_name VoxelWorld
extends Node3D
## Streams voxel chunks around a target, generating and meshing them on demand.
##
## Pipeline per chunk:
##   1. REQUESTED  – queued because it entered the view radius.
##   2. GENERATING – voxel data is being filled on a WorkerThreadPool thread.
##   3. GENERATED  – data ready, waiting for a mesh-build slot.
##   4. READY      – MeshInstance3D + static collision are in the scene tree.
##
## Terrain generation runs off the main thread (it never touches the scene tree);
## mesh building runs on the main thread but is rate-limited to a few chunks per
## frame so streaming never stalls the game. Chunks outside the radius are freed.

const CHUNK_SIZE := Chunk.CHUNK_SIZE
const CHUNK_HEIGHT := Chunk.CHUNK_HEIGHT

enum State { REQUESTED, GENERATING, GENERATED, READY }

var _generator: TerrainGenerator
var _chunks: Dictionary = {}          # Vector2i -> Chunk
var _states: Dictionary = {}          # Vector2i -> State
var _tasks: Dictionary = {}           # Vector2i -> WorkerThreadPool task id
var _nodes: Dictionary = {}           # Vector2i -> MeshInstance3D
var _mesh_queue: Array[Vector2i] = [] # chunks with data ready to mesh

var _last_center := Vector2i(999999, 999999)
var _track_target: Node3D

func _ready() -> void:
	_generator = TerrainGenerator.new(GameState.world_seed)
	set_physics_process(true)

func set_track_target(target: Node3D) -> void:
	_track_target = target

func _physics_process(_delta: float) -> void:
	if _track_target == null:
		return
	var center := _world_to_chunk(_track_target.global_position)
	if center != _last_center:
		_last_center = center
		_update_requested(center)
		_unload_far(center)

	_collect_generated()
	_drain_mesh_queue()

# ---------------------------------------------------------------------------
# Streaming
# ---------------------------------------------------------------------------

func _update_requested(center: Vector2i) -> void:
	var r := GameState.view_distance_chunks
	# Request nearest chunks first so the world fills outward from the player.
	var wanted: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			wanted.append(center + Vector2i(dx, dz))
	wanted.sort_custom(func(a, b): return a.distance_squared_to(center) < b.distance_squared_to(center))
	for coord in wanted:
		if not _states.has(coord):
			_request_chunk(coord)

func _request_chunk(coord: Vector2i) -> void:
	var chunk := Chunk.new(coord.x, coord.y)
	_chunks[coord] = chunk
	_states[coord] = State.GENERATING
	var task_id := WorkerThreadPool.add_task(func(): _generator.generate_chunk(chunk))
	_tasks[coord] = task_id

func _collect_generated() -> void:
	if _tasks.is_empty():
		return
	var done: Array[Vector2i] = []
	for coord in _tasks:
		var task_id: int = _tasks[coord]
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			done.append(coord)
	for coord in done:
		_tasks.erase(coord)
		if _states.get(coord) == State.GENERATING:  # may have been unloaded
			_states[coord] = State.GENERATED
			_mesh_queue.append(coord)

func _drain_mesh_queue() -> void:
	var budget := GameState.max_meshes_per_frame
	while budget > 0 and not _mesh_queue.is_empty():
		var coord: Vector2i = _mesh_queue.pop_front()
		if _states.get(coord) != State.GENERATED:
			continue
		_build_chunk_node(coord)
		# The neighbours were meshed while this chunk was still absent, so their
		# seam faces need re-culling now that this chunk's data exists.
		_remesh_ready_neighbors(coord)
		budget -= 1

func _remesh_ready_neighbors(coord: Vector2i) -> void:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_remesh_now(coord + offset)

## Builds all vertical section meshes for a column and marks it READY.
func _build_chunk_node(coord: Vector2i) -> void:
	if not _nodes.has(coord):
		var arr := []
		arr.resize(Chunk.SECTIONS)  # untyped Array fills with null
		_nodes[coord] = arr
	for sec in Chunk.SECTIONS:
		_build_section_node(coord, sec)
	_states[coord] = State.READY

## Builds (or clears) the MeshInstance for one vertical section of a column.
func _build_section_node(coord: Vector2i, sec: int) -> void:
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null or not _nodes.has(coord):
		return
	var nodes: Array = _nodes[coord]
	var mi: MeshInstance3D = nodes[sec]

	# Skip sections that never had any block written.
	var mesh: ArrayMesh = null
	if chunk.section_has_content(sec):
		var y_lo := sec * Chunk.SECTION_H
		mesh = ChunkMesher.build_section(chunk, _sample_block, y_lo, y_lo + Chunk.SECTION_H)

	if mesh == null:
		if mi:
			mi.queue_free()
			nodes[sec] = null
		return

	if mi == null:
		mi = MeshInstance3D.new()
		# Mesh is built in voxel units; scale the node so a voxel is VOXEL_SCALE
		# metres. Uniform scale keeps the trimesh collision correct.
		mi.scale = Vector3.ONE * Chunk.VOXEL_SCALE
		mi.position = chunk.world_origin() * Chunk.VOXEL_SCALE
		add_child(mi)
		nodes[sec] = mi
	mi.mesh = mesh

	# Rebuild static collision from the mesh.
	for child in mi.get_children():
		child.queue_free()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	mi.add_child(body)

func _unload_far(center: Vector2i) -> void:
	var r := GameState.view_distance_chunks + 2
	var to_remove: Array[Vector2i] = []
	for coord in _states.keys():
		if coord.distance_to(center) > r:
			to_remove.append(coord)
	for coord in to_remove:
		_free_chunk(coord)

func _free_chunk(coord: Vector2i) -> void:
	if _tasks.has(coord):
		# Let the background task finish before freeing so it can't touch a
		# chunk that's about to disappear mid-flight.
		WorkerThreadPool.wait_for_task_completion(_tasks[coord])
		_tasks.erase(coord)
	if _nodes.has(coord):
		for mi in _nodes[coord]:
			if mi:
				mi.queue_free()
		_nodes.erase(coord)
	_chunks.erase(coord)
	_states.erase(coord)
	_mesh_queue.erase(coord)

# ---------------------------------------------------------------------------
# Block access / editing
# ---------------------------------------------------------------------------

## Reads a block at world coordinates. Out-of-range vertical is treated as air.
## Used both by the mesher (across chunk borders) and by gameplay.
func _sample_block(gx: int, gy: int, gz: int) -> int:
	if gy < 0 or gy >= CHUNK_HEIGHT:
		return BlockDB.Type.AIR
	var coord := _voxel_to_chunk(gx, gz)
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null:
		return BlockDB.Type.AIR
	var lx := gx - coord.x * CHUNK_SIZE
	var lz := gz - coord.y * CHUNK_SIZE
	return chunk.get_local(lx, gy, lz)

func get_block_world(pos: Vector3i) -> int:
	return _sample_block(pos.x, pos.y, pos.z)

## Places or removes a block and remeshes only the affected section(s).
func set_block_world(pos: Vector3i, id: int) -> bool:
	if pos.y < 0 or pos.y >= CHUNK_HEIGHT:
		return false
	var coord := _voxel_to_chunk(pos.x, pos.z)
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null:
		return false
	var lx := pos.x - coord.x * CHUNK_SIZE
	var lz := pos.z - coord.y * CHUNK_SIZE
	chunk.set_local(lx, pos.y, lz, id)

	@warning_ignore("integer_division")
	var sec := pos.y / Chunk.SECTION_H
	_remesh_section(coord, sec)
	# Edits on a vertical section boundary touch the neighbouring section too.
	if pos.y % Chunk.SECTION_H == 0:
		_remesh_section(coord, sec - 1)
	elif pos.y % Chunk.SECTION_H == Chunk.SECTION_H - 1:
		_remesh_section(coord, sec + 1)
	# Edits on a horizontal chunk border re-cull the neighbour column's section.
	if lx == 0:
		_remesh_section(coord + Vector2i(-1, 0), sec)
	elif lx == CHUNK_SIZE - 1:
		_remesh_section(coord + Vector2i(1, 0), sec)
	if lz == 0:
		_remesh_section(coord + Vector2i(0, -1), sec)
	elif lz == CHUNK_SIZE - 1:
		_remesh_section(coord + Vector2i(0, 1), sec)
	return true

## Sets every voxel in the inclusive box [minv, maxv] to `id`, remeshing each
## affected chunk exactly once (a naive per-block loop would remesh thousands of
## times). `exclude` is an optional voxel-space AABB left untouched — used so a
## bulk placement doesn't bury the player. Returns the number of voxels changed.
func set_blocks_bulk(minv: Vector3i, maxv: Vector3i, id: int, exclude := AABB()) -> int:
	var changed := 0
	var affected := {}
	var has_exclude := exclude.size != Vector3.ZERO
	for y in range(maxi(minv.y, 0), mini(maxv.y, CHUNK_HEIGHT - 1) + 1):
		for z in range(minv.z, maxv.z + 1):
			for x in range(minv.x, maxv.x + 1):
				if has_exclude and exclude.has_point(Vector3(x, y, z)):
					continue
				var coord := _voxel_to_chunk(x, z)
				var chunk: Chunk = _chunks.get(coord)
				if chunk == null:
					continue
				chunk.set_local(x - coord.x * CHUNK_SIZE, y, z - coord.y * CHUNK_SIZE, id)
				affected[coord] = true
				changed += 1
	# Remesh only the affected sections of each touched column and its
	# neighbours (for seam culling), each section at most once.
	var sec_lo := clampi((minv.y - 1) / Chunk.SECTION_H, 0, Chunk.SECTIONS - 1)
	var sec_hi := clampi((maxv.y + 1) / Chunk.SECTION_H, 0, Chunk.SECTIONS - 1)
	var cols := {}
	for coord in affected:
		cols[coord] = true
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			cols[coord + off] = true
	for coord in cols:
		for sec in range(sec_lo, sec_hi + 1):
			_remesh_section(coord, sec)
	return changed

## Rebuilds every section of a READY column (used when a new neighbour appears).
func _remesh_now(coord: Vector2i) -> void:
	if _states.get(coord) != State.READY:
		return
	_build_chunk_node(coord)

## Rebuilds a single section of a READY column.
func _remesh_section(coord: Vector2i, sec: int) -> void:
	if sec < 0 or sec >= Chunk.SECTIONS:
		return
	if _states.get(coord) != State.READY:
		return
	_build_section_node(coord, sec)

func is_ready_at(pos: Vector3) -> bool:
	return _states.get(_world_to_chunk(pos)) == State.READY

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Chunk coordinate from a world-space (metre) position.
func _world_to_chunk(p: Vector3) -> Vector2i:
	var span := CHUNK_SIZE * Chunk.VOXEL_SCALE
	return Vector2i(floori(p.x / span), floori(p.z / span))

## Chunk coordinate from integer voxel coordinates.
func _voxel_to_chunk(vx: int, vz: int) -> Vector2i:
	return Vector2i(floori(vx / float(CHUNK_SIZE)), floori(vz / float(CHUNK_SIZE)))
