extends Node3D

# =========================
# WEAPON SETTINGS (Revolver)
# =========================
@export var bullet_scene: PackedScene
@export var fire_rate := 0.45
@export var automatic := false
@export var mag_size := 10
@export var reserve_ammo := 18
@export var reload_time := 2.0
@export var bullet_spread := 0.018
@export var ads_spread := 0.004

# =========================
# RECOIL
# =========================
@export var recoil_vertical := 3.5
@export var recoil_horizontal := 1.2

# =========================
# ADS
# =========================
@export var normal_fov := 65.0
@export var ads_fov := 45.0
@export var ads_speed := 10.0

# =========================
# NODEPATHS
# =========================
@export var camera_path: NodePath
@export var muzzle_path: NodePath

# =========================
# VARIABLES
# =========================
var current_ammo := 6
var can_shoot := true
var reloading := false
var shoot_cooldown := 0.0
var player
var hip_rotation := Vector3.ZERO

@onready var camera := get_node_or_null(camera_path) as Camera3D
@onready var muzzle: Node3D = $muzzlePoint

func _ready() -> void:
	current_ammo = mag_size
	hip_rotation = rotation
	if camera == null:
		push_error("Camera path is broken. Fix camera_path in Inspector.")
	if muzzle == null:
		push_error("Muzzle path is broken.")

func _process(delta: float) -> void:
	if camera == null:
		return
	handle_ads(delta)
	if shoot_cooldown > 0.0:
		shoot_cooldown -= delta
	if automatic:
		if Input.is_action_pressed("fire") and shoot_cooldown <= 0.0:
			shoot()
	else:
		if Input.is_action_just_pressed("fire") and shoot_cooldown <= 0.0:
			shoot()
	if Input.is_action_just_pressed("reload"):
		reload()

	# move weapon and straighten rotation when ADS
	if Input.is_action_pressed("aim"):
		position = position.lerp(Vector3(-0.11, 0.06, -0.5), delta * ads_speed)
		var target_rot = Vector3(0.0, deg_to_rad(-5.0), 0.0)
		rotation.x = lerp(rotation.x, target_rot.x, delta * ads_speed * 3.0)
		rotation.y = lerp(rotation.y, target_rot.y, delta * ads_speed * 3.0)
		rotation.z = lerp(rotation.z, target_rot.z, delta * ads_speed * 3.0)
	else:
		position = position.lerp(Vector3(0.2, -0.2, -0.5), delta * ads_speed)
		rotation.x = lerp(rotation.x, hip_rotation.x, delta * ads_speed)
		rotation.y = lerp(rotation.y, hip_rotation.y, delta * ads_speed)
		rotation.z = lerp(rotation.z, hip_rotation.z, delta * ads_speed)

func shoot() -> void:
	if current_ammo <= 0:
		reload()
		return
	if not can_shoot or reloading:
		return
	if camera == null or muzzle == null or bullet_scene == null:
		return
	can_shoot = false
	current_ammo -= 1
	shoot_cooldown = fire_rate

	# raycast from camera center to find what crosshair is pointing at
	var cam_dir = -camera.global_transform.basis.z
	var ray_from = camera.global_position
	var ray_to = ray_from + cam_dir * 1000.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	if player:
		query.exclude = [player]
	var result = space.intersect_ray(query)
	var target_point = result.position if result else ray_to

	# when ADS shoot perfectly straight
	# when hipfiring aim from muzzle toward crosshair point
	var direction: Vector3
	if Input.is_action_pressed("aim"):
		direction = -camera.global_transform.basis.z
	else:
		direction = (target_point - muzzle.global_position).normalized()

	# apply spread
	var spread_amount = ads_spread if Input.is_action_pressed("aim") else bullet_spread
	if player:
		if player.is_sprinting:
			spread_amount *= 2.0
		if player.is_sliding:
			spread_amount *= 2.5
		if player.is_dashing:
			spread_amount *= 3.0
	direction.x += randf_range(-spread_amount, spread_amount)
	direction.y += randf_range(-spread_amount, spread_amount)
	direction.z += randf_range(-spread_amount, spread_amount)
	direction = direction.normalized()

	# always spawn visually from the muzzle
	var bullet = bullet_scene.instantiate()
	bullet.launch(muzzle.global_position, direction, player)
	get_tree().root.add_child(bullet)

	await get_tree().create_timer(fire_rate).timeout
	if not reloading:
		can_shoot = true

func reload() -> void:
	if reloading:
		return
	if current_ammo >= mag_size:
		return
	if reserve_ammo <= 0:
		return
	reloading = true
	can_shoot = false
	await get_tree().create_timer(reload_time).timeout
	var needed = mag_size - current_ammo
	var reload_amount = min(needed, reserve_ammo)
	current_ammo += reload_amount
	reserve_ammo -= reload_amount
	reloading = false
	can_shoot = true

func handle_ads(delta: float) -> void:
	if camera == null:
		return
	var target_fov = normal_fov
	if player:
		if player.is_sliding or player.is_dashing:
			target_fov = normal_fov
		elif Input.is_action_pressed("aim"):
			target_fov = ads_fov
		elif player.is_sprinting:
			target_fov = normal_fov
	else:
		if Input.is_action_pressed("aim"):
			target_fov = ads_fov
	camera.fov = lerp(camera.fov, target_fov, delta * ads_speed)
