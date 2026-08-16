extends Control
class_name DragPart
## Деталь Навигатора Роя — перетаскиваемая «железка» (шестерня/гайка/болт/шайба),
## нарисованная кодом (не эмодзи — иначе не видно на дефолтном шрифте). Тащишь
## пальцем; на отпускании сообщает механике (dropped), та считает детали в банке.

signal dropped(part)

const SZ := 60.0
enum { GEAR, NUT, BOLT, RING, BLOB }

var kind: int = GEAR
var home_zone: Rect2 = Rect2()   # зона «обитания» (доли слоя) — для дрейфа на УР.4
var _drag: bool = false
var _drag_snd_t: int = 0         # троттлинг звука волочения

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(SZ, SZ)
	custom_minimum_size = size
	queue_redraw()

# Обратная совместимость: раньше символ задавался эмодзи — теперь выбираем вид детали.
func set_symbol(_sym: String) -> void:
	pass

func set_kind(k: int) -> void:
	kind = k
	queue_redraw()

func is_dragging() -> bool:
	return _drag

func center() -> Vector2:
	return position + size * 0.5

func _metal() -> Array:
	# [заливка, кромка] по виду детали
	match kind:
		NUT:  return [Color("d8b45a"), Color("6b5320")]   # латунь
		BOLT: return [Color("cdd4dd"), Color("3a4048")]   # сталь
		RING: return [Color("bfc7d1"), Color("41474f")]   # серебро
		_:    return [Color("aeb7c4"), Color("343a42")]   # шестерня, сталь тёмная

func _draw() -> void:
	var ctr := size * 0.5
	var mc: Array = _metal()
	var col: Color = mc[0]
	var edge: Color = mc[1]
	var R := 21.0
	match kind:
		BLOB:
			# мягкий сгусток (Векс) — тёмная капля со светлым бликом
			draw_circle(ctr, R - 2.0, Color(0.12, 0.13, 0.17, 0.95))
			draw_arc(ctr, R - 2.0, 0.0, TAU, 32, Color(0.55, 0.6, 0.72, 0.7), 2.0, true)
			draw_circle(ctr - Vector2(5, 6), 4.5, Color(1, 1, 1, 0.35))
		GEAR:
			# зубья
			for i in 10:
				var a := TAU * float(i) / 10.0
				var dir := Vector2(cos(a), sin(a))
				var perp := Vector2(-dir.y, dir.x)
				var pts := PackedVector2Array([
					ctr + dir * (R - 2.0) + perp * 4.5,
					ctr + dir * (R - 2.0) - perp * 4.5,
					ctr + dir * (R + 6.0) - perp * 3.0,
					ctr + dir * (R + 6.0) + perp * 3.0,
				])
				draw_colored_polygon(pts, edge)
			draw_circle(ctr, R, col)
			draw_arc(ctr, R, 0.0, TAU, 40, edge, 2.5, true)
			draw_circle(ctr, 7.0, edge)
			draw_circle(ctr, 4.0, Color(0, 0, 0, 0.55))
		NUT:
			var hex := PackedVector2Array()
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.26
				hex.append(ctr + Vector2(cos(a), sin(a)) * (R + 3.0))
			draw_colored_polygon(hex, col)
			var out := hex.duplicate(); out.append(hex[0])
			draw_polyline(out, edge, 2.5, true)
			draw_circle(ctr, 8.5, edge)
			draw_circle(ctr, 5.5, Color(0, 0, 0, 0.55))
		BOLT:
			var hexb := PackedVector2Array()
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.26
				hexb.append(ctr + Vector2(cos(a), sin(a)) * (R + 2.0))
			draw_colored_polygon(hexb, col)
			var ob := hexb.duplicate(); ob.append(hexb[0])
			draw_polyline(ob, edge, 2.5, true)
			# шлиц-крест
			draw_line(ctr - Vector2(9, 0), ctr + Vector2(9, 0), edge, 3.0)
			draw_line(ctr - Vector2(0, 9), ctr + Vector2(0, 9), edge, 3.0)
		RING:
			# толстое кольцо-аннулус — центр реально пустой (дырка)
			draw_arc(ctr, R - 3.0, 0.0, TAU, 44, col, 9.0, true)
			draw_arc(ctr, R + 1.5, 0.0, TAU, 44, edge, 2.0, true)
			draw_arc(ctr, R - 7.5, 0.0, TAU, 40, edge, 2.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_drag = true
			z_index = 1
			Sfx.play("blobGrab")
		else:
			if _drag:
				_drag = false
				z_index = 0
				dropped.emit(self)
		accept_event()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _drag:
		position += event.relative
		var now: int = Time.get_ticks_msec()
		if now - _drag_snd_t > 130:      # звук волочения, троттлинг ~130мс
			_drag_snd_t = now
			Sfx.play("blobDrag")
		accept_event()
