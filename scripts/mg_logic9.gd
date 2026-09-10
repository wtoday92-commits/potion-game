extends Control
class_name Logic9Game
## Бонус-раунд Логика-9 на УР.4 (порт l4Logic9StartShooter из game.js).
## Заказ уже сдан на годноту или выше — сгустки уходят из банки наверх и
## по одному падают вниз. Внизу «самолётик» ездит за пальцем и сам стреляет.
## Доля сбитых идёт множителем к рейтингу заказа: всё сбил — плюс половина.
##
## Координаты держим долями от размера окна: тайминги перенесены из браузерной
## версии, где всё считалось в процентах, и в пикселях они разъехались бы на
## другом экране.

signal finished(hit_frac: float)

const INTRO := 2.0                 # «приготовься»: сгустки ждут наверху
const FIRE_GAP := 0.47             # самолёт стреляет сам, чтобы не было двойного тапа
const BULLET_SPEED := 1.4          # долей высоты в секунду
const BLOB_VY := Vector2(0.17, 0.27)
const BLOB_VX := 0.165             # разброс по горизонтали, доли ширины в секунду
const WALL_L := 0.12
const WALL_R := 0.88
const FLOOR_Y := 0.84              # ниже — промах
const PLANE_Y := 0.82
const HIT_X := 0.065
const HIT_Y := 0.06
const BLOB_R := 0.052              # радиус сгустка в долях ширины
const OUT_TAIL := 0.45             # пауза после последнего сгустка перед итогом

var _blobs: Array = []             # {x, y, vx, vy, alive, released, flash}
var _bullets: Array = []           # {x, y}
var _plane_x: float = 0.5
var _total: int = 0
var _shot: int = 0
var _t: float = 0.0                # время с начала раунда
var _fire_acc: float = 0.0
var _release_at: float = 0.0       # когда выпустить следующий сгусток
var _order: Array = []
var _next: int = 0
var _done: bool = false
var _tail: float = 0.0
var _hint: Label
var _score: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP       # раунд забирает весь ввод
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func setup(blob_count: int) -> void:
	_total = maxi(3, blob_count)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in _total:
		_blobs.append({
			"x": 0.22 + (float(i) + 0.5) * (0.56 / float(_total)),
			"y": 0.08,
			"vx": rng.randf_range(-BLOB_VX, BLOB_VX),
			"vy": rng.randf_range(BLOB_VY.x, BLOB_VY.y),
			"alive": true, "released": false, "flash": 0.0,
		})
	_order.resize(_total)
	for i in _total:
		_order[i] = i
	_order.shuffle()
	_build_ui()

func _build_ui() -> void:
	_hint = Label.new()
	_hint.text = "СБЕЙ СГУСТКИ — веди пальцем"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", UI.FS_L)
	_hint.add_theme_color_override("font_color", UI.GOLD)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 92.0
	_hint.offset_bottom = 92.0 + float(UI.FS_L) * 1.6
	add_child(_hint)

	_score = Label.new()
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", UI.FS_M)
	_score.add_theme_color_override("font_color", UI.TXT)
	_score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_score.add_theme_constant_override("outline_size", 5)
	_score.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_score.offset_top = _hint.offset_bottom + 6.0
	_score.offset_bottom = _score.offset_top + float(UI.FS_M) * 1.6
	add_child(_score)
	_refresh_score()

func _refresh_score() -> void:
	if _score != null:
		_score.text = "сбито %d из %d" % [_shot, _total]

# Палец ведёт самолёт: тап и протяжка в любом месте окна.
func _gui_input(event: InputEvent) -> void:
	var px: float = -1.0
	if event is InputEventScreenTouch and event.pressed:
		px = event.position.x
	elif event is InputEventScreenDrag:
		px = event.position.x
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		px = event.position.x
	elif event is InputEventMouseMotion and event.button_mask != 0:
		px = event.position.x
	if px >= 0.0 and size.x > 0.0:
		_plane_x = clampf(px / size.x, 0.10, 0.90)
		accept_event()

