extends Control
## Этап 2: экран выбора (персонаж + сложность УР.1-4) и разный набор
## доступных ползунков по уровню. Цикл раунда — как в этапе 1
## (ЗАПОМНИ -> ВОССОЗДАЙ с таймерами -> РЕЙТИНГ).

const PotionJarScene := preload("res://scenes/potion_jar.tscn")
const WoodShader := preload("res://shaders/wood.gdshader")
const PortraitBgShader := preload("res://shaders/portrait_bg.gdshader")
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

# Персонажи и цвета тиров теперь в GameData (autoload). Ростер — GameData.NPCS,
# цвета — GameData.TIER_COLORS. Флейвор выбирается случайно из npc["flavors"].

const MEMORIZE_S := 2.5
const CRAFT_S := 14.0

var target: Dictionary = {}
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var slider_cols: Dictionary = {}
var active: Array = []
var level: int = 1
var npc: Dictionary = {}

var round_ui: VBoxContainer
var jar: Control
var jar_stage: JarStage
var _serving: bool = false      # банка «уезжает» к гостю — блок повторного финиша
var phase_label: Label
var bulb_bar: BulbBar
var select_panel: Control
var npc_portrait: Label
var npc_portrait_tex: TextureRect
var frame_ring: TextureRect
var tier_glow: Panel
var tier_badge: Label
var npc_name: Label
var npc_flavor: Label
var result_panel: Control
var result_sticker: Label
var result_detail: Label

var result_sticker_tex: TextureRect

var start_panel: Control
var hud_tips: Label
var hud_orders: Label
var hud_streak: Label

var collection_panel: Control
var collection_list: VBoxContainer
var collection_tab: String = "stats"
var coll_tab_btns: Array = []

var seed_val: int = 0
var phase: String = "select"
var phase_left: float = 0.0
var phase_total: float = 1.0

# --- аркадный цикл (Шаг 3a) ---
const CYCLE_DAYS := 8            # длина цикла (позже — из прогрессии progCycleDays)
const MAX_STAGE := 3            # STAGE_TABLE.size() - 1
var stage: int = 0
var day_num: int = 1
var cycle_active: bool = false
var cycle_score: int = 0
var perfect_streak_max: int = 0
var good_streak_max: int = 0
var last_grade: String = ""

var day_panel: Control
var day_header: Label
var day_cards: VBoxContainer
var day_choices: Array = []      # зафиксированная тройка на текущий день

# постоянная верхняя панель (день/рейтинг/серия + иконки-кнопки)
const TOPBAR_H := 48.0
const CONTENT_TOP := 88.0        # верх контента экранов — ниже панели

# Три параллакс-слоя по Z: задний (космос) → средний (стена с окном) →
# передний (стол+пол). Окно среднего слоя прозрачно — сквозь него виден космос.
const WINDOW_UV := Rect2(0.188, 0.164, 0.624, 0.375)   # проём окна в UV (0..1)
var layer_back: TextureRect      # космос (дальний)
var layer_mid: TextureRect       # стена с окном
var layer_front: TextureRect     # стол + пол (ближний)
var window_shutter: ColorRect    # шторка, падающая на окно во время игры
var topbar: PanelContainer
var tb_day: Label
var tb_rating: Label
var tb_streak: Label
var _tb_rating_shown: int = 0    # для count-up рейтинга

func _ready() -> void:
	randomize()
	theme = _make_theme()      # единый стиль (кнопки/шрифты) на всё дерево
	_build_ui()
	_show_start()

