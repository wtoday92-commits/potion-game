extends Control
class_name BadBubble
## «Плохой» пузырь Дрона: растёт со временем, надо лопнуть тапом до взрыва.
## Лопнул игрок → cleared; дорос сам → burst (сбивает регулятор). Порт badBubble*.

signal cleared(b)
signal burst(b)

var grow: float = 2.6           # за сколько секунд дорастает до взрыва
const R0 := 10.0
const R1 := 44.0

var _t: float = 0.0
var _done: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(R1 * 2.0, R1 * 2.0)
	size = Vector2(R1 * 2.0, R1 * 2.0)

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	queue_redraw()
	if _t >= grow:
		_done = true
		burst.emit(self)

func _gui_input(event: InputEvent) -> void:
	var hit := false
	if event is InputEventScreenTouch and event.pressed:
		hit = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hit = true
	if hit and not _done:
		_done = true
		accept_event()
		cleared.emit(self)

func _draw() -> void:
	var p: float = clampf(_t / grow, 0.0, 1.0)
	var r: float = lerpf(R0, R1, p)
	var c := Vector2(R1, R1)
	# чем ближе к взрыву — тем ярче/тревожнее (красный)
	var a: float = 0.45 + 0.4 * p
	draw_circle(c, r, Color(0.9, 0.15, 0.2, a))
	draw_circle(c, r * 0.62, Color(1.0, 0.5, 0.3, a))
	draw_circle(c - Vector2(r * 0.25, r * 0.25), r * 0.18, Color(1, 1, 1, 0.5))
