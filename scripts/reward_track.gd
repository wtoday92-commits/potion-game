extends Control
class_name RewardTrack
## Полоса поощрений цикла: по отметке на каждый день. Годно → золотой барный
## стакан, идеал → крупнее, с «дыханием» и свечением, 100% → именной стакан
## гостя. Пойло → заглушка, брак → разбитая тарелка.
##
## Яркость полосы = градация 0..4 (годно+ поднимает, брак опускает, пойло не
## трогает). Секретная 5-я градация — 5 идеалов подряд, полоса становится
## фиолетовой. Градация решает множитель рейтинга в конце цикла (см. main.gd).

const TrackShader := preload("res://shaders/reward_track.gdshader")

const BAR_H := 20.0            # высота самой полосы
const HALO_PAD := 0.28         # поле под ореол (доли высоты полосы, как в шейдере)
const SLOT := 42.0             # размер пустой отметки
const GLASS_GOOD := 40.0       # барный стакан за «годно»
const GLASS_PERFECT := 48.0    # идеал — заметно крупнее
const TOP_PAD := 4.0           # воздух над стаканами
const BOTTOM_PAD := 12.0       # воздух под стаканами — иначе полоса «лежит» на дне
const MAX_GRADE := 4

# Порядок «ценности» отметки — что рисуем и как анимируем.
const KIND_EMPTY := ""
const KIND_GOOD := "good"
const KIND_PERFECT := "perfect"
const KIND_HUNDRED := "hundred"
const KIND_SWILL := "swill"
const KIND_BAD := "bad"

var days: int = 5
var marks: Array = []          # [{kind, npc}] по дням, длиной days
var grade: int = 0             # градация 0..MAX_GRADE
var secret: bool = false       # секретная фиолетовая градация
var perfect_run: int = 0       # идеалов подряд (для секретной)

var _bar: ColorRect
var _mat: ShaderMaterial
var _slots: Array = []         # Control на каждую отметку
var _fill_shown: float = 0.0   # текущее (анимируемое) заполнение
var _glow_shown: float = 0.0
var _secret_shown: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(440, GLASS_PERFECT + TOP_PAD + BOTTOM_PAD)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = TrackShader
	_bar = ColorRect.new()
	_bar.material = _mat
	_bar.color = Color(1, 1, 1, 1)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

# ---------- построение ----------

func set_days(n: int) -> void:
	days = maxi(1, n)
	if marks.size() != days:
		marks.resize(days)
		for i in days:
			if typeof(marks[i]) != TYPE_DICTIONARY:
				marks[i] = {"kind": KIND_EMPTY, "npc": ""}
	_rebuild()

# Полный сброс на новый цикл.
func reset(n: int) -> void:
	marks = []
	for i in maxi(1, n):
		marks.append({"kind": KIND_EMPTY, "npc": ""})
	days = maxi(1, n)
	grade = 0
	secret = false
	perfect_run = 0
	_fill_shown = 0.0
	_glow_shown = 0.0
	_secret_shown = 0.0
	_rebuild()

# marks всегда длиной days — иначе отрисовка отметок уходит за границы массива.
func _ensure_marks() -> void:
	if marks.size() == days:
		return
	marks.resize(days)
	for i in days:
		if typeof(marks[i]) != TYPE_DICTIONARY:
			marks[i] = {"kind": KIND_EMPTY, "npc": ""}

func _rebuild() -> void:
	_ensure_marks()
	for s in _slots:
		if is_instance_valid(s):
			s.queue_free()
	_slots = []
	for i in days:
		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.custom_minimum_size = Vector2(SLOT, SLOT)
		add_child(slot)
		_slots.append(slot)
		_draw_slot(i, false)
	_layout()
	_push_uniforms()

func _layout() -> void:
	if _bar == null:
		return
	var pad_px: float = BAR_H * HALO_PAD
	# центр полосы держим так, чтобы под стаканами оставался BOTTOM_PAD
	var bar_y: float = size.y - BOTTOM_PAD - GLASS_PERFECT * 0.5 - BAR_H * 0.5
	_bar.position = Vector2(0.0, bar_y - pad_px)
	_bar.size = Vector2(size.x, BAR_H + pad_px * 2.0)
	if _mat != null:
		_mat.set_shader_parameter("aspect", maxf(size.x, 1.0) / maxf(BAR_H + pad_px * 2.0, 1.0))
		_mat.set_shader_parameter("pad", HALO_PAD / (1.0 + HALO_PAD * 2.0))
	for i in _slots.size():
		var s: Control = _slots[i]
		if not is_instance_valid(s):
			continue
		var cx: float = _slot_x(i)
		s.size = Vector2(SLOT, SLOT)
		s.position = Vector2(cx - SLOT * 0.5, bar_y + BAR_H * 0.5 - SLOT * 0.5)

