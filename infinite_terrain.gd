extends Node3D
## Distant terrain ("see forever" like the Distant Horizons mod). Draws the ground far beyond the normal chunks as a few big,
## very cheap, low-detail tiles, so mountains and hills are visible on the horizon without loading those chunks.
##
## SETUP
##  1. Save this as far_terrain.gd in your project.
##  2. Add a Node3D to your main scene (anywhere, e.g. next to the terrain node) and attach this script.
##     It finds the terrain (the node with the chunk script) and the player by itself.
##  3. Nothing else in your project needs to change. The normal chunks (collision, near detail) are untouched.
##
## HOW IT STAYS FAST
##  - Rings of tiles: each ring is twice as far out, and its tiles twice as big, as the one before, but every tile has the
##    same small number of triangles. So 4 km of view costs about the same as one small town of chunks.
##  - Tiles are worked out on background threads (the main thread only makes the mesh, one tile per frame).
##  - No collision, no shadows, one draw call per tile, and the engine skips tiles outside the camera's view.
##  - Tiles are sunk slightly below the real ground, so where they overlap the normal chunks the chunks always win
##    (no flickering), and where a chunk isn't drawn (behind you) the far tile quietly fills the hole.

@export var terrain: Node                              # found automatically (the node with height_at and has_collision_at)
@export var player: Node3D                             # found automatically (group "player")
@export var far_enabled := true
@export var far_distance := 4000.0                     # how far you can see ground (metres). Each doubling adds one ring of tiles.
@export var base_tile_size := 256.0                    # size of the nearest ring's tiles (metres). Each ring out doubles it.
@export var tile_resolution := 32                      # grid cells per tile side (the nearest ring then has 8 m cells; higher = smoother, slower)
@export var ring_start := 0.0                          # where the far ground begins. 0 = automatic, a bit inside the normal render distance
@export var max_jobs := 2                              # tiles being worked out on threads at once
@export var installs_per_frame := 1                    # finished tiles turned into meshes per frame
@export var update_interval := 0.5                     # how often (seconds) the tile set is re-checked
@export var keep_delay := 6.0                          # seconds an unneeded tile stays before being freed
@export var sink := 1.0                                # metres the tiles are lowered so the normal chunks cover them
@export var sink_per_cell := 0.25                      # extra lowering per metre of cell size (coarse tiles are less exact)
@export var casts_shadows := false
@export var adjust_camera_far := true                  # raise the camera's far plane so the far ground isn't cut off

@export_group("Distance fog")
@export var fog_enabled := true                        # sets up fog in your WorldEnvironment so the end of the view fades out (skipped if it already has fog on)
@export var fog_strength := 1.0                        # 1 = the far edge of the view is about 95 % faded. Lower = clearer, higher = hazier
@export var fog_color := Color(0.74, 0.82, 0.92)       # haze colour
@export_range(0.0, 1.0) var fog_sky_blend := 0.5       # how much the haze takes on the sky's colour (hides the line where ground meets sky)

@export_group("Distant forest")
@export var forest_enabled := true                     # paint the groves from the sakura tree script onto the far ground
@export var forest_color := Color(0.9, 0.66, 0.75)     # colour of a far-away grove (a pink-ish blossom blend)
@export_range(0.0, 1.0) var forest_strength := 0.8     # how strongly the groves are painted (0 = none)

@export_group("Distant trees")
@export var far_trees_enabled := true                  # cheap copies of the real trees on the far ground (including mountains). Needs the tree script in the scene.
@export var far_tree_distance := 1800.0                # how far out these trees are drawn (metres)
@export var far_tree_cell := 160.0                     # trees are grouped into cells about this wide (made a whole number of tree-script cells)
@export var far_tree_scale := 1.0                      # size of the cheap trees compared to the real ones (adjust if they look too big or small)
@export_range(0.0, 0.9) var far_tree_thin := 0.4       # each far ring beyond the first shows this fraction fewer trees (cheaper; 0 = all of them)
@export var far_tree_jobs := 2                         # cells being worked out on threads at once
@export var far_tree_crown_color := Color(0.95, 0.72, 0.8)
@export var far_tree_trunk_color := Color(0.3, 0.22, 0.2)

