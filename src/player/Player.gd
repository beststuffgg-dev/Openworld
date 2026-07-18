class_name Player
extends CharacterBody3D
## First-person player controller with voxel interaction.
##
## Builds its own camera, collision and interaction ray in code so no packed
## scene is needed. Handles walking/sprinting/jumping, mouse look, and
## breaking/placing blocks against the VoxelWorld. Touch and controller input
## are roadmap items (docs/ROADMAP.md phase 6) — the input actions are already
## defined so those bindings drop in without code changes.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_VELOCITY := 6.0
const MOUSE_SENSITIVITY := 0.0025
const REACH := 6.0
const ATTACK_DAMAGE := 6.0
const MAX_BRUSH := 32

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _camera: Camera3D
var _ray: RayCast3D
var _pitch: float = 0.0

var world: VoxelWorld
var selected_index: int = 0
var stats: PlayerStats
## Edge length of the cube placed/destroyed per click (1 = single block).
var brush_size: int = 1

# Shape build tool. When shape_active, left-click walks the flow (pick A, pick B,
# then place); the mouse wheel adjusts the extent while adjusting; right-click
# cancels. See ShapeBuilder.
enum ShapeState { AWAIT_A, AWAIT_B, ADJUST }
var shape_active: bool = false
var shape_type: int = ShapeBuilder.Shape.CUBE
var shape_flat: bool = false
var _shape_state: int = ShapeState.AWAIT_A
var _shape_a := Vector3i.ZERO
var _shape_b := Vector3i.ZERO
var _shape_extent: int = 1
var _marker_a: MeshInstance3D
var _marker_b: MeshInstance3D
var _shape_preview: MeshInstance3D

var _spawn_point := Vector3.ZERO
var _respawning := false
var _touch_move := Vector2.ZERO   # set by on-screen joystick
var _jump_queued := false         # set by on-screen jump button

signal selection_changed(block_id: int)
signal brush_changed(size: int)
signal shape_changed
signal spawn_ready

func _ready() -> void:
	_build_body()
	stats = PlayerStats.new()
	stats.name = "PlayerStats"
	add_child(stats)
	stats.died.connect(_on_died)
	# Capture the mouse for look controls on desktop; touch devices use the
	# on-screen controls instead.
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_body() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.65, 0)
	_camera.fov = 75.0
	_camera.far = 1000.0
	add_child(_camera)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collide_with_bodies = true
	_ray.add_exception(self)  # never hit our own capsule
	_camera.add_child(_ray)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative, MOUSE_SENSITIVITY)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll(-1)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if shape_active:
					_shape_advance()
				else:
					_use_primary()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if shape_active:
					_shape_cancel()
				else:
					_place_block()
	elif event.is_action_pressed("brush_increase"):
		set_brush_size(brush_size + 1)
	elif event.is_action_pressed("brush_decrease"):
		set_brush_size(brush_size - 1)

func _physics_process(delta: float) -> void:
	if _respawning:
		# Wait for the spawn area to stream back in, then drop onto it.
		if world and world.is_ready_at(global_position) and _drop_to_ground():
			_respawning = false
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	if (Input.is_action_just_pressed("jump") or _jump_queued) and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_queued = false

	# Combine keyboard and on-screen joystick movement.
	var input := (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + _touch_move).limit_length(1.0)
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	# Sprinting is gated by stamina; the stats node drains/recovers it.
	var want_sprint := Input.is_action_pressed("sprint") and dir != Vector3.ZERO and stats.can_sprint()
	stats.sprinting = want_sprint
	var speed := SPRINT_SPEED if want_sprint else WALK_SPEED

	if dir:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

## Drops the player onto solid ground once the spawn chunk has streamed in.
## Returns true when spawning succeeded so the caller can stop polling.
func try_ground_spawn() -> bool:
	if world == null or not world.is_ready_at(global_position):
		return false
	if _drop_to_ground():
		_spawn_point = global_position
		spawn_ready.emit()
		return true
	return false

func _drop_to_ground() -> bool:
	var v := Chunk.world_to_voxel(global_position)
	for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
		if BlockDB.is_solid(world.get_block_world(Vector3i(v.x, y, v.z))):
			# Stand on top of the block: its top surface is (y + 1) * VOXEL_SCALE.
			global_position.y = (y + 1) * Chunk.VOXEL_SCALE + 0.2
			velocity = Vector3.ZERO
			return true
	return false

