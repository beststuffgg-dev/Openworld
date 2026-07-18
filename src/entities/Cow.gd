class_name Cow
extends Animal
## Large, passive grazer. Wanders calmly and ignores the player.

func _configure() -> void:
	move_speed = 1.4
	run_speed = 3.5
	flee_radius = 0.0        # passive: does not flee
	aggro_radius = 0.0       # passive: does not charge
	jump_strength = 4.5
	max_health = 15
	col_height = 1.0
	col_radius = 0.45

func _build_visual() -> void:
	var brown := Color(0.45, 0.30, 0.18)
	var white := Color(0.90, 0.88, 0.84)
	var pink := Color(0.80, 0.55, 0.55)
	# Body with a white patch (forward is -Z).
	_add_box(Vector3(0.70, 0.70, 1.10), Vector3(0, 0.90, 0.0), brown)
	_add_box(Vector3(0.72, 0.34, 0.50), Vector3(0, 1.02, 0.12), white)  # patch
	# Head and snout.
	_add_box(Vector3(0.40, 0.40, 0.40), Vector3(0, 1.00, -0.72), brown)
	_add_box(Vector3(0.30, 0.24, 0.16), Vector3(0, 0.90, -0.92), pink)
	# Legs.
	_add_box(Vector3(0.16, 0.60, 0.16), Vector3(-0.24, 0.30, -0.38), brown)
	_add_box(Vector3(0.16, 0.60, 0.16), Vector3(0.24, 0.30, -0.38), brown)
	_add_box(Vector3(0.16, 0.60, 0.16), Vector3(-0.24, 0.30, 0.40), brown)
	_add_box(Vector3(0.16, 0.60, 0.16), Vector3(0.24, 0.30, 0.40), brown)
	# Tail.
	_add_box(Vector3(0.06, 0.50, 0.06), Vector3(0, 0.95, 0.58), brown)
