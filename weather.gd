extends Node3D

# =====================================================================================================
# WEATHER: clouds, wind, rain, hail, snow, fog, lightning, thunder, tornadoes, storm damage and erosion.
#
# HOW TO ADD IT: add a Node3D anywhere in your main scene (call it "Weather"), attach this script, run. Nothing else
# needs wiring: it finds the sky_cycle script, the sun and moon, the WorldEnvironment, the player, the terrain (the node
# with ground_chunks.gd), the tree script and the enemies by itself. It does not change any of your other scripts.
#
# TEST KEYS (turn off with debug_keys): F6 = next weather, F7 = lightning strike near you, F8 = spawn a tornado.
# Or call set_weather("storm") from anywhere. Names: clear, cloudy, fog, drizzle, rain, storm, hail, snow, blizzard,
# windstorm, tornado.
# =====================================================================================================

@export_group("General")
@export var weather_enabled := true
@export var auto_weather := true                    # the weather changes by itself (off = it stays on start_weather)
@export var patchy_weather := true                  # the world is mostly sunny, with patches of other weather you walk into and out of (off = one weather everywhere, changing over time)
@export_range(0.3, 0.95) var sunny_fraction := 0.64  # how much of the world is clear (0.64 = roughly two thirds sunny, a bit more with the cloudy patch edges). Lower = more weather patches
@export var patch_size := 650.0                     # roughly how wide a weather patch is, in metres (bigger = larger patches, further apart)
@export var patch_drift_speed := 1.5                # metres per second the patches slowly blow across the land (0 = they stay put)
@export var start_weather := "clear"
@export var min_duration := 120.0                   # each kind of weather lasts between these many seconds
@export var max_duration := 360.0
@export var transition_time := 30.0                 # seconds to fade from one weather to the next
@export_range(0.0, 3.0) var severity := 1.0         # how often the bad weather (storms, hail, tornadoes, blizzards) comes. 0 = never
@export var debug_keys := true
@export var sky_cycle: Node                         # found automatically (the node running your sky script)
@export var terrain: Node                           # found automatically (ground_chunks.gd)
@export var trees: Node                             # found automatically (sakura_trees.gd)
@export var player: Node3D                          # found automatically (group "player")

@export_group("Clouds")
@export var cloud_dome_enabled := true
@export var cloud_speed := 0.012                    # how fast clouds drift (scaled by the wind)
@export var cloud_scale := 1.0                      # bigger = larger cloud shapes
@export var storm_darkness := 0.85                  # how dark and grey storm skies and light get (0..1)
@export_range(0.0, 1.0) var sun_hidden_by_clouds := 0.3     # how much the thickest storm cloud fades your sun and moon sprites (0 = they are never faded, 1 = fully hidden)
@export_group("Sunshine and colour")
@export var sunshine_enabled := true                # the sun's light and its disc cut through light weather (only thick clouds and severe weather block it)
@export_range(0.0, 3.0) var sunshine_strength := 0.6   # how much stronger the sunlight gets when nothing is blocking it (0 = off, 1 = double)
@export_range(0.0, 2.0) var sun_disc_brightness := 1.0 # how bright your sun picture looks when it shines through (1 = unchanged)
@export_enum("auto", "always", "never") var own_sun_disc := "auto"   # draws a sun in the sky if your sky script has none ("auto" = only when its sun picture is missing, "always" = draw this one too, "never" = off)
@export var hide_light_discs := true                # stops every light from drawing its own disc in the sky (those show up as black blobs). Your sun and moon pictures are the only ones drawn.
@export_range(0.0, 1.0) var vibrance := 0.22        # makes the whole picture more colourful (0 = off). Eases off in severe weather.
@export_group("Weather look")
@export_range(0.0, 2.0) var extra_brightness := 0.12    # lifts the shadow-fill light in every weather (raise it if the world still feels dark, 0 = off)
@export_range(0.0, 1.0) var weather_dimming := 0.4   # how much the weather darkens the world overall (0 = weather never makes it darker, 1 = full storm gloom)
@export_range(0.0, 1.0) var overcast_fill := 0.3      # clouds scatter light: extra soft shadow-fill light when it is overcast, so the ground never goes black

@export_group("Wind")
@export var wind_yaw_degrees := 40.0                # the starting wind direction (it slowly drifts)
@export var wind_drift := 0.5                       # how much the wind direction wanders
@export var gust_strength := 0.45                   # 0 = steady wind, 1 = very gusty
@export var tree_sway_degrees := 7.0                # how far trees lean in a strong wind (0 = off)
@export var tree_sway_distance := 85.0              # only trees this close to you sway (it costs a little)
@export var petals_in_wind := true                  # blossoms and leaves blown through the air
@export var wind_pushes_creatures := 0.0            # metres per second of push at gale strength on you and the enemies (0 = none)

@export_group("Rain, hail, snow")
@export var precipitation_enabled := true
@export var rain_amount := 7000
@export var hail_amount := 700
@export var snow_amount := 4500
@export var rain_fog := true                        # rain and snow thin out the distance
@export var puddles := true                         # rain leaves shiny puddles that dry out afterwards
@export var puddle_distance := 55.0
@export var rain_splashes := true

@export_group("Lightning and thunder")
@export var lightning_enabled := true
@export var lightning_rate := 1.0                   # multiplies how often it strikes
@export var strike_min_distance := 50.0
@export var strike_max_distance := 550.0
@export var strike_near_player_chance := 0.06       # chance a strike lands close to you
@export var strike_hits_trees := true               # bolts look for the nearest tree and blast it
@export var cloud_height := 260.0
@export var thunder_volume_db := 0.0
@export var sound_enabled := true                   # rain, wind and thunder are generated by the script (no audio files needed)

@export_group("Tornado")
@export var tornadoes_enabled := true
@export var tornado_radius := 13.0                  # width of the funnel near the ground (metres)
@export var tornado_height := 150.0
@export var tornado_speed := 8.0                    # how fast it crosses the land
@export var tornado_player_bias := 0.35             # 0 = wanders anywhere, 1 = heads straight at you
@export var tornado_lifetime := 110.0               # seconds before it dies out
@export var tornado_pull_radius := 55.0             # how far out it drags creatures and trees in

@export_group("Damage")
@export var storm_damage_trees := true              # lightning, wind, tornadoes and soaked soil bring trees down (they stay down)
@export var tree_fall_wind_speed := 21.0            # winds over this start toppling trees
@export var tree_fall_rate := 0.0015                  # chance per second, per nearby tree, at full gale
@export var erosion_rate := 0.004                   # chance per second, per tree on a slope, when the soil is soaked (trees slide out and fall)
@export var lightning_damage := 120.0
@export var lightning_damage_radius := 9.0
@export var falling_tree_damage := 45.0
@export var hail_damage := 2.0                      # per second to anything caught outside in a hailstorm
@export var tornado_damage := 45.0                  # per second inside the funnel
@export var weather_hurts_enemies := true
@export var weather_hurts_player := true
@export var player_damage_scale := 0.4              # the player takes this fraction of the damage above
@export var weather_limits_enemy_sight := true      # fog, heavy rain and snow shorten how far the enemies can see you
@export var max_fallen_trees := 40                  # fallen trees kept lying around (the oldest vanish)
@export var camera_shake := true

# the weather recipes: cloud cover, darkness, rain, hail, snow, fog, wind (m/s), lightning strikes per minute
const PRESETS := {
	"clear":     {"cloud": 0.10, "dark": 0.00, "rain": 0.0,  "hail": 0.0, "snow": 0.0,  "fog": 0.0,  "wind": 2.0,  "bolts": 0.0, "tornado": 0.0},
	"cloudy":    {"cloud": 0.6, "dark": 0.1,  "rain": 0.0,  "hail": 0.0, "snow": 0.0,  "fog": 0.05, "wind": 5.0,  "bolts": 0.0, "tornado": 0.0},
	"fog":       {"cloud": 0.60, "dark": 0.30, "rain": 0.0,  "hail": 0.0, "snow": 0.0,  "fog": 0.9,  "wind": 1.0,  "bolts": 0.0, "tornado": 0.0},
	"drizzle":   {"cloud": 0.80, "dark": 0.28, "rain": 0.22, "hail": 0.0, "snow": 0.0,  "fog": 0.15, "wind": 4.0,  "bolts": 0.0, "tornado": 0.0},
	"rain":      {"cloud": 0.92, "dark": 0.45, "rain": 0.65, "hail": 0.0, "snow": 0.0,  "fog": 0.2,  "wind": 8.0,  "bolts": 0.0, "tornado": 0.0},
	"storm":     {"cloud": 1.00, "dark": 0.75, "rain": 1.0,  "hail": 0.0, "snow": 0.0,  "fog": 0.25, "wind": 17.0, "bolts": 7.0, "tornado": 0.0},
	"hail":      {"cloud": 1.00, "dark": 0.85, "rain": 0.3,  "hail": 1.0, "snow": 0.0,  "fog": 0.2,  "wind": 12.0, "bolts": 2.0, "tornado": 0.0},
	"snow":      {"cloud": 0.85, "dark": 0.30, "rain": 0.0,  "hail": 0.0, "snow": 0.6,  "fog": 0.25, "wind": 4.0,  "bolts": 0.0, "tornado": 0.0},
	"blizzard":  {"cloud": 1.00, "dark": 0.50, "rain": 0.0,  "hail": 0.0, "snow": 1.0,  "fog": 0.65, "wind": 22.0, "bolts": 0.0, "tornado": 0.0},
	"windstorm": {"cloud": 0.60, "dark": 0.30, "rain": 0.0,  "hail": 0.0, "snow": 0.0,  "fog": 0.05, "wind": 27.0, "bolts": 0.0, "tornado": 0.0},
	"tornado":   {"cloud": 1.00, "dark": 0.92, "rain": 0.6,  "hail": 0.0, "snow": 0.0,  "fog": 0.3,  "wind": 23.0, "bolts": 4.0, "tornado": 1.0},
}
const NEXT := {
	"clear":     {"cloudy": 5, "fog": 1, "windstorm": 1},
	"cloudy":    {"clear": 3, "drizzle": 3, "fog": 1, "rain": 2, "snow": 1, "windstorm": 1},
	"fog":       {"clear": 2, "cloudy": 3, "drizzle": 2},
	"drizzle":   {"cloudy": 3, "rain": 4, "clear": 1},
	"rain":      {"drizzle": 3, "storm": 3, "cloudy": 2, "hail": 1},
	"storm":     {"rain": 4, "hail": 1, "tornado": 1, "cloudy": 1, "windstorm": 1},
	"hail":      {"storm": 2, "rain": 2, "cloudy": 1},
	"snow":      {"cloudy": 3, "blizzard": 2, "clear": 1},
	"blizzard":  {"snow": 4, "cloudy": 1},
	"windstorm": {"cloudy": 3, "clear": 2, "storm": 1},
	"tornado":   {"storm": 3, "rain": 2},
}
const SEVERE := ["storm", "hail", "tornado", "blizzard", "windstorm"]
const ORDER := ["clear", "cloudy", "fog", "drizzle", "rain", "storm", "hail", "snow", "blizzard", "windstorm", "tornado"]

var current_weather := "clear"
var wind_speed := 0.0                               # metres per second right now (with gusts)
var wind_direction := Vector3(1, 0, 0)              # the way the wind blows
var rain_level := 0.0                               # 0..1 right now
var wetness := 0.0                                  # 0..1: puddles and wet ground
var soil_saturation := 0.0                          # 0..1: soaked soil (drives erosion)

var _cur := {"cloud": 0.1, "dark": 0.0, "rain": 0.0, "hail": 0.0, "snow": 0.0, "fog": 0.0, "wind": 2.0, "bolts": 0.0, "tornado": 0.0}
var _tgt := {}
var _weather_timer := 0.0
var _disc_guard_timer := 0.0
var _resolve_timer := 0.0
var _resolve_tries := 0
var _own_sun: Sprite3D
var _sun_warned := false
var _vib_base := 1.0
var _vib_written := -1.0
var _manual_hold := 0.0                             # seconds the weather you picked by hand (F6 / set_weather) stays before patches take over again
var _patch_noise_a := FastNoiseLite.new()
var _patch_noise_b := FastNoiseLite.new()
var _patch_offset := Vector2.ZERO
var _patch_timer := 0.0
var _patch_pending := ""
var _patch_pending_count := 0
var _find_timer := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _wind_yaw := 0.0

