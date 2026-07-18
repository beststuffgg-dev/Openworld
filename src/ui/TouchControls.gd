class_name TouchControls
extends Control
## On-screen controls for touch devices (phones / tablets).
##
## Left thumb: a virtual movement joystick (appears where you press in the lower
## left). Right thumb: drag anywhere on the right to look. Action buttons handle
## jump, break, place and brush size, plus a gear that opens Settings. Enabled
## automatically when a touchscreen is detected (Bootstrap), and toggleable in
## Settings. This is a first-pass layout meant to be refined on-device.

const JOY_RADIUS := 110.0
const LOOK_SENS := 0.005

var _player: Player
var _settings: SettingsMenu
var _buttons: Array[Button] = []

var _joy_finger := -1
var _joy_home := Vector2.ZERO
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_active := false

var _look_finger := -1
var _look_last := Vector2.ZERO

func setup(player: Player) -> void:
	_player = player

func set_settings(settings: SettingsMenu) -> void:
	_settings = settings

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # let the buttons receive taps
	_build_buttons()
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()
	visibility_changed.connect(_on_visibility_changed)

func _build_buttons() -> void:
	_add_button("Jump", _player.queue_jump)
	_add_button("Break", _player.touch_primary)
	_add_button("Place", _player.touch_secondary)
	_add_button("Brush -", func(): _player.set_brush_size(_player.brush_size - 1))
	_add_button("Brush +", func(): _player.set_brush_size(_player.brush_size + 1))
	_add_button("=", _open_settings)  # gear / settings

func _open_settings() -> void:
	if _settings:
		_settings.open()

func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	add_child(b)
	_buttons.append(b)

func _layout() -> void:
	var s := size
	_joy_home = Vector2(150, s.y - 150)
	# _buttons order: Jump, Break, Place, Brush-, Brush+, Gear
	_place(_buttons[0], Vector2(s.x - 150, s.y - 150), Vector2(120, 120))  # Jump
	_place(_buttons[1], Vector2(s.x - 160, s.y - 290), Vector2(100, 100))  # Break
	_place(_buttons[2], Vector2(s.x - 290, s.y - 130), Vector2(100, 100))  # Place
	_place(_buttons[3], Vector2(s.x - 400, s.y - 90), Vector2(80, 70))     # Brush -
	_place(_buttons[4], Vector2(s.x - 400, s.y - 180), Vector2(80, 70))    # Brush +
	_place(_buttons[5], Vector2(s.x - 80, 30), Vector2(50, 50))            # Gear
	queue_redraw()

func _place(b: Button, pos: Vector2, sz: Vector2) -> void:
	b.position = pos
	b.size = sz

func _on_visibility_changed() -> void:
	if not visible:
		_joy_active = false
		_joy_finger = -1
		_look_finger = -1
		if _player:
			_player.set_move_input(Vector2.ZERO)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var p := event.position
		if _over_button(p):
			return  # the button itself handles it
		if _joy_finger == -1 and _in_left_zone(p):
			_joy_finger = event.index
			_joy_active = true
			_joy_center = p
			_joy_pos = p
			_update_move()
			queue_redraw()
		elif _look_finger == -1:
			_look_finger = event.index
			_look_last = p
	else:
		if event.index == _joy_finger:
			_joy_finger = -1
			_joy_active = false
			_player.set_move_input(Vector2.ZERO)
			queue_redraw()
		elif event.index == _look_finger:
			_look_finger = -1

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joy_finger:
		_joy_pos = event.position
		_update_move()
		queue_redraw()
	elif event.index == _look_finger:
		_player.apply_look(event.position - _look_last, LOOK_SENS)
		_look_last = event.position

func _update_move() -> void:
	var v := (_joy_pos - _joy_center) / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_player.set_move_input(v)

func _in_left_zone(p: Vector2) -> bool:
	return p.x < size.x * 0.45 and p.y > size.y * 0.35

func _over_button(p: Vector2) -> bool:
	for b in _buttons:
		if b.get_global_rect().has_point(p):
			return true
	return false

func _draw() -> void:
	# Joystick: faint home ring when idle, active ring + knob while dragging.
	var center := _joy_center if _joy_active else _joy_home
	draw_arc(center, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
	if _joy_active:
		var knob := _joy_pos
		if (_joy_pos - _joy_center).length() > JOY_RADIUS:
			knob = _joy_center + (_joy_pos - _joy_center).normalized() * JOY_RADIUS
		draw_circle(knob, 34, Color(1, 1, 1, 0.35))
