extends Control
class_name CaptchaGame
## Миниигра Маркетолога «капча»: единая сцена (фон + объекты) разбита сеткой n×n
## (3/4/5/6 по УР). Целевой объект встречается КРУПНО и иногда мельче «на фоне»
## (как в настоящих капчах); есть объекты-обманки. Выбрать все клетки с целью и
## нажать «Проверить». Верно (полное совпадение) → буст рейтинга; иначе штраф (в мех.).
## Выделение клетки: она «утопает» (затемняется по краям) + белая рамка, с анимацией.

signal finished(ok: bool, accuracy: float)

const OBJS := {
	"ЗЕЛЬЕ":    "res://assets/market/obj_bottle.png",
	"РАКЕТА":   "res://assets/market/obj_rocket.png",
	"ПЛАНЕТА":  "res://assets/market/obj_planet.png",
	"ШЕСТЕРНЯ": "res://assets/market/obj_gear.png",
	"КОМЕТА":   "res://assets/market/obj_comet.png",
	"ЗВЕЗДА":   "res://assets/market/obj_star.png",
	"КРИСТАЛЛ": "res://assets/market/obj_crystal.png",
	"КЛЮЧ":     "res://assets/market/obj_key.png",
	"ГРИБ":     "res://assets/market/obj_mushroom.png",
}
const BGS := [
	"res://assets/market/bg_lab.png", "res://assets/market/bg_space.png",
	"res://assets/market/bg_circuit.png", "res://assets/market/bg_workshop.png",
	"res://assets/market/bg_void.png",
]
const THRESH := 0.24        # доля площади клетки под целью, чтобы считать её «верной»

var n: int = 3
var level: int = 1
var _bg: Texture2D
var _tgt: Texture2D
var _tgt_name: String = ""
var _tgt_rects: Array = []          # экземпляры цели (доли области), 1 крупный + фоновые
var _dist: Array = []               # обманки: [{tex, rect}]
var _correct: Dictionary = {}       # индекс клетки -> true
var _sel: Dictionary = {}           # выбранные клетки
var _anim: Dictionary = {}          # индекс -> прогресс анимации 0..1
var _btns: Array = []               # кнопки-клетки
var _prompt: Label
var _submit: Button
var _timer: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func set_timer(sec: float) -> void:
	if _timer != null:
		_timer.text = "ВОССОЗДАЙ — %dс" % int(ceil(maxf(sec, 0.0)))

func setup(lvl: int) -> void:
	level = lvl
	n = {1: 3, 2: 4, 3: 5, 4: 6}.get(lvl, 3)
	_bg = load(BGS[randi() % BGS.size()])
	var names: Array = OBJS.keys()
	_tgt_name = names[randi() % names.size()]
	_tgt = load(OBJS[_tgt_name])
	# крупный экземпляр цели (виден сразу), не по сетке — края клеток перекрыты частично
	var tw: float = randf_range(0.32, 0.48)
	var th: float = randf_range(0.32, 0.48)
	_tgt_rects.append(Rect2(randf_range(0.03, 0.97 - tw), randf_range(0.03, 0.97 - th), tw, th))
	# фоновые (мелкие) экземпляры цели — как «где-то на фоне ещё одна планета»
	var extra: int = 1 + (1 if lvl >= 3 else 0)      # 1..2 мелких
	for _e in extra:
		for _a in 18:
			var s: float = randf_range(0.12, 0.19)
			var cand := Rect2(randf_range(0.02, 0.98 - s), randf_range(0.02, 0.98 - s), s, s * randf_range(0.9, 1.1))
			if not _overlaps_any(cand, _tgt_rects, 0.02):
				_tgt_rects.append(cand)
				break
	# обманки (другие объекты), с УР.2 — 1..2, разного размера, не на цели
	if lvl >= 2:
		var dn: Array = names.duplicate(); dn.erase(_tgt_name)
		var dcount: int = 1 + (1 if lvl >= 3 else 0)
		for _d in dcount:
			var dtex: Texture2D = load(OBJS[dn[randi() % dn.size()]])
			for _a in 18:
				var ds: float = randf_range(0.13, 0.24)
				var cand := Rect2(randf_range(0.02, 0.98 - ds), randf_range(0.02, 0.98 - ds), ds, ds)
				if not _overlaps_any(cand, _tgt_rects, 0.03) and not _overlaps_dist(cand):
					_dist.append({"tex": dtex, "rect": cand})
					break
	_calc_correct()
	_build_ui()