# nodes found
var _env: Environment
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _skymat: ShaderMaterial
var _cam: Camera3D

# visuals
var _dome: MeshInstance3D
var _dome_mat: ShaderMaterial
var _rain_p: GPUParticles3D
var _hail_p: GPUParticles3D
var _snow_p: GPUParticles3D
var _splash_p: GPUParticles3D
var _petal_p: GPUParticles3D
var _rain_mat: StandardMaterial3D
var _bolts: Array = []
var _flash := 0.0
var _shake := 0.0
var _light_level := 1.0
var _sun_tint := Color.WHITE

# lightning
var _bolt_timer := 5.0
var _thunder_queue: Array = []

# trees
var _sway_timer := 0.0
var _sway_smooth := 0.0
var _topple_timer := 0.0
var _props: Array = []
var _tree_mesh_cache: Mesh

# tornado
var _tor: Node3D
var _tor_mat: ShaderMaterial
var _tor_debris: MultiMeshInstance3D
var _tor_dust: GPUParticles3D
var _tor_active := false
var _tor_pos := Vector3.ZERO
var _tor_heading := 0.0
var _tor_age := 0.0
var _tor_size := 0.0                                # 0..1 grows in and shrinks out
var _tor_deb: Array = []
var _tor_fling_timer := 0.0

# damage
var _dmg_timer := 0.0
var _hail_timer := 0.0

# puddles
var _pud_mat: ShaderMaterial
var _pud_nodes := {}
var _pud_timer := 0.0

# audio
var _snd_rain: AudioStreamPlayer
var _snd_wind: AudioStreamPlayer
var _snd_tor: AudioStreamPlayer
var _snd_thunder: Array[AudioStreamPlayer] = []
var _wav_thunder: Array = []
var _wav_rain: AudioStreamWAV
var _wav_wind: AudioStreamWAV
var _audio_thread_done := false
var _audio_data := {}
var _audio_built := false


# =====================================================================================================
# START
# =====================================================================================================
func _ready() -> void:
	process_priority = 100                      # runs after the sky script each frame, so it can dim and tint what that script just set
	_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0
	_patch_noise_a.seed = _rng.randi()
	_patch_noise_a.frequency = 1.0
	_patch_noise_b.seed = _rng.randi()
	_patch_noise_b.frequency = 1.0
	_patch_offset = Vector2(_rng.randf_range(-500.0, 500.0), _rng.randf_range(-500.0, 500.0))
	_wind_yaw = deg_to_rad(wind_yaw_degrees)
	if not weather_enabled:
		set_process(false)
		set_physics_process(false)
		return
	_find_things()
	_make_dome()
	_make_own_sun()
	_make_particles()
	_make_tornado()
	_make_puddle_material()
	if sound_enabled:
		WorkerThreadPool.add_task(_generate_audio, false, "weather audio")
	_apply_weather(start_weather if PRESETS.has(start_weather) else "clear", true)
	for k in _tgt:
		_cur[k] = _tgt[k]
	if _tgt["tornado"] > 0.5:
		_spawn_tornado()


## Picks up the sun, moon, sky and environment from the sky script. The sky script only finds its own sun and builds its sky
## in its _ready, which can run AFTER this script's when the Weather node sits above it in the scene tree, so this is
## tried again (see _process) until everything is there.
func _resolve_sky() -> void:
	if sky_cycle != null:
		var sv = sky_cycle.get("sun")
		if sv is DirectionalLight3D:
			_sun = sv
		var mv = sky_cycle.get("moon")
		if mv is DirectionalLight3D:
			_moon = mv
		var we = sky_cycle.get("world_env")
		if we is WorldEnvironment and (we as WorldEnvironment).environment != null:
			_env = (we as WorldEnvironment).environment
		var sm = sky_cycle.get("sky_mat")
		if sm is ShaderMaterial:
			_skymat = sm
	var root := get_tree().current_scene
	if root != null and _sun == null:
		_sun = root.find_child("Sun", true, false) as DirectionalLight3D
	if root != null and _moon == null:
		_moon = root.find_child("Moon", true, false) as DirectionalLight3D


func _find_things() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	if sky_cycle == null:
		for n in root.find_children("*", "Node", true, false):
			if "sky_mat" in n and "sun_sprite" in n:
				sky_cycle = n
				break
	_resolve_sky()
	if _env == null:
		for n in root.find_children("*", "WorldEnvironment", true, false):
			_env = (n as WorldEnvironment).environment
			break
	if _sun == null:
		_sun = root.find_child("Sun", true, false) as DirectionalLight3D
	if _moon == null:
		_moon = root.find_child("Moon", true, false) as DirectionalLight3D
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if terrain == null:
		for n in root.find_children("*", "Node3D", true, false):
			if n.has_method("height_at"):
				terrain = n
				break
	if trees == null:
		for n in root.find_children("*", "Node3D", true, false):
			if "_cells" in n and "_built" in n and "_meshes" in n:
				trees = n
				break


# =====================================================================================================
# WEATHER STATE
# =====================================================================================================
func set_weather(weather_name: String) -> void:
	if PRESETS.has(weather_name):
		_apply_weather(weather_name, false)
		_weather_timer = _rng.randf_range(min_duration, max_duration)
		_manual_hold = _weather_timer


func next_weather() -> void:
	var i := ORDER.find(current_weather)
	set_weather(ORDER[(i + 1) % ORDER.size()])


func _apply_weather(weather_name: String, instant: bool) -> void:
	current_weather = weather_name
	_tgt = (PRESETS[weather_name] as Dictionary).duplicate()
	if not lightning_enabled:
		_tgt["bolts"] = 0.0
	if not tornadoes_enabled:
		_tgt["tornado"] = 0.0
	if not precipitation_enabled:
		_tgt["rain"] = 0.0
		_tgt["hail"] = 0.0
		_tgt["snow"] = 0.0
	if _tgt["tornado"] > 0.5 and not instant and not _tor_active:
		_spawn_tornado()


## Weather patches: the land is mostly sunny. Two slow noise maps decide, for wherever you are standing, whether you are
## in a patch of bad weather (and which kind and how strong). The patches drift slowly across the land with the wind,
## so you can walk out of the rain into sunshine, or a storm can roll over you.
func _weather_at(pos: Vector2) -> String:
	var q := (pos + _patch_offset) / maxf(patch_size, 50.0)
	var v := clampf(0.5 + _patch_noise_a.get_noise_2d(q.x, q.y) * 0.9, 0.0, 1.0)
	if v < sunny_fraction - 0.07:
		return "clear"
	if v < sunny_fraction:
		return "cloudy"                       # the thin edge of a patch: clouds gather before the weather arrives
	var strength := clampf((v - sunny_fraction) / maxf(1.0 - sunny_fraction, 0.05), 0.0, 1.0)   # 0 at the edge, 1 in the heart
	var kind := clampf(0.5 + _patch_noise_b.get_noise_2d(q.x * 0.6 + 40.0, q.y * 0.6 - 40.0) * 0.9, 0.0, 1.0)   # 0..1: which kind of patch this is
	var out := "cloudy"
	if kind < 0.47:
		out = "drizzle" if strength < 0.3 else ("rain" if strength < 0.7 else "storm")
		if out == "storm" and strength > 0.93:
			out = "tornado"
	elif kind < 0.54:
		out = "fog"
	elif kind < 0.66:
		out = "snow" if strength < 0.7 else "blizzard"
	elif kind < 0.80:
		out = "windstorm" if strength > 0.5 else "cloudy"
	else:
		out = "hail" if strength > 0.4 else "rain"
	if severity <= 0.0 and SEVERE.has(out):
		out = {"storm": "rain", "hail": "rain", "tornado": "rain", "blizzard": "snow", "windstorm": "cloudy"}.get(out, "cloudy")
	elif severity < 1.0 and (out == "tornado" or out == "hail") and _rng.randf() > severity:
		out = "storm" if out == "tornado" else "rain"
	return out


func _update_patches(delta: float) -> void:
	_patch_offset += Vector2(wind_direction.x, wind_direction.z) * patch_drift_speed * delta
	if _manual_hold > 0.0:
		return
	_patch_timer -= delta
	if _patch_timer > 0.0:
		return
	_patch_timer = 1.5
	var here := Vector3.ZERO
	if player != null:
		here = player.global_position
	elif _cam != null:
		here = _cam.global_position
	var w := _weather_at(Vector2(here.x, here.z))
	if w == current_weather:
		_patch_pending = ""
		_patch_pending_count = 0
		return
	if w == _patch_pending:
		_patch_pending_count += 1
	else:
		_patch_pending = w
		_patch_pending_count = 1
	if _patch_pending_count >= 2:               # it has to stay different for a few seconds, so the weather never flickers at a patch edge
		_apply_weather(w, false)
		_patch_pending = ""
		_patch_pending_count = 0


func _pick_next_weather() -> String:
	var table: Dictionary = NEXT[current_weather]
	var total := 0.0
	var w := {}
	for k in table:
		var v := float(table[k])
		if SEVERE.has(k):
			v *= severity
		w[k] = v
		total += v
	if total <= 0.0:
		return "cloudy"
	var r := _rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "cloudy"


func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys or not weather_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F6:
				next_weather()
				print("Weather: ", current_weather)
			KEY_F7:
				strike_lightning(Vector3.ZERO, true)
			KEY_F8:
				_spawn_tornado()
			KEY_F9:
				_print_sun_report()
			KEY_F10:
				if sky_cycle != null and sky_cycle.has_method("set_time_of_day"):
					sky_cycle.call("set_time_of_day", 0.5)
					print("Weather: jumped to noon")


# =====================================================================================================
# MAIN LOOP
# =====================================================================================================
func _process(delta: float) -> void:
	_t += delta
	_find_timer -= delta
	if _find_timer <= 0.0:
		_find_timer = 1.0
		if _env == null or player == null or terrain == null or trees == null:
			_find_things()
	var vp := get_viewport()
	_cam = vp.get_camera_3d() if vp else null
	if _audio_thread_done and not _audio_built:
		_build_audio()

	# --- state: fade toward the target, pick the next weather ---
	var k := 1.0 - exp(-delta / maxf(transition_time / 3.0, 0.05))
	for key in _tgt:
		_cur[key] = lerpf(float(_cur[key]), float(_tgt[key]), k)
	_manual_hold = maxf(_manual_hold - delta, 0.0)
	if auto_weather:
		if patchy_weather:
			_update_patches(delta)
		else:
			_weather_timer -= delta
			if _weather_timer <= 0.0:
				_weather_timer = _rng.randf_range(min_duration, max_duration)
				_apply_weather(_pick_next_weather(), false)

	_update_wind(delta)
	var rain: float = _cur["rain"]
	rain_level = rain
	wetness = clampf(wetness + (rain * delta / 50.0 + float(_cur["snow"]) * delta / 200.0 + float(_cur["hail"]) * delta / 90.0) - (delta / 360.0) * (1.0 - clampf(rain * 3.0, 0.0, 1.0)), 0.0, 1.0)
	soil_saturation = clampf(soil_saturation + (rain * delta / 240.0) - delta / 700.0 * (1.0 - clampf(rain * 4.0, 0.0, 1.0)), 0.0, 1.0)

	_flash = maxf(_flash - delta * 2.2, 0.0)
	_shake = maxf(_shake - delta * 1.6, 0.0)

	if (_sun == null or _skymat == null or _env == null) and _resolve_tries < 120:
		_resolve_timer -= delta
		if _resolve_timer <= 0.0:
			_resolve_timer = 0.5
			_resolve_tries += 1
			_resolve_sky()
			if sky_cycle == null:
				_find_things()
			if _resolve_tries == 120 and _sun == null:
				push_warning("Weather: never found the sun light. Assign Sky Cycle on the Weather node (or name your sun light 'Sun').")
	_disc_guard_timer -= delta
	if hide_light_discs and _disc_guard_timer <= 0.0:
		_disc_guard_timer = 1.0
		_guard_light_discs()
	_update_light_level()
	_apply_atmosphere()
	_update_dome(delta)
	_update_precipitation()
	_update_lightning(delta)
	_update_thunder(delta)
	_update_tornado(delta)
	_update_trees(delta)
	_update_props(delta)
	_update_puddles(delta)
	_update_audio(delta)
	_update_camera_shake()


