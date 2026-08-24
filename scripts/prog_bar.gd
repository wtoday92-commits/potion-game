extends Control
class_name ProgBar
## Полоса прогрессии «Лавка ур.N» с крупными маркерами будущих открытий.
## Мобилка: наведения нет — по ТАПУ на маркер всплывает, что откроется.
## Данные из GameData.PROG_LEVELS + текущий xp профиля.

const BAR_H := 24.0
const MARK_R := 18.0        # крупные маркеры под палец
const PAD := 26.0
const BAR_Y := 50.0         # линия полосы внутри виджета

# id механики -> человекочитаемое имя (что показать на маркере уровня)
const MECH_NAMES := {
	"collection": "Коллекция", "characters": "Персонажи",
	"tips": "Чаевые", "shop": "Магазин", "relations": "Связи NPC",
	"skill_1": "Умение", "skill_2": "Умение", "skill_3": "Умение", "skill_4": "Умение",
	"modifiers": "Модификаторы", "modifiers_new3": "Ещё модификаторы",
	"modifiers_multi": "Мультимодификаторы", "unique_items": "Уник-предметы",
}

var _markers: Array = []    # [{frac, text}]
var _fill: float = 0.0
var _level: int = 0
var _title: Label
var _xptext: Label
var _popup: PanelContainer
var _popup_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(440, BAR_Y + MARK_R + 6.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	_title.position = Vector2(PAD, 0)
	add_child(_title)

	_xptext = Label.new()
	_xptext.add_theme_font_size_override("font_size", 23)
	_xptext.modulate = Color(1, 1, 1, 0.8)
	_xptext.custom_minimum_size = Vector2(220, 0)
	_xptext.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_xptext)

	_popup = PanelContainer.new()
	_popup.visible = false
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.z_index = 200                     # поверх строки день/рейтинг, что ниже по дереву
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 1.0)   # ПОЛНОСТЬЮ непрозрачно — не сливается с фоном
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.55, 0.92, 0.95)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 8
	sb.content_margin_left = 14.0; sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0; sb.content_margin_bottom = 10.0
	_popup.add_theme_stylebox_override("panel", sb)
	_popup_label = Label.new()
	_popup_label.add_theme_font_size_override("font_size", 19)
	_popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_label.custom_minimum_size = Vector2(260, 0)
	_popup.add_child(_popup_label)
	add_child(_popup)

func refresh() -> void:
	var xp: int = int(PotionProfile.data.get("progression", {}).get("xp", 0))
	_level = GameData.prog_level(xp)
	var b: Dictionary = GameData.prog_bar(xp)
	_fill = float(b["into"]) / maxf(1.0, float(b["needed"]))
	_title.text = "Лавка ур.%d" % _level
	_xptext.text = "%d / %d" % [int(b["into"]), int(b["needed"])]

	_markers.clear()
	if _level < GameData.PROG_LEVELS.size():
		var lv: Dictionary = GameData.PROG_LEVELS[_level]
		for m in (lv["npc_marks"] as Array):
			var e: Dictionary = GameData.npc_by_id(m[1])
			_markers.append({"frac": float(m[0]), "text": "Новый гость: %s\n(ур.%d)" % [e.get("name", "?"), _level + 1]})
		# завершение уровня (100%): механики + пул/длина цикла
		var comp: Array = []
		if lv.has("cycle_days"): comp.append("цикл %d дн." % int(lv["cycle_days"]))
		if lv.has("pool_size"): comp.append("пул %d карт." % int(lv["pool_size"]))
		for mech in (lv["mechanics"] as Array):
			var mn: String = MECH_NAMES.get(mech, "")
			if mn != "": comp.append(mn)
		if comp.is_empty(): comp.append("уровень %d" % (_level + 1))
		_markers.append({"frac": 1.0, "text": "Ур.%d открывает:\n%s" % [_level + 1, ", ".join(comp)]})

	_popup.visible = false
	_xptext.position = Vector2(size.x - PAD - 220.0, 2)
	queue_redraw()

