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

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _camera: Camera3D
var _ray: RayCast3D
var _pitch: float = 0.0

var world: VoxelWorld
var selected_index: int = 0

signal selection_changed(block_id: int)
signal spawn_ready

func _ready() -> void:
	_build_body()
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
	_camera.add_child(_ray)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.5, 1.5)
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_selection(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_selection(-1)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_break_block()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_place_block()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
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
	for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
		if BlockDB.is_solid(world.get_block_world(Vector3i(int(global_position.x), y, int(global_position.z)))):
			global_position.y = y + 2.0
			spawn_ready.emit()
			return true
	return false

func selected_block() -> int:
	return BlockDB.placeable[selected_index]

func _cycle_selection(dir: int) -> void:
	var count := BlockDB.placeable.size()
	selected_index = (selected_index + dir + count) % count
	selection_changed.emit(selected_block())

func _break_block() -> void:
	if not _ray.is_colliding():
		return
	var point := _ray.get_collision_point()
	var normal := _ray.get_collision_normal()
	# Step just inside the hit face to land on the block that was struck.
	var target := _voxel_from_hit(point, -normal)
	world.set_block_world(target, BlockDB.Type.AIR)

func _place_block() -> void:
	if not _ray.is_colliding():
		return
	var point := _ray.get_collision_point()
	var normal := _ray.get_collision_normal()
	var target := _voxel_from_hit(point, normal)
	# Don't place a block inside the player's own capsule.
	var feet := Vector3i(floori(global_position.x), floori(global_position.y), floori(global_position.z))
	if target == feet or target == feet + Vector3i(0, 1, 0):
		return
	world.set_block_world(target, selected_block())

func _voxel_from_hit(point: Vector3, dir: Vector3) -> Vector3i:
	var p := point + dir * 0.5
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))
