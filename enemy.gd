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
var _death_rb: Node3D = null              # the corpse: a SoftBody3D (or a RigidBody3D if soft body is off)
var _death_rb_mesh: MeshInstance3D = null # only used by the rigid fallback
var _death_face_rb: RigidBody3D = null    # the face pops off as its own little chunk
var _corpse_is_soft := false
var corpse_age := 0.0
var last_hit_dir := Vector3.ZERO          # direction of the last hit, so the corpse flies away from the shooter

# limp_ragdoll: true (default) = the body goes limp like a rag doll: two halves joined at the middle that flop and fold.
# If it's off (or the mesh can't be split) it falls back to the jelly ragdoll / soft body options below.
@export var limp_ragdoll := true
@export var limp_swing_degrees := 95.0     # how far the top half can flop sideways/forward over the bottom half
@export var limp_twist_degrees := 70.0     # how far the halves can twist against each other
@export var limp_mass := 3.0               # mass of each half
@export var limp_angular_damp := 2.5       # higher = floppier / less spinning, lower = tumbles more
var _limp_joint: ConeTwistJoint3D = null
var _limp_mats: Array[ShaderMaterial] = []
# use_real_soft_body: false (default) = jelly ragdoll: tumbles, squashes on impact, can't fold or lose its face.
#                     true = experimental SoftBody3D (the face is a separate chunk and the body can crumple).
@export var use_real_soft_body := false
@export var death_push := 5.0              # launch speed (m/s) the killing blow gives the corpse
@export var corpse_squash := 0.08          # how hard the corpse squashes on impact
@export var corpse_jelly_stiffness := 90.0 # spring pull back to its normal shape
@export var corpse_jelly_damping := 5.0    # lower = jigglier for longer
@export var soft_body_mass := 4.0
@export var soft_body_stiffness := 0.85    # (SoftBody3D only) 0 = very floppy, 1 = stiff
@export var soft_body_pressure := 25.0     # (SoftBody3D only) keeps it plump like a water balloon so it can't cave in
@export var soft_body_damping := 0.08
var _corpse_pivot: Node3D = null           # body + face both live under this, so they always stay together
var _corpse_prev_vel := Vector3.ZERO
var corpse_jelly_scale := Vector3.ONE
var corpse_jelly_vel := Vector3.ZERO

# =========================
# JELLY (squash & stretch, lean, spring)
# =========================
@export var jelly_enabled := true
@export var jelly_stiffness := 140.0       # spring pull toward the target shape
@export var jelly_damping := 9.0           # lower = jigglier
@export var move_accel := 14.0             # ramps up to speed instead of snapping
@export var move_lean_degrees := 12.0      # leans into its movement
@export var hop_squash := 0.10             # squash/stretch in time with the walking bounce
@export var breathe_amount := 0.025        # idle breathing
@export var windup_squash := 0.28          # crouches down and widens before a lunge
@export var lunge_stretch := 0.45          # stretches out along the lunge
@export var hit_squash := 0.25             # jiggle kick when shot

var jelly_scale := Vector3.ONE
var jelly_vel := Vector3.ZERO
var lean_x := 0.0
var lean_z := 0.0
var breathe_time := 0.0
var bob_offset := 0.0
var stand_half_height := 1.0
var mesh_base_scale := Vector3.ONE
var face_base_scale := Vector3.ONE
var _jelly_was_on_floor := true

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
	mesh_base_scale = mesh.scale
	face_base_scale = face_mesh.scale
	var cap := $CollisionShape3D.shape as CapsuleShape3D
	if cap:
		stand_half_height = cap.height * 0.5
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
			velocity.x = move_toward(velocity.x, 0.0, move_accel * 2.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_accel * 2.0 * delta)
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
	# Ramp up to speed instead of snapping to it, so it feels like it has weight.
	var cur := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * move_speed, move_accel * get_physics_process_delta_time())
	velocity.x = cur.x
	velocity.z = cur.y
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
		bob_offset = sin(wobble_time) * wobble_amount
	else:
		wobble_time = 0.0
		bob_offset = lerp(bob_offset, 0.0, 10.0 * delta)
	_apply_jelly(delta)


