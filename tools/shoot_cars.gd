extends SceneTree
## Renders every car model twice -- whole, and after a few panels have been knocked off -- into one PNG,
## so the new inner parts (SPEC 51: the engine under the bonnet, the seats and cage under the roof) can be
## looked at rather than guessed at.
##
##   godot --path . --script res://tools/shoot_cars.gd -- --out build/shots/cars.png

const CELL := 160
const PAD := 8


func _init() -> void:
	var out := "build/shots/cars.png"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == "--out" and i + 1 < args.size():
			out = String(args[i + 1])
	await process_frame
	var ids: PackedStringArray = CarRegistry.ids()
	var sheet := Image.create(CELL * ids.size() + PAD * (ids.size() + 1), CELL * 2 + PAD * 3,
			false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.13, 0.15))
	for i in ids.size():
		var id := ids[i]
		var model := CarModel3D.new()
		root.add_child(model)
		model.set_view(46.0, CELL, 26.0)
		model.build(CarRegistry.get_style(id), Color(0.24, 0.52, 0.88), Color(0.95, 0.95, 0.95))
		model.pose(0.0, 0.0, 0.0, 0.0, 0.0, PackedFloat32Array([0, 0, 0, 0]), 0.0, 0.0)
		await process_frame
		await process_frame
		_blit(sheet, model, Vector2i(PAD + i * (CELL + PAD), PAD))
		# Knock the bonnet and the roof off (a hit from the front, then from behind and above).
		for k in 3:
			model.detach_part(Vector2(1.0, 0.0))
		for k in 3:
			model.detach_part(Vector2(-1.0, 0.0))
		model.set_tyre_burst(0, true)
		model.dent(Vector2(1.0, 0.3), 1.0)
		await process_frame
		await process_frame
		_blit(sheet, model, Vector2i(PAD + i * (CELL + PAD), PAD * 2 + CELL))
		model.queue_free()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("wrote ", out)
	quit()


func _blit(sheet: Image, model: CarModel3D, at: Vector2i) -> void:
	var img := model.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