func _update_wind(delta: float) -> void:
	_wind_yaw += _noise.get_noise_1d(_t * 0.03) * delta * wind_drift * 0.5
	wind_direction = Vector3(cos(_wind_yaw), 0.0, sin(_wind_yaw))
	var gust := 1.0 + gust_strength * (_noise.get_noise_1d(_t * 0.35 + 50.0) * 0.8 + _noise.get_noise_1d(_t * 1.3 + 90.0) * 0.4)
	wind_speed = maxf(float(_cur["wind"]) * gust, 0.0)


## A directional light draws its own bright (or, at zero energy, black) disc in the sky unless its sky mode is "light only".
## The sky script sets that for the sun and moon, but lights made by other scripts (the sky-fill light shining down from
## straight overhead, the ground-bounce light, and so on) can still draw a black blob. This switches all of them to "light only".
func _guard_light_discs() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		var dl := n as DirectionalLight3D
		if dl.sky_mode != DirectionalLight3D.SKY_MODE_LIGHT_ONLY:
			dl.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY


## The sun picture the sky script draws needs res://sun.png. If it is missing, there is no sun at all, so this draws a simple
## glowing one (own_sun_disc). F9 prints where the sun is and whether the sky script's sun picture exists.
func _make_own_sun() -> void:
	if own_sun_disc == "never":
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.26, 0.3, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.98, 0.8, 1.0), Color(1.0, 0.96, 0.7, 1.0), Color(1.0, 0.88, 0.5, 0.55), Color(1.0, 0.8, 0.4, 0.18), Color(1.0, 0.75, 0.35, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_own_sun = Sprite3D.new()
	_own_sun.name = "WeatherSun"
	_own_sun.texture = gt
	_own_sun.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_own_sun.shaded = false
	_own_sun.double_sided = true
	_own_sun.transparent = true
	_own_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own_sun.top_level = true
	_own_sun.visible = false
	var sprite_dist := 900.0
	var size_deg := 9.0
	if sky_cycle != null:
		sprite_dist = float(sky_cycle.get("sprite_distance")) if sky_cycle.get("sprite_distance") != null else 900.0
		size_deg = float(sky_cycle.get("sun_size_degrees")) if sky_cycle.get("sun_size_degrees") != null else 9.0
	var found := _find_sun_texture()
	if found != null:
		# your own sun picture, found by name (e.g. "sun-1.png.png"), because the sky script only loads exactly res://sun.png
		_own_sun.texture = found
		_own_sun.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_own_sun.pixel_size = 2.0 * sprite_dist * tan(deg_to_rad(size_deg) * 0.5) / float(maxi(found.get_width(), found.get_height()))
	else:
		_own_sun.pixel_size = 2.0 * sprite_dist * tan(deg_to_rad(size_deg * 3.4) * 0.5) / 256.0
	_own_sun.set_meta("dist", sprite_dist)
	add_child(_own_sun)


## Looks in res:// for a picture whose name has "sun" in it (sun.png, sun-1.png.png, Sun.webp ...), for the sky script's sun.
func _find_sun_texture() -> Texture2D:
	if sky_cycle != null and sky_cycle.get("sun_texture") is Texture2D:
		return sky_cycle.get("sun_texture") as Texture2D
	var dir := DirAccess.open("res://")
	if dir == null:
		return null
	for f in dir.get_files():
		var fn := String(f)
		if fn.ends_with(".import"):
			fn = fn.trim_suffix(".import")
		elif fn.ends_with(".remap"):
			fn = fn.trim_suffix(".remap")
		var low := fn.to_lower()
		if low.contains("sun") and (low.ends_with(".png") or low.ends_with(".webp") or low.ends_with(".jpg") or low.ends_with(".jpeg")):
			if ResourceLoader.exists("res://" + fn):
				var t = load("res://" + fn)
				if t is Texture2D:
					return t as Texture2D
	return null


func _update_own_sun(sun_h: float, cloud: float) -> void:
	if _own_sun == null or _sun == null:
		return
	var theirs = sky_cycle.get("sun_sprite") if sky_cycle != null else null
	var want := own_sun_disc == "always" or (own_sun_disc == "auto" and theirs == null)
	if own_sun_disc == "auto" and theirs == null and not _sun_warned:
		_sun_warned = true
		push_warning("Weather: your sky script has no sun picture (it only loads exactly res://sun.png), so a sun is drawn here instead, using any picture in res:// with sun in its name, or a plain glowing one. Set own_sun_disc to never to turn this off.")
	var a := smoothstep(-0.08, 0.05, sun_h) * (1.0 - smoothstep(0.7, 1.0, cloud) * sun_hidden_by_clouds)
	_own_sun.visible = want and a > 0.01
	if not _own_sun.visible:
		return
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	_own_sun.global_position = cp + _sun.global_transform.basis.z.normalized() * float(_own_sun.get_meta("dist"))
	_own_sun.modulate = Color(1, 1, 1, a)


func _print_sun_report() -> void:
	if _sun == null:
		print("Weather: no sun light found")
		return
	var d := _sun.global_transform.basis.z.normalized()
	var elev := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var az := rad_to_deg(atan2(d.x, d.z))
	var cam := get_viewport().get_camera_3d()
	var face := 0.0
	if cam != null:
		var f := -cam.global_transform.basis.z
		face = rad_to_deg(atan2(f.x, f.z))
	var sp = sky_cycle.get("sun_sprite") if sky_cycle != null else null
	print("Sun: height ", snappedf(elev, 0.1), " deg above the horizon, direction ", snappedf(az, 1.0), " deg; you face ", snappedf(face, 1.0), " deg (turn to match the direction to see it)")
	print("Sky script's sun picture: ", "MISSING (no sun.png)" if sp == null else ("shown, alpha " + str(snappedf((sp as Sprite3D).modulate.a, 0.01))))
	print("Weather now: ", current_weather, " | own sun disc: ", own_sun_disc, " | F10 jumps to noon")


func _update_light_level() -> void:
	var h := 1.0
	if _sun != null:
		h = _sun.global_transform.basis.z.y                    # the sun's height: +1 straight up, -1 straight down
		_sun_tint = _sun.light_color
	_light_level = lerpf(0.1, 1.0, smoothstep(-0.15, 0.3, h))

# =====================================================================================================
# SKY, LIGHT AND FOG (applied on top of the sky script's values each frame)
# =====================================================================================================
func _apply_atmosphere() -> void:
	var cloud: float = _cur["cloud"]
	var dark: float = float(_cur["dark"]) * storm_darkness * weather_dimming
	var flash := _flash

	# How much the sun is getting through: only thick cloud and severe weather (storm, hail, tornado, blizzard, gales) stop it.
	var sun_h := 0.0
	if _sun != null:
		sun_h = _sun.global_transform.basis.z.y
	var severe := clampf(maxf(maxf(float(_cur["bolts"]) / 4.0, float(_cur["hail"])), maxf(float(_cur["tornado"]), smoothstep(14.0, 24.0, float(_cur["wind"])))), 0.0, 1.0)
	var shine := 0.0
	if sunshine_enabled:
		shine = smoothstep(0.02, 0.3, sun_h) * (1.0 - smoothstep(0.45, 0.95, cloud)) * (1.0 - severe)

	if _sun != null:
		_sun.light_energy *= lerpf(1.0, 0.3, dark * 0.9)
		_sun.light_energy *= 1.0 + sunshine_strength * shine
		_sun.light_color = _sun.light_color.lerp(Color(1.0, 0.95, 0.82), shine * 0.5)
		if flash > 0.0:
			_sun.light_energy += flash * 0.6
	if _moon != null:
		_moon.light_energy *= lerpf(1.0, 0.3, dark)
	if _env != null:
		_env.ambient_light_energy = _env.ambient_light_energy * (lerpf(1.0, 0.92, dark) + cloud * overcast_fill) + flash * 2.2
		_env.ambient_light_energy += extra_brightness * 0.6 + shine * sunshine_strength * 0.2
		# more colour in everything (the sky script resets saturation every frame; this also guards against stacking if it doesn't)
		var cur_s: float = _env.adjustment_saturation
		if absf(cur_s - _vib_written) < 0.00001:
			cur_s = _vib_base
		else:
			_vib_base = cur_s
		_vib_written = cur_s * (1.0 + vibrance * (1.0 - severe * 0.6))
		_env.adjustment_enabled = true
		_env.adjustment_saturation = _vib_written
		_env.adjustment_brightness = 1.0 + vibrance * 0.12 * (1.0 - severe)

	if _skymat != null:
		var storm_top := Color(0.3, 0.33, 0.38) * lerpf(0.3, 1.0, _light_level)
		var storm_hor := Color(0.4, 0.43, 0.47) * lerpf(0.22, 1.0, _light_level)
		var flash_col := Color(0.75, 0.8, 1.0) * flash * 1.2
		var kc := clampf(cloud * 0.7, 0.0, 1.0)
		var t = _skymat.get_shader_parameter("top_color")
		var h = _skymat.get_shader_parameter("horizon_color")
		var g = _skymat.get_shader_parameter("ground_color")
		if t is Color:
			_skymat.set_shader_parameter("top_color", (t as Color).lerp(storm_top, kc) + flash_col)
		if h is Color:
			var hc: Color = (h as Color).lerp(storm_hor, kc) + flash_col
			_skymat.set_shader_parameter("horizon_color", hc)
			if g is Color:
				_skymat.set_shader_parameter("ground_color", (g as Color).lerp(hc.darkened(0.5), kc))
		var ga = _skymat.get_shader_parameter("glow_amount")
		if ga is float:
			_skymat.set_shader_parameter("glow_amount", float(ga) * (1.0 - cloud * 0.85))
		for p in ["star_amount", "sun_aura_amount", "moon_aura_amount"]:
			var v = _skymat.get_shader_parameter(p)
			if v is float:
				var keep := (1.0 - clampf(cloud * 1.1, 0.0, 1.0)) if p == "star_amount" else (1.0 - cloud * 0.3)   # clouds hide the stars, but your sun and moon glow stays
				_skymat.set_shader_parameter(p, float(v) * keep)
	_update_own_sun(sun_h, cloud)
	if sky_cycle != null:
		var ss = sky_cycle.get("sun_sprite")
		if ss is Sprite3D:
			var bright := lerpf(1.0, sun_disc_brightness, shine)
			var sc := ss as Sprite3D
			sc.modulate = Color(bright, bright, bright, sc.modulate.a * (1.0 - smoothstep(0.7, 1.0, cloud) * sun_hidden_by_clouds))
		var ms = sky_cycle.get("moon_sprite")
		if ms is Sprite3D:
			(ms as Sprite3D).modulate.a *= (1.0 - smoothstep(0.7, 1.0, cloud) * sun_hidden_by_clouds)
		var mh = sky_cycle.get("moon_halo")
		if mh is MeshInstance3D and cloud > 0.6:
			(mh as MeshInstance3D).visible = false

	# fog: thick in fog, thinner in rain and snow
	if _env != null:
		var fogv: float = float(_cur["fog"])
		if rain_fog:
			fogv = maxf(fogv, maxf(float(_cur["rain"]) * 0.4, maxf(float(_cur["snow"]) * 0.5, float(_cur["hail"]) * 0.3)) * (1.0 - shine * 0.8))
		if fogv > 0.01:
			_env.fog_enabled = true
			_env.fog_density = fogv * 0.011
			var fc := Color(0.5, 0.53, 0.57).lerp(Color(0.82, 0.85, 0.9), float(_cur["snow"]))
			if _skymat != null:
				var hh = _skymat.get_shader_parameter("horizon_color")
				if hh is Color:
					fc = (hh as Color).lerp(fc, 0.5)
			_env.fog_light_color = fc
			_env.fog_light_energy = lerpf(0.25, 1.0, _light_level)
			_env.fog_sky_affect = 0.5
			_env.fog_aerial_perspective = 0.0
		elif _env.fog_enabled:
			_env.fog_enabled = false


# =====================================================================================================
# CLOUD DOME
# =====================================================================================================
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;

uniform float coverage = 0.5;
uniform float darkness = 0.0;
uniform float light_level = 1.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec2 drift = vec2(0.0);
uniform float flash = 0.0;
uniform float cloud_scale = 1.0;
varying vec3 dirw;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	dirw = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	vec3 d = normalize(dirw);
	float h = d.y;
	if (h <= 0.0) {
		ALPHA = 0.0;
		ALBEDO = vec3(0.0);
	} else {
		vec2 p = d.xz / (h + 0.35) * 3.2 / cloud_scale + drift * 2.5;   // 3.2: big enough that straight overhead still shows cloud shapes, not one blob
		float n = fbm(p);
		float thr = mix(0.78, 0.22, coverage);
		float dens = smoothstep(thr, thr + 0.22, n);
		// light from the sun's side: compare the density a little toward the sun (thin edges toward the sun glow)
		float n2 = fbm(p + sun_dir.xz * 0.12);
		float shade = clamp(0.75 + (n - n2) * 2.4, 0.35, 1.15);
		vec3 lit = mix(vec3(0.97, 0.97, 0.98), vec3(0.17, 0.18, 0.21), darkness);
		vec3 col = lit * shade;
		col *= mix(vec3(0.55, 0.65, 0.95), vec3(1.0), smoothstep(0.0, 0.5, light_level)) * (0.1 + 0.9 * light_level);
		float thick = smoothstep(0.45, 1.0, dens + n * 0.3);
		col = mix(col, col * 0.55, thick * (0.4 + darkness * 0.6));
		float sd = max(dot(d, normalize(sun_dir)), 0.0);
		col += sun_color * pow(sd, 5.0) * (1.0 - dens * 0.6) * (1.0 - darkness) * 0.45 * light_level;
		col += vec3(0.7, 0.78, 1.0) * flash * (0.25 + 0.75 * fbm(p * 1.7 + 3.0));
		ALBEDO = col;
		ALPHA = clamp(dens, 0.0, 1.0) * smoothstep(0.0, 0.2, h) * clamp(coverage * 6.0, 0.0, 1.0);
	}
}
"""


func _make_dome() -> void:
	if not cloud_dome_enabled:
		return
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 48
	sph.rings = 24
	_dome_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	_dome_mat.shader = sh
	_dome_mat.render_priority = -20
	_dome = MeshInstance3D.new()
	_dome.mesh = sph
	_dome.material_override = _dome_mat
	_dome.top_level = true
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.extra_cull_margin = 16384.0
	add_child(_dome)


var _drift := Vector2.ZERO

func _update_dome(delta: float) -> void:
	if _dome == null:
		return
	var cloud: float = _cur["cloud"]
	_dome.visible = cloud > 0.02
	if not _dome.visible:
		return
	var cp := _cam.global_position if _cam else global_position
	var far := _cam.far if _cam else 4000.0
	var radius := minf(2600.0, far * 0.85)
	_dome.global_position = cp
	_dome.scale = Vector3.ONE * radius
	_drift += Vector2(wind_direction.x, wind_direction.z) * (cloud_speed * (0.4 + wind_speed * 0.08)) * delta
	_dome_mat.set_shader_parameter("coverage", cloud)
	_dome_mat.set_shader_parameter("darkness", clampf(float(_cur["dark"]) * storm_darkness * lerpf(1.0, weather_dimming, 0.6), 0.0, 1.0))
	_dome_mat.set_shader_parameter("light_level", _light_level)
	_dome_mat.set_shader_parameter("drift", _drift)
	_dome_mat.set_shader_parameter("flash", _flash)
	_dome_mat.set_shader_parameter("cloud_scale", cloud_scale)
	_dome_mat.set_shader_parameter("sun_color", _sun_tint)
	var sd := Vector3.UP
	if _sun != null:
		sd = _sun.global_transform.basis.z
	_dome_mat.set_shader_parameter("sun_dir", sd)


# =====================================================================================================
# RAIN, HAIL, SNOW, SPLASHES, BLOWN PETALS
# =====================================================================================================
func _soft_dot_texture(size: int = 32) -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex


func _ring_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - absf(r - 0.7) / 0.18, 0.0, 1.0) * clampf(1.0 - maxf(r - 0.85, 0.0) / 0.15, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_particles() -> void:
	# ----- rain: thin streaks falling from a box above the camera -----
	var rq := QuadMesh.new()
	rq.size = Vector2(0.014, 0.65)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_mat.albedo_color = Color(0.72, 0.78, 0.9, 0.38)
	_rain_mat.disable_fog = false
	rq.material = _rain_mat
	_rain_p = _make_emitter(rain_amount, 1.0, Vector3(32, 0.5, 32), Vector3(0, -1, 0), 24.0, 28.0, 0.0, rq)

	# ----- hail: small white balls, fast -----
	var hs := SphereMesh.new()
	hs.radius = 0.045
	hs.height = 0.09
	hs.radial_segments = 6
	hs.rings = 3
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.92, 0.95, 1.0)
	hm.roughness = 0.25
	hm.emission_enabled = true
	hm.emission = Color(0.6, 0.65, 0.75)
	hm.emission_energy_multiplier = 0.4
	hs.material = hm
	_hail_p = _make_emitter(hail_amount, 1.1, Vector3(26, 0.5, 26), Vector3(0, -1, 0), 20.0, 24.0, 0.0, hs)

	# ----- snow: soft flakes drifting and swirling -----
	var sq := QuadMesh.new()
	sq.size = Vector2(0.09, 0.09)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_texture = _soft_dot_texture()
	sm.albedo_color = Color(1, 1, 1, 0.9)
	sq.material = sm
	_snow_p = _make_emitter(snow_amount, 6.0, Vector3(30, 0.5, 30), Vector3(0, -1, 0), 1.4, 2.6, 0.0, sq)
	var spm := _snow_p.process_material as ParticleProcessMaterial
	spm.turbulence_enabled = true
	spm.turbulence_noise_strength = 0.6
	spm.turbulence_noise_scale = 3.0
	spm.turbulence_influence_min = 0.05
	spm.turbulence_influence_max = 0.15

	# ----- rain splashes: little rings on the ground around you -----
	var spq := QuadMesh.new()
	spq.size = Vector2(0.5, 0.5)
	spq.orientation = PlaneMesh.FACE_Y
	var spmat := StandardMaterial3D.new()
	spmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spmat.albedo_texture = _ring_texture()
	spmat.vertex_color_use_as_albedo = true
	spmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spq.material = spmat
	_splash_p = GPUParticles3D.new()
	_splash_p.amount = 450
	_splash_p.lifetime = 0.4
	_splash_p.local_coords = false
	_splash_p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 10, 60))
	_splash_p.draw_pass_1 = spq
	_splash_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0.0, 18)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cg := Gradient.new()
	cg.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	cg.offsets = PackedFloat32Array([0.0, 1.0])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	_splash_p.process_material = pm
	_splash_p.emitting = false
	add_child(_splash_p)
	_splash_p.top_level = true

	# ----- petals / leaves carried by the wind (pink, to match the blossom trees) -----
	var pq := QuadMesh.new()
	pq.size = Vector2(0.11, 0.07)
	var ptm := StandardMaterial3D.new()
	ptm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ptm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ptm.albedo_color = Color(1.0, 0.78, 0.85)
	pq.material = ptm
	_petal_p = _make_emitter(500, 4.0, Vector3(28, 5, 28), Vector3(1, 0, 0), 4.0, 8.0, 0.0, pq)
	var ppm := _petal_p.process_material as ParticleProcessMaterial
	ppm.gravity = Vector3(0, -0.7, 0)
	ppm.angular_velocity_min = -280.0
	ppm.angular_velocity_max = 280.0
	ppm.turbulence_enabled = true
	ppm.turbulence_noise_strength = 1.2
	ppm.turbulence_influence_min = 0.1
	ppm.turbulence_influence_max = 0.3


func _make_emitter(amount: int, life: float, extents: Vector3, dir: Vector3, vmin: float, vmax: float, spread: float, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-extents.x - 10, -30, -extents.z - 10), Vector3(extents.x * 2 + 20, 60, extents.z * 2 + 20))
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	p.emitting = false
	add_child(p)
	p.top_level = true
	return p


func _update_precipitation() -> void:
	if _rain_p == null:
		return
	var cp := _cam.global_position if _cam else (player.global_position if player else global_position)
	var w2 := Vector3(wind_direction.x, 0, wind_direction.z) * minf(wind_speed, 30.0)
	var rain: float = _cur["rain"]
	var hail: float = _cur["hail"]
	var snow: float = _cur["snow"]

	# rain: the streaks slant with the wind
	_rain_p.global_position = cp + Vector3(0, 22, 0) - w2 * 0.4
	_rain_p.emitting = rain > 0.02
	_rain_p.amount_ratio = clampf(rain, 0.02, 1.0)
	var rpm := _rain_p.process_material as ParticleProcessMaterial
	rpm.direction = (Vector3(0, -1, 0) + w2 * 0.03).normalized()
	_rain_mat.albedo_color = Color(0.72, 0.78, 0.9, 0.12 + 0.3 * rain) * Color(1, 1, 1, 1) * lerpf(0.25, 1.0, _light_level)
	_rain_mat.albedo_color.a = 0.12 + 0.3 * rain

	_hail_p.global_position = cp + Vector3(0, 20, 0) - w2 * 0.35
	_hail_p.emitting = hail > 0.02
	_hail_p.amount_ratio = clampf(hail, 0.02, 1.0)
	(_hail_p.process_material as ParticleProcessMaterial).direction = (Vector3(0, -1, 0) + w2 * 0.04).normalized()

	_snow_p.global_position = cp + Vector3(0, 13, 0) - w2 * 1.2
	_snow_p.emitting = snow > 0.02
	_snow_p.amount_ratio = clampf(snow, 0.02, 1.0)
	(_snow_p.process_material as ParticleProcessMaterial).direction = (Vector3(0, -1, 0) + w2 * 0.12).normalized()

	# splashes sit on the ground under the player
	var on := rain_splashes and (rain > 0.08 or hail > 0.2)
	_splash_p.emitting = on
	if on:
		_splash_p.amount_ratio = clampf(maxf(rain, hail * 0.6), 0.05, 1.0)
		var gp := Vector3(cp.x, 0, cp.z)
		if player != null:
			gp = Vector3(player.global_position.x, 0, player.global_position.z)
		gp.y = _ground_y(gp.x, gp.z, player.global_position.y if player else cp.y - 1.6) + 0.05
		_splash_p.global_position = gp

	# blown petals
	var pet := petals_in_wind and wind_speed > 6.0
	_petal_p.emitting = pet
	if pet:
		var f := clampf((wind_speed - 6.0) / 20.0, 0.05, 1.0)
		_petal_p.amount_ratio = f
		_petal_p.global_position = cp + Vector3(0, 2.5, 0) - wind_direction * 18.0
		var ppm := _petal_p.process_material as ParticleProcessMaterial
		ppm.direction = (wind_direction + Vector3(0, 0.1, 0)).normalized()
		ppm.initial_velocity_min = wind_speed * 0.6
		ppm.initial_velocity_max = wind_speed * 1.0


func _ground_y(x: float, z: float, fallback: float) -> float:
	if terrain != null and terrain.has_method("height_at"):
		return float(terrain.height_at(x, z))
	return fallback


# =====================================================================================================
# DAMAGE HELPERS
# =====================================================================================================
func _hurt_enemy(e: Node, amount: float, at: Vector3) -> void:
	if not weather_hurts_enemies or amount <= 0.0:
		return
	if e.get("is_dead") == true:
		return
	if e.has_method("take_damage"):
		e.call("take_damage", amount, at, null)


func _hurt_player(amount: float, at: Vector3) -> void:
	if not weather_hurts_player or player == null or amount <= 0.0:
		return
	if player.has_method("take_damage"):
		player.call("take_damage", amount * player_damage_scale, at, null)


func _sheltered(body: Node3D) -> bool:
	# true if something solid is overhead (a roof, a rock ledge...)
	var space := get_world_3d().direct_space_state
	var from := body.global_position + Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 40, 0))
	if body is CollisionObject3D:
		q.exclude = [(body as CollisionObject3D).get_rid()]
	var r := space.intersect_ray(q)
	return not r.is_empty()


# =====================================================================================================
# LIGHTNING
# =====================================================================================================
func _update_lightning(delta: float) -> void:
	var rate: float = float(_cur["bolts"]) * lightning_rate
	if lightning_enabled and rate > 0.05:
		_bolt_timer -= delta
		if _bolt_timer <= 0.0:
			_bolt_timer = 60.0 / rate * _rng.randf_range(0.35, 1.6)
			if _rng.randf() < 0.35:
				_sheet_lightning()
			else:
				strike_lightning(Vector3.ZERO, _rng.randf() < strike_near_player_chance)
	# animate live bolts
	var i := _bolts.size() - 1
	while i >= 0:
		var b: Dictionary = _bolts[i]
		b["t"] = float(b["t"]) + delta
		var t: float = b["t"]
		var life: float = b["life"]
		var env := _bolt_env(t, life)
		var mat: StandardMaterial3D = b["mat"]
		mat.albedo_color = Color(3.2, 3.2, 4.2, 1.0) * env
		mat.albedo_color.a = 1.0
		var lt: OmniLight3D = b["light"]
		if is_instance_valid(lt):
			lt.light_energy = float(b["energy"]) * env
		_flash = maxf(_flash, env * float(b["power"]))
		if t >= life:
			for n in [b["mi"], b["light"]]:
				if is_instance_valid(n):
					(n as Node).queue_free()
			_bolts.remove_at(i)
		i -= 1


func _bolt_env(t: float, life: float) -> float:
	if t < 0.06:
		return 1.0
	if t < 0.11:
		return 0.12
	if t < 0.2:
		return 0.95
	if t < 0.25:
		return 0.15
	if t < 0.34:
		return 0.6
	return maxf(0.0, 1.0 - (t - 0.34) / maxf(life - 0.34, 0.05)) * 0.45


func _sheet_lightning() -> void:
	# lightning hidden in the clouds: the whole sky flickers and far thunder follows
	_flash = maxf(_flash, _rng.randf_range(0.3, 0.6))
	_thunder_queue.append({"delay": _rng.randf_range(1.2, 3.5), "dist": _rng.randf_range(650.0, 1300.0), "power": 0.5})


## Lightning strikes. With no position it picks a spot around you (near_player = a close one). Call it from anywhere.
func strike_lightning(target: Vector3 = Vector3.ZERO, near_player: bool = false) -> void:
	var pp := player.global_position if player != null else global_position
	if target == Vector3.ZERO:
		var ang := _rng.randf() * TAU
		var dist: float
		if near_player:
			dist = _rng.randf_range(14.0, 40.0)
		else:
			dist = lerpf(strike_min_distance, strike_max_distance, pow(_rng.randf(), 1.4))
		target = pp + Vector3(cos(ang), 0.0, sin(ang)) * dist
	target.y = _ground_y(target.x, target.z, pp.y)

	var hit_key := Vector2i.ZERO
	var hit_i := -1
	if strike_hits_trees and trees != null:
		var near := _trees_in_radius(target, 30.0, pp.distance_to(target) < 170.0)
		var best := 1e9
		for e in near:
			if float(e[2]) < best:
				best = float(e[2])
				hit_key = e[0]
				hit_i = int(e[1])
		if hit_i >= 0:
			var d = _tree_cell(hit_key, false)
			if d != null:
				var o := _tree_origin(d, hit_key, hit_i)
				target = o

	var top := target + Vector3(_rng.randf_range(-70, 70), cloud_height + _rng.randf_range(-30, 60), _rng.randf_range(-70, 70))
	var cam_pos := _cam.global_position if _cam != null else pp
	var dist_cam := cam_pos.distance_to(target)
	_spawn_bolt(top, target, cam_pos)

	var power := clampf(1.3 - dist_cam / 800.0, 0.25, 1.3)
	_flash = maxf(_flash, power)
	_thunder_queue.append({"delay": minf(dist_cam / 343.0, 4.0), "dist": dist_cam, "power": power})
	if dist_cam < 100.0 and camera_shake:
		_shake = maxf(_shake, (1.0 - dist_cam / 100.0) * 0.8)

	# impact
	_burst(target, 40, Color(1.0, 0.95, 0.7), 4.0, 12.0, 0.7, 0.07, 9.8)
	_scorch(target)
	if hit_i >= 0 and storm_damage_trees:
		var dirv := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
		_fell_tree(hit_key, hit_i, dirv, false, true)
		_make_fire(target, 25.0)
	# damage in a ring around the strike
	var R := lightning_damage_radius
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D:
			var d := (e as Node3D).global_position.distance_to(target)
			if d < R:
				_hurt_enemy(e, lightning_damage * (1.0 - 0.7 * d / R), target)
	if player != null:
		var dp := player.global_position.distance_to(target)
		if dp < R * 0.8:
			_hurt_player(lightning_damage * (1.0 - dp / (R * 0.8)) * 0.6, target)


func _spawn_bolt(top: Vector3, target: Vector3, cam_pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.no_depth_test = false
	mat.albedo_color = Color(3.2, 3.2, 4.2)

	var dist := cam_pos.distance_to(target)
	var w := clampf(dist * 0.005, 0.18, 2.4)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _bolt_path(top, target, 6)
	_ribbon(st, main, w * 4.5, cam_pos, Color(0.5, 0.6, 1.0, 0.12))
	_ribbon(st, main, w, cam_pos, Color(1, 1, 1, 1))
	for bi in 4:
		var idx := _rng.randi_range(8, int(main.size() * 0.75))
		var from := main[idx]
		var dirv := Vector3(_rng.randf_range(-1, 1), -_rng.randf_range(0.4, 1.0), _rng.randf_range(-1, 1)).normalized()
		var bp := _bolt_path(from, from + dirv * _rng.randf_range(40.0, 110.0), 4)
		_ribbon(st, bp, w * 0.45, cam_pos, Color(0.85, 0.9, 1.0, 0.8))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY

	var lt := OmniLight3D.new()
	lt.top_level = true
	lt.omni_range = 160.0
	lt.light_color = Color(0.75, 0.82, 1.0)
	lt.light_energy = 0.0
	lt.shadow_enabled = false
	add_child(lt)
	lt.global_position = target + Vector3(0, 12, 0)
	_bolts.append({"mi": mi, "light": lt, "mat": mat, "t": 0.0, "life": 0.6, "power": clampf(1.3 - dist / 800.0, 0.25, 1.3), "energy": 22.0 * clampf(1.2 - dist / 900.0, 0.2, 1.0)})


func _bolt_path(a: Vector3, b: Vector3, levels: int) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var disp := a.distance_to(b) * 0.1
	for lvl in levels:
		var nxt := PackedVector3Array()
		for i in pts.size() - 1:
			var mid := (pts[i] + pts[i + 1]) * 0.5
			mid += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.25, 0.25), _rng.randf_range(-1, 1)) * disp
			nxt.append(pts[i])
			nxt.append(mid)
		nxt.append(pts[pts.size() - 1])
		pts = nxt
		disp *= 0.55
	return pts


func _ribbon(st: SurfaceTool, pts: PackedVector3Array, width: float, cam_pos: Vector3, col: Color) -> void:
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var view := ((p0 + p1) * 0.5 - cam_pos).normalized()
		var side := (p1 - p0).cross(view)
		if side.length() < 0.0001:
			continue
		side = side.normalized() * width * 0.5
		var q := [p0 - side, p0 + side, p1 + side, p1 - side]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(q[idx])


func _scorch(pos: Vector3) -> void:
	var m := QuadMesh.new()
	m.size = Vector2(5.0, 5.0)
	m.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _soft_dot_texture(64)
	mat.albedo_color = Color(0.02, 0.02, 0.02, 0.75)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3(0, 0.07, 0)
	var tw := create_tween()
	tw.tween_interval(40.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 80.0)
	tw.tween_callback(mi.queue_free)


func _burst(pos: Vector3, amount: int, color: Color, vmin: float, vmax: float, life: float, size: float, grav: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -grav, 0)
	p.top_level = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	sm.material = mat
	p.mesh = sm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 1.0).timeout.connect(p.queue_free)


func _make_fire(pos: Vector3, secs: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 1.1
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.top_level = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cg := Gradient.new()
	cg.colors = PackedColorArray([Color(1.0, 0.85, 0.3, 0.9), Color(1.0, 0.4, 0.1, 0.7), Color(0.15, 0.13, 0.12, 0.0)])
	cg.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	p.color_ramp = cg
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot_texture()
	q.material = mat
	p.mesh = q
	add_child(p)
	p.global_position = pos + Vector3(0, 0.4, 0)
	p.emitting = true
	get_tree().create_timer(secs).timeout.connect(func():
		p.emitting = false
		get_tree().create_timer(2.0).timeout.connect(p.queue_free))


# =====================================================================================================
# THUNDER (sound), CAMERA SHAKE
# =====================================================================================================
func _update_thunder(delta: float) -> void:
	var i := _thunder_queue.size() - 1
	while i >= 0:
		var t: Dictionary = _thunder_queue[i]
		t["delay"] = float(t["delay"]) - delta
		if float(t["delay"]) <= 0.0:
			_play_thunder(float(t["dist"]), float(t["power"]))
			_thunder_queue.remove_at(i)
		i -= 1


func _play_thunder(dist: float, power: float) -> void:
	if not sound_enabled or _wav_thunder.is_empty():
		return
	var pl: AudioStreamPlayer = null
	for p in _snd_thunder:
		if not p.playing:
			pl = p
			break
	if pl == null:
		pl = _snd_thunder[0]
	var near := dist < 260.0
	pl.stream = _wav_thunder[0] if near else _wav_thunder[1 + _rng.randi() % maxi(_wav_thunder.size() - 1, 1)]
	var f := clampf(dist / 900.0, 0.0, 1.0)
	pl.volume_db = thunder_volume_db + lerpf(5.0, -24.0, f) + (power - 1.0) * 3.0
	pl.pitch_scale = _rng.randf_range(0.9, 1.05) * lerpf(1.0, 0.8, f)
	pl.play()
	if near and camera_shake and dist < 220.0:
		_shake = maxf(_shake, (1.0 - dist / 220.0) * 0.45)


func _update_camera_shake() -> void:
	if _cam == null or not camera_shake:
		return
	var s := _shake
	if _tor_active and player != null:
		var d := Vector2(player.global_position.x - _tor_pos.x, player.global_position.z - _tor_pos.z).length()
		s = maxf(s, (1.0 - clampf(d / (tornado_pull_radius * 1.4), 0.0, 1.0)) * 0.55 * _tor_size)
	if s > 0.003:
		_cam.h_offset = _rng.randf_range(-1.0, 1.0) * s * 0.12
		_cam.v_offset = _rng.randf_range(-1.0, 1.0) * s * 0.12
		_was_shaking = true
	elif _was_shaking:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
		_was_shaking = false

var _was_shaking := false


# =====================================================================================================
# TREES: sway in the wind, fall in storms, fall to lightning, tornadoes and soaked slopes (erosion)
# These work through the tree script's own tree lists, so no changes to sakura_trees.gd are needed.
# =====================================================================================================
var _swayed := {}

func _tree_cell(key: Vector2i, generate: bool) -> Variant:
	if trees == null or not ("_cells" in trees):
		return null
	var cells: Dictionary = trees._cells
	if cells.has(key):
		return cells[key]
	if generate and trees._logic_ready and trees._physics_ready:
		return trees._get_cell(key)
	return null


func _tree_origin(d: Dictionary, key: Vector2i, i: int) -> Vector3:
	var buf: PackedFloat32Array = d["buf"]
	var cc: Vector3 = trees._cell_centre(key)
	return cc + Vector3(buf[i * 12 + 3], buf[i * 12 + 7], buf[i * 12 + 11])


## Every standing tree within `radius` of pos: [cell key, tree number, distance].
func _trees_in_radius(pos: Vector3, radius: float, generate: bool) -> Array:
	var out: Array = []
	if trees == null or not ("_cells" in trees):
		return out
	var c: Vector2i = trees._cell_of(pos)
	var cs: float = trees.cell_size
	var span := int(ceil(radius / cs))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			var d = _tree_cell(key, generate)
			if d == null:
				continue
			var p2: PackedVector2Array = d["p2"]
			for i in p2.size():
				var q := p2[i]
				if q.x > 1e8:
					continue
				var dd := Vector2(q.x - pos.x, q.y - pos.z).length()
				if dd <= radius:
					out.append([key, i, dd])
	return out


func _set_cell_buffer(key: Vector2i, buf: PackedFloat32Array) -> void:
	var holder = trees._built.get(key)
	if holder != null and is_instance_valid(holder):
		for c in (holder as Node).get_children():
			if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh != null:
				(c as MultiMeshInstance3D).multimesh.buffer = buf


## Takes one tree out of the forest for good (it also stops being solid) and makes a falling copy of it.
## fling = a tornado picks it up. violent = struck by lightning (it topples hard).
func _fell_tree(key: Vector2i, i: int, push: Vector3, fling: bool, violent: bool, mud: bool = false) -> void:
	var d = _tree_cell(key, true)
	if d == null:
		return
	var dead: Dictionary = d["dead"] if d.has("dead") else {}
	if dead.has(i):
		return
	dead[i] = true
	d["dead"] = dead
	var buf: PackedFloat32Array = d["buf"]
	var o := i * 12
	var bas := Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]), Vector3(buf[o + 2], buf[o + 6], buf[o + 10]))
	var origin := _tree_origin(d, key, i)
	for idx in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
		buf[o + idx] = 0.0
	d["buf"] = buf
	var p2: PackedVector2Array = d["p2"]
	p2[i] = Vector2(1e9, 1e9)
	d["p2"] = p2
	_set_cell_buffer(key, buf)
	var body = trees._bodies.get(key)
	if body != null and is_instance_valid(body) and i < (body as Node).get_child_count():
		var cs = (body as Node).get_child(i)
		if cs is CollisionShape3D:
			(cs as CollisionShape3D).set_deferred("disabled", true)
	_swayed.erase(key)
	_spawn_prop(origin, bas, push, fling, violent)
	if mud:
		_burst(origin + Vector3(0, 0.2, 0), 30, Color(0.32, 0.24, 0.16), 1.0, 4.0, 1.2, 0.09, 8.0)


func _spawn_prop(origin: Vector3, bas: Basis, push: Vector3, fling: bool, violent: bool) -> void:
	if trees == null or trees._meshes.is_empty():
		return
	var mesh: Mesh = trees._meshes[0]
	var pivot := Node3D.new()
	pivot.top_level = true
	add_child(pivot)
	pivot.global_position = origin
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(bas, Vector3.ZERO)
	pivot.add_child(mi)
	var height := mesh.get_aabb().size.y * bas.get_scale().y
	var pd := Vector3(push.x, 0.0, push.z)
	if pd.length() < 0.01:
		pd = Vector3(1, 0, 0)
	pd = pd.normalized()
	var axis := Vector3.UP.cross(pd).normalized()
	var prop := {"node": pivot, "mi": mi, "mode": 2 if fling else 1, "axis": axis, "dir": pd, "th": 0.03, "om": 0.9 if violent else 0.1,
		"h": height, "age": 0.0, "hit": false, "vel": Vector3.ZERO, "angv": Vector3.ZERO, "pos": origin}
	if fling:
		mi.position = Vector3(0, -height * 0.45, 0)
		pivot.global_position = origin + Vector3(0, height * 0.45, 0)
		prop["pos"] = pivot.global_position
		prop["vel"] = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(4, 9), _rng.randf_range(-3, 3))
		prop["angv"] = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
	_props.append(prop)
	_burst(origin + Vector3(0, 0.3, 0), 16, Color(0.3, 0.24, 0.18), 1.5, 4.5, 0.9, 0.05, 9.8)
	while _props.size() > max_fallen_trees:
		_remove_prop(0)


func _remove_prop(idx: int) -> void:
	var p: Dictionary = _props[idx]
	var n = p["node"]
	if is_instance_valid(n):
		(n as Node).queue_free()
	_props.remove_at(idx)


func _crush(origin: Vector3, dir: Vector3, length: float) -> void:
	# anything under the trunk as it lands is hurt
	var a := Vector2(origin.x, origin.z)
	var b := a + Vector2(dir.x, dir.z) * length
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D:
			var p := (e as Node3D).global_position
			if absf(p.y - origin.y) < 6.0 and _dist_to_segment(Vector2(p.x, p.z), a, b) < 2.2:
				_hurt_enemy(e, falling_tree_damage, p)
	if player != null:
		var pp := player.global_position
		if absf(pp.y - origin.y) < 6.0 and _dist_to_segment(Vector2(pp.x, pp.z), a, b) < 2.0:
			_hurt_player(falling_tree_damage, pp)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _update_props(delta: float) -> void:
	var i := _props.size() - 1
	while i >= 0:
		var pr: Dictionary = _props[i]
		var node: Node3D = pr["node"]
		if not is_instance_valid(node):
			_props.remove_at(i)
			i -= 1
			continue
		var mode: int = pr["mode"]
		if mode == 1:
			var th: float = pr["th"]
			var om: float = pr["om"]
			th += om * delta
			om += 2.4 * sin(th + 0.15) * delta
			var origin: Vector3 = node.global_position
			if th > 1.0 and not pr["hit"]:
				pr["hit"] = true
				_crush(origin, pr["dir"], float(pr["h"]))
			if th >= 1.42:
				th = 1.42
				if absf(om) > 0.7:
					om = -om * 0.22
					_burst(origin + (pr["dir"] as Vector3) * float(pr["h"]) * 0.8, 14, Color(1.0, 0.75, 0.85), 1.0, 4.0, 1.0, 0.05, 2.0)
				else:
					om = 0.0
					pr["mode"] = 0
			pr["th"] = th
			pr["om"] = om
			node.global_transform = Transform3D(Basis(pr["axis"], th), origin)
		elif mode == 2 or mode == 3:
			var pos: Vector3 = pr["pos"]
			var vel: Vector3 = pr["vel"]
			pr["age"] = float(pr["age"]) + delta
			if mode == 2 and _tor_active and _tor_size > 0.05 and float(pr["age"]) < 9.0:
				var rel := Vector3(pos.x - _tor_pos.x, 0.0, pos.z - _tor_pos.z)
				var tang := Vector3(-rel.z, 0.0, rel.x).normalized()
				var f := _tor_size
				vel += (tang * 30.0 - rel.normalized() * 12.0 + Vector3.UP * 20.0) * f * delta
				vel *= (1.0 - 0.5 * delta)
				if pos.y > tornado_height * 0.55:
					pr["mode"] = 3
			else:
				pr["mode"] = 3
				vel.y -= 16.0 * delta
			pos += vel * delta
			pr["pos"] = pos
			pr["vel"] = vel
			var av: Vector3 = pr["angv"]
			var gb := node.global_transform.basis
			if av.length() > 0.001:
				gb = Basis(av.normalized(), av.length() * delta) * gb
			node.global_transform = Transform3D(gb, pos)
			if int(pr["mode"]) == 3:
				var gy := _ground_y(pos.x, pos.z, -1e5)
				if pos.y <= gy + 0.8 and vel.y < 0.0:
					# lands and lies there
					pr["mode"] = 0
					(pr["mi"] as Node3D).position = Vector3.ZERO
					node.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, deg_to_rad(84.0)), Vector3(pos.x, gy, pos.z))
					_burst(Vector3(pos.x, gy + 0.3, pos.z), 22, Color(0.4, 0.33, 0.25), 2.0, 7.0, 1.0, 0.08, 9.8)
					_crush(Vector3(pos.x, gy, pos.z), Vector3(1, 0, 0), 4.0)
		i -= 1


func _update_trees(delta: float) -> void:
	if trees == null or player == null:
		return
	_sway_timer += delta
	if _sway_timer >= 0.033:                    # about 30 updates a second; the motion itself is smoothed between them
		_sway(_sway_timer)
		_sway_timer = 0.0
	_topple_timer += delta
	if _topple_timer >= 2.0:
		var dt := _topple_timer
		_topple_timer = 0.0
		_topple_check(dt)


func _sway(dt: float) -> void:
	if not ("_built" in trees) or not ("_cells" in trees):
		return
	# The gusty wind speed is smoothed first, so the trees swell and ease with it instead of twitching.
	var target := clampf(wind_speed / 18.0, 0.0, 1.6) if tree_sway_degrees > 0.0 else 0.0
	_sway_smooth += (target - _sway_smooth) * (1.0 - exp(-dt * 1.6))
	var strength := _sway_smooth
	var built: Dictionary = trees._built
	var cells: Dictionary = trees._cells
	var pp := player.global_position
	var range1 := tree_sway_distance
	var amp := deg_to_rad(tree_sway_degrees) * strength
	var wd := wind_direction
	var side0 := Vector3(-wd.z, 0.0, wd.x)
	var t_s := _t
	# put back any cell that is out of range or no longer built, or everything once the wind has dropped
	for key in _swayed.keys():
		var cc0: Vector3 = trees._cell_centre(key)
		var dd := Vector2(cc0.x - pp.x, cc0.z - pp.z).length()
		if strength < 0.02 or dd > range1 * 1.15 or not built.has(key):
			if cells.has(key):
				_set_cell_buffer(key, (cells[key] as Dictionary)["buf"])
			_swayed.erase(key)
	if strength < 0.02:
		return
	for key in built:
		var holder = built[key]
		if holder == null or not is_instance_valid(holder) or not cells.has(key):
			continue
		var cc: Vector3 = trees._cell_centre(key)
		var dist := Vector2(cc.x - pp.x, cc.z - pp.z).length()
		if dist > range1:
			continue
		# Trees near the edge of the range sway less and less, so none of them pop in or out.
		var fade := 1.0 - smoothstep(range1 * 0.55, range1, dist)
		var camp := amp * fade
		if camp < 0.0015:
			if _swayed.has(key) and cells.has(key):
				_set_cell_buffer(key, (cells[key] as Dictionary)["buf"])
				_swayed.erase(key)
			continue
		var d: Dictionary = cells[key]
		var src: PackedFloat32Array = d["buf"]
		var out := src.duplicate()
		var n: int = d["n"]
		for i in n:
			var o := i * 12
			if src[o + 5] == 0.0:
				continue
			var phase := (src[o + 3] + cc.x) * 0.21 + (src[o + 11] + cc.z) * 0.17
			# a slow lean that swells and eases, a gentler faster flutter on top, and a slow side-to-side drift
			var a := camp * (0.6 + 0.4 * sin(t_s * 1.2 + phase)) + camp * 0.18 * sin(t_s * 2.9 + phase * 2.0)
			var dirv := (wd + side0 * (0.3 * sin(t_s * 1.7 + phase * 1.3))).normalized()
			var r := Basis(Vector3.UP.cross(dirv).normalized(), a)
			var bs := Basis(Vector3(src[o], src[o + 4], src[o + 8]), Vector3(src[o + 1], src[o + 5], src[o + 9]), Vector3(src[o + 2], src[o + 6], src[o + 10]))
			var b2 := r * bs
			out[o] = b2.x.x
			out[o + 1] = b2.y.x
			out[o + 2] = b2.z.x
			out[o + 4] = b2.x.y
			out[o + 5] = b2.y.y
			out[o + 6] = b2.z.y
			out[o + 8] = b2.x.z
			out[o + 9] = b2.y.z
			out[o + 10] = b2.z.z
		_set_cell_buffer(key, out)
		_swayed[key] = true


func _topple_check(dt: float) -> void:
	if not storm_damage_trees:
		return
	var windf := clampf((wind_speed - tree_fall_wind_speed) / 10.0, 0.0, 1.5)
	var erof := clampf((soil_saturation - 0.5) / 0.5, 0.0, 1.0) * clampf(rain_level * 2.0 + 0.2, 0.0, 1.0)
	if windf <= 0.0 and erof <= 0.0:
		return
	var near := _trees_in_radius(player.global_position, 100.0, false)
	var p_wind := tree_fall_rate * windf * dt
	var p_ero := erosion_rate * erof * dt
	for e in near:
		var r := _rng.randf()
		if r >= p_wind + p_ero:
			continue
		var key: Vector2i = e[0]
		var i: int = e[1]
		var d = _tree_cell(key, false)
		if d == null:
			continue
		var o := _tree_origin(d, key, i)
		if r < p_wind:
			var jit := Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
			_fell_tree(key, i, wind_direction + jit, false, false)
		else:
			# the soil gives way: only trees on a slope slide out, and they fall downhill
			var sx := _ground_y(o.x + 2.0, o.z, o.y) - _ground_y(o.x - 2.0, o.z, o.y)
			var sz := _ground_y(o.x, o.z + 2.0, o.y) - _ground_y(o.x, o.z - 2.0, o.y)
			if rad_to_deg(atan(sqrt(sx * sx + sz * sz) / 4.0)) > 9.0:
				_fell_tree(key, i, Vector3(-sx, 0, -sz), false, false, true)


# =====================================================================================================
# TORNADO
# =====================================================================================================
const TORNADO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float tm = 0.0;
uniform float vis = 1.0;
uniform float light_level = 1.0;
uniform float flash = 0.0;
varying float vt;
varying vec2 vuv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise_p(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, per);
	float x1 = mod(i.x + 1.0, per);
	return mix(mix(hash21(vec2(x0, i.y)), hash21(vec2(x1, i.y)), f.x), mix(hash21(vec2(x0, i.y + 1.0)), hash21(vec2(x1, i.y + 1.0)), f.x), f.y);
}
float fbm_p(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	float per = 8.0;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise_p(p, per);
		p = vec2(p.x * 2.0, p.y * 2.0 + 3.7);
		per *= 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	float t = clamp(VERTEX.y, 0.0, 1.0);
	vt = t;
	vuv = UV;
	VERTEX.x += sin(tm * 0.9 + t * 3.0) * t * 0.18;
	VERTEX.z += cos(tm * 0.7 + t * 2.3) * t * 0.18;
}

void fragment() {
	vec2 p = vec2(vuv.x * 8.0 + tm * (1.2 + (1.0 - vt) * 3.5), vt * 5.0 - tm * 0.9);
	float n = fbm_p(p);
	vec3 col = mix(vec3(0.15, 0.14, 0.13), vec3(0.5, 0.46, 0.41), n) * (0.12 + 0.88 * light_level);
	col = mix(col * 1.25, col, vt);
	float fres = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = (0.3 + 0.7 * n) * pow(clamp(fres, 0.0, 1.0), 0.45);
	a *= smoothstep(0.0, 0.05, vt) * (1.0 - smoothstep(0.86, 1.0, vt)) * vis;
	ALBEDO = col + vec3(0.7, 0.78, 1.0) * flash * 0.5;
	ALPHA = clamp(a, 0.0, 0.93);
}
"""
const DEBRIS_COUNT := 150
var _tor_flat := false

