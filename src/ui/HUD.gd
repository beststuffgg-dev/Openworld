class_name HUD
extends CanvasLayer
## Minimal heads-up display: crosshair, selected block, clock, season, weather and
## survival bars (health / hunger / stamina).
##
## Deliberately lightweight — the spec's full responsive/touch/controller UI is a
## later phase (docs/ROADMAP.md phase 6). This exists so the vertical slice is
## legible.

const BAR_WIDTH := 200.0
const BAR_HEIGHT := 16.0

var _crosshair: Label
var _info: Label
var _selected: Label

var _player: Player
var _cycle: DayNightCycle
var _seasons: SeasonManager
var _weather: WeatherManager

# Stat bar fills, updated each frame from the player's stats.
var _health_fill: ColorRect
var _hunger_fill: ColorRect
var _stamina_fill: ColorRect

func setup(player: Player, cycle: DayNightCycle, seasons: SeasonManager = null, weather: WeatherManager = null) -> void:
	_player = player
	_cycle = cycle
	_seasons = seasons
	_weather = weather
	_player.selection_changed.connect(_on_selection_changed)

func _ready() -> void:
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 24)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_crosshair)

	_info = _make_label(Vector2(12, 10))
	_selected = _make_label(Vector2(12, 34))
	_build_stat_bars()

func _make_label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l

func _build_stat_bars() -> void:
	var container := VBoxContainer.new()
	container.position = Vector2(12, 64)
	container.add_theme_constant_override("separation", 4)
	add_child(container)
	_health_fill = _make_bar(container, "Health", Color(0.85, 0.24, 0.22))
	_hunger_fill = _make_bar(container, "Hunger", Color(0.85, 0.55, 0.20))
	_stamina_fill = _make_bar(container, "Stamina", Color(0.35, 0.75, 0.40))

func _make_bar(parent: Node, label: String, color: Color) -> ColorRect:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(64, 0)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 3)
	row.add_child(name_label)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	row.add_child(bg)

	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill.position = Vector2.ZERO
	bg.add_child(fill)
	return fill

func _process(_delta: float) -> void:
	if _player == null:
		return
	var p := _player.global_position
	var clock := ""
	if _cycle:
		var h := int(_cycle.time_of_day)
		var m := int((_cycle.time_of_day - h) * 60.0)
		clock = "  %02d:%02d" % [h, m]
	var season := ""
	if _seasons:
		season = "  %s" % _seasons.season_name()
	var weather := ""
	if _weather:
		weather = "  %s" % _weather.weather_name()
	_info.text = "XYZ  %d, %d, %d%s%s%s" % [int(p.x), int(p.y), int(p.z), clock, season, weather]
	if _selected.text == "":
		_on_selection_changed(_player.selected_block())

	if _player.stats:
		_health_fill.size.x = BAR_WIDTH * _player.stats.health_ratio()
		_hunger_fill.size.x = BAR_WIDTH * _player.stats.hunger_ratio()
		_stamina_fill.size.x = BAR_WIDTH * _player.stats.stamina_ratio()

func _on_selection_changed(block_id: int) -> void:
	_selected.text = "Block:  %s  (scroll to change)" % BlockDB.get_name(block_id)
