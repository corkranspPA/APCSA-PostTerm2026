extends Node3D
## Scatters lots of sakura trees over the endless world, cheaply.
##
## SETUP
##  1. Put sakura_lod.glb, sakura_bark.jpg and sakura_blossom.png in your project (res://), next to Enemy.tscn.
##  2. Add a Node3D anywhere in your main scene (e.g. next to the terrain), at the world origin, and attach this script.
##     It finds the terrain (the node with ground_chunks.gd) and the player by itself.
##  3. Use the new enemy_spawner.gd: it finds this node and never spawns enemies inside trees.
##
## HOW IT STAYS FAST
##  - The tree is NOT your original model (that one has about 400,000 triangles). sakura_lod.glb holds three cut-down
##    versions: near (about 9k triangles), mid (about 2k) and far (about 400). The blossom is made of cards instead of
##    400,000 separate petals.
##  - Trees are grouped into small cells. Each cell draws all its trees with ONE MultiMesh per level of detail, and the
##    engine switches between the levels by distance, so far-away trees are cheap and nothing is drawn beyond draw_distance.
##  - Where the trees stand is worked out from the terrain seed alone (no saving needed): the same seed gives the same
##    forest, and a new random world gets a new forest. Placement follows the terrain's height_at().
##  - At most one cell is built per frame, so walking never causes a hitch.
##  - Trunk collision only exists close to you (and close to enemies), and is removed again when you move away.

# -------------------------
# FILES
# -------------------------
@export var tree_scene_path := "res://sakura_lod.glb"
@export var bark_texture_path := "res://sakura_bark.jpg"
@export var blossom_texture_path := "res://sakura_blossom.png"
@export var terrain: Node                              # the ground_chunks node (found automatically)
@export var player: Node3D                             # found automatically (group "player")
@export var trees_enabled := true

# -------------------------
# HOW MANY AND WHERE
# -------------------------
@export_group("Forest")
@export var spacing := 8.0                             # metres between possible tree spots (smaller = more trees, but costs more)
@export var grid_per_cell := 4                         # tree spots per cell side (cell size = spacing x this = 32 m)
@export_range(0.0, 0.9) var jitter := 0.6              # how far each tree can wander from its spot (0.6 keeps them at least 3 m apart)
@export var forest_wavelength := 260.0                 # size of the groves and clearings (metres)
@export_range(-1.0, 1.0) var forest_low := -0.15       # noise value where the grove edge begins
@export_range(-1.0, 1.0) var forest_high := 0.35       # noise value where the grove is fully dense
@export_range(0.0, 1.0) var max_density := 0.75        # chance a tree spot holds a tree inside a grove (raise for a thicker forest)
@export_range(0.0, 1.0) var min_density := 0.04        # chance in clearings (lone trees)
@export var scale_min := 0.75
@export var scale_max := 1.3
@export var max_slope_degrees := 38.0                  # no trees on steeper ground (raised so mountain slopes get trees)
@export var max_tree_height := 90.0                    # no trees above this height (mountain tops)
@export var tree_line_start := 45.0                    # above this height the trees thin out, reaching none at max_tree_height
@export var clear_origin_radius := 20.0                # no trees this close to the world centre (where you start)

# -------------------------
# DISTANCES (performance)
# -------------------------
@export_group("Distances")
@export var draw_distance := 280.0                     # trees further than this are not drawn at all
@export var lod0_distance := 55.0                      # full-detail trees up to here
@export var lod1_distance := 160.0                     # medium-detail trees up to here, then the cheapest version
@export var lod_overlap := 12.0                        # both levels show for this many metres when switching (hides the pop)
@export var lod0_casts_shadows := true                 # near trees cast shadows
@export var lod1_casts_shadows := false                # medium trees cast shadows (nicer, but costs more)
@export var cells_per_frame := 1                       # new cells built per frame (raise for faster filling, lower if it stutters)
@export var update_interval := 0.25                    # how often (seconds) the tree area is re-checked

# -------------------------
# COLLISION (trunks)
# -------------------------
@export_group("Collision")
@export var collision_enabled := true
@export var collision_distance := 70.0                 # trunks are solid within this distance of you
@export var enemy_collision_range := 160.0             # ... and around enemies that are within this distance of you
@export var trunk_radius := 0.55                       # trunk collision radius (metres, at scale 1)
@export var trunk_height := 6.0                        # trunk collision height (metres, at scale 1)

