extends Control
## Верхний слой деревянной рамки портрета: тёмная внутренняя тень по проёму
## (вокруг портрета) + гвозди по углам. Рисуется поверх дерева и портрета.

const INSET := 16.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	# тень по внутреннему проёму (портрет как будто утоплен в рамку)
	draw_rect(Rect2(INSET - 3.0, INSET - 3.0, w - 2.0 * (INSET - 3.0), h - 2.0 * (INSET - 3.0)),
		Color(0.0, 0.0, 0.0, 0.5), false, 3.0)
	# внешняя тёмная кромка дерева
	draw_rect(Rect2(1.0, 1.0, w - 2.0, h - 2.0), Color(0.10, 0.06, 0.03, 0.9), false, 2.0)
	# гвозди по углам
	var d: float = 10.0
	for p in [Vector2(d, d), Vector2(w - d, d), Vector2(d, h - d), Vector2(w - d, h - d)]:
		draw_circle(p, 4.2, Color(0.08, 0.05, 0.03))
		draw_circle(p, 2.6, Color(0.5, 0.44, 0.36))
		draw_circle(p + Vector2(-0.8, -0.8), 1.1, Color(0.72, 0.66, 0.56))
