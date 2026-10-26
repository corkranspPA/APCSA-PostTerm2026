extends Node3D
## Infinite ground, Minecraft style: copies of your ground tile are laid out in a grid of chunks around the player.
## Only chunks near you or inside the camera's view are loaded; chunks that stay out of view are removed, so the ground
## never ends and costs about the same wherever you are.
## Add this to a Node3D at the world origin (position 0,0,0, no rotation or scale), drag ground.glb into "Ground Scene".
##
## The tile is reshaped once at start-up:
##  - bumpiness is scaled down (height_scale)
##  - the tile's edges are blended flat to one common height (edge_blend), so neighbouring chunks always meet with no gaps
##  - collision follows the real surface, so the player stands ON the ground instead of floating above it
##  - an optional grass texture is put on the ground (Grass Texture slot)

# -------------------------
# SETUP
# -------------------------
@export var ground_scene: PackedScene                  # your ground.glb (or any scene that is one tile)
@export var ground_scene_path := "res://ground/ground.glb"   # used if Ground Scene is empty (right-click ground.glb > Copy Path)
@export var player: Node3D                             # leave empty to find a node in group "player", or one named "Player"
@export var render_distance := 6                       # how many chunks out from you can be loaded (radius)
@export var chunks_per_frame := 4                      # how many new chunks may appear per frame (keeps movement smooth)
@export var chunk_size_override := Vector2.ZERO        # 0,0 = measure the tile automatically; set X,Z in metres to force a size

# -------------------------
# ONLY LOAD WHAT YOU CAN SEE
# -------------------------
@export var load_only_in_view := true                  # chunks outside the camera's view are not loaded (turn off to load the whole circle)
@export var always_load_radius := 2                    # chunks this close to you are always loaded, even behind you (so you never see a hole when turning)
@export var view_margin := 1.3                         # how generously the view is measured (higher = chunks appear a bit before they come into view)
@export var unload_delay := 3.0                        # seconds a chunk can stay out of view before it is removed (stops pop-in when you turn back)
@export var update_interval := 0.15                    # how often (seconds) the view is checked

# -------------------------
# GRASS
# -------------------------
@export_group("Grass")
@export var grass_texture: Texture2D                   # drop your grass image here (empty = keep the material from ground.glb)
@export var grass_normal_texture: Texture2D            # optional bump map for the grass (only used with world projection on)
@export_range(0.0, 4.0) var grass_normal_strength := 1.0
@export var grass_tint := Color(1.0, 1.0, 1.0)         # multiplies the grass colour; use it to darken or shift the green
@export_range(0.0, 1.0) var grass_roughness := 1.0     # 1 = matte, like real grass
@export var grass_world_projection := true             # on: the grass is painted in world space, so it lines up across every chunk and ignores the mesh's UVs
@export var grass_tile_meters := 4.0                   # world projection: how many metres one copy of the texture covers (smaller = finer grass)
@export var grass_uv_repeat := 8.0                     # mesh-UV mode (world projection off): how many times the texture repeats per tile

# -------------------------
# SHAPE
# -------------------------
@export_group("Shape")
@export_range(0.0, 1.0) var height_scale := 0.35       # 1 = the bumps exactly as Blender made them, 0 = completely flat. Lower = gentler ground.
@export var edge_blend := 0.0                          # metres over which each tile's edge is flattened so tiles join cleanly (0 = auto, 10% of the tile)

# -------------------------
# COLLISION
# -------------------------
@export_group("Collision")
@export var mesh_collision := true                     # the player walks on the real surface (shared between all chunks, so it's cheap)
@export var safety_floor := true                       # an endless invisible floor just below the ground, so you can never fall out of the world
@export var collision_height_offset := 0.0             # nudge the ground collision up/down if you sink in or float

var _chunks := {}                                      # Vector2i -> Node3D
var _last_wanted := {}                                 # Vector2i -> the last time (seconds) that chunk was needed
var _queue: Array[Vector2i] = []                       # chunks waiting to appear (nearest last, so pop_back gives the nearest)
var _size := Vector2(10.0, 10.0)                       # one tile's size on X and Z
var _center_offset := Vector2.ZERO                     # where the tile's middle sits relative to its origin
var _base_y := 0.0                                     # the height every tile edge sits at
var _timer := 0.0
var _ready_done := false

var _parts: Array = []                                 # reshaped meshes: { "mesh": ArrayMesh, "xf": Transform3D, "shape": Shape3D }


