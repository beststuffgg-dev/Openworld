class_name HUD
extends CanvasLayer
## Minimal heads-up display: crosshair, selected block, clock and coordinates.
##
## Deliberately tiny — the spec's full responsive/touch/controller UI is a later
## phase (docs/ROADMAP.md phase 6). This exists so the vertical slice is legible.

var _crosshair: Label
var _info: Label
var _selected: Label

var _player: Player
var _cycle: DayNightCycle
var _seasons: SeasonManager

func setup(player: Player, cycle: DayNightCycle, seasons: SeasonManager = null) -> void:
	_player = player
	_cycle = cycle
	_seasons = seasons
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

func _make_label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l

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
	_info.text = "XYZ  %d, %d, %d%s%s" % [int(p.x), int(p.y), int(p.z), clock, season]
	if _selected.text == "":
		_on_selection_changed(_player.selected_block())

func _on_selection_changed(block_id: int) -> void:
	_selected.text = "Block:  %s  (scroll to change)" % BlockDB.get_name(block_id)
