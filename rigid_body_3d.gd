extends RigidBody3D
class_name Bullet

# -------------------------
# BULLET STATS
# -------------------------
@export var speed := 80.0
@export var damage := 25.0
@export var headshot_multiplier := 2.0
@export var gravity_scale_value := 0.08   # slight bullet drop
@export var lifetime := 3.0               # seconds before auto-free
@export var impact_scene: PackedScene     # optional impact VFX

# -------------------------
# VARIABLES
# -------------------------
var shooter
var direction := Vector3.ZERO

# -------------------------
# READY
# -------------------------
func _ready() -> void:
	# Enable collision monitoring
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

	# Ignore collision with shooter
	if shooter:
		add_collision_exception_with(shooter)

	# Apply gravity scale
	gravity_scale = gravity_scale_value

	# Set initial velocity
	if direction != Vector3.ZERO:
		linear_velocity = direction.normalized() * speed
	else:
		linear_velocity = -global_transform.basis.z * speed

	# Auto-despawn timer
	await get_tree().create_timer(lifetime).timeout

	if is_instance_valid(self):
		queue_free()


# -------------------------
# LAUNCH FUNCTION
# -------------------------
func launch(origin: Vector3, dir: Vector3, from_shooter) -> void:
	shooter = from_shooter
	direction = dir.normalized()

	global_position = origin
	look_at(origin + direction, Vector3.UP)

	linear_velocity = direction * speed

	# Ignore shooter collision
	if shooter:
		add_collision_exception_with(shooter)


# -------------------------
# HIT DETECTION
# -------------------------
func _on_body_entered(body: Node) -> void:
	# Prevent self-hit
	if body == shooter:
		return

	var hit_point := global_position

	# Detect headshot
	var is_headshot := body.is_in_group("head")

	var damage_dealt := damage
	if is_headshot:
		damage_dealt *= headshot_multiplier

	# Deal damage directly
	if body.has_method("take_damage"):
		body.take_damage(damage_dealt, hit_point, shooter)

	# Deal damage to parent if hitbox is child
	elif body.get_parent() and body.get_parent().has_method("take_damage"):
		body.get_parent().take_damage(damage_dealt, hit_point, shooter)

	# Spawn impact VFX
	if impact_scene:
		var impact = impact_scene.instantiate()
		get_tree().root.add_child(impact)
		impact.global_position = hit_point

	# Destroy bullet
	queue_free()


# -------------------------
# PROCESS
# -------------------------
func _process(delta: float) -> void:
	# Rotate bullet toward velocity direction for realism
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity.normalized(), Vector3.UP)
