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

# NEW: stops enemies losing you the moment you sprint past them.
@export var los_check_interval := 0.1   # PERFORMANCE: seconds between line-of-sight / hearing ray checks (0.1 = 10 a second instead of 60)
@export var sleep_distance := 45.0       # PERFORMANCE: an idle enemy this far from the player only updates 1 frame in 6 (0 = never sleeps)
@export var anim_distance := 40.0        # PERFORMANCE: beyond this distance the jelly squash/stretch animation is skipped (0 = always animate)
var _los_timer := 0.0
var _los_cache := false
var _sleep_frame := 0
@export var close_sense_radius := 3.5   # inside this distance it notices you even from behind (still needs a clear line)
@export var lose_sight_grace := 1.5     # seconds it keeps coming after you lose sight, before giving up
var lost_sight_timer := 0.0

# =========================
# LOOK TOWARD A SHOT
# =========================
# When shot and it can't already see you, the enemy turns to face where the shot came from and looks around.
# If you're in its sight (range, angle and clear line) it goes after you. If not, it just keeps looking, then settles down.
@export var hit_look_time := 2.5          # seconds it keeps staring toward the shot before giving up
@export var hit_look_turn_speed := 8.0    # how fast it turns toward the shooter (higher = snappier)
@export var behind_shot_deaf_time := 6.0  # shot from behind: for this long it ignores footstep noise, so it has to actually SEE you
var look_timer := 0.0
var deaf_timer := 0.0                     # counts down; while > 0 sound detection is off
var look_target := Vector3.ZERO           # world position of whoever shot it

# =========================
# ATTACK (telegraphed lunge)
# =========================
@export var attack_range := 2.4          # CHANGED (was 2.6): starts an attack when the player is this close (flat distance)
@export var attack_windup := 0.4         # CHANGED (was 0.55): telegraph time — enemy turns orange and stops. Dodge window!
@export var attack_lunge_speed := 2.5    # the little step forward during the claw swipe (it no longer lunges across the room)
@export var attack_lunge_time := 0.3    # CHANGED (was 0.2): how long the lunge lasts
@export var attack_recover := 0.45       # CHANGED (was 0.6): vulnerable recovery after the lunge
@export var attack_cooldown := 0.6       # CHANGED (was 1.2): extra wait before it can attack again
@export var attack_damage := 20.0
@export var attack_hit_radius := 2.6     # CHANGED (was 1.8): how close the player must be during the lunge to get hit
@export var attack_knockback := 9.0

@export var sprint_speed := 8.0          # NEW: speed when it is running at you from far away
@export var sprint_min_distance := 4.5    # NEW: it sprints while you are further than this, then slows to a walk to swipe
@export var swipe_hit_time := 0.4         # NEW: how far through the swipe (0-1) the claws land
enum AttackPhase { NONE, WINDUP, LUNGE, RECOVER }   # LUNGE is now the claw swipe
var attack_phase: AttackPhase = AttackPhase.NONE
var attack_timer := 0.0
var attack_cooldown_timer := 0.0
var attack_hit_landed := false
var attack_right := true                  # which arm swipes (alternates)
var _sprinting := false
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
enum State { IDLE, ALERT, CHASING, ATTACKING, LOOKING }   # LOOKING = turned toward a shot, scanning for you
var state: State = State.IDLE
var player: Node3D = null
var last_known_position: Vector3 = Vector3.ZERO
var can_see_player := false

# =========================
# GOBLIN MODEL (replaces the old blob; walks, runs, claws, flinches and falls over by moving the rig's bones from code)
# =========================
@export_group("Goblin model")
@export var goblin_enabled := true                 # off = the old blob model, exactly as before
@export var goblin_scene_path := "res://goblin.glb"
@export var goblin_height_scale := 1.0             # 1.0 = the goblin is exactly as tall as the enemy's collision capsule
@export var goblin_arm_down_degrees := 68.0        # how far the arms hang down from the model's T-pose (90 = straight down)
@export var goblin_gait_rate := 5.0                # how fast the legs cycle for a given speed (raise if the feet slide)
@export var goblin_lean_strength := 1.0            # how much the body leans into its movement and rocks back in a wind-up
@export var goblin_squash_strength := 0.3          # how much of the old jelly squash-and-stretch is kept (0 = none)

