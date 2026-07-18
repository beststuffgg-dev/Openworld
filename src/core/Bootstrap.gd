extends Node3D
## Assembles the playable vertical slice at runtime.
##
## Builds everything in code (environment, sun, voxel world, player, HUD) so the
## project needs only a one-node entry scene and stays diff-friendly. This is the
## composition root; as systems grow (weather, NPCs, quests) they get wired in
## here or moved into their own coordinators.

const SPAWN_XZ := Vector2(8, 8)

var _world: VoxelWorld
var _player: Player
var _cycle: DayNightCycle
var _spawned := false

func _ready() -> void:
	_setup_environment()
	_setup_world()
	_setup_player()
	_setup_ui()
	print("[Project Horizons] Vertical slice booted. Seed: %d" % GameState.world_seed)

func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.52, 0.82)
	sky_mat.sky_horizon_color = Color(0.70, 0.80, 0.90)
	sky_mat.ground_horizon_color = Color(0.70, 0.80, 0.90)
	sky_mat.ground_bottom_color = Color(0.40, 0.42, 0.40)
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.70, 0.80, 0.90)

	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	sun.rotation_degrees = Vector3(-50, -60, 0)
	add_child(sun)

	_cycle = DayNightCycle.new()
	add_child(_cycle)
	_cycle.setup(sun, env)

func _setup_world() -> void:
	_world = VoxelWorld.new()
	_world.name = "VoxelWorld"
	add_child(_world)

func _setup_player() -> void:
	_player = Player.new()
	_player.name = "Player"
	_player.world = _world
	# Start high; try_ground_spawn() drops us onto terrain once it streams in.
	_player.global_position = Vector3(SPAWN_XZ.x, Chunk.CHUNK_HEIGHT, SPAWN_XZ.y)
	add_child(_player)
	_world.set_track_target(_player)

func _setup_ui() -> void:
	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(_player, _cycle)

func _process(_delta: float) -> void:
	if not _spawned:
		_spawned = _player.try_ground_spawn()
