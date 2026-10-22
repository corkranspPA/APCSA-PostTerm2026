extends Node3D

# -------------------------
# REFERENCES (anything left empty is found automatically)
# -------------------------
@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_env: WorldEnvironment
@export var stars: GPUParticles3D          # optional old particle stars (hidden while use_shader_stars is on)
@export var moon_halo: MeshInstance3D

# -------------------------
# SPRITES (your own textures, nothing new is drawn for the sun or moon)
# -------------------------
@export var sun_texture: Texture2D
@export var moon_texture: Texture2D
@export var sun_texture_path := "res://sun.png"
@export var moon_texture_path := "res://moon.png"
@export var sun_size_degrees := 9.0           # how big the sun looks in the sky (angular size)
@export var moon_size_degrees := 8.0
@export var sprite_distance := 900.0          # must be LESS than your camera's Far value (default 4000)

# -------------------------
# AURA — a soft coloured hue around the sun and the moon, no ring, no hard edges
# -------------------------
@export var sun_aura_color := Color(1.0, 0.7, 0.25)
@export var moon_aura_color := Color(0.16, 0.72, 0.45)   # the moon's ring: a mix of jade (#00A86B) and emerald (#50C878)
@export var aura_size_degrees := 16.0         # how far the tint spreads out past the sprite's edge (bigger = wider, softer vignette)
@export var aura_intensity := 0.35            # overall strength of the tint (0 = off)
@export_range(0.0, 1.0) var moon_aura_strength := 0.25   # moon glow as a fraction of the sun's (0.25 = a quarter as strong, 0 = no moon glow)
@export var aura_falloff := 1.5               # higher = tint stays tight to the object, lower = spreads wider and flatter

# -------------------------
# STARS — drawn right in the sky, so they always surround you and twinkle
# -------------------------
@export var use_shader_stars := true
@export var star_color := Color(0.85, 0.92, 1.0)
@export var star_density := 70.0              # higher = smaller, more tightly packed grid
@export var star_size := 0.18                 # bigger stars
@export var star_chance := 0.1                # how many grid cells hold a star (more = more stars)
@export var star_twinkle := 0.5               # 0 = steady, 1 = strong twinkle

# -------------------------
# DIM LIGHTS — the sun glow, moon glow and the stars each cast a faint light of their own
# -------------------------
@export var dim_lights_enabled := true
@export var aura_light_energy := 0.25         # light from the sun glow / moon glow (tinted their glow colour)
@export var star_light_energy := 0.12         # faint cool light from the stars at night
@export var star_light_color := Color(0.7, 0.8, 1.0)

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
# AMBIENT / SKY LOOK (the raw colours; the dusk grade below is applied on top of these)
# -------------------------
@export var day_ambient_energy := 0.8
@export var night_ambient_energy := 0.18      # raise this if nights are too dark to see
@export var night_sky_energy := 0.5
@export var day_top_color := Color(0.35, 0.6, 1.0)
@export var day_horizon_color := Color(0.65, 0.82, 1.0)
@export var night_top_color := Color(0.01, 0.015, 0.07)
@export var night_horizon_color := Color(0.04, 0.06, 0.16)
@export var sunset_color := Color(1.0, 0.35, 0.12)
@export var moon_light_color := Color(0.15, 0.78, 0.5)   # emerald (#50C878) mixed with jade (#00A86B)
@export var glow_spread := 3.0                # sunrise/sunset glow: higher = narrower patch around the sun
@export var glow_height := 6.0                # higher = glow hugs the horizon more tightly

# =====================================================================================================
# NATURAL DUSK LIGHTING (merged in from natural_dusk.gd; no fog). Every part of the light is driven by how high
# the sun is: low sun = long shadows, dried-blood red-orange light, cool fill, warm ground bounce. Bloodborne-style
# greyed colours by day, greyed moonlit blue by night. Runs inside this script, right after the sky values are set.
# =====================================================================================================
@export_group("Dusk look")
@export var dusk_look_enabled := true              # master switch: off = the raw sky_cycle look, nothing graded
@export_range(0.0, 1.0) var dusk_strength := 1.0   # 0 = off, 1 = full dusk look
@export_range(0.1, 1.0) var dusk_max_height := 0.45 # caps how "high noon" the grading ever gets (lower = warmer all day)
@export_range(0.0, 1.0) var color_muting := 0.2    # 0 = original vibrant colours, 1 = grey light

