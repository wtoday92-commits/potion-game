extends Control
## Этап 2: экран выбора (персонаж + сложность УР.1-4) и разный набор
## доступных ползунков по уровню. Цикл раунда — как в этапе 1
## (ЗАПОМНИ -> ВОССОЗДАЙ с таймерами -> РЕЙТИНГ).

const PotionJarScene := preload("res://scenes/potion_jar.tscn")
const GameFrameScene := preload("res://scenes/game_frame.tscn")
const WoodShader := preload("res://shaders/wood.gdshader")
const PortraitEdge := preload("res://scripts/portrait_edge.gd")

func _make_wood_material(planks_val: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WoodShader
	m.set_shader_parameter("planks", planks_val)
	return m

# Параметры зелья. count.min = 1 (нулевых сгустков не бывает).
const PARAMS := {
	"color":  {"min": 0.0,  "max": 360.0, "step": 5.0, "weight": 1.0, "label": "Спектр",  "suffix": "°"},
	"volume": {"min": 10.0, "max": 100.0, "step": 1.0, "weight": 1.0, "label": "Объём",   "suffix": "%"},
	"count":  {"min": 1.0,  "max": 12.0,  "step": 1.0, "weight": 0.8, "label": "Сгустки", "suffix": ""},
	"bsize":  {"min": 10.0, "max": 100.0, "step": 2.0, "weight": 0.6, "label": "Размер",  "suffix": "%"},
}
const ORDER: Array = ["color", "volume", "count", "bsize"]

# Какие ползунки активны (доступны и учитываются) на каждом уровне сложности.
const ACTIVE := {
	1: ["color", "volume"],
	2: ["color", "volume", "count"],
	3: ["color", "volume", "count", "bsize"],
	4: ["color", "volume", "count", "bsize"],
}
const LEVEL_DESC := {
	1: "УР.1 — цвет + объём",
	2: "УР.2 — + сгустки",
	3: "УР.3 — + размер сгустка",
	4: "УР.4 — всё + механика (скоро)",
}

# Персонажи (этап 3 вынесет в ресурсы .tres). img — файл портрета в assets/npc/,
# emoji — фолбэк, если текстура ещё не импортирована Godot.
const NPCS := [
	{"img": "drone",       "emoji": "🛰", "name": "Служебный дрон",      "flavor": "Смесь для смазки шлюза. Стандарт."},
	{"img": "tentacloid",  "emoji": "🐙", "name": "Тентаклоид",           "flavor": "Что-нибудь... со вкусом. Удиви."},
	{"img": "gurman",      "emoji": "👽", "name": "Гурман с Веги",        "flavor": "Три глаза — три придирки."},
	{"img": "dj",          "emoji": "🎧", "name": "Диджей Пульсар",       "flavor": "Дай что-нибудь под бит."},
	{"img": "janitor",     "emoji": "🪣", "name": "Уборщик Пятого Дока",  "flavor": "Ведро смеси. Только не пахучую."},
	{"img": "bip",         "emoji": "📦", "name": "Стажёр Бип",           "flavor": "Э-это мой первый заказ... Любую?"},
	{"img": "khrom",       "emoji": "🚚", "name": "Дальнобойщик Хром",    "flavor": "Залей чего-нибудь. Время — топливо."},
	{"img": "fashionista", "emoji": "💅", "name": "Модница с Кассиопеи",  "flavor": "Мне — только по последней моде."},
	{"img": "collector",   "emoji": "🔍", "name": "Коллекционер Гз",      "flavor": "Ищу одну, совершенно определённую."},
	{"img": "kai",         "emoji": "🏎", "name": "Гонщица Кай",          "flavor": "Быстро. Очень быстро."},
]

const MEMORIZE_S := 2.5
const CRAFT_S := 14.0
const GOOD := 0.80
const PERFECT := 0.95

var target: Dictionary = {}
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var slider_cols: Dictionary = {}
var active: Array = []
var level: int = 1
var npc: Dictionary = {}

var round_ui: VBoxContainer
var jar: Control
var phase_label: Label
var phase_bar: ProgressBar
var select_panel: Control
var npc_portrait: Label
var npc_portrait_tex: TextureRect
var npc_name: Label
var npc_flavor: Label
var result_panel: Control
var result_sticker: Label
var result_detail: Label

var seed_val: int = 0
var phase: String = "select"
var phase_left: float = 0.0
var phase_total: float = 1.0

func _ready() -> void:
	randomize()
	_build_ui()
	_show_select()

# ---------- построение интерфейса ----------
func _build_ui() -> void:
	# фон — временная нейтральная заливка (свой фон поставишь позже, генерацией)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.06, 0.06, 0.085)
	add_child(bg)

	# ---- UI раунда ----
	round_ui = VBoxContainer.new()
	round_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	round_ui.offset_left = 36.0
	round_ui.offset_top = 36.0
	round_ui.offset_right = -36.0
	round_ui.offset_bottom = -36.0
	round_ui.add_theme_constant_override("separation", 14)
	add_child(round_ui)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 28)
	round_ui.add_child(phase_label)

	phase_bar = ProgressBar.new()
	phase_bar.custom_minimum_size = Vector2(0, 14)
	phase_bar.min_value = 0.0
	phase_bar.max_value = 1.0
	phase_bar.value = 1.0
	phase_bar.show_percentage = false
	round_ui.add_child(phase_bar)

	var jar_center := CenterContainer.new()
	jar_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	round_ui.add_child(jar_center)
	jar = PotionJarScene.instantiate()
	jar_center.add_child(jar)

	var sliders_row := HBoxContainer.new()
	sliders_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sliders_row.add_theme_constant_override("separation", 24)
	round_ui.add_child(sliders_row)

	for key in ORDER:
		var p: Dictionary = PARAMS[key]
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		sliders_row.add_child(col)
		slider_cols[key] = col

		var name_lbl := Label.new()
		name_lbl.text = p["label"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lbl)

		var s := VSlider.new()
		s.min_value = p["min"]
		s.max_value = p["max"]
		s.step = p["step"]
		s.custom_minimum_size = Vector2(44, 240)
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_slider_changed.bind(key))
		col.add_child(s)
		sliders[key] = s

		var val_lbl := Label.new()
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(val_lbl)
		value_labels[key] = val_lbl

	var done_btn := Button.new()
	done_btn.text = "ГОТОВО!"
	done_btn.custom_minimum_size = Vector2(0, 56)
	done_btn.pressed.connect(_on_done)
	round_ui.add_child(done_btn)

	# ---- экран выбора ----
	select_panel = _make_center_panel()
	var sv := select_panel.get_node("C/Card/V") as VBoxContainer
	sv.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "К тебе заглянул посетитель"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	sv.add_child(title)

	# портрет в ДЕРЕВЯННОЙ рамке: текстура дерева + гвозди, портрет утоплен внутрь
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(240, 240)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(frame)

	var pwood := ColorRect.new()          # деревянная поверхность рамки
	pwood.set_anchors_preset(Control.PRESET_FULL_RECT)
	pwood.material = _make_wood_material(2.4)
	pwood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pwood)

	npc_portrait_tex = TextureRect.new()
	npc_portrait_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	npc_portrait_tex.offset_left = 16.0
	npc_portrait_tex.offset_top = 16.0
	npc_portrait_tex.offset_right = -16.0
	npc_portrait_tex.offset_bottom = -16.0
	npc_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE       # НЕ раздуваться до размера текстуры
	npc_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	npc_portrait_tex.visible = false
	frame.add_child(npc_portrait_tex)

	npc_portrait = Label.new()   # фолбэк-эмодзи, если текстура не импортирована
	npc_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	npc_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	npc_portrait.add_theme_font_size_override("font_size", 72)
	frame.add_child(npc_portrait)

	var pedge := Control.new()            # тень проёма + гвозди (поверх всего)
	pedge.set_script(PortraitEdge)
	pedge.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(pedge)

	npc_name = Label.new()
	npc_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_name.add_theme_font_size_override("font_size", 26)
	sv.add_child(npc_name)

	npc_flavor = Label.new()
	npc_flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_flavor.custom_minimum_size = Vector2(440, 0)
	sv.add_child(npc_flavor)

	var pick := Label.new()
	pick.text = "Выбери сложность:"
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(pick)

	for lvl in [1, 2, 3, 4]:
		var b := Button.new()
		b.text = LEVEL_DESC[lvl]
		b.custom_minimum_size = Vector2(440, 52)
		b.pressed.connect(_start_round.bind(lvl))
		sv.add_child(b)

	# ---- экран результата ----
	result_panel = _make_center_panel()
	var rv := result_panel.get_node("C/Card/V") as VBoxContainer
	rv.add_theme_constant_override("separation", 14)

	result_sticker = Label.new()
	result_sticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sticker.add_theme_font_size_override("font_size", 40)
	rv.add_child(result_sticker)

	result_detail = Label.new()
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_detail)

	var again := Button.new()
	again.text = "Дальше →"
	again.custom_minimum_size = Vector2(0, 48)
	again.pressed.connect(_show_select)
	rv.add_child(again)

	# металлическая рамка-обрамление — поверх всего (клики не перехватывает)
	add_child(GameFrameScene.instantiate())

