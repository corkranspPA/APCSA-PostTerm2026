extends Node3D
## Scatters copies of your enemy around the endless world.
## Add this to a Node3D anywhere in the scene (main.tscn) and attach the script. It finds the player, the terrain
## (your ground_chunks node) and your enemy scene by itself.
##
## - Copies appear at random spots around the player (never right next to you), on the ground, not on steep slopes,
##   and never inside a tree (it finds the sakura_trees.gd node by itself; with no trees in the scene this is skipped).
## - New copies are held invisible and frozen for a moment until the ground under them has loaded, so they never fall through.
## - Copies that end up far behind you are removed and new ones appear somewhere else ahead, so enemies are
##   always scattered around wherever you walk. Dead enemies are left alone so they can finish their death and respawn
##   the way your enemy script already does.
## - Your original enemy stays where it is and keeps working as before.

# -------------------------
# SETUP
# -------------------------
@export var enemy_scene: PackedScene                   # leave empty to use the path below (or the scene your existing enemy came from)
@export var enemy_scene_path := "res://Enemy.tscn"
@export var terrain: Node                              # the ground_chunks node (found automatically)
@export var player: Node3D                             # found automatically (group "player")
@export var trees: Node                                # the sakura_trees node (found automatically, optional)

# -------------------------
# HOW MANY AND WHERE
# -------------------------
@export var max_enemies := 20                          # copies alive at once (your original isn't counted)
@export var min_spawn_distance := 50.0                 # never closer to you than this (metres)
@export var max_spawn_distance := 350.0                # never further from you than this
@export var despawn_distance := 500.0                  # copies further than this from you are removed and re-spawned closer
@export var despawn_after_unseen := 30.0               # a copy is removed this many seconds after the ground under it has disappeared from view
@export var behind_keep_range := 80.0                  # ...unless it is behind you and closer than this (metres), so enemies chasing you from behind aren't lost
@export var spawn_interval := 1.5                      # seconds between new copies while below the maximum
@export var max_slope_degrees := 38.0                  # won't spawn on ground steeper than this (raised so mountain slopes work)
@export var spawn_height_offset := 1.5                 # starts this far above the ground
@export var tree_clearance := 2.0                      # stays at least this many metres away from tree trunks

var _spawned: Array[Node3D] = []
var _pending: Array = []                               # copies waiting for their ground: { "node": Node3D, "age": float }
var _timer := 0.0
var _unseen_timer := 0.0
var _ready_done := false


func _ready() -> void:
	# Wait two frames so the player, the terrain and the first ground chunks exist.
	await get_tree().process_frame
	await get_tree().process_frame
	_find_things()
	if enemy_scene == null or terrain == null or player == null:
		return
	_ready_done = true
	for i in max_enemies:                               # first scatter all at once
		_try_spawn()


func _find_things() -> void:
	var root := get_tree().current_scene
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_error("enemy_spawner: couldn't find the player. Put the player in group 'player'.")

	if terrain == null and root:
		for n in root.find_children("*", "Node3D", true, false):
			if n.has_method("height_at") and n.has_method("has_collision_at"):
				terrain = n
				break
	if terrain == null:
		push_error("enemy_spawner: couldn't find the terrain node (the one with ground_chunks.gd). Drag it into Terrain.")

	# The tree scatter node (optional)
	if trees == null and root:
		for n in root.find_children("*", "Node3D", true, false):
			if n.has_method("is_blocked_at"):
				trees = n
				break

	if enemy_scene == null:
		if ResourceLoader.exists(enemy_scene_path):
			enemy_scene = load(enemy_scene_path) as PackedScene
		else:
			var existing := get_tree().get_first_node_in_group("enemy")
			if existing and existing.scene_file_path != "":
				enemy_scene = load(existing.scene_file_path) as PackedScene
	if enemy_scene == null:
		push_error("enemy_spawner: couldn't find your enemy scene. Drag Enemy.tscn into Enemy Scene.")