func _bar_geom() -> Dictionary:
	var x0: float = PAD
	var x1: float = size.x - PAD
	return {"x0": x0, "x1": x1, "y": BAR_Y}

func _draw() -> void:
	if size.x <= 0.0:
		return
	var g: Dictionary = _bar_geom()
	var x0: float = g["x0"]; var x1: float = g["x1"]; var y: float = g["y"]
	# фон-дорожка
	_capsule(x0, x1, y, BAR_H, Color(0.10, 0.09, 0.14, 0.95))
	# заполнение (градиент бирюза→фиолет)
	var fx: float = lerpf(x0, x1, clampf(_fill, 0.0, 1.0))
	if fx > x0 + 1.0:
		_capsule_grad(x0, fx, y, BAR_H)
	# маркеры
	for m in _markers:
		var mx: float = lerpf(x0, x1, clampf(float(m["frac"]), 0.0, 1.0))
		var reached: bool = float(m["frac"]) <= _fill
		var col: Color = Color(0.6, 0.9, 1.0) if reached else Color(0.5, 0.5, 0.62)
		draw_circle(Vector2(mx, y), MARK_R, Color(0.05, 0.05, 0.09))
		draw_circle(Vector2(mx, y), MARK_R - 3.0, col)
		if not reached:
			draw_circle(Vector2(mx, y), MARK_R - 8.0, Color(0.10, 0.09, 0.14))  # «замок» — полая точка

func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		pressed = true; pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true; pos = event.position
	if not pressed:
		return
	var i := _marker_at(pos)
	if i >= 0:
		_show_popup(i)
		accept_event()
	else:
		_popup.visible = false

func _marker_at(pos: Vector2) -> int:
	var g: Dictionary = _bar_geom()
	for idx in _markers.size():
		var mx: float = lerpf(g["x0"], g["x1"], clampf(float(_markers[idx]["frac"]), 0.0, 1.0))
		if pos.distance_to(Vector2(mx, g["y"])) <= MARK_R + 10.0:
			return idx
	return -1

func _show_popup(i: int) -> void:
	var g: Dictionary = _bar_geom()
	var mx: float = lerpf(g["x0"], g["x1"], clampf(float(_markers[i]["frac"]), 0.0, 1.0))
	_popup_label.text = str(_markers[i]["text"])
	_popup.visible = true
	_popup.reset_size()
	await get_tree().process_frame     # чтобы узнать размер после раскладки
	var pw: float = _popup.size.x
	var ph: float = _popup.size.y
	var px: float = clampf(mx - pw * 0.5, 4.0, size.x - pw - 4.0)
	var above: float = float(g["y"]) - MARK_R - ph - 6.0
	var py: float = above if above >= 0.0 else float(g["y"]) + MARK_R + 6.0   # снизу, если сверху не влезает
	_popup.position = Vector2(px, py)

# ---------- рисование ----------
func _capsule(x0: float, x1: float, y: float, h: float, col: Color) -> void:
	var r: float = h * 0.5
	draw_circle(Vector2(x0, y), r, col)
	draw_circle(Vector2(x1, y), r, col)
	draw_rect(Rect2(x0, y - r, x1 - x0, h), col)

func _capsule_grad(x0: float, x1: float, y: float, h: float) -> void:
	var r: float = h * 0.5
	var c0 := Color(0.25, 0.85, 0.95)
	var c1 := Color(0.65, 0.4, 0.95)
	var steps := 32
	for i in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var xa: float = lerpf(x0, x1, t0)
		var xb: float = lerpf(x0, x1, t1)
		draw_rect(Rect2(xa, y - r, xb - xa + 1.0, h), c0.lerp(c1, t0))
	draw_circle(Vector2(x0, y), r, c0)
	draw_circle(Vector2(x1, y), r, c1)
