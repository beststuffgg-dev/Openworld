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
var _nodes: Dictionary = {}           # Vector2i -> Array[MeshInstance3D] per section (detailed)
var _lod_nodes: Dictionary = {}       # Vector2i -> MeshInstance3D (single coarse mesh)
var _column_lod: Dictionary = {}      # Vector2i -> int step (0 = full detail, 2/4 = LOD)
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
		_reevaluate_lod(center)

	_collect_generated()
	_drain_mesh_queue()

## Distance band -> LOD step. Full detail near the player, coarser further out.
func _lod_for(dist: float) -> int:
	if dist <= GameState.view_distance_chunks:
		return 0
	var mid := GameState.view_distance_chunks + (GameState.lod_distance_chunks - GameState.view_distance_chunks) / 2.0
	return 2 if dist <= mid else 4

## Re-mesh columns whose LOD band changed as the player moved.
func _reevaluate_lod(center: Vector2i) -> void:
	for coord in _states.keys():
		var new_lod := _lod_for(Vector2(coord).distance_to(Vector2(center)))
		if int(_column_lod.get(coord, 0)) != new_lod:
			_column_lod[coord] = new_lod
			if _states[coord] == State.READY:
				_states[coord] = State.GENERATED
				if not _mesh_queue.has(coord):
					_mesh_queue.append(coord)

# ---------------------------------------------------------------------------
# Streaming
# ---------------------------------------------------------------------------

func _update_requested(center: Vector2i) -> void:
	# Load out to the LOD radius; nearer rings render at full detail, further ones
	# as coarse LOD columns so the view (and tall mountains) reach much farther.
	var r := GameState.lod_distance_chunks
	var wanted: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			wanted.append(center + Vector2i(dx, dz))
	wanted.sort_custom(func(a, b): return a.distance_squared_to(center) < b.distance_squared_to(center))
	for coord in wanted:
		if not _states.has(coord):
			_column_lod[coord] = _lod_for(Vector2(coord).distance_to(Vector2(center)))
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
		budget -= 1
		# Note: neighbours are NOT re-culled here. A chunk meshed before a
		# neighbour existed keeps a few border faces that later become hidden
		# inside the (solid) neighbour — invisible waste, but re-culling every
		# neighbour column per new chunk was a big streaming cost. Removing it is
		# the biggest streaming-throughput win.

## Meshes a column at its current LOD (detailed per-section, or coarse) and marks
## it READY.
func _build_chunk_node(coord: Vector2i) -> void:
	var step := int(_column_lod.get(coord, 0))
	if step == 0:
		_free_lod_node(coord)  # in case it was previously an LOD column
		if not _nodes.has(coord):
			var arr := []
			arr.resize(Chunk.SECTIONS)  # untyped Array fills with null
			_nodes[coord] = arr
		for sec in Chunk.SECTIONS:
			_build_section_node(coord, sec)
	else:
		_free_detailed_nodes(coord)  # in case it was previously detailed
		_build_lod_node(coord, step)
	_states[coord] = State.READY

## Builds the single coarse mesh for a distant (LOD) column. LOD columns skip
## collision — the player is never near enough to touch them before they upgrade
## to full detail.
func _build_lod_node(coord: Vector2i, step: int) -> void:
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null:
		return
	var mesh := ChunkMesher.build_column_lod(chunk, _sample_block, step)
	var mi: MeshInstance3D = _lod_nodes.get(coord)
	if mesh == null:
		_free_lod_node(coord)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.scale = Vector3.ONE * Chunk.VOXEL_SCALE
		mi.position = chunk.world_origin() * Chunk.VOXEL_SCALE
		add_child(mi)
		_lod_nodes[coord] = mi
	mi.mesh = mesh

func _free_lod_node(coord: Vector2i) -> void:
	if _lod_nodes.has(coord):
		_lod_nodes[coord].queue_free()
		_lod_nodes.erase(coord)

