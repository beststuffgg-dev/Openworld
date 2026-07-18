class_name SettingsMenu
extends CanvasLayer
## Pause / settings overlay, opened with Escape.
##
## Houses things that don't deserve a global hotkey — the Texture Editor lives
## here now instead of on F1 — plus the brush-size control and a touch-controls
## toggle. Opening pauses the game and frees the mouse; closing resumes and
## recaptures it (unless on a touch device).

var _player: Player
var _touch: Node
var _is_touch := false

var _root: Control
var _brush_label: Label
var _brush_slider: HSlider
var _open := false

func setup(player: Player, touch: Node, is_touch: bool) -> void:
	_player = player
	_touch = touch
	_is_touch = is_touch
	if _player:
		_player.brush_changed.connect(_on_brush_changed)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the tree is paused
	layer = 20
	_build()
	_apply_open(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_apply_open(not _open)
		get_viewport().set_input_as_handled()

## Public so the touch UI's gear button can open settings.
func open() -> void:
	_apply_open(true)

func _apply_open(open: bool) -> void:
	_open = open
	_root.visible = open
	get_tree().paused = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _brush_slider:
			_brush_slider.value = _player.brush_size
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _is_touch else Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.process_mode = Node.PROCESS_MODE_ALWAYS  # buttons must work while paused
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# A CenterContainer keeps the panel truly centred (PRESET_CENTER on a
	# container mis-sizes it into the corner).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	_brush_label = Label.new()
	box.add_child(_brush_label)
	_brush_slider = HSlider.new()
	_brush_slider.min_value = 1
	_brush_slider.max_value = Player.MAX_BRUSH
	_brush_slider.step = 1
	_brush_slider.value = _player.brush_size if _player else 1
	_brush_slider.value_changed.connect(_on_slider_changed)
	box.add_child(_brush_slider)
	_on_brush_changed(_player.brush_size if _player else 1)

	# Build-shape tool.
	var shape_label := Label.new()
	shape_label.text = "Build shape"
	box.add_child(shape_label)
	var shape_pick := OptionButton.new()
	shape_pick.add_item("Off")  # index 0
	for i in ShapeBuilder.Shape.size():
		shape_pick.add_item(ShapeBuilder.shape_name(i))
	shape_pick.selected = (_player.shape_type + 1) if (_player and _player.shape_active) else 0
	shape_pick.item_selected.connect(func(idx): _player.set_shape(idx))
	box.add_child(shape_pick)
	var flat_toggle := CheckButton.new()
	flat_toggle.text = "Flat (2D)"
	flat_toggle.button_pressed = _player.shape_flat if _player else false
	flat_toggle.toggled.connect(func(on): _player.set_shape_flat(on))
	box.add_child(flat_toggle)

	box.add_child(_menu_button("Resume", func(): _apply_open(false)))
	box.add_child(_menu_button("Texture Editor", _open_texture_editor))

	if _is_touch and _touch:
		var touch_toggle := CheckButton.new()
		touch_toggle.text = "On-screen controls"
		touch_toggle.button_pressed = _touch.visible
		touch_toggle.toggled.connect(func(on): _touch.visible = on)
		box.add_child(touch_toggle)

	box.add_child(_menu_button("Quit", func(): get_tree().quit()))

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(cb)
	return b

func _open_texture_editor() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://tools/TextureEditor.tscn")

func _on_slider_changed(v: float) -> void:
	if _player:
		_player.set_brush_size(int(v))

func _on_brush_changed(size: int) -> void:
	if _brush_label:
		_brush_label.text = "Brush size:  %d × %d × %d" % [size, size, size]
	if _brush_slider and int(_brush_slider.value) != size:
		_brush_slider.value = size