# Единый Theme: аккуратные кнопки (скруглённые, тёмные, неоновая кайма) и
# крупный базовый шрифт под телефон. Кастомные контролы (TouchSlider, рамка)
# рисуются сами и темой не затрагиваются.
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	# тень у подписей — читаемость поверх арта прозрачных экранов
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("shadow_outline_size", "Label", 3)
	t.set_color("font_color", "Button", Color(0.93, 0.91, 0.96))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.66, 0.5))
	t.set_font_size("font_size", "Button", 18)
	t.set_constant("outline_size", "Button", 0)
	t.set_stylebox("normal", "Button", _btn_sb(Color(0.13, 0.12, 0.18, 0.95), Color(0.42, 0.36, 0.62, 0.55)))
	t.set_stylebox("hover", "Button", _btn_sb(Color(0.19, 0.17, 0.26, 0.97), Color(0.62, 0.52, 0.95, 0.8)))
	t.set_stylebox("pressed", "Button", _btn_sb(Color(0.08, 0.07, 0.12, 1.0), Color(0.62, 0.52, 0.95, 0.9)))
	t.set_stylebox("disabled", "Button", _btn_sb(Color(0.10, 0.10, 0.13, 0.55), Color(0.3, 0.3, 0.36, 0.25)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t

func _btn_sb(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb

# Камера-параллакс: три слоя двигаются масштабом+сдвигом с разной скоростью.
# menu — только космос; select — камера в окне (окно почти во весь экран, по центру);
# game — общий кадр бара, чуть приподнятый (стол выше, зелье по центру).
# На слой: [scale, alpha, offset_y_px]. Пивот масштаба — центр (360,640).
const SCENE_STATES := {
	"menu":   [[1.05, 1.0, 0.0],   [1.30, 0.0, 0.0],   [1.60, 0.0, 0.0]],
	"select": [[1.15, 1.0, 150.0], [1.45, 1.0, 276.0], [1.90, 0.0, 0.0]],
	"game":   [[1.00, 1.0, 0.0],   [1.00, 1.0, 0.0],   [1.00, 1.0, 0.0]],
}
func _scene_state(state: String, dur: float = 0.55) -> void:
	var c: Array = SCENE_STATES.get(state, SCENE_STATES["game"])
	_tween_layer(layer_back, c[0], dur)
	_tween_layer(layer_mid, c[1], dur)
	_tween_layer(layer_front, c[2], dur)

func _tween_layer(l: TextureRect, cfg: Array, dur: float) -> void:
	if l == null:
		return
	var old: Variant = l.get_meta("cam_tw", null)   # заглушить прошлый камерный тви́н
	if old is Tween and old.is_valid():
		old.kill()
	var t := l.create_tween().set_parallel(true)
	l.set_meta("cam_tw", t)
	t.tween_property(l, "scale", Vector2(cfg[0], cfg[0]), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", cfg[1], dur).set_trans(Tween.TRANS_SINE)
	t.tween_property(l, "position", Vector2(0.0, cfg[2]), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Один фоновый слой (9:16, во весь экран, пивот по центру; позицию тви́ним под камеру).
func _bg_layer(path: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.position = Vector2.ZERO
	t.size = Vector2(720, 1280)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE      # тот же 9:16 — без искажений
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.pivot_offset = Vector2(360, 640)
	add_child(t)
	return t

# ---------- построение интерфейса ----------
func _build_ui() -> void:
	# три параллакс-слоя по Z (дальний → ближний). Все 9:16, тянутся на весь экран.
	# Пивот по центру — чтобы камера-переходы масштабировали относительно центра.
	layer_back = _bg_layer("res://assets/bg/cosmos for bg.png")       # космос (дальний)
	layer_mid = _bg_layer("res://assets/bg/bg_for_game_no_table.png") # стена с окном
	layer_front = _bg_layer("res://assets/bg/bg_for_game_table.png")  # стол + пол (ближний)
	# стартовое состояние «меню» мгновенно (без вспышки полного бара на буте)
	layer_back.scale = Vector2(1.05, 1.05)
	layer_mid.scale = Vector2(1.30, 1.30); layer_mid.modulate.a = 0.0
	layer_front.scale = Vector2(1.60, 1.60); layer_front.modulate.a = 0.0

	# ---- UI раунда ----
	round_ui = VBoxContainer.new()
	round_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	round_ui.offset_left = 36.0
	round_ui.offset_top = CONTENT_TOP        # ниже постоянной верхней панели
	round_ui.offset_right = -36.0
	round_ui.offset_bottom = -36.0
	round_ui.add_theme_constant_override("separation", 14)
	add_child(round_ui)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 28)
	round_ui.add_child(phase_label)

	# лампочки-таймер: заполняются на «запомни», гаснут на «воссоздай»
	bulb_bar = BulbBar.new()
	round_ui.add_child(bulb_bar)

	# банка «на сцене»: спот + барный стол + тень (даёт ей место и точку отсчёта)
	jar_stage = JarStage.new()
	jar_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	round_ui.add_child(jar_stage)
	jar = PotionJarScene.instantiate()
	jar_stage.set_jar(jar)

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

		var s := TouchSlider.new()
		s.min_value = p["min"]
		s.max_value = p["max"]
		s.step = p["step"]
		s.value = p["min"]
		s.hue_track = key == "color"   # регулятор спектра — радужный градиент
		s.custom_minimum_size = Vector2(84, 300)
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
	select_panel = _make_center_panel(true)   # прозрачная — виден бар за окном
	var sv := select_panel.get_node("Card/V") as VBoxContainer
	sv.add_theme_constant_override("separation", 12)

	var sel_menu := Button.new()
	sel_menu.text = "← К выбору"
	sel_menu.custom_minimum_size = Vector2(140, 40)
	sel_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sel_menu.pressed.connect(_show_day)
	sv.add_child(sel_menu)

	var title := Label.new()
	title.text = "К тебе заглянул посетитель"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	sv.add_child(title)

	# портрет в круглой металлической рамке (frame_round.png): кольцо поверх
	# портрета само маскирует его в круг; поворот на случайный угол — для разнообразия
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(240, 240)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(frame)

	tier_glow = Panel.new()               # цветное свечение тира за рамкой (позади всего)
	tier_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	tier_glow.offset_left = -8.0
	tier_glow.offset_top = -8.0
	tier_glow.offset_right = 8.0
	tier_glow.offset_bottom = 8.0
	tier_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tier_glow)

	# тёмная текстурная подложка под портретом (как внутри рамки, третий скрин).
	# Перекрывает свечение в центре — персонаж стоит на текстуре, а не на глоу.
	var portrait_bg := ColorRect.new()
	portrait_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = PortraitBgShader
	portrait_bg.material = bg_mat
	frame.add_child(portrait_bg)

	npc_portrait_tex = TextureRect.new()
	npc_portrait_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	npc_portrait_tex.offset_left = 43.0
	npc_portrait_tex.offset_top = 43.0
	npc_portrait_tex.offset_right = -43.0
	npc_portrait_tex.offset_bottom = -43.0
	npc_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE       # НЕ раздуваться до размера текстуры
	npc_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	npc_portrait_tex.visible = false
	frame.add_child(npc_portrait_tex)

	npc_portrait = Label.new()   # фолбэк-эмодзи, если текстура не импортирована
	npc_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	npc_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	npc_portrait.add_theme_font_size_override("font_size", 72)
	frame.add_child(npc_portrait)

	# кольцо-рамка поверх (маскирует портрет в круг), поворачивается каждый визит
	frame_ring = TextureRect.new()
	frame_ring.texture = load("res://assets/ui/frame_round.png")
	frame_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_ring.stretch_mode = TextureRect.STRETCH_SCALE
	frame_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_ring.pivot_offset = Vector2(120, 120)
	frame.add_child(frame_ring)

	npc_name = Label.new()
	npc_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_name.add_theme_font_size_override("font_size", 26)
	sv.add_child(npc_name)

	tier_badge = Label.new()
	tier_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_badge.add_theme_font_size_override("font_size", 13)
	sv.add_child(tier_badge)

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
	var rv := result_panel.get_node("Card/V") as VBoxContainer
	rv.add_theme_constant_override("separation", 14)

	# картинка-стикер (perfect/good/swill/bad), если PNG импортирован
	result_sticker_tex = TextureRect.new()
	result_sticker_tex.custom_minimum_size = Vector2(200, 200)
	result_sticker_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_sticker_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_sticker_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_sticker_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(result_sticker_tex)

	result_sticker = Label.new()
	result_sticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sticker.add_theme_font_size_override("font_size", 32)
	rv.add_child(result_sticker)

	result_detail = Label.new()
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_detail)

	var again := Button.new()
	again.text = "Дальше →"
	again.custom_minimum_size = Vector2(0, 56)
	again.pressed.connect(_result_next)
	rv.add_child(again)

	var res_menu := Button.new()
	res_menu.text = "← В меню"
	res_menu.custom_minimum_size = Vector2(0, 48)
	res_menu.pressed.connect(_show_start)
	rv.add_child(res_menu)

	# ---- стартовый экран (главное меню + HUD профиля) ----
	_build_start()
	# ---- экран коллекции (репутация NPC + альбом стикеров + статистика) ----
	_build_collection()
	# ---- экран дня (выбор одного из трёх посетителей) ----
	_build_day()
	# ---- постоянная верхняя панель (над экранами, под рамкой) ----
	_build_topbar()
	# рамкой служит сам бар-арт (bar_frame) — отдельная металлическая рамка не нужна

func _build_start() -> void:
	start_panel = _make_center_panel(true)    # прозрачная — виден космос/бар
	var sv := start_panel.get_node("Card/V") as VBoxContainer
	sv.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "ЗЕЛЬЕВАРНЯ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	sv.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Sector Seven Saloon"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = Color(1, 1, 1, 0.5)
	sv.add_child(subtitle)

	# HUD профиля: чипы чаевые / заказы / серия
	var hud := HBoxContainer.new()
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	hud.add_theme_constant_override("separation", 22)
	sv.add_child(hud)
	hud_tips = _hud_chip(hud, "🪙")
	hud_orders = _hud_chip(hud, "📦")
	hud_streak = _hud_chip(hud, "🔥")

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	sv.add_child(spacer)

	var play := Button.new()
	play.text = "ИГРАТЬ"
	play.custom_minimum_size = Vector2(440, 64)
	play.add_theme_font_size_override("font_size", 24)
	play.pressed.connect(_start_cycle)
	sv.add_child(play)

	var coll_btn := Button.new()
	coll_btn.text = "Коллекция"
	coll_btn.custom_minimum_size = Vector2(440, 52)
	coll_btn.pressed.connect(_show_collection)
	sv.add_child(coll_btn)

	var daily_btn := Button.new()      # заглушка под Фазу 2/3
	daily_btn.text = "Ежедневный заказ  (скоро)"
	daily_btn.custom_minimum_size = Vector2(440, 52)
	daily_btn.disabled = true
	sv.add_child(daily_btn)

# Чип HUD: «эмодзи + значение», значение обновляется в _refresh_hud().
func _hud_chip(row: HBoxContainer, icon: String) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.text = "%s 0" % icon
	lbl.set_meta("icon", icon)
	row.add_child(lbl)
	return lbl

# ---------- экран коллекции ----------
# Статичный каркас (заголовок, скролл, «назад») строится один раз; наполнение
# (статы/альбом/список NPC) пересобирается каждый показ из живого профиля.
func _build_collection() -> void:
	collection_panel = _make_center_panel()
	var cv := collection_panel.get_node("Card/V") as VBoxContainer
	cv.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "🗂 Коллекция"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	cv.add_child(title)

	# вкладки (как в вебе: разделы, а не одна простыня)
	var tabrow := HBoxContainer.new()
	tabrow.alignment = BoxContainer.ALIGNMENT_CENTER
	tabrow.add_theme_constant_override("separation", 6)
	cv.add_child(tabrow)
	coll_tab_btns.clear()
	for tab in [["stats", "Статистика"], ["ribbon", "Лента"], ["stickers", "Стикеры"], ["npcs", "Посетители"]]:
		var b := Button.new()
		b.text = tab[1]
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("tab", tab[0])
		b.pressed.connect(_set_collection_tab.bind(tab[0]))
		tabrow.add_child(b)
		coll_tab_btns.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)

	collection_list = VBoxContainer.new()
	collection_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_list.add_theme_constant_override("separation", 8)
	scroll.add_child(collection_list)

	var back := Button.new()
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(_close_collection)
	cv.add_child(back)

func _show_collection() -> void:
	phase = "collection"
	start_panel.visible = false
	select_panel.visible = false
	result_panel.visible = false
	round_ui.visible = false
	day_panel.visible = false
	collection_panel.visible = true
	_set_topbar(false)
	_set_collection_tab(collection_tab)
	Juice.fade_in(collection_panel)

# Возврат из коллекции: в день, если цикл активен, иначе в меню.
func _close_collection() -> void:
	if cycle_active:
		_show_day()
	else:
		_show_start()

func _set_collection_tab(tab: String) -> void:
	collection_tab = tab
	for b in coll_tab_btns:          # активная вкладка ярче
		b.modulate = Color(1, 1, 1, 1) if b.get_meta("tab") == tab else Color(1, 1, 1, 0.5)
	_populate_collection()

func _populate_collection() -> void:
	for c in collection_list.get_children():
		c.queue_free()

	match collection_tab:
		"stats": _fill_stats_tab()
		"ribbon": _fill_ribbon_tab()
		"stickers": _fill_stickers_tab()
		"npcs": _fill_npcs_tab()

func _fill_stats_tab() -> void:
	var st: Dictionary = PotionProfile.data.get("stats", {})
	var tips: Dictionary = PotionProfile.data.get("tips", {})
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	var life: Dictionary = st.get("stickers_lifetime", {})
	_coll_header("Всего")
	_coll_line("Заказов: %d" % int(st.get("total_orders", 0)))
	_coll_line("Чаевых за всё время: %d" % int(tips.get("lifetime", 0)))
	_coll_line("Встречено посетителей: %d / %d" % [PotionProfile.data.get("progression", {}).get("met_npcs", []).size(), GameData.NPCS.size()])
	_coll_header("Серии")
	_coll_line("Лучшая серия идеалов: %d" % int(sk.get("perfect_best", 0)))
	_coll_line("Лучшая серия без брака: %d" % int(sk.get("goodplus_best", 0)))
	_coll_header("Смеси по грейдам")
	for cat in ["perfect", "good", "swill", "bad"]:
		_coll_line("%s: %d" % [GRADE_LABEL.get(cat, cat), int(life.get(cat, 0))])

func _fill_stickers_tab() -> void:
	var seen: Dictionary = PotionProfile.data.get("stats", {}).get("stickers_seen", {})
	for cat in ["perfect", "good", "swill", "bad"]:
		var all: Array = GameData.STICKERS[cat]
		var got: Array = seen.get(cat, [])
		_coll_header("%s — %d/%d" % [GRADE_LABEL.get(cat, cat), got.size(), all.size()])
		_sticker_grid(all, got)

func _fill_npcs_tab() -> void:
	for npc_e in GameData.NPCS:
		_npc_row(npc_e)

func _coll_header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	collection_list.add_child(l)

func _coll_line(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.modulate = Color(1, 1, 1, 0.85)
	collection_list.add_child(l)

const STICKER_COLS := 5      # телефон: крупные слоты, 5 в ряд

# Ряд миниатюр стикеров: виденные — картинкой, невиденные — тёмный слот. Крупно.
func _sticker_grid(all: Array, got: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = STICKER_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for name in all:
		if got.has(name):
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(104, 104)
			tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture = load(GameData.sticker_path(name)) as Texture2D
			grid.add_child(tr)
		else:
			var slot := Panel.new()
			slot.custom_minimum_size = Vector2(104, 104)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.05)
			sb.set_corner_radius_all(10)
			slot.add_theme_stylebox_override("panel", sb)
			grid.add_child(slot)
	collection_list.add_child(grid)

# ---------- вкладка «Лента идеальных» ----------
func _fill_ribbon_tab() -> void:
	var rb: Dictionary = PotionProfile.data.get("perfect_ribbon", {"count": 0.0, "platinum_count": 0})
	var count: float = float(rb.get("count", 0.0))
	var plat: int = int(rb.get("platinum_count", 0))
	_coll_header("Лента идеальных — %.1f / %d" % [count, int(GameData.RIBBON_FULL)])
	_ribbon_grid(count, int(GameData.RIBBON_FULL))
	_coll_line("Идеалы на высоких тирах и сложностях заполняют ленту быстрее.")
	if plat > 0:
		_coll_header("Платиновых лент: %d" % plat)
		_plat_row(plat)

# Сетка ленты: заполненные слоты — иконкой идеала, текущий — приглушённо (дробно).
func _ribbon_grid(count: float, total: int) -> void:
	var icon := load(GameData.sticker_path("perfect1")) as Texture2D
	var filled: int = int(floor(count))
	var frac: float = count - float(filled)
	var grid := GridContainer.new()
	grid.columns = STICKER_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in total:
		if i < filled:
			grid.add_child(_ribbon_slot(icon, 1.0))
		elif i == filled and frac > 0.0:
			grid.add_child(_ribbon_slot(icon, 0.3 + 0.6 * frac))   # текущий — по доле
		else:
			grid.add_child(_ribbon_slot(null, 0.0))
	collection_list.add_child(grid)

func _ribbon_slot(icon: Texture2D, fill: float) -> Control:
	if icon != null and fill > 0.0:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(104, 104)
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = icon
		tr.modulate = Color(1, 1, 1, fill)
		return tr
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(104, 104)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(52)      # круглые пустые слоты
	slot.add_theme_stylebox_override("panel", sb)
	return slot

func _plat_row(plat: int) -> void:
	var icon := load(GameData.sticker_path("perfect1")) as Texture2D
	var grid := GridContainer.new()
	grid.columns = STICKER_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var show: int = mini(plat, STICKER_COLS)
	for i in show:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(104, 104)
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = icon
		tr.modulate = Color(0.7, 0.85, 1.0)     # платиновый отлив
		grid.add_child(tr)
	collection_list.add_child(grid)
	if plat > STICKER_COLS:
		_coll_line("… и ещё %d" % (plat - STICKER_COLS))

# Ряд NPC: портрет/эмодзи + имя (цвет тира) + уровень репутации. Невстреченные
# показываются скрытыми («???»).
func _npc_row(npc_e: Dictionary) -> void:
	var id: String = npc_e["id"]
	var met: bool = PotionProfile.has_met(id)
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var tex: Texture2D = null
	if met:
		tex = load(GameData.portrait_path(npc_e)) as Texture2D
	if tex:
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(84, 84)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = tex
		row.add_child(pic)
	else:
		# фолбэк: эмодзи для встреченного без текстуры, знак вопроса для скрытого
		var e := Label.new()
		e.custom_minimum_size = Vector2(84, 84)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.add_theme_font_size_override("font_size", 46)
		e.text = npc_e.get("emoji", "❓") if met else "❓"
		row.add_child(e)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := Label.new()
	nm.text = npc_e["name"] if met else "???"
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", tcol if met else Color(1, 1, 1, 0.4))
	col.add_child(nm)
	var rep := Label.new()
	if met:
		var lvl: int = PotionProfile.get_rep_level(id)
		rep.text = ("Репутация: " + "★".repeat(lvl)) if lvl > 0 else "Репутация: —"
	else:
		rep.text = "не встречен"
	rep.modulate = Color(1, 1, 1, 0.6)
	rep.add_theme_font_size_override("font_size", 15)
	col.add_child(rep)
	row.add_child(col)

	collection_list.add_child(row)

# Полноэкранная тёмная карточка (внутри металлической рамки), контент — VBox
# по пути "Card/V". VBox тянется на всю высоту и центрирует свой блок по
# вертикали (разреженные экраны — по центру, коллекция — заполняет).
const PANEL_INSET := 34.0    # отступ от края экрана — чтобы влезть внутрь рамки
func _make_center_panel(transparent: bool = false) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_left = PANEL_INSET
	card.offset_top = CONTENT_TOP        # ниже постоянной верхней панели
	card.offset_right = -PANEL_INSET
	card.offset_bottom = -PANEL_INSET
	var sb := StyleBoxFlat.new()
	if transparent:
		# прозрачная карточка — сквозь неё виден параллакс-бар (меню/выбор)
		sb.bg_color = Color(0, 0, 0, 0)
	else:
		sb.bg_color = Color(0.05, 0.04, 0.07, 0.84)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.35, 0.24, 0.13, 0.85)   # деревянно-коричневая кайма
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var v := VBoxContainer.new()
	v.name = "V"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(v)
	return root

# ---------- аркадный цикл: день (выбор одного из трёх) ----------
func _build_day() -> void:
	day_panel = _make_center_panel(true)      # прозрачная — виден космос/бар
	var dv := day_panel.get_node("Card/V") as VBoxContainer
	dv.add_theme_constant_override("separation", 12)

	var hint := Label.new()
	hint.text = "КТО ПРИШВАРТОВАЛСЯ К ЛАВКЕ?"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	dv.add_child(hint)

	# карточки заполняют всю доступную высоту (крупно даже когда их 2)
	day_cards = VBoxContainer.new()
	day_cards.add_theme_constant_override("separation", 16)
	day_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(day_cards)

	# day_header скрыт в шапке экрана — держим ссылку живой (день виден в топбаре)
	day_header = Label.new()
	day_header.visible = false
	dv.add_child(day_header)

	var to_menu := Button.new()
	to_menu.text = "← Меню (бросить цикл)"
	to_menu.custom_minimum_size = Vector2(0, 48)
	to_menu.pressed.connect(_show_start)
	dv.add_child(to_menu)

# ---------- постоянная верхняя панель ----------
func _build_topbar() -> void:
	topbar = PanelContainer.new()
	topbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	topbar.offset_left = 30.0
	topbar.offset_right = -30.0
	topbar.offset_top = 30.0
	topbar.offset_bottom = 30.0 + TOPBAR_H
	topbar.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.30, 0.5, 0.6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	topbar.add_theme_stylebox_override("panel", sb)
	add_child(topbar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	topbar.add_child(row)

	tb_day = Label.new()
	tb_day.add_theme_font_size_override("font_size", 16)
	row.add_child(tb_day)
	tb_streak = Label.new()
	tb_streak.add_theme_font_size_override("font_size", 16)
	tb_streak.modulate = Color(1.0, 0.7, 0.4)
	row.add_child(tb_streak)

	var sp_l := Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp_l)

	tb_rating = Label.new()
	tb_rating.add_theme_font_size_override("font_size", 18)
	row.add_child(tb_rating)

	var sp_r := Control.new()
	sp_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp_r)

	# иконки-кнопки (Коллекция активна; остальное — заглушки под будущие системы)
	_topbar_icon(row, "🗂", "Коллекция", _show_collection, true)
	_topbar_icon(row, "👥", "Персонажи", Callable(), false)
	_topbar_icon(row, "⚡", "Пассивки", Callable(), false)
	_topbar_icon(row, "⚙", "Настройки", Callable(), false)

func _topbar_icon(row: HBoxContainer, glyph: String, tip: String, cb: Callable, enabled: bool) -> void:
	var b := Button.new()
	b.text = glyph
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(48, 40)
	b.add_theme_font_size_override("font_size", 20)
	b.disabled = not enabled
	if enabled and cb.is_valid():
		b.pressed.connect(cb)
	row.add_child(b)

func _set_topbar(on: bool) -> void:
	topbar.visible = on
	if on:
		_refresh_topbar()

func _refresh_topbar() -> void:
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	tb_day.text = "День %d / %d   ·   ст.%d" % [day_num, CYCLE_DAYS, stage + 1]
	tb_streak.text = "🔥 %d" % int(sk.get("goodplus_current", 0))
	if cycle_score != _tb_rating_shown:
		Juice.count_up(tb_rating, _tb_rating_shown, cycle_score, "Рейтинг: %d")
		_tb_rating_shown = cycle_score
	else:
		tb_rating.text = "Рейтинг: %d" % cycle_score

func _start_cycle() -> void:
	stage = 0
	day_num = 1
	cycle_score = 0
	perfect_streak_max = 0
	good_streak_max = 0
	cycle_active = true
	_tb_rating_shown = 0
	_new_day()

# Новый день: фиксируем тройку посетителей и показываем экран выбора.
func _new_day() -> void:
	day_choices = _pick_day_npcs()
	_show_day()

func _show_day() -> void:
	phase = "day"
	start_panel.visible = false
	select_panel.visible = false
	result_panel.visible = false
	round_ui.visible = false
	collection_panel.visible = false
	day_panel.visible = true

	day_header.text = "День %d / %d   ·   стадия %d" % [day_num, CYCLE_DAYS, stage + 1]
	for c in day_cards.get_children():
		c.queue_free()
	for e in day_choices:
		day_cards.add_child(_day_card(e))
	_set_topbar(true)
	_scene_state("menu")
	Juice.stagger_fade(day_cards.get_children())   # карточки влетают по очереди

# Тиры трёх карточек = STAGE_TABLE[stage]; на макс. стадии серии подменяют
# хвостовые карточки на тир-5. Возвращает 3 записи NPC (по возможности разные).
func _pick_day_npcs() -> Array:
	var tiers: Array = (GameData.STAGE_TABLE[stage] as Array).duplicate()
	if stage == MAX_STAGE:
		var t5: int = 0
		if perfect_streak_max >= 3: t5 = 3
		elif perfect_streak_max == 2: t5 = 2
		elif perfect_streak_max == 1: t5 = 1
		elif good_streak_max >= 3: t5 = 2
		elif good_streak_max >= 2: t5 = 1
		for i in t5:
			tiers[tiers.size() - 1 - i] = 5
	var chosen: Array = []
	var used: Array = []
	for tier in tiers:
		var pool: Array = []
		for n in GameData.NPCS:
			if int(n.get("tier", 1)) == tier and not used.has(n["id"]):
				pool.append(n)
		if pool.is_empty():   # пул исчерпан — разрешаем повтор
			for n in GameData.NPCS:
				if int(n.get("tier", 1)) == tier:
					pool.append(n)
		var pick: Dictionary = pool[randi() % pool.size()]
		used.append(pick["id"])
		chosen.append(pick)
	return chosen

const TIER_NAMES := {1: "НОВИЧОК", 2: "ЗАВСЕГДАТАЙ", 3: "ЦЕНИТЕЛЬ", 4: "ВИП-ГОСТЬ", 5: "ЛЕГЕНДА"}

# Крупная карточка посетителя: круглая аватарка с тир-кольцом и свечением,
# имя, бейдж тира, реплика. Весь прямоугольник — тач-кнопка, растянута по высоте.
func _day_card(npc_e: Dictionary) -> Button:
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(440, 150)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL   # делят высоту поровну
	btn.pressed.connect(_choose_npc.bind(npc_e))
	# индивидуальный стайлбокс с тир-каймой/акцентом слева
	btn.add_theme_stylebox_override("normal", _card_sb(tcol, 0.55))
	btn.add_theme_stylebox_override("hover", _card_sb(tcol, 0.95))
	btn.add_theme_stylebox_override("pressed", _card_sb(tcol, 1.0))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_top = 14
	row.offset_right = -18
	row.offset_bottom = -14
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	row.add_child(_card_avatar(npc_e, 118.0))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge := Label.new()
	badge.text = "★ ТИР %d · %s" % [tier, TIER_NAMES.get(tier, "")]
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", tcol)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(badge)

	var nm := Label.new()
	nm.text = npc_e["name"]
	nm.add_theme_font_size_override("font_size", 26)
	nm.add_theme_color_override("font_color", Color(0.97, 0.96, 1.0))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)

	var flavors: Array = npc_e.get("flavors", [""])
	var fl := Label.new()
	fl.text = "«%s»" % flavors[0]
	fl.add_theme_font_size_override("font_size", 15)
	fl.modulate = Color(1, 1, 1, 0.6)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fl)

	row.add_child(col)
	return btn

