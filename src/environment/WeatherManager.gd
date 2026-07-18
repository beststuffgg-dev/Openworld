class_name WeatherManager
extends Node3D
## Drives evolving weather: clear, cloudy, rain, storm and snow.
##
## Picks a new weather state every so often, biased by the current season (snow
## in winter, storms in summer, …), then blends fog, sunlight and precipitation
## toward that state so transitions are smooth. Rain and snow are GPU particle
## systems that follow the player; storms add lightning flashes. Snow-vs-rain and
## storm frequency come from the season, tying this system to SeasonManager.
##
## Gameplay effects (crop growth, river levels, temperature) are later roadmap
## items; this delivers the atmosphere and the state machine they hook into.

enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW }

@export var min_duration: float = 25.0
@export var max_duration: float = 60.0
@export var transition_time: float = 6.0

var _env: Environment
var _cycle: DayNightCycle
var _player: Node3D
var _seasons: SeasonManager

var _current: int = Weather.CLEAR
var _timer: float = 15.0
var _blend: float = 1.0           # 0..1 progress into the current state
# Blend endpoints as Vector2(fog_density, sunlight_scale).
var _from := Vector2(0.003, 1.0)
var _to := Vector2(0.003, 1.0)

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _flash: ColorRect
var _flash_alpha: float = 0.0
var _lightning_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# Per-season weather weights for [clear, cloudy, rain, storm, snow].
const SEASON_WEATHER := {
	SeasonManager.Season.SPRING: [4, 3, 4, 1, 0],
	SeasonManager.Season.SUMMER: [5, 2, 2, 2, 0],
	SeasonManager.Season.AUTUMN: [3, 4, 3, 1, 1],
	SeasonManager.Season.WINTER: [2, 3, 0, 0, 5],
}

func setup(env: Environment, cycle: DayNightCycle, player: Node3D, seasons: SeasonManager) -> void:
	_env = env
	_cycle = cycle
	_player = player
	_seasons = seasons
	_rng.randomize()
	_build_particles()
	_build_flash()
	_apply_immediate(Weather.CLEAR)

func _process(delta: float) -> void:
	if _rain == null:
		return  # not set up yet
	_timer -= delta
	if _timer <= 0.0:
		_choose_next()

	# Blend fog/light from the previous state toward the target.
	_blend = minf(1.0, _blend + delta / transition_time)
	if _env:
		_env.fog_density = lerpf(_from.x, _to.x, _blend)
	if _cycle:
		_cycle.light_scale = lerpf(_from.y, _to.y, _blend)

	if is_instance_valid(_player):
		var overhead := _player.global_position + Vector3(0, 16, 0)
		_rain.global_position = overhead
		_snow.global_position = overhead

	_update_lightning(delta)

func weather_name() -> String:
	return ["Clear", "Cloudy", "Rain", "Storm", "Snow"][_current]

func is_precipitating() -> bool:
	return _current == Weather.RAIN or _current == Weather.STORM or _current == Weather.SNOW

# --- State machine ---------------------------------------------------------

func _choose_next() -> void:
	_timer = _rng.randf_range(min_duration, max_duration)
	var weights: Array = SEASON_WEATHER[_seasons.current] if _seasons else [4, 3, 3, 1, 0]
	var next := _weighted_pick(weights)
	if next == _current:
		return
	_from = _params(_current)
	_to = _params(next)
	_blend = 0.0
	_current = next
	_apply_precip(next)

func _weighted_pick(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += w
	if total <= 0:
		return Weather.CLEAR
	var roll := _rng.randi_range(1, total)
	var acc := 0
	for i in weights.size():
		acc += weights[i]
		if roll <= acc:
			return i
	return Weather.CLEAR

func _apply_immediate(w: int) -> void:
	_current = w
	_from = _params(w)
	_to = _params(w)
	_blend = 1.0
	if _env:
		_env.fog_density = _to.x
	if _cycle:
		_cycle.light_scale = _to.y
	_apply_precip(w)

func _apply_precip(w: int) -> void:
	_rain.emitting = (w == Weather.RAIN or w == Weather.STORM)
	_snow.emitting = (w == Weather.SNOW)

## Target as Vector2(fog_density, sunlight_scale) for each weather state.
func _params(w: int) -> Vector2:
	match w:
		Weather.CLOUDY: return Vector2(0.006, 0.75)
		Weather.RAIN: return Vector2(0.013, 0.55)
		Weather.STORM: return Vector2(0.020, 0.40)
		Weather.SNOW: return Vector2(0.011, 0.70)
		_: return Vector2(0.003, 1.0)  # CLEAR

# --- Lightning -------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(0.0, _flash_alpha - delta * 3.5)
		_flash.color.a = _flash_alpha
	if _current == Weather.STORM:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = _rng.randf_range(4.0, 12.0)
			_flash_alpha = 0.6
			_flash.color.a = _flash_alpha

# --- Node construction -----------------------------------------------------

func _build_particles() -> void:
	_rain = _make_precip(Vector2(0.03, 0.5), Color(0.7, 0.8, 1.0, 0.6), 700, 30.0, 14.0)
	_snow = _make_precip(Vector2(0.09, 0.09), Color(1, 1, 1, 0.9), 500, 3.0, 1.5)
	add_child(_rain)
	add_child(_snow)

func _make_precip(quad_size: Vector2, color: Color, amount: int, gravity: float, speed: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-24, -40, -24), Vector3(48, 48, 48))
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.gravity = Vector3(0, -gravity, 0)
	pm.initial_velocity_min = speed * 0.7
	pm.initial_velocity_max = speed
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = quad_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	p.draw_pass_1 = quad
	return p

func _build_flash() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
