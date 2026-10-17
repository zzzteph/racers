extends SceneTree
## Renders the game's key art from the real low-poly car models: low-poly racers charging straight at the
## viewer down a track, every one of them pulled along by its rope, some of them flipping or up on two
## wheels, with dust and rubber on the road. (SPEC 121: no glowing rings on the ends of the ropes --
## they read as somebody else's game.)
##
## Writes (into res://art/):
##   splash.png    1920x1080, with the title -- the boot splash (replaces the Godot logo)
##   menu_bg.png   1920x1080, no title      -- the title screen's background
##   icon_render.png  the hero car on transparent -- tools/make_icons.py makes the icons from it
## and the calmer night-time backgrounds of the other screens (the empty circuit, no cars, a vignette):
##   bg_garage.png   the start / finish gantry, low from the side -- car select
##   bg_tracks.png   the straight from high above                 -- track select
##   bg_grid.png     the empty starting grid from behind          -- multiplayer lobby
##   bg_wreck.png    across the sand trap                         -- settings
##
## Run with a real renderer (not --headless):
##   godot --path . --script res://tools/render_art.gd
## Deterministic: the same picture every time.

const W := 1920
const H := 1080
const ROPE_COLOR := Color(1.0, 0.42, 0.18)
const RING_COLOR := Color(1.0, 0.85, 0.3)

var _vp: SubViewport
var _world: Node3D
var _camera: Camera3D
var _title: Control


func _init() -> void:
	await process_frame
	# ART_ICON_ONLY=1 skips the big pictures (for iterating on the icon).
	if OS.get_environment("ART_ICON_ONLY") == "":
		_new_stage(false)
		_build_track()
		_build_cars()
		_build_title()

		# The key art, with and without the title.
		_camera.position = Vector3(8, 26, 96)
		_camera.look_at(Vector3(0, 6, -170), Vector3.UP)
		_title.visible = true
		await _save("res://art/splash.png")
		_title.visible = false
		await _save("res://art/menu_bg.png")

		# The other screens' backgrounds: the same world at night, calmer, darker at the edges.
		for scene in ["garage", "tracks", "grid", "wreck"]:
			_new_stage(true)
			_build_track()
			_build_floodlights()
			call("_scene_" + scene)
			_build_vignette()
			await _save("res://art/bg_%s.png" % scene)

	# The icon: its own clean stage -- the hero car, its rope and its ring, on a transparent background
	# (tools/make_icons.py puts it on the badge and writes every size).
	if _vp != null:
		_vp.queue_free()
	_vp = SubViewport.new()
	_vp.size = Vector2i(1024, 1024)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.84, 0.95)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	_world.add_child(key)
	key.look_at_from_position(Vector3(40, 90, 70), Vector3.ZERO, Vector3.UP)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_world.add_child(_camera)
	# No ring on the icon: a thick rope running off to the side, low and slack.
	_car("f1", 0, Vector3(0, 0, 0), 0.0, 0.0, 0.0, 16.0, false, Vector3(-44, 3, 0), false, 2.2)
	_camera.position = Vector3(44, 66, 80)
	_camera.look_at(Vector3(-12, 3, 14), Vector3.UP)
	var icon := await _grab()
	icon.save_png(ProjectSettings.globalize_path("res://art/icon_render.png"))
	print("art: wrote splash.png, menu_bg.png, bg_*.png, icon_render.png")
	quit()


func _grab() -> Image:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