const _GOBLIN_HEIGHT := 1.41                       # the goblin's height in its own file (metres)
static var _goblin_mat_shared: BaseMaterial3D = null

var _model_pivot: Node3D = null                    # feet-level pivot: lean, squash, and the death fall
var _skel: Skeleton3D = null
var _goblin_mi: MeshInstance3D = null
var _feet_local := Vector3.ZERO
var _model_scale := 1.0
var _bones := {}                                   # "thigh_l" -> bone index
var _flash_overlay: StandardMaterial3D = null
var _windup_overlay: StandardMaterial3D = null
var _g_gait := 0.0
var _g_move := 0.0
var _g_idle := 0.0
var _g_head := 0.0
var _g_hit := 0.0
var _g_sprint := 0.0
var _g_dead := false
var _g_fall_t := 0.0
var _g_fall_sign := 1.0

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

	_setup_goblin()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if is_dead:
		_apply_fade(delta)
		return

	# PERFORMANCE: an idle enemy far from the player does nothing useful (it can't see or hear you from here), so it only
	# runs one physics frame in six. It always runs fully while it's in the air, so it still settles onto the ground.
	if sleep_distance > 0.0 and state == State.IDLE and is_on_floor():
		if global_position.distance_squared_to(player.global_position) > sleep_distance * sleep_distance:
			_sleep_frame += 1
			if _sleep_frame % 6 != 0:
				return

	attack_cooldown_timer = max(attack_cooldown_timer - delta, 0.0)
	deaf_timer = max(deaf_timer - delta, 0.0)

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
				lost_sight_timer = lose_sight_grace
				last_known_position = player.global_position
				if _flat_distance_to_player() <= attack_range and attack_cooldown_timer <= 0.0 and player.get("is_dead") != true:
					_start_attack()
				else:
					# Far away: sprint. Close: walk the last bit and swipe.
					_sprinting = _flat_distance_to_player() > sprint_min_distance
					_move_toward(player.global_position, sprint_speed if _sprinting else move_speed)
			else:
				# CHANGED: keep coming for a moment after losing sight instead of giving up straight away.
				lost_sight_timer -= delta
				if lost_sight_timer > 0.0:
					_move_toward(last_known_position)
				else:
					state = State.ALERT
		State.ATTACKING:
			_process_attack(delta)
		State.LOOKING:
			# Stand still, turn toward the shot and watch. Seeing you (in _check_detection) flips this to CHASING.
			velocity.x = move_toward(velocity.x, 0.0, move_accel * 2.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_accel * 2.0 * delta)
			_face_position(look_target, hit_look_turn_speed, delta)
			look_timer -= delta
			if look_timer <= 0.0:
				state = State.IDLE

	if is_flashing:
		flash_timer -= delta
		if flash_timer <= 0.0:
			is_flashing = false
			_apply_base_materials()

	# PERFORMANCE: the squash-and-stretch animation is skipped for enemies too far away to notice it.
	if anim_distance <= 0.0 or global_position.distance_squared_to(player.global_position) < anim_distance * anim_distance:
		_apply_wobble(delta)
	move_and_slide()

# =========================
# DETECTION
# =========================
func _check_detection() -> void:
	# NEW: right after the player pops out of the ground (burrow) they're hidden for a moment: no sight, no hearing.
	var stealth = player.get("stealth_timer")
	var hidden: bool = stealth != null and stealth > 0.0
	# PERFORMANCE: the line-of-sight ray is only re-cast a few times a second (each enemy on its own beat), not every frame.
	_los_timer -= get_physics_process_delta_time()
	var refresh := _los_timer <= 0.0
	if refresh:
		_los_timer = los_check_interval + randf() * 0.05
		_los_cache = _has_line_of_sight()
	can_see_player = false if hidden else _los_cache
	# Once committed to an attack, don't let detection interrupt it.
	if state == State.ATTACKING:
		return
	if can_see_player:
		state = State.CHASING
		lost_sight_timer = lose_sight_grace
		last_known_position = player.global_position
		return
	if hidden:
		return
	# While looking toward a shot, only actually SEEING you makes it come after you (no sound detection).
	if state == State.LOOKING or deaf_timer > 0.0:
		return
	if not refresh:
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
	# NEW: right next to it, it notices you from any angle (as long as nothing solid is in the way).
	if dist <= close_sense_radius:
		return _raycast_clear(player.global_position)
	var dir_to_player = (player.global_position - global_position).normalized()
	var forward = -global_transform.basis.z
	var angle = rad_to_deg(forward.angle_to(dir_to_player))
	if angle > sight_angle:
		return false
	return _raycast_clear(player.global_position)

