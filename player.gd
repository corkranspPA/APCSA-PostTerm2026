extends CharacterBody3D

@export var speed := 7.0            # brisk walking pace, m/s
@export var sprint_speed := 11.5    # top sustained sprint, m/s
@export var crouch_speed := 2.6     # crouched movement speed, m/s

@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var crouch_lerp_speed := 10.0

# -------------------------
# GROUND / AIR MOVEMENT (snappy, ULTRAKILL-ish)
# -------------------------
@export var ground_accel := 60.0          # how quickly velocity ramps toward target speed
@export var ground_decel := 55.0          # how quickly velocity bleeds off when stopping/turning
@export var ground_overspeed_decel := 10.0 # how slowly extra momentum (from a jump, dash or slide) fades on the ground
@export var air_accel := 16.0             # air strafing / air control
@export var fall_gravity_mult := 1.35     # heavier fall than rise = snappier jumps

@export var sprint_ramp_time := 0.25      # seconds to build up from standstill to full sprint speed
@export var backpedal_speed_mult := 0.75  # running backwards is slower than forward
@export var strafe_speed_mult := 0.9      # side-stepping is slower than a straight sprint

@export var uphill_slowdown_strength := 0.5    # 0 = no effect, 1 = strong slowdown running uphill
@export var downhill_speedup_strength := 0.3   # 0 = no effect, 1 = strong speedup running downhill
@export var turn_brake_mult := 1.8             # extra deceleration when reversing direction sharply
@export var turn_brake_dot_threshold := -0.3   # how sharp a direction change counts as "reversing"

var sprint_ramp := 0.0  # 0..1, how "spooled up" the current sprint is

# -------------------------
# STAMINA (fatigue while sprinting)
# -------------------------
@export var max_stamina := 15.0          # raised from 10 (with dash_stamina_cost 3 that's 5 dashes)
@export var stamina_drain_rate := 1.0        # stamina lost per second while actively sprinting
@export var stamina_regen_rate := 1.6        # stamina gained per second once recovering
@export var stamina_regen_delay := 0.8       # seconds after you stop sprinting before regen kicks in
@export var min_stamina_to_sprint := 0.5     # can't START a new sprint below this
@export var low_stamina_speed_mult := 0.55   # sprint speed multiplier once fully gassed
@export var stamina_taper_ratio := 0.3       # below this fraction of max stamina, speed starts tapering

var stamina := 15.0
var stamina_regen_timer := 0.0

# NEW: each jump takes one chunk of stamina (nothing more is drained while you're in the air); hitting a wall gives it back.
@export var jump_stamina_cost := 1.5          # one-time stamina taken per ground jump / bunny hop (never blocks the jump; bottoms out at 0)
@export var wall_hit_stamina_burst := 2.0     # instant stamina gained the moment you hit a wall in the air
@export var wall_stamina_regen_rate := 6.0    # stamina gained per second while touching / clinging to a wall
@export var wall_hit_cooldown := 0.4          # seconds before another wall hit can give the burst again (stops wall-spam abuse)

var was_wall_contact := false
var wall_hit_cooldown_timer := 0.0

# -------------------------
# HEALTH (red) / SHIELD (blue)
# -------------------------
@export var max_health := 100.0
@export var health_regen_rate := 2.0         # per second once regen delay passes (0 = off, rely on shield + pickups)
@export var health_regen_delay := 4.0        # seconds after last hit before health can start regenerating
@export var invuln_time := 0.4               # brief invulnerability window right after a hit

@export var max_shield := 50.0
@export var shield_regen_rate := 8.0         # per second once regen delay passes
@export var shield_regen_delay := 3.0        # seconds after last hit before shield starts regenerating
@export var shield_break_extra_delay := 2.0  # EXTRA wait before regen if a hit fully breaks the shield

var health := 100.0
var health_regen_timer := 0.0
var invuln_timer := 0.0

var shield := 50.0
var shield_regen_timer := 0.0

var is_dead := false

# -------------------------
# DEATH / RESPAWN
# -------------------------
@export var respawn_delay := 1.5          # seconds on the death screen after dying to damage
@export var void_respawn_delay := 0.5     # shorter wait when you fall off the map
@export var kill_height := -20.0          # fall below this Y and you die
@export var respawn_invuln_time := 1.5    # brief spawn protection after coming back

var spawn_position := Vector3.ZERO
var spawn_yaw := 0.0

# Emitted whenever health/shield/stamina change, so the HUD can just connect
# once and read player.health / player.shield / player.stamina.
signal stats_changed
signal died
signal shield_broken   # shield just hit zero from a hit (good hook for a sound / screen flash)
signal respawned       # fired after the player comes back to life
signal knocked_down    # NEW: an air roll was botched and you hit the floor (hook a thud sound here)
signal roll_wall_bounced # NEW: a roll hit a wall and kicked you off it

# -------------------------
# JUMP BOOST SYSTEM
# -------------------------
@export var sprint_jump_boost := 1.35

@export var wall_jump_up_boost := 1.6
@export var wall_jump_speed_scale := 1.35
@export var min_wall_jump_up := 5.5
@export var max_wall_jump_up := 8.0

@export var slide_jump_boost := 1.4
@export var slide_exit_speed_boost := 1.25

# -------------------------
# DASH SYSTEM (multiple charges, i-frames, keeps momentum)
# -------------------------
@export var dash_speed := 20.0
@export var dash_duration := 0.15
@export var dash_cooldown := 0.2            # short delay between back-to-back dashes
@export var dash_stamina_cost := 3.0        # stamina spent per dash/roll (10 max = 3 dashes)
@export var dash_exit_momentum := 0.55      # fraction of dash speed kept when the dash ends
@export var dash_grants_iframes := true     # can't be hurt mid-dash

# Dashing while crouched or sliding = a ground roll. Dashing in mid-air = an air roll (gentler, see below).
@export var roll_speed := 10.5              # starting speed of the roll (eases out over its duration)
@export var roll_duration := 0.75     # longer roll = slower, easier-to-watch spin
@export var roll_exit_momentum := 0.7       # fraction of roll speed kept when it ends
@export var roll_grants_iframes := true
@export var roll_iframe_time := 0.3         # seconds of invulnerability at the start of a roll
@export var roll_full_spin := true            # true = visible full camera roll; false = gentle tilt only (GROUND rolls)
@export var roll_spin_degrees := 360.0        # how far the camera rotates during a ground roll
@export var roll_camera_tilt_degrees := 12.0  # tilt amount used when roll_full_spin is off
# Comfort aids while rolling: a vignette hides the fast-moving screen edges and a narrower FOV
# reduces peripheral motion — both are well-known ways to cut motion sickness.
@export var roll_vignette_boost := 0.5        # extra squint-vignette during a ground roll (needs the eyelid overlay)
@export var roll_fov_change := -4.0           # FOV added during a ground roll (negative = narrower)
@export var roll_fov_kick := 6.0              # NEW: extra FOV that follows the speed surge, so the launch feels fast
@export var ground_roll_surge := 0.25         # NEW: extra speed at the start of a ground roll, as a fraction of its speed

