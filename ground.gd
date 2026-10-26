extends Node3D
## Minecraft-style endless terrain, generated chunk by chunk from noise (no ground.glb needed).
## This replaces the old ground_chunks.gd. Keep it on the same Node3D at the world origin (position 0,0,0, no rotation or scale).
##
## - Every chunk's height comes from world coordinates, so neighbouring chunks always join perfectly, and the same seed
##   always gives the same world.
## - Rolling hills, flat plains, fine bumps, and the occasional big mountain: a large hill that stands out of the ground (rock on steep or high ground, snow on peaks).
## - Chunks are only drawn when they are close to you or inside the camera's view. Chunks behind you lose their mesh after
##   a short delay, but their COLLISION stays loaded (around you, and around anything in the groups listed below),
##   so enemies, bullets and anything else that is happening keeps running on solid ground. Nothing else in your game
##   is paused, hidden or touched by this script.
## - NEW: level of detail. Chunks close to you are built at full detail, chunks further out at half and then a quarter
##   of the detail. On top of a mountain, where almost the whole world is in view, this makes generating and drawing the
##   distant ground many times cheaper. Small "skirts" under each chunk's edge hide any crack between two detail levels.
##
## Handy for your other scripts:  get_node("Terrain").height_at(x, z)  returns the ground height at any spot.

# -------------------------
# WORLD
# -------------------------
@export var player: Node3D                             # leave empty to find a node in group "player", or one named "Player"
@export var seed_value := 0                            # 0 = a new random world every run. Any other number = that exact world.
@export var chunk_size := 32.0                         # metres per chunk side
@export var chunk_resolution := 24                     # grid cells per chunk side at FULL detail (higher = smoother ground, slower to generate)
@export var render_distance := 16                      # how many chunks out can be drawn (radius). 16 x 32 m = 512 m
@export var chunks_per_frame := 2                      # how much new ground may be generated per frame (a full-detail chunk counts 1, far chunks count much less)

# -------------------------
# TERRAIN SHAPE
# -------------------------
@export_group("Terrain shape")
@export var hill_height := 5.0                         # height of the rolling hills (metres)
@export var hill_wavelength := 140.0                   # distance between hills (metres)
@export var plains_wavelength := 420.0                 # size of the flat plains and hilly regions
@export var detail_height := 0.5                       # small bumps on top of everything (more variation up close)
@export var detail_wavelength := 14.0
@export_range(0.0, 1.0) var mountain_amount := 0.35    # chance that each mountain slot holds a mountain (0 = none, 1 = every slot)
@export var mountain_height := 100.0                   # how high a typical mountain stands above the ground (metres); each one varies a bit
@export var mountain_radius := 260.0                   # how wide a typical mountain is, from its middle to its foot (metres)
@export var mountain_spacing := 700.0                  # size of the grid of mountain slots (metres): bigger = mountains further apart
@export var spawn_flat_radius := 40.0                  # ground around the world origin stays flat, so you never start inside a mountain

# -------------------------
# COLOURS (painted into the terrain; multiplied with the grass texture if you add one)
# -------------------------
@export_group("Colours")
@export var grass_color_a := Color(0.36, 0.58, 0.22)
@export var grass_color_b := Color(0.55, 0.66, 0.26)   # grass patches blend between the two colours
@export var rock_color := Color(0.44, 0.42, 0.41)
@export var snow_color := Color(0.93, 0.95, 0.98)
@export_range(0.0, 1.0) var rock_slope := 0.85         # steeper than this turns to rock (higher = more rock)
@export var rock_height := 50.0                        # above this height the ground turns to rock
@export var snow_height := 85.0                        # above this height flatter ground turns to snow (set very high for no snow)

