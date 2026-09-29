extends CharacterBody3D

# =========================
# WOBBLE
# =========================
var wobble_time := 0.0
@export var wobble_speed := 8.0
@export var wobble_amount := 0.12
@onready var mesh: MeshInstance3D = $MeshInstance3D
var mesh_base_y := 0.0
var face_mesh_base_y := 0.0

# =========================
# FACE BOX
# =========================
const FACEBOX_LAYER := 20
@onready var face_mesh: MeshInstance3D = $Facebox/MeshInstance3D
var face_original_material: Material = null

# =========================
# STATS
# =========================
@export var move_speed := 3.5
@export var detection_radius := 6.0
@export var sight_range := 10.0
@export var sight_angle := 60.0
@export var sound_radius := 8.0
@export var crouch_sound_radius := 1.5
@export var gravity := 9.8

# =========================
# ATTACK (telegraphed lunge)
# =========================
@export var attack_range := 2.6          # starts an attack when the player is this close (flat distance)
@export var attack_windup := 0.55        # telegraph time — enemy turns orange and stops. Dodge window!
@export var attack_lunge_speed := 16.0   # how fast the lunge is
@export var attack_lunge_time := 0.2     # how long the lunge lasts
@export var attack_recover := 0.6        # vulnerable recovery after the lunge
@export var attack_cooldown := 1.2       # extra wait before it can attack again
@export var attack_damage := 20.0
@export var attack_hit_radius := 1.8     # how close the player must be during the lunge to get hit
@export var attack_knockback := 9.0

enum AttackPhase { NONE, WINDUP, LUNGE, RECOVER }
var attack_phase: AttackPhase = AttackPhase.NONE
var attack_timer := 0.0
var attack_cooldown_timer := 0.0
var attack_hit_landed := false
var lunge_dir := Vector3.ZERO
var windup_material: StandardMaterial3D = null

# =========================
# HEALTH / DAMAGE
# =========================
@export var max_health := 100.0
var health := 100.0
var is_dead := false

@export var flash_duration := 0.15
var flash_timer := 0.0
var is_flashing := false

var original_material: Material = null
var flash_material: StandardMaterial3D = null

# =========================
# DEATH
# =========================
var death_timer := 0.0
@export var death_fade_delay := 0.5
@export var death_fade_duration := 1.5
var death_material: StandardMaterial3D = null
var is_fading := false
var _death_rb: RigidBody3D = null
var _death_rb_mesh: MeshInstance3D = null

# =========================
# RESPAWN
# =========================
@export var respawn_time := 5.0
var spawn_position: Vector3 = Vector3.ZERO
var spawn_rotation: Vector3 = Vector3.ZERO

# =========================
# STATE
# =========================
enum State { IDLE, ALERT, CHASING, ATTACKING }
var state: State = State.IDLE
var player: Node3D = null
var last_known_position: Vector3 = Vector3.ZERO
var can_see_player := false

