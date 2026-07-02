extends Control

@export var gap_min := 6.0
@export var gap_max := 24.0
@export var spread_speed := 8.0
@export var ads_gap := 2.0

@onready var top: ColorRect = $Top
@onready var bottom: ColorRect = $Bottom
@onready var left: ColorRect = $Left
@onready var right: ColorRect = $Right

var player: CharacterBody3D = null
var current_gap := 6.0

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if player == null:
		return

	var target_gap := gap_min

	if Input.is_action_pressed("aim"):
		target_gap = ads_gap
	else:
		var h_vel := Vector2(player.velocity.x, player.velocity.z).length()

		if player.get("is_sprinting") == true:
			target_gap = gap_max
		elif player.get("is_crouching") == true:
			target_gap = gap_min
		elif player.get("is_sliding") == true:
			target_gap = gap_max
		elif h_vel > 0.5:
			target_gap = lerpf(gap_min, gap_max * 0.6, h_vel / 10.0)

	current_gap = lerpf(current_gap, target_gap, spread_speed * delta)

	top.position = Vector2(-1, -current_gap - top.size.y)
	bottom.position = Vector2(-1, current_gap)
	left.position = Vector2(-current_gap - left.size.x, -1)
	right.position = Vector2(current_gap, -1)
