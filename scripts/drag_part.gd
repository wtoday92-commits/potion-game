extends Control
class_name DragPart
## Деталь Навигатора Роя — перетаскиваемая «железка», нарисованная кодом (не эмодзи —
## иначе не видно на дефолтном шрифте). У детали есть СИГНАТУРА = форма + цвет-металл,
## по ней механика отличает нужные детали от обманок. BLOB — отдельный вид для Векса.

signal dropped(part)

const SZ := 56.0
enum { GEAR, NUT, BOLT, RING, SPRING, CHIP, BLOB }
const N_SHAPE := 6      # видов-форм в пуле (BLOB не входит)
const N_COLOR := 5      # оттенков металла

var shape: int = GEAR
var tint: int = 0
var home_zone: Rect2 = Rect2()   # зона «обитания» (доли слоя) — для дрейфа на УР.4
var _drag: bool = false
var _drag_snd_t: int = 0
var _palette := [
	[Color("aeb7c4"), Color("343a42")],   # сталь
	[Color("d8b45a"), Color("6b5320")],   # латунь
	[Color("d08a5a"), Color("5a3320")],   # медь
	[Color("cfd6dd"), Color("41474f")],   # серебро
	[Color("8a94a2"), Color("262b31")],   # вороненый
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(SZ, SZ)
	custom_minimum_size = size
	queue_redraw()

func set_symbol(_sym: String) -> void:
	pass

func set_kind(k: int) -> void:
	shape = k
	queue_redraw()

func set_signature(sh: int, ti: int) -> void:
	shape = sh
	tint = ti
	queue_redraw()

func sig() -> int:
	return shape * 10 + tint

func is_dragging() -> bool:
	return _drag

func center() -> Vector2:
	return position + size * 0.5

func _cols() -> Array:
	if shape == BLOB:
		return [Color(0.12, 0.13, 0.17, 0.95), Color(0.55, 0.6, 0.72, 0.7)]
	return _palette[tint % _palette.size()]

func _draw() -> void:
	var ctr := size * 0.5
	var mc: Array = _cols()
	var col: Color = mc[0]
	var edge: Color = mc[1]
	var R := 19.0
	match shape:
		BLOB:
			draw_circle(ctr, R - 1.0, col)
			draw_arc(ctr, R - 1.0, 0.0, TAU, 32, edge, 2.0, true)
			draw_circle(ctr - Vector2(5, 6), 4.5, Color(1, 1, 1, 0.35))
		GEAR:
			for i in 10:
				var a := TAU * float(i) / 10.0
				var dir := Vector2(cos(a), sin(a))
				var perp := Vector2(-dir.y, dir.x)
				draw_colored_polygon(PackedVector2Array([
					ctr + dir * (R - 2.0) + perp * 4.2, ctr + dir * (R - 2.0) - perp * 4.2,
					ctr + dir * (R + 5.5) - perp * 2.8, ctr + dir * (R + 5.5) + perp * 2.8,
				]), edge)
			draw_circle(ctr, R, col)
			draw_arc(ctr, R, 0.0, TAU, 40, edge, 2.5, true)
			draw_circle(ctr, 6.5, edge)
			draw_circle(ctr, 3.5, Color(0, 0, 0, 0.55))
		NUT:
			var hex := PackedVector2Array()
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.26
				hex.append(ctr + Vector2(cos(a), sin(a)) * (R + 3.0))
			draw_colored_polygon(hex, col)
			var outp := hex.duplicate(); outp.append(hex[0])
			draw_polyline(outp, edge, 2.5, true)
			draw_circle(ctr, 8.0, edge)
			draw_circle(ctr, 5.0, Color(0, 0, 0, 0.55))
		BOLT:
			var hexb := PackedVector2Array()
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.26
				hexb.append(ctr + Vector2(cos(a), sin(a)) * (R + 1.5))
			draw_colored_polygon(hexb, col)
			var ob := hexb.duplicate(); ob.append(hexb[0])
			draw_polyline(ob, edge, 2.5, true)
			draw_line(ctr - Vector2(8, 0), ctr + Vector2(8, 0), edge, 3.0)
			draw_line(ctr - Vector2(0, 8), ctr + Vector2(0, 8), edge, 3.0)
		RING:
			draw_arc(ctr, R - 2.0, 0.0, TAU, 44, col, 8.0, true)
			draw_arc(ctr, R + 2.0, 0.0, TAU, 44, edge, 2.0, true)
			draw_arc(ctr, R - 6.0, 0.0, TAU, 40, edge, 2.0, true)
		SPRING:
			var pts := PackedVector2Array()
			var top := ctr.y - 16.0
			for j in 25:
				var t := float(j) / 24.0
				pts.append(Vector2(ctr.x + 12.0 * sin(t * TAU * 3.5), top + t * 32.0))
			draw_polyline(pts, edge, 5.0, true)
			draw_polyline(pts, col, 3.0, true)
		CHIP:
			var half := 14.0
			for j in 4:
				var yy := ctr.y - 9.0 + float(j) * 6.0
				draw_rect(Rect2(ctr.x - half - 5.0, yy - 1.5, 5.0, 3.0), edge)
				draw_rect(Rect2(ctr.x + half, yy - 1.5, 5.0, 3.0), edge)
			var body := Rect2(ctr - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
			draw_rect(body, col)
			draw_rect(body, edge, false, 2.0)
			draw_circle(ctr - Vector2(half - 5.0, half - 5.0), 2.5, edge)

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
		if now - _drag_snd_t > 130:
			_drag_snd_t = now
			Sfx.play("blobDrag")
		accept_event()