var _ready_done := false
var _radii := PackedFloat32Array()                     # ring boundaries: ring i covers _radii[i] .. _radii[i+1]
var _levels := 0
var _indices := PackedInt32Array()
var _tiles := {}                                       # Vector3i(level, x, z) -> MeshInstance3D
var _last_needed := {}                                 # key -> last time (seconds) the tile was wanted
var _jobs := {}                                        # key -> worker task id
var _results := {}                                     # key -> finished tile data
var _mutex := Mutex.new()
var _queue: Array[Vector3i] = []
var _timer := 0.0
var _material: Material

var _forest_on := false
var _forest_noise: FastNoiseLite
var _forest_col := Color.WHITE
var _f_low := 0.05
var _f_high := 0.5
var _f_min := 0.05
var _f_max := 0.55
var _f_line := 45.0
var _f_maxh := 90.0
var _f_slope := 38.0
var _f_clear := 40.0

var _ft_on := false
var _ft_mesh: ArrayMesh
var _ft_trees: Node                                    # the tree script (its settings, and which of its cells are built, are read from it)
var _ft_seed := 0
var _ft_spacing := 10.0
var _ft_jitter := 0.5
var _ft_gn := 4                                        # tree spots per tree-script cell side
var _ft_real_cell := 40.0                              # size of the tree script's cells
var _ft_reach := 240.0                                 # the tree script builds cells whose centre is this close to you
var _ft_mult := 4                                      # tree-script cells per far cell side
var _ft_far_cell := 160.0
var _ft_half_diag := 113.0
var _ft_smin := 0.75
var _ft_smax := 1.3
var _ft_near_zone := 435.0                             # inside this the visible ground is the real chunks, beyond it the far tiles
var _ft_bpos := PackedVector2Array()                   # spots the tree script keeps clear (its blocker group)
var _ft_brad := PackedFloat32Array()
var _ft_cells := {}                                    # Vector3i(band, x, z) -> { "mmi", "data", "hid", "n_hid" } (or null for a cell with no trees)
var _ft_last := {}
var _ft_jobs := {}
var _ft_results := {}
var _ft_queue: Array[Vector3i] = []
var _ft_here := Vector2.ZERO
var _ft_hide_timer := 0.0


func _ready() -> void:
	if not far_enabled:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if terrain == null:
		var root := get_tree().current_scene
		if root:
			for n in root.find_children("*", "Node3D", true, false):
				if n.has_method("height_at") and n.has_method("has_collision_at"):
					terrain = n
					break
	if terrain == null:
		push_error("far_terrain: couldn't find the terrain node (the one with the chunk script).")
		return
	_material = terrain.get("_material") as Material

	var r0 := ring_start
	if r0 <= 0.0:
		r0 = float(terrain.get("render_distance")) * float(terrain.get("chunk_size")) * 0.8
	_radii = PackedFloat32Array([r0])
	while _radii[_radii.size() - 1] < far_distance:
		_radii.append(_radii[_radii.size() - 1] * 2.0)
	_levels = _radii.size() - 1
	if _levels < 1:
		push_warning("far_terrain: far_distance is smaller than the normal render distance, nothing to draw.")
		return

	_build_indices()
	_setup_forest()
	_setup_fog()
	_ready_done = true
	_update(_focus())


func _exit_tree() -> void:
	for key in _jobs.keys():
		WorkerThreadPool.wait_for_task_completion(int(_jobs[key]))
	_jobs.clear()
	for key in _ft_jobs.keys():
		WorkerThreadPool.wait_for_task_completion(int(_ft_jobs[key]))
	_ft_jobs.clear()


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		_update(_focus())
	_dispatch()
	_collect()
	if _ft_on:
		_ft_dispatch()
		_ft_collect()
		_ft_hide_timer -= delta
		if _ft_hide_timer <= 0.0:
			_ft_hide_timer = 0.2
			var fp := _focus()
			_ft_refresh_hidden(Vector2(fp.x, fp.z))


