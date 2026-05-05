extends CharacterBody3D

@export var speed := 6.0
@export var crouch_speed := 3.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var pitch := 0.0
var is_crouching := false

var normal_height := 2.0
var crouch_height := 1.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# store original capsule height safely
	var shape = collision.shape as CapsuleShape3D
	if shape:
		normal_height = shape.height

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)

		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
		head.rotation.x = pitch

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	handle_crouch()

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	var current_speed = crouch_speed if is_crouching else speed

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

func handle_crouch() -> void:
	var shape = collision.shape as CapsuleShape3D
	if not shape:
		return

	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			is_crouching = true
			shape.height = crouch_height
			camera.position.y = 0.8
	else:
		if is_crouching:
			is_crouching = false
			shape.height = normal_height
			camera.position.y = 1.6