func _make_tornado() -> void:
	_tor = Node3D.new()
	_tor.top_level = true
	_tor.visible = false
	add_child(_tor)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 28
	var segs := 28
	for k in rings:
		for s in segs:
			var t0 := float(k) / rings
			var t1 := float(k + 1) / rings
			var u0 := float(s) / segs
			var u1 := float(s + 1) / segs
			_funnel_vertex(st, t0, u0)
			_funnel_vertex(st, t1, u0)
			_funnel_vertex(st, t1, u1)
			_funnel_vertex(st, t0, u0)
			_funnel_vertex(st, t1, u1)
			_funnel_vertex(st, t0, u1)
	var fm := MeshInstance3D.new()
	fm.mesh = st.commit()
	_tor_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TORNADO_SHADER
	_tor_mat.shader = sh
	fm.material_override = _tor_mat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fm.extra_cull_margin = 400.0
	_tor.add_child(fm)

	# debris circling in the funnel
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.25, 0.4)
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.roughness = 1.0
	bm.material = dm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = DEBRIS_COUNT
	_tor_debris = MultiMeshInstance3D.new()
	_tor_debris.multimesh = mm
	_tor_debris.top_level = true
	_tor_debris.visible = false
	_tor_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tor_debris.extra_cull_margin = 400.0
	add_child(_tor_debris)
	for i in DEBRIS_COUNT:
		var brown := _rng.randf_range(0.25, 0.55)
		var col := Color(brown, brown * 0.8, brown * 0.6) if _rng.randf() < 0.75 else Color(0.5, 0.2, 0.3)
		mm.set_instance_color(i, col)
		_tor_deb.append({"a": _rng.randf() * TAU, "t": _rng.randf_range(0.0, 0.5), "rf": _rng.randf_range(0.55, 1.15), "w": _rng.randf_range(1.2, 2.8),
			"v": _rng.randf_range(0.01, 0.045), "ax": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			"sp": _rng.randf_range(2.0, 7.0), "sz": _rng.randf_range(0.6, 2.2)})

	# a rolling dust skirt at the base
	var dq := QuadMesh.new()
	dq.size = Vector2(9.0, 9.0)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = _soft_dot_texture(64)
	dq.material = dmat
	_tor_dust = GPUParticles3D.new()
	_tor_dust.amount = 110
	_tor_dust.lifetime = 4.0
	_tor_dust.local_coords = false
	_tor_dust.visibility_aabb = AABB(Vector3(-70, -10, -70), Vector3(140, 80, 140))
	_tor_dust.draw_pass_1 = dq
	_tor_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = tornado_radius * 0.9
	pm.emission_ring_inner_radius = tornado_radius * 0.3
	pm.emission_ring_height = 1.0
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.8))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cg := Gradient.new()
	cg.colors = PackedColorArray([Color(0.36, 0.31, 0.26, 0.0), Color(0.36, 0.31, 0.26, 0.4), Color(0.3, 0.27, 0.24, 0.0)])
	cg.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	_tor_dust.process_material = pm
	_tor_dust.emitting = false
	_tor_dust.top_level = true
	add_child(_tor_dust)