func _ready() -> void:
	if ground_scene == null:
		for path in [ground_scene_path, "res://ground.glb", "res://ground/ground.glb"]:
			if path != "" and ResourceLoader.exists(path):
				ground_scene = load(path) as PackedScene
				break
	if ground_scene == null:
		push_error("ground_chunks: no Ground Scene. Drag ground.glb into the Ground Scene slot.")
		return

	var sample := ground_scene.instantiate()
	var floor_y := 0.0
	if sample is Node3D:
		floor_y = _build_parts(sample)
	sample.free()

	if chunk_size_override.x > 0.0 and chunk_size_override.y > 0.0:
		_size = chunk_size_override
	if _size.x < 0.01 or _size.y < 0.01:
		push_error("ground_chunks: couldn't measure the ground tile. Set Chunk Size Override.")
		return
	print("ground_chunks: tile size = ", _size)

	if safety_floor:
		var body := StaticBody3D.new()
		body.name = "SafetyFloor"
		var shape := CollisionShape3D.new()
		shape.shape = WorldBoundaryShape3D.new()        # an endless flat plane facing up
		body.add_child(shape)
		body.position.y = floor_y - 1.0 + collision_height_offset
		add_child(body)

	_ready_done = true
	_update_chunks()
	_spawn_from_queue(1 << 30)                          # first fill happens all at once, so you don't start in a void


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		_update_chunks()
	_spawn_from_queue(chunks_per_frame)


# -------------------------
# TILE RESHAPING (runs once)
# -------------------------

## Measures the tile, then builds gentler meshes whose edges all sit at the same height. Returns the lowest height.
func _build_parts(sample: Node3D) -> float:
	var instances: Array[MeshInstance3D] = []
	var xforms: Array[Transform3D] = []
	_gather_meshes(sample, Transform3D.IDENTITY, instances, xforms)
	if instances.is_empty():
		return 0.0

	# Pass 1: size of the tile and its average height.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var sum_y := 0.0
	var count := 0
	for i in instances.size():
		var mesh := instances[i].mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xforms[i] * v
				lo = lo.min(p)
				hi = hi.max(p)
				sum_y += p.y
				count += 1
	if count == 0:
		return 0.0

	var base_y := sum_y / float(count)                  # the height every tile edge is brought to
	_base_y = base_y
	_size = Vector2(hi.x - lo.x, hi.z - lo.z)
	_center_offset = Vector2((lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5)
	var blend := edge_blend if edge_blend > 0.0 else minf(_size.x, _size.y) * 0.1
	blend = maxf(blend, 0.001)
	var hs := maxf(height_scale, 0.0)
	var low_y := base_y
	var grass_mat := _make_grass_material()

	# Pass 2: rebuild each mesh with scaled-down bumps and flat edges.
	for i in instances.size():
		var src := instances[i].mesh
		if src == null:
			continue
		var xf := xforms[i]
		var inv := xf.affine_inverse()
		var new_mesh := ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals = arrays[Mesh.ARRAY_NORMAL]
			var has_normals: bool = normals is PackedVector3Array and (normals as PackedVector3Array).size() == verts.size()
			for j in verts.size():
				var p := xf * verts[j]
				var d := minf(minf(p.x - lo.x, hi.x - p.x), minf(p.z - lo.z, hi.z - p.z))
				var w := 1.0 - smoothstep(0.0, blend, d)    # 1 right on the tile edge, 0 once inside the blend zone
				p.y = base_y + (p.y - base_y) * hs * (1.0 - w)
				low_y = minf(low_y, p.y)
				verts[j] = inv * p
				if has_normals:
					var n: Vector3 = xf.basis * (normals as PackedVector3Array)[j]
					n = Vector3(n.x, n.y / maxf(hs, 0.05), n.z).normalized()   # flatter ground = shallower slopes
					n = n.lerp(Vector3.UP, w).normalized()
					(normals as PackedVector3Array)[j] = (xf.basis.inverse() * n).normalized()
			arrays[Mesh.ARRAY_VERTEX] = verts
			if has_normals:
				arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null           # the old tangents no longer match, so drop them
			new_mesh.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
			var mat: Material = grass_mat
			if mat == null:
				mat = instances[i].get_surface_override_material(s)
			if mat == null:
				mat = src.surface_get_material(s)
			if mat:
				new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, mat)

		var part := { "mesh": new_mesh, "xf": xf, "shape": null }
		if mesh_collision:
			part["shape"] = new_mesh.create_trimesh_shape()
		_parts.append(part)

	return low_y


