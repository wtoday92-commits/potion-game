extends Node
func _ready() -> void:
	var m: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m)
	for i in 12:
		await get_tree().process_frame
	m.start_panel.visible = false
	m.collection_panel.visible = false
	m.npc = GameData.npc_by_id("janitor")
	m._start_round(3)
	await get_tree().create_timer(1.0).timeout
	print("окно: ширина ", m.jar_stage.size.x, " линия стола ", m.jar_stage.table_line())
	for ch in m.jar_stage.get_children():
		if ch is GrimeOverlay:
			print("грязь: размер ", ch.size, " губка r=", ch.sponge_r, " доля грязных ячеек ", "%.2f" % (1.0 - ch.clean_fraction()))
	print("ALL DONE")
	get_tree().quit()