func _save(path: String) -> void:
	var img := await _grab()
	img.save_png(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- the world

## A fresh 1920x1080 stage (the old one is freed): sunset for the key art, night for the backgrounds.
func _new_stage(night: bool) -> void:
	if _vp != null:
		_vp.queue_free()
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_build_environment(night)


func _build_environment(night: bool) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.28, 0.62)
	sky_mat.sky_horizon_color = Color(0.95, 0.72, 0.52)
	sky_mat.ground_horizon_color = Color(0.55, 0.42, 0.3)
	sky_mat.ground_bottom_color = Color(0.12, 0.16, 0.1)
	sky_mat.sun_angle_max = 8.0
	if night:
		sky_mat.sky_top_color = Color(0.015, 0.02, 0.06)
		sky_mat.sky_horizon_color = Color(0.16, 0.12, 0.22)
		sky_mat.ground_horizon_color = Color(0.08, 0.07, 0.09)
		sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.03)
		sky_mat.sun_angle_max = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.66, 0.45)
	env.fog_density = 0.00025
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.08
	if night:
		env.ambient_light_energy = 0.6
		env.fog_light_color = Color(0.14, 0.12, 0.2)
		env.fog_density = 0.0012
		env.glow_intensity = 0.8
		env.glow_bloom = 0.05
		env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.35
	if night:
		# The moon: cool and weak; the floodlights do the rest.
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 700.0
	_world.add_child(sun)
	sun.look_at_from_position(Vector3(-160, 120, -300), Vector3(0, 0, 0), Vector3.UP)

	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.far = 3000.0
	_world.add_child(_camera)


func _build_track() -> void:
	var grass := _mat(Color(0.22, 0.44, 0.19), 0.95)
	var asphalt := _mat(Color(0.2, 0.2, 0.22), 0.9)
	var white := _mat(Color(0.94, 0.94, 0.94), 0.6)
	var dash := _mat(Color(0.85, 0.78, 0.42), 0.6)
	var red := _mat(Color(0.82, 0.16, 0.12), 0.6)
	var sand := _mat(Color(0.86, 0.75, 0.5), 1.0)
	_box(Vector3(3000, 1, 3000), Vector3(0, -0.5, -1000), grass)
	var road_w := 120.0
	var length := 1400.0
	_box(Vector3(road_w, 0.4, length), Vector3(0, 0.2, -length * 0.5 + 200), asphalt)
	for side in [-1.0, 1.0]:
		_box(Vector3(3, 0.5, length), Vector3(side * (road_w * 0.5 - 2), 0.3, -length * 0.5 + 200), white)
		# Red / white kerbs on the outside.
		for k in 90:
			var z := 200.0 - float(k) * 16.0
			_box(Vector3(7, 0.7, 8), Vector3(side * (road_w * 0.5 + 4), 0.35, z), red if k % 2 == 0 else white)
		# Sand run-off on the right.
		if side > 0.0:
			_box(Vector3(70, 0.3, 260), Vector3(road_w * 0.5 + 45, 0.15, -260), sand)
	for k in 60:
		_box(Vector3(1.6, 0.45, 10), Vector3(0, 0.25, 180.0 - float(k) * 24.0), dash)
	# Rubber: skid marks of a car that went sideways.
	var rubber := _mat(Color(0.11, 0.11, 0.12), 1.0)
	for k in 26:
		var t := float(k) / 25.0
		for off in [-9.0, 9.0]:
			var m := _box(Vector3(2.6, 0.42, 7), Vector3(-26.0 + sin(t * 3.0) * 14.0 + off, 0.22, -130.0 - t * 150.0), rubber)
			m.rotation.y = cos(t * 3.0) * 0.35
	# Distant grandstands and a gantry, low-poly silhouettes.
	var stand := _mat(Color(0.32, 0.34, 0.4), 0.8)
	for k in 6:
		_box(Vector3(90, 40 + (k % 3) * 12, 40), Vector3(-190.0 + (k % 2) * 380.0, 20 + (k % 3) * 6, -500.0 - float(k / 2) * 180.0), stand)
	var gantry := _mat(Color(0.12, 0.12, 0.14), 0.5)
	_box(Vector3(4, 70, 4), Vector3(-70, 35, -330), gantry)
	_box(Vector3(4, 70, 4), Vector3(70, 35, -330), gantry)
	_box(Vector3(148, 12, 4), Vector3(0, 66, -330), gantry)
	var chk_w := _mat(Color(0.95, 0.95, 0.95), 0.6)
	for k in 12:
		_box(Vector3(10, 5, 1), Vector3(-55.0 + float(k) * 10.0, 66 + (2.5 if k % 2 == 0 else -2.5), -327.8), chk_w)


