class_name Chicken
extends Animal
## Small, skittish bird. Flees the player and darts around in short bursts.

func _configure() -> void:
	move_speed = 1.8
	run_speed = 5.5
	flee_radius = 6.0        # skittish
	jump_strength = 4.0
	max_health = 4
	col_height = 0.5
	col_radius = 0.2

func _build_visual() -> void:
	var white := Color(0.95, 0.95, 0.92)
	var orange := Color(0.95, 0.62, 0.15)
	var red := Color(0.85, 0.20, 0.18)
	# Body + tail (forward is -Z).
	_add_box(Vector3(0.30, 0.30, 0.42), Vector3(0, 0.30, 0.02), white)
	_add_box(Vector3(0.14, 0.22, 0.12), Vector3(0, 0.42, 0.24), white)  # tail
	# Head, beak and comb.
	_add_box(Vector3(0.22, 0.22, 0.22), Vector3(0, 0.50, -0.22), white)
	_add_box(Vector3(0.08, 0.06, 0.10), Vector3(0, 0.48, -0.36), orange)  # beak
	_add_box(Vector3(0.05, 0.10, 0.14), Vector3(0, 0.62, -0.16), red)     # comb
	# Legs.
	_add_box(Vector3(0.05, 0.26, 0.05), Vector3(-0.08, 0.13, 0.02), orange)
	_add_box(Vector3(0.05, 0.26, 0.05), Vector3(0.08, 0.13, 0.02), orange)