@export_group("Dusk: day / night grade")
@export var day_tint := Color(0.76, 0.74, 0.7)              # faint sepia-grey the daytime light is pulled toward
@export_range(0.0, 1.0) var day_tint_amount := 0.35
@export_range(0.0, 1.0) var day_extra_greying := 0.2        # extra greying on top of color_muting, daytime only
@export var day_ambient_color := Color(0.42, 0.47, 0.56)    # cool slate-blue fill in the shadows by day
@export var day_saturation := 0.85                          # overall picture saturation by day
@export var night_ambient_color := Color(0.15, 0.16, 0.2)   # grey-blue fill in the shadows by night
@export var night_moon_color := Color(0.68, 0.7, 0.76)      # near-grey pale blue moonlight
@export_range(0.0, 1.0) var night_moon_color_amount := 1.0  # 0 = keep moon_light_color (green), 1 = fully night_moon_color
@export_range(0.0, 1.0) var night_glow_light_amount := 0.9  # how much the moon-glow and star lights turn to the same pale blue
@export_range(0.0, 1.0) var night_moon_greying := 0.8       # dulls the moonlight and the moon-glow / star lights (higher = greyer)
@export var night_saturation := 0.5                         # overall picture saturation by night (lower = greyer)

@export_group("Dusk: sky grade")
@export var grade_sky := true                               # gives the sky, glow and aura colours the same hue
@export_range(0.0, 1.0) var sky_greying := 0.2
@export_range(0.0, 1.0) var sky_night_extra_greying := 0.6  # extra greying of the night sky and glow (night only)
@export_range(0.0, 1.0) var moon_ring_night_greying := 0.3  # lightly mutes the moon's jade/emerald ring at night (0 = full colour)
@export var sky_day_tint := Color(0.78, 0.74, 0.68)
@export_range(0.0, 1.0) var sky_day_tint_amount := 0.18
@export var sky_night_tint := Color(0.2, 0.23, 0.3)
@export_range(0.0, 1.0) var sky_night_tint_amount := 0.35
@export_range(0.0, 1.0) var sky_moon_aura_to_blue := 0.9    # turns the green glow around the moon pale blue
@export_range(0.0, 1.0) var sky_blood_glow := 0.25          # pulls the sunset glow toward dried-blood red

@export_group("Dusk: sun and fill light")
@export var sun_color_ramp: Gradient                        # sun colour by height (left = horizon/twilight, right = high sun)
@export var sun_brightness := 0.65                          # sun strength multiplier
@export var moon_brightness := 0.7                          # moon strength multiplier (colour is set by night_moon_color)
@export var ambient_color_ramp: Gradient                    # shadow fill colour by sun height
@export var ambient_energy_low := 0.55
@export var ambient_energy_high := 0.9
@export var sky_fill_color := Color(0.42, 0.5, 0.68)        # cold slate light from above
@export var sky_fill_energy := 0.18
@export var ground_bounce_color := Color(0.8, 0.42, 0.26)   # dull dried-blood glow bouncing up off the ground
@export var ground_bounce_energy := 0.22

@export_group("Dusk: shadows")
@export var shadow_max_distance := 120.0
@export var shadow_blur := 1.6
@export var shadow_bias := 0.04
@export var shadow_normal_bias := 1.5
@export var penumbra_low_sun := 2.2                         # soft shadow edge (degrees) with the sun on the horizon
@export var penumbra_high_sun := 1.0

@export_group("Dusk: colour / contact shadows / glow")
@export var exposure := 0.9
@export var tonemap_white := 6.0
@export var saturation := 0.82                              # dusk saturation (day and night have their own above)
@export var contrast := 0.98
@export var ssao_enabled := true
@export var ssil_enabled := true                            # cheap screen-space bounce light
@export var sdfgi_enabled := false                          # real bounce light everywhere; Forward+ only, costs more
@export var glow_enabled := true
@export var glow_intensity := 0.45
@export var glow_hdr_threshold := 1.0