# Прозрачный слой на весь экран (дерево-фон просвечивает) с тёмной карточкой
# по центру; контент — VBox по пути "C/Card/V".
func _make_center_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var c := CenterContainer.new()
	c.name = "C"
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var card := PanelContainer.new()
	card.name = "Card"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.07, 0.84)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.35, 0.24, 0.13, 0.85)   # деревянно-коричневая кайма
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", sb)
	c.add_child(card)
	var v := VBoxContainer.new()
	v.name = "V"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	return root

# ---------- экран выбора ----------
func _show_select() -> void:
	phase = "select"
	result_panel.visible = false
	round_ui.visible = false
	select_panel.visible = true
	npc = NPCS[randi() % NPCS.size()]
	# реальный портрет, если импортирован; иначе — эмодзи-фолбэк
	var tex := load("res://assets/npc/%s.png" % npc["img"]) as Texture2D
	if tex:
		npc_portrait_tex.texture = tex
		npc_portrait_tex.visible = true
		npc_portrait.visible = false
	else:
		npc_portrait_tex.visible = false
		npc_portrait.visible = true
		npc_portrait.text = npc["emoji"]
	npc_name.text = npc["name"]
	npc_flavor.text = "«%s»" % npc["flavor"]

# ---------- начало раунда ----------
func _start_round(lvl: int) -> void:
	level = lvl
	active = ACTIVE[lvl].duplicate()
	select_panel.visible = false
	result_panel.visible = false
	round_ui.visible = true
	phase_bar.visible = true

	# показываем только активные ползунки
	for key in ORDER:
		slider_cols[key].visible = key in active

	seed_val = randi()
	target = _random_values()
	_apply_to_jar(target)          # цель показываем целиком
	_set_sliders_interactable(false)
	for key in ORDER:
		value_labels[key].text = "?"
	phase = "memorize"
	phase_total = MEMORIZE_S
	phase_left = MEMORIZE_S
	phase_bar.value = 1.0