func _funnel_vertex(st: SurfaceTool, t: float, u: float) -> void:
	var a := u * TAU
	var r := 0.30 + 0.70 * pow(t, 2.2)
	st.set_uv(Vector2(u, t))
	st.set_normal(Vector3(cos(a), 0.25, sin(a)).normalized())
	st.add_vertex(Vector3(cos(a) * r, t, sin(a) * r))


func _tor_top_radius() -> float:
	return tornado_radius * 3.3


func _tor_offset(t: float) -> Vector2:
	return Vector2(sin(_t * 0.9 + t * 3.0), cos(_t * 0.7 + t * 2.3)) * t * 0.18


## Summons a tornado some distance from you (it also switches the weather to tornado weather).
func _spawn_tornado() -> void:
	if _tor_active or not tornadoes_enabled or _tor == null:
		return
	var pp := player.global_position if player != null else global_position
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(170.0, 260.0)
	_tor_pos = pp + Vector3(cos(ang), 0.0, sin(ang)) * dist
	_tor_pos.y = _ground_y(_tor_pos.x, _tor_pos.z, pp.y)
	var to_p := pp - _tor_pos
	_tor_heading = atan2(to_p.z, to_p.x) + _rng.randf_range(-0.8, 0.8)
	_tor_age = 0.0
	_tor_size = 0.0
	_tor_active = true
	_tor.visible = true
	_tor_debris.visible = true
	if current_weather != "tornado":
		_apply_weather("tornado", true)
		_weather_timer = maxf(_weather_timer, tornado_lifetime)
		_manual_hold = maxf(_manual_hold, minf(tornado_lifetime, 60.0))