# -------------------------
# LOOK
# -------------------------
@export_group("Look")
@export var blossom_tint := Color(1.0, 1.0, 1.0)       # multiplies the blossom colour (try a deeper pink)
@export var bark_tint := Color(0.78, 0.72, 0.7)
@export var bark_tile_meters := 2.0                    # how many metres one copy of the bark texture covers

var cell_size := 32.0

var _seed := 0
var _n_forest: FastNoiseLite
var _logic_ready := false
var _ready_done := false

var _cells := {}                                       # Vector2i -> { "n", "xf", "scl", "p2" } (where the trees are; cheap)
var _built := {}                                       # Vector2i -> Node3D holding the cell's MultiMeshes
var _bodies := {}                                      # Vector2i -> StaticBody3D with the trunk collision
var _build_queue: Array[Vector2i] = []
var _free_queue: Array[Vector2i] = []
var _body_queue: Array[Vector2i] = []
var _lod_mask := {}                                    # Vector2i -> which levels are built for the cell (1 = near, 2 = mid, 4 = far)
var _upgrade_queue: Array[Vector2i] = []               # built cells that now need a nearer level added
var _body_keep := {}                                   # cells whose collision should exist (with a little extra, so it doesn't flicker)
var _timer := 0.0

var _meshes: Array[Mesh] = []
var _bark_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D


func _ready() -> void:
	if not trees_enabled:
		return
	# Wait two frames so the player and the terrain exist.
	await get_tree().process_frame
	await get_tree().process_frame
	if not _find_things():
		return
	if not _load_resources():
		return
	if not _ensure_logic():
		push_error("sakura_trees: the terrain isn't ready (no seed found).")
		return
	_ready_done = true
	_update(_focus())
	# Fill the area right around you at once, so you never start in an empty field; the rest streams in.
	var f := _focus()
	while _build_queue.size() > 0 and _dist2(_build_queue.back(), f) <= 100.0 * 100.0:
		var key: Vector2i = _build_queue.pop_back()
		if not _built.has(key):
			_build_cell(key)
	while _body_queue.size() > 0:
		var bk: Vector2i = _body_queue.pop_back()
		if not _bodies.has(bk) and _body_keep.has(bk):
			_build_body(bk)


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		_update(_focus())

	var n := 0
	while n < cells_per_frame and _build_queue.size() > 0:
		var key: Vector2i = _build_queue.pop_back()
		if not _built.has(key):
			_build_cell(key)
		n += 1

	var up := 0
	while up < 2 and _upgrade_queue.size() > 0:
		var uk: Vector2i = _upgrade_queue.pop_back()
		if _built.has(uk):
			var missing := _lods_needed(uk, _focus()) & ~int(_lod_mask.get(uk, 0))
			if missing != 0:
				_add_lods(uk, missing)
		up += 1

	var f := 0
	while f < 3 and _free_queue.size() > 0:
		var fk: Vector2i = _free_queue.pop_back()
		_free_cell(fk)
		f += 1

	if _body_queue.size() > 0:
		var bk: Vector2i = _body_queue.pop_back()
		if not _bodies.has(bk) and _body_keep.has(bk):
			_build_body(bk)


# -------------------------
# SETUP
# -------------------------
func _find_things() -> bool:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_error("sakura_trees: couldn't find the player. Put the player in group 'player'.")
		return false
	if _find_terrain() == false:
		push_error("sakura_trees: couldn't find the terrain node (the one with ground_chunks.gd). Drag it into Terrain.")
		return false
	return true


func _find_terrain() -> bool:
	if terrain != null:
		return true
	var root := get_tree().current_scene
	if root:
		for n in root.find_children("*", "Node3D", true, false):
			if n.has_method("height_at") and n.has_method("has_collision_at"):
				terrain = n
				return true
	return false


