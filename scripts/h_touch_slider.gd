extends Control
class_name HTouchSlider
## Крупный ГОРИЗОНТАЛЬНЫЙ слайдер под палец: вся полоса — зона попадания, ручка едет
## за пальцем (точно попадать не нужно). Левый край = минимум, правый = максимум.
## API-совместим в нужном объёме: min_value/max_value/step/value, value_changed,
## set_value_no_signal, editable.

signal value_changed(value: float)

@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var step: float = 0.001
@export var value: float = 0.0:
	set(v):
		value = _snap(v)
		queue_redraw()
@export var editable: bool = true
@export var accent: Color = Color(0.95, 0.78, 0.42)

const TRACK_H := 16.0        # толщина дорожки
const KNOB_R := 26.0         # радиус ручки (крупная тач-цель)
const PAD := KNOB_R + 4.0

var _dragging: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(300, 64)

func set_value_no_signal(v: float) -> void:
	value = _snap(v)
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
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_dragging = true
			_set_from_x(event.position.x)
		else:
			_dragging = false
		accept_event()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _dragging:
		_set_from_x(event.position.x)
		accept_event()

func _set_from_x(x: float) -> void:
	var usable: float = maxf(1.0, size.x - PAD * 2.0)
	var frac: float = clampf((x - PAD) / usable, 0.0, 1.0)   # лево=min, право=max
	var v: float = _snap(min_value + frac * (max_value - min_value))
	if not is_equal_approx(v, value):
		value = v
		value_changed.emit(value)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cy: float = h * 0.5
	var left: float = PAD
	var right: float = w - PAD
	var usable: float = maxf(1.0, right - left)
	var knob_x: float = left + _frac() * usable
	# зона-аффорданс (вся полоса кликабельна)
	draw_rect(Rect2(0.0, cy - KNOB_R - 2.0, w, (KNOB_R + 2.0) * 2.0), Color(1, 1, 1, 0.05), true)
	# дорожка
	_capsule_h(left, right, cy, TRACK_H, Color(0.16, 0.15, 0.19))
	_capsule_h(left, right, cy, TRACK_H - 6.0, Color(0.34, 0.33, 0.38))
	# заполненная часть
	_capsule_h(left, knob_x, cy, TRACK_H - 6.0, accent.darkened(0.25))
	# ручка (крупная)
	draw_circle(Vector2(knob_x, cy + 3.0), KNOB_R, Color(0, 0, 0, 0.3))       # тень
	draw_circle(Vector2(knob_x, cy), KNOB_R, accent.darkened(0.4))
	draw_circle(Vector2(knob_x, cy), KNOB_R - 4.0, accent)
	draw_circle(Vector2(knob_x - KNOB_R * 0.3, cy - KNOB_R * 0.3), KNOB_R * 0.28, Color(1, 1, 1, 0.35))  # блик

func _capsule_h(x1: float, x2: float, cy: float, thick: float, col: Color) -> void:
	var r: float = thick * 0.5
	var a: float = minf(x1, x2)
	var b: float = maxf(x1, x2)
	draw_circle(Vector2(a, cy), r, col)
	draw_circle(Vector2(b, cy), r, col)
	draw_rect(Rect2(a, cy - r, b - a, thick), col)
