extends Node

# =========================
# WEAPON SETTINGS
# =========================
@export var bullet_scene: PackedScene
@export var fire_rate := 0.12
@export var automatic := true
@export var mag_size := 30
@export var reserve_ammo := 90
@export var reload_time := 1.5
@export var bullet_spread := 0.01
@export var ads_spread := 0.002

# =========================
# RECOIL
# =========================
@export var recoil_vertical := 1.5
@export var recoil_horizontal := 0.8

# =========================
# ADS
# =========================
@export var normal_fov := 75.0
@export var ads_fov := 60.0
@export var ads_speed := 10.0

# =========================
# NODEPATHS
# =========================
@export var camera_path: NodePath
@export var muzzle_path: NodePath

# =========================
# VARIABLES
# =========================
var current_ammo := 30
var can_shoot := true
var reloading := false
var shoot_cooldown := 0.0
var player

@onready var camera := get_node_or_null(camera_path) as Camera3D
@onready var muzzle := get_node_or_null(muzzle_path) as Node3D

# =========================
# READY
# =========================
func _ready() -> void:
	current_ammo = mag_size
	if camera == null:
		push_error("Camera path is broken. Fix camera_path in Inspector.")
	if muzzle == null:
		push_error("Muzzle path is broken. Fix muzzle_path in Inspector.")

# =========================
# PROCESS
# =========================
func _process(delta: float) -> void:
	if camera == null:
		return
	
	handle_ads(delta)
	
	# Fire rate cooldown
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

# =========================
# SHOOT
# =========================
func shoot() -> void:
	if not can_shoot or reloading or current_ammo <= 0:
		return
	if camera == null or muzzle == null or bullet_scene == null:
		return

	can_shoot = false
	current_ammo -= 1
	shoot_cooldown = fire_rate

	# Direction
	var direction = -camera.global_transform.basis.z

	# Spread
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

	# -------------------------
	# SPAWN BULLET
	# -------------------------
	var bullet = bullet_scene.instantiate()
	bullet.get_child(0).launch(muzzle.global_position, direction, player)  # launch BEFORE add_child
	get_tree().root.add_child(bullet)                         # add AFTER launch

	# -------------------------
	# RECOIL
	# -------------------------
	if player:
		player.pitch -= deg_to_rad(recoil_vertical)
		player.pitch = clamp(player.pitch, deg_to_rad(-89), deg_to_rad(89))
		player.head.rotation.x = player.pitch
		player.rotate_y(deg_to_rad(randf_range(-recoil_horizontal, recoil_horizontal)))
	else:
		camera.rotation.x -= deg_to_rad(recoil_vertical)
		camera.rotation.y += deg_to_rad(randf_range(-recoil_horizontal, recoil_horizontal))
# =========================
# RELOAD
# =========================
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

# =========================
# ADS
# =========================
func handle_ads(delta: float) -> void:
	if camera == null:
		return
	
	var target_fov = normal_fov
	if player:
		if player.is_sliding or player.is_dashing:
			target_fov = normal_fov
		elif Input.is_action_pressed("aim"):
			target_fov = ads_fov
	else:
		if Input.is_action_pressed("aim"):
			target_fov = ads_fov
	
	camera.fov = lerp(camera.fov, target_fov, delta * ads_speed)
