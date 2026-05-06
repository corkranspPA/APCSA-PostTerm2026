extends CharacterBody3D

@export var speed := 6.0
@export var sprint_speed := 10.0
@export var crouch_speed := 3.0

@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var crouch_lerp_speed := 10.0

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
@export var sprint_fov := 85.0
@export var slide_fov := 105.0
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)

		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
		head.rotation.x = pitch

	if event.is_action_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
		)


func _physics_process(delta: float) -> void:

	if is_sliding:
		is_crouching = true

	handle_crouch(delta)

	if Input.is_action_just_pressed("sprint"):
		is_sprinting = !is_sprinting

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	if Input.is_action_just_pressed("crouch") \
	and is_sprinting \
	and is_on_floor() \
	and not is_sliding \
	and velocity.length() > 4.0 \
	and input_dir.y < -0.5:
		start_slide()

	elif Input.is_action_just_pressed("crouch") and is_on_floor() and not is_sliding:
		is_crouching = !is_crouching

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

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
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	update_fov(delta)
	update_camera_tilt(delta)
	apply_headbob(delta)


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

	camera.fov = slide_fov
	is_crouching = true


func stop_slide():
	is_sliding = false

	# SAFE STAND LOGIC
	if can_stand_up():
		is_crouching = false


# -------------------------
# REQUIRED FIX (WAS MISSING)
# -------------------------
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

	if is_sliding:
		target = slide_fov
	elif is_sprinting:
		target = sprint_fov
	elif is_crouching:
		target = normal_fov - 5.0

	current_fov = lerp(current_fov, target, fov_speed * delta)
	camera.fov = current_fov


# -------------------------
# CAMERA TILT
# -------------------------
func update_camera_tilt(delta: float) -> void:
	var target_roll := 0.0

	if is_sliding:
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
