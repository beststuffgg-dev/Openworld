class_name Animal
extends CharacterBody3D
## Base class for wildlife (chickens, cows, bulls, …).
##
## Handles gravity, ground movement, a small behaviour state machine and seasonal
## migration. Visuals are built from primitive boxes in `_configure()` overrides
## so no external model assets are needed. Combat, breeding and taming are later
## roadmap phases; the hooks (health, `hurt()`) are stubbed here so they slot in.

enum State { IDLE, WANDER, FLEE, CHARGE, MIGRATE }

# Tuned by subclasses in _configure().
var move_speed: float = 2.0
var run_speed: float = 5.0
var flee_radius: float = 0.0     # > 0 makes the animal skittish
var aggro_radius: float = 0.0    # > 0 makes the animal charge the player
var jump_strength: float = 4.5
var max_health: int = 10
var col_height: float = 0.8
var col_radius: float = 0.35
## Hunger restored to the player when this animal is killed (a stand-in for a
## dropped food item until the inventory system exists).
var food_value: float = 20.0
## Damage dealt to the player on a landed charge (aggressive animals only).
var charge_damage: float = 0.0

var health: int
var player: Node3D

var _state: int = State.IDLE
var _state_timer: float = 0.0
var _heading := Vector3.ZERO
var _migrate_target := Vector3.ZERO
var _forced_flee: float = 0.0    # seconds of forced fleeing after being hurt
var _attack_cd: float = 0.0      # cooldown between charge hits
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("animals")
	_rng.randomize()
	_configure()
	health = max_health
	_build_collision()
	_build_visual()
	_pick_idle_or_wander()

## Subclasses set stats here (speeds, radii, collision size).
func _configure() -> void:
	pass

## Subclasses build their body from primitive meshes here.
func _build_visual() -> void:
	pass

func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = col_height
	capsule.radius = col_radius
	shape.shape = capsule
	shape.position.y = col_height * 0.5
	add_child(shape)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	_update_state(delta)
	_apply_movement(delta)
	move_and_slide()
	_face_travel(delta)
	_try_charge_hit(delta)

## Aggressive animals damage the player when a charge lands.
func _try_charge_hit(delta: float) -> void:
	if charge_damage <= 0.0 or not is_instance_valid(player):
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _state == State.CHARGE and _attack_cd <= 0.0:
		if global_position.distance_to(player.global_position) < 1.6:
			_attack_cd = 1.0
			if player.has_method("receive_attack"):
				player.receive_attack(charge_damage)

# --- Behaviour -------------------------------------------------------------

func _update_state(delta: float) -> void:
	_state_timer -= delta

	# A recently-hurt animal flees for a moment regardless of temperament.
	if _forced_flee > 0.0:
		_forced_flee -= delta
		_state = State.FLEE
		return

	var dist := INF
	if is_instance_valid(player):
		dist = global_position.distance_to(player.global_position)

	# Reactions to the player take priority over wandering/migrating.
	if aggro_radius > 0.0 and dist < aggro_radius:
		_state = State.CHARGE
		return
	if flee_radius > 0.0 and dist < flee_radius:
		_state = State.FLEE
		return
	# Player is no longer a factor — drop out of reactive states.
	if _state == State.CHARGE or _state == State.FLEE:
		_pick_idle_or_wander()
		return

	if _state == State.MIGRATE:
		var flat := Vector2(_migrate_target.x - global_position.x, _migrate_target.z - global_position.z)
		if _state_timer <= 0.0 or flat.length() < 2.0:
			_pick_idle_or_wander()
		return

	if _state_timer <= 0.0:
		_pick_idle_or_wander()

func _pick_idle_or_wander() -> void:
	if _rng.randf() < 0.35:
		_state = State.IDLE
		_state_timer = _rng.randf_range(1.5, 4.0)
	else:
		_state = State.WANDER
		var angle := _rng.randf() * TAU
		_heading = Vector3(cos(angle), 0, sin(angle))
		_state_timer = _rng.randf_range(2.0, 5.0)

func _apply_movement(_delta: float) -> void:
	var dir := Vector3.ZERO
	var speed := move_speed
	match _state:
		State.WANDER:
			dir = _heading
		State.MIGRATE:
			dir = (_migrate_target - global_position)
			dir.y = 0
			dir = dir.normalized()
			speed = move_speed * 1.15
		State.FLEE:
			if is_instance_valid(player):
				dir = global_position - player.global_position
				dir.y = 0
				dir = dir.normalized()
			speed = run_speed
		State.CHARGE:
			if is_instance_valid(player):
				dir = player.global_position - global_position
				dir.y = 0
				dir = dir.normalized()
			speed = run_speed
		State.IDLE:
			dir = Vector3.ZERO

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	# Hop up single-block steps and small obstacles instead of getting stuck.
	if is_on_floor() and is_on_wall() and dir != Vector3.ZERO:
		velocity.y = jump_strength

## Turn to face horizontal travel direction, smoothly.
func _face_travel(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length_squared() < 0.01:
		return
	var target_yaw := atan2(-velocity.x, -velocity.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0.0, 1.0))

# --- External hooks --------------------------------------------------------

## Sent by the SeasonManager (via the spawner) when a season turns.
func migrate(direction: Vector3, distance: float = 30.0) -> void:
	if _state == State.FLEE or _state == State.CHARGE:
		return
	_migrate_target = global_position + direction.normalized() * distance
	_state = State.MIGRATE
	_state_timer = _rng.randf_range(6.0, 12.0)

## Applies damage. Returns true if this killed the animal.
func hurt(amount: float) -> bool:
	health -= int(ceil(amount))
	if health <= 0:
		queue_free()
		return true
	# Aggressive animals retaliate; everyone else bolts for a few seconds.
	if aggro_radius > 0.0:
		_state = State.CHARGE
	else:
		_forced_flee = 3.0
	return false

# --- Visual helper ---------------------------------------------------------

## Adds a coloured box part to the body. Used by subclasses to assemble animals
## from primitives without any imported model.
func _add_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	return mi