# -------------------------
# GRASS TEXTURE
# -------------------------
@export_group("Grass")
@export var grass_texture: Texture2D                   # drop your seamless grass image here (empty = plain painted colours)
@export var grass_normal_texture: Texture2D            # optional bump map for the grass
@export_range(0.0, 4.0) var grass_normal_strength := 1.0
@export_range(0.0, 1.0) var grass_color_strength := 0.65   # with a texture: how strongly the painted colours tint it (0 = pure texture)
@export var grass_tile_meters := 4.0                   # how many metres one copy of the texture covers (smaller = finer grass)
@export_range(0.0, 1.0) var grass_roughness := 1.0

# -------------------------
# LEVEL OF DETAIL (NEW) - the main fix for lag when standing on a mountain
# -------------------------
@export_group("Level of detail")
@export var lod_enabled := true                        # off = every chunk at full detail, like before
@export var lod_full_chunks := 6                       # chunks this close (radius) are full detail. Never below physics_radius + 1
@export var lod_mid_chunks := 11                       # up to here: half detail. Beyond: a quarter of the detail
@export var skirt_depth := 4.0                         # how far the edge skirts hang down to hide cracks between detail levels (metres)
@export var regen_per_frame := 1                       # chunks re-built per frame when they change detail level as you move

# -------------------------
# ONLY DRAW WHAT YOU CAN SEE
# -------------------------
@export_group("View")
@export var load_only_in_view := true                  # chunks outside the camera's view are not drawn (off = draw the whole circle)
@export var always_load_radius := 2                    # chunks this close are always drawn, even behind you (no holes when you turn)
@export var view_margin := 1.3                         # how generously the view is measured (higher = chunks appear a bit earlier)
@export var unload_delay := 3.0                        # seconds a chunk can stay out of view before its mesh is removed
@export var update_interval := 0.25                    # how often (seconds) the view is checked
@export var mesh_free_delay := 30.0                    # seconds a chunk's mesh stays hidden (so turning back is instant) before it is freed
@export var meshes_per_frame := 4                      # how many chunk meshes may be shown again per frame (keeps turning smooth)
@export var pregenerate_behind := true                 # quietly build the ground behind and beside you ahead of time, so turning never has to generate it
@export var data_keep_extra := 2                       # chunks this far beyond render_distance keep their built ground before it is thrown away

# -------------------------
# COLLISION / KEEP THE WORLD RUNNING
# -------------------------
@export_group("Collision")
@export var physics_radius := 5                        # chunks around the player that always keep their collision, even behind you
@export var keep_physics_around_groups: Array[String] = ["enemy", "terrain_follow"]   # collision is also kept around anything in these groups (add your enemies to one)
@export var safety_floor := true                       # an endless invisible floor far below, so nothing can fall out of the world forever

var _seed := 0
var _n_hills: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_plains: FastNoiseLite
var _n_mask: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_patch: FastNoiseLite
var _mtn_cells := {}                                   # Vector2i -> Vector4(x, z, radius, height) for each mountain slot (height 0 = none)
var _material: StandardMaterial3D
var _tint_k := 1.0

var _chunks := {}                                      # Vector2i -> { "node", "data", "mesh", "body" }
var _vis_time := {}                                    # Vector2i -> last time (seconds) this chunk was needed for drawing
var _phys_time := {}                                   # Vector2i -> last time (seconds) this chunk was needed for collision
var _queue: Array[Vector2i] = []                       # chunks waiting to be generated (nearest last, so pop_back gives the nearest)
var _bg_queue: Array[Vector2i] = []                    # chunks to build quietly in the background (behind / beside you)
var _mesh_queue: Array[Vector2i] = []                  # chunks whose mesh needs making or showing (nearest last)
var _regen_queue: Array[Vector2i] = []                 # chunks that should be re-built at a different detail level (nearest last)
var _data_time := {}                                   # Vector2i -> last time (seconds) the built ground of this chunk was worth keeping
var _indices_cache := {}                               # grid resolution -> triangle list (the same for every chunk of that detail), built once
var _centre_chunk := Vector2i.ZERO                     # the chunk the player is in (updated with the view)
var _timer := 0.0
var _ready_done := false


