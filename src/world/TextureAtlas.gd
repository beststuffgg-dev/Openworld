extends Node
## Runtime block texture atlas (autoload `Textures`).
##
## Packs a 16x16 tile per block into one atlas texture. A block's tile is loaded
## from a PNG if the player has painted one, otherwise it is filled with the
## block's flat colour — so the world ALWAYS renders, with or without custom art.
##
## Custom textures live in `user://textures/blocks/<name>.png` (what the in-game
## Texture Editor writes); optional shipped defaults may live in
## `res://textures/blocks/`. `rebuild()` re-reads them and updates the shared
## terrain material's atlas uniform, so freshly painted textures appear without
## re-meshing (the UV layout per block is stable).

const TILE := 16
const COLS := 8
const USER_DIR := "user://textures/blocks"
const RES_DIR := "res://textures/blocks"

var atlas_texture: ImageTexture
var _rects: Dictionary = {}   # block_id -> Rect2 in UV space
var _width := TILE
var _height := TILE

func _ready() -> void:
	rebuild()

## UV rectangle (inset to avoid tile bleeding) for a block's atlas tile.
func uv_rect(block_id: int) -> Rect2:
	return _rects.get(block_id, Rect2(0, 0, 1, 1))

func rebuild() -> void:
	var n := BlockDB.count()
	var rows := int(ceil(float(n) / COLS))
	_width = COLS * TILE
	_height = rows * TILE
	var img := Image.create(_width, _height, false, Image.FORMAT_RGBA8)
	_rects.clear()

	for id in n:
		var col := id % COLS
		@warning_ignore("integer_division")
		var row := id / COLS
		var ox := col * TILE
		var oy := row * TILE
		var tile := _load_tile_image(BlockDB.get_name(id).to_lower())
		if tile == null:
			img.fill_rect(Rect2i(ox, oy, TILE, TILE), BlockDB.get_color(id))
		else:
			img.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(ox, oy))
		# Inset by half a texel so nearest-filtered sampling never bleeds into
		# the neighbouring tile.
		var hu := 0.5 / _width
		var hv := 0.5 / _height
		_rects[id] = Rect2(
			float(ox) / _width + hu,
			float(oy) / _height + hv,
			float(TILE) / _width - 2.0 * hu,
			float(TILE) / _height - 2.0 * hv)

	atlas_texture = ImageTexture.create_from_image(img)
	ChunkMesher.get_opaque_material().set_shader_parameter("atlas", atlas_texture)

# Returns a 16x16 RGBA8 image for a block's texture, or null if none exists.
func _load_tile_image(name: String) -> Image:
	var user_path := "%s/%s.png" % [USER_DIR, name]
	if FileAccess.file_exists(user_path):
		var im := Image.new()
		if im.load(user_path) == OK:
			return _normalize(im)
	var res_path := "%s/%s.png" % [RES_DIR, name]
	if ResourceLoader.exists(res_path):
		var tex := load(res_path) as Texture2D
		if tex:
			var im2 := tex.get_image()
			if im2:
				return _normalize(im2)
	return null

func _normalize(im: Image) -> Image:
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != TILE or im.get_height() != TILE:
		im.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	return im

## Current image for a block for editing: its texture if present, else a solid
## tile of the block's colour. Always a 16x16 RGBA8 image.
func load_block_image(block_id: int) -> Image:
	var tile := _load_tile_image(BlockDB.get_name(block_id).to_lower())
	if tile == null:
		tile = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		tile.fill(BlockDB.get_color(block_id))
	return tile

static func user_texture_path(name: String) -> String:
	return "%s/%s.png" % [USER_DIR, name.to_lower()]

static func ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
