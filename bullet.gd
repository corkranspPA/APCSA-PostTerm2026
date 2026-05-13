extends RigidBody3D
class_name Bullet

# -------------------------
# STATS
# -------------------------
@export var speed: float = 80.0
@export var damage: float = 25.0
@export var headshot_multiplier: float = 2.0
@export var gravity_scale_value: float = 0.08
@export var lifetime: float = 3.0
@export var impact_scene: PackedScene
@export var arm_distance: float = 1.5

var shooter: Node = null
var direction: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO
var _started: bool = false

# -------------------------
# READY
# -------------------------
func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4

	gravity_scale = gravity_scale_value
	sleeping = false
	freeze = false

	if shooter:
		add_collision_exception_with(shooter)

	body_entered.connect(_on_body_entered)

	# delete after lifetime
	await get_tree().create_timer(lifetime).timeout

	if is_instance_valid(self):
		queue_free()

# -------------------------
# LAUNCH
# -------------------------
func launch(origin: Vector3, dir: Vector3, from_shooter: Node) -> void:
	shooter = from_shooter
	direction = dir.normalized()
	_origin = origin

	# IMPORTANT:
	# use position instead of global_position
	# before entering tree
	position = origin

# -------------------------
# PHYSICS
# -------------------------
func _physics_process(_delta: float) -> void:

	# Apply velocity ONE time
	if not _started:
		_started = true

		linear_velocity = direction * speed

	# Rotate toward velocity
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity.normalized(), Vector3.UP)

# -------------------------
# COLLISION
# -------------------------
func _on_body_entered(body: Node) -> void:

	if body == shooter:
		return

	# prevent self-hit at muzzle
	if global_position.distance_to(_origin) < arm_distance:
		return

	var hit_point: Vector3 = global_position

	var dmg: float = damage

	if body.is_in_group("head"):
		dmg *= headshot_multiplier

	if body.has_method("take_damage"):
		body.take_damage(dmg, hit_point, shooter)

	elif body.get_parent() and body.get_parent().has_method("take_damage"):
		body.get_parent().take_damage(dmg, hit_point, shooter)

	# impact effect
	if impact_scene:
		var impact = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = hit_point

	queue_free()