# Стайлбокс карточки: тёмный фон, тир-кайма, толстый левый акцент (яркость каймы
# растёт на hover/press через параметр k).
func _card_sb(tcol: Color, k: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.10, 0.15, 0.96)
	sb.set_corner_radius_all(18)
	sb.border_width_left = 7
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(tcol.r, tcol.g, tcol.b, k)
	sb.shadow_color = Color(tcol.r, tcol.g, tcol.b, 0.28 * k)
	sb.shadow_size = 10
	return sb

# Круглая аватарка: тир-свечение → тёмный диск → портрет → металлическое кольцо
# (frame_round.png маскирует портрет в круг). Возвращает Control size×size.
func _card_avatar(npc_e: Dictionary, sz: float) -> Control:
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)
	var box := Control.new()
	box.custom_minimum_size = Vector2(sz, sz)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER    # держим квадрат, не тянемся
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# свечение тира (позади, круглое, с тенью-ореолом)
	var glow := Panel.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(tcol.r, tcol.g, tcol.b, 0.14)
	gsb.set_corner_radius_all(int(sz))
	gsb.shadow_color = Color(tcol.r, tcol.g, tcol.b, 0.5)
	gsb.shadow_size = 14
	glow.add_theme_stylebox_override("panel", gsb)
	box.add_child(glow)

	# тёмный диск-подложка (чтобы прозрачные портреты не светились насквозь)
	var disc := Panel.new()
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.09, 0.09, 0.12, 1.0)
	dsb.set_corner_radius_all(int(sz))
	disc.add_theme_stylebox_override("panel", dsb)
	box.add_child(disc)

	var tex := load(GameData.portrait_path(npc_e)) as Texture2D
	if tex:
		var pic := TextureRect.new()
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		var ins: float = sz * 0.09
		pic.offset_left = ins
		pic.offset_top = ins
		pic.offset_right = -ins
		pic.offset_bottom = -ins
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture = tex
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pic)
	else:
		var e := Label.new()
		e.set_anchors_preset(Control.PRESET_FULL_RECT)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.add_theme_font_size_override("font_size", int(sz * 0.5))
		e.text = npc_e.get("emoji", "❓")
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(e)

	var ring := TextureRect.new()
	ring.texture = load("res://assets/ui/frame_round.png")
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ring)

	return box