## One racer: the game's model, placed and posed, with its rope and cursor ring.
## `pos` is where the car's centre is; it faces the camera (+Z) turned by `yaw`; `roll`/`pitch` tilt it.
func _car(style: String, color_index: int, pos: Vector3, yaw: float, roll: float, pitch: float,
		rope_ahead: float, dusty: bool, ring_offset: Vector3 = Vector3(0, 14, 0),
		with_ring: bool = false, rope_radius: float = 0.7) -> Node3D:
	var id := CarRegistry.resolve(style)
	var pal: Array = CarRegistry.get_palette(id)
	var builder := CarModel3D.new()
	root.add_child(builder)
	builder.build(CarRegistry.get_style(id), pal[color_index]["body"], pal[color_index]["stripe"])
	var model := builder.detach_model()
	builder.queue_free()
	var holder := Node3D.new()
	_world.add_child(holder)
	holder.position = pos
	model.rotation = Vector3.ZERO
	holder.add_child(model)
	# Face the viewer (+Z), then the pose: yaw about Y, roll about the car's length, pitch about its width.
	holder.rotation = Vector3(0, -PI * 0.5 + yaw, 0)
	var tilt := Node3D.new()
	holder.remove_child(model)
	holder.add_child(tilt)
	tilt.add_child(model)
	tilt.position = Vector3(0, 6, 0)
	model.position = Vector3(0, -6, 0)
	tilt.rotation = Vector3(roll, 0, pitch)
	# The rope: from the nose, forward and a little up, to the cursor ring -- sagging, taut near the car.
	var nose := tilt.to_global(Vector3(20, 0, 0) + model.position)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	# SPEC 121: the rope runs off to a cursor that is not drawn. The glowing rings it used to end in
	# ("they look like Sonic") were the one thing in the picture that was not the game.
	var ring := nose + fwd * rope_ahead + ring_offset
	_rope(nose, ring, rope_radius)
	if with_ring:
		_ring(ring, fwd)
	if dusty:
		_dust(pos - fwd * 26.0, 7)
	return holder


func _build_cars() -> void:
	# The hero: a red Formula, right in front, rope stretched to a ring past the camera's shoulder.
	_car("f1", 0, Vector3(0, 0, -34), 0.12, 0.05, 0.0, 38.0, true, Vector3(-30, 26, 0))
	# A Sport up on two wheels, leaning hard.
	_car("sport", 1, Vector3(-34, 3, -112), -0.25, -0.62, 0.0, 70.0, true, Vector3(-40, 30, 0))
	# A Grand Tourer flipping through the air.
	_car("gt", 2, Vector3(36, 30, -150), 0.5, 2.4, 0.35, 70.0, true, Vector3(45, 34, 0))
	# A Rally car sideways in a drift, sand flying.
	_car("rally", 0, Vector3(30, 0, -222), 0.75, 0.12, 0.0, 80.0, true, Vector3(30, 24, 0))
	# A Kart and a Sport further back.
	_car("kart", 3, Vector3(-18, 0, -262), -0.1, 0.0, 0.0, 90.0, false)
	_car("sport", 4, Vector3(-42, 0, -330), 0.05, 0.0, 0.0, 90.0, false)
	# One more tumbling end over end in the distance.
	_car("f1", 2, Vector3(12, 22, -380), 0.2, 1.2, 2.2, 90.0, true)


# ---------------------------------------------------------------- the night scenes

## Floodlight towers down both sides of the straight: a mast, a glowing lamp head, a warm light.
func _build_floodlights() -> void:
	var mast := _mat(Color(0.1, 0.1, 0.12), 0.6)
	var lamp := _mat(Color(1.0, 0.92, 0.75), 0.3)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.7)
	lamp.emission_energy_multiplier = 3.0
	for k in 6:
		var z := 120.0 - float(k) * 150.0
		for side in [-1.0, 1.0]:
			var x: float = side * 110.0
			_box(Vector3(3, 80, 3), Vector3(x, 40, z + side * 40.0), mast)
			_box(Vector3(16, 6, 3), Vector3(x, 82, z + side * 40.0), lamp)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.62)
			l.light_energy = 5.0
			l.omni_range = 280.0
			l.omni_attenuation = 0.9
			l.shadow_enabled = k < 3
			_world.add_child(l)
			l.position = Vector3(x * 0.8, 70, z + side * 40.0)