## Squash & stretch driven by a spring, so every change of shape overshoots and jiggles a little.
## Windup = crouch and widen, lunge = stretch out forward, recover = flop, walking = hops in time with the bob.
func _apply_jelly(delta: float) -> void:
	if not jelly_enabled:
		mesh.position.y = mesh_base_y + bob_offset
		face_mesh.position.y = face_mesh_base_y + bob_offset
		return

	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	breathe_time += delta * 2.0
	var wob := bob_offset / maxf(wobble_amount, 0.001)   # -1..1 in step with the walking bounce

	# Target shape: x = width, y = height, z = depth (forward).
	var target := Vector3.ONE
	var lean_back := 0.0
	if state == State.ATTACKING:
		match attack_phase:
			AttackPhase.WINDUP:
				var t := 1.0 - clampf(attack_timer / maxf(attack_windup, 0.01), 0.0, 1.0)
				var sq := windup_squash * smoothstep(0.0, 1.0, t)
				target = Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
				target.x += sin(Time.get_ticks_msec() * 0.05) * 0.03 * t   # trembles as it charges
				lean_back = 0.8 * t
			AttackPhase.LUNGE:
				target = Vector3(1.0 - lunge_stretch * 0.35, 1.0 - lunge_stretch * 0.3, 1.0 + lunge_stretch)
			AttackPhase.RECOVER:
				target = Vector3(1.12, 0.9, 0.95)
	elif moving:
		target = Vector3(1.0 - hop_squash * 0.5 * wob, 1.0 + hop_squash * wob, 1.0 - hop_squash * 0.5 * wob)
	else:
		var b := sin(breathe_time) * breathe_amount
		target = Vector3(1.0 - b * 0.5, 1.0 + b, 1.0 - b * 0.5)

	# Landing thump.
	if is_on_floor() and not _jelly_was_on_floor:
		jelly_vel += Vector3(1.5, -2.5, 1.5)
	_jelly_was_on_floor = is_on_floor()

	# Spring toward the target shape.
	jelly_vel += (target - jelly_scale) * jelly_stiffness * delta
	jelly_vel *= maxf(1.0 - jelly_damping * delta, 0.0)
	jelly_scale += jelly_vel * delta
	jelly_scale = jelly_scale.clamp(Vector3(0.4, 0.4, 0.4), Vector3(2.0, 2.0, 2.0))

	# Lean into the direction of travel (and rock back while winding up).
	var local_vel := global_transform.basis.inverse() * velocity
	var lean_amt := deg_to_rad(move_lean_degrees)
	var want_x := lean_amt * clampf(local_vel.z / 8.0, -1.0, 1.0) + lean_amt * lean_back
	var want_z := -lean_amt * clampf(local_vel.x / 8.0, -1.0, 1.0)
	lean_x = lerp(lean_x, want_x, 10.0 * delta)
	lean_z = lerp(lean_z, want_z, 10.0 * delta)

	mesh.scale = mesh_base_scale * jelly_scale
	face_mesh.scale = face_base_scale * jelly_scale
	mesh.rotation.x = lean_x
	mesh.rotation.z = lean_z
	face_mesh.rotation.x = lean_x
	face_mesh.rotation.z = lean_z

	# Keep its feet planted while it squashes/stretches.
	var plant := (1.0 - jelly_scale.y) * stand_half_height
	mesh.position.y = mesh_base_y + bob_offset + plant
	face_mesh.position.y = face_mesh_base_y + bob_offset + plant

# =========================
# HEALTH / DAMAGE
# =========================
func take_damage(amount: float, hit_point: Vector3, shooter: Node) -> void:
	if is_dead:
		return
	health -= amount
	if shooter is Node3D:
		var away := global_position - (shooter as Node3D).global_position
		away.y = 0.0
		if away.length() > 0.05:
			last_hit_dir = away.normalized()
	jelly_vel += Vector3(0.6, -1.0, 0.6) * hit_squash * 12.0   # jiggle when hit
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

	# Start the corpse from the neutral pose (not mid-squash).
	mesh.scale = mesh_base_scale
	mesh.rotation = Vector3.ZERO

	# The corpse is shoved away from whatever killed it.
	var push := last_hit_dir
	if push.length() < 0.1:
		push = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	push = push.normalized()

	corpse_age = 0.0
	_corpse_is_soft = false
	var spawned := false
	if limp_ragdoll and mesh.mesh:
		spawned = _spawn_limp_corpse(push)
	if not spawned and use_real_soft_body and mesh.mesh:
		_corpse_is_soft = _spawn_soft_body_corpse(push)
		spawned = _corpse_is_soft
	if not spawned:
		_spawn_jelly_corpse(push)

	mesh.visible = false
	face_mesh.visible = false

	await get_tree().create_timer(death_fade_delay).timeout
	is_fading = true

	await get_tree().create_timer(death_fade_duration + respawn_time).timeout
	_respawn()