func _choose_npc(npc_e: Dictionary) -> void:
	npc = npc_e
	_show_select()

# ---------- переход после заказа: стадия/день/цикл ----------
func _after_order() -> void:
	# стадийная машина (как в game.js finalizeResult)
	if last_grade == "swill":
		perfect_streak_max = 0
		good_streak_max = 0
	elif last_grade == "bad":
		stage = maxi(0, stage - 1)
		perfect_streak_max = 0
		good_streak_max = 0
	elif stage < MAX_STAGE:
		stage = mini(MAX_STAGE, stage + 1)
		perfect_streak_max = 0
		good_streak_max = 0
	else:
		if last_grade == "perfect":
			perfect_streak_max += 1
			good_streak_max = 0
		else:
			good_streak_max += 1
			perfect_streak_max = 0

	day_num += 1
	if day_num > CYCLE_DAYS:
		_show_cycle_end()
	else:
		_new_day()

func _show_cycle_end() -> void:
	cycle_active = false
	var res: Dictionary = PotionProfile.end_cycle(cycle_score)
	phase = "cycle_end"
	round_ui.visible = false
	result_sticker_tex.visible = false
	result_sticker.text = "Цикл пройден!"
	var lines: Array = [
		"Рейтинг цикла: %d" % cycle_score,
		"Циклов всего: %d" % int(res.get("cycles", 0)),
		"Опыт: %d" % int(res.get("xp_after", 0)),
	]
	result_detail.text = "\n".join(lines)
	# кнопки на экране результата переиспользуем: «Дальше →» стартует новый цикл
	result_panel.visible = true
	_set_topbar(true)
	Juice.fade_in(result_panel)
	Juice.pop.call_deferred(result_sticker)