func _ready() -> void:
	_seed = seed_value if seed_value != 0 else randi()
	print("terrain_chunks: seed = ", _seed)
	_setup_noise()
	_material = _make_material()
	_tint_k = grass_color_strength if grass_texture != null else 1.0

	if safety_floor:
		var body := StaticBody3D.new()
		body.name = "SafetyFloor"
		var shape := CollisionShape3D.new()
		shape.shape = WorldBoundaryShape3D.new()
		body.add_child(shape)
		body.position.y = -(hill_height + detail_height) - 5.0
		add_child(body)

	_ready_done = true
	_update_chunks()
	# Fill the area right around the player at once, so you never start in a void; the rest streams in.
	while _queue.size() > 0 and (_queue.back() - _chunk_of(_focus_position())).length() <= float(always_load_radius) + 0.5:
		_spawn(_queue.pop_back(), true)


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		_update_chunks()
	_spawn_from_queue(float(chunks_per_frame))
	_regen_chunks(regen_per_frame)
	_build_meshes(meshes_per_frame)


# -------------------------
# THE HEIGHT OF THE WORLD
# -------------------------
func _make_noise(offset: int, wavelength: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = _seed + offset
	n.frequency = 1.0 / maxf(wavelength, 0.01)
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n


func _setup_noise() -> void:
	_n_hills = _make_noise(1, hill_wavelength, 4)
	_n_detail = _make_noise(2, detail_wavelength, 2)
	_n_plains = _make_noise(3, plains_wavelength, 2)
	_n_mask = _make_noise(4, 300.0, 2)                  # wobbles the outline of each mountain
	_n_ridge = _make_noise(5, 80.0, 3)                  # lumps on the mountain surface
	_n_patch = _make_noise(6, 22.0, 2)
	_mtn_cells.clear()


## The ground height at any world position. Use this to place things on the ground, even in chunks that aren't loaded.
func height_at(x: float, z: float) -> float:
	var plains := 0.3 + 0.7 * smoothstep(-0.35, 0.45, _n_plains.get_noise_2d(x, z))   # flat regions and hilly regions
	var h := _n_hills.get_noise_2d(x, z) * hill_height * plains
	h += _n_detail.get_noise_2d(x, z) * detail_height
	if mountain_amount > 0.0:
		var cx := floori(x / mountain_spacing)
		var cz := floori(z / mountain_spacing)
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var m := _mountain_at(Vector2i(cx + ox, cz + oz))
				if m.w <= 0.0:
					continue
				var dx := x - m.x
				var dz := z - m.y
				var reach := m.z * (1.0 + 0.25 * _n_mask.get_noise_2d(x, z))   # wobbles the outline so it isn't a perfect circle
				var d2 := (dx * dx + dz * dz) / (reach * reach)
				if d2 < 1.0:
					var f := 1.0 - d2
					h += m.w * f * f * (0.88 + 0.24 * (_n_ridge.get_noise_2d(x, z) * 0.5 + 0.5))   # smooth rounded hill with a lumpy surface
	var flat_w := smoothstep(spawn_flat_radius, spawn_flat_radius * 2.0, sqrt(x * x + z * z))
	return h * flat_w


## Each square slot of the world (mountain_spacing metres wide) may hold ONE mountain, decided by the seed alone,
## so the same mountain is always in the same place. Returns Vector4(x, z, radius, height); height 0 = no mountain.
func _mountain_at(cell: Vector2i) -> Vector4:
	if _mtn_cells.has(cell):
		return _mtn_cells[cell]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(_seed, cell.x, cell.y))
	var res := Vector4.ZERO
	if rng.randf() < mountain_amount:
		var mx := (cell.x + rng.randf_range(0.25, 0.75)) * mountain_spacing
		var mz := (cell.y + rng.randf_range(0.25, 0.75)) * mountain_spacing
		var radius := mountain_radius * rng.randf_range(0.7, 1.2)
		var height := mountain_height * rng.randf_range(0.6, 1.0)
		if sqrt(mx * mx + mz * mz) > radius + spawn_flat_radius * 2.0:   # never on top of the spawn area
			res = Vector4(mx, mz, radius, height)
	_mtn_cells[cell] = res
	return res