## Called externally (bull charge, etc.) to hurt the player.
func receive_attack(amount: float) -> void:
	if stats:
		stats.damage(amount)

func _on_died() -> void:
	# Respawn back at the original spawn column with fresh stats.
	stats.reset()
	global_position = Vector3(_spawn_point.x, Chunk.CHUNK_HEIGHT * Chunk.VOXEL_SCALE, _spawn_point.z)
	velocity = Vector3.ZERO
	_respawning = true

func selected_block() -> int:
	return BlockDB.placeable[selected_index]

func _cycle_selection(dir: int) -> void:
	var count := BlockDB.placeable.size()
	selected_index = (selected_index + dir + count) % count
	selection_changed.emit(selected_block())

func set_brush_size(n: int) -> void:
	brush_size = clampi(n, 1, MAX_BRUSH)
	brush_changed.emit(brush_size)

# The mouse wheel changes the shape extent while adjusting, else the held block.
func _scroll(dir: int) -> void:
	if shape_active and _shape_state == ShapeState.ADJUST:
		_shape_extent = maxi(1, _shape_extent + dir)
		_update_preview()
		shape_changed.emit()
	else:
		_cycle_selection(dir)

# --- Shape build tool ------------------------------------------------------

## `idx` 0 = off; 1.. selects ShapeBuilder.Shape (idx - 1).
func set_shape(idx: int) -> void:
	if idx <= 0:
		shape_active = false
	else:
		shape_active = true
		shape_type = idx - 1
	_shape_reset()
	shape_changed.emit()

func set_shape_flat(flat: bool) -> void:
	shape_flat = flat
	_update_preview()
	shape_changed.emit()

func shape_status_text() -> String:
	if not shape_active:
		return ""
	var name := ShapeBuilder.shape_name(shape_type)
	var dim := "2D" if shape_flat else "3D"
	match _shape_state:
		ShapeState.AWAIT_A:
			return "%s %s — click point A" % [dim, name]
		ShapeState.AWAIT_B:
			return "%s %s — click point B" % [dim, name]
		_:
			return "%s %s — scroll size (%d), click to place, right-click cancels" % [dim, name, _shape_extent]

func _shape_advance() -> void:
	if not _ray.is_colliding():
		return
	var v := _voxel_from_hit(_ray.get_collision_point(), _ray.get_collision_normal())
	match _shape_state:
		ShapeState.AWAIT_A:
			_shape_a = v
			_shape_state = ShapeState.AWAIT_B
		ShapeState.AWAIT_B:
			_shape_b = v
			_shape_extent = 1
			_shape_state = ShapeState.ADJUST
		ShapeState.ADJUST:
			_place_shape()
			return
	_update_markers()
	_update_preview()
	shape_changed.emit()

func _place_shape() -> void:
	var voxels := ShapeBuilder.generate(shape_type, shape_flat, _shape_a, _shape_b, _shape_extent)
	world.stamp_voxels(voxels, selected_block(), _player_voxel_aabb())
	_shape_reset()
	shape_changed.emit()

func _shape_cancel() -> void:
	_shape_reset()
	shape_changed.emit()

func _shape_reset() -> void:
	_shape_state = ShapeState.AWAIT_A
	if _marker_a:
		_marker_a.visible = false
	if _marker_b:
		_marker_b.visible = false
	if _shape_preview:
		_shape_preview.visible = false

func _ensure_shape_nodes() -> void:
	if _marker_a != null or world == null:
		return
	_marker_a = _make_ghost(Color(0.3, 1.0, 0.4, 0.6))
	_marker_b = _make_ghost(Color(1.0, 0.6, 0.2, 0.6))
	_shape_preview = _make_ghost(Color(0.5, 0.7, 1.0, 0.25))
	world.add_child(_marker_a)
	world.add_child(_marker_b)
	world.add_child(_shape_preview)