## Real soft body: the whole blob squishes, sags and jiggles as it hits the ground.
func _spawn_soft_body_corpse(push: Vector3) -> bool:
	var sb := SoftBody3D.new()
	sb.mesh = mesh.mesh
	sb.material_override = death_material
	sb.collision_layer = 0      # nothing collides with the corpse, so it never blocks the player
	sb.collision_mask = 1       # but it still lands on the world
	sb.simulation_precision = 12
	sb.total_mass = soft_body_mass
	sb.linear_stiffness = soft_body_stiffness
	sb.pressure_coefficient = soft_body_pressure
	sb.damping_coefficient = soft_body_damping
	sb.drag_coefficient = 0.02

	get_tree().current_scene.add_child(sb)
	sb.global_transform = mesh.global_transform
	_death_rb = sb
	_death_rb_mesh = null
	_kick_soft_body(sb, push)

	# A soft body is a single mesh, so the face pops off as its own little chunk.
	_spawn_face_chunk(push)
	return true


func _kick_soft_body(sb: SoftBody3D, push: Vector3) -> void:
	await get_tree().physics_frame   # wait until the soft body has built its points
	if is_instance_valid(sb) and sb.has_method("apply_central_impulse"):
		sb.apply_central_impulse(push * death_push + Vector3.UP * death_push * 0.6)


func _spawn_face_chunk(push: Vector3) -> void:
	var fm := MeshInstance3D.new()
	fm.mesh = face_mesh.mesh
	fm.set_surface_override_material(0, death_material)
	fm.scale = face_mesh.global_transform.basis.get_scale()

	var aabb := face_mesh.mesh.get_aabb()
	var box := BoxShape3D.new()
	box.size = aabb.size * fm.scale
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center() * fm.scale

	var rb := RigidBody3D.new()
	rb.mass = 0.5
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.add_child(fm)
	rb.add_child(shape)
	get_tree().current_scene.add_child(rb)
	rb.global_transform = face_mesh.global_transform.orthonormalized()
	rb.apply_impulse(push * 2.0 + Vector3.UP * 2.5)
	rb.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)))
	_death_face_rb = rb


## Limp ragdoll: the body is cut at the middle into two rigid halves joined by a loose cone-twist joint,
## so the top half flops over the bottom like a rag doll. Each half draws the same mesh, clipped at the cut
## (with a little overlap so there's never a gap). The face rides on the top half, so it stays attached.
func _spawn_limp_corpse(push: Vector3) -> bool:
	var aabb := mesh.mesh.get_aabb()
	if aabb.size.y < 0.01:
		return false

	var t_mesh := Transform3D(Basis.from_scale(mesh_base_scale), Vector3(mesh.position.x, mesh_base_y, mesh.position.z))
	var c := aabb.get_center()
	var low_local := t_mesh * Vector3(c.x, aabb.position.y + aabb.size.y * 0.25, c.z)
	var up_local := t_mesh * Vector3(c.x, aabb.position.y + aabb.size.y * 0.75, c.z)
	var cut_local := t_mesh * Vector3(c.x, aabb.position.y + aabb.size.y * 0.5, c.z)
	var cut_mesh_y := aabb.position.y + aabb.size.y * 0.5
	var margin := aabb.size.y * 0.08

	# Collision shape for each half.
	var cap := $CollisionShape3D.shape as CapsuleShape3D
	var half_shape: Shape3D
	if cap:
		var cs := CapsuleShape3D.new()
		cs.radius = cap.radius
		cs.height = maxf(cap.height * 0.5, cap.radius * 2.0 + 0.02)
		half_shape = cs
	else:
		var ss := SphereShape3D.new()
		ss.radius = maxf(aabb.size.x * mesh_base_scale.x, aabb.size.z * mesh_base_scale.z) * 0.25
		half_shape = ss

	var pm := PhysicsMaterial.new()
	pm.bounce = 0.05      # dead weight: it doesn't bounce
	pm.friction = 1.0

	_limp_mats.clear()
	var lower := _make_limp_half(low_local, t_mesh, half_shape, pm, -1.0, cut_mesh_y, margin, false)
	var upper := _make_limp_half(up_local, t_mesh, half_shape, pm, 1.0, cut_mesh_y, margin, true)

	# The loose joint at the middle. Its X axis is "up", which is the twist axis.
	var joint := ConeTwistJoint3D.new()
	get_tree().current_scene.add_child(joint)
	var up_dir := global_transform.basis.y.normalized()
	var right_dir := global_transform.basis.x.normalized()
	joint.global_transform = Transform3D(Basis(up_dir, right_dir, up_dir.cross(right_dir)), global_transform * cut_local)
	joint.node_a = joint.get_path_to(lower)
	joint.node_b = joint.get_path_to(upper)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(limp_swing_degrees))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(limp_twist_degrees))

	# The killing blow: the top half gets thrown harder than the bottom, so it whips over.
	lower.apply_impulse((push * death_push * 0.6 + Vector3.UP * death_push * 0.3) * lower.mass)
	upper.apply_impulse((push * death_push + Vector3.UP * death_push * 0.6) * upper.mass)
	upper.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * upper.mass)

	_death_rb = lower
	_death_face_rb = upper
	_limp_joint = joint
	_death_rb_mesh = null
	_corpse_pivot = null
	return true