func _process(delta: float) -> void:
	if not _ready_done or not is_instance_valid(player):
		return

	# Let a new copy start once the ground under it has loaded (or after 15 s regardless).
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		var e = p["node"]
		if not is_instance_valid(e):
			_pending.remove_at(i)
			continue
		p["age"] = float(p["age"]) + delta
		if terrain.has_collision_at((e as Node3D).global_position) or float(p["age"]) > 15.0:
			(e as Node3D).visible = true
			(e as Node3D).set_physics_process(true)
			(e as Node3D).set_meta("active", true)
			_pending.remove_at(i)

	_unseen_timer += delta
	if _unseen_timer >= 0.5:
		_check_unseen(_unseen_timer)
		_unseen_timer = 0.0

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_remove_far_ones()
		_try_spawn()


## Counts how long each copy has been standing on ground that is no longer drawn. After despawn_after_unseen seconds
## it is removed (a new one appears somewhere else later). The count restarts whenever its ground is drawn again, and
## stays at zero while the enemy is behind you and within behind_keep_range. Dead enemies are never touched.
func _check_unseen(dt: float) -> void:
	var fwd := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam:
		fwd = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()

	for i in range(_spawned.size() - 1, -1, -1):
		var e := _spawned[i]
		if not is_instance_valid(e):
			_spawned.remove_at(i)
			continue
		if not e.has_meta("active") or e.get("is_dead") == true:
			continue                                    # still waiting for its ground, or already dying
		var pos := e.global_position
		if terrain.is_drawn_at(pos):
			e.set_meta("unseen", 0.0)
			continue
		var to := pos - player.global_position
		to.y = 0.0
		if fwd != Vector3.ZERO and to.length() > 0.01 and to.length() <= behind_keep_range and fwd.dot(to.normalized()) < 0.0:
			e.set_meta("unseen", 0.0)                   # behind you, within range: keep it
			continue
		var t := float(e.get_meta("unseen", 0.0)) + dt
		if t >= despawn_after_unseen:
			e.queue_free()
			_spawned.remove_at(i)
		else:
			e.set_meta("unseen", t)


func _remove_far_ones() -> void:
	for i in range(_spawned.size() - 1, -1, -1):
		var e := _spawned[i]
		if not is_instance_valid(e):
			_spawned.remove_at(i)
		elif e.get("is_dead") != true and e.global_position.distance_to(player.global_position) > despawn_distance:
			e.queue_free()
			_spawned.remove_at(i)


func _try_spawn() -> void:
	if _spawned.size() >= max_enemies:
		return
	var spot = _pick_spot()
	if spot == null:
		return
	var e := enemy_scene.instantiate() as Node3D
	if e == null:
		return
	e.visible = false
	add_child(e)
	e.global_position = spot
	e.rotation.y = randf() * TAU
	e.set_physics_process(false)                        # frozen until its ground exists
	_spawned.append(e)
	_pending.append({ "node": e, "age": 0.0 })


## A random spot on the ground between min and max distance from the player, on gentle slope and not inside a tree.
## Null if none was found.
func _pick_spot() -> Variant:
	var centre := player.global_position
	var lo := min_spawn_distance * min_spawn_distance
	var hi := max_spawn_distance * max_spawn_distance
	for attempt in 12:
		var ang := randf() * TAU
		var dist := sqrt(randf_range(lo, hi))           # square-root keeps them evenly spread over the area
		var x := centre.x + cos(ang) * dist
		var z := centre.z + sin(ang) * dist
		var sx: float = terrain.height_at(x + 2.0, z) - terrain.height_at(x - 2.0, z)
		var sz: float = terrain.height_at(x, z + 2.0) - terrain.height_at(x, z - 2.0)
		var slope := rad_to_deg(atan(sqrt(sx * sx + sz * sz) / 4.0))
		if slope > max_slope_degrees:
			continue
		var y := float(terrain.height_at(x, z)) + spawn_height_offset
		# Never inside a tree
		if trees != null and is_instance_valid(trees) and trees.is_blocked_at(Vector3(x, y, z), tree_clearance):
			continue
		return Vector3(x, y, z)
	return null