## Builds the grass material from the Grass section of the Inspector (nothing if no texture is assigned).
func _make_grass_material() -> StandardMaterial3D:
	if grass_texture == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = grass_texture
	m.albedo_color = grass_tint
	m.roughness = grass_roughness
	m.texture_repeat = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if grass_world_projection:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true                     # painted in world space, so chunks line up perfectly
		m.uv1_scale = Vector3.ONE / maxf(grass_tile_meters, 0.01)
		m.uv1_triplanar_sharpness = 4.0
		if grass_normal_texture:
			m.normal_enabled = true
			m.normal_texture = grass_normal_texture
			m.normal_scale = grass_normal_strength
	else:
		m.uv1_scale = Vector3(grass_uv_repeat, grass_uv_repeat, 1.0)
	return m


## Collects every mesh in the tile with its position relative to the tile's own origin.
func _gather_meshes(node: Node, xf: Transform3D, out_meshes: Array[MeshInstance3D], out_xf: Array[Transform3D]) -> void:
	for child in node.get_children():
		var cx := xf
		if child is Node3D:
			cx = xf * (child as Node3D).transform
		if child is MeshInstance3D:
			out_meshes.append(child as MeshInstance3D)
			out_xf.append(cx)
		_gather_meshes(child, cx, out_meshes, out_xf)


# -------------------------
# CHUNK STREAMING
# -------------------------
func _get_focus() -> Node3D:
	if player and is_instance_valid(player):
		return player
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null and get_tree().current_scene:
		p = get_tree().current_scene.find_child("Player", true, false) as Node3D
	if p:
		player = p
		return p
	return get_viewport().get_camera_3d()


## Works out which chunks are needed right now (close to you, or inside the camera's view), queues the missing ones,
## and removes chunks that have been out of view for longer than unload_delay.
func _update_chunks() -> void:
	var focus := _get_focus()
	var pos := focus.global_position if focus else Vector3.ZERO
	var c := Vector2i(
		roundi((pos.x - _center_offset.x) / _size.x),
		roundi((pos.z - _center_offset.y) / _size.y))

	var cam := get_viewport().get_camera_3d()
	var planes: Array = []
	if load_only_in_view and cam:
		planes = cam.get_frustum()
	var sphere := _size.length() * 0.5 * maxf(view_margin, 1.0)   # a ball around the chunk that must touch the view
	var now := Time.get_ticks_msec() / 1000.0

	_queue.clear()
	var r := render_distance
	var near_r := always_load_radius
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var dist2 := dx * dx + dz * dz
			if dist2 > r * r:
				continue
			var key := Vector2i(c.x + dx, c.y + dz)
			var wanted := true
			if planes.size() > 0 and dist2 > near_r * near_r:
				var centre := Vector3(key.x * _size.x + _center_offset.x, _base_y, key.y * _size.y + _center_offset.y)
				for pl in planes:
					if (pl as Plane).distance_to(centre) > sphere:    # completely outside one side of the view
						wanted = false
						break
			if wanted:
				_last_wanted[key] = now
				if not _chunks.has(key):
					_queue.append(key)

	# Furthest first, so pop_back() always gives the chunk closest to the player.
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - c).length_squared() > (b - c).length_squared())

	for key in _chunks.keys():
		if now - float(_last_wanted.get(key, -1e9)) > unload_delay:
			(_chunks[key] as Node).queue_free()
			_chunks.erase(key)
			_last_wanted.erase(key)


func _spawn_from_queue(budget: int) -> void:
	while budget > 0 and _queue.size() > 0:
		var key: Vector2i = _queue.pop_back()
		if not _chunks.has(key):
			_spawn(key)
		budget -= 1


func _spawn(key: Vector2i) -> void:
	var chunk: Node3D
	if _parts.is_empty():
		chunk = ground_scene.instantiate() as Node3D      # fallback: the tile had no meshes to reshape
		if chunk == null:
			return
	else:
		chunk = Node3D.new()
		var body: StaticBody3D = null
		if mesh_collision:
			body = StaticBody3D.new()
			body.position.y = collision_height_offset
			chunk.add_child(body)
		for part in _parts:
			var mi := MeshInstance3D.new()
			mi.mesh = part["mesh"]                          # the same mesh is shared by every chunk
			mi.transform = part["xf"]
			chunk.add_child(mi)
			if body and part["shape"]:
				var cs := CollisionShape3D.new()
				cs.shape = part["shape"]                    # and so is the collision shape
				cs.transform = part["xf"]
				body.add_child(cs)
	chunk.name = "Chunk_%d_%d" % [key.x, key.y]
	chunk.position = Vector3(key.x * _size.x, 0.0, key.y * _size.y)
	add_child(chunk)
	_chunks[key] = chunk