func _start_recreate() -> void:
	phase = "recreate"
	phase_total = CRAFT_S
	phase_left = CRAFT_S
	phase_bar.value = 1.0
	# активные ползунки — в случайное; неактивные держим на цели (не участвуют)
	var start_vals: Dictionary = _random_values()
	for key in ORDER:
		var v: float = start_vals[key] if key in active else float(target[key])
		sliders[key].set_value_no_signal(v)
	_set_sliders_interactable(true)
	_apply_to_jar(_current_values())
	_update_value_labels(_current_values())

# ---------- таймеры фаз ----------
func _process(delta: float) -> void:
	if phase == "memorize":
		phase_left -= delta
		phase_bar.value = clampf(phase_left / phase_total, 0.0, 1.0)
		phase_label.text = "ЗАПОМНИ — %dс" % int(ceil(maxf(phase_left, 0.0)))
		if phase_left <= 0.0:
			_start_recreate()
	elif phase == "recreate":
		phase_left -= delta
		phase_bar.value = clampf(phase_left / phase_total, 0.0, 1.0)
		phase_label.text = "ВОССОЗДАЙ — %dс" % int(ceil(maxf(phase_left, 0.0)))
		if phase_left <= 0.0:
			_finish()

# ---------- завершение ----------
func _on_done() -> void:
	if phase != "recreate":
		return
	_finish()

