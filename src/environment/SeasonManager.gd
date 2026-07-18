class_name SeasonManager
extends Node
## Advances the world through Spring → Summer → Autumn → Winter and recolours
## foliage live.
##
## Seasons are driven by elapsed in-game days (from DayNightCycle), so they run
## on the same clock as day/night. Each season pushes a tint colour + strength
## onto the shared terrain shader material, so the whole world's grass and leaves
## recolour instantly without re-meshing a single chunk. Other systems (mob
## spawning/migration) listen to `season_changed`.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

## In-game days each season lasts. Short by default so the effect is visible.
@export var days_per_season: float = 2.0

var _cycle: DayNightCycle
var current: int = Season.SPRING

signal season_changed(season: int)

# Multiplicative foliage tint + strength per season. 1,1,1 leaves colour as-is.
const TINTS := {
	Season.SPRING: {"tint": Color(0.75, 1.15, 0.60), "strength": 0.65},
	Season.SUMMER: {"tint": Color(0.85, 1.05, 0.70), "strength": 0.45},
	Season.AUTUMN: {"tint": Color(1.60, 0.90, 0.35), "strength": 0.85},
	Season.WINTER: {"tint": Color(1.40, 1.50, 1.70), "strength": 0.80},
}

# Direction animals drift when a season turns (on the XZ plane).
const MIGRATION_DIRS := {
	Season.SPRING: Vector3(0, 0, -1),
	Season.SUMMER: Vector3(1, 0, 0),
	Season.AUTUMN: Vector3(0, 0, 1),
	Season.WINTER: Vector3(-1, 0, 0),
}

func setup(cycle: DayNightCycle) -> void:
	_cycle = cycle
	_apply(current)

func _process(_delta: float) -> void:
	if _cycle == null:
		return
	var idx := int(floor(_cycle.elapsed_days / days_per_season)) % 4
	if idx != current:
		current = idx
		_apply(idx)
		season_changed.emit(idx)

func _apply(season: int) -> void:
	var data: Dictionary = TINTS[season]
	var mat := ChunkMesher.get_opaque_material()
	mat.set_shader_parameter("season_tint", data["tint"])
	mat.set_shader_parameter("season_strength", data["strength"])

func season_name(season: int = -1) -> String:
	var s := current if season < 0 else season
	return ["Spring", "Summer", "Autumn", "Winter"][s]

func migration_direction() -> Vector3:
	return MIGRATION_DIRS[current]
