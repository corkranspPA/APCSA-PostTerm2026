extends Node3D

# -------------------------
# REFERENCES
# -------------------------
@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_env: WorldEnvironment
@export var stars: GPUParticles3D
@export var moon_halo: MeshInstance3D

# -------------------------
# SETTINGS
# -------------------------
@export var cycle_speed: float = 60.0

var time: float = 0.0
var sky_rotation_offset: float = 0.0


# -------------------------
# START CHECK
# -------------------------
func _ready() -> void:
	print("Day/Night system loaded")

	# DEBUG CHECK (VERY IMPORTANT)
	if sun == null:
		print("❌ Sun is NOT assigned in Inspector")
	if moon == null:
		print("❌ Moon is NOT assigned in Inspector")


# -------------------------
# LOOP
# -------------------------
func _process(delta: float) -> void:
	time += delta / cycle_speed
	if time > 1.0:
		time -= 1.0

	update_sun_and_moon()


# -------------------------
# ☀️ SUN + 🌙 MOON (FORCED WORKING VERSION)
# -------------------------
func update_sun_and_moon() -> void:
	if sun == null or moon == null:
		return

	var angle: float = (time * TAU) - PI * 0.5
	var height: float = sin(angle)

	var day_factor: float = clamp(height, 0.0, 1.0)
	var night_factor: float = clamp(-height, 0.0, 1.0)

	# ---------------- SUN (FORCED VISIBILITY) ----------------
	sun.visible = true
	sun.light_energy = 2.5

	sun.rotation_degrees.x = rad_to_deg(-angle)

	sun.light_color = Color(1.0, 0.45, 0.15).lerp(
		Color(1.0, 1.0, 1.0),
		day_factor
	)

	# ---------------- MOON (FORCED VISIBILITY) ----------------
	moon.visible = true
	moon.light_energy = 1.2 * night_factor

	moon.rotation_degrees.x = rad_to_deg(-angle + PI)

	moon.light_color = Color(0.6, 0.7, 1.0)


	# ---------------- SKY SYNC ----------------
	sky_rotation_offset = angle

	update_night_darkness(height)
	update_stars(height)
	update_moon_halo(height)
	update_sky_colors(height)
	update_sky_rotation()


# -------------------------
# 🌑 NIGHT DARKNESS (SAFE)
# -------------------------
func update_night_darkness(height: float) -> void:
	if world_env == null:
		return

	var env: Environment = world_env.environment
	if env == null:
		return

	var night_factor: float = clamp(-height, 0.0, 1.0)

	env.ambient_light_energy = lerp(0.6, 0.0, night_factor)
	env.sky_contribution = 0.0

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)


# -------------------------
# 🌌 STARS (SAFE)
# -------------------------
func update_stars(height: float) -> void:
	if stars == null:
		return

	var is_night: bool = height < 0.0

	stars.emitting = is_night
	stars.visible = is_night


# -------------------------
# 🌙 MOON HALO (SAFE)
# -------------------------
func update_moon_halo(height: float) -> void:
	if moon_halo == null:
		return

	var night_factor: float = clamp(-height, 0.0, 1.0)

	moon_halo.visible = night_factor > 0.2
	moon_halo.scale = Vector3.ONE * lerp(1.0, 2.5, night_factor)


# -------------------------
# 🌅 SKY COLORS
# -------------------------
func update_sky_colors(height: float) -> void:
	if world_env == null:
		return

	var env: Environment = world_env.environment
	if env == null or env.sky == null:
		return

	var material := env.sky.sky_material
	if material == null:
		return

	if material is ProceduralSkyMaterial:
		var mat := material as ProceduralSkyMaterial

		var t: float = clamp(height * 0.5 + 0.5, 0.0, 1.0)

		mat.sky_horizon_color = Color(1.0, 0.25, 0.1).lerp(
			Color(0.6, 0.8, 1.0),
			t
		)

		mat.sky_top_color = Color(0.02, 0.02, 0.15).lerp(
			Color(0.35, 0.6, 1.0),
			t
		)


# -------------------------
# 🌍 SKY ROTATION (SAFE)
# -------------------------
func update_sky_rotation() -> void:
	if world_env == null:
		return

	var env: Environment = world_env.environment
	if env == null or env.sky == null:
		return

	var material := env.sky.sky_material
	if material == null:
		return

	if material is ProceduralSkyMaterial:
		var mat := material as ProceduralSkyMaterial
		mat.sun_angle_max = sky_rotation_offset