func _overlaps_any(r: Rect2, arr: Array, pad: float) -> bool:
	for x in arr:
		if r.intersects((x as Rect2).grow(pad)):
			return true
	return false

func _overlaps_dist(r: Rect2) -> bool:
	for d in _dist:
		if r.intersects((d["rect"] as Rect2).grow(0.02)):
			return true
	return false

# верные клетки = перекрыты ЛЮБЫМ экземпляром цели >= THRESH площади клетки
func _calc_correct() -> void:
	_correct.clear()
	var cell: float = 1.0 / float(n)
	var best_i: int = -1
	var best_ov: float = 0.0
	for r in n:
		for c in n:
			var cr := Rect2(c * cell, r * cell, cell, cell)
			var ov: float = 0.0
			for tr in _tgt_rects:
				var inter := cr.intersection(tr)
				if inter.size.x > 0.0 and inter.size.y > 0.0:
					ov = maxf(ov, (inter.size.x * inter.size.y) / (cell * cell))
			var idx: int = r * n + c
			if ov >= THRESH:
				_correct[idx] = true
			if ov > best_ov:
				best_ov = ov; best_i = idx
	if _correct.is_empty() and best_i >= 0:
		_correct[best_i] = true

func _build_ui() -> void:
	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size", 22)
	_timer.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_timer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer.offset_top = 8.0
	_timer.offset_bottom = 34.0
	add_child(_timer)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	_prompt.text = "Выберите все клетки с: %s" % _tgt_name
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_top = 44.0
	_prompt.offset_bottom = 80.0
	add_child(_prompt)

	_submit = Button.new()
	_submit.text = "Проверить"
	_submit.focus_mode = Control.FOCUS_NONE
	_submit.add_theme_font_size_override("font_size", 22)
	_submit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_submit.offset_top = -66.0
	_submit.offset_bottom = -14.0
	_submit.offset_left = 40.0
	_submit.offset_right = -40.0
	_submit.pressed.connect(_on_submit)
	add_child(_submit)

	# клетки — настоящие кнопки-ноды (надёжный ввод вне зависимости от координат/масштаба)
	for idx in n * n:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_on_cell.bind(idx))
		add_child(b)
		_btns.append(b)
	_layout_cells()

func _on_cell(idx: int) -> void:
	if _sel.has(idx): _sel.erase(idx)
	else: _sel[idx] = true
	_anim[idx] = float(_anim.get(idx, 0.0))
	Sfx.play("uiClick")
	queue_redraw()

# расставить кнопки-клетки по текущей области сетки
func _layout_cells() -> void:
	if _btns.size() != n * n:
		return
	var a := _grid_area()
	var cw: float = a.size.x / float(n)
	var ch: float = a.size.y / float(n)
	for idx in _btns.size():
		var rr: int = idx / n
		var cc: int = idx % n
		var b: Button = _btns[idx]
		b.position = a.position + Vector2(cc * cw, rr * ch)
		b.size = Vector2(cw, ch)

# квадратная область сетки между подсказкой (сверху) и кнопкой (снизу)
func _grid_area() -> Rect2:
	var top: float = 92.0
	var bot: float = 84.0
	var avail_h: float = maxf(40.0, size.y - top - bot)
	var side: float = minf(size.x - 20.0, avail_h)
	return Rect2((size.x - side) * 0.5, top + (avail_h - side) * 0.5, side, side)

