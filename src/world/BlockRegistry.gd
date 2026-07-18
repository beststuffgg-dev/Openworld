extends Node
## Central registry of block types and their properties.
##
## Registered as the `BlockDB` autoload singleton. Every voxel in a chunk is a
## single byte that indexes into this registry. Keeping block data in one place
## (colour, solidity, transparency) makes it trivial to add new blocks later and
## to swap the current vertex-colour rendering for a texture atlas without
## touching the mesher or terrain generator.

## Block type identifiers. A voxel is stored as a byte, so ids must stay < 256.
enum Type {
	AIR = 0,
	STONE = 1,
	DIRT = 2,
	GRASS = 3,
	SAND = 4,
	WATER = 5,
	WOOD = 6,
	LEAVES = 7,
	SNOW = 8,
	GRAVEL = 9,
	CLAY = 10,
	PLANKS = 11,
}

## Per-block metadata. `solid` blocks collide and cull neighbouring faces.
## `transparent` blocks (air, water, leaves) do not cull faces behind them.
class BlockInfo:
	var id: int
	var name: String
	var color: Color
	var solid: bool
	var transparent: bool
	func _init(p_id: int, p_name: String, p_color: Color, p_solid: bool, p_transparent: bool) -> void:
		id = p_id
		name = p_name
		color = p_color
		solid = p_solid
		transparent = p_transparent

var _blocks: Array[BlockInfo] = []

## Blocks the player can select and place from the hotbar, in order.
var placeable: PackedInt32Array = PackedInt32Array([
	Type.STONE, Type.DIRT, Type.GRASS, Type.SAND, Type.WOOD,
	Type.PLANKS, Type.LEAVES, Type.SNOW, Type.GRAVEL,
])

func _ready() -> void:
	# Order must match the Type enum so an id can index directly into the array.
	_register(Type.AIR,    "Air",    Color(0, 0, 0, 0),            false, true)
	_register(Type.STONE,  "Stone",  Color(0.50, 0.50, 0.53),      true,  false)
	_register(Type.DIRT,   "Dirt",   Color(0.45, 0.31, 0.19),      true,  false)
	_register(Type.GRASS,  "Grass",  Color(0.36, 0.58, 0.27),      true,  false)
	_register(Type.SAND,   "Sand",   Color(0.83, 0.77, 0.55),      true,  false)
	_register(Type.WATER,  "Water",  Color(0.20, 0.40, 0.70, 0.6), true,  true)
	_register(Type.WOOD,   "Wood",   Color(0.36, 0.25, 0.15),      true,  false)
	# Leaves are opaque (fast-graphics style) so they cull cleanly and can take
	# the seasonal grass/leaf tint from the terrain shader.
	_register(Type.LEAVES, "Leaves", Color(0.24, 0.45, 0.20),      true,  false)
	_register(Type.SNOW,   "Snow",   Color(0.92, 0.94, 0.97),      true,  false)
	_register(Type.GRAVEL, "Gravel", Color(0.42, 0.40, 0.38),      true,  false)
	_register(Type.CLAY,   "Clay",   Color(0.58, 0.60, 0.63),      true,  false)
	_register(Type.PLANKS, "Planks", Color(0.62, 0.46, 0.28),      true,  false)

func _register(id: int, name: String, color: Color, solid: bool, transparent: bool) -> void:
	assert(id == _blocks.size(), "Block ids must be registered in enum order")
	_blocks.append(BlockInfo.new(id, name, color, solid, transparent))

func count() -> int:
	return _blocks.size()

func get_block(id: int) -> BlockInfo:
	if id < 0 or id >= _blocks.size():
		return _blocks[Type.AIR]
	return _blocks[id]

func is_solid(id: int) -> bool:
	return get_block(id).solid

func is_transparent(id: int) -> bool:
	return get_block(id).transparent

func get_color(id: int) -> Color:
	return get_block(id).color

func block_name(id: int) -> String:
	return get_block(id).name

## Blocks whose colour follows the season (grass & foliage). The terrain shader
## tints these via a per-vertex weight.
func is_tintable(id: int) -> bool:
	return id == Type.GRASS or id == Type.LEAVES