## A soft dark edge (and a slightly darker whole) so the panels of a screen read over the picture.
func _build_vignette() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.12))
	grad.set_color(1, Color(0, 0, 0, 0.72))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 256
	var shade := TextureRect.new()
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2.ZERO
	shade.size = Vector2(W, H)
	_vp.add_child(shade)


## The screen backgrounds are the empty circuit at night -- no cars (they would compete with the
## screens' own content); each is just a camera on the lit straight.

## Car select: low, looking across the kerb at the start / finish gantry.
func _scene_garage() -> void:
	_camera.position = Vector3(40, 48, -150)
	_camera.look_at(Vector3(-10, 6, -310), Vector3.UP)


## Track select: the straight from high above, the sand trap off to the side.
func _scene_tracks() -> void:
	_camera.position = Vector3(-150, 300, 150)
	_camera.look_at(Vector3(10, 0, -200), Vector3.UP)


## Lobby: the empty starting grid from above and behind, under the gantry.
func _scene_grid() -> void:
	_camera.position = Vector3(-60, 70, -150)
	_camera.look_at(Vector3(0, 4, -330), Vector3.UP)


## Settings: from the run-off, across the sand trap to the gantry.
func _scene_wreck() -> void:
	_camera.position = Vector3(150, 30, -150)
	_camera.look_at(Vector3(80, 6, -240), Vector3.UP)


func _rope(a: Vector3, b: Vector3, radius: float = 0.7) -> void:
	var mat := _mat(ROPE_COLOR, 0.4)
	mat.emission_enabled = true
	mat.emission = ROPE_COLOR
	mat.emission_energy_multiplier = 1.4
	var segs := 14
	var prev := a
	for k in range(1, segs + 1):
		var t := float(k) / float(segs)
		var p := a.lerp(b, t) + Vector3(0, -sin(t * PI) * a.distance_to(b) * 0.05, 0)
		var mid := (prev + p) * 0.5
		var seg_len := prev.distance_to(p)
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = seg_len
		c.radial_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(mi)
		mi.position = mid
		var dir := (p - prev).normalized()
		mi.basis = Basis(_perp(dir), dir, dir.cross(_perp(dir))).orthonormalized()
		prev = p


func _perp(v: Vector3) -> Vector3:
	var p := v.cross(Vector3.RIGHT)
	if p.length() < 0.1:
		p = v.cross(Vector3.FORWARD)
	return p.normalized()


func _ring(at: Vector3, facing: Vector3) -> void:
	var mat := _mat(RING_COLOR, 0.3)
	mat.emission_enabled = true
	mat.emission = RING_COLOR
	mat.emission_energy_multiplier = 2.2
	var t := TorusMesh.new()
	t.inner_radius = 5.0
	t.outer_radius = 6.5
	t.rings = 24
	t.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat
	_world.add_child(mi)
	mi.position = at
	# The torus lies in XZ; stand it up facing the car.
	mi.rotation = Vector3(PI * 0.5, atan2(facing.x, facing.z), 0)


func _dust(at: Vector3, n: int) -> void:
	for k in n:
		var mat := _mat(Color(0.86, 0.8, 0.68, 0.32 - float(k) * 0.03), 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var sph := SphereMesh.new()
		var r := 6.0 + float(k) * 2.2
		sph.radius = r
		sph.height = r * 2.0
		sph.radial_segments = 10
		sph.rings = 5
		var mi := MeshInstance3D.new()
		mi.mesh = sph
		mi.material_override = mat
		_world.add_child(mi)
		mi.position = at + Vector3(sin(float(k) * 2.1) * 8.0, 4.0 + float(k) * 2.5, -float(k) * 9.0)


func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_title)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.08, 0.62))
	grad.set_color(1, Color(0.02, 0.03, 0.08, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 16
	tex.height = 256
	var shade := TextureRect.new()
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(0, 0)
	shade.size = Vector2(W, 300)
	_title.add_child(shade)
	var l := Label.new()
	l.text = "ROPE RACERS"
	l.position = Vector2(0, 70)
	l.size = Vector2(W, 150)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 140)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.28))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	l.add_theme_constant_override("outline_size", 22)
	_title.add_child(l)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	_world.add_child(mi)
	mi.position = pos
	return mi