func _process(delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size        # держим капчу на весь экран
	if not size.is_equal_approx(vp):
		size = vp
		_layout_cells()
	# анимация «утопания»: к 1 если выбрана, к 0 если снята
	var done: Array = []
	for i in _anim:
		var a: float = float(_anim[i])
		var tgt: float = 1.0 if _sel.has(i) else 0.0
		a = move_toward(a, tgt, delta * 7.0)
		_anim[i] = a
		if a <= 0.001 and tgt == 0.0:
			done.append(i)
	for i in done:
		_anim.erase(i)
	queue_redraw()

# короткий итог: «Капча закрыта на N%» поверх сетки; ввод отключается
func show_result(pct: int, ok: bool) -> void:
	for b in _btns:
		b.disabled = true
	if _submit != null:
		_submit.disabled = true
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.6)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	var res := Label.new()
	res.text = "Капча закрыта на %d%%" % pct
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res.add_theme_font_size_override("font_size", 40)
	res.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65) if ok else Color(1.0, 0.65, 0.55))
	res.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(res)

func _on_submit() -> void:
	var inter: int = 0
	var uni: Dictionary = {}
	for k in _correct: uni[k] = true
	for k in _sel:
		uni[k] = true
		if _correct.has(k): inter += 1
	var acc: float = float(inter) / float(maxi(1, uni.size()))
	var ok: bool = (_sel.size() == _correct.size()) and (inter == _correct.size())
	Sfx.play("dock" if ok else "tick")
	finished.emit(ok, acc)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.10, 1.0))   # непрозрачный фон миниигры
	var a := _grid_area()
	if _bg:
		draw_texture_rect(_bg, a, false)
	# обманки, затем экземпляры цели поверх (с мягкой тенью — «вписаны» в сцену)
	var shadow := Color(0, 0, 0, 0.35)
	for d in _dist:
		var dr := Rect2(a.position + (d["rect"] as Rect2).position * a.size, (d["rect"] as Rect2).size * a.size)
		draw_texture_rect(d["tex"], Rect2(dr.position + Vector2(4, 6), dr.size), false, shadow)
		draw_texture_rect(d["tex"], dr, false)
	if _tgt:
		for tr in _tgt_rects:
			var r := Rect2(a.position + (tr as Rect2).position * a.size, (tr as Rect2).size * a.size)
			draw_texture_rect(_tgt, Rect2(r.position + Vector2(5, 7), r.size), false, shadow)
			draw_texture_rect(_tgt, r, false)
	# сетка
	var cw: float = a.size.x / float(n)
	var ch: float = a.size.y / float(n)
	var line := Color(1, 1, 1, 0.65)
	for k in range(n + 1):
		draw_line(a.position + Vector2(k * cw, 0), a.position + Vector2(k * cw, a.size.y), line, 2.0)
		draw_line(a.position + Vector2(0, k * ch), a.position + Vector2(a.size.x, k * ch), line, 2.0)
	# выбранные клетки: «утопают» (тёмная виньетка) + белая рамка. Сила берётся из
	# _sel (видно СРАЗУ), _anim лишь сглаживает появление/угасание.
	var strength: Dictionary = {}
	for i in _sel:
		strength[i] = maxf(0.55, float(_anim.get(i, 0.0)))
	for i in _anim:
		if not _sel.has(i):
			strength[i] = float(_anim[i])
	for i in strength:
		var t: float = float(strength[i])
		if t <= 0.001:
			continue
		var rr: int = int(i) / n
		var cc: int = int(i) % n
		var cell := Rect2(a.position + Vector2(cc * cw, rr * ch), Vector2(cw, ch))
		draw_rect(cell, Color(0, 0, 0, 0.34 * t))                     # «вдавленность»
		var m: float = 2.0 + 5.0 * t
		draw_rect(cell.grow(-m), Color(1, 1, 1, 0.98), false, 3.0)   # белая рамка
	# рамка всей области
	draw_rect(a, Color(1, 1, 1, 0.9), false, 3.0)
