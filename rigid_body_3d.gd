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

var shooter: Node = null
var direction: Vector3 = Vector3.ZERO

# -------------------------
# READY
# -------------------------
func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = gravity_scale_value
	# IMPORTANT: prevent physics from "fighting" initial velocity
	sleeping = false
	freeze = false
	body_entered.connect(_on_body_entered)
	
	# auto delete
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

# -------------------------
# LAUNCH
# -------------------------
func launch(origin: Vector3, dir: Vector3, from_shooter: Node) -> void:
	shooter = from_shooter
	direction = dir.normalized()
	global_position = origin
	look_at(origin + direction, Vector3.UP)
	
	# force physics update cleanly
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# apply velocity AFTER placement
	linear_velocity = direction * speed
	
	# ignore shooter
	if shooter:
		add_collision_exception_with(shooter)

# -------------------------
# COLLISION
# -------------------------
func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	
	var hit_point: Vector3 = global_position
	var is_headshot: bool = body.is_in_group("head")
	var dmg: float = damage
	if is_headshot:
		dmg *= headshot_multiplier
	
	if body.has_method("take_damage"):
		body.take_damage(dmg, hit_point, shooter)
	elif body.get_parent() and body.get_parent().has_method("take_damage"):
		body.get_parent().take_damage(dmg, hit_point, shooter)
	
	if impact_scene:
		var impact = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = hit_point
	
	queue_free()

# -------------------------
# DEBUG VISUAL DIRECTION
# -------------------------
func _process(delta: float) -> void:
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity.normalized(), Vector3.UP)