func _make_limp_half(center_local: Vector3, t_mesh: Transform3D, shape: Shape3D, pm: PhysicsMaterial,
		side: float, cut_mesh_y: float, margin: float, with_face: bool) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = limp_mass
	rb.collision_layer = 0      # never blocks the player
	rb.collision_mask = 1       # still lands on the world
	rb.linear_damp = 0.3
	rb.angular_damp = limp_angular_damp
	rb.physics_material_override = pm

	var col := CollisionShape3D.new()
	col.shape = shape
	rb.add_child(col)

	var mat := _make_clip_material(side, cut_mesh_y, margin)
	_limp_mats.append(mat)
	var body := MeshInstance3D.new()
	body.mesh = mesh.mesh
	body.material_override = mat
	body.transform = Transform3D(t_mesh.basis, t_mesh.origin - center_local)
	rb.add_child(body)

	if with_face:
		var face := MeshInstance3D.new()
		face.mesh = face_mesh.mesh
		face.set_surface_override_material(0, death_material)
		var face_local: Transform3D = $Facebox.transform * Transform3D(Basis.from_scale(face_base_scale), Vector3(face_mesh.position.x, face_mesh_base_y, face_mesh.position.z))
		face.transform = Transform3D(face_local.basis, face_local.origin - center_local)
		rb.add_child(face)

	get_tree().current_scene.add_child(rb)
	rb.global_transform = Transform3D(global_transform.basis, global_transform * center_local)
	return rb