func _update_tornado(delta: float) -> void:
	if _tor == null:
		return
	if not _tor_active:
		return
	_tor_age += delta
	var alive := float(_tgt["tornado"]) > 0.5 and _tor_age < tornado_lifetime
	_tor_size = move_toward(_tor_size, 1.0 if alive else 0.0, delta / (14.0 if alive else 9.0))
	if not alive and _tor_size <= 0.0:
		_tor_active = false
		_tor.visible = false
		_tor_debris.visible = false
		_tor_dust.emitting = false
		return
	var pp := player.global_position if player != null else _tor_pos
	_tor_heading += _noise.get_noise_1d(_t * 0.08 + 200.0) * delta * 0.5
	var to_p := pp - _tor_pos
	var desired := atan2(to_p.z, to_p.x)
	_tor_heading += wrapf(desired - _tor_heading, -PI, PI) * tornado_player_bias * delta * 0.25
	_tor_pos += Vector3(cos(_tor_heading), 0.0, sin(_tor_heading)) * tornado_speed * delta
	_tor_pos.y = _ground_y(_tor_pos.x, _tor_pos.z, _tor_pos.y)
	if Vector2(to_p.x, to_p.z).length() > 650.0:
		_tor_age = tornado_lifetime + 1.0                       # wandered off: let it die

	var sc := clampf(_tor_size, 0.02, 1.0)
	var rad := _tor_top_radius() * (0.35 + 0.65 * sc)
	_tor.global_transform = Transform3D(Basis.from_scale(Vector3(rad, tornado_height * (0.5 + 0.5 * sc), rad)), _tor_pos - Vector3(0, 2.0, 0))
	_tor_mat.set_shader_parameter("tm", _t)
	_tor_mat.set_shader_parameter("vis", clampf(_tor_size * 1.3, 0.0, 1.0))
	_tor_mat.set_shader_parameter("light_level", _light_level)
	_tor_mat.set_shader_parameter("flash", _flash)

	_tor_dust.global_position = _tor_pos
	_tor_dust.emitting = _tor_size > 0.15
	_tor_dust.amount_ratio = clampf(_tor_size, 0.05, 1.0)

	# debris
	var mm := _tor_debris.multimesh
	var hh := tornado_height * (0.5 + 0.5 * sc)
	for i in DEBRIS_COUNT:
		var d: Dictionary = _tor_deb[i]
		var t: float = d["t"]
		t += float(d["v"]) * delta * 8.0
		if t > 0.62:
			t = 0.0
			d["a"] = _rng.randf() * TAU
		d["t"] = t
		var a: float = float(d["a"]) + float(d["w"]) * delta * (1.8 - t)
		d["a"] = a
		var r := (0.30 + 0.70 * pow(t, 2.2)) * rad * float(d["rf"])
		var off := _tor_offset(t) * rad
		var pos := _tor_pos + Vector3(cos(a) * r + off.x, t * hh, sin(a) * r + off.y)
		var bs := Basis(d["ax"], _t * float(d["sp"])) * Basis.from_scale(Vector3.ONE * float(d["sz"]) * clampf(_tor_size * 1.4, 0.0, 1.0))
		mm.set_instance_transform(i, Transform3D(bs, pos))