# -------------------------
# NIGHT VISION — a gentle help so you can still see at night. It only works when the sun is down.
# -------------------------
@export_group("Night vision")
@export var night_vision_enabled := true
@export_range(0.0, 1.0) var night_vision_strength := 0.6    # 0 = off, 1 = strong. Raise this if nights are still too dark.
@export var night_vision_ambient_boost := 0.5               # extra shadow-fill light at night (at strength 1)
@export var night_vision_exposure_boost := 0.5              # brightens the whole picture a little at night (at strength 1)
@export var night_vision_light_energy := 0.8                # soft pale light around the player (at strength 1)
@export var night_vision_light_range := 18.0                # how far that light reaches, in metres
@export var night_vision_color := Color(0.74, 0.76, 0.82)   # near-neutral pale grey, so the area around you is grey
@export var night_vision_toggle_action := ""                # optional: an Input Map action name that switches it on/off (e.g. "night_vision")

var time: float = 0.0
var _nv_light: OmniLight3D
var _nv_base_exposure := -1.0
var _nv_on := true

var sun_sprite: Sprite3D
var moon_sprite: Sprite3D
var sky_mat: ShaderMaterial
var halo_base_scale := Vector3.ONE

var sun_aura_light: DirectionalLight3D
var moon_aura_light: DirectionalLight3D
var star_light: DirectionalLight3D

var _sky_fill: DirectionalLight3D
var _bounce: DirectionalLight3D


# The sky itself. Written as a shader so the sunrise glow can sit on ONE side of the sky (where the sun is),
# and so it can also draw the stars and the soft glow around the sun and moon.
const SKY_SHADER := """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.35, 0.6, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.65, 0.82, 1.0);
uniform vec3 ground_color : source_color = vec3(0.1, 0.12, 0.15);
uniform float sky_energy = 1.0;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);

uniform vec3 glow_color : source_color = vec3(1.0, 0.35, 0.12);
uniform float glow_amount = 0.0;
uniform float glow_spread = 3.0;
uniform float glow_height = 6.0;

uniform vec3 sun_aura_color : source_color = vec3(1.0, 0.7, 0.25);
uniform vec3 moon_aura_color : source_color = vec3(0.25, 0.95, 0.65);
uniform float sun_aura_amount = 0.0;
uniform float moon_aura_amount = 0.0;
uniform float sun_radius = 0.08;
uniform float moon_radius = 0.07;
uniform float aura_size = 0.12;
uniform float aura_falloff = 2.0;

uniform float star_amount = 0.0;
uniform vec3 star_color : source_color = vec3(0.85, 0.92, 1.0);
uniform float star_density = 70.0;
uniform float star_size = 0.18;
uniform float star_chance = 0.1;
uniform float star_twinkle = 0.5;

float hash31(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float star_field(vec3 dir) {
	vec3 p = dir * star_density;
	vec3 cell = floor(p);
	vec3 local = fract(p);
	if (hash31(cell + 17.0) > star_chance) {
		return 0.0;
	}
	vec3 center = 0.2 + 0.6 * hash33(cell);
	float size = star_size * (0.5 + hash31(cell + 3.0));
	float d = length(local - center);
	float shape = 1.0 - smoothstep(0.0, size, d);
	float speed = 1.0 + 3.0 * hash31(cell + 9.0);
	float phase = 6.2831 * hash31(cell + 5.0);
	float twinkle = 1.0 - star_twinkle * (0.5 + 0.5 * sin(TIME * speed + phase));
	return shape * twinkle * (0.4 + 0.6 * hash31(cell + 1.0));
}

// A smooth hue that is strongest at the object's edge and fades to nothing, with no ring and no steps.
float aura_shape(vec3 dir, vec3 center, float radius) {
	float ang = acos(clamp(dot(dir, center), -1.0, 1.0));
	float x = clamp((ang - radius) / max(aura_size, 0.0001), 0.0, 1.0);
	float t = 1.0 - x;
	t = t * t * (3.0 - 2.0 * t);          // smooth the start and the end of the fade
	return pow(t, aura_falloff);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;

	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	// Sunrise / sunset glow: only on the side of the sky the sun is on, and hugging the horizon.
	vec2 d2 = dir.xz;
	vec2 s2 = sun_dir.xz;
	float side = 0.0;
	if (length(d2) > 0.001 && length(s2) > 0.001) {
		side = pow(max(dot(normalize(d2), normalize(s2)), 0.0), glow_spread);
	}
	float band = exp(-abs(h) * glow_height);
	col = mix(col, glow_color, clamp(side * band * glow_amount, 0.0, 1.0));

	// Stars (upper sky only, fading out near the horizon).
	if (star_amount > 0.0 && h > 0.0) {
		float s = star_field(dir) * star_amount * smoothstep(0.0, 0.15, h);
		col += star_color * s * 1.5;
	}

	// Soft hue around the sun and the moon (your sprites are drawn on top of this).
	// Blended in (not added), so it tints the sky like a soft vignette instead of brightening it.
	col = mix(col, sun_aura_color, clamp(aura_shape(dir, sun_dir, sun_radius) * sun_aura_amount, 0.0, 1.0));
	col = mix(col, moon_aura_color, clamp(aura_shape(dir, moon_dir, moon_radius) * moon_aura_amount, 0.0, 1.0));

	COLOR = col * sky_energy;
}
"""