func _focus() -> Vector3:
	if player and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _tile_size(level: int) -> float:
	return base_tile_size * float(1 << level)


func _tile_centre(key: Vector3i) -> Vector2:
	var s := _tile_size(key.x)
	return Vector2((key.y + 0.5) * s, (key.z + 0.5) * s)


# -------------------------
# WHICH TILES ARE NEEDED
# -------------------------
func _update(pos: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var here := Vector2(pos.x, pos.z)

	if adjust_camera_far:
		var cam := get_viewport().get_camera_3d()
		var want_far := (far_distance + _tile_size(_levels - 1)) * 1.2
		if cam and cam.far < want_far:
			cam.far = want_far

	var needed := {}
	for lvl in _levels:
		var s := _tile_size(lvl)
		# Tiles reach half a tile inward, so there is never a gap between two rings.
		var r_in := _radii[lvl] - s * 0.5
		var r_out := _radii[lvl + 1]
		var span := int(ceil(r_out / s)) + 1
		var ci := Vector2i(floori(pos.x / s), floori(pos.z / s))
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				var ix := ci.x + dx
				var iz := ci.y + dz
				var d := Vector2((ix + 0.5) * s, (iz + 0.5) * s).distance_to(here)
				if d < r_in or d > r_out:
					continue
				needed[Vector3i(lvl, ix, iz)] = true

	_queue.clear()
	for key in needed.keys():
		_last_needed[key] = now
		if not _tiles.has(key) and not _jobs.has(key):
			_queue.append(key)
	_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _tile_centre(a).distance_squared_to(here) > _tile_centre(b).distance_squared_to(here))   # nearest last

	for key in _tiles.keys():
		if not needed.has(key) and now - float(_last_needed.get(key, -1e9)) > keep_delay:
			(_tiles[key] as Node).queue_free()
			_tiles.erase(key)
			_last_needed.erase(key)

	if _ft_on:
		_update_far_trees(here, now)


# -------------------------
# WORKER THREADS
# -------------------------
func _dispatch() -> void:
	while _jobs.size() < max_jobs and _queue.size() > 0:
		var key: Vector3i = _queue.pop_back()
		if _tiles.has(key) or _jobs.has(key):
			continue
		_jobs[key] = WorkerThreadPool.add_task(_job.bind(key), false, "far terrain tile")


func _job(key: Vector3i) -> void:
	var data := _generate(key)
	_mutex.lock()
	_results[key] = data
	_mutex.unlock()


func _collect() -> void:
	var done := 0
	var now := Time.get_ticks_msec() / 1000.0
	for key in _jobs.keys():
		if done >= installs_per_frame:
			return
		var id := int(_jobs[key])
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		_jobs.erase(key)
		_mutex.lock()
		var data = _results.get(key)
		_results.erase(key)
		_mutex.unlock()
		if data == null or _tiles.has(key):
			continue
		if now - float(_last_needed.get(key, -1e9)) > keep_delay:
			continue                                    # you've moved on, not needed any more
		_install(key, data)
		done += 1


