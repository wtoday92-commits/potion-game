extends Control
class_name DossierFolder
## Закрытая папка-«дело» на столе (Инспектор Гильдии). Клик → открывает досье.
## Рисуется кодом: манильская папка с вкладкой, печатью и подписью «ДЕЛО».

signal opened

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(104, 82)
	pivot_offset = custom_minimum_size * 0.5
	var lbl := Label.new()
	lbl.text = "ДЕЛО"
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.offset_top = 10.0
	lbl.add_theme_font_size_override("font_size", UI.FS_S)
	lbl.add_theme_color_override("font_color", Color(0.28, 0.18, 0.08))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)

func _process(delta: float) -> void:
	# лёгкое «дыхание», чтобы папку заметили и захотели ткнуть
	_t += delta
	scale = Vector2.ONE * (1.0 + 0.03 * sin(_t * 2.2))

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0:
		return
	var manila := Color(0.84, 0.70, 0.40)
	var manila_d := Color(0.58, 0.44, 0.22)
	# вкладка сверху-слева
	draw_rect(Rect2(w * 0.08, 0.0, w * 0.34, h * 0.24), manila.darkened(0.08))
	# тело папки
	var body := Rect2(0.0, h * 0.16, w, h * 0.84)
	draw_rect(body, manila)
	draw_rect(body, manila_d, false, 2.0)
	# «строки» бумаги, выглядывающей из папки
	for i in 3:
		var yy := h * (0.34 + float(i) * 0.16)
		draw_line(Vector2(w * 0.14, yy), Vector2(w * 0.86, yy), Color(0.55, 0.42, 0.22, 0.5), 1.5)
	# сургучная печать
	draw_circle(Vector2(w * 0.80, h * 0.30), h * 0.12, Color(0.62, 0.16, 0.13))
	draw_arc(Vector2(w * 0.80, h * 0.30), h * 0.12, 0.0, TAU, 20, Color(0.4, 0.1, 0.08), 1.5, true)

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)) and event.pressed:
		accept_event()
		Sfx.play("uiClick")
		opened.emit()