## Shows only one half of the mesh (side +1 = above the cut, -1 = below), with a little overlap.
func _make_clip_material(side: float, cut_mesh_y: float, margin: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform vec4 albedo : source_color = vec4(0.3, 0.0, 0.0, 1.0);
uniform float alpha = 1.0;
uniform float cut = 0.0;
uniform float side = 1.0;
uniform float margin = 0.1;
varying float local_y;
void vertex() {
	local_y = VERTEX.y;
}
void fragment() {
	if (side > 0.0) {
		if (local_y < cut - margin) { discard; }
	} else {
		if (local_y > cut + margin) { discard; }
	}
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb;
	ALPHA = alpha;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("cut", cut_mesh_y)
	mat.set_shader_parameter("side", side)
	mat.set_shader_parameter("margin", margin)
	return mat


## Default corpse: a rigid ragdoll that tumbles and bounces, with a spring-driven jelly squash on every impact.
## The body and the face are both children of one pivot, so the face can never come loose and nothing can fold in.
func _spawn_jelly_corpse(push: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 5.0
	rb.collision_layer = 0      # never blocks the player
	rb.collision_mask = 1       # still lands on the world
	rb.linear_damp = 0.4
	rb.angular_damp = 1.2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.9
	rb.physics_material_override = pm

	var rb_col := CollisionShape3D.new()
	rb_col.shape = $CollisionShape3D.shape
	rb_col.transform = $CollisionShape3D.transform
	rb.add_child(rb_col)

	# Everything visible hangs off one pivot that gets squashed and stretched.
	_corpse_pivot = Node3D.new()
	rb.add_child(_corpse_pivot)

	var body := MeshInstance3D.new()
	body.mesh = mesh.mesh
	body.set_surface_override_material(0, death_material)
	body.transform = Transform3D(Basis.from_scale(mesh_base_scale), Vector3(mesh.position.x, mesh_base_y, mesh.position.z))
	_corpse_pivot.add_child(body)

	var face := MeshInstance3D.new()
	face.mesh = face_mesh.mesh
	face.set_surface_override_material(0, death_material)
	face.transform = $Facebox.transform * Transform3D(Basis.from_scale(face_base_scale), Vector3(face_mesh.position.x, face_mesh_base_y, face_mesh.position.z))
	_corpse_pivot.add_child(face)

	get_tree().current_scene.add_child(rb)
	rb.global_transform = global_transform
	rb.apply_impulse((push * death_push + Vector3.UP * death_push * 0.6) * rb.mass)
	rb.apply_torque_impulse(Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))

	_death_rb = rb
	_death_rb_mesh = null
	_corpse_prev_vel = rb.linear_velocity
	corpse_jelly_scale = Vector3.ONE
	corpse_jelly_vel = Vector3(0.5, -0.9, 0.5) * corpse_squash * 12.0   # a squish the moment it dies


## Spring-driven squash: a sudden change in the corpse's velocity (landing, bouncing, hitting a wall)
## squashes it along that direction and bulges it sideways, then it wobbles back. Clamped so it can't fold.
func _update_corpse_jelly(delta: float) -> void:
	var rb := _death_rb as RigidBody3D
	if rb == null or not is_instance_valid(rb) or _corpse_pivot == null or not is_instance_valid(_corpse_pivot):
		return

	var v := rb.linear_velocity
	var dv := v - _corpse_prev_vel
	_corpse_prev_vel = v
	var impact := dv.length()
	if impact > 1.5:
		var ld := (rb.global_transform.basis.inverse() * dv).normalized()
		var axis := Vector3(absf(ld.x), absf(ld.y), absf(ld.z))
		corpse_jelly_vel += (Vector3(0.5, 0.5, 0.5) * (Vector3.ONE - axis) - axis) * impact * corpse_squash * 4.0

	corpse_jelly_vel += (Vector3.ONE - corpse_jelly_scale) * corpse_jelly_stiffness * delta
	corpse_jelly_vel *= maxf(1.0 - corpse_jelly_damping * delta, 0.0)
	corpse_jelly_scale += corpse_jelly_vel * delta
	corpse_jelly_scale = corpse_jelly_scale.clamp(Vector3(0.6, 0.6, 0.6), Vector3(1.5, 1.5, 1.5))
	_corpse_pivot.scale = corpse_jelly_scale


func _apply_fade(delta: float) -> void:
	corpse_age += delta

	if not _corpse_is_soft:
		_update_corpse_jelly(delta)

	if not is_fading:
		return
	death_timer += delta
	var alpha = 1.0 - clamp(death_timer / death_fade_duration, 0.0, 1.0)
	if death_material:
		death_material.albedo_color.a = alpha
	for m in _limp_mats:
		m.set_shader_parameter("alpha", alpha)

func _respawn() -> void:
	if _death_rb and is_instance_valid(_death_rb):
		_death_rb.queue_free()
	if _death_face_rb and is_instance_valid(_death_face_rb):
		_death_face_rb.queue_free()
	if _limp_joint and is_instance_valid(_limp_joint):
		_limp_joint.queue_free()
	_limp_joint = null
	_limp_mats.clear()
	_death_rb = null
	_death_rb_mesh = null
	_death_face_rb = null
	_corpse_pivot = null
	corpse_jelly_scale = Vector3.ONE
	corpse_jelly_vel = Vector3.ZERO
	_corpse_is_soft = false
	corpse_age = 0.0
	jelly_scale = Vector3.ONE
	jelly_vel = Vector3.ZERO
	lean_x = 0.0
	lean_z = 0.0
	bob_offset = 0.0
	last_hit_dir = Vector3.ZERO

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
	mesh.scale = mesh_base_scale
	face_mesh.scale = face_base_scale
	face_mesh.rotation = Vector3.ZERO
	mesh.position.y = mesh_base_y
	face_mesh.position.y = face_mesh_base_y
	mesh.set_surface_override_material(0, original_material)
	face_mesh.set_surface_override_material(0, face_original_material)