# -------------------------
# BUILDING A TILE (the worker part only reads, it never touches the scene)
# -------------------------
func _generate(key: Vector3i) -> Dictionary:
	var s := _tile_size(key.x)
	var res := maxi(tile_resolution, 2)
	var n := res + 1
	var cell := s / float(res)
	var half := s * 0.5
	var c := _tile_centre(key)
	var lower := sink + cell * sink_per_cell
	var tile_m := float(terrain.get("grass_tile_meters"))
	# The nearest ring (mostly under the real chunks) gets no forest paint, the next gets half, the rest full. This keeps the
	# painted groves from starting right next to the zone where the real trees stop.
	var forest_level := 0.0
	if _forest_on:
		forest_level = forest_strength * minf(1.0, float(key.x) * 0.5)

	# Heights on a grid one step bigger on every side, so the normals at the tile edge are right.
	var pw := n + 2
	var hp := PackedFloat32Array()
	hp.resize(pw * pw)
	for iz in pw:
		for ix in pw:
			hp[iz * pw + ix] = terrain.height_at(c.x - half + (ix - 1) * cell, c.y - half + (iz - 1) * cell)

	var total := n * n + 4 * n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(total)
	normals.resize(total)
	colors.resize(total)
	uvs.resize(total)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var p := (iz + 1) * pw + (ix + 1)
			var h := hp[p]
			var lx := -half + ix * cell
			var lz := -half + iz * cell
			var nrm := Vector3(hp[p - 1] - hp[p + 1], 2.0 * cell, hp[p - pw] - hp[p + pw]).normalized()
			verts[i] = Vector3(lx, h - lower, lz)
			normals[i] = nrm
			uvs[i] = Vector2((c.x + lx) / tile_m, (c.y + lz) / tile_m)
			var col: Color = terrain._vertex_color(c.x + lx, c.y + lz, h, nrm.y)
			if forest_level > 0.0:
				col = col.lerp(_forest_col, _forest_weight(c.x + lx, c.y + lz, h, nrm.y) * forest_level)
			colors[i] = col

	# Skirts hung under the edges hide any crack between two rings.
	var depth := cell * 0.5 + 4.0
	for e in 4:
		for k in n:
			var src := _edge_vertex(e, k, n)
			var di := n * n + e * n + k
			verts[di] = verts[src] + Vector3(0.0, -depth, 0.0)
			normals[di] = normals[src]
			colors[di] = colors[src]
			uvs[di] = uvs[src]

	return { "verts": verts, "normals": normals, "colors": colors, "uvs": uvs }


## How covered with trees the ground is here (0..1), using the same grove noise, tree line and slope limit as the tree script.
func _forest_weight(x: float, z: float, h: float, ny: float) -> float:
	if x * x + z * z < _f_clear * _f_clear or h > _f_maxh:
		return 0.0
	if ny < cos(deg_to_rad(_f_slope)):
		return 0.0
	var f := smoothstep(_f_low, _f_high, _forest_noise.get_noise_2d(x, z))
	var dens := lerpf(_f_min, _f_max, f) * (1.0 - smoothstep(_f_line, _f_maxh, h))
	return smoothstep(0.0, _f_max * 0.8, dens)