# Центр отметки i по X: отметки равномерно вдоль полосы с отступами от торцов.
func _slot_x(i: int) -> float:
	var edge: float = maxf(SLOT * 0.5 + 6.0, size.x * 0.04)
	if days <= 1:
		return size.x * 0.5
	return edge + (size.x - edge * 2.0) * (float(i) / float(days - 1))

# ---------- отметки ----------

# Поставить отметку за день day_idx. animate=true — с анимацией установки.
func place(day_idx: int, kind: String, npc_id: String = "", animate: bool = true) -> void:
	if day_idx < 0 or day_idx >= days:
		return
	marks[day_idx] = {"kind": kind, "npc": npc_id}
	_recompute_grade()
	_draw_slot(day_idx, animate)
	_animate_fill()

# Градацию считаем по всей полосе заново — так переигровка дня (Ир) не двоит
# эффект и порядок отметок всегда даёт один и тот же результат.
func _recompute_grade() -> void:
	grade = 0
	perfect_run = 0
	secret = false
	for m in marks:
		match String(m.get("kind", KIND_EMPTY)):
			KIND_GOOD:
				grade = mini(MAX_GRADE, grade + 1)
				perfect_run = 0
			KIND_PERFECT, KIND_HUNDRED:
				grade = mini(MAX_GRADE, grade + 1)
				perfect_run += 1
				if perfect_run >= 5:
					secret = true        # 5 идеалов подряд — секретная градация
			KIND_SWILL:
				perfect_run = 0          # пойло: цвет не трогаем
			KIND_BAD:
				grade = maxi(0, grade - 1)
				perfect_run = 0

# Доля заполнения = сколько дней уже отыграно.
func _filled_frac() -> float:
	var n := 0
	for m in marks:
		if String(m.get("kind", KIND_EMPTY)) != KIND_EMPTY:
			n += 1
	if days <= 0:
		return 0.0
	# заливаем до центра последней занятой отметки (+ немного за неё)
	if n <= 0:
		return 0.0
	return clampf(_slot_x(n - 1) / maxf(size.x, 1.0) + 0.02, 0.0, 1.0)