# -------------------------
# START
# -------------------------
func _ready() -> void:
	time = start_time

	_auto_find_nodes()
	_auto_load_textures()

	if sun == null:
		push_warning("Day/Night: couldn't find a Sun light (a DirectionalLight3D named 'Sun')")
	if moon == null:
		push_warning("Day/Night: couldn't find a Moon light (a DirectionalLight3D named 'Moon')")

	# The sprites ARE the sun and moon now, so stop the engine from drawing its own discs.
	for l in [sun, moon]:
		if l:
			l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY

	if moon_halo:
		halo_base_scale = moon_halo.scale

	sun_sprite = _make_sprite(sun_texture, sun_size_degrees)
	moon_sprite = _make_sprite(moon_texture, moon_size_degrees)

	sun_aura_light = _make_dim_light(sun_aura_color)
	moon_aura_light = _make_dim_light(moon_aura_color)
	star_light = _make_dim_light(star_light_color)

	_setup_environment()
	_setup_dusk()
	_setup_night_vision()
	update_sun_and_moon()


## Anything not assigned in the Inspector is found automatically: lights named Sun / Moon (or, failing that, the
## first two DirectionalLight3D nodes in the scene), the WorldEnvironment, and nodes named Stars / MoonHalo.
func _auto_find_nodes() -> void:
	var root := get_tree().current_scene
	if root == null:
		return

	if sun == null:
		sun = root.find_child("Sun", true, false) as DirectionalLight3D
	if moon == null:
		moon = root.find_child("Moon", true, false) as DirectionalLight3D

	if sun == null or moon == null:
		var lights: Array[DirectionalLight3D] = []
		for n in root.find_children("*", "DirectionalLight3D", true, false):
			var l := n as DirectionalLight3D
			if l != sun and l != moon:
				lights.append(l)
		if sun == null and lights.size() > 0:
			sun = lights.pop_front()
		if moon == null and lights.size() > 0:
			moon = lights.pop_front()

	if world_env == null:
		world_env = root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if world_env == null:
			var envs := root.find_children("*", "WorldEnvironment", true, false)
			if envs.size() > 0:
				world_env = envs[0] as WorldEnvironment

	if stars == null:
		stars = root.find_child("Stars", true, false) as GPUParticles3D
	if moon_halo == null:
		moon_halo = root.find_child("MoonHalo", true, false) as MeshInstance3D

	print("Day/Night: sun=", sun, " moon=", moon, " env=", world_env)


func _auto_load_textures() -> void:
	if sun_texture == null and ResourceLoader.exists(sun_texture_path):
		sun_texture = load(sun_texture_path) as Texture2D
	if moon_texture == null and ResourceLoader.exists(moon_texture_path):
		moon_texture = load(moon_texture_path) as Texture2D
	if sun_texture == null:
		push_warning("Day/Night: no sun texture. Put sun.png at %s or assign Sun Texture." % sun_texture_path)
	if moon_texture == null:
		push_warning("Day/Night: no moon texture. Put moon.png at %s or assign Moon Texture." % moon_texture_path)