## Reads the grove settings and noise from the tree script (the node that has is_blocked_at), if there is one.
func _setup_forest() -> void:
	_forest_on = false
	if not forest_enabled:
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var trees: Node = null
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_method("is_blocked_at") and n.has_method("_ensure_logic"):
			trees = n
			break
	if trees == null or not trees._ensure_logic():
		return
	var nz = trees.get("_n_forest")
	if nz == null:
		return
	_forest_noise = nz
	_f_low = float(trees.get("forest_low"))
	_f_high = float(trees.get("forest_high"))
	_f_min = float(trees.get("min_density"))
	_f_max = float(trees.get("max_density"))
	_f_line = float(trees.get("tree_line_start"))
	_f_maxh = float(trees.get("max_tree_height"))
	_f_slope = float(trees.get("max_slope_degrees"))
	_f_clear = float(trees.get("clear_origin_radius"))
	# Same grass-texture tinting rule as the terrain's own colours.
	_forest_col = Color.WHITE.lerp(forest_color, float(terrain.get("_tint_k")))
	_forest_on = true

	# Distant trees: the very same trees as the tree script's (same seed, spots, sizes, turns), drawn cheaply.
	_ft_on = false
	if far_trees_enabled:
		_ft_trees = trees
		_ft_seed = int(trees.get("_seed"))
		_ft_spacing = float(trees.get("spacing"))
		_ft_jitter = float(trees.get("jitter"))
		_ft_gn = maxi(int(trees.get("grid_per_cell")), 1)
		_ft_real_cell = float(trees.get("cell_size"))
		_ft_reach = float(trees.get("draw_distance")) + _ft_real_cell * 0.5
		_ft_smin = float(trees.get("scale_min"))
		_ft_smax = float(trees.get("scale_max"))
		_ft_mult = maxi(int(roundf(far_tree_cell / _ft_real_cell)), 1)
		_ft_far_cell = _ft_real_cell * float(_ft_mult)
		_ft_half_diag = _ft_far_cell * 0.7072
		_ft_near_zone = float(terrain.get("render_distance")) * float(terrain.get("chunk_size")) * 0.85
		_ft_bpos = PackedVector2Array()
		_ft_brad = PackedFloat32Array()
		for b in get_tree().get_nodes_in_group(str(trees.get("blocker_group"))):
			if b is Node3D:
				var bp := (b as Node3D).global_position
				_ft_bpos.append(Vector2(bp.x, bp.z))
				_ft_brad.append(float(b.get_meta("radius", float(trees.get("blocker_default_radius")))))
		_ft_mesh = _make_far_tree_mesh()
		_ft_on = true


## Turns on haze in the scene's Environment so the far edge fades out instead of ending in a hard line.
func _setup_fog() -> void:
	if not fog_enabled:
		return
	var env: Environment = null
	var root := get_tree().current_scene
	if root:
		for n in root.find_children("*", "WorldEnvironment", true, false):
			env = (n as WorldEnvironment).environment
			if env != null:
				break
	if env == null:
		var cam := get_viewport().get_camera_3d()
		if cam:
			env = cam.environment
	if env == null:
		push_warning("far_terrain: no Environment found, so fog wasn't set up. Add a WorldEnvironment with an Environment.")
		return
	if env.fog_enabled:
		return                                          # you already have fog, leave it alone
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_strength * 3.0 / maxf(far_distance, 1.0)   # about 95 % faded at far_distance
	env.fog_aerial_perspective = fog_sky_blend


# -------------------------
# DISTANT TREES
# -------------------------
# These are the SAME trees as the real ones: same spots, sizes and turns, worked out with the tree script's own rules.
# They are drawn as very cheap models. When you walk up and the tree script builds the real trees around you, the cheap
# tree in each spot is hidden and its real twin appears in the same place (a high-quality tree, and the closer you get the
# better still).

## A very low-poly tree (about 45 triangles): a trunk that reaches well below the ground (so it never floats above the
## slightly lowered far ground) and a flattened blossom crown.
func _make_far_tree_mesh() -> ArrayMesh:
	var m := ArrayMesh.new()

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.5
	trunk.height = 11.0
	trunk.radial_segments = 5
	trunk.rings = 1
	trunk.cap_top = false
	trunk.cap_bottom = false
	var ta := trunk.get_mesh_arrays()
	var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	for i in tv.size():
		tv[i] += Vector3(0.0, -0.5, 0.0)                # trunk spans from 6 m below the base up to 5 m
	ta[Mesh.ARRAY_VERTEX] = tv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)

	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 6
	crown.rings = 3
	var ca := crown.get_mesh_arrays()
	var cv: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
	for i in cv.size():
		cv[i] = Vector3(cv[i].x * 3.0, cv[i].y * 2.2 + 4.8, cv[i].z * 3.0)
	ca[Mesh.ARRAY_VERTEX] = cv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ca)

	var bark := StandardMaterial3D.new()
	bark.albedo_color = far_tree_trunk_color
	bark.roughness = 1.0
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = far_tree_crown_color
	leaf.roughness = 1.0
	leaf.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.surface_set_material(0, bark)
	m.surface_set_material(1, leaf)
	return m