func _vertex_color(wx: float, wz: float, h: float, ny: float) -> Color:
	var patch := _n_patch.get_noise_2d(wx, wz) * 0.5 + 0.5
	var col := grass_color_a.lerp(grass_color_b, patch)
	var rock_w := 1.0 - smoothstep(rock_slope - 0.1, rock_slope + 0.1, ny)           # steep = rock
	rock_w = maxf(rock_w, smoothstep(rock_height, rock_height + 8.0, h))             # high = rock
	col = col.lerp(rock_color, rock_w)
	var snow_w := smoothstep(snow_height, snow_height + 6.0, h) * smoothstep(0.45, 0.7, ny)
	col = col.lerp(snow_color, snow_w)
	if _tint_k < 1.0:
		col = Color.WHITE.lerp(col, _tint_k)
	return col


# -------------------------
# LEVEL OF DETAIL
# -------------------------
## 0 = full detail, 1 = half, 2 = a quarter. d is the distance from the player in chunks.
func _tier_at(d: float) -> int:
	if not lod_enabled:
		return 0
	var full := float(maxi(lod_full_chunks, physics_radius + 1))   # the ground you stand and fight on is always full detail
	if d <= full:
		return 0
	if d <= maxf(float(lod_mid_chunks), full + 1.0):
		return 1
	return 2


func _res_of_tier(tier: int) -> int:
	var res := maxi(chunk_resolution, 2)
	if tier == 1:
		return maxi(res / 2, 2)
	if tier == 2:
		return maxi(res / 4, 2)
	return res


## How much of the per-frame generation budget a chunk of this detail level uses up (far chunks are much cheaper).
func _tier_cost(key: Vector2i) -> float:
	var t := _tier_at((key - _centre_chunk).length())
	if t == 1:
		return 0.35
	if t == 2:
		return 0.12
	return 1.0


# -------------------------
# BUILDING A CHUNK (the arrays are kept so its mesh can be re-made cheaply when you turn back)
# -------------------------
func _generate(key: Vector2i, tier: int) -> Dictionary:
	var res := _res_of_tier(tier)
	var n := res + 1                                    # vertices per side
	var cell := chunk_size / float(res)
	var half := chunk_size * 0.5
	var ox := key.x * chunk_size                        # world position of this chunk's centre
	var oz := key.y * chunk_size

	# Heights on a grid one step bigger on every side, so normals at the chunk edge match the neighbour exactly.
	var pw := n + 2
	var hp := PackedFloat32Array()
	hp.resize(pw * pw)
	for iz in pw:
		for ix in pw:
			hp[iz * pw + ix] = height_at(ox - half + (ix - 1) * cell, oz - half + (iz - 1) * cell)

	var total := n * n + 4 * n                          # the grid, then 4 skirt rows (one per edge)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var hmap := PackedFloat32Array()
	verts.resize(total)
	normals.resize(total)
	colors.resize(total)
	uvs.resize(total)
	hmap.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var p := (iz + 1) * pw + (ix + 1)
			var h := hp[p]
			var lx := -half + ix * cell
			var lz := -half + iz * cell
			var nrm := Vector3(hp[p - 1] - hp[p + 1], 2.0 * cell, hp[p - pw] - hp[p + pw]).normalized()
			verts[i] = Vector3(lx, h, lz)
			normals[i] = nrm
			uvs[i] = Vector2((ox + lx) / grass_tile_meters, (oz + lz) / grass_tile_meters)
			colors[i] = _vertex_color(ox + lx, oz + lz, h, nrm.y)
			hmap[i] = h

	# Skirts: a copy of every edge vertex, hung straight down. They are hidden under the ground, and only show if the
	# neighbouring chunk is built at a different detail level and a thin crack would otherwise open up.
	var depth := skirt_depth + float(tier) * 2.0
	for e in 4:
		for k in n:
			var src := _edge_vertex(e, k, n)
			var di := n * n + e * n + k
			verts[di] = verts[src] + Vector3(0.0, -depth, 0.0)
			normals[di] = normals[src]
			colors[di] = colors[src]
			uvs[di] = uvs[src]

	var indices := _get_indices(res, n)

	return { "verts": verts, "normals": normals, "colors": colors, "uvs": uvs, "indices": indices,
		"hmap": hmap, "n": n, "cell": cell, "tier": tier }


