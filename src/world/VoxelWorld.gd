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

func _build_chunk_node(coord: Vector2i) -> void:
	var chunk: Chunk = _chunks[coord]
	var mesh := ChunkMesher.build(chunk, _sample_block)

	var existing: MeshInstance3D = _nodes.get(coord)
	if mesh == null:
		# Empty chunk (e.g. all air): drop any old node, mark ready.
		if existing:
			existing.queue_free()
			_nodes.erase(coord)
		_states[coord] = State.READY
		return

	var mi: MeshInstance3D = existing
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = chunk.world_origin()
		add_child(mi)
		_nodes[coord] = mi
	mi.mesh = mesh

	# Rebuild static collision from the mesh.
	for child in mi.get_children():
		child.queue_free()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	mi.add_child(body)

	_states[coord] = State.READY

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
		_nodes[coord].queue_free()
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
	var coord := _world_to_chunk(Vector3(gx, 0, gz))
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null:
		return BlockDB.Type.AIR
	var lx := gx - coord.x * CHUNK_SIZE
	var lz := gz - coord.y * CHUNK_SIZE
	return chunk.get_local(lx, gy, lz)

func get_block_world(pos: Vector3i) -> int:
	return _sample_block(pos.x, pos.y, pos.z)

## Places or removes a block and remeshes the affected chunk(s) immediately.
func set_block_world(pos: Vector3i, id: int) -> bool:
	if pos.y < 0 or pos.y >= CHUNK_HEIGHT:
		return false
	var coord := _world_to_chunk(Vector3(pos.x, 0, pos.z))
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null:
		return false
	var lx := pos.x - coord.x * CHUNK_SIZE
	var lz := pos.z - coord.y * CHUNK_SIZE
	chunk.set_local(lx, pos.y, lz, id)
	_remesh_now(coord)
	# If the edit was on a border, remesh the neighbour so its seam faces update.
	if lx == 0:
		_remesh_now(coord + Vector2i(-1, 0))
	elif lx == CHUNK_SIZE - 1:
		_remesh_now(coord + Vector2i(1, 0))
	if lz == 0:
		_remesh_now(coord + Vector2i(0, -1))
	elif lz == CHUNK_SIZE - 1:
		_remesh_now(coord + Vector2i(0, 1))
	return true

func _remesh_now(coord: Vector2i) -> void:
	if _states.get(coord) != State.READY:
		return
	_states[coord] = State.GENERATED
	_build_chunk_node(coord)

func is_ready_at(pos: Vector3) -> bool:
	return _states.get(_world_to_chunk(pos)) == State.READY

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _world_to_chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / float(CHUNK_SIZE)), floori(p.z / float(CHUNK_SIZE)))