func _ft_centre(key: Vector3i) -> Vector2:
	return Vector2((key.y + 0.5) * _ft_far_cell, (key.z + 0.5) * _ft_far_cell)


## Which far-ground ring is visible at this distance (-1 = the real chunks). Used to stand trees exactly on the ground that is drawn.
func _band_for(d: float) -> int:
	if d < _ft_near_zone:
		return -1
	for lvl in _levels:
		if d <= _radii[lvl + 1]:
			return lvl
	return _levels - 1


func _update_far_trees(here: Vector2, now: float) -> void:
	_ft_here = here
	var cs := _ft_far_cell
	var span := int(ceil(far_tree_distance / cs)) + 1
	var ci := Vector2i(floori(here.x / cs), floori(here.y / cs))
	var wanted := {}
	_ft_queue.clear()
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var ix := ci.x + dx
			var iz := ci.y + dz
			var d := Vector2((ix + 0.5) * cs, (iz + 0.5) * cs).distance_to(here)
			if d > far_tree_distance:
				continue
			if d + _ft_half_diag < _ft_reach - 40.0:
				continue                                # completely inside the zone of real trees: nothing to draw here
			var key := Vector3i(_band_for(d), ix, iz)
			wanted[key] = true
			_ft_last[key] = now
			if not _ft_cells.has(key) and not _ft_jobs.has(key):
				_ft_queue.append(key)
	_ft_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _ft_centre(a).distance_squared_to(here) > _ft_centre(b).distance_squared_to(here))   # nearest last

	for key in _ft_cells.keys():
		if not wanted.has(key) and now - float(_ft_last.get(key, -1e9)) > keep_delay:
			_ft_free_cell(key)
			_ft_last.erase(key)


func _ft_free_cell(key: Vector3i) -> void:
	var cell = _ft_cells.get(key)
	if cell != null:
		var mmi = (cell as Dictionary)["mmi"]
		if is_instance_valid(mmi):
			(mmi as Node).queue_free()
	_ft_cells.erase(key)


func _ft_dispatch() -> void:
	while _ft_jobs.size() < far_tree_jobs and _ft_queue.size() > 0:
		var key: Vector3i = _ft_queue.pop_back()
		if _ft_cells.has(key) or _ft_jobs.has(key):
			continue
		_ft_jobs[key] = WorkerThreadPool.add_task(_ft_job.bind(key, _ft_here), false, "far trees")


func _ft_job(key: Vector3i, here: Vector2) -> void:
	var data := _ft_generate(key, here)
	_mutex.lock()
	_ft_results[key] = data
	_mutex.unlock()


func _ft_collect() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for key in _ft_jobs.keys():
		var id := int(_ft_jobs[key])
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		_ft_jobs.erase(key)
		_mutex.lock()
		var data = _ft_results.get(key)
		_ft_results.erase(key)
		_mutex.unlock()
		if data == null or _ft_cells.has(key):
			continue
		if now - float(_ft_last.get(key, -1e9)) > keep_delay:
			continue
		_ft_install(key, data)
		return                                          # one cell per frame