func _ready() -> void:
	# The player's slam + wall-cling code look for this group.
	add_to_group("enemy")

	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("Enemy could not find player. Make sure Player is in group 'player'.")
	mesh_base_y = mesh.position.y
	face_mesh_base_y = face_mesh.position.y
	original_material = mesh.get_active_material(0)
	face_original_material = face_mesh.get_active_material(0)
	flash_material = StandardMaterial3D.new()
	flash_material.albedo_color = Color.RED
	flash_material.emission_enabled = true
	flash_material.emission = Color.RED
	flash_material.emission_energy_multiplier = 2.0

	# Orange glow shown during the attack wind-up so the player can read it.
	windup_material = StandardMaterial3D.new()
	windup_material.albedo_color = Color(1.0, 0.55, 0.05)
	windup_material.emission_enabled = true
	windup_material.emission = Color(1.0, 0.45, 0.0)
	windup_material.emission_energy_multiplier = 2.5

	spawn_position = global_position
	spawn_rotation = rotation

	if $Facebox:
		$Facebox.collision_layer = 1 << (FACEBOX_LAYER - 1)
		$Facebox.collision_mask = 0

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if is_dead:
		_apply_fade(delta)
		return

	attack_cooldown_timer = max(attack_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	_check_detection()

	match state:
		State.IDLE:
			velocity.x = 0
			velocity.z = 0
		State.ALERT:
			_move_toward(last_known_position)
			if global_position.distance_to(last_known_position) < 0.5:
				state = State.IDLE
		State.CHASING:
			if can_see_player:
				last_known_position = player.global_position
				if _flat_distance_to_player() <= attack_range and attack_cooldown_timer <= 0.0 and player.get("is_dead") != true:
					_start_attack()
				else:
					_move_toward(player.global_position)
			else:
				state = State.ALERT
		State.ATTACKING:
			_process_attack(delta)

	if is_flashing:
		flash_timer -= delta
		if flash_timer <= 0.0:
			is_flashing = false
			_apply_base_materials()

	_apply_wobble(delta)
	move_and_slide()

# =========================
# DETECTION
# =========================
func _check_detection() -> void:
	can_see_player = _has_line_of_sight()
	# Once committed to an attack, don't let detection interrupt it.
	if state == State.ATTACKING:
		return
	if can_see_player:
		state = State.CHASING
		last_known_position = player.global_position
		return
	var dist = global_position.distance_to(player.global_position)
	var is_crouching = player.get("is_crouching") == true
	var effective_sound_radius = crouch_sound_radius if is_crouching else sound_radius
	if dist <= effective_sound_radius:
		if _raycast_clear(player.global_position):
			last_known_position = player.global_position
			state = State.ALERT

func _has_line_of_sight() -> bool:
	var dist = global_position.distance_to(player.global_position)
	if dist > sight_range:
		return false
	var dir_to_player = (player.global_position - global_position).normalized()
	var forward = -global_transform.basis.z
	var angle = rad_to_deg(forward.angle_to(dir_to_player))
	if angle > sight_angle:
		return false
	return _raycast_clear(player.global_position)

func _raycast_clear(target: Vector3) -> bool:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.5,
		target + Vector3.UP * 0.5
	)
	query.exclude = [self]
	query.collision_mask = 0xFFFFFFFF & ~(1 << (FACEBOX_LAYER - 1))
	var result = space.intersect_ray(query)
	if result.is_empty():
		return true
	if result.collider == player:
		return true
	return false

# =========================
# MOVEMENT
# =========================
func _move_toward(target: Vector3) -> void:
	var dir = (target - global_position).normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	var flat_dir = Vector3(dir.x, 0, dir.z)
	if flat_dir.length() > 0.1:
		var target_basis = Basis.looking_at(flat_dir, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, 10.0 * get_physics_process_delta_time())

func _face_position(target: Vector3, rate: float, delta: float) -> void:
	var flat_dir = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if flat_dir.length() > 0.1:
		var target_basis = Basis.looking_at(flat_dir.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, clampf(rate * delta, 0.0, 1.0))

func _flat_distance_to_player() -> float:
	var d = player.global_position - global_position
	d.y = 0
	return d.length()

# =========================
# ATTACK
# =========================
func _start_attack() -> void:
	state = State.ATTACKING
	attack_phase = AttackPhase.WINDUP
	attack_timer = attack_windup
	attack_hit_landed = false
	velocity.x = 0
	velocity.z = 0
	if not is_flashing:
		_apply_base_materials()

func _process_attack(delta: float) -> void:
	match attack_phase:
		AttackPhase.WINDUP:
			# Stand still, track the player, glow orange.
			velocity.x = 0
			velocity.z = 0
			_face_position(player.global_position, 12.0, delta)
			attack_timer -= delta
			if attack_timer <= 0.0:
				# Lunge direction is locked in NOW — that's what makes it dodgeable.
				var to_player = player.global_position - global_position
				to_player.y = 0
				if to_player.length() > 0.05:
					lunge_dir = to_player.normalized()
				else:
					lunge_dir = -global_transform.basis.z
				attack_phase = AttackPhase.LUNGE
				attack_timer = attack_lunge_time
				if not is_flashing:
					_apply_base_materials()
		AttackPhase.LUNGE:
			velocity.x = lunge_dir.x * attack_lunge_speed
			velocity.z = lunge_dir.z * attack_lunge_speed
			if not attack_hit_landed and _player_in_hit_range():
				_deal_attack_damage()
			attack_timer -= delta
			if attack_timer <= 0.0:
				attack_phase = AttackPhase.RECOVER
				attack_timer = attack_recover
		AttackPhase.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)
			attack_timer -= delta
			if attack_timer <= 0.0:
				_end_attack()

func _player_in_hit_range() -> bool:
	var d = player.global_position - global_position
	if absf(d.y) > 1.8:
		return false
	d.y = 0
	return d.length() <= attack_hit_radius

func _deal_attack_damage() -> void:
	# If the player is mid-dash (i-frames), the lunge whiffs — keep checking
	# each frame in case they come out of it while still in range.
	var inv = player.get("invuln_timer")
	if inv != null and inv > 0.0:
		return

	attack_hit_landed = true
	var push = player.global_position - global_position
	push.y = 0
	push = push.normalized()

	if player.has_method("take_damage"):
		player.take_damage(attack_damage, player.global_position, self)
	if player.has_method("apply_knockback"):
		player.apply_knockback(push * attack_knockback + Vector3.UP * 2.0)