## Index of the k-th vertex along an edge of the grid. 0 = top (z min), 1 = bottom, 2 = left (x min), 3 = right.
func _edge_vertex(e: int, k: int, n: int) -> int:
	if e == 0:
		return k
	if e == 1:
		return (n - 1) * n + k
	if e == 2:
		return k * n
	return k * n + (n - 1)


## The triangle list is identical for every chunk of the same detail, so it is built once per detail level and shared.
func _get_indices(res: int, n: int) -> PackedInt32Array:
	if _indices_cache.has(res):
		return _indices_cache[res]
	var indices := PackedInt32Array()
	for iz in res:
		for ix in res:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	# Skirt strips, wound both ways so they show from outside whichever side the crack is on.
	var s := n * n
	for e in 4:
		for k in n - 1:
			var a := _edge_vertex(e, k, n)
			var b := _edge_vertex(e, k + 1, n)
			var a2 := s + e * n + k
			var b2 := a2 + 1
			indices.append_array(PackedInt32Array([a, b, b2, a, b2, a2, a, b2, b, a, a2, b2]))
	_indices_cache[res] = indices
	return indices


func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = grass_roughness
	m.metallic_specular = 0.2
	if grass_texture != null:
		m.albedo_texture = grass_texture
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.texture_repeat = true
		m.uv1_triplanar = true                           # painted in world space: lines up across chunks, doesn't stretch on mountains
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(grass_tile_meters, 0.01)
		m.uv1_triplanar_sharpness = 4.0
		if grass_normal_texture != null:
			m.normal_enabled = true
			m.normal_texture = grass_normal_texture
			m.normal_scale = grass_normal_strength
	return m


# -------------------------
# WHICH CHUNKS ARE NEEDED
# -------------------------
func _focus_position() -> Vector3:
	if player and is_instance_valid(player):
		return player.global_position
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null and get_tree().current_scene:
		p = get_tree().current_scene.find_child("Player", true, false) as Node3D
	if p:
		player = p
		return p.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / chunk_size), roundi(pos.z / chunk_size))


## True once the ground under this position has its collision loaded (used to hold new enemies until they have floor).
func has_collision_at(pos: Vector3) -> bool:
	var key := _chunk_of(pos)
	return _chunks.has(key) and (_chunks[key] as Dictionary)["body"] != null


## True while this position's chunk has its mesh showing (false once the chunk has disappeared from view).
func is_drawn_at(pos: Vector3) -> bool:
	var c = _chunks.get(_chunk_of(pos))
	return c != null and c["mesh"] != null and (c["mesh"] as MeshInstance3D).visible


func _sort_far_first(arr: Array[Vector2i], c: Vector2i) -> void:
	# Furthest first, so pop_back() always gives the chunk closest to the player.
	arr.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - c).length_squared() > (b - c).length_squared())


