extends Control
class_name JarStage
## «Сцена» для банки: тёплый спот сверху + металлическая плита-подиум снизу +
## контактная тень. Даёт банке место и опору, чтобы она не висела в воздухе.
## Плита фиксированного размера → по ней читается размер банки (банка масштабом
## «объёма» растёт от основания, стоя на плите).

# Крупная банка на игре: почти во всю высоту «окна». Тюнится по скрину.
const JAR_W := 308.0
const JAR_H := 530.0
const BASE_FRAC := 0.92         # доля высоты банки до основания (== pivot в potion_jar)
# Экранный Y основания банки («стол»). Поднят — стойка выше, снизу больше места
# под регуляторы. Синхронизирован с offset передней стойки в SCENE_STATES["play"].
const TABLE_SCREEN_Y := 664.0

var jar: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)

func set_jar(j: Control) -> void:
	jar = j
	add_child(j)               # рисуется ПОВЕРХ тени (_draw идёт под детьми)
	_layout()

# Локальный Y верха стойки (перевод из экранного в координаты сцены).
func _base_local() -> float:
	return TABLE_SCREEN_Y - global_position.y

# Публично: линия стола в локальных координатах (низ «стекла окна»).
func table_line() -> float:
	return _base_local()

# Публично: прямоугольник банки в координатах сцены (для расстановки деталей и т.п.).
func jar_rect() -> Rect2:
	if jar == null:
		return Rect2()
	return Rect2(jar.position, jar.size)

func _layout() -> void:
	if jar == null:
		return
	jar.size = Vector2(JAR_W, JAR_H)
	var base_local: float = _base_local()
	jar.position = Vector2(size.x * 0.5 - JAR_W * 0.5, base_local - JAR_H * BASE_FRAC)
	queue_redraw()

# Вернуть банку на стол (после отъезда к гостю) — позиция, поворот, масштаб узла.
func reset_jar() -> void:
	if jar == null:
		return
	jar.rotation = 0.0
	jar.scale = Vector2.ONE
	_layout()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Стол даёт арт-слой (bg_for_game_table). Тут — только мягкая контактная тень
	# под основанием, чтобы банка «стояла» на арт-стойке.
	_ellipse(Vector2(size.x * 0.5, _base_local() + 2.0), 100.0, 15.0, Color(0.0, 0.0, 0.0, 0.35))

# Мягкое радиальное свечение (концентрические круги с накоплением альфы).
func _glow(c: Vector2, radius: float, col: Color) -> void:
	var steps := 26
	for i in range(steps, 0, -1):
		var t: float = float(i) / float(steps)
		draw_circle(c, radius * t, Color(col.r, col.g, col.b, (1.0 - t) * 0.05))

# Залитый эллипс (нет примитива — строим полигон).
func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a: float = TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
