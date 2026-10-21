extends Node
## Natural dusk lighting (no fog). Add as a child node of your world and it finds everything itself.
##
## Different approach from natural_lighting.gd: instead of tinting the sun by a fixed amount, every part of the
## light is driven by how HIGH the sun is, the way real dusk works. Low sun = long shadows, red-orange light,
## cool violet sky fill and warm light bouncing up off the ground. It never recolors the moon (green stays green).
## Use this INSTEAD of natural_lighting.gd, not alongside it.

@export var world_env: WorldEnvironment            # left empty = found automatically
@export var sun: DirectionalLight3D                # left empty = found automatically (first DirectionalLight3D)
@export var moon: DirectionalLight3D               # optional second directional light

@export_range(0.0, 1.0) var dusk_strength := 1.0   # 0 = off, 1 = full dusk look
@export_range(0.1, 1.0) var dusk_max_height := 0.45 # caps how "high noon" the grading ever gets (lower = warmer all day)
@export_range(0.0, 1.0) var color_muting := 0.4    # 0 = original vibrant colours, 1 = grey light. Dulls the light colours themselves.

# -------------------------
# DAY / NIGHT GRADE (Bloodborne style): murky sepia and slate by day, cold moonlit blue by night, dried-blood dusk
# -------------------------
@export var day_tint := Color(0.78, 0.72, 0.6)              # sickly sepia the daytime light is pulled toward
@export_range(0.0, 1.0) var day_tint_amount := 0.6
@export_range(0.0, 1.0) var day_extra_greying := 0.35       # extra greying on top of color_muting, daytime only
@export var day_ambient_color := Color(0.38, 0.38, 0.41)    # cold slate fill in the shadows by day
@export var day_saturation := 0.55                          # overall picture saturation by day
@export var night_ambient_color := Color(0.1, 0.14, 0.24)   # cold blue-black fill in the shadows by night
@export var night_moon_color := Color(0.55, 0.68, 0.9)      # pale cold moonlight, replaces sky_cycle's green moon light
@export_range(0.0, 1.0) var night_moon_color_amount := 1.0  # 0 = keep sky_cycle's moon colour, 1 = fully this colour
@export_range(0.0, 1.0) var night_moon_greying := 0.15      # dulls the moonlight a little
@export var night_saturation := 0.7

# -------------------------
# SUN: colour by height (left = at the horizon / twilight, right = high sun)
# -------------------------
@export var sun_color_ramp: Gradient
@export var sun_brightness := 0.65                 # sun strength multiplier on top of sky_cycle
@export var moon_brightness := 0.85                # brightness only, never colour

# -------------------------
# FILL LIGHT (what makes shadows look natural instead of black)
# -------------------------
@export var ambient_color_ramp: Gradient           # colour of the fill in the shadows, by sun height
@export var ambient_energy_low := 0.55             # fill strength with the sun on the horizon
@export var ambient_energy_high := 0.9             # fill strength with the sun higher up
@export var sky_fill_color := Color(0.4, 0.45, 0.6)    # cold slate light from above
@export var sky_fill_energy := 0.18
@export var ground_bounce_color := Color(0.7, 0.35, 0.22)   # dull dried-blood glow bouncing up off the ground
@export var ground_bounce_energy := 0.22

# -------------------------
# SHADOWS
# -------------------------
@export var shadow_max_distance := 120.0           # low sun casts long shadows, so draw them further
@export var shadow_blur := 1.6
@export var shadow_bias := 0.04
@export var shadow_normal_bias := 1.5
@export var penumbra_low_sun := 2.2                # soft shadow edge (degrees) with the sun on the horizon
@export var penumbra_high_sun := 1.0

# -------------------------
# COLOUR / CONTACT SHADOWS / GLOW
# -------------------------
@export var exposure := 0.9
@export var tonemap_white := 6.0
@export var saturation := 0.82                     # below 1 = duller overall picture
@export var contrast := 0.98
@export var ssao_enabled := true
@export var ssil_enabled := true                   # cheap screen-space bounce light
@export var sdfgi_enabled := false                 # real bounce light everywhere; Forward+ only, costs more
@export var glow_enabled := true
@export var glow_intensity := 0.45
@export var glow_hdr_threshold := 1.0

# -------------------------
# OPTIONAL: freeze the sun at golden hour
# -------------------------
@export var hold_golden_hour := false              # keeps the sun's direction but locks its height. Off = sky_cycle owns the sun.
@export_range(2.0, 40.0) var held_elevation_degrees := 9.0

var _sky_fill: DirectionalLight3D
var _bounce: DirectionalLight3D


