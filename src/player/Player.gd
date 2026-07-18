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

var _spawn_point := Vector3.ZERO
var _respawning := false
var _touch_move := Vector2.ZERO   # set by on-screen joystick
var _jump_queued := false         # set by on-screen jump button

signal selection_changed(block_id: int)
signal brush_changed(size: int)
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
			_cycle_selection(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_selection(-1)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_use_primary()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
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
