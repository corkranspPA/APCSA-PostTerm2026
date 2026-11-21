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
@export var attack_windup := 0.0         # CHANGED (was 0.55): telegraph time — enemy turns orange and stops. Dodge window!
@export var attack_lunge_speed := 4.0    # the little step forward during the claw swipe (it no longer lunges across the room)
@export var attack_lunge_time := 0.28    # CHANGED (was 0.2): how long the lunge lasts
@export var attack_recover := 0.22       # CHANGED (was 0.6): vulnerable recovery after the lunge
@export var attack_cooldown := 0.0       # CHANGED (was 1.2): extra wait before it can attack again
@export var attack_damage := 20.0
@export var attack_debug := false          # prints in the Output panel why a swipe missed (too far, or out of vertical reach)
@export var attack_hit_radius := 3.0     # CHANGED (was 1.8): how close the player must be during the lunge to get hit
@export var attack_knockback := 9.0

@export var sprint_speed := 10.0          # NEW: speed when it is running at you from far away
@export var sprint_min_distance := 0.0    # sprint while you are further than this (0 = he sprints all the way in and never slows down)
@export var hunt_time := 5.0              # NEW: how long he keeps tracking you after you get away (he runs at wherever you are, even without seeing you)
@export var swipe_hit_time := 0.4         # NEW: how far through the swipe (0-1) the claws land
enum AttackPhase { NONE, WINDUP, LUNGE, RECOVER }   # LUNGE is now the claw swipe
var attack_phase: AttackPhase = AttackPhase.NONE
var attack_timer := 0.0
var attack_cooldown_timer := 0.0
var attack_hit_landed := false
var _hunt_timer := 0.0
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
@export_subgroup("Goblin textures (drag images into these slots)")
@export var goblin_albedo_texture: Texture2D       # the colour image (goblin_ma_Base_color.jpg)
@export var goblin_roughness_texture: Texture2D    # optional: goblin_ma_Roughness.jpg
@export var goblin_metallic_texture: Texture2D     # optional: goblin_ma_Metallic.png
@export var goblin_translucency_texture: Texture2D # optional: goblin_ma_Translucency.jpg: makes thin parts (ears, fingers) glow a little when light comes through them
@export var goblin_translucency_strength := 0.35   # how strong that effect is (0 = off)
@export var goblin_normal_texture: Texture2D       # optional: goblin_ma_Normal_GL.jpg (the model already has its own, so only fill this to replace it)
@export_subgroup("Goblin texture file paths (only used if the slots above are empty)")
@export var goblin_albedo_path := "res://goblin_ma_Base_color.jpg"   # the goblin's real colour image (copy goblin_ma_Base_color.jpg from the Blender project into your project)
@export var goblin_albedo_fallback_path := "res://goblin_albedo.png"  # used if the real colour image isn't there: my painted stand-in
@export var goblin_roughness_path := "res://goblin_ma_Roughness.jpg"   # optional: leave it out of the project and the model's built-in one is used
@export var goblin_metallic_path := "res://goblin_ma_Metallic.png"      # optional, same
@export var goblin_height_scale := 1.0             # 1.0 = the goblin is exactly as tall as the enemy's collision capsule
@export var goblin_arm_down_degrees := 72.0        # how far the arms hang down from the model's T-pose (90 = straight down)
@export var goblin_gait_rate := 1.0                # 1.0 = legs step exactly as fast as the ground moves under them; lower if the feet look like they skate, raise if they drag
@export var goblin_lean_strength := 1.0            # how much the body leans into its movement and rocks back in a wind-up
@export var goblin_step_surge := 0.1             # how much the body speeds up on each push-off and eases on landing (0 = constant glide)
@export var goblin_shoulder_widen := 0.05          # how far each shoulder is moved out from the middle (metres, in the model's own size; 0 = original)
@export var goblin_run_arms_bend := true            # while running, the arms swing back straight and fold inward as they come forward
@export var goblin_elbow_out_degrees := 10.0        # elbows sit out from the body a little (the forearms angle back in)
@export var goblin_hands_parallel := false          # true = the hands ignore the forearms and stay lined up with his body. false = hands continue straight on from the forearms
@export var goblin_death_fall := true               # he goes limp AND falls over (backwards if shot from the front, forwards otherwise). false = he goes limp but stays standing
@export var goblin_feet_in_line := true              # feet stay in line with the legs (no ankle bending while walking, like when he stands). false = feet kept flat on the ground
@export var goblin_palms_in := true                 # palms always face in toward his body, also when the arm is raised or reaching
@export var goblin_hand_forward_degrees := 25.0     # how far the fingers point forward from straight down
@export var goblin_forearm_inward_degrees := 0.0    # how far each forearm angles in from the upper arm (0 = forearms line up with the upper arms)
@export var goblin_arms_still := true               # arms rest at his sides and don't move (except for the claw swipe)
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
var _g_stance := 0.5
var _q_pel := Quaternion.IDENTITY                  # hips' twist, tilt and pitch (the legs hang from the hips)
var _q_chest := Quaternion.IDENTITY                # hips + spine combined (the arms hang from the chest)
var _pel_pitch := 0.0
var _head_pitch := 0.0
var _head_roll := 0.0
var _g_posed := false
var _far_anim_ms := 0
var _head_pitch_idle := 0.0
var _toe_l := 0.0
var _toe_r := 0.0
var _hand_l := 0.0
var _hand_r := 0.0
var _sw_arm := 0                                   # which arm is doing the claw swipe (0 = left, 1 = right)
var _sw_w := 0.0                                   # how much the swipe pose is in charge of that arm (0..1)
var _sw_d := Vector3(0.65, 0.62, -0.25)            # swipe: where the upper arm points (body space; left arm shown, the right is mirrored)
var _sw_f := Vector3(0.35, 0.95, 0.15)             # swipe: where the forearm points
var _run_d := [Vector3.ZERO, Vector3.ZERO]         # running arm: where each upper arm points (left-arm frame, mirrored for the right)
var _run_f := [Vector3.ZERO, Vector3.ZERO]         # running arm: where each forearm points
var _run_w := 0.0                                  # how much the running arm swing is in charge (0..1)
var _elbow_in := 0.0                               # radians the forearms angle inward from the elbows
var _facing_node: Node3D = null                    # the node that turns the model round to face the right way
var _rd_on := false                                # the arms and legs are being simulated (death)
var _rd_d := []                                    # simulated limb directions in the goblin's own space: armL upper/fore, armR upper/fore, thighL/shinL, thighR/shinR
var _rd_v := []                                    # their swing speeds
var _rd_ground := 0.0                              # world height of the ground under him
var _gs := []                                      # smoothed pose values, so the upper body follows through instead of snapping
var _g_dead := false
var _g_fall_t := 0.0
var _g_fall_th := 0.04                              # how far over he has tipped (radians; PI/2 = flat on the ground)
var _g_fall_w := 0.0                                # how fast he is tipping (radians/second)
var _g_land_age := -1.0                             # corpse_age when he first hit the ground (-1 = not yet)
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

	# The goblin is posed on the very first frame, wherever it is, so it never shows the model's arms-out T-pose.
	if _model_pivot != null and not _g_posed:
		_g_posed = true
		_goblin_animate(0.016)
		_far_anim_ms = Time.get_ticks_msec()

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

	# Right next to it, it always attacks: no matter what state it is in (looking, alert, a stale "can't see you" from the
	# sight check) and no matter where you are relative to its view cone.
	if state != State.ATTACKING and attack_cooldown_timer <= 0.0 and player.get("is_dead") != true:
		var stl = player.get("stealth_timer")
		if not (stl != null and stl > 0.0) and _flat_distance_to_player() <= attack_range + 0.3 and _player_in_vertical_reach():
			_start_attack()

	# He tries again: while he is still hunting you (you got away, or he lost you and found his feet), he goes straight back to chasing.
	if _hunt_timer > 0.0:
		var stl2 = player.get("stealth_timer")
		if stl2 != null and stl2 > 0.0:
			_hunt_timer = 0.0                       # you vanished into the ground: he loses you
		elif state == State.IDLE or state == State.ALERT:
			state = State.CHASING

	match state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, move_accel * 2.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_accel * 2.0 * delta)
		State.ALERT:
			_move_toward(last_known_position, sprint_speed if global_position.distance_to(last_known_position) > 6.0 else -1.0)
			if global_position.distance_to(last_known_position) < 0.5:
				state = State.IDLE
		State.CHASING:
			if can_see_player:
				lost_sight_timer = lose_sight_grace
				_hunt_timer = hunt_time
				last_known_position = player.global_position
				if _flat_distance_to_player() <= attack_range and attack_cooldown_timer <= 0.0 and player.get("is_dead") != true:
					_start_attack()
				else:
					# He sprints the whole way in, with no slowing down as he gets close.
					_sprinting = _flat_distance_to_player() > sprint_min_distance
					_move_toward(player.global_position, sprint_speed if _sprinting else move_speed)
			else:
				# You got away or he lost sight of you: he keeps coming at where you are for a while, then at where he last saw you.
				lost_sight_timer -= delta
				if _hunt_timer > 0.0:
					_hunt_timer -= delta
					last_known_position = player.global_position
					_sprinting = _flat_distance_to_player() > sprint_min_distance
					_move_toward(player.global_position, sprint_speed if _sprinting else move_speed)
				elif lost_sight_timer > 0.0:
					_move_toward(last_known_position, sprint_speed)
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
		_far_anim_ms = Time.get_ticks_msec()
	elif _model_pivot != null:
		# Far away: the goblin still idles, just at a lower rate (about 8 times a second), by the real time that has passed.
		var now := Time.get_ticks_msec()
		var el := float(now - _far_anim_ms) / 1000.0
		if el >= 0.12:
			_far_anim_ms = now
			_goblin_animate(minf(el, 0.25))
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
	var accel := move_accel
	if _model_pivot != null and goblin_step_surge > 0.0:
		# Each push-off throws him forward and each landing checks him, so he moves in steps instead of gliding.
		var kk := clampf((speed - 1.0) / maxf(sprint_speed - 1.0, 0.1), 0.0, 1.0)
		speed *= 1.0 + goblin_step_surge * (0.5 + 0.5 * kk) * cos(4.0 * PI * (_g_gait - _g_stance)) * _g_move
		accel = maxf(move_accel, 28.0)
	var dir = (target - global_position).normalized()
	# Ramp up to speed instead of snapping to it, so it feels like it has weight.
	var cur := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * speed, accel * get_physics_process_delta_time())
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
	_hunt_timer = hunt_time
	if not is_flashing:
		_apply_base_materials()