func _raycast_clear(target: Vector3) -> bool:
	var space = get_world_3d().direct_space_state
	# From the enemy's eyes to the player's chest, not from near the ground, so bumps in the terrain don't block the view.
	var from := global_position + Vector3.UP * 1.2
	var to := target + Vector3.UP * 1.0
	var mask := 0xFFFFFFFF & ~(1 << (FACEBOX_LAYER - 1))
	var exclude: Array[RID] = [get_rid()]
	# The ground is skipped (the ray carries on past it), so only trees, rocks, walls and other props block sight.
	for i in 4:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		query.collision_mask = mask
		var result = space.intersect_ray(query)
		if result.is_empty():
			return true
		if result.collider == player:
			return true
		if (result.position as Vector3).distance_to(to) < 1.0:
			return true                                 # it hit something right at the player (e.g. the ground under their feet)
		if _is_terrain(result.collider):
			exclude.append(result.rid)
			continue
		return false
	return true


## True if this physics body belongs to the terrain (a chunk of ground_chunks.gd).
func _is_terrain(col: Object) -> bool:
	var n := col as Node
	for i in 4:
		if n == null:
			return false
		if n.has_method("height_at"):
			return true
		n = n.get_parent()
	return false

# =========================
# MOVEMENT
# =========================
func _move_toward(target: Vector3, speed: float = -1.0) -> void:
	if speed < 0.0:
		speed = move_speed
	var dir = (target - global_position).normalized()
	# Ramp up to speed instead of snapping to it, so it feels like it has weight.
	var cur := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * speed, move_accel * get_physics_process_delta_time())
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
	attack_right = not attack_right
	_sprinting = false
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
			var sp := 1.0 - clampf(attack_timer / maxf(attack_lunge_time, 0.01), 0.0, 1.0)
			_face_position(player.global_position, 4.0, delta)   # the swipe follows you a little
			velocity.x = lunge_dir.x * attack_lunge_speed * (1.0 - sp)
			velocity.z = lunge_dir.z * attack_lunge_speed * (1.0 - sp)
			if not attack_hit_landed and sp >= swipe_hit_time and _player_in_hit_range():
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
	if absf(d.y) > 2.5:   # CHANGED (was 1.8): slopes and hops no longer make the lunge whiff
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
	lost_sight_timer = lose_sight_grace   # NEW: it keeps chasing for a moment even if you slipped behind it
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
	_goblin_set_overlay()

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
	if _model_pivot != null:
		_goblin_animate(delta)


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
		# Turn toward whoever shot us (unless we're mid-attack or already chasing something we can see).
		if state != State.ATTACKING and not (state == State.CHASING and can_see_player):
			look_target = (shooter as Node3D).global_position
			look_timer = hit_look_time
			state = State.LOOKING
			# Shot from behind (outside its view cone) = it can't "hear" you into chasing; it must turn and see you.
			var to_shooter := look_target - global_position
			to_shooter.y = 0.0
			if to_shooter.length() > 0.05:
				var shot_angle := rad_to_deg((-global_transform.basis.z).angle_to(to_shooter.normalized()))
				if shot_angle > sight_angle:
					deaf_timer = behind_shot_deaf_time
	jelly_vel += Vector3(0.6, -1.0, 0.6) * hit_squash * 12.0   # jiggle when hit
	_g_hit = 1.0                                               # the goblin flinches
	_start_flash()
	if health <= 0.0:
		die()

func _start_flash() -> void:
	is_flashing = true
	flash_timer = flash_duration
	mesh.set_surface_override_material(0, flash_material)
	face_mesh.set_surface_override_material(0, flash_material)
	_goblin_set_overlay()

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
	if _model_pivot != null:
		_goblin_death_begin(push)
		spawned = true
	if not spawned and limp_ragdoll and mesh.mesh:
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
	if _g_dead:
		_goblin_dead_update(delta)

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
	if _goblin_mi != null:
		_goblin_mi.transparency = 1.0 - alpha

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
	look_timer = 0.0
	deaf_timer = 0.0
	lost_sight_timer = 0.0

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
	mesh.visible = _model_pivot == null
	face_mesh.visible = _model_pivot == null
	_goblin_reset()
	mesh.rotation = Vector3.ZERO
	mesh.scale = mesh_base_scale
	face_mesh.scale = face_base_scale
	face_mesh.rotation = Vector3.ZERO
	mesh.position.y = mesh_base_y
	face_mesh.position.y = face_mesh_base_y
	mesh.set_surface_override_material(0, original_material)
	face_mesh.set_surface_override_material(0, face_original_material)