# -------------------------
# AIR ROLL (NEW) — easier on the eyes than the ground roll
# -------------------------
# Air rolls NEVER move or rotate the camera. Instead the momentum comes from SPEED: you surge forward a
# little in the roll direction, then ease back down to the speed you came in with.
@export var air_roll_speed_boost := 0.3        # peak extra speed as a fraction of your entry speed (0.3 = +30%)
@export var air_roll_min_speed := 7.0          # entry speed used if you were slower than this (e.g. a standing jump)
@export var air_roll_gravity_mult := 0.8       # slightly floatier while rolling in the air (arc feels smoother, easier to finish)
@export var air_roll_fov_kick := 5.0           # FOV widens by this much at the peak of the surge, then settles
@export var air_roll_vignette_boost := 0.15    # light vignette so the screen edges don't swim
# If you land before the air roll is this far along (0..1), you botch it and tumble. Set to 0 to disable.
@export var air_roll_complete_progress := 0.7

# -------------------------
# ROLL WITH THE MOVEMENT KEYS (NEW)
# -------------------------
# Double-tap a movement key (W/A/S/D or stick) to roll that way — no mouse, no crouch, no extra button.
# Works on the ground and in the air. The normal dash button still works too.
@export var roll_double_tap_enabled := true
@export var roll_double_tap_window := 0.25    # seconds between the two taps
@export var roll_input_buffer := 0.2          # a tap made slightly early (cooldown / mid-roll) still fires when it's allowed

var last_tap_time := {}                        # action name -> time of its last fresh press
var roll_request_pending := false
var roll_request_dir := Vector2.ZERO           # local input direction (x = right, y = back) of the tapped key
var roll_buffer_timer := 0.0

# -------------------------
# FAILED ROLL / KNOCKDOWN (NEW)
# -------------------------
@export var knockdown_duration := 0.6          # total seconds on the ground before you can act again (keep under 1s)
@export var knockdown_friction := 14.0         # how quickly you skid to a stop while down
@export var knockdown_camera_tilt_degrees := 14.0
@export var knockdown_camera_drop := 0.3       # extra camera height lost while down (rises back up as you get up)

# -------------------------
# ROLL INTO WALL = WALL BOUNCE (NEW)
# -------------------------
@export var roll_wall_bounce := true
@export var roll_wall_bounce_speed_mult := 1.0       # how much of the roll's speed carries into the bounce
@export var roll_wall_bounce_up_mult := 0.75         # scales the normal wall-jump height (1.0 = same as a wall jump)
@export var roll_wall_bounce_stamina_refund := 1.5   # stamina given back so you can chain into another dash
@export var roll_wall_bounce_min_dot := 0.35         # how head-on the roll must be (0 = any touch, 1 = perfectly head-on)

var is_dashing := false
var is_rolling := false                     # true while a crouched dash (roll) is happening
var roll_is_air := false                    # NEW: this roll was started in mid-air
var roll_progress := 0.0                    # 0..1 through the current roll (drives the camera spin)
var roll_current_speed := 0.0               # speed of the current roll (never slower than the speed you started it at)
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := Vector3.ZERO

# NEW: knockdown state. Weapon scripts can check player.is_knocked_down to block shooting while down.
var is_knocked_down := false
var knockdown_timer := 0.0
var knockdown_tilt_sign := 1.0
var restore_camera_pitch := false

# -------------------------
# GROUND SLAM (press crouch in the air)
# -------------------------
@export var slam_speed := 42.0
@export var slam_air_drag := 25.0            # how fast sideways speed dies while slamming
@export var slam_damage := 60.0
@export var slam_radius := 6.0
@export var slam_bounce_velocity := 11.0     # hold jump on landing for a big bounce

var is_slamming := false

# -------------------------
# SLIDE SYSTEM
# -------------------------
@export var slide_base_speed := 14.0
@export var slide_duration := 1.0
@export var slide_friction := 4.5
@export var slide_burst := 1.6
@export var slope_slide_boost := 2.2
@export var slide_from_walk := true          # crouch while moving fast enough slides even if not sprinting

var is_sliding := false
var slide_timer := 0.0
var slide_direction := Vector3.ZERO
var slide_speed := 0.0

# -------------------------
# KNOCKBACK (from enemy hits)
# -------------------------
var knockback_timer := 0.0

# -------------------------
# FOV SYSTEM
# -------------------------
@export var normal_fov := 75.0
@export var sprint_fov := 105.0     # widens while sprinting for a sense of speed
@export var slide_fov := 110.0      # widens further while sliding
@export var dash_fov := 100.0       # dash also widens briefly for a burst-of-speed feel
@export var slam_fov := 112.0       # slam stretches the view while diving
@export var fov_speed := 9.0

var current_fov := 75.0

# -------------------------
# CAMERA
# -------------------------
@export var slide_tilt_amount := 8.0
@export var slide_lean_amount := 0.12

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var Weapon = $Head/Camera3D/weapon  # matches the lowercase "weapon" node in the scene tree

var pitch := 0.0
var mouse_captured := true

var is_crouching := false
var is_sprinting := false

var stand_height := 2.0
var crouch_height := 1.2

var stand_cam_y := 1.6
var crouch_cam_y := 0.8

var headspace_check_distance := 0.6

# -------------------------
# HEAD BOB
# -------------------------
var bob_time := 0.0
var base_camera_pos := Vector3.ZERO
var base_camera_rot_x := 0.0

@export var walk_bob_speed := 8.0
@export var sprint_bob_speed := 13.0
@export var crouch_bob_speed := 5.0

@export var walk_bob_amount := 0.09
@export var sprint_bob_amount := 0.16
@export var crouch_bob_amount := 0.03

# -------------------------
# BUNNY HOPPING
# -------------------------
@export var bhop_speed_boost := 1.05
@export var max_bhop_speed := 18.0
@export var auto_bhop := true

var was_on_floor := false

# -------------------------
# WALL CLING
# -------------------------
@export var wall_cling_gravity_scale := 0.08
@export var wall_cling_max_slide_speed := 2.0
@export var wall_cling_fov := 88.0

var is_wall_clinging := false
var wall_cling_normal := Vector3.ZERO

# -------------------------
# SQUINT / EYELID VIGNETTE
# -------------------------
@export var base_squint_amount := 0.1   # resting vignette pull, always applied even when idle
@export var squint_speed_ref := 11.5    # speed (m/s) that counts as "fully squinted" — match sprint_speed
@export var squint_smoothing := 6.0     # higher = vignette reacts to speed changes faster
@export var squint_extra_when_exhausted := 0.2  # extra squint added as stamina bottoms out
@export var squint_slide_boost := 0.35  # extra squint added while sliding, on top of speed
@export var squint_crouch_boost := 0.12  # slight extra squint while crouched (not sliding)
@export var squint_zoom_boost := 0.3    # extra squint while aiming/zoomed in (ADS)
@export var squint_low_health_boost := 0.3  # extra squint as health bottoms out (panic/pain vignette)

