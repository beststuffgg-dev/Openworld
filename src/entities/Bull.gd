class_name Bull
extends Animal
## Territorial bovine. Passive at range, but charges the player who comes close.

func _configure() -> void:
	move_speed = 1.6
	run_speed = 6.5
	flee_radius = 0.0        # holds its ground
	aggro_radius = 7.0       # charges when the player is near
	jump_strength = 5.0
	max_health = 25
	col_height = 1.1
	col_radius = 0.5

func _build_visual() -> void:
	var dark := Color(0.24, 0.17, 0.12)
	var horn := Color(0.90, 0.88, 0.80)
	var snout := Color(0.55, 0.40, 0.40)
	# Bulkier body (forward is -Z).
	_add_box(Vector3(0.82, 0.82, 1.30), Vector3(0, 1.00, 0.0), dark)
	# Head, snout and horns.
	_add_box(Vector3(0.46, 0.46, 0.46), Vector3(0, 1.05, -0.82), dark)
	_add_box(Vector3(0.32, 0.26, 0.16), Vector3(0, 0.95, -1.06), snout)
	_add_box(Vector3(0.30, 0.10, 0.10), Vector3(-0.24, 1.24, -0.90), horn)
	_add_box(Vector3(0.30, 0.10, 0.10), Vector3(0.24, 1.24, -0.90), horn)
	# Legs.
	_add_box(Vector3(0.18, 0.66, 0.18), Vector3(-0.28, 0.33, -0.46), dark)
	_add_box(Vector3(0.18, 0.66, 0.18), Vector3(0.28, 0.33, -0.46), dark)
	_add_box(Vector3(0.18, 0.66, 0.18), Vector3(-0.28, 0.33, 0.48), dark)
	_add_box(Vector3(0.18, 0.66, 0.18), Vector3(0.28, 0.33, 0.48), dark)
	# Tail.
	_add_box(Vector3(0.07, 0.55, 0.07), Vector3(0, 1.00, 0.66), dark)