# =========================
# GOBLIN MODEL
# =========================
## Puts the goblin on the enemy, hides the old blob (its hit boxes and face box stay, so shooting works as before), and
## finds the bones it will move.
func _setup_goblin() -> void:
	if not goblin_enabled:
		return
	var ps := load(goblin_scene_path) as PackedScene
	if ps == null:
		push_warning("enemy: couldn't load %s, keeping the old model. Put goblin.glb in your project (or fix goblin_scene_path)." % goblin_scene_path)
		return
	var inst := ps.instantiate()
	for c in inst.get_children():
		if String(c.name).begins_with("WGT-"):            # leftover rig widgets from Blender, nothing to see
			c.free()
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		_skel = skels[0] as Skeleton3D
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).mesh != null:
			_goblin_mi = m as MeshInstance3D
			break
	if _goblin_mi == null:
		push_warning("enemy: %s has no mesh, keeping the old model." % goblin_scene_path)
		inst.free()
		_skel = null
		return

	# Where the feet are, and how big to make it: as tall as the collision capsule, so it fits the hit box.
	var cap := $CollisionShape3D.shape as CapsuleShape3D
	var height: float = cap.height if cap else 1.8
	var col_pos: Vector3 = $CollisionShape3D.position
	_feet_local = Vector3(col_pos.x, col_pos.y - height * 0.5, col_pos.z)
	_model_scale = height * goblin_height_scale / _GOBLIN_HEIGHT

	_model_pivot = Node3D.new()
	_model_pivot.name = "GoblinPivot"
	_model_pivot.position = _feet_local
	_model_pivot.scale = Vector3.ONE * _model_scale
	add_child(_model_pivot)
	var facing := Node3D.new()                           # the goblin faces +Z in its file, the enemy faces -Z
	facing.rotation.y = PI
	_model_pivot.add_child(facing)
	facing.add_child(inst)

	mesh.visible = false
	face_mesh.visible = false

	# The imported material is "blend" with no depth writing, which sorts badly on a character. One shared fixed copy for all goblins.
	var gm := _goblin_mi.get_active_material(0)
	if gm is BaseMaterial3D:
		if _goblin_mat_shared == null:
			_goblin_mat_shared = (gm as BaseMaterial3D).duplicate() as BaseMaterial3D
			_goblin_mat_shared.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_goblin_mi.set_surface_override_material(0, _goblin_mat_shared)
	_goblin_mi.extra_cull_margin = 1.0                   # posed arms reach outside the model's resting box

	# Red flash when hit and orange glow in the wind-up, laid over the goblin's own look.
	_flash_overlay = StandardMaterial3D.new()
	_flash_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_overlay.albedo_color = Color(1.0, 0.05, 0.05, 0.6)
	_flash_overlay.emission_enabled = true
	_flash_overlay.emission = Color.RED
	_flash_overlay.emission_energy_multiplier = 1.5
	_windup_overlay = StandardMaterial3D.new()
	_windup_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_windup_overlay.albedo_color = Color(1.0, 0.5, 0.05, 0.5)
	_windup_overlay.emission_enabled = true
	_windup_overlay.emission = Color(1.0, 0.45, 0.0)
	_windup_overlay.emission_energy_multiplier = 2.0

	if _skel != null:
		var names := {
			"thigh_l": "DEF-thigh.L", "thigh_r": "DEF-thigh.R", "shin_l": "DEF-shin.L", "shin_r": "DEF-shin.R",
			"foot_l": "DEF-foot.L", "foot_r": "DEF-foot.R", "arm_l": "DEF-upper_arm.L", "arm_r": "DEF-upper_arm.R",
			"fore_l": "DEF-forearm.L", "fore_r": "DEF-forearm.R", "head": "DEF-spine.006",
		}
		for key in names.keys():
			var idx := _skel.find_bone(names[key])
			if idx < 0:
				idx = _skel.find_bone(String(names[key]).replace(".", "_"))   # (in case the importer changed the dots)
			if idx < 0:
				push_warning("enemy: the goblin has no bone called %s, so that part won't animate." % names[key])
			_bones[key] = idx
	else:
		push_warning("enemy: the goblin has no skeleton, so it can't animate.")
	_goblin_animate(0.0)