# Set true/false by the weapon script whenever ADS starts/stops (see weapon's _process,
# which already checks Input.is_action_pressed("aim")).
var is_zooming := false

# Point this at your ColorRect overlay in the editor (or set it in _ready()).
# Give the ColorRect a Unique Name (%EyelidOverlay) in your scene, or fix this path.
@onready var eyelid_overlay: ColorRect = get_node_or_null("%EyelidOverlay")

var current_squint := 0.0

# -------------------------
# DAMAGE FLASH (maroon vignette)
# -------------------------
@export var health_flash_color := Color(0.85, 0.05, 0.05)  # red: health took damage
@export var shield_flash_color := Color(0.1, 0.4, 1.0)     # blue: shield took damage
@export var both_flash_color := Color(0.6, 0.1, 0.9)       # purple: ONE hit hurt shield AND health
@export var damage_flash_min := 0.55          # flash strength for a tiny hit (0..1)
@export var damage_flash_max := 1.0           # flash strength for a big hit
@export var damage_flash_fade := 2.5          # higher = flash fades faster (about 0.4s at 2.5)
@export var damage_flash_inner := 0.3         # how far the clear centre reaches (0 = all colour, 1 = edges only)

var health_flash := 0.0
var shield_flash := 0.0
var both_flash := 0.0
var damage_flash_rect: ColorRect


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

	current_fov = normal_fov
	camera.fov = normal_fov

	var shape = collision.shape as CapsuleShape3D
	if shape:
		stand_height = shape.height

	stand_cam_y = camera.position.y
	crouch_cam_y = stand_cam_y - 0.8

	base_camera_pos = camera.position
	base_camera_rot_x = camera.rotation.x

	stamina = max_stamina
	health = max_health
	shield = max_shield

	# Wherever the player is placed in the scene is where they respawn.
	spawn_position = global_position
	spawn_yaw = rotation.y

	# ---- give the weapon a reference to this player ----
	if Weapon:
		Weapon.player = self

	_build_damage_flash()


func _input(event: InputEvent) -> void:
	# NEW: double-tap a movement key = roll in that direction.
	if roll_double_tap_enabled and not is_dead and not event.is_echo():
		var tap_dirs := {
			"move_left": Vector2(-1, 0),
			"move_right": Vector2(1, 0),
			"move_forward": Vector2(0, -1),
			"move_back": Vector2(0, 1),
		}
		for action in tap_dirs:
			if event.is_action_pressed(action):
				var now := Time.get_ticks_msec() / 1000.0
				if last_tap_time.has(action) and now - last_tap_time[action] <= roll_double_tap_window:
					roll_request_pending = true
					roll_request_dir = tap_dirs[action]
					roll_buffer_timer = roll_input_buffer
					last_tap_time.erase(action)   # a third tap starts a fresh count
				else:
					last_tap_time[action] = now
				break

	if event.is_action_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
		)