func _animate_fill() -> void:
	var target_fill: float = _filled_frac()
	var target_glow: float = 1.0 if secret else clampf(float(grade) / float(MAX_GRADE), 0.0, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_method(_set_fill_shown, _fill_shown, target_fill, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_glow_shown, _glow_shown, target_glow, 0.7).set_trans(Tween.TRANS_SINE)
	var target_secret: float = 1.0 if secret else 0.0
	if not is_equal_approx(target_secret, _secret_shown):
		t.tween_method(_set_secret_shown, _secret_shown, target_secret, 1.1).set_trans(Tween.TRANS_SINE)
	_fill_shown = target_fill
	_glow_shown = target_glow
	_secret_shown = target_secret

func _set_fill_shown(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("fill", v)

func _set_glow_shown(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("glow", v)

func _set_secret_shown(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("secret", v)

func _push_uniforms() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("fill", _fill_shown)
	_mat.set_shader_parameter("glow", _glow_shown)
	_mat.set_shader_parameter("secret", _secret_shown)

# Перерисовать содержимое отметки (пустая лунка / стакан / заглушка / осколки).
func _draw_slot(i: int, animate: bool) -> void:
	var slot: Control = _slots[i]
	if not is_instance_valid(slot):
		return
	for c in slot.get_children():
		c.queue_free()
	var m: Dictionary = marks[i]
	var kind: String = String(m.get("kind", KIND_EMPTY))
	if kind == KIND_EMPTY:
		slot.add_child(_socket_node())
		return
	var big: bool = kind == KIND_PERFECT or kind == KIND_HUNDRED
	# свечение под идеалом — «дышит» вместе со стаканом
	if big:
		var gl := _glow_node(Color("ffe27a") if kind == KIND_PERFECT else Color("9ee7ff"))
		slot.add_child(gl)
		_breathe(gl, 1.0, 1.22, 0.32, 0.62)
	var pic := TextureRect.new()
	pic.texture = _kind_texture(kind, String(m.get("npc", "")))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz: float = GLASS_PERFECT if big else GLASS_GOOD
	pic.size = Vector2(sz, sz)
	pic.position = Vector2((SLOT - sz) * 0.5, (SLOT - sz) * 0.5)
	pic.pivot_offset = Vector2(sz, sz) * 0.5
	if pic.texture == null:                    # арта ещё нет — эмодзи-заглушка
		pic.queue_free()
		var lab := Label.new()
		lab.text = _kind_glyph(kind)
		lab.size = Vector2(SLOT, SLOT)
		lab.pivot_offset = Vector2(SLOT, SLOT) * 0.5
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", int(sz * 0.72))
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lab)
		if animate:
			_drop_in(lab)
		if big:
			_breathe(lab, 1.0, 1.06, 0.0, 0.0)
		return
	slot.add_child(pic)
	if animate:
		_drop_in(pic)
	if big:
		_breathe(pic, 1.0, 1.06, 0.0, 0.0)

# Арт может быть ещё не нарисован — грузим только существующее, иначе
# движок сыплет ошибками, а отметка честно падает на эмодзи-заглушку.
func _tex_or_null(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _kind_texture(kind: String, npc_id: String) -> Texture2D:
	match kind:
		KIND_HUNDRED:
			var t := _tex_or_null("res://assets/ui/track_glass_%s.png" % npc_id)
			return t if t != null else _tex_or_null("res://assets/ui/track_glass_gold.png")
		KIND_GOOD, KIND_PERFECT:
			return _tex_or_null("res://assets/ui/track_glass_gold.png")
		KIND_SWILL:
			return _tex_or_null("res://assets/ui/track_plug.png")
		KIND_BAD:
			return _tex_or_null("res://assets/ui/track_broken.png")
	return null

func _kind_glyph(kind: String) -> String:
	match kind:
		KIND_HUNDRED: return "🏆"
		KIND_PERFECT: return "🥂"
		KIND_GOOD: return "🥃"
		KIND_SWILL: return "🪨"
		KIND_BAD: return "💥"
	return ""

# Пустая лунка: тёмный кружок с тонкой каймой.
func _socket_node() -> Control:
	var p := Panel.new()
	var d: float = SLOT * 0.62
	p.size = Vector2(d, d)
	p.position = Vector2((SLOT - d) * 0.5, (SLOT - d) * 0.5)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.85)
	sb.set_corner_radius_all(int(d * 0.5))
	sb.set_border_width_all(2)
	sb.border_color = Color(0.55, 0.50, 0.68, 0.45)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _glow_node(col: Color) -> Control:
	var p := Panel.new()
	var d: float = SLOT * 0.94
	p.size = Vector2(d, d)
	p.position = Vector2((SLOT - d) * 0.5, (SLOT - d) * 0.5)
	p.pivot_offset = Vector2(d, d) * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.16)
	sb.set_corner_radius_all(int(d * 0.5))
	sb.shadow_color = Color(col.r, col.g, col.b, 0.5)
	sb.shadow_size = 14
	p.add_theme_stylebox_override("panel", sb)
	return p

# Стакан «падает» на отметку с отскоком.
func _drop_in(n: Control) -> void:
	var y: float = n.position.y
	n.position.y = y - 46.0
	n.modulate.a = 0.0
	n.scale = Vector2(0.7, 1.25)
	var t := n.create_tween()
	t.set_parallel(true)
	t.tween_property(n, "position:y", y, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(n, "modulate:a", 1.0, 0.18)
	t.tween_property(n, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# Бесконечное «дыхание» элемента (масштаб + опционально прозрачность).
func _breathe(n: Control, lo: float, hi: float, a_lo: float, a_hi: float) -> void:
	var t := n.create_tween()
	t.set_loops()
	if a_hi > 0.0:
		t.set_parallel(true)
	t.tween_property(n, "scale", Vector2(hi, hi), 1.1).set_trans(Tween.TRANS_SINE)
	if a_hi > 0.0:
		t.tween_property(n, "modulate:a", a_hi, 1.1).set_trans(Tween.TRANS_SINE)
		t.chain()
		t.set_parallel(true)
	t.tween_property(n, "scale", Vector2(lo, lo), 1.1).set_trans(Tween.TRANS_SINE)
	if a_hi > 0.0:
		t.tween_property(n, "modulate:a", a_lo, 1.1).set_trans(Tween.TRANS_SINE)

# ---------- итоги цикла ----------

# Эффективная градация с учётом секретной (5 = секрет).
func final_grade() -> int:
	return 5 if secret else grade

# Идеальные отметки: [{npc, kind}] — по ним начисляем бонус репутации.
func perfect_marks() -> Array:
	var out: Array = []
	for m in marks:
		var k: String = String(m.get("kind", KIND_EMPTY))
		if k == KIND_PERFECT or k == KIND_HUNDRED:
			out.append({"npc": String(m.get("npc", "")), "kind": k})
	return out