func _ready() -> void:
	_make_default_ramps()
	if world_env == null:
		world_env = _find_first(get_tree().root, "WorldEnvironment") as WorldEnvironment
	if sun == null or moon == null:
		var lights := _find_all(get_tree().root, "DirectionalLight3D")
		if sun == null and lights.size() > 0:
			sun = lights[0] as DirectionalLight3D
		if moon == null and lights.size() > 1:
			moon = lights[1] as DirectionalLight3D

	_apply_environment()
	_apply_shadows(sun)
	_apply_shadows(moon)
	_sky_fill = _make_fill("SkyFill", -90.0)    # shines down
	_bounce = _make_fill("GroundBounce", 90.0)  # shines up

	# Run AFTER sky_cycle each frame so this is applied on top of its values.
	process_priority = 1000


func _process(_delta: float) -> void:
	if sun == null or not is_instance_valid(sun):
		return
	var k := clampf(dusk_strength, 0.0, 1.0)

	if hold_golden_hour:
		_hold_sun_height()

	# Sun height: 0 at/below the horizon, 1 straight overhead; capped so the look never goes to white noon.
	var to_sun := sun.global_transform.basis.z.normalized()
	var height := clampf(to_sun.y, 0.0, 1.0)
	var t := minf(height / maxf(dusk_max_height, 0.01), 1.0)
	var up := smoothstep(-0.12, 0.2, to_sun.y)        # 0 once the sun is well below the horizon
	var day_w := smoothstep(0.35, 1.0, t) * k          # 1 in full daylight, 0 at dusk and night
	var night_w := (1.0 - smoothstep(-0.15, 0.08, to_sun.y)) * k   # 1 once the sun is below the horizon

	# Sun: colour and strength follow its height
	var sun_col := _mute(sun_color_ramp.sample(t))
	sun_col = sun_col.lerp(day_tint, day_w * day_tint_amount)
	sun_col = _grey(sun_col, day_w * day_extra_greying)
	sun.light_color = sun.light_color.lerp(sun_col, k)
	sun.light_energy *= lerpf(1.0, sun_brightness, k)
	sun.light_angular_distance = lerpf(penumbra_low_sun, penumbra_high_sun, t)
	if moon and is_instance_valid(moon):
		moon.light_energy *= lerpf(1.0, moon_brightness, k)
		moon.light_color = moon.light_color.lerp(night_moon_color, night_moon_color_amount * night_w)
		moon.light_color = _grey(moon.light_color, night_moon_greying * night_w)

	# Fill lights fade out with the sun, so night stays dark
	_sky_fill.light_energy = sky_fill_energy * up * k
	_bounce.light_energy = ground_bounce_energy * up * k * lerpf(1.0, 0.5, t)
	_sky_fill.light_color = _grey(_mute(sky_fill_color).lerp(day_tint, day_w * day_tint_amount), day_w * day_extra_greying)
	_bounce.light_color = _grey(_mute(ground_bounce_color.lerp(sun_color_ramp.sample(t), 0.35)), day_w * day_extra_greying)

	# Ambient: colour and strength follow sun height
	if world_env and world_env.environment:
		var env := world_env.environment
		var amb := _mute(ambient_color_ramp.sample(t))
		amb = amb.lerp(day_ambient_color, day_w)
		amb = amb.lerp(night_ambient_color, night_w)
		env.ambient_light_color = amb
		var sat := saturation
		sat = lerpf(sat, day_saturation, day_w)
		sat = lerpf(sat, night_saturation, night_w)
		env.adjustment_saturation = sat
		env.ambient_light_energy = lerpf(ambient_energy_low, ambient_energy_high, t)


## Pulls a colour toward grey of the same brightness, so it keeps its warmth but loses some punch.
func _mute(c: Color) -> Color:
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), clampf(color_muting, 0.0, 1.0))


## Pulls a colour toward grey by `amount` (0..1), keeping its brightness.
func _grey(c: Color, amount: float) -> Color:
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), clampf(amount, 0.0, 1.0))


func _hold_sun_height() -> void:
	var d := sun.global_transform.basis.z.normalized()
	var az := atan2(d.x, d.z)
	var e := deg_to_rad(held_elevation_degrees)
	var to_sun := Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))
	sun.global_transform.basis = Basis.looking_at(-to_sun, Vector3.UP)


func _apply_environment() -> void:
	if world_env == null:
		push_warning("natural_dusk: no WorldEnvironment found, so only the light and shadow settings were applied.")
		return
	var env := world_env.environment
	if env == null:
		env = Environment.new()
		world_env.environment = env

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
	add_child(l)
	l.global_rotation_degrees = Vector3(pitch_degrees, 0.0, 0.0)
	l.light_color = sky_fill_color if pitch_degrees < 0.0 else ground_bounce_color
	return l


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


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for c in node.get_children():
		var r := _find_first(c, type_name)
		if r:
			return r
	return null


func _find_all(node: Node, type_name: String, out: Array = []) -> Array:
	if node.is_class(type_name):
		out.append(node)
	for c in node.get_children():
		_find_all(c, type_name, out)
	return out