func _process(delta: float) -> void:
	# Damage flash: red for health hits, blue for shield hits. Both fade out smoothly.
	if health_flash > 0.0 or shield_flash > 0.0 or both_flash > 0.0:
		health_flash = move_toward(health_flash, 0.0, damage_flash_fade * delta)
		shield_flash = move_toward(shield_flash, 0.0, damage_flash_fade * delta)
		both_flash = move_toward(both_flash, 0.0, damage_flash_fade * delta)
		if damage_flash_rect:
			var fm := damage_flash_rect.material as ShaderMaterial
			fm.set_shader_parameter("health_intensity", health_flash)
			fm.set_shader_parameter("shield_intensity", shield_flash)
			fm.set_shader_parameter("both_intensity", both_flash)

	if eyelid_overlay and eyelid_overlay.material:
		var fatigue := 1.0 - clampf(stamina / max_stamina, 0.0, 1.0)
		var hurt := 1.0 - clampf(health / max_health, 0.0, 1.0)

		# How fast you're actually moving right now, 0..1 relative to squint_speed_ref.
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		var speed_ratio := clampf(horizontal_speed / squint_speed_ref, 0.0, 1.0)

		# Always-on resting pull, plus more the faster you're actually going, plus fatigue and pain.
		var target_squint := base_squint_amount \
			+ speed_ratio * (1.0 - base_squint_amount) \
			+ fatigue * squint_extra_when_exhausted \
			+ hurt * squint_low_health_boost
		if is_sliding:
			target_squint += squint_slide_boost
		elif is_crouching:
			target_squint += squint_crouch_boost
		if is_zooming:
			target_squint += squint_zoom_boost
		if is_rolling:
			# NEW: air rolls use a much lighter vignette than ground rolls
			target_squint += air_roll_vignette_boost if roll_is_air else roll_vignette_boost
		target_squint = clampf(target_squint, 0.0, 1.0)

		current_squint = lerp(current_squint, target_squint, squint_smoothing * delta)
		eyelid_overlay.material.set_shader_parameter("squint", current_squint)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured and not is_dead:
		rotate_y(-event.relative.x * mouse_sensitivity)

		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:

	if is_dead:
		_dead_physics(delta)
		return

	dash_cooldown_timer = max(dash_cooldown_timer - delta, 0.0)
	knockback_timer = max(knockback_timer - delta, 0.0)

	update_health_and_shield(delta)

	# NEW: while knocked down you can't act — you skid, then get back up.
	if is_knocked_down:
		_knockdown_physics(delta)
		return

	# NEW: rolling into a wall kicks you off it (checked before wall-cling so cling can't steal the roll).
	if is_dashing and is_rolling and roll_wall_bounce and is_on_wall():
		_try_roll_wall_bounce()

	if is_sliding:
		is_crouching = true

	if is_crouching and not is_sliding:
		is_sprinting = false

	handle_crouch(delta)

	if Input.is_action_just_pressed("sprint") and not is_crouching:
		if is_sprinting:
			is_sprinting = false
		elif stamina > min_stamina_to_sprint:
			is_sprinting = true

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	# NEW: double-tap roll request (buffered briefly so a slightly-early tap still counts).
	roll_buffer_timer = max(roll_buffer_timer - delta, 0.0)
	if roll_request_pending:
		if roll_buffer_timer <= 0.0:
			roll_request_pending = false
		elif not is_dashing and dash_cooldown_timer <= 0.0 and stamina >= dash_stamina_cost:
			start_dash(true, roll_request_dir)
			roll_request_pending = false

	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0 and stamina >= dash_stamina_cost:
		start_dash()

	var flat_speed := Vector2(velocity.x, velocity.z).length()

	if Input.is_action_just_pressed("crouch") \
	and is_on_floor() \
	and not is_sliding \
	and not is_dashing \
	and flat_speed > 4.0 \
	and (is_sprinting or slide_from_walk) \
	and input_dir.length() > 0.5:
		start_slide()

	elif Input.is_action_just_pressed("crouch") and is_on_floor() and not is_sliding and not is_dashing:
		is_crouching = !is_crouching

	# Crouch in mid-air = ground slam
	if Input.is_action_just_pressed("crouch") and not is_on_floor() and not is_slamming and not is_dashing:
		start_slam()

	# NEW: "and not is_dashing" — a roll no longer gets frozen in place by wall cling.
	if is_on_wall() and not is_on_floor() and not is_wall_clinging and not is_sliding and not is_slamming and not is_dashing and velocity.y < 0.0:
		var space_state = get_world_3d().direct_space_state
		var ray = PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + (-wall_cling_normal if wall_cling_normal != Vector3.ZERO else -transform.basis.z) * 0.6
		)
		ray.exclude = [self]
		var ray_chest = PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.5,
			global_position + Vector3.UP * 0.5 + (-get_wall_normal()) * 0.6
		)
		ray_chest.exclude = [self]
		var ray_waist = PhysicsRayQueryParameters3D.create(
			global_position + Vector3.DOWN * 0.3,
			global_position + Vector3.DOWN * 0.3 + (-get_wall_normal()) * 0.6
		)
		ray_waist.exclude = [self]

		var result_center = space_state.intersect_ray(ray)
		var result_chest = space_state.intersect_ray(ray_chest)
		var result_waist = space_state.intersect_ray(ray_waist)

		var hit_center = not result_center.is_empty() and not (result_center.collider and result_center.collider.is_in_group("enemy"))
		var hit_chest = not result_chest.is_empty() and not (result_chest.collider and result_chest.collider.is_in_group("enemy"))
		var hit_waist = not result_waist.is_empty() and not (result_waist.collider and result_waist.collider.is_in_group("enemy"))

		var hits = int(hit_center) + int(hit_chest) + int(hit_waist)
		if hits >= 2:
			is_wall_clinging = true
			wall_cling_normal = get_wall_normal()

	if is_wall_clinging and is_on_floor():
		is_wall_clinging = false

	if not is_on_floor():
		if is_wall_clinging:
			velocity = Vector3.ZERO
		elif is_slamming:
			pass  # slam sets its own vertical speed below
		else:
			var g := get_gravity() * delta
			if velocity.y < 0.0:
				g *= fall_gravity_mult
			if is_dashing and roll_is_air:
				g *= air_roll_gravity_mult
			velocity += g

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# ---- Sprint ramp-up: takes sprint_ramp_time to reach full sprint speed ----
	# sprint_input = you're sprinting and moving; the ramp only builds on the ground but is HELD
	# (not reset) in the air, so you keep full sprint speed through a jump instead of dropping to a walk.
	var sprint_input := is_sprinting and not is_crouching and not is_sliding and direction.length() > 0.1
	if sprint_input and is_on_floor():
		sprint_ramp = min(sprint_ramp + delta / sprint_ramp_time, 1.0)
	elif sprint_input and not is_on_floor():
		pass
	else:
		sprint_ramp = max(sprint_ramp - delta / (sprint_ramp_time * 0.5), 0.0)

	# ---- Stamina ----
	# Drains while sprinting. Jumps take a one-time chunk (see _spend_jump_stamina). Touching or clinging to a wall
	# in the air refills it fast, with an instant burst on first contact. Otherwise it regens after a short delay.
	var wall_contact := not is_on_floor() and (is_on_wall() or is_wall_clinging)
	wall_hit_cooldown_timer = max(wall_hit_cooldown_timer - delta, 0.0)

	if wall_contact:
		if not was_wall_contact and wall_hit_cooldown_timer <= 0.0:
			stamina = min(stamina + wall_hit_stamina_burst, max_stamina)
			wall_hit_cooldown_timer = wall_hit_cooldown
		stamina = min(stamina + wall_stamina_regen_rate * delta, max_stamina)
		stamina_regen_timer = 0.0
		stats_changed.emit()
	elif sprint_input:
		stamina = max(stamina - stamina_drain_rate * delta, 0.0)
		stamina_regen_timer = stamina_regen_delay
		stats_changed.emit()
	else:
		stamina_regen_timer = max(stamina_regen_timer - delta, 0.0)
		if stamina_regen_timer <= 0.0:
			var prev_stamina := stamina
			stamina = min(stamina + stamina_regen_rate * delta, max_stamina)
			if stamina != prev_stamina:
				stats_changed.emit()
	was_wall_contact = wall_contact

	if is_dashing:
		dash_timer -= delta

		if is_rolling:
			# Roll surges forward then settles (see _roll_speed_at); roll_progress also drives FOV / camera.
			roll_progress = clampf(1.0 - dash_timer / maxf(roll_duration, 0.01), 0.0, 1.0)
			var roll_spd := _roll_speed_at(roll_progress)
			velocity.x = dash_direction.x * roll_spd
			velocity.z = dash_direction.z * roll_spd
			# velocity.y is left alone: on the ground it stays put, in the air gravity keeps acting.
		else:
			# Plain dash: full speed at launch, easing down to the exit speed so it doesn't snap when it ends.
			var dash_progress := clampf(1.0 - dash_timer / maxf(dash_duration, 0.01), 0.0, 1.0)
			var dash_spd := dash_speed * lerpf(1.0, dash_exit_momentum, smoothstep(0.0, 1.0, dash_progress))
			velocity = dash_direction * dash_spd

		if dash_timer <= 0.0:
			_end_dash()

	elif is_wall_clinging:
		velocity = Vector3.ZERO

	elif is_slamming:
		velocity.x = move_toward(velocity.x, 0.0, slam_air_drag * delta)
		velocity.z = move_toward(velocity.z, 0.0, slam_air_drag * delta)
		velocity.y = -slam_speed

	else:

		if is_sliding:
			slide_timer -= delta

			var slope_factor := 1.0
			if is_on_floor():
				var n = get_floor_normal()
				var slope = rad_to_deg(acos(n.dot(Vector3.UP)))
				if slope > 5.0:
					slope_factor = 1.0 + (slope / 45.0) * slope_slide_boost

			slide_speed -= slide_friction * delta
			slide_speed = max(slide_speed, 0.0)

			velocity.x = slide_direction.x * slide_speed * slope_factor
			velocity.z = slide_direction.z * slide_speed * slope_factor

			if slide_timer <= 0.0 or slide_speed < 2.0:
				stop_slide()

		else:
			var current_speed = speed

			# Direction relative to facing: 1 = straight forward, -1 = straight backward.
			var move_dot := 0.0
			if direction.length() > 0.01:
				move_dot = direction.dot(-transform.basis.z)

			var dir_mult := 1.0
			if move_dot < -0.3:
				dir_mult = backpedal_speed_mult
			elif absf(move_dot) < 0.6:
				dir_mult = strafe_speed_mult

			if is_crouching:
				current_speed = crouch_speed * dir_mult
			elif is_sprinting:
				# Fatigue: speed tapers off as stamina runs low instead of hard-cutting
				var stamina_ratio: float = stamina / max_stamina
				var stamina_mult: float = lerp(
					low_stamina_speed_mult,
					1.0,
					clampf(stamina_ratio / stamina_taper_ratio, 0.0, 1.0)
				)

				var target_sprint_speed: float = sprint_speed * dir_mult * stamina_mult
				current_speed = lerp(speed * dir_mult, target_sprint_speed, sprint_ramp)
			else:
				current_speed = speed * dir_mult

			# Slope handling: running uphill is slower, downhill is faster.
			if is_on_floor() and direction.length() > 0.01:
				var floor_normal := get_floor_normal()
				var slope_deg := rad_to_deg(acos(clampf(floor_normal.dot(Vector3.UP), -1.0, 1.0)))
				if slope_deg > 3.0:
					var downhill_dir := Vector3(floor_normal.x, 0, floor_normal.z).normalized()
					var uphill_dir := -downhill_dir
					var uphill_amount := direction.dot(uphill_dir)  # 1 = straight uphill, -1 = straight downhill
					var slope_ratio := clampf(slope_deg / 45.0, 0.0, 1.0)

					if uphill_amount > 0.0:
						current_speed *= 1.0 - uphill_amount * slope_ratio * uphill_slowdown_strength
					else:
						current_speed *= 1.0 + (-uphill_amount) * slope_ratio * downhill_speedup_strength

			# Momentum: if reversing direction sharply, brake hard first.
			var horizontal_vel := Vector2(velocity.x, velocity.z)
			var desired_dir2 := Vector2(direction.x, direction.z)
			var vel_dot := 0.0
			if horizontal_vel.length() > 0.3 and desired_dir2.length() > 0.01:
				vel_dot = horizontal_vel.normalized().dot(desired_dir2.normalized())

			# While being knocked back, you have much less control for a moment.
			var control := 0.15 if knockback_timer > 0.0 else 1.0

			var wish: Vector2 = desired_dir2 * current_speed
			var cur_speed := horizontal_vel.length()

			if is_on_floor():
				var accel := ground_accel
				if vel_dot < turn_brake_dot_threshold:
					accel = ground_decel * turn_brake_mult
				elif cur_speed > current_speed and vel_dot > 0.0:
					# Carrying extra speed (from a jump/dash/slide): let it fade slowly
					# instead of snapping straight back down to run speed.
					accel = ground_overspeed_decel
				accel *= control

				if direction:
					horizontal_vel = horizontal_vel.move_toward(wish, accel * delta)
				else:
					horizontal_vel = horizontal_vel.move_toward(Vector2.ZERO, ground_decel * control * delta)
			elif direction:
				# In the air there's no friction, so momentum carries. You can steer, and build speed up
				# to your run speed, but you never get slowed down below the speed you jumped with.
				var air_a := air_accel * control
				if cur_speed <= current_speed:
					horizontal_vel = horizontal_vel.move_toward(wish, air_a * delta)
				else:
					horizontal_vel = (horizontal_vel + desired_dir2.normalized() * air_a * delta).limit_length(cur_speed)

			velocity.x = horizontal_vel.x
			velocity.z = horizontal_vel.y

	if Input.is_action_just_pressed("jump"):

		if is_on_floor():
			if is_dashing:
				_end_dash()   # jumping out of a dash/roll carries its momentum

			var final_jump := jump_velocity

			if is_sprinting:
				final_jump *= sprint_jump_boost

			if is_sliding:
				final_jump *= slide_jump_boost

				var horiz := Vector2(velocity.x, velocity.z)
				horiz *= slide_exit_speed_boost
				velocity.x = horiz.x
				velocity.z = horiz.y
				stop_slide()   # end the slide so the boosted speed carries through the air

			velocity.y = max(velocity.y, final_jump)
			_spend_jump_stamina()

		elif is_wall_clinging:
			is_wall_clinging = false

			var wall_normal = wall_cling_normal
			velocity += wall_normal * wall_jump_speed_scale

			var horizontal_speed = Vector2(velocity.x, velocity.z).length()

			var up_boost = clamp(
				horizontal_speed * 0.22 * wall_jump_up_boost,
				min_wall_jump_up * wall_jump_up_boost,
				max_wall_jump_up * wall_jump_up_boost
			)

			velocity.y = up_boost
			velocity += -transform.basis.z * wall_jump_speed_scale

		elif is_on_wall():
			var wall_normal = get_wall_normal()

			velocity += wall_normal * wall_jump_speed_scale

			var horizontal_speed = Vector2(velocity.x, velocity.z).length()

			var up_boost = clamp(
				horizontal_speed * 0.22 * wall_jump_up_boost,
				min_wall_jump_up * wall_jump_up_boost,
				max_wall_jump_up * wall_jump_up_boost
			)

			velocity.y = up_boost
			velocity += -transform.basis.z * wall_jump_speed_scale

	if is_on_floor():
		if not was_on_floor:
			if velocity.length() > speed:
				velocity.x *= bhop_speed_boost
				velocity.z *= bhop_speed_boost

				var h_vel := Vector2(velocity.x, velocity.z)
				h_vel = h_vel.limit_length(max_bhop_speed)
				velocity.x = h_vel.x
				velocity.z = h_vel.y

		if auto_bhop and Input.is_action_pressed("jump"):
			if velocity.y < jump_velocity:
				_spend_jump_stamina()   # an auto-hop is a jump too (skipped if a normal jump already paid this frame)
			velocity.y = max(velocity.y, jump_velocity)

	was_on_floor = is_on_floor()

	move_and_slide()

	# NEW: landed before finishing an air roll = you botch it and tumble.
	if is_dashing and is_rolling and roll_is_air and is_on_floor() \
	and roll_progress < air_roll_complete_progress:
		_start_knockdown()

	if is_slamming and is_on_floor():
		_slam_impact()

	# Fell off the map = dead (then respawns like any other death).
	if global_position.y < kill_height:
		die(void_respawn_delay)

	update_fov(delta)
	update_camera_tilt(delta)
	apply_headbob(delta)


