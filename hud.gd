extends Control

## Attach to the HUD's root Control node (already wired in hud.tscn).
##
## Your icon is split into 4 transparent layers that stack perfectly back
## into the original sprite: the green (stamina), teal (shield), and dark
## red (health) zones each sit on their own TextureProgressBar, and a
## black-outline layer sits on top of all three as a static frame. Each
## TextureProgressBar's "texture_progress" is the full-color zone and its
## "texture_under" is a dim/desaturated version of the same zone — so as a
## stat drops, that part of the icon visually fades from full color down to
## a faint ghost instead of just vanishing.
##
## HUD (Control, this script)
## ├── StaminaGauge (TextureProgressBar) -- green zone
## ├── ShieldGauge (TextureProgressBar)  -- teal zone
## ├── HealthGauge (TextureProgressBar)  -- red zone
## └── Outline (TextureRect)             -- black linework, always full

## Optional manual override — leave empty and the HUD will just find the
## player automatically via the "player" group (the same group enemy.gd
## already uses to find the player). Only set this if you have more than
## one CharacterBody3D in the "player" group for some reason.
@export var player_path: NodePath
var player: CharacterBody3D

@onready var health_gauge: TextureProgressBar = get_node_or_null("HealthGauge")
@onready var shield_gauge: TextureProgressBar = get_node_or_null("ShieldGauge")
@onready var stamina_gauge: TextureProgressBar = get_node_or_null("StaminaGauge")


func _ready() -> void:
	print("HUD: gauges found -> health=", health_gauge, " shield=", shield_gauge, " stamina=", stamina_gauge)

	if player_path != NodePath():
		player = get_node(player_path)
	else:
		# Wait one frame so the player has had a chance to enter the tree
		# and register itself in the "player" group first.
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")

	if player == null:
		push_warning("HUD: couldn't find a node in the 'player' group. Make sure your Player node is in that group, or set Player Path manually.")
		return

	print("HUD: player found -> ", player, " | has stats_changed signal: ", player.has_signal("stats_changed"))

	# If the player happens to have a stats_changed signal, still hook it up
	# for instant updates — but we no longer depend on it existing.
	if player.has_signal("stats_changed"):
		player.stats_changed.connect(_on_stats_changed)

	_on_stats_changed()


func _process(_delta: float) -> void:
	# Poll every frame instead of relying solely on a signal, so the bars
	# update no matter how player.gd manages its stats.
	_on_stats_changed()


func _on_stats_changed() -> void:
	if player == null:
		return

	if health_gauge and "health" in player and "max_health" in player:
		health_gauge.max_value = player.max_health
		health_gauge.value = player.health

	if shield_gauge and "shield" in player and "max_shield" in player:
		shield_gauge.max_value = player.max_shield
		shield_gauge.value = player.shield

	if stamina_gauge and "stamina" in player and "max_stamina" in player:
		stamina_gauge.max_value = player.max_stamina
		stamina_gauge.value = player.stamina

	# One-time-per-second debug print so we can see live values without spamming.
	if Engine.get_frames_drawn() % 60 == 0:
		var hg_value_str: String = str(health_gauge.value) if health_gauge else "NO NODE"
		print("HUD update -> health=", player.health, "/", player.max_health,
			" shield=", player.shield, "/", player.max_shield,
			" stamina=", player.stamina, "/", player.max_stamina,
			" | health_gauge.value=", hg_value_str)