func _goblin_set_overlay() -> void:
	if _goblin_mi == null:
		return
	if is_flashing:
		_goblin_mi.material_overlay = _flash_overlay
	elif attack_phase == AttackPhase.WINDUP:
		_goblin_mi.material_overlay = _windup_overlay
	else:
		_goblin_mi.material_overlay = null


## Turns a bone by `q` (a rotation in the goblin's own space, around the bone's own joint) on top of whatever its parent
## bones are doing. Bones are set parent-first, so every limb follows the bone above it.
func _bone_extra(key: String, q: Quaternion) -> void:
	var idx: int = _bones.get(key, -1)
	if idx < 0 or _skel == null:
		return
	var parent := _skel.get_bone_parent(idx)
	var pg := Basis.IDENTITY
	if parent >= 0:
		pg = _skel.get_bone_global_pose(parent).basis.orthonormalized()
	var rest_local := _skel.get_bone_rest(idx).basis.orthonormalized()
	var local := pg.inverse() * Basis(q) * pg * rest_local
	_skel.set_bone_pose_rotation(idx, local.get_rotation_quaternion())


## Poses the whole goblin. Angles are in radians. In the goblin's space +Z is forward, +Y is up and +X is its left. A swing
## about X that goes forward is NEGATIVE; the arms start in a T-pose and are brought down by `down`.
func _goblin_pose(th_l: float, th_r: float, knee_l: float, knee_r: float, arm_lx: float, arm_rx: float,
		down_l: float, down_r: float, elbow_l: float, elbow_r: float, head_yaw: float) -> void:
	if _skel == null:
		return
	var rx := Vector3(1.0, 0.0, 0.0)
	var rz := Vector3(0.0, 0.0, 1.0)
	_bone_extra("thigh_l", Quaternion(rx, th_l))
	_bone_extra("shin_l", Quaternion(rx, knee_l))
	_bone_extra("foot_l", Quaternion(rx, -(th_l + knee_l)))          # keeps the foot flat on the ground
	_bone_extra("thigh_r", Quaternion(rx, th_r))
	_bone_extra("shin_r", Quaternion(rx, knee_r))
	_bone_extra("foot_r", Quaternion(rx, -(th_r + knee_r)))
	_bone_extra("arm_l", Quaternion(rx, arm_lx) * Quaternion(rz, -down_l))   # (left arm points +X: down is a turn the other way for the right arm)
	_bone_extra("arm_r", Quaternion(rx, arm_rx) * Quaternion(rz, down_r))
	_bone_extra("fore_l", Quaternion(rx, -elbow_l))
	_bone_extra("fore_r", Quaternion(rx, -elbow_r))
	_bone_extra("head", Quaternion(Vector3.UP, head_yaw))


