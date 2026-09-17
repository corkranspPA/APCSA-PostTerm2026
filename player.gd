extends CharacterBody3D

@export var speed := 6.0            # brisk walking pace, m/s
@export var sprint_speed := 9.5     # top sustained sprint, m/s
@export var crouch_speed := 2.6     # crouched movement speed, m/s

@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var crouch_lerp_speed := 10.0

# -------------------------
# REALISTIC GROUND MOVEMENT
# -------------------------
@export var ground_accel := 32.0          # how quickly velocity ramps toward target speed
@export var ground_decel := 36.0          # how quickly velocity bleeds off when stopping/turning
@export var air_accel := 7.0              # (kept modest so air control still feels floaty/arcadey if you use it)

@export var sprint_ramp_time := 0.35      # seconds to build up from standstill to full sprint speed
@export var backpedal_speed_mult := 0.6   # running backwards is slower than forward
@export var strafe_speed_mult := 0.8      # side-stepping is slower than a straight sprint

@export var uphill_slowdown_strength := 0.5    # 0 = no effect, 1 = strong slowdown running uphill
@export var downhill_speedup_strength := 0.3   # 0 = no effect, 1 = strong speedup running downhill
@export var turn_brake_mult := 1.8             # extra deceleration when reversing direction sharply
@export var turn_brake_dot_threshold := -0.3   # how sharp a direction change counts as "reversing"

var sprint_ramp := 0.0  # 0..1, how "spooled up" the current sprint is

# -------------------------
# STAMINA (fatigue while sprinting)
# -------------------------
@export var max_stamina := 10.0
@export var stamina_drain_rate := 1.0        # stamina lost per second while actively sprinting
@export var stamina_regen_rate := 1.6        # stamina gained per second once recovering
@export var stamina_regen_delay := 0.8       # seconds after you stop sprinting before regen kicks in
@export var min_stamina_to_sprint := 0.5     # can't START a new sprint below this
@export var low_stamina_speed_mult := 0.55   # sprint speed multiplier once fully gassed
@export var stamina_taper_ratio := 0.3       # below this fraction of max stamina, speed starts tapering

var stamina := 10.0
var stamina_regen_timer := 0.0

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
# DASH SYSTEM (NEW)
# -------------------------
@export var dash_speed := 18.0
@export var dash_duration := 0.15
@export var dash_cooldown := 0.8

var is_dashing := false
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := Vector3.ZERO

# -------------------------
# SLIDE SYSTEM
# -------------------------
@export var slide_base_speed := 14.0
@export var slide_duration := 1.0
@export var slide_friction := 4.5
@export var slide_burst := 1.6
@export var slope_slide_boost := 2.2

var is_sliding := false
var slide_timer := 0.0
var slide_direction := Vector3.ZERO
var slide_speed := 0.0

# -------------------------
# FOV SYSTEM
# -------------------------
@export var normal_fov := 75.0
@export var sprint_fov := 105.0     # widens while sprinting for a sense of speed
@export var slide_fov := 110.0      # widens further while sliding
@export var dash_fov := 100.0       # dash also widens briefly for a burst-of-speed feel
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
@onready var Weapon = $Head/Camera3D/Weapon  # adjust this path to match your scene tree

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
@export var squint_speed_ref := 9.5     # speed (m/s) that counts as "fully squinted" — match sprint_speed
@export var squint_smoothing := 6.0     # higher = vignette reacts to speed changes faster
@export var squint_extra_when_exhausted := 0.2  # extra squint added as stamina bottoms out
@export var squint_slide_boost := 0.35  # extra squint added while sliding, on top of speed
@export var squint_crouch_boost := 0.12  # slight extra squint while crouched (not sliding)
@export var squint_zoom_boost := 0.3    # extra squint while aiming/zoomed in (ADS)

# Set true/false by the weapon script whenever ADS starts/stops (see weapon's _process,
# which already checks Input.is_action_pressed("aim")).
var is_zooming := false

# Point this at your ColorRect overlay in the editor (or set it in _ready()).
# Give the ColorRect a Unique Name (%EyelidOverlay) in your scene, or fix this path.
@onready var eyelid_overlay: ColorRect = get_node_or_null("%EyelidOverlay")

var current_squint := 0.0


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

	stamina = max_stamina

	# ---- NEW: give the weapon a reference to this player ----
	if Weapon:
		Weapon.player = self


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
		)


