extends CharacterBody3D

@export var speed := 6.0
@export var sprint_speed := 10.0
@export var crouch_speed := 3.0

@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var crouch_lerp_speed := 10.0

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
@export var sprint_fov := 100.0
@export var slide_fov := 105.0
@export var dash_fov := 95.0
@export var fov_speed := 7.0

var current_fov := 75.0

# -------------------------
# CAMERA
# -------------------------
@export var slide_tilt_amount := 8.0
@export var slide_lean_amount := 0.12

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D

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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
		)


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
		is_sprinting = !is_sprinting

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

	# Wall cling: only attach if a center raycast confirms solid wall contact
	if is_on_wall() and not is_on_floor() and not is_wall_clinging and not is_sliding and velocity.y < 0.0:
		var space_state = get_world_3d().direct_space_state
		var ray = PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + (-wall_cling_normal if wall_cling_normal != Vector3.ZERO else -transform.basis.z) * 0.6
		)
		ray.exclude = [self]
		# Also cast from chest and waist height to confirm broad contact
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
		var hit_center = not space_state.intersect_ray(ray).is_empty()
		var hit_chest = not space_state.intersect_ray(ray_chest).is_empty()
		var hit_waist = not space_state.intersect_ray(ray_waist).is_empty()
		var hits = int(hit_center) + int(hit_chest) + int(hit_waist)
		if hits >= 2:
			is_wall_clinging = true
			wall_cling_normal = get_wall_normal()

	# Stop clinging only when landing on the floor
	if is_wall_clinging and is_on_floor():
		is_wall_clinging = false

	if not is_on_floor():
		if is_wall_clinging:
			# Completely freeze the player to the wall
			velocity = Vector3.ZERO
		else:
			velocity += get_gravity() * delta

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

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

			if is_crouching:
				current_speed = crouch_speed
			elif is_sprinting and is_on_floor():
				current_speed = sprint_speed

			if direction:
				velocity.x = direction.x * current_speed
				velocity.z = direction.z * current_speed
			else:
				velocity.x = move_toward(velocity.x, 0, current_speed * 0.2)
				velocity.z = move_toward(velocity.z, 0, current_speed * 0.2)

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
			# Jump off the wall
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
	var target = normal_fov

	var sprint_multiplier := 1.6 if is_sprinting else 1.0

	if is_dashing:
		target = dash_fov
	elif is_wall_clinging:
		target = wall_cling_fov
	elif is_sliding:
		target = slide_fov
	elif is_sprinting:
		target = sprint_fov
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
		# Tilt toward the wall based on which side it's on
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