func _free_detailed_nodes(coord: Vector2i) -> void:
	if _nodes.has(coord):
		for mi in _nodes[coord]:
			if mi:
				mi.queue_free()
		_nodes.erase(coord)

## Builds (or clears) the MeshInstance for one vertical section of a column.
func _build_section_node(coord: Vector2i, sec: int) -> void:
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null or not _nodes.has(coord):
		return
	var nodes: Array = _nodes[coord]
	var mi: MeshInstance3D = nodes[sec]

	# Skip empty sections, and solid sections that are fully buried.
	var mesh: ArrayMesh = null
	if chunk.section_has_content(sec) and not _section_buried(coord, chunk, sec):
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

## True when section `sec` is fully solid and so are all six neighbouring
## sections — it has no visible faces, so meshing it is pure waste. Below the
## world floor counts as solid (we never render the underside of the world); a
## not-yet-loaded horizontal neighbour counts as NOT solid (mesh to be safe, then
## re-cull once it loads). Conservative: a wrong "not buried" only costs a mesh.
func _section_buried(coord: Vector2i, chunk: Chunk, sec: int) -> bool:
	if not chunk.section_full_solid(sec):
		return false
	var below := true if sec == 0 else chunk.section_full_solid(sec - 1)
	var above := false if sec == Chunk.SECTIONS - 1 else chunk.section_full_solid(sec + 1)
	if not (below and above):
		return false
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Chunk = _chunks.get(coord + off)
		if nb == null or not nb.section_full_solid(sec):
			return false
	return true

func _unload_far(center: Vector2i) -> void:
	var r := GameState.lod_distance_chunks + 2
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
	_free_lod_node(coord)
	_column_lod.erase(coord)
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

## Writes an arbitrary list of voxels (Array of Vector3i) to `id`, remeshing each
## affected section once. Used by the shape builder. `exclude` is an optional
## voxel-space AABB left untouched (e.g. the player). Returns voxels changed.
func stamp_voxels(voxels: Array, id: int, exclude := AABB()) -> int:
	var changed := 0
	var has_exclude := exclude.size != Vector3.ZERO
	var cols := {}
	var min_y := CHUNK_HEIGHT
	var max_y := 0
	for v in voxels:
		if v.y < 0 or v.y >= CHUNK_HEIGHT:
			continue
		if has_exclude and exclude.has_point(Vector3(v)):
			continue
		var coord := _voxel_to_chunk(v.x, v.z)
		var chunk: Chunk = _chunks.get(coord)
		if chunk == null:
			continue
		chunk.set_local(v.x - coord.x * CHUNK_SIZE, v.y, v.z - coord.y * CHUNK_SIZE, id)
		cols[coord] = true
		min_y = mini(min_y, v.y)
		max_y = maxi(max_y, v.y)
		changed += 1
	if changed == 0:
		return 0
	var sec_lo := clampi((min_y - 1) / Chunk.SECTION_H, 0, Chunk.SECTIONS - 1)
	var sec_hi := clampi((max_y + 1) / Chunk.SECTION_H, 0, Chunk.SECTIONS - 1)
	var to_remesh := {}
	for coord in cols:
		to_remesh[coord] = true
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			to_remesh[coord + off] = true
	for coord in to_remesh:
		for sec in range(sec_lo, sec_hi + 1):
			_remesh_section(coord, sec)
	return changed

## Rebuilds every section of a READY column (used when a new neighbour appears).
func _remesh_now(coord: Vector2i) -> void:
	if _states.get(coord) != State.READY:
		return
	_build_chunk_node(coord)

## Rebuilds a single section of a READY column. For a coarse LOD column (edits
## there are rare — it's far away) the whole column is rebuilt instead.
func _remesh_section(coord: Vector2i, sec: int) -> void:
	if sec < 0 or sec >= Chunk.SECTIONS:
		return
	if _states.get(coord) != State.READY:
		return
	if int(_column_lod.get(coord, 0)) != 0:
		_build_chunk_node(coord)
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