## Works out which chunks need to be drawn (close to you, or inside the camera's view) and which need collision
## (around you and around anything in the "keep physics" groups), queues what is missing, and trims the rest.
## Chunks that leave the view are only HIDDEN at first, and their built ground is kept, so turning around is instant.
func _update_chunks() -> void:
	var c := _chunk_of(_focus_position())
	_centre_chunk = c
	var cam := get_viewport().get_camera_3d()
	var planes: Array = []
	if load_only_in_view and cam:
		planes = cam.get_frustum()
	var sphere := chunk_size * 0.7071 * maxf(view_margin, 1.0)    # a ball around the chunk that must touch the view
	var now := Time.get_ticks_msec() / 1000.0
	var needed := {}      # must exist now: in view, or needed for collision
	var behind := {}      # inside the render circle but out of view: built quietly in the background

	# Drawing: close to you, or inside the camera's view.
	var r := render_distance
	var rd := r + maxi(data_keep_extra, 0)
	var near_r := always_load_radius
	for dx in range(-rd, rd + 1):
		for dz in range(-rd, rd + 1):
			var dist2 := dx * dx + dz * dz
			if dist2 > rd * rd:
				continue
			var key := Vector2i(c.x + dx, c.y + dz)
			_data_time[key] = now
			if dist2 > r * r:
				continue
			var wanted := true
			if planes.size() > 0 and dist2 > near_r * near_r:
				var centre := Vector3(key.x * chunk_size, mountain_height * 0.3, key.y * chunk_size)
				for pl in planes:
					if (pl as Plane).distance_to(centre) > sphere + mountain_height * 0.6:   # outside one side of the view (the extra covers tall mountains)
						wanted = false
						break
			if wanted:
				_vis_time[key] = now
				needed[key] = true
			else:
				behind[key] = true

	# Collision: around the player, even behind you.
	var pr := physics_radius
	for dx in range(-pr, pr + 1):
		for dz in range(-pr, pr + 1):
			if dx * dx + dz * dz > pr * pr:
				continue
			var key := Vector2i(c.x + dx, c.y + dz)
			_phys_time[key] = now
			_data_time[key] = now
			needed[key] = true

	# Collision around anything else that keeps happening (enemies and so on), wherever it is.
	for group_name in keep_physics_around_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D:
				var ec := _chunk_of((node as Node3D).global_position)
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var key := Vector2i(ec.x + dx, ec.y + dz)
						_phys_time[key] = now
						_data_time[key] = now
						needed[key] = true

	_queue.clear()
	_bg_queue.clear()
	_mesh_queue.clear()
	for key in needed.keys():
		if not _chunks.has(key):
			_queue.append(key)
	if pregenerate_behind:
		for key in behind.keys():
			if not _chunks.has(key) and not needed.has(key):
				_bg_queue.append(key)
	_sort_far_first(_queue, c)
	_sort_far_first(_bg_queue, c)

	for key in _chunks.keys():
		_sync_chunk(key, now)
	_sort_far_first(_mesh_queue, c)

	# Chunks that are now at the wrong detail level for their distance get re-built (a little gap before going coarser,
	# so a chunk right on a boundary doesn't flip back and forth).
	_regen_queue.clear()
	if lod_enabled:
		for key: Vector2i in _chunks.keys():
			var data: Dictionary = (_chunks[key] as Dictionary)["data"]
			var d: float = (key - c).length()
			var want: int = _tier_at(d)
			var have: int = int(data["tier"])
			if want < have or (want > have and _tier_at(d - 2.0) >= want):
				_regen_queue.append(key)
		_sort_far_first(_regen_queue, c)


func _spawn_from_queue(budget: float) -> void:
	while budget > 0.0 and _queue.size() > 0:
		var key: Vector2i = _queue.pop_back()
		if not _chunks.has(key):
			_spawn(key)
			budget -= _tier_cost(key)
	# Only when nothing in view is waiting: build the ground behind you (one full chunk per frame, or several far ones).
	if _queue.is_empty() and pregenerate_behind:
		var bg_budget := 1.0
		while bg_budget > 0.0 and _bg_queue.size() > 0:
			var bg_key: Vector2i = _bg_queue.pop_back()
			if not _chunks.has(bg_key):
				_spawn(bg_key)
				bg_budget -= _tier_cost(bg_key)


