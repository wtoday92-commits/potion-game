extends Control
class_name TouchSlider
## Крупный вертикальный слайдер под палец. В отличие от VSlider, вся колонка —
## зона попадания: тянешь/тапаешь где угодно по высоте, ручка едет за пальцем
## (точно попадать в маленькую ручку не нужно). API совместим с VSlider в тех
## местах, что нужны игре: min_value/max_value/step/value, сигнал value_changed,
## set_value_no_signal(), editable. Верх колонки = максимум, низ = минимум.

signal value_changed(value: float)

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var step: float = 1.0
@export var value: float = 0.0:
	set(v):
		value = _snap(v)
		queue_redraw()
@export var editable: bool = true
@export var accent: Color = Color(0.90, 0.72, 0.42)   # латунь (салун-стиль)
@export var hue_track: bool = false                   # дорожка = радужный спектр

const TRACK_W := 26.0        # толщина ножки-стойки
const TRACK_W_HUE := 40.0    # спектр-ножка толще — чтобы читалась радуга
const KNOB_R := 30.0         # радиус сиденья (крупная тач-цель)
const PAD := KNOB_R + 4.0    # вертикальный отступ, чтобы сиденье не срезалось

func _pole_w() -> float:
	return TRACK_W_HUE if hue_track else TRACK_W

var _dragging: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(76, 300)

func set_value_no_signal(v: float) -> void:
	value = _snap(v)      # сеттер уже перерисует
	queue_redraw()

func _snap(v: float) -> float:
	var r: float = clampf(v, min_value, max_value)
	if step > 0.0:
		r = min_value + roundf((r - min_value) / step) * step
	return clampf(r, min_value, max_value)

func _frac() -> float:
	if max_value <= min_value:
		return 0.0
	return (value - min_value) / (max_value - min_value)

func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_set_from_y(event.position.y)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		_set_from_y(event.position.y)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_set_from_y(event.position.y)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_y(event.position.y)
		accept_event()

func _set_from_y(y: float) -> void:
	var usable: float = maxf(1.0, size.y - PAD * 2.0)
	var frac: float = clampf(1.0 - (y - PAD) / usable, 0.0, 1.0)  # верх=max, низ=min
	var v: float = _snap(min_value + frac * (max_value - min_value))
	if not is_equal_approx(v, value):
		value = v
		value_changed.emit(value)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cx: float = w * 0.5
	var top: float = PAD
	var bot: float = h - PAD
	var usable: float = maxf(1.0, bot - top)
	var knob_y: float = bot - _frac() * usable

	# фон-колонка: показывает, что тянуть можно по всей высоте (тач-аффорданс)
	_capsule(cx, top - KNOB_R * 0.4, bot + KNOB_R * 0.4, KNOB_R + 2.0, Color(1, 1, 1, 0.05))

	# --- НОЖКА СТУЛА (стойка) ---
	var metal := Color(0.34, 0.33, 0.38)
	var metal_dark := Color(0.16, 0.15, 0.19)
	var pole_w: float = _pole_w()
	if hue_track:
		_capsule_hue(cx, top, bot, pole_w)                        # спектр-стойка (толще)
	else:
		_capsule(cx, top, bot, pole_w, metal_dark)
		_capsule(cx, top, bot, pole_w - 6.0, metal)               # тело
		draw_line(Vector2(cx - 3.0, top + 4.0), Vector2(cx - 3.0, bot - 4.0), Color(1, 1, 1, 0.12), 2.0)  # блик

	# перекладина-подножка ближе к низу
	var foot_y: float = bot - usable * 0.16
	draw_arc(Vector2(cx, foot_y), 22.0, 0.15 * PI, 0.85 * PI, 20, metal_dark, 4.0, true)
	draw_arc(Vector2(cx, foot_y - 1.0), 22.0, 0.15 * PI, 0.85 * PI, 20, metal, 2.0, true)
	# опора-основание
	_ellipse(Vector2(cx, bot + 2.0), 18.0, 6.0, metal_dark)

	# --- СИДЕНЬЕ (ручка): едет по ножке, крупная тач-цель ---
	var seat_col: Color = Color.from_hsv(_frac(), 0.72, 0.95) if hue_track else accent
	var sr: float = KNOB_R + 3.0        # радиус сиденья по X
	var sy: float = KNOB_R * 0.5        # «толщина» эллипса по Y
	# кронштейн ножки под сиденьем
	draw_rect(Rect2(cx - 4.0, knob_y, 8.0, 14.0), metal_dark)
	# бок сиденья (толщина) + тень
	_ellipse(Vector2(cx, knob_y + sy * 0.7 + 3.0), sr, sy, Color(0, 0, 0, 0.3))
	_ellipse(Vector2(cx, knob_y + sy * 0.55), sr, sy, seat_col.darkened(0.45))
	# верх сиденья + кайма + пуговица + блик
	_ellipse(Vector2(cx, knob_y), sr, sy, seat_col)
	_ellipse(Vector2(cx, knob_y), sr * 0.82, sy * 0.78, seat_col.lightened(0.12))
	draw_circle(Vector2(cx, knob_y), 3.0, seat_col.darkened(0.35))                  # пуговица-тафтинг
	_ellipse(Vector2(cx - sr * 0.32, knob_y - sy * 0.35), sr * 0.22, sy * 0.3, Color(1, 1, 1, 0.28))  # блик

# Вертикальная «капсула» (скруглённый столбик) от y1 до y2 заданной ширины.
func _capsule(cx: float, y1: float, y2: float, width: float, col: Color) -> void:
	var r: float = width * 0.5
	var a: float = minf(y1, y2)
	var b: float = maxf(y1, y2)
	draw_circle(Vector2(cx, a), r, col)
	draw_circle(Vector2(cx, b), r, col)
	draw_rect(Rect2(cx - r, a, width, b - a), col)

# Дорожка-спектр: скруглённый столбик, залитый радужным градиентом по высоте
# (низ = оттенок 0, верх = оттенок 1). Рисуется полосами + скруглённые концы.
func _capsule_hue(cx: float, top: float, bot: float, width: float) -> void:
	var r: float = width * 0.5
	var steps: int = 48
	for i in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var y_a: float = lerpf(bot, top, t0)   # низ → верх
		var y_b: float = lerpf(bot, top, t1)
		var col := Color.from_hsv(t0, 0.72, 0.95)
		draw_rect(Rect2(cx - r, minf(y_a, y_b), width, absf(y_b - y_a) + 1.0), col)
	# скруглённые концы под цвет краёв
	draw_circle(Vector2(cx, bot), r, Color.from_hsv(0.0, 0.72, 0.95))
	draw_circle(Vector2(cx, top), r, Color.from_hsv(1.0, 0.72, 0.95))

# Залитый эллипс (нет примитива — строим полигон). Для сиденья/опоры стула.
func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a: float = TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