func _load_resources() -> bool:
	var ps := load(tree_scene_path) as PackedScene
	if ps == null:
		push_error("sakura_trees: couldn't load %s. Put sakura_lod.glb in your project." % tree_scene_path)
		return false
	var bark_tex := load(bark_texture_path) as Texture2D
	var leaf_tex := load(blossom_texture_path) as Texture2D
	if bark_tex == null or leaf_tex == null:
		push_error("sakura_trees: couldn't load the bark or blossom texture (%s, %s)." % [bark_texture_path, blossom_texture_path])
		return false

	_bark_mat = StandardMaterial3D.new()
	_bark_mat.albedo_texture = bark_tex
	_bark_mat.albedo_color = bark_tint
	_bark_mat.roughness = 0.95
	_bark_mat.uv1_triplanar = true                    # the bark is painted onto the shape from 3 sides, so it never stretches
	_bark_mat.uv1_scale = Vector3.ONE / maxf(bark_tile_meters, 0.01)
	_bark_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_texture = leaf_tex
	_leaf_mat.albedo_color = blossom_tint
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.35
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 0.85
	_leaf_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_leaf_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var inst := ps.instantiate()
	_meshes.clear()
	for i in 3:
		var mi := inst.find_child("LOD%d" % i, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			push_error("sakura_trees: %s has no mesh called LOD%d." % [tree_scene_path, i])
			inst.free()
			return false
		var m := mi.mesh.duplicate() as Mesh
		m.surface_set_material(0, _bark_mat)           # surface 0 = wood
		m.surface_set_material(1, _leaf_mat)           # surface 1 = blossom cards
		_meshes.append(m)
	inst.free()
	return true


## Works out the seed and noise. Can be called at any time (enemy_spawner uses is_blocked_at before the first frame).
func _ensure_logic() -> bool:
	if _logic_ready:
		return true
	if not _find_terrain():
		return false
	var s := int(terrain.get("_seed"))
	if s == 0:
		return false                                   # terrain hasn't picked its seed yet
	_seed = s
	cell_size = spacing * float(maxi(grid_per_cell, 1))
	_n_forest = FastNoiseLite.new()
	_n_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_forest.seed = _seed + 77
	_n_forest.frequency = 1.0 / maxf(forest_wavelength, 1.0)
	_n_forest.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_forest.fractal_octaves = 2
	_logic_ready = true
	return true


# -------------------------
# WHERE THE TREES ARE (decided by the seed alone)
# -------------------------
func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


func _cell_centre(key: Vector2i) -> Vector3:
	return Vector3((key.x + 0.5) * cell_size, 0.0, (key.y + 0.5) * cell_size)


func _dist2(key: Vector2i, pos: Vector3) -> float:
	var c := _cell_centre(key)
	var dx := c.x - pos.x
	var dz := c.z - pos.z
	return dx * dx + dz * dz


func _get_cell(key: Vector2i) -> Dictionary:
	if _cells.has(key):
		return _cells[key]
	var xf := []
	var scl := PackedFloat32Array()
	var p2 := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	var gn := maxi(grid_per_cell, 1)
	for gi in gn:
		for gj in gn:
			var ix := key.x * gn + gi
			var iz := key.y * gn + gj
			rng.seed = hash(Vector3i(_seed + 911, ix, iz))
			var keep_r := rng.randf()
			var jx := rng.randf_range(-1.0, 1.0)
			var jz := rng.randf_range(-1.0, 1.0)
			var yaw := rng.randf() * TAU
			var sr := rng.randf()
			var hr := rng.randf_range(0.92, 1.1)
			var x := (float(ix) + 0.5 + jx * jitter * 0.5) * spacing
			var z := (float(iz) + 0.5 + jz * jitter * 0.5) * spacing

			# Cheap checks first, so the terrain is only asked about trees that might really exist.
			var dens := lerpf(min_density, max_density, smoothstep(forest_low, forest_high, _n_forest.get_noise_2d(x, z)))
			if keep_r > dens:
				continue
			if x * x + z * z < clear_origin_radius * clear_origin_radius:
				continue
			var h: float = terrain.height_at(x, z)
			if h > max_tree_height:
				continue
			# Thinner and thinner towards the top of a mountain (a tree line) instead of a hard cut-off.
			if keep_r > dens * (1.0 - smoothstep(tree_line_start, max_tree_height, h)):
				continue
			var sx: float = terrain.height_at(x + 2.0, z) - terrain.height_at(x - 2.0, z)
			var sz: float = terrain.height_at(x, z + 2.0) - terrain.height_at(x, z - 2.0)
			var slope_t := sqrt(sx * sx + sz * sz) / 4.0              # tan of the slope angle
			if rad_to_deg(atan(slope_t)) > max_slope_degrees:
				continue

			var s := lerpf(scale_min, scale_max, sr)
			var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s * hr, s))
			var sink := 0.1 + slope_t * 0.8 * s                      # sunk a touch (more on a slope) so the roots meet the ground
			xf.append(Transform3D(basis, Vector3(x, h - sink, z)))
			scl.append(s)
			p2.append(Vector2(x, z))
	var d := { "n": xf.size(), "xf": xf, "scl": scl, "p2": p2 }
	_cells[key] = d
	return d


