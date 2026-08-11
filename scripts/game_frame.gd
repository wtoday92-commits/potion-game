extends Control
## Металлическая рамка-обрамление всей игры (салун-стиль): болтовая кайма по
## краю экрана с бевелом, гравировкой и заклёпками. Рисуется кодом, тянется под
## любой размер. Клики не перехватывает (mouse_filter = ignore).

const T := 26.0   # толщина рамки

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	var metal := Color(0.15, 0.13, 0.11)      # тёмный тёплый металл
	var metal_hi := Color(0.31, 0.26, 0.21)   # блик (верх/лево)
	var metal_lo := Color(0.07, 0.06, 0.05)   # тень (низ/право)
	var engrave := Color(0.42, 0.35, 0.27)    # гравированная кайма

	# 4 полосы рамки
	draw_rect(Rect2(0.0, 0.0, w, T), metal)
	draw_rect(Rect2(0.0, h - T, w, T), metal)
	draw_rect(Rect2(0.0, 0.0, T, h), metal)
	draw_rect(Rect2(w - T, 0.0, T, h), metal)

	# бевел: светлая кромка снаружи сверху/слева, тёмная снизу/справа
	draw_rect(Rect2(0.0, 0.0, w, 4.0), metal_hi)
	draw_rect(Rect2(0.0, 0.0, 4.0, h), metal_hi)
	draw_rect(Rect2(0.0, h - 4.0, w, 4.0), metal_lo)
	draw_rect(Rect2(w - 4.0, 0.0, 4.0, h), metal_lo)

	# гравированная внутренняя кайма (двойная линия — как на плашке)
	draw_rect(Rect2(T - 2.0, T - 2.0, w - 2.0 * (T - 2.0), h - 2.0 * (T - 2.0)), engrave, false, 2.0)
	draw_rect(Rect2(T - 7.0, T - 7.0, w - 2.0 * (T - 7.0), h - 2.0 * (T - 7.0)), metal_lo, false, 1.0)

	# заклёпки: 4 угла + середины сторон
	var inset: float = T * 0.5
	var bolts: Array = [
		Vector2(inset, inset), Vector2(w - inset, inset),
		Vector2(inset, h - inset), Vector2(w - inset, h - inset),
		Vector2(w * 0.5, inset), Vector2(w * 0.5, h - inset),
		Vector2(inset, h * 0.5), Vector2(w - inset, h * 0.5),
	]
	for p in bolts:
		_bolt(p)

func _bolt(p: Vector2) -> void:
	draw_circle(p, 7.0, Color(0.06, 0.05, 0.04))              # гнездо/тень
	draw_circle(p, 5.2, Color(0.33, 0.29, 0.24))              # шляпка
	draw_circle(p + Vector2(-1.5, -1.5), 2.0, Color(0.52, 0.46, 0.38))  # блик
	draw_line(p + Vector2(-3.2, 0.0), p + Vector2(3.2, 0.0), Color(0.10, 0.09, 0.07), 1.3)  # шлиц
	draw_line(p + Vector2(0.0, -3.2), p + Vector2(0.0, 3.2), Color(0.10, 0.09, 0.07), 1.3)