func _end_attack() -> void:
	attack_phase = AttackPhase.NONE
	attack_cooldown_timer = attack_cooldown
	state = State.CHASING
	if not is_flashing:
		_apply_base_materials()

func _apply_base_materials() -> void:
	if attack_phase == AttackPhase.WINDUP and windup_material:
		mesh.set_surface_override_material(0, windup_material)
		face_mesh.set_surface_override_material(0, windup_material)
	else:
		mesh.set_surface_override_material(0, original_material)
		face_mesh.set_surface_override_material(0, face_original_material)

# =========================
# WOBBLE
# =========================
func _apply_wobble(delta: float) -> void:
	var moving = Vector2(velocity.x, velocity.z).length() > 0.5
	if moving:
		wobble_time += delta * wobble_speed
		var offset = sin(wobble_time) * wobble_amount
		mesh.position.y = mesh_base_y + offset
		face_mesh.position.y = face_mesh_base_y + offset
	else:
		wobble_time = 0.0
		mesh.position.y = lerp(mesh.position.y, mesh_base_y, 10.0 * delta)
		face_mesh.position.y = lerp(face_mesh.position.y, face_mesh_base_y, 10.0 * delta)

# =========================
# HEALTH / DAMAGE
# =========================
func take_damage(amount: float, hit_point: Vector3, shooter: Node) -> void:
	if is_dead:
		return
	health -= amount
	_start_flash()
	if health <= 0.0:
		die()

func _start_flash() -> void:
	is_flashing = true
	flash_timer = flash_duration
	mesh.set_surface_override_material(0, flash_material)
	face_mesh.set_surface_override_material(0, flash_material)

# =========================
# DEATH
# =========================
func die() -> void:
	is_dead = true
	attack_phase = AttackPhase.NONE
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", true)

	death_material = StandardMaterial3D.new()
	death_material.albedo_color = Color(0.3, 0.0, 0.0, 1.0)
	death_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	death_material.emission_enabled = true
	death_material.emission = Color(0.3, 0.0, 0.0)

	var rb = RigidBody3D.new()
	_death_rb_mesh = MeshInstance3D.new()
	_death_rb_mesh.mesh = mesh.mesh
	_death_rb_mesh.set_surface_override_material(0, death_material)

	var rb_col = CollisionShape3D.new()
	rb_col.shape = $CollisionShape3D.shape

	rb.add_child(_death_rb_mesh)
	rb.add_child(rb_col)
	rb.mass = 5.0

	# carry the face box mesh over onto the ragdoll, keeping its relative position
	var face_rb_mesh = MeshInstance3D.new()
	face_rb_mesh.mesh = face_mesh.mesh
	face_rb_mesh.set_surface_override_material(0, death_material)
	rb.add_child(face_rb_mesh)
	face_rb_mesh.transform = $Facebox.transform * face_mesh.transform

	get_tree().current_scene.add_child(rb)
	rb.global_position = global_position
	rb.global_rotation = global_rotation
	rb.apply_impulse(Vector3(randf_range(-1.0, 1.0), 1.0, randf_range(-1.0, 1.0)) * 2.0)
	rb.apply_torque_impulse(Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))

	mesh.visible = false
	face_mesh.visible = false
	_death_rb = rb

	await get_tree().create_timer(death_fade_delay).timeout
	is_fading = true

	await get_tree().create_timer(death_fade_duration + respawn_time).timeout
	_respawn()

func _apply_fade(delta: float) -> void:
	if not is_fading:
		return
	death_timer += delta
	var alpha = 1.0 - clamp(death_timer / death_fade_duration, 0.0, 1.0)
	if death_material:
		death_material.albedo_color.a = alpha

func _respawn() -> void:
	if _death_rb and is_instance_valid(_death_rb):
		_death_rb.queue_free()

	is_dead = false
	is_fading = false
	health = max_health
	death_timer = 0.0
	state = State.IDLE
	attack_phase = AttackPhase.NONE
	attack_cooldown_timer = 0.0
	velocity = Vector3.ZERO

	global_position = spawn_position
	rotation = spawn_rotation

	$CollisionShape3D.set_deferred("disabled", false)
	mesh.visible = true
	face_mesh.visible = true
	mesh.rotation = Vector3.ZERO
	mesh.position.y = mesh_base_y
	face_mesh.position.y = face_mesh_base_y
	mesh.set_surface_override_material(0, original_material)
	face_mesh.set_surface_override_material(0, face_original_material)
