extends Control
class_name ColorPad
## 2D-пэд «спектр × накал» (Парфюмер). По горизонтали — накал (X), по вертикали —
## спектр (Y, верх = макс). Порт l4Perfumer (прямоугольный пэд). Пишет в оба
## ползунка через сигнал changed(hue, sat). Фон = сама сетка цветов (с полом
## насыщенности 30%, как в банке), курсор — текущая точка.

signal changed(hue: float, sat: float)

var hue_min: float = 0.0
var hue_max: float = 360.0
var hue_step: float = 5.0
var sat_min: float = 0.0
var sat_max: float = 100.0
var sat_step: float = 10.0
var cur_hue: float = 0.0
var cur_sat: float = 50.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(300, 300)

func config(hmin: float, hmax: float, hstep: float, smin: float, smax: float, sstep: float, h0: float, s0: float) -> void:
	hue_min = hmin; hue_max = hmax; hue_step = hstep
	sat_min = smin; sat_max = smax; sat_step = sstep
	cur_hue = h0; cur_sat = s0
	queue_redraw()

func _snap(v: float, lo: float, hi: float, step: float) -> float:
	var r: float = clampf(v, lo, hi)
	if step > 0.0:
		r = lo + roundf((r - lo) / step) * step
	return clampf(r, lo, hi)

func _hue_frac() -> float:
	return (cur_hue - hue_min) / maxf(0.0001, hue_max - hue_min)

func _sat_frac() -> float:
	return (cur_sat - sat_min) / maxf(0.0001, sat_max - sat_min)

func _set_from_pos(p: Vector2) -> void:
	var xf: float = clampf(p.x / maxf(1.0, size.x), 0.0, 1.0)      # накал
	var yf: float = clampf(p.y / maxf(1.0, size.y), 0.0, 1.0)
	var hue: float = _snap(hue_min + (1.0 - yf) * (hue_max - hue_min), hue_min, hue_max, hue_step)
	var sat: float = _snap(sat_min + xf * (sat_max - sat_min), sat_min, sat_max, sat_step)
	if not (is_equal_approx(hue, cur_hue) and is_equal_approx(sat, cur_sat)):
		cur_hue = hue
		cur_sat = sat
		queue_redraw()
		changed.emit(hue, sat)
	else:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_set_from_pos(event.position); accept_event()
	elif event is InputEventScreenDrag:
		_set_from_pos(event.position); accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_from_pos(event.position); accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_set_from_pos(event.position); accept_event()

func _draw() -> void:
	# сетка цветов: X = накал (пол 30%, как в банке), Y = спектр (верх = макс)
	var cols := 20
	var rows := 20
	var cw: float = size.x / float(cols)
	var ch: float = size.y / float(rows)
	for r in rows:
		for c in cols:
			var xf: float = (float(c) + 0.5) / float(cols)
			var yf: float = (float(r) + 0.5) / float(rows)
			var hue_deg: float = hue_min + (1.0 - yf) * (hue_max - hue_min)
			var sat_v: float = 0.30 + xf * 0.70
			var col := Color.from_hsv(fposmod(hue_deg, 360.0) / 360.0, sat_v, 0.95)
			draw_rect(Rect2(c * cw, r * ch, cw + 1.0, ch + 1.0), col)
	# курсор на текущей точке
	var cx: float = _sat_frac() * size.x
	var cy: float = (1.0 - _hue_frac()) * size.y
	draw_circle(Vector2(cx, cy), 13.0, Color(0, 0, 0, 0.5))
	draw_circle(Vector2(cx, cy), 10.0, Color(1, 1, 1, 0.95))
	draw_circle(Vector2(cx, cy), 6.0, Color.from_hsv(fposmod(cur_hue, 360.0) / 360.0, 0.30 + _sat_frac() * 0.70, 0.95))
