extends Control
class_name VexBoard
## Доска узлов Векса: сетка cols×rows ВНУТРИ жидкости банки, сгустки «магнитятся»
## к узлам. Доска вешается в качающийся узел банки (sway) → живёт и качается внутри
## сосуда. Рисует слоты-гнёзда и подсвечивает ближайший узел. Порт l4Vex*.

var nodes: Array = []      # Vector2 — центры узлов (локальные координаты банки)
var hot: int = -1          # узел под пальцем (подсветка при перетаскивании)
var _cols: int = 3
var _rows: int = 3
var r_ring: float = 16.0   # радиус кольца-гнезда (по размеру ячейки)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# area — прямоугольник ЗОНЫ ЖИДКОСТИ в локальных координатах банки; cols×rows узлов
# равномерно по ячейкам (центры ячеек), чтобы сетка всегда была внутри жидкости.
var _area: Rect2 = Rect2()
func build(area: Rect2, cols: int, rows: int) -> void:
	_area = area
	_cols = maxi(1, cols)
	_rows = maxi(1, rows)
	nodes.clear()
	for r in _rows:
		var fy: float = (float(r) + 0.5) / float(_rows)
		for c in _cols:
			var fx: float = (float(c) + 0.5) / float(_cols)
			nodes.append(area.position + Vector2(fx * area.size.x, fy * area.size.y))
	# кольцо ≈ 38% меньшего шага ячейки (не наползают, читаются как гнёзда)
	var stepx: float = area.size.x / float(_cols)
	var stepy: float = area.size.y / float(_rows)
	r_ring = clampf(minf(stepx, stepy) * 0.38, 9.0, 20.0)
	queue_redraw()

func set_hot(i: int) -> void:
	if i != hot:
		hot = i
		queue_redraw()

func nearest_index(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in nodes.size():
		var d: float = p.distance_to(nodes[i])
		if d < best_d:
			best_d = d
			best = i
	return best

func _draw() -> void:
	if nodes.is_empty():
		return
	# тонкая соединительная решётка (ряды/столбцы) — читается как «доска» внутри зелья
	var line_c := Color(1, 1, 1, 0.09)
	for r in _rows:
		draw_line(nodes[r * _cols], nodes[r * _cols + _cols - 1], line_c, 1.5, true)
	for c in _cols:
		draw_line(nodes[c], nodes[c + (_rows - 1) * _cols], line_c, 1.5, true)
	# гнёзда: тёмное гало (контраст поверх зелья) + светлое кольцо + центр
	for i in nodes.size():
		var n: Vector2 = nodes[i]
		var is_hot: bool = (i == hot)
		draw_arc(n, r_ring + 1.0, 0.0, TAU, 26, Color(0, 0, 0, 0.28), 3.0, true)
		if is_hot:
			draw_circle(n, r_ring, Color(0.55, 0.85, 1.0, 0.20))
			draw_arc(n, r_ring, 0.0, TAU, 26, Color(0.6, 0.9, 1.0, 0.95), 3.0, true)
		else:
			draw_arc(n, r_ring, 0.0, TAU, 26, Color(1, 1, 1, 0.45), 2.0, true)
		draw_circle(n, 2.0, Color(1, 1, 1, 0.45 if is_hot else 0.22))
