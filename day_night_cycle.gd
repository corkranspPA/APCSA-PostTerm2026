extends Node3D

# -------------------------
# REFERENCES (same slots as before — your scene assignments still work)
# -------------------------
@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_env: WorldEnvironment
@export var stars: GPUParticles3D
@export var moon_halo: MeshInstance3D

# -------------------------
# SPRITES (NEW) — drag sun.png / moon.png into these slots
# -------------------------
@export var sun_texture: Texture2D
@export var moon_texture: Texture2D
@export var sun_size_degrees := 9.0           # how big the sun looks in the sky (angular size)
@export var moon_size_degrees := 8.0
@export var sprite_distance := 900.0          # how far away the sprites sit. Must be LESS than your camera's Far value (default 4000)

# -------------------------
# TIME
# -------------------------
@export var cycle_speed: float = 60.0         # seconds for one full day (60 = a one-minute day)
@export_range(0.0, 1.0) var start_time := 0.3 # 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
@export var running := true

# -------------------------
# SUN / MOON PATH + LIGHT
# -------------------------
@export var sun_path_yaw_degrees := 30.0      # turns the whole sun/moon path around the world (which way is "east")
@export var sun_path_tilt_degrees := 20.0     # leans the path, so noon isn't exactly overhead
@export var sun_energy := 2.5
@export var moon_energy := 0.6

# -------------------------
# AMBIENT / SKY LOOK
# -------------------------
@export var day_ambient_energy := 0.8
@export var night_ambient_energy := 0.18      # raise this if nights are too dark to see
@export var night_sky_energy := 0.5
@export var day_top_color := Color(0.35, 0.6, 1.0)
@export var day_horizon_color := Color(0.65, 0.82, 1.0)
@export var night_top_color := Color(0.01, 0.015, 0.07)
@export var night_horizon_color := Color(0.04, 0.06, 0.16)
@export var sunset_color := Color(1.0, 0.35, 0.12)
@export var moon_light_color := Color(0.6, 0.7, 1.0)

var time: float = 0.0

var sun_sprite: Sprite3D
var moon_sprite: Sprite3D
var sky_mat: ProceduralSkyMaterial
var halo_base_scale := Vector3.ONE


# -------------------------
# START
# -------------------------
func _ready() -> void:
	time = start_time

	if sun == null:
		push_warning("Day/Night: Sun is NOT assigned in the Inspector")
	if moon == null:
		push_warning("Day/Night: Moon is NOT assigned in the Inspector")

	# The sprites ARE the sun and moon now, so stop the procedural sky from drawing its own discs.
	for l in [sun, moon]:
		if l:
			l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY

	if moon_halo:
		halo_base_scale = moon_halo.scale

	sun_sprite = _make_sprite(sun_texture, sun_size_degrees)
	moon_sprite = _make_sprite(moon_texture, moon_size_degrees)
	_setup_environment()
	update_sun_and_moon()


## Makes sure the world uses a real sky (the old script forced a flat black background, so the sky and its
## colours were never visible), and that ambient light comes from that sky.
func _setup_environment() -> void:
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	if env.sky == null:
		env.sky = Sky.new()
	if not (env.sky.sky_material is ProceduralSkyMaterial):
		env.sky.sky_material = ProceduralSkyMaterial.new()
	sky_mat = env.sky.sky_material as ProceduralSkyMaterial


func _make_sprite(tex: Texture2D, size_degrees: float) -> Sprite3D:
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.double_sided = true
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # keeps the pixel art crisp
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.top_level = true                                          # positioned in world space, not relative to this node
	s.pixel_size = 2.0 * sprite_distance * tan(deg_to_rad(size_degrees) * 0.5) / float(maxi(tex.get_width(), tex.get_height()))
	add_child(s)
	return s


# -------------------------
# LOOP
# -------------------------
func _process(delta: float) -> void:
	if running:
		time = fposmod(time + delta / maxf(cycle_speed, 0.01), 1.0)
	update_sun_and_moon()


## Jump to a time of day (0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset).
func set_time_of_day(t: float) -> void:
	time = fposmod(t, 1.0)
	update_sun_and_moon()


