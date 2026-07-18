extends Control
## In-game pixel-art texture editor.
##
## Lets the player paint a 16x16 texture for any block and save it. Saved
## textures go to user://textures/blocks/<name>.png and are picked up by the
## runtime atlas (see src/world/TextureAtlas.gd), so painted blocks show their
## art in the world. Open it from the game with F1; "Back to Game" returns.
##
## Built entirely in code so it needs only a one-node scene.

const TILE := 16
const CANVAS_PX := 512

var _image: Image
var _canvas: PixelCanvas
var _color: Color = Color(0.6, 0.4, 0.25)
var _erasing := false
var _current_id: int = BlockDB.Type.STONE
var _block_ids: Array[int] = []
var _status: Label
var _picker: ColorPickerButton
var _eraser: CheckButton

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_load_block(_current_id)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Texture Editor  —  paint a block, Save, then Back to Game"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)

	main.add_child(_build_block_list())
	main.add_child(_build_canvas_panel())
	main.add_child(_build_tools())

	_status = Label.new()
	_status.text = ""
	root.add_child(_status)

func _build_block_list() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(180, 0)
	var label := Label.new()
	label.text = "Block"
	panel.add_child(label)

	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(180, 400)
	# Every opaque block is texturable (skip air and water).
	for id in BlockDB.count():
		if id == BlockDB.Type.AIR or BlockDB.is_transparent(id):
			continue
		list.add_item(BlockDB.get_name(id))
		_block_ids.append(id)
	list.item_selected.connect(func(index): _load_block(_block_ids[index]))
	panel.add_child(list)
	list.select(0)
	if _block_ids.size() > 0:
		_current_id = _block_ids[0]
	return panel

func _build_canvas_panel() -> Control:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = PixelCanvas.new()
	_canvas.on_paint = Callable(self, "_paint_cell")
	center.add_child(_canvas)
	return center

func _build_tools() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.add_theme_constant_override("separation", 6)

	var col_label := Label.new()
	col_label.text = "Colour"
	panel.add_child(col_label)

	_picker = ColorPickerButton.new()
	_picker.custom_minimum_size = Vector2(0, 36)
	_picker.color = _color
	_picker.color_changed.connect(_on_picker_changed)
	panel.add_child(_picker)

	# Quick palette.
	var palette := GridContainer.new()
	palette.columns = 4
	for c in [
		Color(0.50, 0.50, 0.53), Color(0.45, 0.31, 0.19), Color(0.36, 0.58, 0.27),
		Color(0.83, 0.77, 0.55), Color(0.92, 0.94, 0.97), Color(0.36, 0.25, 0.15),
		Color(0.24, 0.45, 0.20), Color(0.1, 0.1, 0.12), Color(0.9, 0.85, 0.3),
		Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(1, 1, 1),
	]:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(40, 28)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		swatch.add_theme_stylebox_override("normal", sb)
		swatch.add_theme_stylebox_override("hover", sb)
		swatch.add_theme_stylebox_override("pressed", sb)
		swatch.pressed.connect(_pick_color.bind(c))
		palette.add_child(swatch)
	panel.add_child(palette)

	_eraser = CheckButton.new()
	_eraser.text = "Eraser (transparent)"
	_eraser.toggled.connect(_on_eraser_toggled)
	panel.add_child(_eraser)

	panel.add_child(_button("Fill with colour", _fill_with_color))
	panel.add_child(_button("Clear (transparent)", _clear_canvas))
	panel.add_child(_button("Reset to block colour", _reset_to_block_color))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(spacer)

	panel.add_child(_button("Save texture", _save))
	panel.add_child(_button("Back to Game", func(): get_tree().change_scene_to_file("res://scenes/Main.tscn")))
	return panel

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	return b

func _load_block(id: int, force_color: bool = false) -> void:
	_current_id = id
	if force_color:
		_image = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		_image.fill(BlockDB.get_color(id))
	else:
		_image = Textures.load_block_image(id)
	_canvas.setup(_image, TILE, CANVAS_PX)
	if _status:
		_status.text = "Editing: %s" % BlockDB.get_name(id)

func _paint_cell(x: int, y: int) -> void:
	_image.set_pixel(x, y, Color(0, 0, 0, 0) if _erasing else _color)

func _on_picker_changed(c: Color) -> void:
	_color = c
	_set_erasing(false)

func _pick_color(c: Color) -> void:
	_color = c
	_set_erasing(false)
	if _picker:
		_picker.color = c

func _on_eraser_toggled(on: bool) -> void:
	_erasing = on

func _set_erasing(on: bool) -> void:
	_erasing = on
	if _eraser:
		_eraser.button_pressed = on

func _fill_with_color() -> void:
	_image.fill(_color)
	_canvas.queue_redraw()

func _clear_canvas() -> void:
	_image.fill(Color(0, 0, 0, 0))
	_canvas.queue_redraw()

func _reset_to_block_color() -> void:
	_load_block(_current_id, true)

func _save() -> void:
	Textures.ensure_user_dir()
	var path := Textures.user_texture_path(BlockDB.get_name(_current_id))
	var err := _image.save_png(path)
	if err == OK:
		Textures.rebuild()
		_status.text = "Saved to %s  —  it now shows in the world." % path
	else:
		_status.text = "Save failed (error %d)." % err

## Inner canvas: draws the working image as big pixels with a grid and paints on
## click/drag. Shares the Image with the editor, so edits are reflected live.
class PixelCanvas extends Control:
	var img: Image
	var tiles: int = 16
	var cell: float = 32.0
	var on_paint: Callable

	func setup(image: Image, tiles_count: int, size_px: int) -> void:
		img = image
		tiles = tiles_count
		cell = float(size_px) / tiles_count
		custom_minimum_size = Vector2(size_px, size_px)
		queue_redraw()

	func _draw() -> void:
		if img == null:
			return
		# Checkerboard so transparency is visible.
		for y in tiles:
			for x in tiles:
				var checker := Color(0.30, 0.30, 0.33) if (x + y) % 2 == 0 else Color(0.22, 0.22, 0.25)
				draw_rect(Rect2(x * cell, y * cell, cell, cell), checker)
				var px := img.get_pixel(x, y)
				if px.a > 0.0:
					draw_rect(Rect2(x * cell, y * cell, cell, cell), px)
		var grid := Color(0, 0, 0, 0.25)
		for i in range(tiles + 1):
			draw_line(Vector2(i * cell, 0), Vector2(i * cell, tiles * cell), grid)
			draw_line(Vector2(0, i * cell), Vector2(tiles * cell, i * cell), grid)

	func _gui_input(event: InputEvent) -> void:
		var pos := Vector2.INF
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pos = event.position
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pos = event.position
		if pos == Vector2.INF or not on_paint.is_valid():
			return
		var cx := int(pos.x / cell)
		var cy := int(pos.y / cell)
		if cx >= 0 and cx < tiles and cy >= 0 and cy < tiles:
			on_paint.call(cx, cy)
			queue_redraw()