## Gives the world a real sky made from the shader above (the old script forced a flat black background, so the
## sky was never visible), and makes ambient light come from that sky.
func _setup_environment() -> void:
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	var shader := Shader.new()
	shader.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = shader

	if env.sky == null:
		env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.sky.process_mode = Sky.PROCESS_MODE_REALTIME   # the sky changes every frame (time of day, twinkling stars)
	env.sky.radiance_size = Sky.RADIANCE_SIZE_64


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


func _make_dim_light(color: Color) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = color
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	l.visible = false
	add_child(l)
	return l


# -------------------------
# LOOP
# -------------------------
func _process(delta: float) -> void:
	if night_vision_toggle_action != "" and InputMap.has_action(night_vision_toggle_action) \
	and Input.is_action_just_pressed(night_vision_toggle_action):
		_nv_on = not _nv_on
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

	var sun_amount := smoothstep(-0.05, 0.2, height)      # 0 below the horizon, 1 once it's well up
	var moon_amount := smoothstep(-0.05, 0.25, -height)
	var sun_alpha := smoothstep(-0.08, 0.05, height)      # how visible the sprite / glow are
	var moon_alpha := smoothstep(-0.08, 0.05, -height)

	# ---------------- MAIN LIGHTS ----------------
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
	update_sky_colors(height, to_sun, to_moon, sun_alpha, moon_alpha, moon_amount)
	update_dim_lights(to_sun, to_moon, side, sun_amount, moon_amount)

	# ---------------- DUSK GRADE (on top of everything set above, same frame, so nothing builds up) ----------------
	_apply_dusk_grade(to_sun)
	_update_night_vision(to_sun)

	# ---------------- THINGS THAT FOLLOW THE CAMERA ----------------
	var cam := get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam else global_position

	_place_sprite(sun_sprite, to_sun, cam_pos, sun_alpha)
	_place_sprite(moon_sprite, to_moon, cam_pos, moon_alpha)
	update_moon_halo(height, to_moon, cam_pos)
	update_particle_stars(height, cam_pos)


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
# 🌅 SKY (colours, glow, aura, stars)
# -------------------------
func update_sky_colors(height: float, to_sun: Vector3, to_moon: Vector3, sun_alpha: float, moon_alpha: float, night_amount: float) -> void:
	if sky_mat == null:
		return

	var day_t := smoothstep(-0.12, 0.35, height)
	# Peaks right as the sun crosses the horizon (a touch below it). The shader only paints it on the sun's side.
	var glow := 1.0 - smoothstep(0.0, 0.35, absf(height + 0.03))

	var top := night_top_color.lerp(day_top_color, day_t)
	var horizon := night_horizon_color.lerp(day_horizon_color, day_t)

	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", horizon.darkened(0.5))
	sky_mat.set_shader_parameter("sky_energy", lerpf(night_sky_energy, 1.0, day_t))

	sky_mat.set_shader_parameter("sun_dir", to_sun)
	sky_mat.set_shader_parameter("moon_dir", to_moon)
	sky_mat.set_shader_parameter("glow_color", sunset_color)
	sky_mat.set_shader_parameter("glow_amount", glow * 0.9)
	sky_mat.set_shader_parameter("glow_spread", glow_spread)
	sky_mat.set_shader_parameter("glow_height", glow_height)

	sky_mat.set_shader_parameter("sun_aura_color", sun_aura_color)
	sky_mat.set_shader_parameter("moon_aura_color", moon_aura_color)
	sky_mat.set_shader_parameter("sun_aura_amount", sun_alpha * aura_intensity)
	sky_mat.set_shader_parameter("moon_aura_amount", moon_alpha * aura_intensity * moon_aura_strength)
	sky_mat.set_shader_parameter("sun_radius", deg_to_rad(sun_size_degrees * 0.5))
	sky_mat.set_shader_parameter("moon_radius", deg_to_rad(moon_size_degrees * 0.5))
	sky_mat.set_shader_parameter("aura_size", deg_to_rad(aura_size_degrees))
	sky_mat.set_shader_parameter("aura_falloff", aura_falloff)

	sky_mat.set_shader_parameter("star_amount", night_amount if use_shader_stars else 0.0)
	sky_mat.set_shader_parameter("star_color", star_color)
	sky_mat.set_shader_parameter("star_density", star_density)
	sky_mat.set_shader_parameter("star_size", star_size)
	sky_mat.set_shader_parameter("star_chance", star_chance)
	sky_mat.set_shader_parameter("star_twinkle", star_twinkle)


