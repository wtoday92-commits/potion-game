extends Control
class_name GrimeOverlay
## «Грязь» на банке (Уборщик Пятого Дока). Сетка покрытия: каждая ячейка грязная,
## палец-«губка» стирает ячейки под собой. Порт l4Janitor* (canvas destination-out).
## Перехватывает ввод. clean_fraction() — доля отмытого (для score_bonus).

const COLS := 8
const ROWS := 13

var sponge_r: float = 52.0          # радиус губки (пиксели)
var _dirty: Array = []              # ROWS*COLS bool: true = грязно
var _seed: Array = []               # на ячейку: смещение/оттенок, чтобы грязь не была ровной

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	reset()

func reset() -> void:
	_dirty.clear()
	_seed.clear()
	for i in ROWS * COLS:
		_dirty.append(true)
		_seed.append(Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(0.0, 1.0)))
	queue_redraw()

func clean_fraction() -> float:
	if _dirty.is_empty():
		return 1.0
	var cleaned := 0
	for d in _dirty:
		if not d:
			cleaned += 1
	return float(cleaned) / float(_dirty.size())

func _cell_size() -> Vector2:
	return Vector2(size.x / float(COLS), size.y / float(ROWS))

func _wipe_at(p: Vector2) -> void:
	var cs := _cell_size()
	if cs.x <= 0.0 or cs.y <= 0.0:
		return
	var changed := false
	for r in ROWS:
		for c in COLS:
			var i: int = r * COLS + c
			if not _dirty[i]:
				continue
			var s: Vector3 = _seed[i]
			var center := Vector2((c + 0.5 + s.x) * cs.x, (r + 0.5 + s.y) * cs.y)
			if center.distance_to(p) <= sponge_r:
				_dirty[i] = false
				changed = true
	if changed:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_wipe_at(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_wipe_at(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_wipe_at(event.position)
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_wipe_at(event.position)
		accept_event()

func _draw() -> void:
	var cs := _cell_size()
	var rad: float = maxf(cs.x, cs.y) * 0.82
	for r in ROWS:
		for c in COLS:
			var i: int = r * COLS + c
			if not _dirty[i]:
				continue
			var s: Vector3 = _seed[i]
			var center := Vector2((c + 0.5 + s.x) * cs.x, (r + 0.5 + s.y) * cs.y)
			# грязно-бурые кляксы с лёгким разбросом оттенка/прозрачности
			var g := 0.10 + s.z * 0.10
			draw_circle(center, rad, Color(0.16 + g, 0.13 + g * 0.7, 0.06, 0.86))