## True if this spot is inside a tree trunk (plus `extra` metres of clearance). Used by enemy_spawner.gd.
func is_blocked_at(pos: Vector3, extra := 0.0) -> bool:
	if not _ensure_logic():
		return false
	var reach := trunk_radius * scale_max + extra
	var here := Vector2(pos.x, pos.z)
	var base := _cell_of(pos)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(base.x + dx, base.y + dz)
			# skip neighbouring cells that are too far away to hold a tree touching this spot
			var lo_x := key.x * cell_size
			var lo_z := key.y * cell_size
			var gx := maxf(maxf(lo_x - pos.x, pos.x - (lo_x + cell_size)), 0.0)
			var gz := maxf(maxf(lo_z - pos.z, pos.z - (lo_z + cell_size)), 0.0)
			if gx * gx + gz * gz > reach * reach:
				continue
			var d := _get_cell(key)
			var p2: PackedVector2Array = d["p2"]
			var scl: PackedFloat32Array = d["scl"]
			for i in int(d["n"]):
				var r := trunk_radius * scl[i] + extra
				if p2[i].distance_squared_to(here) < r * r:
					return true
	return false


# -------------------------
# WHICH CELLS ARE NEEDED
# -------------------------
func _focus() -> Vector3:
	if player and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _update(pos: Vector3) -> void:
	var c := _cell_of(pos)

	# ---- drawing ----
	var rc := int(ceil(draw_distance / cell_size)) + 1
	var reach_draw := draw_distance + cell_size * 0.5
	var reach_free := draw_distance + cell_size * 2.0
	var list: Array[Vector2i] = []
	for dx in range(-rc, rc + 1):
		for dz in range(-rc, rc + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if _dist2(key, pos) <= reach_draw * reach_draw and not _built.has(key):
				list.append(key)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a, pos) > _dist2(b, pos))   # nearest last
	_build_queue = list

	_free_queue.clear()
	for key in _built.keys():
		if _dist2(key, pos) > reach_free * reach_free:
			_free_queue.append(key)

	# Cells you are walking towards need their nearer detail levels added (far cells only ever build the cheapest one).
	_upgrade_queue.clear()
	for key in _built.keys():
		var need := _lods_needed(key, pos)
		if (need & ~int(_lod_mask.get(key, 0))) != 0:
			_upgrade_queue.append(key)
	_upgrade_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a, pos) > _dist2(b, pos))

	# ---- collision ----
	_body_keep.clear()
	var build_set := {}
	if collision_enabled:
		var cr := int(ceil(collision_distance / cell_size)) + 1
		var keep_d := collision_distance + cell_size
		for dx in range(-cr, cr + 1):
			for dz in range(-cr, cr + 1):
				var key := Vector2i(c.x + dx, c.y + dz)
				var d2 := _dist2(key, pos)
				if d2 <= keep_d * keep_d:
					_body_keep[key] = true
				if d2 <= collision_distance * collision_distance:
					build_set[key] = true
		# Around enemies too, so they bump into trunks like you do.
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Node3D:
				var ep := (e as Node3D).global_position
				if Vector2(ep.x - pos.x, ep.z - pos.z).length() > enemy_collision_range:
					continue
				var ec := _cell_of(ep)
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var key := Vector2i(ec.x + dx, ec.y + dz)
						_body_keep[key] = true
						build_set[key] = true

	var blist: Array[Vector2i] = []
	for key in build_set.keys():
		if not _bodies.has(key):
			blist.append(key)
	blist.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a, pos) > _dist2(b, pos))
	_body_queue = blist

	for key in _bodies.keys():
		if not _body_keep.has(key):
			_free_body(key)

	# Keep the "where are the trees" memory from growing forever while you travel.
	if _cells.size() > 1600:
		var far := (draw_distance + cell_size * 6.0)
		for key in _cells.keys():
			if not _built.has(key) and not _bodies.has(key) and _dist2(key, pos) > far * far:
				_cells.erase(key)