func _process_attack(delta: float) -> void:
	match attack_phase:
		AttackPhase.WINDUP:
			# (no warning any more: the windup is zero length unless you set attack_windup)
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
				if attack_cooldown_timer <= 0.0 and player.get("is_dead") != true and _flat_distance_to_player() <= attack_range + 0.6:
					_start_attack()                        # still in reach: keep swinging

func _player_in_hit_range() -> bool:
	var d = player.global_position - global_position
	if not _player_in_vertical_reach():   # slopes, hops and walls: compares the player's real body, not the node's origin
		if attack_debug:
			print("goblin swipe missed: player is out of vertical reach")
		return false
	d.y = 0
	if attack_debug and d.length() > attack_hit_radius:
		print("goblin swipe missed: too far (", snappedf(d.length(), 0.01), " > ", attack_hit_radius, ")")
	return d.length() <= attack_hit_radius

## True when the player's body (their capsule, top to bottom) overlaps the height the goblin can reach, from a little below
## his feet to well above his head. Using the capsule instead of the player node's origin means it no longer matters
## where on the player the origin sits (feet, centre or camera).
func _player_in_vertical_reach() -> bool:
	var lo: float = player.global_position.y
	var hi: float = player.global_position.y
	var col = player.get("collision")
	if col is CollisionShape3D and (col as CollisionShape3D).shape is CapsuleShape3D:
		var half: float = ((col as CollisionShape3D).shape as CapsuleShape3D).height * 0.5
		lo = (col as CollisionShape3D).global_position.y - half
		hi = (col as CollisionShape3D).global_position.y + half
	else:
		lo -= 1.0
		hi += 1.0
	var feet: float = global_position.y + _feet_local.y
	return hi >= feet - 1.2 and lo <= feet + 4.0

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
	_hunt_timer = 0.0
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
	_facing_node = facing

	mesh.visible = false
	face_mesh.visible = false

	# The imported material is "blend" with no depth writing, which sorts badly on a character. One shared fixed copy for all goblins.
	var gm := _goblin_mi.get_active_material(0)
	if gm is BaseMaterial3D:
		if _goblin_mat_shared == null:
			_goblin_mat_shared = (gm as BaseMaterial3D).duplicate() as BaseMaterial3D
			_goblin_mat_shared.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			# The model's own colour map is only grey shading, so it was showing up grey. This is a painted colour map with
			# the goblin's real colours (green skin, brown shorts, bone skull hat, black beads, silver and gold bands, claws).
			var tex: Texture2D = goblin_albedo_texture if goblin_albedo_texture != null else _goblin_load_tex(goblin_albedo_path)
			if tex == null:
				tex = _goblin_load_tex(goblin_albedo_fallback_path)
			if tex != null:
				_goblin_mat_shared.albedo_texture = tex
				_goblin_mat_shared.albedo_color = Color.WHITE
				_goblin_mat_shared.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED  # the real colour image is fully opaque
			else:
				push_warning("enemy: couldn't find %s (or %s), so the goblin keeps the model's grey look. Copy the goblin's Base_color image into your project." % [goblin_albedo_path, goblin_albedo_fallback_path])
			var rt: Texture2D = goblin_roughness_texture if goblin_roughness_texture != null else _goblin_load_tex(goblin_roughness_path)
			if rt != null:
				_goblin_mat_shared.roughness_texture = rt
				_goblin_mat_shared.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				_goblin_mat_shared.roughness = 1.0
			var mt: Texture2D = goblin_metallic_texture if goblin_metallic_texture != null else _goblin_load_tex(goblin_metallic_path)
			var tr: Texture2D = goblin_translucency_texture if goblin_translucency_texture != null else _goblin_load_tex("res://goblin_ma_Translucency.jpg")
			if tr != null and goblin_translucency_strength > 0.0:
				_goblin_mat_shared.subsurf_scatter_enabled = true
				_goblin_mat_shared.subsurf_scatter_strength = goblin_translucency_strength
				_goblin_mat_shared.subsurf_scatter_texture = tr
				_goblin_mat_shared.backlight_enabled = true
				_goblin_mat_shared.backlight = Color(0.55, 0.65, 0.3) * goblin_translucency_strength
				_goblin_mat_shared.backlight_texture = tr
			if goblin_normal_texture != null:
				_goblin_mat_shared.normal_enabled = true
				_goblin_mat_shared.normal_texture = goblin_normal_texture
			if mt != null:
				_goblin_mat_shared.metallic_texture = mt
				_goblin_mat_shared.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				_goblin_mat_shared.metallic = 1.0
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
			"sp0": "DEF-spine", "sp1": "DEF-spine.001", "sp2": "DEF-spine.002", "sp3": "DEF-spine.003",
			"neck1": "DEF-spine.004", "neck2": "DEF-spine.005",
			"org_sh_l": "ORG-shoulder.L", "org_sh_r": "ORG-shoulder.R", "sh_l": "DEF-shoulder.L", "sh_r": "DEF-shoulder.R", "hand_l": "DEF-hand.L", "hand_r": "DEF-hand.R", "toe_l": "DEF-toe.L", "toe_r": "DEF-toe.R",
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


