class_name DayNightCycle
extends Node
## Drives a directional "sun" light and the world environment through a 24h cycle.
##
## Rotates the sun across the sky, fades its colour/energy through sunrise, day,
## golden hour and night, and shifts ambient + fog to match. This is the hook the
## spec's weather, seasons and volumetric sky systems extend later
## (docs/ROADMAP.md phase 4); for now it delivers a readable, moving sky.

## Full day length in real seconds.
@export var day_length: float = 600.0
## Start time of day in hours (0..24). 8.0 == morning.
@export var start_hour: float = 8.0

var _sun: DirectionalLight3D
var _env: Environment
var time_of_day: float  # hours, 0..24
## Total in-game days elapsed since start (fractional). Seasons key off this.
var elapsed_days: float = 0.0
## Multiplier the weather system applies to sunlight (1 = clear, < 1 = overcast).
var light_scale: float = 1.0

signal hour_changed(hour: float)

func setup(sun: DirectionalLight3D, env: Environment) -> void:
	_sun = sun
	_env = env
	time_of_day = start_hour

func _process(delta: float) -> void:
	if _sun == null:
		return
	var day_delta := delta / day_length
	elapsed_days += day_delta
	time_of_day = fmod(time_of_day + day_delta * 24.0, 24.0)
	_apply()
	hour_changed.emit(time_of_day)

func _apply() -> void:
	# Sun angle: -90° at midnight, +90° at noon (rotating around X).
	var frac := time_of_day / 24.0
	var sun_angle := (frac * 360.0) - 90.0
	_sun.rotation_degrees = Vector3(sun_angle, -60.0, 0.0)

	# Daylight factor: 1 at noon, 0 at/after dusk.
	var elevation := sin(deg_to_rad(sun_angle))
	var day_amount := clampf(elevation, 0.0, 1.0)

	# Warm the light near the horizon (sunrise / golden hour).
	var horizon := 1.0 - clampf(abs(elevation) * 2.5, 0.0, 1.0)
	var day_color := Color(1.0, 0.98, 0.92)
	var dusk_color := Color(1.0, 0.55, 0.30)
	_sun.light_color = dusk_color.lerp(day_color, 1.0 - horizon)
	_sun.light_energy = lerpf(0.05, 1.2, day_amount) * light_scale
	_sun.visible = elevation > -0.15

	if _env:
		_env.ambient_light_energy = lerpf(0.15, 0.6, day_amount) * lerpf(0.6, 1.0, light_scale)
		var sky_day := Color(0.42, 0.62, 0.86)
		var sky_night := Color(0.03, 0.04, 0.09)
		var sky := sky_night.lerp(sky_day, day_amount)
		_env.ambient_light_color = sky
		if _env.fog_enabled:
			_env.fog_light_color = sky
