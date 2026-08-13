extends Control
class_name GearPath
## Особый регулятор Хромого Дальнобойщика («рычаг КПП»). Порт makeGearPathWidget
## из браузерной версии: вместо вертикального слайдера — ломаная траектория
## (одна из 10 «форм передач»), рычаг таскается ПО ПУТИ, значение = доля
## пройденного пути по полилинии. Значение пишется во внешний TouchSlider через
## сигнал value_changed → скоринг/банка работают как с обычным ползунком.

signal value_changed(value: float)

# 10 форм траекторий из оригинала (TRUCKER_GEAR_PATHS, координаты в системе 0..100)
const PATHS: Array = [
	[Vector2(50,92),Vector2(50,66),Vector2(20,66),Vector2(20,40),Vector2(50,40),Vector2(50,14)],
	[Vector2(50,92),Vector2(50,70),Vector2(80,70),Vector2(80,44),Vector2(50,44),Vector2(50,18),Vector2(80,18),Vector2(80,8)],
	[Vector2(50,92),Vector2(25,80),Vector2(25,54),Vector2(75,54),Vector2(75,28),Vector2(50,16),Vector2(50,8)],
	[Vector2(50,92),Vector2(75,78),Vector2(75,52),Vector2(25,52),Vector2(25,26),Vector2(75,26),Vector2(75,8)],
	[Vector2(50,92),Vector2(50,60),Vector2(30,60),Vector2(30,36),Vector2(70,36),Vector2(70,12),Vector2(50,12),Vector2(50,8)],
	[Vector2(50,92),Vector2(20,84),Vector2(20,58),Vector2(60,58),Vector2(60,32),Vector2(35,32),Vector2(35,10),Vector2(50,10),Vector2(50,8)],
	[Vector2(50,92),Vector2(50,72),Vector2(78,72),Vector2(78,48),Vector2(22,48),Vector2(22,24),Vector2(50,24),Vector2(50,8)],
	[Vector2(50,92),Vector2(22,82),Vector2(22,56),Vector2(64,56),Vector2(64,32),Vector2(38,32),Vector2(38,10),Vector2(50,10)],
	[Vector2(50,92),Vector2(50,64),Vector2(74,64),Vector2(74,40),Vector2(26,40),Vector2(26,20),Vector2(74,20),Vector2(74,8)],
	[Vector2(50,92),Vector2(30,78),Vector2(70,78),Vector2(70,52),Vector2(30,52),Vector2(30,26),Vector2(70,26),Vector2(50,10),Vector2(50,8)],
]

var points: Array = []          # выбранная ломаная (Vector2 в системе 0..100)
var min_value: float = 0.0
var max_value: float = 100.0
var step: float = 1.0
var value: float = 0.0
var accent: Color = Color(0.90, 0.72, 0.42)   # латунь (салун-стиль)

var _cum: Array = []
var _total: float = 1.0
var _dragging: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(84, 300)

# mn/mx/st/val — как у связанного слайдера; shape_idx<0 → случайная форма
func setup(mn: float, mx: float, st: float, val: float, shape_idx: int = -1) -> void:
	min_value = mn
	max_value = mx
	step = st
	if shape_idx < 0:
		shape_idx = randi() % PATHS.size()
	points = (PATHS[shape_idx] as Array).duplicate()
	_measure()
	value = _snap(val)
	queue_redraw()

func _measure() -> void:
	_cum = [0.0]
	for i in range(1, points.size()):
		_cum.append(_cum[i - 1] + (points[i] as Vector2).distance_to(points[i - 1]))
	_total = maxf(_cum[_cum.size() - 1], 0.0001)

func _snap(v: float) -> float:
	var r: float = clampf(v, min_value, max_value)
	if step > 0.0:
		r = min_value + roundf((r - min_value) / step) * step
	return clampf(r, min_value, max_value)

func _value_to_frac(v: float) -> float:
	if max_value <= min_value:
		return 0.0
	return (v - min_value) / (max_value - min_value)

func _frac_to_value(f: float) -> float:
	return _snap(min_value + f * (max_value - min_value))

# точка на ломаной по доле пути (0..1), в системе 0..100
func _point_at_frac(frac: float) -> Vector2:
	var t: float = clampf(frac, 0.0, 1.0) * _total
	for i in range(1, points.size()):
		if t <= _cum[i] or i == points.size() - 1:
			var seg: float = maxf(_cum[i] - _cum[i - 1], 0.0001)
			var f: float = clampf((t - _cum[i - 1]) / seg, 0.0, 1.0)
			return (points[i - 1] as Vector2).lerp(points[i], f)
	return points[points.size() - 1]

# доля пути (0..1) ближайшей к p точки ломаной, p — в системе 0..100
func _frac_at(p: Vector2) -> float:
	var best_d: float = INF
	var best_f: float = 0.0
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var ab: Vector2 = b - a
		var seg2: float = maxf(ab.length_squared(), 0.0001)
		var f: float = clampf((p - a).dot(ab) / seg2, 0.0, 1.0)
		var d: float = p.distance_to(a + ab * f)
		if d < best_d:
			best_d = d
			best_f = (_cum[i - 1] + f * ab.length()) / _total
	return best_f

# квадратный «viewBox» 0..100, вписанный по центру в прямоугольник Control
func _fit() -> Vector3:                          # возвращает (offset_x, offset_y, scale)
	var s: float = minf(size.x, size.y)
	return Vector3((size.x - s) * 0.5, (size.y - s) * 0.5, maxf(s, 0.0001))

func _to_view(pos: Vector2) -> Vector2:
	var f: Vector3 = _fit()
	return Vector2((pos.x - f.x) / f.z * 100.0, (pos.y - f.y) / f.z * 100.0)

func _from_view(v: Vector2) -> Vector2:
	var f: Vector3 = _fit()
	return Vector2(f.x + v.x / 100.0 * f.z, f.y + v.y / 100.0 * f.z)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_dragging = true
			_set_from_pos(event.position)
		else:
			_dragging = false
		accept_event()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _dragging:
		_set_from_pos(event.position)
		accept_event()

func _set_from_pos(pos: Vector2) -> void:
	var v: float = _frac_to_value(_frac_at(_to_view(pos)))
	queue_redraw()
	if not is_equal_approx(v, value):
		value = v
		value_changed.emit(value)

func _draw() -> void:
	if points.size() < 2:
		return
	var sc: float = _fit().z / 100.0          # масштаб «viewBox 0..100» → пиксели
	var scr := PackedVector2Array()
	for p in points:
		scr.append(_from_view(p))
	# трек-ломаная: тёмная подложка + светлое тело (толщина от размера виджета)
	draw_polyline(scr, Color(0.16, 0.15, 0.19), 14.0 * sc, true)
	draw_polyline(scr, Color(0.34, 0.33, 0.38), 7.0 * sc, true)
	# засечки-узлы траектории
	for p in scr:
		draw_circle(p, 4.0 * sc, Color(1, 1, 1, 0.12))
	# рычаг КПП на текущем значении
	var tp: Vector2 = _from_view(_point_at_frac(_value_to_frac(value)))
	var r: float = 7.5 * sc                    # крупная тач-цель
	draw_circle(tp, r + 3.0, Color(0, 0, 0, 0.35))
	draw_circle(tp, r, accent.darkened(0.4))
	draw_circle(tp, r * 0.78, accent)
	draw_circle(tp - Vector2(r * 0.3, r * 0.3), r * 0.24, Color(1, 1, 1, 0.35))