## Loads an image from the project if it is there (no error if it isn't).
func _goblin_load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _goblin_set_overlay() -> void:
	if _goblin_mi == null:
		return
	if is_flashing:
		_goblin_mi.material_overlay = _flash_overlay
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
	# Legs hang from the hips and arms from the chest, so they carry the body's twist and lean with them.
	var q_th := [_q_pel * Quaternion(rx, th_l), _q_pel * Quaternion(rx, th_r)]
	var q_sh := [Quaternion(rx, knee_l), Quaternion(rx, knee_r)]
	var feet_flat: bool = not goblin_feet_in_line
	if _rd_on and _rd_d.size() == 8:
		# Dead: the legs follow the simulation (each thigh and shin is aimed at where gravity has swung it).
		for i in 2:
			var sl := 1.0 if i == 0 else -1.0
			var t0 := Vector3(0.008 * sl, -0.237, -0.001).normalized()
			var s0 := Vector3(0.007 * sl, -0.249, -0.027).normalized()
			var qt: Quaternion = Quaternion(t0, _rd_d[4 + i * 2])
			q_th[i] = qt
			q_sh[i] = Quaternion(s0, _rd_d[5 + i * 2]) * qt.inverse()
		feet_flat = false
	_bone_extra("thigh_l", q_th[0])
	_bone_extra("shin_l", q_sh[0])
	_bone_extra("foot_l", Quaternion(rx, -(th_l + knee_l + _pel_pitch) + _toe_l) if feet_flat else Quaternion.IDENTITY)
	_bone_extra("toe_l", Quaternion(rx, -_toe_l) if feet_flat else Quaternion.IDENTITY)
	_bone_extra("thigh_r", q_th[1])
	_bone_extra("shin_r", q_sh[1])
	_bone_extra("foot_r", Quaternion(rx, -(th_r + knee_r + _pel_pitch) + _toe_r) if feet_flat else Quaternion.IDENTITY)
	_bone_extra("toe_r", Quaternion(rx, -_toe_r) if feet_flat else Quaternion.IDENTITY)
	# The collar bones (ORG-shoulder) carry the shoulder joints. Swinging an arm up and forward with the shoulder joint
	# fixed drives the armpit and shoulder through the chest, so while the swipe is on, the shoulder lifts and rolls
	# forward with the arm (the way a real shoulder does), which carries the whole arm out of the torso.
	var qs := [Quaternion.IDENTITY, Quaternion.IDENTITY]
	if _sw_w > 0.001:
		var sgs := 1.0 if _sw_arm == 0 else -1.0
		var lift := deg_to_rad(40.0) * maxf(_sw_d.y, 0.0) - deg_to_rad(10.0) * maxf(-_sw_d.y, 0.0)
		var prot := deg_to_rad(50.0) * _sw_d.z
		qs[_sw_arm] = Quaternion(rz, sgs * lift * _sw_w) * Quaternion(Vector3.UP, -sgs * prot * _sw_w)
	var qst: Array = [_q_chest * (qs[0] as Quaternion), _q_chest * (qs[1] as Quaternion)]
	_bone_extra("org_sh_l", qst[0])
	_bone_extra("org_sh_r", qst[1])
	_bone_shift("org_sh_l", Vector3(goblin_shoulder_widen, 0.0, 0.0))     # wider shoulders: both collar bones sit further out
	_bone_shift("org_sh_r", Vector3(-goblin_shoulder_widen, 0.0, 0.0))
	var q_arm := [_q_chest * Quaternion(rx, arm_lx) * Quaternion(rz, -down_l), _q_chest * Quaternion(rx, arm_rx) * Quaternion(rz, down_r)]
	var q_fore := [Quaternion(rz, _elbow_in) * Quaternion(rx, -elbow_l), Quaternion(rz, -_elbow_in) * Quaternion(rx, -elbow_r)]
	if _run_w > 0.001:
		# Running arms: each upper arm and forearm is aimed directly, so the whole arm moves (see the swipe below).
		for i in 2:
			var sr := 1.0 if i == 0 else -1.0
			var ur := Vector3(0.197 * sr, -0.041, 0.013).normalized()
			var fr := Vector3(0.151 * sr, -0.018, 0.014).normalized()
			var dr := Vector3((_run_d[i] as Vector3).x * sr, (_run_d[i] as Vector3).y, (_run_d[i] as Vector3).z).normalized()
			var ff := Vector3((_run_f[i] as Vector3).x * sr, (_run_f[i] as Vector3).y, (_run_f[i] as Vector3).z).normalized()
			var qa2: Quaternion = _q_chest * Quaternion(ur, dr)
			var qf2: Quaternion = (_q_chest * Quaternion(fr, ff)) * qa2.inverse()
			q_arm[i] = (q_arm[i] as Quaternion).slerp(qa2, _run_w)
			q_fore[i] = (q_fore[i] as Quaternion).slerp(qf2, _run_w)
	if _sw_w > 0.001:
		# The claw swipe. Swinging the arm by angles only twists it about its own length once it is raised out to the side
		# (so only the hand seemed to move). Instead, aim the upper arm and the forearm at where they should point, which
		# makes the whole arm reach and sweep, and keeps it out in front of the body instead of through it.
		var sg := 1.0 if _sw_arm == 0 else -1.0
		var u0 := Vector3(0.197 * sg, -0.041, 0.013).normalized()          # the arm's directions in the T-pose
		var f0 := Vector3(0.151 * sg, -0.018, 0.014).normalized()
		var d := Vector3(_sw_d.x * sg, _sw_d.y, _sw_d.z).normalized()
		var f := Vector3(_sw_f.x * sg, _sw_f.y, _sw_f.z).normalized()
		var qa: Quaternion = _q_chest * Quaternion(u0, d)
		var qf: Quaternion = (_q_chest * Quaternion(f0, f)) * qa.inverse()
		q_arm[_sw_arm] = (q_arm[_sw_arm] as Quaternion).slerp(qa, _sw_w)
		q_fore[_sw_arm] = (q_fore[_sw_arm] as Quaternion).slerp(qf, _sw_w)
	if _rd_on and _rd_d.size() == 8:
		# Dead: the arms follow the simulation too.
		for i in 2:
			var sa := 1.0 if i == 0 else -1.0
			var ua := Vector3(0.197 * sa, -0.041, 0.013).normalized()
			var fa2 := Vector3(0.151 * sa, -0.018, 0.014).normalized()
			var qau: Quaternion = Quaternion(ua, _rd_d[i * 2])
			q_arm[i] = qau
			q_fore[i] = Quaternion(fa2, _rd_d[i * 2 + 1]) * qau.inverse()
	# (The arm bones sit under the shoulders, so take the shoulders' own turn back out of what they are given.)
	_bone_extra("arm_l", (q_arm[0] as Quaternion) * (qst[0] as Quaternion).inverse())
	_bone_extra("arm_r", (q_arm[1] as Quaternion) * (qst[1] as Quaternion).inverse())
	_bone_extra("sh_l", _q_chest * Quaternion(rz, -clampf(down_l - 1.2, -0.4, 0.0) * 0.35) * (qst[0] as Quaternion).inverse())
	_bone_extra("sh_r", _q_chest * Quaternion(rz, clampf(down_r - 1.2, -0.4, 0.0) * 0.35) * (qst[1] as Quaternion).inverse())
	_bone_extra("fore_l", q_fore[0])
	_bone_extra("fore_r", q_fore[1])
	if goblin_hands_parallel:
		# Hands hold one direction relative to his body (fingers down and a little forward, palms toward him), whatever the
		# arm is doing, by cancelling out everything the arm and forearm have turned.
		for i in 2:
			var sh := 1.0 if i == 0 else -1.0
			var fa := deg_to_rad(goblin_hand_forward_degrees)
			var tgt := Vector3(-0.12 * sh, -cos(fa), sin(fa)).normalized()
			var q_des: Quaternion = _q_chest * Quaternion(Vector3(sh, 0.0, 0.0), tgt)
			var q_par: Quaternion = (q_fore[i] as Quaternion) * (q_arm[i] as Quaternion)
			_bone_extra("hand_l" if i == 0 else "hand_r", q_des * q_par.inverse())
	else:
		# Hands in line with the forearms, with the palms always turned in toward his body. A hand hanging at his side
		# already faces that way; when the arm is raised or reaching, the aimed arm leaves the palm facing down or out,
		# so the hand is rolled about its own length until the palm faces in again.
		for i in 2:
			var sp2 := 1.0 if i == 0 else -1.0
			var qp: Quaternion = (q_fore[i] as Quaternion) * (q_arm[i] as Quaternion)
			var hdir: Vector3 = qp * Vector3(sp2, 0.0, 0.0)                    # which way the hand points now
			var palm: Vector3 = qp * Vector3(0.0, -1.0, 0.0)                   # which way the palm faces now (it starts facing down)
			var want: Vector3 = _q_chest * Vector3(-sp2, 0.0, 0.0)              # toward the middle of the body
			want = want - hdir * want.dot(hdir)
			var roll := 0.0
			if goblin_palms_in and want.length() > 0.05:
				want = want.normalized()
				roll = atan2(hdir.dot(palm.cross(want)), palm.dot(want))
			_bone_extra("hand_l" if i == 0 else "hand_r", Quaternion(hdir.normalized(), roll))
	# Neck and head share the turn, so it reads as a neck rather than a head spinning on a post.
	var hq := Vector3(_head_pitch, head_yaw, _head_roll)
	_bone_extra("neck1", Quaternion(Basis.from_euler(hq * 0.25)))
	_bone_extra("neck2", Quaternion(Basis.from_euler(hq * 0.3)))
	_bone_extra("head", Quaternion(Basis.from_euler(hq * 0.45)))


