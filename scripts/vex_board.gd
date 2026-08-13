extends Control
class_name VexBoard
## Доска узлов Векса: сетка 3×3 внутри банки, сгустки «магнитятся» к узлам.
## Рисует кольца-слоты; даёт позиции узлов и ближайший узел к точке. Порт l4Vex*.

var nodes: Array = []      # Vector2 — центры узлов (локальные координаты)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# sz — размер области сцены (jar_stage.size); узлы в центральной зоне банки
func build(sz: Vector2) -> void:
	nodes.clear()
	var xs := [0.36, 0.50, 0.64]
	var ys := [0.46, 0.62, 0.78]
	for y in ys:
		for x in xs:
			nodes.append(Vector2(x * sz.x, y * sz.y))
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