# -------------------------
# HEALTH / SHIELD
# -------------------------

## Matches the signature bullet.gd already calls on enemies:
## body.take_damage(dmg, hit_point, shooter) — so bullet.gd needs NO changes
## to also damage the player. Shield absorbs first, then health.
func take_damage(amount: float, hit_point: Vector3 = Vector3.ZERO, shooter: Node = null) -> void:
	if is_dead or amount <= 0.0 or invuln_timer > 0.0:
		return

	var remaining := amount
	var had_shield := shield > 0.0

	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed

	if remaining > 0.0:
		health = max(health - remaining, 0.0)

	shield_regen_timer = shield_regen_delay
	health_regen_timer = health_regen_delay
	invuln_timer = invuln_time

	_flash_damage(amount - remaining, remaining)   # (damage the shield took, damage health took)

	# A hit that fully breaks the shield makes it take longer to come back.
	if had_shield and shield <= 0.0:
		shield_regen_timer = shield_regen_delay + shield_break_extra_delay
		shield_broken.emit()

	stats_changed.emit()

	if health <= 0.0 and not is_dead:
		die()


## Builds the maroon vignette overlay in code, so no scene changes are needed.
func _build_damage_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 health_color : source_color = vec4(0.85, 0.05, 0.05, 1.0);
uniform vec4 shield_color : source_color = vec4(0.1, 0.4, 1.0, 1.0);
uniform vec4 both_color : source_color = vec4(0.6, 0.1, 0.9, 1.0);
uniform float health_intensity = 0.0;
uniform float shield_intensity = 0.0;
uniform float both_intensity = 0.0;
uniform float inner_radius = 0.3;
void fragment() {
	float d = length(UV - vec2(0.5)) * 1.4142;
	float v = smoothstep(inner_radius, 1.0, d);
	float total = health_intensity + shield_intensity + both_intensity;
	vec3 col = (health_color.rgb * health_intensity + shield_color.rgb * shield_intensity + both_color.rgb * both_intensity) / max(total, 0.0001);
	float peak = max(max(health_intensity, shield_intensity), both_intensity);
	COLOR = vec4(col, clamp(v * peak, 0.0, 1.0));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("health_color", health_flash_color)
	mat.set_shader_parameter("shield_color", shield_flash_color)
	mat.set_shader_parameter("both_color", both_flash_color)
	mat.set_shader_parameter("inner_radius", damage_flash_inner)
	mat.set_shader_parameter("health_intensity", 0.0)
	mat.set_shader_parameter("shield_intensity", 0.0)
	mat.set_shader_parameter("both_intensity", 0.0)

	damage_flash_rect = ColorRect.new()
	damage_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash_rect.material = mat
	layer.add_child(damage_flash_rect)


## Kick the flash: blue if only the shield took damage, red if only health did, purple if one hit
## hurt both. Bigger hits flash harder.
func _flash_damage(shield_dmg: float, health_dmg: float) -> void:
	if shield_dmg > 0.0 and health_dmg > 0.0:
		var total := shield_dmg + health_dmg
		var bs := lerpf(damage_flash_min, damage_flash_max, clampf(total / ((max_health + max_shield) * 0.3), 0.0, 1.0))
		both_flash = maxf(both_flash, bs)
		return
	if shield_dmg > 0.0:
		var ss := lerpf(damage_flash_min, damage_flash_max, clampf(shield_dmg / (max_shield * 0.4), 0.0, 1.0))
		shield_flash = maxf(shield_flash, ss)
	if health_dmg > 0.0:
		var hs := lerpf(damage_flash_min, damage_flash_max, clampf(health_dmg / (max_health * 0.4), 0.0, 1.0))
		health_flash = maxf(health_flash, hs)


## Call for healing pickups — only restores health, not shield.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = min(health + amount, max_health)
	stats_changed.emit()


## Call for shield pickups — instant restore, separate from passive regen.
func add_shield(amount: float) -> void:
	if amount <= 0.0:
		return
	shield = min(shield + amount, max_shield)
	stats_changed.emit()


## Called by enemies when they land a hit. Shoves the player and briefly
## reduces air/ground control so the hit actually feels like something.
func apply_knockback(impulse: Vector3) -> void:
	velocity += impulse
	knockback_timer = 0.25
	is_sliding = false
	is_wall_clinging = false


## Kill the player and schedule a respawn. `wait` < 0 uses respawn_delay.
func die(wait: float = -1.0) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0

	is_sliding = false
	is_dashing = false
	is_rolling = false
	roll_is_air = false
	is_knocked_down = false
	roll_request_pending = false
	is_slamming = false
	is_wall_clinging = false
	is_crouching = false
	is_sprinting = false
	is_zooming = false

	stats_changed.emit()
	died.emit()

	var t := respawn_delay if wait < 0.0 else wait
	await get_tree().create_timer(t).timeout
	respawn()


func respawn() -> void:
	global_position = spawn_position
	rotation = Vector3(0.0, spawn_yaw, 0.0)
	pitch = 0.0
	head.rotation.x = 0.0
	velocity = Vector3.ZERO

	health = max_health
	shield = max_shield
	stamina = max_stamina
	dash_cooldown_timer = 0.0
	stamina_regen_timer = 0.0
	shield_regen_timer = 0.0
	health_regen_timer = 0.0
	knockback_timer = 0.0
	knockdown_timer = 0.0
	is_knocked_down = false
	roll_is_air = false
	was_wall_contact = false
	wall_hit_cooldown_timer = 0.0
	health_flash = 0.0
	shield_flash = 0.0
	both_flash = 0.0
	restore_camera_pitch = false
	sprint_ramp = 0.0
	was_on_floor = false

	# Undo the death-cam and crouch squash.
	camera.rotation = Vector3(base_camera_rot_x, 0.0, 0.0)
	camera.position = base_camera_pos
	var shape = collision.shape as CapsuleShape3D
	if shape:
		shape.height = stand_height

	is_dead = false
	invuln_timer = respawn_invuln_time
	stats_changed.emit()
	respawned.emit()


## While dead: no input, body settles to the ground, camera slumps over.
func _dead_physics(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(65.0), 3.0 * delta)
	camera.position.y = lerp(camera.position.y, crouch_cam_y - 0.4, 3.0 * delta)


func update_health_and_shield(delta: float) -> void:
	if is_dead:
		return

	invuln_timer = max(invuln_timer - delta, 0.0)

	var changed := false

	# Shield regenerates on its own delay/rate once out of combat.
	shield_regen_timer = max(shield_regen_timer - delta, 0.0)
	if shield_regen_timer <= 0.0 and shield < max_shield:
		shield = min(shield + shield_regen_rate * delta, max_shield)
		changed = true

	# Health only regens if health_regen_rate > 0 (off by default).
	health_regen_timer = max(health_regen_timer - delta, 0.0)
	if health_regen_rate > 0.0 and health_regen_timer <= 0.0 and health < max_health:
		health = min(health + health_regen_rate * delta, max_health)
		changed = true

	if changed:
		stats_changed.emit()


# -------------------------
# DASH / ROLL
# -------------------------

## NEW: one-time stamina chunk for a jump. Never blocks the jump — it just bottoms out at 0.
func _spend_jump_stamina() -> void:
	if jump_stamina_cost <= 0.0:
		return
	stamina = max(stamina - jump_stamina_cost, 0.0)
	stamina_regen_timer = stamina_regen_delay
	stats_changed.emit()


## How many full dashes your current stamina can pay for (handy for a HUD readout).
func get_dash_charges() -> int:
	return int(stamina / dash_stamina_cost + 0.0001)


func start_dash(force_roll := false, tap_dir := Vector2.ZERO):
	# Dashing while crouched, sliding, or in mid-air turns the dash into a roll.
	# NEW: a double-tapped movement key (force_roll) is always a roll, even standing on the ground.
	var rolling := force_roll or is_crouching or is_sliding or not is_on_floor()

	# Leaving a slide into a roll keeps you low; a normal dash out of a slide is not possible anymore.
	if is_sliding:
		is_sliding = false

	is_slamming = false
	is_wall_clinging = false
	is_sprinting = false

	is_rolling = rolling
	roll_is_air = rolling and not is_on_floor()   # NEW: air rolls get the gentler camera + the "must finish it" rule
	roll_progress = 0.0
	# Never roll slower than the speed you were already carrying (keeps momentum).
	roll_current_speed = maxf(air_roll_min_speed if roll_is_air else roll_speed, Vector2(velocity.x, velocity.z).length())

	is_dashing = true
	dash_timer = roll_duration if rolling else dash_duration
	dash_cooldown_timer = dash_cooldown

	# Dashing/rolling costs stamina and pauses stamina regen briefly.
	stamina = max(stamina - dash_stamina_cost, 0.0)
	stamina_regen_timer = stamina_regen_delay
	stats_changed.emit()

	if rolling:
		if roll_grants_iframes:
			invuln_timer = max(invuln_timer, roll_iframe_time)
	elif dash_grants_iframes:
		invuln_timer = max(invuln_timer, dash_duration + 0.05)

	var input_dir := Input.get_vector("move_left","move_right","move_forward","move_back")
	# Roll direction comes from the movement keys, not from where the mouse is looking.
	# (If the tapped key was already released, fall back to the direction that was tapped.)
	if input_dir.length() < 0.1 and tap_dir != Vector2.ZERO:
		input_dir = tap_dir
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if dir.length() == 0:
		dir = -transform.basis.z

	dash_direction = dir.normalized()


func _end_dash() -> void:
	is_dashing = false

	# Keep some momentum instead of stopping dead — lets you chain a dash/roll into a jump or slide.
	var exit_speed := _roll_speed_at(roll_progress) if is_rolling else dash_speed * dash_exit_momentum
	var exit_vel := dash_direction * exit_speed
	if is_rolling:
		exit_vel.y = velocity.y   # don't freeze vertical motion when an air roll ends
	velocity = exit_vel

	if is_rolling:
		is_rolling = false
		roll_is_air = false
		roll_progress = 0.0
		# A full 360° spin ends exactly where it started; snap the camera back to neutral.
		camera.rotation.x = base_camera_rot_x
		camera.rotation.z = 0.0


## NEW: 0 -> 1 -> 0 bump over a roll (p = 0..1). Rises quickly (peak about 30% in) and eases back to 0 at the end.
func _roll_surge(p: float) -> float:
	return sin(PI * pow(clampf(p, 0.0, 1.0), 0.6))


## NEW: speed of the current roll at progress p (0..1).
## Air roll: entry speed -> small surge -> back to the entry speed (so nothing snaps when it ends).
## Ground roll: surge at the start, then settles to roll_exit_momentum of its speed.
func _roll_speed_at(p: float) -> float:
	var surge := _roll_surge(p)
	if roll_is_air:
		return roll_current_speed * (1.0 + air_roll_speed_boost * surge)
	var settle := lerpf(1.0, roll_exit_momentum, smoothstep(0.0, 1.0, p))
	return roll_current_speed * settle * (1.0 + ground_roll_surge * surge)


## NEW: a roll that runs head-on into a wall kicks you off it, like a wall jump.
## Returns true if the bounce happened.
func _try_roll_wall_bounce() -> bool:
	var n := get_wall_normal()
	n.y = 0.0
	if n.length() < 0.1:
		return false
	n = n.normalized()

	# Only bounce if the roll is actually heading into the wall (not just grazing along it).
	if dash_direction.dot(n) > -roll_wall_bounce_min_dot:
		return false

	# Kick away from the wall: reflect the roll direction, blended with the wall normal so it never skims along it.
	var out := (dash_direction.bounce(n) + n).normalized()
	var h_speed := maxf(roll_current_speed * roll_wall_bounce_speed_mult, 6.0)

	# End the roll without the usual exit-momentum rewrite.
	is_dashing = false
	is_rolling = false
	roll_is_air = false
	roll_progress = 0.0
	is_wall_clinging = false
	restore_camera_pitch = true   # camera eases back to level instead of snapping

	velocity.x = out.x * h_speed
	velocity.z = out.z * h_speed
	# Same up-boost formula as your normal wall jump, scaled down a bit.
	velocity.y = clampf(
		h_speed * 0.22 * wall_jump_up_boost,
		min_wall_jump_up * wall_jump_up_boost,
		max_wall_jump_up * wall_jump_up_boost
	) * roll_wall_bounce_up_mult

	# Reward the wall-kick so you can chain it into another dash.
	stamina = minf(stamina + roll_wall_bounce_stamina_refund, max_stamina)
	stamina_regen_timer = stamina_regen_delay
	dash_cooldown_timer = 0.0
	stats_changed.emit()
	roll_wall_bounced.emit()
	return true


# -------------------------
# KNOCKDOWN (failed air roll)
# -------------------------
func _start_knockdown() -> void:
	# Tilt the camera toward the side you were rolling.
	var local_dir := global_transform.basis.inverse() * dash_direction
	knockdown_tilt_sign = -1.0 if local_dir.x < 0.0 else 1.0

	is_dashing = false
	is_rolling = false
	roll_is_air = false
	roll_progress = 0.0

	is_knocked_down = true
	knockdown_timer = knockdown_duration

	is_sprinting = false
	is_crouching = false
	is_sliding = false
	is_slamming = false
	is_wall_clinging = false
	sprint_ramp = 0.0

	# Skid for a moment instead of stopping dead.
	velocity.x *= 0.6
	velocity.z *= 0.6
	velocity.y = 0.0
	dash_cooldown_timer = knockdown_duration
	knocked_down.emit()


func _knockdown_physics(delta: float) -> void:
	knockdown_timer -= delta

	velocity.x = move_toward(velocity.x, 0.0, knockdown_friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, knockdown_friction * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta

	was_on_floor = is_on_floor()
	move_and_slide()

	if global_position.y < kill_height:
		die(void_respawn_delay)
		return

	if knockdown_timer <= 0.0:
		# Back on your feet — unless there's a low ceiling, then stay crouched.
		is_knocked_down = false
		is_crouching = not can_stand_up()
		restore_camera_pitch = true

	handle_crouch(delta)
	update_fov(delta)
	update_camera_tilt(delta)
	apply_headbob(delta)


# -------------------------
# GROUND SLAM
# -------------------------
func start_slam() -> void:
	is_slamming = true
	is_wall_clinging = false
	is_sprinting = false
	velocity.x *= 0.3
	velocity.z *= 0.3
	velocity.y = -slam_speed


func _slam_impact() -> void:
	is_slamming = false
	var hit_pos := global_position

	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not e.has_method("take_damage"):
			continue
		var d: float = e.global_position.distance_to(hit_pos)
		if d <= slam_radius:
			var falloff := 1.0 - clampf(d / slam_radius, 0.0, 1.0) * 0.5
			e.take_damage(slam_damage * falloff, e.global_position, self)

	# Hold jump as you land for a big bounce.
	if Input.is_action_pressed("jump"):
		velocity.y = slam_bounce_velocity


# -------------------------
# SLIDE
# -------------------------
func start_slide():
	is_sliding = true
	slide_timer = slide_duration
	slide_speed = slide_base_speed * slide_burst

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.1:
		slide_direction = flat.normalized()
	else:
		slide_direction = -transform.basis.z

	is_crouching = true


func stop_slide():
	is_sliding = false

	if can_stand_up():
		is_crouching = false
		is_sprinting = true


func can_stand_up() -> bool:
	var space_state = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.UP * headspace_check_distance
	)

	query.exclude = [self]

	return space_state.intersect_ray(query).is_empty()


# -------------------------
# FOV
# -------------------------
func update_fov(delta: float) -> void:
	# While aiming, the weapon script (handle_ads) owns camera.fov directly —
	# don't fight it here.
	if is_zooming:
		return

	var target = normal_fov

	var sprint_multiplier := 1.6 if is_sprinting else 1.0

	if is_rolling:
		# FOV follows the speed surge: widens a little as you launch, then settles back.
		var surge := _roll_surge(roll_progress)
		if roll_is_air:
			target = normal_fov + air_roll_fov_kick * surge
		else:
			target = normal_fov + roll_fov_change + roll_fov_kick * surge
	elif is_dashing:
		target = dash_fov
	elif is_slamming:
		target = slam_fov
	elif is_wall_clinging:
		target = wall_cling_fov
	elif is_sliding:
		# Slide widens further than sprint, scaled by how fast the slide still is.
		var slide_amount := clampf(slide_speed / slide_base_speed, 0.0, 1.0)
		target = lerp(normal_fov, slide_fov, slide_amount)
	elif is_sprinting:
		# FOV widens in step with the sprint ramp-up, not instantly
		target = lerp(normal_fov, sprint_fov, sprint_ramp)
	elif is_crouching or is_knocked_down:
		target = normal_fov - 5.0

	current_fov = lerp(current_fov, target, fov_speed * sprint_multiplier * delta)
	camera.fov = current_fov


# -------------------------
# CAMERA TILT
# -------------------------
func update_camera_tilt(delta: float) -> void:
	# Roll camera.
	if is_rolling:
		var local_dir := global_transform.basis.inverse() * dash_direction

		# AIR roll = the camera stays level (no tilt, no spin). The speed surge + FOV kick carry the feel.
		if roll_is_air:
			camera.rotation.x = lerp(camera.rotation.x, base_camera_rot_x, 10.0 * delta)
			camera.rotation.z = lerp(camera.rotation.z, 0.0, 10.0 * delta)
			return

		# GROUND roll (unchanged): backward = back-flip, sideways = barrel roll, forward = no camera flip,
		# or just a gentle tilt if roll_full_spin is off.
		var amount: float
		if roll_full_spin:
			# Smoothstep easing: the spin starts and ends gently instead of snapping.
			var eased := roll_progress * roll_progress * (3.0 - 2.0 * roll_progress)
			amount = deg_to_rad(roll_spin_degrees) * eased
		else:
			# Smooth dip that peaks mid-roll and returns to level by the end — no spinning.
			amount = deg_to_rad(roll_camera_tilt_degrees) * sin(roll_progress * PI)
		# No front rolls: only a backward roll pitches the camera. Forward rolls get no flip
		# (sideways rolls still barrel-roll via the z rotation below).
		# Spin around ONE axis at the full angle, so diagonals do the whole flip too. (The old per-axis split
		# scaled each part by the direction's x/z, so a 45° roll only reached ~70% of the spin.)
		var spin_axis := Vector3(maxf(local_dir.z, 0.0), 0.0, -local_dir.x)
		if spin_axis.length() > 0.01:
			camera.basis = Basis(spin_axis.normalized(), amount) * Basis.from_euler(Vector3(base_camera_rot_x, 0.0, 0.0))
		return

	# NEW: knocked down — camera lists to one side and looks slightly down, easing back to level as you get up.
	if is_knocked_down:
		var k := clampf(knockdown_timer / maxf(knockdown_duration, 0.01), 0.0, 1.0)
		var target_z := deg_to_rad(knockdown_camera_tilt_degrees) * knockdown_tilt_sign * k
		var target_x := base_camera_rot_x - deg_to_rad(6.0) * k
		camera.rotation.z = lerp(camera.rotation.z, target_z, 12.0 * delta)
		camera.rotation.x = lerp(camera.rotation.x, target_x, 12.0 * delta)
		return

	var target_roll := 0.0

	if is_wall_clinging:
		target_roll = -wall_cling_normal.x * 12.0
	elif is_sliding:
		target_roll = slide_tilt_amount * slide_direction.x

	camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(target_roll), 6.0 * delta)

	# NEW: after a wall bounce / getting up, ease the camera pitch back to neutral (only then, so this
	# never fights anything else that touches camera.rotation.x, like recoil).
	if restore_camera_pitch:
		camera.rotation.x = lerp(camera.rotation.x, base_camera_rot_x, 8.0 * delta)
		if absf(camera.rotation.x - base_camera_rot_x) < 0.002:
			camera.rotation.x = base_camera_rot_x
			restore_camera_pitch = false

	var pos := camera.position
	pos.x = lerp(pos.x, slide_direction.x * slide_lean_amount, 6.0 * delta)
	camera.position = pos