# ---------- стартовый экран ----------
func _show_start() -> void:
	phase = "start"
	result_panel.visible = false
	round_ui.visible = false
	select_panel.visible = false
	collection_panel.visible = false
	day_panel.visible = false
	start_panel.visible = true
	cycle_active = false
	_set_topbar(false)
	_scene_state("menu")
	_refresh_hud()
	Juice.fade_in(start_panel)

func _refresh_hud() -> void:
	var t: Dictionary = PotionProfile.data.get("tips", {})
	var st: Dictionary = PotionProfile.data.get("stats", {})
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	hud_tips.text = "%s %d" % [hud_tips.get_meta("icon"), int(t.get("balance", 0))]
	hud_orders.text = "%s %d" % [hud_orders.get_meta("icon"), int(st.get("total_orders", 0))]
	hud_streak.text = "%s %d" % [hud_streak.get_meta("icon"), int(sk.get("goodplus_current", 0))]

# ---------- экран выбора ----------
func _show_select() -> void:
	phase = "select"
	result_panel.visible = false
	round_ui.visible = false
	start_panel.visible = false
	collection_panel.visible = false
	day_panel.visible = false
	select_panel.visible = true
	_set_topbar(true)
	_scene_state("select")
	Juice.fade_in(select_panel)
	# npc уже выбран карточкой дня (_choose_npc); показываем его детально
	frame_ring.rotation = randf() * TAU   # случайный поворот кольца — «другой» вид рамки
	# реальный портрет, если импортирован; иначе — эмодзи-фолбэк
	var tex := load(GameData.portrait_path(npc)) as Texture2D
	if tex:
		npc_portrait_tex.texture = tex
		npc_portrait_tex.visible = true
		npc_portrait.visible = false
	else:
		npc_portrait_tex.visible = false
		npc_portrait.visible = true
		npc_portrait.text = npc["emoji"]
	npc_name.text = npc["name"]
	var flavors: Array = npc.get("flavors", [""])
	npc_flavor.text = "«%s»" % flavors[randi() % flavors.size()]
	# тир: цвет имени + бейдж + цветное свечение за рамкой
	var tier: int = int(npc.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)
	npc_name.add_theme_color_override("font_color", tcol)
	tier_badge.text = "★ ТИР %d" % tier
	tier_badge.add_theme_color_override("font_color", tcol)
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(tcol.r, tcol.g, tcol.b, 0.10)
	gsb.set_corner_radius_all(200)                 # большой радиус → круг
	gsb.shadow_color = Color(tcol.r, tcol.g, tcol.b, 0.55)
	gsb.shadow_size = 22
	tier_glow.add_theme_stylebox_override("panel", gsb)