# -------------------------
# 💡 DIM LIGHTS (sun glow light, moon glow light, star light)
# -------------------------
func update_dim_lights(to_sun: Vector3, to_moon: Vector3, side: Vector3, sun_amount: float, moon_amount: float) -> void:
	if sun_aura_light == null or moon_aura_light == null or star_light == null:
		return

	if not dim_lights_enabled:
		sun_aura_light.visible = false
		moon_aura_light.visible = false
		star_light.visible = false
		return

	# Glow lights come from the same direction as their sun / moon, in the glow's colour.
	_aim_light(sun_aura_light, -to_sun, side)
	sun_aura_light.light_color = sun_aura_color
	sun_aura_light.light_energy = aura_light_energy * sun_amount
	sun_aura_light.visible = sun_aura_light.light_energy > 0.005

	_aim_light(moon_aura_light, -to_moon, side)
	moon_aura_light.light_color = moon_aura_color
	moon_aura_light.light_energy = aura_light_energy * moon_amount
	moon_aura_light.visible = moon_aura_light.light_energy > 0.005

	# Starlight: a faint cool fill from above that fades in at night and shimmers slightly.
	_aim_light(star_light, Vector3(0.15, -1.0, 0.1).normalized(), Vector3.FORWARD)
	var shimmer := 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.0017)
	star_light.light_color = star_light_color
	star_light.light_energy = star_light_energy * moon_amount * shimmer
	star_light.visible = star_light.light_energy > 0.005


# -------------------------
# 🌌 OLD PARTICLE STARS (only used if use_shader_stars is off)
# -------------------------
func update_particle_stars(height: float, cam_pos: Vector3) -> void:
	if stars == null:
		return
	if use_shader_stars:
		stars.emitting = false
		stars.visible = false
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


# =====================================================================================================
# 🌆 NATURAL DUSK (merged from natural_dusk.gd)
# =====================================================================================================

## One-time setup: default colour ramps, the post-processing look (tone mapping, contact shadows, glow), soft
## shadows on the sun and moon, and two dim fill lights. Fog is always switched off.
func _setup_dusk() -> void:
	if not dusk_look_enabled:
		return
	_make_default_ramps()
	_apply_dusk_environment()
	_apply_shadows(sun)
	_apply_shadows(moon)
	_sky_fill = _make_fill("SkyFill", -90.0)    # shines down
	_bounce = _make_fill("GroundBounce", 90.0)  # shines up


func _apply_dusk_environment() -> void:
	if world_env == null or world_env.environment == null:
		push_warning("sky_cycle (dusk): no WorldEnvironment found, so only the light and shadow settings were applied.")
		return
	var env := world_env.environment

	env.fog_enabled = false
	env.volumetric_fog_enabled = false

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = tonemap_white
	env.tonemap_exposure = exposure
	env.adjustment_enabled = true
	env.adjustment_saturation = saturation
	env.adjustment_contrast = contrast

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55          # the rest comes from the ambient colour set each frame
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.ssao_enabled = ssao_enabled
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.0
	env.ssao_light_affect = 0.15
	env.ssil_enabled = ssil_enabled
	env.sdfgi_enabled = sdfgi_enabled
	if sdfgi_enabled:
		env.sdfgi_use_occlusion = true

	env.glow_enabled = glow_enabled
	env.glow_intensity = glow_intensity
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = glow_hdr_threshold