func _process(delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	if not size.is_equal_approx(vp):
		size = vp
	if _done:
		return
	_t += delta
	if _t < INTRO:
		queue_redraw()
		return
	_release(delta)
	_fire(delta)
	_move_bullets(delta)
	_move_blobs(delta)
	queue_redraw()
	# Раунд кончается, когда все сгустки разрешились. Небольшой хвост нужен,
	# чтобы игрок увидел последнее попадание, а не оборванный кадр.
	for b in _blobs:
		if b["alive"]:
			return
	if _next < _order.size():
		return
	_tail += delta
	if _tail >= OUT_TAIL:
		_done = true
		finished.emit(float(_shot) / float(maxi(1, _total)))

# Сгустки выпускаются вразнобой: иногда два почти подряд, иногда с паузой.
func _release(_delta: float) -> void:
	if _next >= _order.size() or _t < _release_at:
		return
	_blobs[_order[_next]]["released"] = true
	_next += 1
	var gap: float = randf_range(0.04, 0.17) if randf() < 0.35 else randf_range(0.22, 0.82)
	_release_at = _t + gap

func _fire(delta: float) -> void:
	_fire_acc -= delta
	if _fire_acc > 0.0:
		return
	_fire_acc = FIRE_GAP
	_bullets.append({"x": _plane_x, "y": PLANE_Y})
	Sfx.play("tick")

func _move_bullets(delta: float) -> void:
	var keep: Array = []
	for bl in _bullets:
		bl["y"] -= BULLET_SPEED * delta
		if bl["y"] > -0.04:
			keep.append(bl)
	_bullets = keep

func _move_blobs(delta: float) -> void:
	for b in _blobs:
		if not b["alive"] or not b["released"]:
			if b["flash"] > 0.0:
				b["flash"] = maxf(0.0, b["flash"] - delta * 3.0)
			continue
		b["y"] += b["vy"] * delta
		b["x"] += b["vx"] * delta
		if b["x"] < WALL_L:
			b["x"] = WALL_L; b["vx"] = absf(b["vx"])       # отскок от стенки банки
		elif b["x"] > WALL_R:
			b["x"] = WALL_R; b["vx"] = -absf(b["vx"])
		if b["y"] >= FLOOR_Y:
			b["alive"] = false
			b["flash"] = 1.0
			Sfx.play("badPop")
			continue
		for bl in _bullets:
			if absf(bl["x"] - b["x"]) < HIT_X and absf(bl["y"] - b["y"]) < HIT_Y:
				b["alive"] = false
				b["flash"] = 1.0
				_shot += 1
				_refresh_score()
				bl["y"] = -1.0                              # пуля израсходована
				Sfx.play("blobSnap")
				break

# ---------- отрисовка ----------
func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.07, 0.82), true)
	# полоса пола: ниже неё сгусток считается упущенным
	var fy: float = FLOOR_Y * h
	draw_line(Vector2(0.0, fy), Vector2(w, fy), Color(1, 0.36, 0.42, 0.35), 3.0)
	if _t < INTRO:
		var left: int = int(ceil(INTRO - _t))
		var f: Font = ThemeDB.fallback_font
		var txt: String = "%d" % maxi(left, 1)
		var sz: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, UI.FS_HERO)
		draw_string_outline(f, Vector2(w * 0.5 - sz.x * 0.5, h * 0.5), txt,
			HORIZONTAL_ALIGNMENT_CENTER, -1, UI.FS_HERO, 8, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(w * 0.5 - sz.x * 0.5, h * 0.5), txt,
			HORIZONTAL_ALIGNMENT_CENTER, -1, UI.FS_HERO, UI.GOLD)
	var r: float = BLOB_R * w
	for b in _blobs:
		var c := Vector2(b["x"] * w, b["y"] * h)
		if b["alive"]:
			draw_circle(c, r * 1.28, Color(0.49, 1.0, 0.42, 0.16))       # ореол
			draw_circle(c, r, Color(0.04, 0.05, 0.09, 1.0))
			draw_circle(c, r - 3.0, Color(0.49, 1.0, 0.42, 0.88))
			draw_circle(c - Vector2(r * 0.32, r * 0.32), r * 0.26, Color(1, 1, 1, 0.75))
		elif b["flash"] > 0.0:
			var k: float = b["flash"]
			draw_circle(c, r * (1.0 + (1.0 - k) * 1.1), Color(1.0, 0.85, 0.36, 0.5 * k))
	for bl in _bullets:
		var p := Vector2(bl["x"] * w, bl["y"] * h)
		draw_circle(p, 11.0, Color(1.0, 0.81, 0.36, 0.35))
		draw_circle(p, 6.0, UI.GOLD)
	_draw_plane(Vector2(_plane_x * w, PLANE_Y * h), w * 0.075)

# Самолётик: простой корпус треугольником с крыльями — эмодзи на этом фоне
# читается хуже, чем плотный силуэт.
func _draw_plane(c: Vector2, s: float) -> void:
	var body := PackedVector2Array([
		c + Vector2(0.0, -s * 0.95), c + Vector2(s * 0.42, s * 0.55), c + Vector2(-s * 0.42, s * 0.55)])
	var wing := PackedVector2Array([
		c + Vector2(-s * 1.0, s * 0.22), c + Vector2(s * 1.0, s * 0.22),
		c + Vector2(s * 0.5, s * 0.62), c + Vector2(-s * 0.5, s * 0.62)])
	draw_colored_polygon(wing, Color(0.42, 0.76, 1.0, 0.85))
	draw_colored_polygon(body, Color(0.86, 0.93, 1.0, 1.0))
	draw_circle(c + Vector2(0.0, -s * 0.2), s * 0.2, Color(0.2, 0.45, 0.75, 1.0))