func _make_ghost(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.visible = false
	return mi

func _update_markers() -> void:
	_ensure_shape_nodes()
	if _shape_state >= ShapeState.AWAIT_B:
		_place_ghost(_marker_a, _shape_a, _shape_a)
		_marker_a.visible = true
	if _shape_state == ShapeState.ADJUST:
		_place_ghost(_marker_b, _shape_b, _shape_b)
		_marker_b.visible = true

func _update_preview() -> void:
	_ensure_shape_nodes()
	if not shape_active or _shape_state != ShapeState.ADJUST:
		if _shape_preview:
			_shape_preview.visible = false
		return
	var box := _shape_bbox()
	_place_ghost(_shape_preview, box[0], box[1])
	_shape_preview.visible = true

## Positions a ghost box to cover the inclusive voxel range [lo, hi].
func _place_ghost(mi: MeshInstance3D, lo: Vector3i, hi: Vector3i) -> void:
	var size := (Vector3(hi - lo) + Vector3.ONE) * Chunk.VOXEL_SCALE
	var center := (Vector3(lo) + Vector3(hi) + Vector3.ONE) * 0.5 * Chunk.VOXEL_SCALE
	(mi.mesh as BoxMesh).size = size
	mi.position = center

## Analytic bounding box of the current shape (cheap; avoids generating voxels).
func _shape_bbox() -> Array:
	var a := _shape_a
	var b := _shape_b
	var e := _shape_extent
	match shape_type:
		ShapeBuilder.Shape.SPHERE:
			var r := int(round(Vector2(b.x - a.x, b.z - a.z).length())) if shape_flat else int(round(Vector3(b - a).length()))
			var ry := 0 if shape_flat else r
			return [a - Vector3i(r, ry, r), a + Vector3i(r, ry, r)]
		ShapeBuilder.Shape.CYLINDER:
			var r := int(round(Vector2(b.x - a.x, b.z - a.z).length()))
			var h := 1 if shape_flat else maxi(absi(b.y - a.y), maxi(e, 1))
			return [a - Vector3i(r, 0, r), a + Vector3i(r, h - 1, r)]
		ShapeBuilder.Shape.SLOPE:
			var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)) - Vector3i(e, 0, e)
			var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z)) + Vector3i(e, 0, e)
			return [lo, hi]
		_:
			var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
			var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
			if shape_flat:
				lo.y = a.y
				hi.y = a.y
			return [lo, hi]

## Rotate the view. Shared by mouse look and the on-screen touch look area.
func apply_look(rel: Vector2, sensitivity: float) -> void:
	rotate_y(-rel.x * sensitivity)
	_pitch = clampf(_pitch - rel.y * sensitivity, -1.5, 1.5)
	_camera.rotation.x = _pitch

# --- On-screen touch control hooks -----------------------------------------

func set_move_input(v: Vector2) -> void:
	_touch_move = v

func queue_jump() -> void:
	_jump_queued = true

func touch_primary() -> void:
	_use_primary()

func touch_secondary() -> void:
	_place_block()

## Left click: attack an animal if the ray hits one, otherwise mine an NxNxN box.
func _use_primary() -> void:
	if not _ray.is_colliding():
		return
	var collider := _ray.get_collider()
	if collider is Animal:
		var animal := collider as Animal
		var food := animal.food_value
		if animal.hurt(ATTACK_DAMAGE):
			# Killing an animal feeds the player (stand-in for a food item until
			# the inventory system lands).
			stats.eat(food)
		return
	var target := _voxel_from_hit(_ray.get_collision_point(), -_ray.get_collision_normal())
	var box := _brush_box(target)
	world.set_blocks_bulk(box[0], box[1], BlockDB.Type.AIR)

## Right click: place an NxNxN box of the selected block, skipping the player.
func _place_block() -> void:
	if not _ray.is_colliding():
		return
	var target := _voxel_from_hit(_ray.get_collision_point(), _ray.get_collision_normal())
	var box := _brush_box(target)
	world.set_blocks_bulk(box[0], box[1], selected_block(), _player_voxel_aabb())

## Returns [min_voxel, max_voxel] for a brush of `brush_size` centred on target.
func _brush_box(target: Vector3i) -> Array:
	var r := (brush_size - 1) / 2
	var extra := (brush_size - 1) % 2  # extend +1 side for even sizes
	var lo := target - Vector3i(r, r, r)
	var hi := target + Vector3i(r + extra, r + extra, r + extra)
	return [lo, hi]

## The voxels the player's capsule occupies, as a voxel-space AABB.
func _player_voxel_aabb() -> AABB:
	var half := Vector3(0.35, 0, 0.35)
	var lo := Chunk.world_to_voxel(global_position - half)
	var hi := Chunk.world_to_voxel(global_position + Vector3(0.35, 1.8, 0.35))
	return AABB(Vector3(lo), Vector3(hi - lo) + Vector3.ONE)

func _voxel_from_hit(point: Vector3, dir: Vector3) -> Vector3i:
	# Step half a voxel along the hit direction, then snap to the voxel grid.
	return Chunk.world_to_voxel(point + dir * (0.5 * Chunk.VOXEL_SCALE))