func _finish() -> void:
	phase_bar.visible = false
	var comps: Dictionary = {}
	var overall: float = 0.0
	var wsum: float = 0.0
	for key in active:                       # считаем только активные параметры
		var p: Dictionary = PARAMS[key]
		var span: float = float(p["max"]) - float(p["min"])
		var diff: float = abs(sliders[key].value - float(target[key])) / span
		var sc: float = pow(clampf(1.0 - diff, 0.0, 1.0), 1.6)
		comps[key] = sc
		overall += sc * float(p["weight"])
		wsum += float(p["weight"])
	overall = overall / maxf(wsum, 0.001)
	_show_result(overall, comps)

func _show_result(overall: float, comps: Dictionary) -> void:
	phase = "result"
	round_ui.visible = false
	var sticker: String = "БРАК"
	if overall >= PERFECT:
		sticker = "ИДЕАЛ!"
	elif overall >= GOOD:
		sticker = "ГОДНО"
	result_sticker.text = "%s   %d%%" % [sticker, int(round(overall * 100.0))]
	var lines: Array = ["%s · %s" % [npc["name"], LEVEL_DESC[level]]]
	for key in active:
		lines.append("%s: %d%%" % [PARAMS[key]["label"], int(round(float(comps[key]) * 100.0))])
	result_detail.text = "\n".join(lines)
	result_panel.visible = true

# ---------- вспомогательное ----------
func _random_values() -> Dictionary:
	var v: Dictionary = {}
	for key in ORDER:
		var p: Dictionary = PARAMS[key]
		var steps: int = int((float(p["max"]) - float(p["min"])) / float(p["step"]))
		v[key] = float(p["min"]) + float(p["step"]) * float(randi() % (steps + 1))
	return v

func _current_values() -> Dictionary:
	var v: Dictionary = {}
	for key in ORDER:
		v[key] = sliders[key].value
	return v

func _apply_to_jar(vals: Dictionary) -> void:
	var vp: Dictionary = PARAMS["volume"]
	var vsize: float = (float(vals["volume"]) - float(vp["min"])) / (float(vp["max"]) - float(vp["min"]))
	var bp: Dictionary = PARAMS["bsize"]
	var bfrac: float = (float(vals["bsize"]) - float(bp["min"])) / (float(bp["max"]) - float(bp["min"]))
	jar.set_potion(float(vals["color"]), vsize, int(vals["count"]), bfrac, seed_val)

func _on_slider_changed(_value: float, key: String) -> void:
	if phase != "recreate":
		return
	_apply_to_jar(_current_values())
	value_labels[key].text = _fmt(key, sliders[key].value)

func _update_value_labels(vals: Dictionary) -> void:
	for key in ORDER:
		value_labels[key].text = _fmt(key, float(vals[key])) if key in active else "?"

func _fmt(key: String, value: float) -> String:
	return "%d%s" % [int(round(value)), PARAMS[key]["suffix"]]

func _set_sliders_interactable(on: bool) -> void:
	for key in ORDER:
		sliders[key].editable = on
		sliders[key].modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.45)
