extends Control
class_name VexBoard
## Доска узлов Векса: сетка 3×3 внутри банки, сгустки «магнитятся» к узлам.
## Рисует кольца-слоты; даёт позиции узлов и ближайший узел к точке. Порт l4Vex*.

var nodes: Array = []      # Vector2 — центры узлов (локальные координаты)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# area — прямоугольник ТЕЛА банки (в локальных координатах сцены); сетка 3×3
# внутри стекла банки, с отступами от стенок.
var _area: Rect2 = Rect2()
func build(area: Rect2) -> void:
	_area = area
	nodes.clear()
	var xs := [0.24, 0.5, 0.76]
	var ys := [0.22, 0.5, 0.78]
	for y in ys:
		for x in xs:
			nodes.append(area.position + Vector2(x * area.size.x, y * area.size.y))
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
	for n in nodes:
		draw_arc(n, 26.0, 0.0, TAU, 28, Color(1, 1, 1, 0.18), 3.0, true)
		draw_circle(n, 3.0, Color(1, 1, 1, 0.12))