# -------------------------
# ☀️ SUN + 🌙 MOON
# -------------------------
func update_sun_and_moon() -> void:
	var angle: float = (time * TAU) - PI * 0.5
	var height: float = sin(angle)   # +1 = sun straight up (noon), -1 = straight down (midnight)

	# Direction from the world TO the sun. The path is built as a vector (not Euler angles), because
	# setting rotation_degrees.x past +-90 flips the other axes and made the sun jump around.
	var path := Basis(Vector3.UP, deg_to_rad(sun_path_yaw_degrees)) * Basis(Vector3.BACK, deg_to_rad(sun_path_tilt_degrees))
	var to_sun: Vector3 = (path * Vector3(0.0, sin(angle), cos(angle))).normalized()
	var side: Vector3 = path * Vector3.RIGHT      # always perpendicular to the sun's path, so looking_at never degenerates
	var to_moon: Vector3 = -to_sun

	# ---------------- LIGHTS ----------------
	var sun_amount := smoothstep(-0.05, 0.2, height)      # 0 below the horizon, 1 once it's well up
	var moon_amount := smoothstep(-0.05, 0.25, -height)

	if sun:
		_aim_light(sun, -to_sun, side)
		sun.light_energy = sun_energy * sun_amount
		sun.light_color = sunset_color.lerp(Color.WHITE, smoothstep(0.0, 0.5, height))
		sun.visible = sun.light_energy > 0.01             # no light (and no shadow cost) while it's below the horizon

	if moon:
		_aim_light(moon, -to_moon, side)
		moon.light_energy = moon_energy * moon_amount
		moon.light_color = moon_light_color
		moon.visible = moon.light_energy > 0.01

	# ---------------- SKY / WORLD ----------------
	update_night_darkness(height)
	update_sky_colors(height)

	# ---------------- THINGS THAT FOLLOW THE CAMERA ----------------
	var cam := get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam else global_position

	_place_sprite(sun_sprite, to_sun, cam_pos, smoothstep(-0.08, 0.05, height))
	_place_sprite(moon_sprite, to_moon, cam_pos, smoothstep(-0.08, 0.05, -height))
	update_moon_halo(height, to_moon, cam_pos)
	update_stars(height, cam_pos)


## Points a DirectionalLight3D so its light travels along `travel_dir`.
func _aim_light(light: DirectionalLight3D, travel_dir: Vector3, up_hint: Vector3) -> void:
	var t := light.global_transform
	t.basis = Basis.looking_at(travel_dir, up_hint)
	light.global_transform = t


func _place_sprite(s: Sprite3D, dir: Vector3, cam_pos: Vector3, alpha: float) -> void:
	if s == null:
		return
	s.visible = alpha > 0.01
	s.global_position = cam_pos + dir * sprite_distance
	s.modulate.a = alpha


# -------------------------
# 🌑 AMBIENT LIGHT
# -------------------------
func update_night_darkness(height: float) -> void:
	if world_env == null or world_env.environment == null:
		return
	var day_t := smoothstep(-0.12, 0.35, height)
	world_env.environment.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, day_t)


# -------------------------
# 🌅 SKY COLOURS
# -------------------------
func update_sky_colors(height: float) -> void:
	if sky_mat == null:
		return

	var day_t := smoothstep(-0.12, 0.35, height)
	# Peaks right as the sun crosses the horizon (a touch below it), for the sunrise/sunset glow.
	var glow := 1.0 - smoothstep(0.0, 0.35, absf(height + 0.03))

	var top := night_top_color.lerp(day_top_color, day_t)
	var horizon := night_horizon_color.lerp(day_horizon_color, day_t).lerp(sunset_color, glow * 0.85)

	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = top.darkened(0.6)
	sky_mat.sky_energy_multiplier = lerpf(night_sky_energy, 1.0, day_t)


# -------------------------
# 🌌 STARS
# -------------------------
func update_stars(height: float, cam_pos: Vector3) -> void:
	if stars == null:
		return
	var is_night: bool = height < -0.05
	stars.global_position = cam_pos      # keeps the star field around you, so you can never walk out of it
	if stars.emitting != is_night:
		stars.emitting = is_night
	stars.visible = is_night


# -------------------------
# 🌙 MOON HALO
# -------------------------
func update_moon_halo(height: float, to_moon: Vector3, cam_pos: Vector3) -> void:
	if moon_halo == null:
		return
	var night_factor: float = clampf(-height, 0.0, 1.0)
	moon_halo.visible = night_factor > 0.2
	moon_halo.scale = halo_base_scale * lerpf(1.0, 2.5, night_factor)
	# Sit just behind the moon sprite, facing the camera.
	moon_halo.global_position = cam_pos + to_moon * (sprite_distance + 5.0)
	if absf(to_moon.dot(Vector3.UP)) < 0.99:
		moon_halo.look_at(cam_pos, Vector3.UP)