# -------------------------
# CROUCH
# -------------------------
func handle_crouch(delta: float) -> void:
	var shape = collision.shape as CapsuleShape3D
	if not shape:
		return

	# Rolling (including in the air) and being knocked down both tuck you down to crouch size.
	var low := is_crouching or is_rolling or is_knocked_down
	var target_h = crouch_height if low else stand_height
	var target_y = crouch_cam_y if low else stand_cam_y
	if is_knocked_down:
		target_y = crouch_cam_y - knockdown_camera_drop   # lower still; rises as you get up

	shape.height = lerp(shape.height, target_h, crouch_lerp_speed * delta)
	camera.position.y = lerp(camera.position.y, target_y, crouch_lerp_speed * delta)


# -------------------------
# HEAD BOB
# -------------------------
func apply_headbob(delta: float) -> void:
	if is_rolling or is_knocked_down:
		return  # no bobbing on top of the roll tilt / knockdown drop

	var moving := is_on_floor() and velocity.length() > 0.1

	if not moving:
		bob_time = 0.0
		camera.position = camera.position.lerp(base_camera_pos, 10.0 * delta)
		return

	var spd := walk_bob_speed
	var amt := walk_bob_amount

	if is_crouching:
		spd = crouch_bob_speed
		amt = crouch_bob_amount
	elif is_sprinting:
		spd = sprint_bob_speed
		amt = sprint_bob_amount

	bob_time += delta * spd

	var offset := Vector3(
		sin(bob_time * 2.5) * amt * 0.4,
		sin(bob_time * 1.2) * amt * 1.8,
		0
	)

	camera.position = camera.position.lerp(base_camera_pos + offset, 12.0 * delta)