func _apply_shadows(light: DirectionalLight3D) -> void:
	if light == null:
		return
	light.shadow_enabled = true
	light.directional_shadow_max_distance = shadow_max_distance
	light.shadow_blur = shadow_blur
	light.shadow_bias = shadow_bias
	light.shadow_normal_bias = shadow_normal_bias
	light.directional_shadow_blend_splits = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


func _make_fill(node_name: String, pitch_degrees: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = node_name
	l.shadow_enabled = false
	l.light_specular = 0.0
	l.light_energy = 0.0
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(l)
	l.global_rotation_degrees = Vector3(pitch_degrees, 0.0, 0.0)
	l.light_color = sky_fill_color if pitch_degrees < 0.0 else ground_bounce_color
	return l


## Every frame, right after the raw sun/moon/sky values are written: re-colour everything by how high the sun is.
func _apply_dusk_grade(to_sun: Vector3) -> void:
	if not dusk_look_enabled or sun == null or _sky_fill == null:
		return
	var k := clampf(dusk_strength, 0.0, 1.0)

	# Sun height: 0 at/below the horizon, 1 straight overhead; capped so the look never goes to white noon.
	var height := clampf(to_sun.y, 0.0, 1.0)
	var t := minf(height / maxf(dusk_max_height, 0.01), 1.0)
	var up := smoothstep(-0.12, 0.2, to_sun.y)                       # 0 once the sun is well below the horizon
	var day_w := smoothstep(0.35, 1.0, t) * k                        # 1 in full daylight, 0 at dusk and night
	var night_w := (1.0 - smoothstep(-0.15, 0.08, to_sun.y)) * k     # 1 once the sun is below the horizon

	# Sun: colour and strength follow its height
	var sun_col := _mute(sun_color_ramp.sample(t))
	sun_col = sun_col.lerp(day_tint, day_w * day_tint_amount)
	sun_col = _grey(sun_col, day_w * day_extra_greying)
	sun.light_color = sun.light_color.lerp(sun_col, k)
	sun.light_energy *= lerpf(1.0, sun_brightness, k)
	sun.light_angular_distance = lerpf(penumbra_low_sun, penumbra_high_sun, t)

	# Moon: greyed pale blue instead of green
	if moon:
		moon.light_energy *= lerpf(1.0, moon_brightness, k)
		moon.light_color = moon.light_color.lerp(night_moon_color, night_moon_color_amount * night_w)
		moon.light_color = _grey(moon.light_color, night_moon_greying * night_w)

	# The moon-glow and star lights follow the same pale blue at night
	for l in [sun_aura_light, moon_aura_light, star_light]:
		if l:
			l.light_color = l.light_color.lerp(night_moon_color, night_glow_light_amount * night_w)
			l.light_color = _grey(l.light_color, night_moon_greying * night_w)   # same greying as the moonlight itself

	# Fill lights fade out with the sun, so night stays dark
	_sky_fill.light_energy = sky_fill_energy * up * k
	_bounce.light_energy = ground_bounce_energy * up * k * lerpf(1.0, 0.5, t)
	_sky_fill.light_color = _grey(_mute(sky_fill_color).lerp(day_tint, day_w * day_tint_amount), day_w * day_extra_greying)
	_bounce.light_color = _grey(_mute(ground_bounce_color.lerp(sun_color_ramp.sample(t), 0.35)), day_w * day_extra_greying)

	# Ambient fill + overall saturation
	if world_env and world_env.environment:
		var env := world_env.environment
		var amb := _mute(ambient_color_ramp.sample(t))
		amb = amb.lerp(day_ambient_color, day_w)
		amb = amb.lerp(night_ambient_color, night_w)
		env.ambient_light_color = amb
		env.ambient_light_energy = lerpf(ambient_energy_low, ambient_energy_high, t)
		var sat := saturation
		sat = lerpf(sat, day_saturation, day_w)
		sat = lerpf(sat, night_saturation, night_w)
		env.adjustment_saturation = sat

	if grade_sky:
		_grade_sky_colors(day_w, night_w)


## Re-tints the sky colours that update_sky_colors just wrote this frame.
func _grade_sky_colors(day_w: float, night_w: float) -> void:
	if sky_mat == null:
		return
	for param in ["top_color", "horizon_color", "ground_color", "glow_color", "sun_aura_color", "moon_aura_color"]:
		var v = sky_mat.get_shader_parameter(param)
		if not (v is Color):
			continue
		if param == "moon_aura_color":
			# the moon's ring stays jade/emerald (never tinted blue), only lightly muted at night
			sky_mat.set_shader_parameter(param, _grey(v, moon_ring_night_greying * night_w))
			continue
		var c: Color = _grey(v, sky_greying)
		c = c.lerp(sky_day_tint, sky_day_tint_amount * day_w)
		c = c.lerp(sky_night_tint, sky_night_tint_amount * night_w)
		if param == "glow_color":
			c = c.lerp(Color(0.62, 0.1, 0.08), sky_blood_glow)
		# Night only: grey the sky and glow a bit further so the night sky is slightly grey like the day.
		c = _grey(c, sky_night_extra_greying * night_w)
		sky_mat.set_shader_parameter(param, c)


## Pulls a colour toward grey of the same brightness, so it keeps its warmth but loses some punch.
func _mute(c: Color) -> Color:
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), clampf(color_muting, 0.0, 1.0))