func _goblin_animate(delta: float) -> void:
	if _model_pivot == null:
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	_g_move = lerpf(_g_move, clampf(hs / 1.0, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	var sprint_k := clampf((hs - move_speed) / maxf(sprint_speed - move_speed, 0.1), 0.0, 1.0)
	_g_sprint = lerpf(_g_sprint, sprint_k, 1.0 - exp(-8.0 * delta))
	_g_gait = fposmod(_g_gait + delta * hs * goblin_gait_rate * (1.0 - 0.45 * _g_sprint), TAU)
	_g_idle += delta
	_g_hit = maxf(_g_hit - delta * 4.0, 0.0)

	var sp := _g_sprint
	var m := _g_move
	var fwd := sin(_g_gait)                                   # +1 = left leg furthest forward
	var thigh_amp := deg_to_rad(lerpf(34.0, 58.0, sp)) * m
	var breathe := sin(_g_idle * 2.0) * deg_to_rad(1.5)
	var down := deg_to_rad(goblin_arm_down_degrees)

	# Arms: [0] = left, [1] = right. They swing against the legs, and the elbow folds as the arm comes forward.
	var swing := deg_to_rad(lerpf(30.0, 55.0, sp)) * m
	var ax := [fwd * swing, -fwd * swing]                     # (negative = forward)
	var adown := [down + breathe, down - breathe]
	var elb_base := deg_to_rad(lerpf(14.0, 75.0, sp))
	var elb_range := deg_to_rad(lerpf(30.0, 40.0, sp)) * m
	var aelb := [elb_base + elb_range * 0.5 * (1.0 - fwd), elb_base + elb_range * 0.5 * (1.0 + fwd)]

	# Legs: the thigh swings, the knee folds as the leg comes through, and bends harder when sprinting.
	var knee_max := deg_to_rad(lerpf(60.0, 105.0, sp))
	var th := [-fwd * thigh_amp, fwd * thigh_amp]
	var knee := [deg_to_rad(6.0) + knee_max * maxf(0.0, cos(_g_gait)) * m,
		deg_to_rad(6.0) + knee_max * maxf(0.0, cos(_g_gait + PI)) * m]

	var crouch := 0.0
	var lean_extra := -deg_to_rad(20.0) * sp                  # sprinting: leaning forward
	var bounce := 0.035 + 0.03 * sp

	# The claw swipe: one arm winds up high and back while the body crouches and rocks back, then it rakes down and across
	# while the goblin steps in, then it recovers.
	if state == State.ATTACKING:
		var s_i := 1 if attack_right else 0
		var o_i := 1 - s_i
		var up := deg_to_rad(-150.0)
		match attack_phase:
			AttackPhase.WINDUP:
				var e := smoothstep(0.0, 1.0, 1.0 - attack_timer / maxf(attack_windup, 0.01))
				ax[s_i] = lerpf(ax[s_i], up, e)
				adown[s_i] = lerpf(adown[s_i], deg_to_rad(25.0), e)
				aelb[s_i] = lerpf(aelb[s_i], deg_to_rad(115.0), e)
				ax[o_i] = lerpf(ax[o_i], deg_to_rad(-45.0), e)
				aelb[o_i] = lerpf(aelb[o_i], deg_to_rad(80.0), e)
				crouch = e * 0.7
				lean_extra = deg_to_rad(10.0) * e
			AttackPhase.LUNGE:
				var p := clampf(1.0 - attack_timer / maxf(attack_lunge_time, 0.01), 0.0, 1.0)
				var e2 := 1.0 - pow(1.0 - p, 3.0)
				ax[s_i] = lerpf(up, deg_to_rad(-15.0), e2)
				adown[s_i] = lerpf(deg_to_rad(25.0), deg_to_rad(62.0), e2)
				aelb[s_i] = lerpf(deg_to_rad(115.0), deg_to_rad(12.0), e2)
				ax[o_i] = lerpf(deg_to_rad(-45.0), deg_to_rad(-10.0), e2)
				adown[o_i] = down
				aelb[o_i] = lerpf(deg_to_rad(80.0), deg_to_rad(45.0), e2)
				crouch = lerpf(0.7, 0.3, e2)
				lean_extra = lerpf(deg_to_rad(10.0), -deg_to_rad(22.0), e2)   # throws the shoulders into it
				var lead := 0 if attack_right else 1                         # the leg opposite the swinging arm steps in
				th[lead] = lerpf(0.0, deg_to_rad(-40.0), e2)
				knee[lead] = lerpf(deg_to_rad(30.0), deg_to_rad(15.0), e2)
				th[1 - lead] = deg_to_rad(20.0) * e2
				knee[1 - lead] = deg_to_rad(25.0)
			AttackPhase.RECOVER:
				var e3 := smoothstep(0.0, 1.0, 1.0 - attack_timer / maxf(attack_recover, 0.01))
				ax[s_i] = lerpf(deg_to_rad(-15.0), ax[s_i], e3)
				adown[s_i] = lerpf(deg_to_rad(62.0), adown[s_i], e3)
				aelb[s_i] = lerpf(deg_to_rad(12.0), aelb[s_i], e3)
				ax[o_i] = lerpf(deg_to_rad(-10.0), ax[o_i], e3)
				aelb[o_i] = lerpf(deg_to_rad(45.0), aelb[o_i], e3)
				crouch = lerpf(0.3, 0.0, e3)
				lean_extra = lerpf(-deg_to_rad(22.0), 0.0, e3)
				th[0] = lerpf(deg_to_rad(-20.0), th[0], e3)
				th[1] = lerpf(deg_to_rad(10.0), th[1], e3)
				knee[0] = lerpf(deg_to_rad(20.0), knee[0], e3)
				knee[1] = lerpf(deg_to_rad(20.0), knee[1], e3)

	# Crouch: both thighs come forward and both knees fold.
	th[0] -= crouch * deg_to_rad(22.0)
	th[1] -= crouch * deg_to_rad(22.0)
	knee[0] += crouch * deg_to_rad(45.0)
	knee[1] += crouch * deg_to_rad(45.0)

	# Flinch when hit: arms jerk up, elbows fold, the body rocks back.
	for i in 2:
		ax[i] -= _g_hit * deg_to_rad(50.0)
		adown[i] -= _g_hit * deg_to_rad(15.0)
		aelb[i] += _g_hit * deg_to_rad(30.0)

	# The head turns to follow you, within what a neck can do.
	var want_head := sin(_g_idle * 0.7) * 0.08
	if player != null and (state == State.CHASING or state == State.ATTACKING or state == State.LOOKING or state == State.ALERT):
		var to_p := global_transform.basis.inverse() * (player.global_position - global_position)
		want_head = clampf(atan2(-to_p.x, -to_p.z), -1.0, 1.0)
	_g_head = lerpf(_g_head, want_head, 1.0 - exp(-8.0 * delta))

	_goblin_pose(th[0], th[1], knee[0], knee[1], ax[0], ax[1], adown[0], adown[1], aelb[0], aelb[1], _g_head)

	# Body: lean into the movement, a little of the old squash, a bounce in step with the run, lower when crouched.
	_model_pivot.scale = Vector3.ONE * _model_scale * Vector3.ONE.lerp(jelly_scale, goblin_squash_strength)
	_model_pivot.rotation = Vector3((lean_x + lean_extra) * goblin_lean_strength + _g_hit * 0.25, 0.0, lean_z * goblin_lean_strength)
	_model_pivot.position = _feet_local + Vector3(0.0, absf(sin(_g_gait)) * bounce * m - crouch * 0.07, 0.0)


## Death: the goblin goes limp and falls over backwards (if it was shot from the front) or forwards, then fades like the old corpse did.
func _goblin_death_begin(push: Vector3) -> void:
	_g_dead = true
	_g_fall_t = 0.0
	var forward := -global_transform.basis.z
	_g_fall_sign = -1.0 if push.dot(forward) > 0.0 else 1.0
	_goblin_mi.material_overlay = null
	_g_hit = 0.0


func _goblin_dead_update(delta: float) -> void:
	if _model_pivot == null:
		return
	_g_fall_t = minf(_g_fall_t + delta / 0.5, 1.0)
	var e := 1.0 - pow(1.0 - _g_fall_t, 3.0)
	_model_pivot.scale = Vector3.ONE * _model_scale
	_model_pivot.rotation = Vector3(_g_fall_sign * PI * 0.5 * e, 0.0, 0.0)
	_model_pivot.position = _feet_local + Vector3(0.0, 0.12 * e, 0.0)             # lies on the ground, not in it
	# Limp: arms flop out to the sides, knees soften.
	var down := lerpf(deg_to_rad(goblin_arm_down_degrees), deg_to_rad(45.0), e)
	_goblin_pose(deg_to_rad(-8.0) * e, deg_to_rad(6.0) * e, deg_to_rad(15.0) * e, deg_to_rad(10.0) * e,
		deg_to_rad(-10.0) * e, deg_to_rad(10.0) * e, down, down, deg_to_rad(12.0), deg_to_rad(12.0), 0.0)


## Puts the goblin back on its feet (after respawning).
func _goblin_reset() -> void:
	if _model_pivot == null:
		return
	_g_dead = false
	_g_fall_t = 0.0
	_g_hit = 0.0
	_g_move = 0.0
	_g_sprint = 0.0
	_g_head = 0.0
	_model_pivot.rotation = Vector3.ZERO
	_model_pivot.scale = Vector3.ONE * _model_scale
	_model_pivot.position = _feet_local
	if _goblin_mi != null:
		_goblin_mi.transparency = 0.0
		_goblin_mi.material_overlay = null
	_goblin_animate(0.0)
