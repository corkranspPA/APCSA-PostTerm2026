extends Node
## PERFORMANCE MANAGER — drop this on any Node in your main scene (or add it as an Autoload). No setup needed.
##
## What it does:
##  * ADAPTIVE RESOLUTION: watches your frame rate and quietly lowers the 3D render resolution when the game starts to lag,
##    then raises it again when there's headroom. The HUD stays sharp (only the 3D world is scaled).
##  * Cheaper shadows: shorter sun-shadow distance, optional softer-shadow quality drop.
##  * Turns off expensive extras that are rarely worth it (MSAA), and turns on occlusion culling + mesh LOD.
##  * Optional frame cap so the GPU isn't running flat out.
##
## Everything is an @export, so you can tweak it in the Inspector.

@export_group("Adaptive resolution")
@export var adaptive_resolution := true
@export var target_fps := 60.0              # the frame rate it tries to hold
@export var min_scale := 0.6                # never render below this fraction of your screen resolution
@export var max_scale := 1.0
@export var adjust_interval := 0.5          # seconds between checks
@export var step_down := 0.06               # how much to lower the scale when lagging
@export var step_up := 0.03                 # how much to raise it when there's headroom (slower, so it doesn't flicker)

@export_group("Rendering")
@export var disable_msaa := true            # MSAA is expensive; FSR upscaling / TAA are cheaper
@export var occlusion_culling := true       # skips drawing things hidden behind hills and walls (needs the Forward+/Mobile renderer)
@export var mesh_lod := true                # distant meshes use simpler versions (only affects meshes that have LODs)
@export var mesh_lod_threshold := 2.0       # higher = switches to simpler meshes sooner (faster)
@export var shadow_distance := 90.0         # how far the sun's shadows reach (0 = leave as is). Shorter = faster
@export var limit_fps := 0                  # 0 = no cap. e.g. 120 to stop the GPU running flat out
@export var show_fps_label := false         # a small FPS counter in the corner (handy while testing)

var _timer := 0.0
var _scale := 1.0
var _smooth_fps := 60.0
var _label: Label
var _can_scale := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport()
	_can_scale = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_scale = clampf(vp.scaling_3d_scale, min_scale, max_scale)

	if disable_msaa:
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if occlusion_culling:
		vp.use_occlusion_culling = true
	if mesh_lod:
		vp.mesh_lod_threshold = mesh_lod_threshold
	if limit_fps > 0:
		Engine.max_fps = limit_fps
	if shadow_distance > 0.0:
		_apply_shadow_distance.call_deferred()

	if show_fps_label:
		var layer := CanvasLayer.new()
		layer.layer = 100
		_label = Label.new()
		_label.position = Vector2(8, 8)
		layer.add_child(_label)
		add_child(layer)


## Shortens every sun light's shadow reach, which is one of the biggest GPU costs in an open-world scene.
func _apply_shadow_distance() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		var l := n as DirectionalLight3D
		if l.shadow_enabled:
			l.directional_shadow_max_distance = minf(l.directional_shadow_max_distance, shadow_distance)


func _process(delta: float) -> void:
	var fps := 1.0 / maxf(delta, 0.0001)
	_smooth_fps = lerpf(_smooth_fps, fps, 0.05)
	if _label:
		_label.text = "%d FPS  (3D scale %d%%)" % [roundi(_smooth_fps), roundi(_scale * 100.0)]

	if not adaptive_resolution or not _can_scale:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = adjust_interval

	var vp := get_viewport()
	var new_scale := _scale
	if _smooth_fps < target_fps * 0.92:
		new_scale = maxf(_scale - step_down, min_scale)
	elif _smooth_fps > target_fps * 1.1 and _scale < max_scale:
		new_scale = minf(_scale + step_up, max_scale)
	if is_equal_approx(new_scale, _scale):
		return
	_scale = new_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if _scale >= 0.999 else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = _scale
