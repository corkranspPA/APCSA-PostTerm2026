extends Control

## Attach to the HUD's root Control node (same node tree as before):
##
## HUD (Control, this script)
## ├── StaminaGauge (TextureProgressBar) -- green zone
## ├── ShieldGauge (TextureProgressBar)  -- teal zone
## ├── HealthGauge (TextureProgressBar)  -- red zone
## └── Outline (TextureRect)             -- black linework, always full
##
## What's new:
##  - Bars glide toward the real value instead of snapping (and step is forced
##    to 0, because TextureProgressBar defaults to step = 1, which made a
##    10-point stamina bar move in 10 chunky jumps).
##  - Health and shield flash when they take a hit.
##  - Health and stamina pulse when low.

@export var player_path: NodePath

@export_group("Smoothing")
@export var fall_smoothing := 7.0     # how fast a bar drains toward a lower value
@export var rise_smoothing := 4.0     # how fast a bar refills toward a higher value
@export var flash_decay := 4.0        # how quickly the hit-flash fades

@export_group("Hit flash / low warnings")
@export var health_hit_tint := Color(2.0, 0.5, 0.5)
@export var shield_hit_tint := Color(1.6, 2.0, 2.4)
@export var min_drop_for_flash := 0.5        # ignore tiny drops (regen jitter)
@export var low_health_threshold := 0.3      # fraction of max where health pulses
@export var low_stamina_threshold := 0.2     # fraction of max where stamina pulses
@export var pulse_speed := 8.0

var player: CharacterBody3D

@onready var health_gauge: TextureProgressBar = get_node_or_null("HealthGauge")
@onready var shield_gauge: TextureProgressBar = get_node_or_null("ShieldGauge")
@onready var stamina_gauge: TextureProgressBar = get_node_or_null("StaminaGauge")

# Per-gauge display state: { key: { "shown": float, "last": float, "flash": float } }
var _state := {}
var _time := 0.0


func _ready() -> void:
	for g in [health_gauge, shield_gauge, stamina_gauge]:
		if g:
			g.step = 0.0        # continuous values, no whole-number snapping
			g.rounded = false

	if player_path != NodePath():
		player = get_node(player_path)
	else:
		# Wait a frame so the player has registered in the "player" group.
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")

	if player == null:
		push_warning("HUD: couldn't find a node in the 'player' group. Make sure your Player node is in that group, or set Player Path manually.")


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta

	_update_gauge(health_gauge, "health", player.health, player.max_health,
		health_hit_tint, low_health_threshold, delta)
	_update_gauge(shield_gauge, "shield", player.shield, player.max_shield,
		shield_hit_tint, 0.0, delta)
	# Stamina drains continuously while sprinting, so no hit flash (tint = white).
	_update_gauge(stamina_gauge, "stamina", player.stamina, player.max_stamina,
		Color.WHITE, low_stamina_threshold, delta)


func _update_gauge(gauge: TextureProgressBar, key: String, target: float, max_v: float,
		hit_tint: Color, low_threshold: float, delta: float) -> void:
	if gauge == null:
		return

	if not _state.has(key):
		# First frame: snap to the real value so the bar doesn't animate in from empty.
		_state[key] = {"shown": target, "last": target, "flash": 0.0}

	var s: Dictionary = _state[key]
	gauge.max_value = max_v

	# Hit detection: a sudden drop since last frame triggers the flash.
	if s.last - target >= min_drop_for_flash and hit_tint != Color.WHITE:
		s.flash = 1.0
	s.last = target

	# Exponential smoothing (frame-rate independent). Drains a bit faster than refills.
	var rate := fall_smoothing if target < s.shown else rise_smoothing
	s.shown = lerpf(s.shown, target, 1.0 - exp(-rate * delta))
	if absf(s.shown - target) < 0.005:
		s.shown = target
	gauge.value = s.shown

	# Flash fade + low-value pulse.
	s.flash = maxf(s.flash - flash_decay * delta, 0.0)
	var col := Color.WHITE.lerp(hit_tint, s.flash)

	if low_threshold > 0.0 and max_v > 0.0 and (target / max_v) <= low_threshold and target > 0.0:
		var pulse := 0.5 + 0.5 * sin(_time * pulse_speed)
		col.a = lerpf(0.55, 1.0, pulse)
	else:
		col.a = 1.0

	gauge.modulate = col
