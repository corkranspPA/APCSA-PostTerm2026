extends CharacterBody3D

@export var speed := 6.0
@export var crouch_speed := 3.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var crouch_lerp_speed := 10.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var pitch := 0.0
var is_crouching := false

var was_on_floor := true

var stand_height := 2.0
var crouch_height := 1.2

var stand_collision_pos := Vector3.ZERO

var stand_cam_y := 1.6
var crouch_cam_y := 0.8

var headspace_check_distance := 0.6


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var shape = collision.shape as CapsuleShape3D
	if shape:
		stand_height = shape.height

	stand_collision_pos = collision.position
	stand_cam_y = camera.position.y
	crouch_cam_y = stand_cam_y - 0.8


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

	# --- landing detection (basic hook) ---
	if not was_on_floor and is_on_floor():
		# You can add sound, camera shake, etc here later
		pass

	was_on_floor = is_on_floor()

	if not is_on_floor():
		velocity += get_gravity() * delta

	# --- jump (crouch unaffected) ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var current_speed = crouch_speed if is_crouching else speed

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()


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
# CROUCH SYSTEM (TOGGLE + SMOOTH)
# -------------------------
func handle_crouch(delta: float) -> void:
	var shape = collision.shape as CapsuleShape3D
	if not shape:
		return

	# --- toggle crouch ---
	if Input.is_action_just_pressed("crouch") and is_on_floor():
		if is_crouching:
			if can_stand_up():
				is_crouching = false
		else:
			is_crouching = true

	# --- safety: block standing under ceilings ---
	if not is_crouching and not can_stand_up():
		is_crouching = true

	# --- targets ---
	var target_height = crouch_height if is_crouching else stand_height
	var target_cam_y = crouch_cam_y if is_crouching else stand_cam_y
	var target_collision_y = -0.5 if is_crouching else 0.0

	# --- smooth capsule ---
	shape.height = lerp(shape.height, target_height, crouch_lerp_speed * delta)

	# --- smooth collider offset ---
	collision.position.y = lerp(collision.position.y, target_collision_y, crouch_lerp_speed * delta)

	# --- smooth camera ---
	camera.position.y = lerp(camera.position.y, target_cam_y, crouch_lerp_speed * delta)