## Worker thread: works out the trees of one cell. This repeats the real tree script's own rules (same seed, same spots,
## same chance, tree line, slope limit, size and turn), so each far tree stands exactly where its real twin will.
## Returns 8 numbers per tree: x, y, z, yaw, scale, height stretch, and which real tree-script cell (x, z) the tree belongs to.
func _ft_generate(key: Vector3i, here: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var gn := _ft_gn
	var per := _ft_mult * gn                            # tree spots per side of this far cell
	var sp := _ft_spacing
	var thin := clampf(far_tree_thin, 0.0, 0.95)
	var rng := RandomNumberGenerator.new()
	for gi in per:
		for gj in per:
			var ix := key.y * per + gi
			var iz := key.z * per + gj
			rng.seed = hash(Vector3i(_ft_seed + 911, ix, iz))
			var keep_r := rng.randf()
			var jx := rng.randf_range(-1.0, 1.0)
			var jz := rng.randf_range(-1.0, 1.0)
			var yaw := rng.randf() * TAU
			var sr := rng.randf()
			var hr := rng.randf_range(0.92, 1.1)
			var rank := rng.randf()                     # (drawn last, so it doesn't change the real tree's numbers above)
			var x := (float(ix) + 0.5 + jx * _ft_jitter * 0.5) * sp
			var z := (float(iz) + 0.5 + jz * _ft_jitter * 0.5) * sp
			var dens := lerpf(_f_min, _f_max, smoothstep(_f_low, _f_high, _forest_noise.get_noise_2d(x, z)))
			if keep_r > dens:
				continue
			if x * x + z * z < _f_clear * _f_clear:
				continue
			# Further out, only some of the trees are drawn. Each tree has a fixed random rank, so a tree that is drawn
			# far away is still drawn when you are closer: trees only ever get added as you approach, never taken away.
			var band := _band_for(Vector2(x, z).distance_to(here))
			if rank > pow(1.0 - thin, float(maxi(band, 0))):
				continue
			var blocked := false
			for bi in _ft_bpos.size():
				if Vector2(_ft_bpos[bi].x - x, _ft_bpos[bi].y - z).length() < _ft_brad[bi]:
					blocked = true
					break
			if blocked:
				continue
			var h: float = terrain.height_at(x, z)
			if h > _f_maxh:
				continue
			if keep_r > dens * (1.0 - smoothstep(_f_line, _f_maxh, h)):
				continue
			var sx: float = terrain.height_at(x + 2.0, z) - terrain.height_at(x - 2.0, z)
			var sz: float = terrain.height_at(x, z + 2.0) - terrain.height_at(x, z - 2.0)
			var slope_t := sqrt(sx * sx + sz * sz) / 4.0
			if rad_to_deg(atan(slope_t)) > _f_slope:
				continue
			var s_real := lerpf(_ft_smin, _ft_smax, sr)
			var y := h - (0.1 + slope_t * 0.8 * s_real)   # exactly where the real tree's roots will be
			if band >= 0:
				y = _ft_base_y(x, z, band)
			var rkx := key.y * _ft_mult + floori(float(gi) / float(gn))
			var rkz := key.z * _ft_mult + floori(float(gj) / float(gn))
			out.append_array(PackedFloat32Array([x, y, z, yaw, s_real * far_tree_scale, hr, float(rkx), float(rkz)]))
	return out


## The height a tree should stand at on the far ground: the height of the far tile that is actually drawn there (the tiles are
## lowered a little, and cut corners on bumpy ground).
func _ft_base_y(x: float, z: float, band: int) -> float:
	var res := maxi(tile_resolution, 2)
	var cl := _tile_size(band) / float(res)
	var gx := floorf(x / cl)
	var gz := floorf(z / cl)
	var u := x / cl - gx
	var v := z / cl - gz
	var ha: float = terrain.height_at(gx * cl, gz * cl)
	var hb: float = terrain.height_at((gx + 1.0) * cl, gz * cl)
	var hc: float = terrain.height_at(gx * cl, (gz + 1.0) * cl)
	var hd: float = terrain.height_at((gx + 1.0) * cl, (gz + 1.0) * cl)
	var surf: float
	if u + v <= 1.0:                                    # the same two triangles the tile mesh is made of
		surf = ha + (hb - ha) * u + (hc - ha) * v
	else:
		surf = hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)
	return surf - (sink + cl * sink_per_cell)


func _ft_tree_xf(data: PackedFloat32Array, i: int, c: Vector2, hidden: bool) -> Transform3D:
	var o := i * 8
	var s := data[o + 4]
	var b := Basis(Vector3.UP, data[o + 3]).scaled(Vector3(s, s * data[o + 5], s))
	if hidden:
		b = Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001))   # (a hidden tree is shrunk to nothing)
	return Transform3D(b, Vector3(data[o] - c.x, data[o + 1], data[o + 2] - c.y))


