extends CharacterBody3D

@export var speed := 6.0
@export var sprint_speed := 10.0
@export var crouch_speed := 3.0

@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var crouch_lerp_speed := 10.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var pitch := 0.0

var is_crouching := false
var is_sprinting := false
var was_on_floor := true

var stand_height := 2.0
var crouch_height := 1.2

var stand_collision_pos := Vector3.ZERO

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

	var shape = collision.shape as CapsuleShape3D
	if shape:
		stand_height = shape.height

	stand_collision_pos = collision.position

	stand_cam_y = camera.position.y
	crouch_cam_y = stand_cam_y - 0.8

	base_camera_pos = camera.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)

		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
		head.rotation.x = pitch

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	handle_crouch(delta)

	# -------------------------
	# TOGGLES
	# -------------------------
	if Input.is_action_just_pressed("sprint"):
		is_sprinting = !is_sprinting

	if Input.is_action_just_pressed("crouch") and is_on_floor():
		is_crouching = !is_crouching

	# ceiling safety
	if not is_crouching and not can_stand_up():
		is_crouching = true

	# landing hook
	if not was_on_floor and is_on_floor():
		pass

	was_on_floor = is_on_floor()

	if not is_on_floor():
		velocity += get_gravity() * delta

	# -------------------------
	# JUMP
	# -------------------------
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# -------------------------
	# SPEED LOGIC (SPRINT + CROUCH COMBO)
	# -------------------------
	var current_speed = speed

	if is_crouching:
		current_speed = crouch_speed

		# sprint still works while crouched (boost)
		if is_sprinting and is_on_floor():
			current_speed += 2.5

	elif is_sprinting and is_on_floor():
		current_speed = sprint_speed

	# movement
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	# -------------------------
	# HEAD BOB
	# -------------------------
	apply_headbob(delta)


# -------------------------
# CEILING CHECK
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
# CROUCH SYSTEM
# -------------------------
func handle_crouch(delta: float) -> void:
	var shape = collision.shape as CapsuleShape3D
	if not shape:
		return

	var target_height = crouch_height if is_crouching else stand_height
	var target_cam_y = crouch_cam_y if is_crouching else stand_cam_y
	var target_collision_y = -0.5 if is_crouching else 0.0

	shape.height = lerp(shape.height, target_height, crouch_lerp_speed * delta)
	collision.position.y = lerp(collision.position.y, target_collision_y, crouch_lerp_speed * delta)
	camera.position.y = lerp(camera.position.y, target_cam_y, crouch_lerp_speed * delta)


# -------------------------
# HEAD BOB SYSTEM (SPRINT + CROUCH COMBO)
# -------------------------
func apply_headbob(delta: float) -> void:
	var is_moving := is_on_floor() and velocity.length() > 0.1

	if not is_moving:
		bob_time = 0.0
		camera.position = camera.position.lerp(base_camera_pos, 10.0 * delta)
		return

	var speed := walk_bob_speed
	var amount := walk_bob_amount

	if is_crouching:
		speed = crouch_bob_speed
		amount = crouch_bob_amount
	elif is_sprinting:
		speed = sprint_bob_speed
		amount = sprint_bob_amount

	# 🔥 combo boost: crouch + sprint = stronger motion
	if is_crouching and is_sprinting:
		speed *= 1.2
		amount *= 1.6

	bob_time += delta * speed

	var bob_offset := Vector3(
		sin(bob_time * 2.5) * amount * 0.4,
		sin(bob_time * 1.2) * amount * 1.8,
		0
	)

	camera.position = camera.position.lerp(base_camera_pos + bob_offset, 12.0 * delta)