func _tornado_forces(delta: float) -> void:
	var R := tornado_pull_radius * _tor_size
	var core := tornado_radius * 1.3 * _tor_size
	var apply_dmg := _dmg_timer >= 0.5
	var bodies: Array = get_tree().get_nodes_in_group("enemy").duplicate()
	if player != null:
		bodies.append(player)
	for e in bodies:
		if not (e is CharacterBody3D):
			continue
		var cb := e as CharacterBody3D
		if cb.get("is_dead") == true:
			continue
		var rel := Vector3(cb.global_position.x - _tor_pos.x, 0.0, cb.global_position.z - _tor_pos.z)
		var d := rel.length()
		if d >= R or d < 0.01:
			continue
		var f := 1.0 - d / R
		var is_player := (cb == player)
		var move := (-rel.normalized() * 9.0 + Vector3(-rel.z, 0.0, rel.x).normalized() * 10.0) * f * f * delta * (0.7 if is_player else 1.0)
		cb.move_and_collide(move)
		if d < core * 1.7:
			cb.velocity.y = maxf(cb.velocity.y, 10.0 * (1.0 - d / (core * 1.7)) + 2.0)
		if apply_dmg and d < core * 1.4:
			if is_player:
				_hurt_player(tornado_damage * 0.5, cb.global_position)
			else:
				_hurt_enemy(cb, tornado_damage * 0.5, cb.global_position)
	if storm_damage_trees and _tor_fling_timer <= 0.0:
		_tor_fling_timer = 0.3
		var cnt := 0
		for e in _trees_in_radius(_tor_pos, core * 1.8 + 6.0, false):
			if cnt >= 3:
				break
			var d2 = _tree_cell(e[0], false)
			if d2 == null:
				continue
			_fell_tree(e[0], int(e[1]), Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), true, false)
			cnt += 1
	_tor_fling_timer -= delta