## Moves a bone away from its resting place by `offset` (in the goblin's own space). Everything under it comes with it.
func _bone_shift(key: String, offset: Vector3) -> void:
	var idx: int = _bones.get(key, -1)
	if idx < 0 or _skel == null:
		return
	var parent := _skel.get_bone_parent(idx)
	var pg := Basis.IDENTITY
	if parent >= 0:
		pg = _skel.get_bone_global_pose(parent).basis.orthonormalized()
	_skel.set_bone_pose_position(idx, _skel.get_bone_rest(idx).origin + pg.inverse() * offset)


## Bends the spine. Torso angles are shared over the chest bones; the hips move on their own. Angles in radians: pitch
## (negative = forward), yaw (positive = turn left), roll (side lean).
func _goblin_spine(t_pitch: float, t_yaw: float, t_roll: float, p_pitch: float, p_yaw: float, p_roll: float) -> void:
	if _skel == null:
		return
	_q_pel = Quaternion(Basis.from_euler(Vector3(p_pitch, p_yaw, p_roll)))
	_pel_pitch = p_pitch
	_bone_extra("sp0", _q_pel)
	var qt := Quaternion(Basis.from_euler(Vector3(t_pitch, t_yaw, t_roll) / 3.0))
	_bone_extra("sp1", qt)
	_bone_extra("sp2", qt)
	_bone_extra("sp3", qt)
	_q_chest = qt * qt * qt * _q_pel


## Smooths one pose value toward its target.
func _gsm(i: int, target: float, rate: float, delta: float) -> float:
	while _gs.size() <= i:
		_gs.append(target)
	_gs[i] = lerpf(_gs[i], target, 1.0 - exp(-rate * delta))
	return _gs[i]


## One leg's pose for a point in its stride (u from 0 to 1, 0 = the foot lands). While the foot is on the ground the thigh
## sweeps back at a steady rate, so the foot is carried backwards at the speed the body moves forward and doesn't slide.
## Returns [thigh, knee, foot toe-down push-off].
func _leg_cycle(u: float, stance: float, fwd_a: float, back_a: float, k_stance: float, k_swing: float) -> Array:
	var th: float
	var knee: float
	var toe := 0.0
	if u < stance:
		var v := u / stance
		th = lerpf(-fwd_a, back_a, lerpf(v, smoothstep(0.0, 1.0, v), 0.35))   # sweeping back under the body (eased at the ends)
		knee = deg_to_rad(8.0) + k_stance * sin(PI * v) + deg_to_rad(10.0) * smoothstep(0.75, 1.0, v)   # soaks up the landing, then pushes off
		toe = smoothstep(0.65, 1.0, v) * deg_to_rad(55.0)      # heel comes up as the toes push
	else:
		var w := (u - stance) / (1.0 - stance)
		th = lerpf(back_a, -fwd_a, smoothstep(0.0, 1.0, w))   # swinging forward
		knee = deg_to_rad(18.0) + k_swing * sin(PI * pow(w, 0.75))      # heel kicks up, then the leg reaches out to land
		toe = (1.0 - smoothstep(0.0, 0.3, w)) * deg_to_rad(40.0) * 0.5
	return [th, knee, toe]