func _ft_install(key: Vector3i, data: PackedFloat32Array) -> void:
	# Drop any older build of this cell (it was built for another ring).
	for k in _ft_cells.keys():
		if k != key and k.y == key.y and k.z == key.z:
			_ft_free_cell(k)
			_ft_last.erase(k)
	var n := data.size() / 8
	if n == 0:
		_ft_cells[key] = null
		return
	var c := _ft_centre(key)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _ft_mesh
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, _ft_tree_xf(data, i, c, false))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	mmi.global_position = Vector3(c.x, 0.0, c.y)
	var hid := PackedByteArray()
	hid.resize(n)
	_ft_cells[key] = { "mmi": mmi, "data": data, "hid": hid, "n_hid": 0 }
	var built = _ft_trees.get("_built") if is_instance_valid(_ft_trees) else null
	if built != null:
		_ft_hide_cell(key, _ft_here, built)


## Hands the trees over to the real ones: a far tree is hidden as soon as the tree script has built the cell that holds its
## real twin (and shown again if that cell is later removed), so each tree stays in its spot and just gets better as you come close.
func _ft_refresh_hidden(here: Vector2) -> void:
	if not is_instance_valid(_ft_trees):
		return
	var built = _ft_trees.get("_built")
	if built == null:
		return
	for key in _ft_cells.keys():
		_ft_hide_cell(key, here, built)


func _ft_hide_cell(key: Vector3i, here: Vector2, built: Dictionary) -> void:
	var cell = _ft_cells.get(key)
	if cell == null:
		return
	var c := _ft_centre(key)
	var near := c.distance_to(here) - _ft_half_diag <= _ft_reach + 40.0     # can this cell touch the zone of real trees?
	var n_hid: int = cell["n_hid"]
	if not near and n_hid == 0:
		return
	var data: PackedFloat32Array = cell["data"]
	var hid: PackedByteArray = cell["hid"]
	var mm := (cell["mmi"] as MultiMeshInstance3D).multimesh
	var reach2 := _ft_reach * _ft_reach
	for i in hid.size():
		var hide := false
		if near:
			var rk := Vector2i(roundi(data[i * 8 + 6]), roundi(data[i * 8 + 7]))
			if built.has(rk):
				var rc := Vector2((rk.x + 0.5) * _ft_real_cell, (rk.y + 0.5) * _ft_real_cell)
				hide = rc.distance_squared_to(here) <= reach2
		if hide != (hid[i] == 1):
			hid[i] = 1 if hide else 0
			n_hid += 1 if hide else -1
			mm.set_instance_transform(i, _ft_tree_xf(data, i, c, hide))
	cell["hid"] = hid
	cell["n_hid"] = n_hid


func _edge_vertex(e: int, k: int, n: int) -> int:
	if e == 0:
		return k
	if e == 1:
		return (n - 1) * n + k
	if e == 2:
		return k * n
	return k * n + (n - 1)


func _build_indices() -> void:
	var res := maxi(tile_resolution, 2)
	var n := res + 1
	_indices = PackedInt32Array()
	for iz in res:
		for ix in res:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			_indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var s := n * n
	for e in 4:
		for k in n - 1:
			var a := _edge_vertex(e, k, n)
			var b := _edge_vertex(e, k + 1, n)
			var a2 := s + e * n + k
			var b2 := a2 + 1
			_indices.append_array(PackedInt32Array([a, b, b2, a, b2, a2, a, b2, b, a, a2, b2]))


func _install(key: Vector3i, data: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _material != null:
		mesh.surface_set_material(0, _material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true                                 # placed in world space, wherever this node sits
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	var c := _tile_centre(key)
	mi.global_position = Vector3(c.x, 0.0, c.y)
	_tiles[key] = mi