# =====================================================================================================
# PHYSICS-RATE WEATHER EFFECTS ON CREATURES
# =====================================================================================================
var _sight_timer := 0.0

func _physics_process(delta: float) -> void:
	if not weather_enabled:
		return
	_dmg_timer += delta
	if _tor_active and _tor_size > 0.2 and (weather_hurts_enemies or weather_hurts_player):
		_tornado_forces(delta)
	elif _tor_active:
		_tor_fling_timer -= delta

	# wind pushing creatures around
	if wind_pushes_creatures > 0.0 and wind_speed > 6.0:
		var push := wind_direction * wind_pushes_creatures * clampf((wind_speed - 6.0) / 20.0, 0.0, 1.4) * delta
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is CharacterBody3D and e.get("is_dead") != true:
				(e as CharacterBody3D).move_and_collide(push)
		if player is CharacterBody3D:
			(player as CharacterBody3D).move_and_collide(push)

	# hail hurts anything caught outside
	_hail_timer += delta
	if _hail_timer >= 1.0:
		_hail_timer = 0.0
		var hail: float = _cur["hail"]
		if hail > 0.3:
			for e in get_tree().get_nodes_in_group("enemy"):
				if e is Node3D and not _sheltered(e as Node3D):
					_hurt_enemy(e, hail_damage * hail, (e as Node3D).global_position)
			if player != null and not _sheltered(player):
				_hurt_player(hail_damage * hail, player.global_position)

	# bad weather shortens how far the enemies can see
	_sight_timer += delta
	if _sight_timer >= 0.5:
		_sight_timer = 0.0
		var vis := maxf(float(_cur["fog"]), maxf(float(_cur["rain"]) * 0.6, maxf(float(_cur["snow"]) * 0.7, float(_cur["hail"]) * 0.5)))
		var factor := lerpf(1.0, 0.45, clampf(vis, 0.0, 1.0)) if weather_limits_enemy_sight else 1.0
		for e in get_tree().get_nodes_in_group("enemy"):
			if not ("sight_range" in e):
				continue
			if not e.has_meta("wx_sight"):
				e.set_meta("wx_sight", e.get("sight_range"))
			e.set("sight_range", float(e.get_meta("wx_sight")) * factor)
	if _dmg_timer >= 0.5:
		_dmg_timer = 0.0


# =====================================================================================================
# PUDDLES (rain pools on flat ground and dries out afterwards)
# =====================================================================================================
const PUDDLE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;
uniform float amount = 0.0;
uniform float rain = 0.0;
uniform float tm = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float wob = vnoise(UV * 6.0) * 0.35 + vnoise(UV * 13.0 + 4.0) * 0.12;
	float r = length(p) + wob - 0.25;
	float edge = 1.0 - smoothstep(0.55, 0.95, r);
	vec2 nrm = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 g = UV * (7.0 + float(k) * 4.0) + float(k) * 13.7;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float ph = fract(hash21(id) + tm * (0.9 + 0.3 * float(k)));
		vec2 c = (vec2(hash21(id + 7.0), hash21(id + 11.0)) - 0.5) * 0.5;
		float d = length(f - c);
		float ring = sin((d - ph * 0.5) * 40.0) * smoothstep(0.5, 0.0, d) * (1.0 - ph) * step(hash21(id + 3.0), rain * 0.9 + 0.04);
		nrm += normalize(f - c + 0.001) * ring * 0.35;
	}
	ALBEDO = vec3(0.04, 0.05, 0.06);
	ROUGHNESS = 0.04;
	SPECULAR = 0.85;
	METALLIC = 0.0;
	NORMAL_MAP = vec3(0.5 + nrm.x * 0.5, 0.5 + nrm.y * 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	ALPHA = clamp(edge * amount * 0.85, 0.0, 1.0);
}
"""

func _make_puddle_material() -> void:
	_pud_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PUDDLE_SHADER
	_pud_mat.shader = sh


func _update_puddles(delta: float) -> void:
	if not puddles or terrain == null or player == null or _pud_mat == null:
		return
	_pud_mat.set_shader_parameter("amount", smoothstep(0.04, 0.45, wetness))
	_pud_mat.set_shader_parameter("rain", rain_level)
	_pud_mat.set_shader_parameter("tm", _t)
	_pud_timer -= delta
	if _pud_timer > 0.0:
		return
	_pud_timer = 0.7
	if wetness < 0.04 and _pud_nodes.is_empty():
		return
	var grid := 12.0
	var pp := player.global_position
	var cx := int(floor(pp.x / grid))
	var cz := int(floor(pp.z / grid))
	var span := int(ceil(puddle_distance / grid))
	var keep := {}
	if wetness >= 0.04:
		for gx in range(cx - span, cx + span + 1):
			for gz in range(cz - span, cz + span + 1):
				var key := Vector2i(gx, gz)
				var h := hash(key)
				if float(h & 0xFFFF) / 65535.0 > 0.38:
					continue
				var px := (float(gx) + 0.15 + 0.7 * float((h >> 16) & 0xFF) / 255.0) * grid
				var pz := (float(gz) + 0.15 + 0.7 * float((h >> 24) & 0xFF) / 255.0) * grid
				if Vector2(px - pp.x, pz - pp.z).length() > puddle_distance:
					continue
				keep[key] = true
				if _pud_nodes.has(key):
					continue
				var rr := 1.3 + 2.4 * float((h >> 8) & 0xFF) / 255.0
				var y0 := _ground_y(px, pz, pp.y)
				var nrm := Vector3(_ground_y(px - 1.5, pz, y0) - _ground_y(px + 1.5, pz, y0), 3.0, _ground_y(px, pz - 1.5, y0) - _ground_y(px, pz + 1.5, y0)).normalized()
				if nrm.y < 0.985:
					_pud_nodes[key] = null                  # too steep for water to sit
					keep[key] = true
					continue
				var pm := PlaneMesh.new()
				pm.size = Vector2(rr * 2.0, rr * 2.0)
				var mi := MeshInstance3D.new()
				mi.mesh = pm
				mi.material_override = _pud_mat
				mi.top_level = true
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				mi.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, nrm)) * Basis(Vector3.UP, float(h & 0xFF) / 40.0), Vector3(px, y0 + 0.04, pz))
				_pud_nodes[key] = mi
	for key in _pud_nodes.keys():
		if not keep.has(key):
			var n = _pud_nodes[key]
			if n != null and is_instance_valid(n):
				(n as Node).queue_free()
			_pud_nodes.erase(key)


# =====================================================================================================
# SOUND (generated in code: rain, wind, thunder)
# =====================================================================================================
func _generate_audio() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var th: Array = []
	th.append(_synth_thunder(rng, 11025, 7.0, true))
	th.append(_synth_thunder(rng, 11025, 8.5, false))
	th.append(_synth_thunder(rng, 11025, 6.5, false))
	_audio_data = {"thunder": th, "rain": _synth_loop(rng, 22050, 3.0, 0), "wind": _synth_loop(rng, 11025, 5.0, 1)}
	_audio_thread_done = true


func _to_pcm16(s: PackedFloat32Array, gain: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	return b


func _synth_thunder(rng: RandomNumberGenerator, rate: int, dur: float, crack: bool) -> PackedByteArray:
	var n := int(rate * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var bumps: Array = []
	for k in 7:
		bumps.append(Vector3(rng.randf_range(0.4, dur * 0.7), rng.randf_range(0.2, 0.7), rng.randf_range(0.25, 1.0)))
	var lp1 := 0.0
	var lp2 := 0.0
	var peak := 0.0001
	for i in n:
		var t := float(i) / rate
		var nz := rng.randf() * 2.0 - 1.0
		lp1 += (nz - lp1) * 0.07
		lp2 += (lp1 - lp2) * 0.07
		var env := (1.0 - exp(-t / 0.3)) * exp(-t / (dur * 0.3))
		var bump := 0.5
		for b in bumps:
			var x: float = (t - b.x) / b.y
			bump += b.z * exp(-x * x) * 0.7
		var v := lp2 * 9.0 * env * bump
		if crack:
			v += (nz - lp1) * exp(-t * 16.0) * 0.9 + lp1 * 3.5 * exp(-t * 5.0)
		if t > dur - 0.4:
			v *= (dur - t) / 0.4
		s[i] = v
		peak = maxf(peak, absf(v))
	return _to_pcm16(s, 0.92 / peak)


## A loop with no seam: kind 0 = rain hiss, kind 1 = wind.
func _synth_loop(rng: RandomNumberGenerator, rate: int, dur: float, kind: int) -> PackedByteArray:
	var n := int(rate * dur)
	var fade := int(rate * 0.2)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var a := 0.0
	var b := 0.0
	var c := 0.0
	var peak := 0.0001
	for i in n + fade:
		var nz := rng.randf() * 2.0 - 1.0
		var v := 0.0
		if kind == 0:
			a += (nz - a) * 0.55
			b += (nz - b) * 0.09
			v = (nz - a) * 0.55 + b * 0.9
			if rng.randf() < 0.004:
				v += rng.randf_range(-0.9, 0.9)
		else:
			a += (nz - a) * 0.035
			b += (a - b) * 0.05
			c += (nz - c) * 0.3
			var t := float(i) / rate
			var m := 0.65 + 0.35 * sin(TAU * t * 2.0 / dur) * sin(TAU * t * 3.0 / dur + 1.0)
			v = (b * 7.0 + (c - a) * 0.25 * (0.5 + 0.5 * sin(TAU * t * 5.0 / dur))) * m
		raw[i] = v
		peak = maxf(peak, absf(v))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := raw[i]
		if i < fade:
			var k := float(i) / fade
			v = raw[i] * k + raw[n + i] * (1.0 - k)
		out[i] = v
	return _to_pcm16(out, 0.85 / peak)


func _wav_from(data: PackedByteArray, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w


func _build_audio() -> void:
	_audio_built = true
	if not sound_enabled:
		return
	for d in _audio_data["thunder"]:
		_wav_thunder.append(_wav_from(d, 11025, false))
	_wav_rain = _wav_from(_audio_data["rain"], 22050, true)
	_wav_wind = _wav_from(_audio_data["wind"], 11025, true)
	_snd_rain = _loop_player(_wav_rain)
	_snd_wind = _loop_player(_wav_wind)
	_snd_tor = _loop_player(_wav_wind)
	_snd_tor.pitch_scale = 0.55
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_snd_thunder.append(p)


func _loop_player(w: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = w
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func _update_audio(_delta: float) -> void:
	if not _audio_built or _snd_rain == null:
		return
	var rain_v := clampf(float(_cur["rain"]) * 0.85 + float(_cur["hail"]) * 0.7 + float(_cur["snow"]) * 0.08, 0.0, 1.0)
	_snd_rain.volume_db = linear_to_db(maxf(rain_v * 0.65, 0.0001))
	var wind_v := clampf((wind_speed - 3.0) / 24.0, 0.0, 1.0)
	_snd_wind.volume_db = linear_to_db(maxf(wind_v * 0.8, 0.0001))
	_snd_wind.pitch_scale = 0.8 + 0.4 * wind_v
	var tv := 0.0
	if _tor_active and player != null:
		var d := Vector2(player.global_position.x - _tor_pos.x, player.global_position.z - _tor_pos.z).length()
		tv = clampf(1.0 - d / (tornado_pull_radius * 5.0), 0.0, 1.0) * _tor_size
	_snd_tor.volume_db = linear_to_db(maxf(tv * tv * 1.0, 0.0001))