func _goblin_animate(delta: float) -> void:
	if _model_pivot == null:
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	_g_move = lerpf(_g_move, clampf(hs / 1.0, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	var k := clampf((hs - 1.0) / maxf(sprint_speed - 1.0, 0.1), 0.0, 1.0)      # 0 = a walk, 1 = a full sprint
	_g_sprint = lerpf(_g_sprint, clampf((hs - move_speed) / maxf(sprint_speed - move_speed, 0.1), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	_g_idle += delta
	_g_hit = maxf(_g_hit - delta * 4.0, 0.0)
	var m := _g_move
	var sp := _g_sprint

	# Stride shape grows with speed: longer steps, higher knees, less time on the ground.
	var stance := lerpf(0.6, 0.36, k)
	_g_stance = stance
	var fwd_a := deg_to_rad(lerpf(38.0, 60.0, k))
	var back_a := deg_to_rad(lerpf(34.0, 52.0, k))
	var k_stance := deg_to_rad(lerpf(14.0, 38.0, k))
	var k_swing := deg_to_rad(lerpf(60.0, 96.0, k))

	# Step the stride at exactly the rate that keeps a planted foot still on the ground: the foot travels back by one stride
	# length per footfall, and the body moves forward by the same amount.
	var sweep := (0.237 + 0.249) * _model_scale * (sin(fwd_a) + sin(back_a)) * 0.92
	_g_gait = fposmod(_g_gait + delta * hs * stance / maxf(sweep, 0.1) * goblin_gait_rate, 1.0)

	var cl := _leg_cycle(_g_gait, stance, fwd_a, back_a, k_stance, k_swing)
	var cr := _leg_cycle(fposmod(_g_gait + 0.5, 1.0), stance, fwd_a, back_a, k_stance, k_swing)
	var rest_knee := deg_to_rad(6.0)
	var th := [lerpf(0.0, cl[0], m), lerpf(0.0, cr[0], m)]
	var knee := [lerpf(rest_knee, cl[1], m), lerpf(rest_knee, cr[1], m)]
	var toe := [cl[2] * m, cr[2] * m]

	# Arms pump against the legs; the elbows fold hard as the hand comes forward, and sprinting holds them near a right angle.
	var down := deg_to_rad(goblin_arm_down_degrees)
	var breathe := sin(_g_idle * 2.0) * deg_to_rad(1.5)
	var ratio := lerpf(0.75, 1.15, k)
	var ax := [-th[0] * ratio, -th[1] * ratio]
	var adown := [down + breathe, down - breathe]
	var elb_base := deg_to_rad(lerpf(24.0, 92.0, k))
	var aelb := []
	for i in 2:
		var fwd_amount: float = clampf(-ax[i] / maxf(fwd_a * 1.3, 0.1), -1.0, 1.0)      # 1 = arm all the way forward
		aelb.append(elb_base + m * deg_to_rad(lerpf(40.0, 38.0, k)) * fwd_amount)
	# Arms swing out and in: each arm sweeps outward and back, then inward across the body, once per step, with only a
	# moderate swing forward and back. (A bit of quarter-stride offset makes the hand trace a loop.)
	var arc := sin(TAU * _g_gait)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var phase_in: float = clampf(-ax[i] / maxf(fwd_a * ratio, 0.1), -1.0, 1.0)     # 1 = arm forward
		adown[i] += m * deg_to_rad(38.0 + 14.0 * k) * (0.75 * phase_in + 0.25 * arc * side) - m * deg_to_rad(6.0 + 8.0 * k)
	# Sprinting like a soldier carrying a two-handed weapon (without the weapon): both arms held in front of the body at
	# waist height, elbows bent and tucked in, hands near the middle, barely swinging.
	if sp > 0.05:
		for i in 2:
			ax[i] = lerpf(ax[i], deg_to_rad(-48.0), sp)
			adown[i] = lerpf(adown[i], deg_to_rad(86.0), sp)
			aelb[i] = lerpf(aelb[i], deg_to_rad(100.0), sp)
	if goblin_arms_still:
		# Almost still: just a faint sway against the legs, a slight give at the elbow, and a little breathing.
		for i in 2:
			var sd := 1.0 if i == 0 else -1.0
			var still_ax: float = -th[i] * 0.1 * (0.5 + k)
			var still_down: float = down + breathe * 0.6 + m * deg_to_rad(2.5) * sin(TAU * _g_gait) * sd
			var still_elb: float = deg_to_rad(3.0) + m * deg_to_rad(4.0) * (0.5 - 0.5 * clampf(still_ax * 8.0, -1.0, 1.0))
			ax[i] = lerpf(still_ax, deg_to_rad(-48.0), sp)           # (while sprinting: held in front, see above)
			adown[i] = lerpf(still_down, deg_to_rad(86.0), sp)
			aelb[i] = lerpf(still_elb, deg_to_rad(100.0), sp)
	# Standing about: now and then one hand comes up to the chest (a scratch or a fidget), each arm on its own timing.
	var idle_k := 1.0 - m
	if idle_k > 0.01 and state != State.ATTACKING:
		for i in 2:
			var cyc := 9.0 if i == 0 else 13.0
			var ph0 := fposmod(_g_idle + (0.0 if i == 0 else 4.0), cyc)
			var bump := sin(PI * clampf((ph0 - (cyc - 2.4)) / 2.4, 0.0, 1.0))
			bump = bump * bump * idle_k
			ax[i] -= deg_to_rad(52.0) * bump
			aelb[i] += deg_to_rad(80.0) * bump
			adown[i] += deg_to_rad(14.0) * bump + deg_to_rad(3.0) * sin(_g_idle * 1.3 + float(i) * 2.0) * idle_k

	var crouch := 0.0
	var lean_extra := -deg_to_rad(14.0) * sp - deg_to_rad(5.0) * k * m          # leaning into the run
	var twist := 0.0

	# The claw swipe: a fast diagonal slash. One arm whips from high and outside down across the body to low on the far
	# side, the shoulders turning through it, with no wind-up pause. Each attack uses the other arm.
	var sw_target := 0.0
	if state == State.ATTACKING:
		var s_i := 1 if attack_right else 0
		var o_i := 1 - s_i
		var sgn := 1.0 if attack_right else -1.0
		var hi_x := deg_to_rad(-125.0)
		var lo_x := deg_to_rad(-25.0)
		var hi_down := deg_to_rad(15.0)       # arm out to the side and up
		var lo_down := deg_to_rad(112.0)      # arm across the body, past straight down
		match attack_phase:
			AttackPhase.WINDUP, AttackPhase.LUNGE:
				var p := 0.0
				if attack_phase == AttackPhase.LUNGE:
					p = clampf(1.0 - attack_timer / maxf(attack_lunge_time, 0.01), 0.0, 1.0)
				var rise := smoothstep(0.0, 0.25, p)                         # the arm snaps up and out in the first moments,
				var slash := 1.0 - pow(1.0 - smoothstep(0.2, 1.0, p), 3.0)   # then rakes across, fast at first
				ax[s_i] = lerpf(lerpf(ax[s_i], hi_x, rise), lo_x, slash)
				adown[s_i] = lerpf(lerpf(adown[s_i], hi_down, rise), lo_down, slash)
				aelb[s_i] = lerpf(lerpf(aelb[s_i], deg_to_rad(105.0), rise), deg_to_rad(15.0), slash)
				ax[o_i] = lerpf(ax[o_i], deg_to_rad(-40.0), rise)             # the other arm comes up as a guard
				aelb[o_i] = lerpf(aelb[o_i], deg_to_rad(85.0), rise)
				twist = sgn * lerpf(lerpf(0.0, -0.5, rise), 0.4, slash)       # shoulders wind back, then whip through
				# The reach: the arm starts high, out and back with the forearm cocked up; it then sweeps forward at
				# chest height, fully extended (the reach); and finishes low and across, still out in front of the body.
				_sw_arm = s_i
				var pa := Vector3(0.65, 0.62, -0.25)
				var pfa := Vector3(0.35, 0.95, 0.15)
				var pb := Vector3(0.40, 0.08, 0.92)
				var pfb := Vector3(0.12, 0.0, 1.0)
				var pc := Vector3(-0.05, -0.55, 0.83)
				var pfc := Vector3(-0.30, -0.70, 0.65)
				var s1 := smoothstep(0.12, 0.55, p)
				var s2 := smoothstep(0.5, 1.0, p)
				_sw_d = (pa.lerp(pb, s1).lerp(pc, s2)).normalized()
				_sw_f = (pfa.lerp(pfb, s1).lerp(pfc, s2)).normalized()
				sw_target = 1.0
				crouch = 0.45 * rise
				lean_extra = lerpf(lean_extra, -deg_to_rad(18.0), slash)
			AttackPhase.RECOVER:
				var e3 := smoothstep(0.0, 1.0, 1.0 - attack_timer / maxf(attack_recover, 0.01))
				ax[s_i] = lerpf(lo_x, ax[s_i], e3)
				adown[s_i] = lerpf(lo_down, adown[s_i], e3)
				aelb[s_i] = lerpf(deg_to_rad(15.0), aelb[s_i], e3)
				ax[o_i] = lerpf(deg_to_rad(-40.0), ax[o_i], e3)
				aelb[o_i] = lerpf(deg_to_rad(85.0), aelb[o_i], e3)
				twist = sgn * lerpf(0.4, 0.0, e3)
				crouch = lerpf(0.45, 0.0, e3)
				_sw_arm = s_i
				_sw_d = Vector3(-0.05, -0.55, 0.83).normalized()
				_sw_f = Vector3(-0.30, -0.70, 0.65).normalized()
				sw_target = 1.0 - e3

	th[0] -= crouch * deg_to_rad(22.0)
	th[1] -= crouch * deg_to_rad(22.0)
	knee[0] += crouch * deg_to_rad(45.0)
	knee[1] += crouch * deg_to_rad(45.0)

	# Flinch when hit: arms jerk up, elbows fold, the body rocks back.
	for i in 2:
		if goblin_arms_still:
			continue
		ax[i] -= _g_hit * deg_to_rad(50.0)
		adown[i] -= _g_hit * deg_to_rad(15.0)
		aelb[i] += _g_hit * deg_to_rad(30.0)

	# ---- flexibility: the body moves as one soft chain instead of a stiff block ----
	var ph := TAU * _g_gait
	var runk := k * m
	# Hips turn and tilt with each stride; the shoulders twist the other way and the torso leans into it.
	var p_yaw := cos(ph) * deg_to_rad(20.0) * runk + sin(_g_idle * 0.5) * deg_to_rad(3.0) * (1.0 - m)
	var p_roll := sin(ph * 2.0) * deg_to_rad(10.0) * runk + sin(_g_idle * 0.7) * deg_to_rad(2.0) * (1.0 - m)
	var p_pitch := deg_to_rad(4.0) * m * (0.3 + k) + deg_to_rad(8.0) * crouch
	var t_yaw := -p_yaw * 2.0 + sin(_g_idle * 0.6) * deg_to_rad(2.0) * (1.0 - m) + twist * 0.9
	var t_roll := -p_roll * 1.8 + sin(_g_idle * 0.9) * deg_to_rad(1.5) * (1.0 - m)
	var t_pitch := sin(ph * 2.0 + 0.6) * deg_to_rad(4.0) * runk - deg_to_rad(8.0) * sp + sin(_g_idle * 2.0) * deg_to_rad(1.2) + _g_hit * deg_to_rad(20.0) + deg_to_rad(14.0) * crouch
	if state == State.ATTACKING and attack_phase != AttackPhase.RECOVER:
		t_pitch -= deg_to_rad(10.0)                                  # chest drives into the swipe

	# Footfall impact: each time a foot lands the body takes a jolt. It drops, the chest and head tip into it, the knee
	# gives, and the held arms and the hips shake with it, then it recovers before the next step.
	var imp_l := exp(-_g_gait * 11.0)
	var imp_r := exp(-fposmod(_g_gait + 0.5, 1.0) * 11.0)
	var imp := _gsm(18, (imp_l + imp_r) * m * (0.35 + 0.65 * k), 30.0, delta)
	var imp_side := _gsm(19, (imp_l - imp_r) * m * k, 30.0, delta)
	t_pitch -= imp * deg_to_rad(7.0 + 3.0 * sp)
	t_roll += imp_side * deg_to_rad(6.0) * sp                    # lurches onto each stomp
	p_roll += imp_side * deg_to_rad(6.0)
	knee[0] += imp * deg_to_rad(12.0)
	knee[1] += imp * deg_to_rad(12.0)
	for i in 2:
		if goblin_arms_still:
			ax[i] += imp * deg_to_rad(2.5 + 4.0 * sp)           # a small jolt on each footfall
			aelb[i] += imp * deg_to_rad(8.0) * sp
			adown[i] += imp * deg_to_rad(1.5)
			continue
		ax[i] += imp * deg_to_rad(10.0) * sp                    # held arms jolt with the landing
		aelb[i] += imp * deg_to_rad(14.0) * sp
		adown[i] += imp * deg_to_rad(5.0) * sp

	# Idle: weight shifts slowly from one leg to the other (the unloaded knee softens), and he breathes.
	var shift := sin(_g_idle * 0.35)
	p_roll += shift * deg_to_rad(4.0) * (1.0 - m)
	p_yaw += sin(_g_idle * 0.21) * deg_to_rad(3.0) * (1.0 - m)
	knee[0] += maxf(shift, 0.0) * deg_to_rad(11.0) * (1.0 - m)
	knee[1] += maxf(-shift, 0.0) * deg_to_rad(11.0) * (1.0 - m)
	th[0] -= maxf(shift, 0.0) * deg_to_rad(5.0) * (1.0 - m)
	th[1] -= maxf(-shift, 0.0) * deg_to_rad(5.0) * (1.0 - m)
	t_pitch += sin(_g_idle * 1.6) * deg_to_rad(1.6) * (1.0 - m)

	var rate_t := 11.0
	var rate_a := 16.0
	t_yaw = _gsm(0, t_yaw, rate_t, delta)
	t_roll = _gsm(1, t_roll, rate_t, delta)
	t_pitch = _gsm(2, t_pitch, rate_t, delta)
	p_yaw = _gsm(3, p_yaw, rate_t, delta)
	p_roll = _gsm(4, p_roll, rate_t, delta)
	p_pitch = _gsm(5, p_pitch, rate_t, delta)
	th[0] = _gsm(12, th[0], 22.0, delta)
	th[1] = _gsm(13, th[1], 22.0, delta)
	knee[0] = _gsm(14, knee[0], 20.0, delta)
	knee[1] = _gsm(15, knee[1], 20.0, delta)
	toe[0] = _gsm(16, toe[0], 18.0, delta)
	toe[1] = _gsm(17, toe[1], 18.0, delta)
	_sw_w = _gsm(20, sw_target, 24.0, delta)
	var ax_s := [_gsm(6, ax[0], rate_a, delta), _gsm(7, ax[1], rate_a, delta)]
	var ad_s := [_gsm(8, adown[0], rate_a, delta), _gsm(9, adown[1], rate_a, delta)]
	var ae_s := [_gsm(10, aelb[0], rate_a, delta), _gsm(11, aelb[1], rate_a, delta)]

	# Hands trail behind the arm and snap after it, and the heels' toes bend with the push-off.
	_hand_l = clampf((ax[0] - ax_s[0]) * 1.4 + deg_to_rad(8.0), -0.9, 0.9)
	_hand_r = clampf((ax[1] - ax_s[1]) * 1.4 + deg_to_rad(8.0), -0.9, 0.9)
	_toe_l = toe[0]
	_toe_r = toe[1]

	# The head follows you, stays steadier than the chest, and tips with the movement.
	# Idle: he glances slowly around, pausing to look one way, then the other (and a little up and down).
	var want_head := (sin(_g_idle * 0.45) * 0.55 + sin(_g_idle * 0.93 + 1.3) * 0.22) * (1.0 - m) + sin(_g_idle * 0.7) * 0.08 * m
	if player != null and (state == State.CHASING or state == State.ATTACKING or state == State.LOOKING or state == State.ALERT):
		var to_p := global_transform.basis.inverse() * (player.global_position - global_position)
		var ang := atan2(-to_p.x, -to_p.z)
		# Only look at you when you are in front of him. Behind his shoulders he faces forward instead of craning round.
		var in_front := 1.0 - smoothstep(deg_to_rad(65.0), deg_to_rad(105.0), absf(ang))
		want_head = clampf(ang, -1.0, 1.0) * in_front
	want_head -= t_yaw * 0.6                                         # cancel most of the torso's twist so the eyes stay on you
	_g_head = lerpf(_g_head, want_head, 1.0 - exp(-8.0 * delta))
	_head_pitch = _head_pitch_idle - t_pitch * (0.6 + 0.2 * sp) - p_pitch * 0.3 - _g_hit * 0.3 - imp * deg_to_rad(10.0)     # head nods into each landing
	_head_pitch_idle = sin(_g_idle * 0.6 + 0.5) * 0.1 * (1.0 - m)
	_head_roll = -t_roll * 0.7 + sin(ph) * deg_to_rad(7.0) * runk
	_head_pitch += sin(ph * 2.0) * deg_to_rad(8.0) * runk

	# Elbows out: the upper arms angle out a little and the forearms come back in toward the body.
	_elbow_in = deg_to_rad(goblin_forearm_inward_degrees)
	for i in 2:
		ad_s[i] -= deg_to_rad(goblin_elbow_out_degrees)

	# Running arms: as an arm goes back it extends straight down behind; as it comes forward the elbow folds and the hand
	# tucks inward toward the middle of the chest; then it straightens and drops back again. Opposite to the legs.
	var run_target := 0.0
	if goblin_run_arms_bend:
		run_target = smoothstep(2.0, 6.0, hs) * m
	_run_w = _gsm(21, run_target, 10.0, delta)
	if _run_w > 0.001:
		var back_d := Vector3(0.20, -0.86, -0.46)
		var back_f := Vector3(0.14, -0.93, -0.34)       # (almost straight, hanging down behind)
		var fwd_d := Vector3(0.22, -0.78, 0.58)
		var fwd_f := Vector3(-0.20, 0.12, 0.97)         # (folded up and inward toward the chest)
		for i in 2:
			var ua := _g_gait if i == 0 else fposmod(_g_gait + 0.5, 1.0)       # the left arm is back when the left leg is forward
			var tt := 0.5 - 0.5 * cos(TAU * ua)                                  # 0 = furthest back, 1 = furthest forward
			var bend := smoothstep(0.1, 0.95, tt)
			_run_d[i] = back_d.lerp(fwd_d, tt).normalized()
			_run_f[i] = back_f.lerp(fwd_f, bend).normalized()
	_goblin_spine(t_pitch, t_yaw, t_roll, p_pitch, p_yaw, p_roll)
	_goblin_pose(th[0], th[1], knee[0], knee[1], ax_s[0], ax_s[1], ad_s[0], ad_s[1], ae_s[0], ae_s[1], _g_head + cos(ph) * deg_to_rad(9.0) * runk * (0.0 if state == State.ATTACKING else 1.0))

	# Height: the body sits exactly as high as the planted foot needs, so a bent leg lowers the body and the foot stays on
	# the ground instead of floating or sinking. In a run the body also rises and falls once per step.
	var h_need := 0.0
	for i in 2:
		h_need = maxf(h_need, 0.051 + 0.237 * cos(th[i]) + 0.249 * cos(th[i] + knee[i]))
	var drop := (h_need - 0.537) * _model_scale
	var rise_run := 0.0
	if m > 0.05:
		rise_run = 0.5 * (1.0 - cos(4.0 * PI * (_g_gait - stance * 0.5))) * (0.035 + 0.11 * k) * m

	_model_pivot.scale = Vector3.ONE * _model_scale * Vector3.ONE.lerp(jelly_scale, goblin_squash_strength)
	_model_pivot.rotation = Vector3((lean_x + lean_extra) * goblin_lean_strength + _g_hit * 0.25, twist * 0.3, lean_z * goblin_lean_strength)
	var sway := cos(ph) * (0.02 + 0.08 * k) * runk                  # weight rolls onto the planted foot
	var idle_sway := sin(_g_idle * 0.8) * 0.012 * (1.0 - m)
	_model_pivot.position = _feet_local + Vector3(sway + idle_sway, drop + rise_run - imp * (0.03 + 0.05 * k + 0.04 * sp), 0.0)


## Death: the goblin goes limp and falls over backwards (if it was shot from the front) or forwards, then fades like the old corpse did.
func _goblin_death_begin(push: Vector3) -> void:
	_g_dead = true
	_sw_w = 0.0
	_run_w = 0.0
	_elbow_in = 0.0
	_g_fall_t = 0.0
	_g_fall_th = 0.04
	_g_fall_w = clampf(0.25 + 0.1 * push.length(), 0.25, 1.4)      # the killing blow gives him his first shove
	_g_land_age = -1.0
	_rd_start(push)
	var forward := -global_transform.basis.z
	_g_fall_sign = -1.0 if push.dot(forward) > 0.0 else 1.0
	_goblin_mi.material_overlay = null
	_g_hit = 0.0


func _goblin_dead_update(delta: float) -> void:
	if _model_pivot == null:
		return
	_goblin_limp_update(delta, goblin_death_fall)


## Death: every muscle lets go. The knees give, the back slumps, the head drops and the arms hang and swing loosely. With
## `fall` on he also topples over like a dropped sack, with the limp joints letting him fold as he goes.
func _goblin_limp_update(delta: float, fall: bool) -> void:
	_g_fall_t = minf(_g_fall_t + delta / 0.35, 1.0)
	var e := 1.0 - pow(1.0 - _g_fall_t, 2.0)
	var loose := exp(-corpse_age * 2.5)                          # the arms' loose swing dies away (starts again when he hits the ground)
	if _g_land_age >= 0.0:
		loose = 1.4 * exp(-(corpse_age - _g_land_age) * 3.0)
	_model_pivot.scale = Vector3.ONE * _model_scale
	var th := [deg_to_rad(-12.0) * e, deg_to_rad(9.0) * e]
	var kn := [deg_to_rad(46.0) * e, deg_to_rad(34.0) * e]
	var h_need := 0.0
	for i in 2:
		h_need = maxf(h_need, 0.051 + 0.237 * cos(th[i]) + 0.249 * cos(th[i] + kn[i]))
	var sag_y := (h_need - 0.537) * _model_scale
	if fall:
		# Gravity takes him: he tips over his heels like a dropped plank. The pull gets stronger the further over he is, so he
		# starts slowly and drops faster and faster, then lands with a thump and a small bounce.
		var dt := minf(delta, 0.033)
		var steps := 3
		for _i in steps:
			var h := dt / float(steps)
			_g_fall_w += (9.0 * sin(_g_fall_th) + 1.5) * h
			_g_fall_th += _g_fall_w * h
			if _g_fall_th >= PI * 0.5:
				_g_fall_th = PI * 0.5
				if _g_fall_w > 0.8:
					_g_fall_w = -_g_fall_w * 0.2                              # small bounce
				else:
					_g_fall_w = 0.0
				if _g_land_age < 0.0:
					_g_land_age = corpse_age
		var ef := _g_fall_th / (PI * 0.5)
		_rd_step(dt, _g_land_age >= 0.0 and corpse_age - _g_land_age < dt * 1.5)
		_model_pivot.rotation = Vector3(_g_fall_sign * _g_fall_th, 0.0, deg_to_rad(4.0) * e)
		_model_pivot.position = _feet_local + Vector3(0.0, lerpf(sag_y, 0.12, ef), 0.0)       # lies on the ground, not in it
	else:
		_model_pivot.rotation = Vector3(_g_fall_sign * deg_to_rad(-6.0) * e, 0.0, deg_to_rad(4.0) * e)
		_model_pivot.position = _feet_local + Vector3(0.0, sag_y, 0.0)
	_toe_l = 0.0
	_toe_r = 0.0
	_hand_l = 0.0
	_hand_r = 0.0
	_head_pitch = -0.5 * e + sin(corpse_age * 7.0) * 0.06 * loose
	_head_roll = 0.25 * e
	_goblin_spine(-deg_to_rad(26.0) * e, deg_to_rad(5.0) * e, deg_to_rad(7.0) * e, deg_to_rad(8.0) * e, 0.0, 0.0)
	var down := lerpf(deg_to_rad(goblin_arm_down_degrees), deg_to_rad(82.0), e)
	var swing := sin(corpse_age * 6.0) * 0.18 * loose
	_goblin_pose(th[0], th[1], kn[0], kn[1], swing, -swing, down, down, deg_to_rad(10.0), deg_to_rad(10.0), 0.0)


# Limb segments for the death simulation: root joint (goblin space), length, and how far it may swing from its parent.
const _RD_LEN := [0.20, 0.25, 0.20, 0.25, 0.237, 0.34, 0.237, 0.34]

func _rd_root(i: int) -> Vector3:
	var sx := 1.0 if (i == 0 or i == 1 or i == 4 or i == 5) else -1.0
	if i < 4:
		return Vector3(0.117 + goblin_shoulder_widen, 0.948, -0.016) * Vector3(sx, 1.0, 1.0)
	return Vector3(0.081 * sx, 0.537, 0.018)


## Starts the arms and legs flopping: they begin where he stood and are free to swing.
func _rd_start(push: Vector3) -> void:
	if _facing_node == null or not goblin_death_fall:
		_rd_on = false
		return
	var mn := _facing_node.global_transform.basis.orthonormalized()
	var pm := mn.inverse() * push.normalized() if push.length() > 0.01 else Vector3.ZERO
	_rd_d = []
	_rd_v = []
	for i in 8:
		var sx := 1.0 if (i == 0 or i == 1 or i == 4 or i == 5) else -1.0
		var d := Vector3.ZERO
		if i < 4:
			d = Vector3(0.31 * sx, -0.95, 0.0).normalized()          # arms hang by his sides
		else:
			d = Vector3(0.0, -1.0, -0.03).normalized()               # legs straight down
		_rd_d.append(d)
		_rd_v.append((-pm - d * (-pm).dot(d)) * 2.0)                 # the shove throws the limbs the other way
	_rd_ground = global_position.y + _feet_local.y
	_rd_on = true


## One step of the simulation. Every limb segment is a swinging pendulum under gravity (gravity is worked out in the
## goblin's own space, so it changes direction as he tips over), with loose joints that can only bend so far, a floor
## the limbs can't go through, and a bounce when he lands.
func _rd_step(dt: float, landed_now: bool) -> void:
	if not _rd_on or _facing_node == null or _rd_d.size() != 8:
		return
	var mn := _facing_node.global_transform.basis.orthonormalized()
	var mi := mn.inverse()
	var g := mi * Vector3.DOWN
	var scale_w := _model_scale
	var floor_y := _rd_ground + 0.04
	var start := Vector3.ZERO
	for i in 8:
		var lower := (i % 2) == 1
		var d: Vector3 = _rd_d[i]
		var v: Vector3 = _rd_v[i]
		var parent_d := Vector3.ZERO
		if lower:
			parent_d = _rd_d[i - 1]
			start = start + parent_d * float(_RD_LEN[i - 1])
		else:
			start = _rd_root(i)
		var is_arm := i < 4
		if landed_now:
			var up := -g
			v += (up - d * up.dot(d)) * (3.2 if is_arm else 2.0)
		var k := 20.0 if is_arm else 16.0
		var a := (g - d * g.dot(d)) * k
		if lower:
			a += (parent_d - d * parent_d.dot(d)) * (4.0 if is_arm else 6.0)      # the elbow and knee want to straighten a little
		a -= v * 2.4
		v += a * dt
		v -= d * v.dot(d)
		d = (d + v * dt).normalized()
		# Joint limits: how far this segment may swing from its parent (or, for the upper arm and thigh, from its rest line).
		var ref: Vector3
		var max_ang: float
		if lower:
			ref = parent_d
			max_ang = deg_to_rad(140.0 if is_arm else 125.0)
		elif is_arm:
			ref = Vector3((1.0 if i == 0 else -1.0), -0.2, 0.0).normalized()
			max_ang = deg_to_rad(150.0)
		else:
			ref = Vector3(0.0, -1.0, 0.0)
			max_ang = deg_to_rad(80.0)
		var cosang := clampf(d.dot(ref), -1.0, 1.0)
		if acos(cosang) > max_ang:
			var side := d - ref * cosang
			if side.length() < 0.0001:
				side = Vector3(0.0, 0.0, 1.0) - ref * ref.z
			side = side.normalized()
			d = (ref * cos(max_ang) + side * sin(max_ang)).normalized()
			v *= 0.3
		# The floor: if the far end would go below the ground, push the segment up along it.
		var seg_len := float(_RD_LEN[i])
		var start_w := _facing_node.global_transform * start
		var dw := mn * d
		var min_y := clampf((floor_y - start_w.y) / maxf(seg_len * scale_w, 0.01), -1.0, 1.0)
		if dw.y < min_y:
			var hl := Vector2(dw.x, dw.z)
			var target_h := sqrt(maxf(1.0 - min_y * min_y, 0.0))
			if hl.length() > 0.0001:
				hl = hl.normalized() * target_h
			else:
				hl = Vector2(target_h, 0.0)
			dw = Vector3(hl.x, min_y, hl.y)
			d = (mi * dw).normalized()
			v *= 0.4
		_rd_d[i] = d
		_rd_v[i] = v


## Puts the goblin back on its feet (after respawning).
func _goblin_reset() -> void:
	if _model_pivot == null:
		return
	_g_dead = false
	_g_fall_t = 0.0
	_g_fall_th = 0.04
	_g_fall_w = 0.0
	_g_land_age = -1.0
	_rd_on = false
	_g_hit = 0.0
	_g_move = 0.0
	_gs.clear()
	_q_pel = Quaternion.IDENTITY
	_q_chest = Quaternion.IDENTITY
	_g_sprint = 0.0
	_g_head = 0.0
	_model_pivot.rotation = Vector3.ZERO
	_model_pivot.scale = Vector3.ONE * _model_scale
	_model_pivot.position = _feet_local
	if _goblin_mi != null:
		_goblin_mi.transparency = 0.0
		_goblin_mi.material_overlay = null
	_goblin_animate(0.0)