# -------------------------
# BUILDING / REMOVING A CELL
# -------------------------
## Which detail levels (bit 0 = near, 1 = mid, 2 = far) a cell could be showing, given how far it is from `pos`.
## The extra 30 m means you can walk a while before a level is needed and not yet built.
func _lods_needed(key: Vector2i, pos: Vector3) -> int:
	var d := sqrt(_dist2(key, pos))
	var half := cell_size * 0.7072                      # half the cell's diagonal: its trees can be this much nearer or further than its centre
	var begins := [0.0, lod0_distance - lod_overlap, lod1_distance - lod_overlap]
	var ends := [lod0_distance, lod1_distance, draw_distance + cell_size * 1.5]
	var m := 0
	for lod in 3:
		if d - half - 30.0 <= float(ends[lod]) and d + half + 30.0 >= float(begins[lod]):
			m |= 1 << lod
	return m


func _build_cell(key: Vector2i) -> void:
	var d := _get_cell(key)
	var n: int = d["n"]
	var holder := Node3D.new()
	holder.top_level = true                             # placed in world space, wherever this node sits
	add_child(holder)
	holder.global_position = _cell_centre(key)
	_built[key] = holder
	if n == 0:
		_lod_mask[key] = 7
		return
	_lod_mask[key] = 0
	_add_lods(key, _lods_needed(key, _focus()))


## Adds the MultiMeshes for the given detail levels to an already built cell.
func _add_lods(key: Vector2i, mask: int) -> void:
	var holder = _built.get(key)
	if holder == null or not is_instance_valid(holder):
		return
	var d := _get_cell(key)
	var n: int = d["n"]
	var centre := _cell_centre(key)
	var xfs: Array = d["xf"]
	var casts := [lod0_casts_shadows, lod1_casts_shadows, false]
	var begins := [0.0, lod0_distance - lod_overlap, lod1_distance - lod_overlap]
	var ends := [lod0_distance, lod1_distance, draw_distance + cell_size * 1.5]
	for lod in 3:
		if (mask & (1 << lod)) == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[lod]
		mm.instance_count = n
		for i in n:
			var t: Transform3D = xfs[i]
			t.origin -= centre
			mm.set_instance_transform(i, t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts[lod] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.visibility_range_begin = begins[lod]
		mmi.visibility_range_end = ends[lod]
		(holder as Node3D).add_child(mmi)
	_lod_mask[key] = int(_lod_mask.get(key, 0)) | mask


func _free_cell(key: Vector2i) -> void:
	var h = _built.get(key)
	if h != null and is_instance_valid(h):
		(h as Node).queue_free()
	_built.erase(key)
	_lod_mask.erase(key)


func _build_body(key: Vector2i) -> void:
	var d := _get_cell(key)
	var n: int = d["n"]
	if n == 0:
		_bodies[key] = null
		return
	var body := StaticBody3D.new()
	body.top_level = true
	add_child(body)
	var centre := _cell_centre(key)
	body.global_position = centre
	var xfs: Array = d["xf"]
	var scl: PackedFloat32Array = d["scl"]
	for i in n:
		var s := scl[i]
		var sh := CylinderShape3D.new()
		sh.radius = trunk_radius * s
		sh.height = trunk_height * s
		var cs := CollisionShape3D.new()
		cs.shape = sh
		var o: Vector3 = (xfs[i] as Transform3D).origin
		cs.position = Vector3(o.x - centre.x, o.y + sh.height * 0.5, o.z - centre.z)
		body.add_child(cs)
	_bodies[key] = body


func _free_body(key: Vector2i) -> void:
	var b = _bodies.get(key)
	if b != null and is_instance_valid(b):
		(b as Node).queue_free()
	_bodies.erase(key)