func _process(delta: float) -> void:
	if eyelid_overlay and eyelid_overlay.material:
		var fatigue := 1.0 - clampf(stamina / max_stamina, 0.0, 1.0)

		# How fast you're actually moving right now, 0..1 relative to squint_speed_ref.
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		var speed_ratio := clampf(horizontal_speed / squint_speed_ref, 0.0, 1.0)

		# Always-on resting pull, plus more the faster you're actually going, plus fatigue.
		var target_squint := base_squint_amount \
			+ speed_ratio * (1.0 - base_squint_amount) \
			+ fatigue * squint_extra_when_exhausted
		if is_sliding:
			target_squint += squint_slide_boost
		elif is_crouching:
			target_squint += squint_crouch_boost
		if is_zooming:
			target_squint += squint_zoom_boost
		target_squint = clampf(target_squint, 0.0, 1.0)

		current_squint = lerp(current_squint, target_squint, squint_smoothing * delta)
		eyelid_overlay.material.set_shader_parameter("squint", current_squint)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)

		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:

	dash_cooldown_timer = max(dash_cooldown_timer - delta, 0.0)

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

	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		start_dash()

	if Input.is_action_just_pressed("crouch") \
	and is_sprinting \
	and is_on_floor() \
	and not is_sliding \
	and velocity.length() > 4.0 \
	and input_dir.y < -0.5:
		start_slide()

	elif Input.is_action_just_pressed("crouch") and is_on_floor() and not is_sliding:
		is_crouching = !is_crouching

	if is_on_wall() and not is_on_floor() and not is_wall_clinging and not is_sliding and velocity.y < 0.0:
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

		print("center: ", result_center.get("collider"), " chest: ", result_chest.get("collider"), " waist: ", result_waist.get("collider"))

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
		else:
			velocity += get_gravity() * delta

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# ---- Sprint ramp-up: takes sprint_ramp_time to reach full sprint speed ----
	var actively_sprinting := is_sprinting and is_on_floor() and not is_crouching and not is_sliding and direction.length() > 0.1
	if actively_sprinting:
		sprint_ramp = min(sprint_ramp + delta / sprint_ramp_time, 1.0)
	else:
		sprint_ramp = max(sprint_ramp - delta / (sprint_ramp_time * 0.5), 0.0)

	# ---- Stamina: drains while actively sprinting, regens after a short delay ----
	if actively_sprinting:
		stamina = max(stamina - stamina_drain_rate * delta, 0.0)
		stamina_regen_timer = stamina_regen_delay
	else:
		stamina_regen_timer = max(stamina_regen_timer - delta, 0.0)
		if stamina_regen_timer <= 0.0:
			stamina = min(stamina + stamina_regen_rate * delta, max_stamina)

	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * dash_speed

		if dash_timer <= 0.0:
			is_dashing = false

	elif is_wall_clinging:
		velocity = Vector3.ZERO

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
			# Now applies to walking too, not just sprinting — real people are also
			# slower moving backward/sideways than straight ahead at any pace.
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
			elif is_sprinting and is_on_floor():
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

			# Slope handling: running uphill is slower, downhill is faster, like
			# working against/with gravity. Skipped on very flat ground.
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

			# Momentum: if reversing direction sharply, brake hard first rather than
			# instantly redirecting at full speed — avoids an "ice skating" feel.
			var horizontal_vel := Vector2(velocity.x, velocity.z)
			var desired_dir2 := Vector2(direction.x, direction.z)
			var vel_dot := 0.0
			if horizontal_vel.length() > 0.3 and desired_dir2.length() > 0.01:
				vel_dot = horizontal_vel.normalized().dot(desired_dir2.normalized())

			# Acceleration/deceleration instead of snapping straight to target speed
			var accel := ground_accel if is_on_floor() else air_accel
			if vel_dot < turn_brake_dot_threshold:
				accel = (ground_decel if is_on_floor() else air_accel) * turn_brake_mult

			if direction:
				velocity.x = move_toward(velocity.x, direction.x * current_speed, accel * delta)
				velocity.z = move_toward(velocity.z, direction.z * current_speed, accel * delta)
			else:
				velocity.x = move_toward(velocity.x, 0, ground_decel * delta)
				velocity.z = move_toward(velocity.z, 0, ground_decel * delta)

	if Input.is_action_just_pressed("jump"):

		if is_on_floor():
			var final_jump := jump_velocity

			if is_sprinting:
				final_jump *= sprint_jump_boost

			if is_sliding:
				final_jump *= slide_jump_boost

				var horiz := Vector2(velocity.x, velocity.z)
				horiz *= slide_exit_speed_boost
				velocity.x = horiz.x
				velocity.z = horiz.y

			velocity.y = final_jump

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
			velocity.y = jump_velocity

	was_on_floor = is_on_floor()

	move_and_slide()

	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
		velocity = Vector3.ZERO
		is_sliding = false
		is_dashing = false
		is_wall_clinging = false
		is_crouching = false
		is_sprinting = false

	update_fov(delta)
	update_camera_tilt(delta)
	apply_headbob(delta)


# -------------------------
# DASH FUNCTION
# -------------------------
func start_dash():
	if is_crouching:
		return

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown

	var input_dir := Input.get_vector("move_left","move_right","move_forward","move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if dir.length() == 0:
		dir = -transform.basis.z

	dash_direction = dir.normalized()


# -------------------------
# SLIDE
# -------------------------
func start_slide():
	is_sliding = true
	slide_timer = slide_duration
	slide_speed = slide_base_speed * slide_burst

	slide_direction = velocity.normalized()
	if slide_direction.length() == 0:
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

	if is_dashing:
		target = dash_fov
	elif is_wall_clinging:
		target = wall_cling_fov
	elif is_sliding:
		# Slide widens further than sprint, scaled by how fast the slide still is.
		var slide_amount := clampf(slide_speed / slide_base_speed, 0.0, 1.0)
		target = lerp(normal_fov, slide_fov, slide_amount)
	elif is_sprinting:
		# FOV widens in step with the sprint ramp-up, not instantly
		target = lerp(normal_fov, sprint_fov, sprint_ramp)
	elif is_crouching:
		target = normal_fov - 5.0

	current_fov = lerp(current_fov, target, fov_speed * sprint_multiplier * delta)
	camera.fov = current_fov


# -------------------------
# CAMERA TILT
# -------------------------
func update_camera_tilt(delta: float) -> void:
	var target_roll := 0.0

	if is_wall_clinging:
		target_roll = -wall_cling_normal.x * 12.0
	elif is_sliding:
		target_roll = slide_tilt_amount * slide_direction.x

	camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(target_roll), 6.0 * delta)

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

	var target_h = crouch_height if is_crouching else stand_height
	var target_y = crouch_cam_y if is_crouching else stand_cam_y

	shape.height = lerp(shape.height, target_h, crouch_lerp_speed * delta)
	camera.position.y = lerp(camera.position.y, target_y, crouch_lerp_speed * delta)


# -------------------------
# HEAD BOB
# -------------------------
func apply_headbob(delta: float) -> void:
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
