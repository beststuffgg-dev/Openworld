class_name PlayerStats
extends Node
## Survival stats for the player: health, hunger and stamina.
##
## Ticks hunger down over time; when hunger bottoms out, health drains (you
## starve). When you're fed, health slowly regenerates. Stamina drains while
## sprinting and recovers while you aren't. Combat and eating drive health and
## hunger from the outside. This is the seed of the wider survival system in the
## roadmap (thirst, temperature, disease, food spoilage).

signal died

@export var max_health: float = 100.0
@export var max_hunger: float = 100.0
@export var max_stamina: float = 100.0

@export var hunger_decay: float = 0.6          # per second
@export var starve_damage: float = 2.0         # per second at 0 hunger
@export var health_regen: float = 1.5          # per second when well fed
@export var regen_hunger_threshold: float = 60.0
@export var stamina_drain: float = 22.0        # per second sprinting
@export var stamina_regen: float = 16.0        # per second recovering

var health: float
var hunger: float
var stamina: float
var sprinting: bool = false

var _dead: bool = false

func _ready() -> void:
	reset()

func reset() -> void:
	health = max_health
	hunger = max_hunger
	stamina = max_stamina
	sprinting = false
	_dead = false

func _process(delta: float) -> void:
	if _dead:
		return

	hunger = maxf(0.0, hunger - hunger_decay * delta)
	if hunger <= 0.0:
		_change_health(-starve_damage * delta)
	elif health < max_health and hunger > regen_hunger_threshold:
		_change_health(health_regen * delta)

	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)

## True while the player has enough stamina to keep sprinting.
func can_sprint() -> bool:
	return stamina > 1.0

func eat(amount: float) -> void:
	hunger = minf(max_hunger, hunger + amount)

func heal(amount: float) -> void:
	_change_health(amount)

func damage(amount: float) -> void:
	_change_health(-amount)

func _change_health(delta: float) -> void:
	health = clampf(health + delta, 0.0, max_health)
	if health <= 0.0 and not _dead:
		_dead = true
		died.emit()

func health_ratio() -> float:
	return health / max_health

func hunger_ratio() -> float:
	return hunger / max_hunger

func stamina_ratio() -> float:
	return stamina / max_stamina