## Pulls a colour toward grey by `amount` (0..1), keeping its brightness.
func _grey(c: Color, amount: float) -> Color:
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), clampf(amount, 0.0, 1.0))


func _make_default_ramps() -> void:
	if sun_color_ramp == null:
		sun_color_ramp = Gradient.new()
		sun_color_ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.35, 0.6, 1.0])
		sun_color_ramp.colors = PackedColorArray([
			Color(0.3, 0.25, 0.4),     # twilight: cold bruised purple-grey
			Color(0.75, 0.22, 0.14),   # sun on the horizon: dried-blood red
			Color(0.8, 0.45, 0.28),    # low sun: burnt amber
			Color(0.85, 0.68, 0.48),   # dull gaslight gold
			Color(0.88, 0.82, 0.72)])  # high sun: pale sepia
	if ambient_color_ramp == null:
		ambient_color_ramp = Gradient.new()
		ambient_color_ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		ambient_color_ramp.colors = PackedColorArray([
			Color(0.14, 0.15, 0.28),   # twilight: cold deep blue
			Color(0.38, 0.28, 0.34),   # dusk: bruised mauve
			Color(0.42, 0.42, 0.47)])  # day-ish: murky slate


# =====================================================================================================
# 👁 NIGHT VISION
# =====================================================================================================

## A soft, shadowless pale light that follows the camera, so the player can see a little way in the dark.
func _setup_night_vision() -> void:
	_nv_light = OmniLight3D.new()
	_nv_light.name = "NightVisionLight"
	_nv_light.top_level = true             # positioned in the world, not relative to this node
	_nv_light.shadow_enabled = false
	_nv_light.light_specular = 0.0
	_nv_light.light_energy = 0.0
	_nv_light.omni_range = night_vision_light_range
	_nv_light.omni_attenuation = 1.2
	_nv_light.light_color = night_vision_color
	_nv_light.visible = false
	add_child(_nv_light)


## Every frame, after the dusk grade: at night, lift the shadow fill and exposure a little and glow a soft light
## around the player. Fades in and out with the sunset and sunrise, and does nothing in daylight.
func _update_night_vision(to_sun: Vector3) -> void:
	if _nv_light == null:
		return
	var night := (1.0 - smoothstep(-0.15, 0.08, to_sun.y))
	var k := night * night_vision_strength if (night_vision_enabled and _nv_on) else 0.0

	if world_env and world_env.environment:
		var env := world_env.environment
		if _nv_base_exposure < 0.0:
			_nv_base_exposure = env.tonemap_exposure
		env.ambient_light_energy += night_vision_ambient_boost * k
		env.tonemap_exposure = _nv_base_exposure + night_vision_exposure_boost * k

	_nv_light.omni_range = night_vision_light_range
	_nv_light.light_color = night_vision_color
	_nv_light.light_energy = night_vision_light_energy * k
	_nv_light.visible = _nv_light.light_energy > 0.005
	var cam := get_viewport().get_camera_3d()
	if cam:
		_nv_light.global_position = cam.global_position