## Re-builds chunks whose detail level changed as you moved, a few per frame, swapping the mesh and collision in place.
func _regen_chunks(budget: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while budget > 0 and _regen_queue.size() > 0:
		var key: Vector2i = _regen_queue.pop_back()
		var c = _chunks.get(key)
		if c == null:
			continue
		var want := _tier_at((key - _centre_chunk).length())
		if int(c["data"]["tier"]) == want:
			continue
		c["data"] = _generate(key, want)
		var node: Node3D = c["node"]
		if c["mesh"] != null:
			var old := c["mesh"] as MeshInstance3D
			var was_visible := old.visible
			old.queue_free()
			c["mesh"] = null
			if was_visible:
				c["mesh"] = _make_mesh_node(c["data"], node)      # swapped straight away, so no hole appears
		if c["body"] != null:
			(c["body"] as Node).queue_free()
			c["body"] = _make_body_node(c["data"], node)
		_sync_chunk(key, now)
		budget -= 1


## Makes or re-shows chunk meshes a few at a time, nearest first, so turning around never causes one big hitch.
func _build_meshes(budget: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while budget > 0 and _mesh_queue.size() > 0:
		var key: Vector2i = _mesh_queue.pop_back()
		var c = _chunks.get(key)
		if c == null or c["mesh"] != null:
			continue
		if now - float(_vis_time.get(key, -1e9)) <= unload_delay:
			c["mesh"] = _make_mesh_node(c["data"], c["node"])
			budget -= 1


func _spawn(key: Vector2i, immediate := false) -> void:
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	node.position = Vector3(key.x * chunk_size, 0.0, key.y * chunk_size)
	add_child(node)
	var tier := _tier_at((key - _centre_chunk).length())
	_chunks[key] = { "node": node, "data": _generate(key, tier), "mesh": null, "body": null }
	_sync_chunk(key, Time.get_ticks_msec() / 1000.0, immediate)


## Gives a chunk the parts it needs right now: a mesh while it's wanted for drawing, a collision body while it's wanted
## for physics. A mesh that is no longer wanted is first just hidden (cheap to bring back), and only freed after
## mesh_free_delay seconds, or when the chunk is too far away to be worth keeping at all.
func _sync_chunk(key: Vector2i, now: float, immediate := false) -> void:
	var c: Dictionary = _chunks[key]
	var keep := now - float(_data_time.get(key, -1e9)) <= unload_delay
	if not keep:
		(c["node"] as Node).queue_free()                  # takes its mesh and collision with it
		_chunks.erase(key)
		_vis_time.erase(key)
		_phys_time.erase(key)
		_data_time.erase(key)
		return

	var vis_age := now - float(_vis_time.get(key, -1e9))
	if vis_age <= unload_delay:
		if c["mesh"] == null:
			if immediate:
				c["mesh"] = _make_mesh_node(c["data"], c["node"])
			else:
				_mesh_queue.append(key)
		elif not (c["mesh"] as MeshInstance3D).visible:
			(c["mesh"] as MeshInstance3D).visible = true
	elif c["mesh"] != null:
		if vis_age > mesh_free_delay:
			(c["mesh"] as Node).queue_free()
			c["mesh"] = null
		else:
			(c["mesh"] as MeshInstance3D).visible = false

	var want_body := now - float(_phys_time.get(key, -1e9)) <= unload_delay
	if want_body and c["body"] == null:
		c["body"] = _make_body_node(c["data"], c["node"])
	elif not want_body and c["body"] != null:
		(c["body"] as Node).queue_free()
		c["body"] = null


func _make_mesh_node(data: Dictionary, parent: Node3D) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _make_body_node(data: Dictionary, parent: Node3D) -> StaticBody3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = data["n"]
	shape.map_depth = data["n"]
	shape.map_data = data["hmap"]
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(data["cell"], 1.0, data["cell"])  # the height map is one metre per cell, so stretch it to the chunk
	var body := StaticBody3D.new()
	body.add_child(cs)
	parent.add_child(body)
	return body