# ---------- начало раунда ----------
func _start_round(lvl: int) -> void:
	level = lvl
	active = ACTIVE[lvl].duplicate()
	select_panel.visible = false
	result_panel.visible = false
	day_panel.visible = false
	round_ui.visible = true
	bulb_bar.visible = true
	_serving = false
	jar_stage.reset_jar()          # вернуть банку на стол после прошлого отъезда
	_set_topbar(true)
	_scene_state("game")
	Juice.fade_in(round_ui)

	# показываем только активные ползунки
	for key in ORDER:
		slider_cols[key].visible = key in active
	_slide_in_stools()             # стулья выезжают слева направо

	seed_val = randi()
	target = _random_values()
	_apply_to_jar(target)          # цель показываем целиком
	_set_sliders_interactable(false)
	for key in ORDER:
		value_labels[key].text = "?"
	phase = "memorize"
	phase_total = MEMORIZE_S
	phase_left = MEMORIZE_S
	bulb_bar.set_fraction(0.0)      # лампы гаснут в начале, будут заполняться

# Стулья-регуляторы выезжают слева направо по очереди. Ждём кадр, чтобы HBox
# успел разложить колонки (иначе не знаем их финальный x).
func _slide_in_stools() -> void:
	await get_tree().process_frame
	var d: float = 0.0
	for key in ORDER:
		var col: Control = slider_cols[key]
		if not col.visible:
			continue
		var x: float = col.position.x
		col.position.x = x - 360.0
		col.modulate.a = 0.0
		var t := col.create_tween()
		t.tween_interval(d)
		t.set_parallel(true)
		t.tween_property(col, "position:x", x, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(col, "modulate:a", 1.0, 0.28)
		d += 0.09

func _start_recreate() -> void:
	phase = "recreate"
	phase_total = CRAFT_S
	phase_left = CRAFT_S
	bulb_bar.set_fraction(1.0)      # все горят, дальше гаснут по таймеру
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
		# лампы ЗАПОЛНЯЮТСЯ по мере запоминания
		bulb_bar.set_fraction(1.0 - clampf(phase_left / phase_total, 0.0, 1.0))
		phase_label.text = "ЗАПОМНИ — %dс" % int(ceil(maxf(phase_left, 0.0)))
		if phase_left <= 0.0:
			_start_recreate()
	elif phase == "recreate":
		phase_left -= delta
		# лампы ГАСНУТ по мере игры
		bulb_bar.set_fraction(clampf(phase_left / phase_total, 0.0, 1.0))
		phase_label.text = "ВОССОЗДАЙ — %dс" % int(ceil(maxf(phase_left, 0.0)))
		if phase_left <= 0.0:
			_finish()

# ---------- завершение ----------
func _on_done() -> void:
	if phase != "recreate":
		return
	_finish()

# «ГОТОВО»/таймер: банка уезжает к гостю, затем считаем результат.
func _finish() -> void:
	if _serving:
		return
	_serving = true
	phase = "serving"
	bulb_bar.visible = false
	_set_sliders_interactable(false)
	_serve_jar()

# Мультяшный отъезд: короткий замах влево, затем разгон вправо с наклоном.
func _serve_jar() -> void:
	var x0: float = jar.position.x
	jar.pivot_offset = Vector2(jar.size.x * 0.5, jar.size.y * 0.92)   # наклон от основания
	var t := jar.create_tween()
	# замах (анти-выпад) влево
	t.tween_property(jar, "rotation", deg_to_rad(-9.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(jar, "position:x", x0 - 26.0, 0.14).set_trans(Tween.TRANS_SINE)
	# разгон вправо к гостю с наклоном вперёд
	t.tween_property(jar, "position:x", x0 + size.x + 300.0, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(jar, "rotation", deg_to_rad(24.0), 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(_do_finish)

func _do_finish() -> void:
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

	# грейд по порогам тира + запись результата в профиль
	var tier: int = int(npc.get("tier", 1))
	var grade: String = GameData.grade(overall, tier)
	var reward: int = int(GameData.npc_config(npc)["reward"])
	var cat: Array = GameData.STICKERS[grade]
	var sticker_name: String = cat[randi() % GameData.BASE_STICKERS]
	var time_frac: float = clampf(1.0 - phase_left / maxf(0.001, phase_total), 0.0, 1.0)
	var outcome: Dictionary = PotionProfile.record_result(
		npc["id"], tier, overall, grade, reward, sticker_name,
		time_frac, level)

	# для перехода дня/цикла
	last_grade = grade
	cycle_score += int(outcome.get("points", 0))

	_show_result(overall, comps, grade, outcome, sticker_name)

# «Дальше →» на экране результата: конец цикла → новый цикл, иначе → следующий день.
func _result_next() -> void:
	if phase == "cycle_end":
		_start_cycle()
	else:
		_after_order()

const GRADE_LABEL := {"perfect": "ИДЕАЛ!", "good": "ГОДНО", "swill": "ПОЙЛО", "bad": "БРАК"}

func _show_result(overall: float, comps: Dictionary, grade: String, outcome: Dictionary, sticker_name: String) -> void:
	phase = "result"
	round_ui.visible = false
	# картинка-стикер (если PNG импортирован) + подпись грейд + процент
	var stex := load(GameData.sticker_path(sticker_name)) as Texture2D
	result_sticker_tex.texture = stex
	result_sticker_tex.visible = stex != null
	result_sticker.text = "%s   %d%%" % [GRADE_LABEL.get(grade, "БРАК"), int(round(overall * 100.0))]
	var lines: Array = ["%s · %s" % [npc["name"], LEVEL_DESC[level]]]
	for key in active:
		lines.append("%s: %d%%" % [PARAMS[key]["label"], int(round(float(comps[key]) * 100.0))])
	# чаевые + репутация (данные из профиля)
	if int(outcome.get("tip", 0)) > 0:
		lines.append("+%d чаевых" % int(outcome["tip"]))
	if bool(outcome.get("level_up", false)):
		lines.append("Репутация с «%s»: уровень %d!" % [npc["name"], int(outcome["level_after"])])
	result_detail.text = "\n".join(lines)
	result_panel.visible = true
	_set_topbar(true)
	Juice.fade_in(result_panel)
	# «печать» стикера + конфетти цветом тира на годноте/идеале
	if result_sticker_tex.visible:
		Juice.pop.call_deferred(result_sticker_tex)
	if grade == "perfect" or grade == "good":
		var tcol: Color = GameData.TIER_COLORS.get(int(npc.get("tier", 1)), Color.WHITE)
		_confetti_at.call_deferred(result_sticker_tex, tcol)

# Всплеск конфетти в центре узла (глобальные координаты берём после layout).
func _confetti_at(node: Control, col: Color) -> void:
	if node != null and node.visible:
		Juice.burst(self, node.get_global_rect().get_center(), col)

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
