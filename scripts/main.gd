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
	"color":  {"min": 0.0,  "max": 360.0, "step": 5.0,  "weight": 1.0, "label": "Спектр",  "suffix": "°"},
	# 2-й спектр (Двуликая жрица, градиент) — базовая механика на всех уровнях
	"colorB": {"min": 0.0,  "max": 360.0, "step": 5.0,  "weight": 1.0, "label": "Спектр Б", "suffix": "°"},
	"sat":    {"min": 0.0,  "max": 100.0, "step": 10.0, "weight": 0.6, "label": "Накал",   "suffix": "%"},
	"volume": {"min": 10.0, "max": 100.0, "step": 1.0,  "weight": 1.0, "label": "Объём",   "suffix": "%"},
	"fill":   {"min": 20.0, "max": 100.0, "step": 10.0, "weight": 0.7, "label": "Уровень", "suffix": "%"},
	"size2":  {"min": 10.0, "max": 100.0, "step": 2.0,  "weight": 0.6, "label": "Высота",  "suffix": "%"},
	# Наклон сосуда (Дитя Сверхновой, УР.4) — небольшой, банка остаётся стоять на столе.
	"rotation": {"min": -15.0, "max": 15.0, "step": 5.0, "weight": 0.5, "label": "Наклон", "suffix": "°"},
	"count":  {"min": 1.0,  "max": 12.0,  "step": 1.0,  "weight": 0.8, "label": "Сгустки", "suffix": ""},
	"countB": {"min": 1.0,  "max": 7.0,   "step": 1.0,  "weight": 0.8, "label": "Сгустки Б", "suffix": ""},
	"bsize":  {"min": 10.0, "max": 100.0, "step": 2.0,  "weight": 0.6, "label": "Размер",  "suffix": "%"},
	"speed":  {"min": 0.0,  "max": 100.0, "step": 10.0, "weight": 0.6, "label": "Скорость", "suffix": ""},
	# «Градус» Пита (УР.4) — риск-дайл, НЕ оценивается (не входит в active): выше =
	# больше времени и чаевых, но меньше рейтинга и мутнее банка.
	"degree": {"min": 0.0,  "max": 100.0, "step": 10.0, "weight": 0.0, "label": "Градус",  "suffix": "°"},
}
# Накал (sat) — у спектра; Высота (size2) — у объёма; Сгустки Б (countB) — у сгустков;
# Скорость (speed) — в конце. size2/countB/speed активны только у своих гостей
# (Сверхнова / Двуликая / Бармен).
const ORDER: Array = ["color", "colorB", "sat", "volume", "fill", "size2", "rotation", "count", "countB", "bsize", "speed", "degree"]

# Какие ползунки активны (доступны и учитываются) на каждом уровне сложности.
# Накал — только на УР.4 (доп. регулятор рядом с цветом).
const ACTIVE := {
	1: ["color", "volume"],
	2: ["color", "volume", "count"],
	3: ["color", "volume", "count", "bsize"],
	4: ["color", "sat", "volume", "count", "bsize"],
}
const LEVEL_DESC := {
	1: "УР.1 — цвет + объём",
	2: "УР.2 — + сгустки",
	3: "УР.3 — + размер сгустка",
	4: "УР.4 — всё + механика",
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
var done_btn: Button
var mech: NpcMech             # уникальная механика гостя на этот раунд (или null)
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
var diff_btns: Dictionary = {}   # lvl -> кнопка сложности (для гейта УР.4)
var result_panel: Control
var result_sticker: Label
var result_points: Label
var result_breakdown: VBoxContainer
var result_detail: Label

var result_sticker_tex: TextureRect
var result_next_btn: Button       # «Дальше →»
var result_replay_btn: Button     # «Переиграть» (Ир)

var start_panel: Control
var hud_tips: Label
var hud_orders: Label
var hud_streak: Label
var coll_btn: Button          # кнопка «Коллекция» в меню (гейт прогрессией)
var profile_btn: Button       # кнопка «Профиль» в меню (ник)
var prog_strip: PanelContainer # постоянный стрип под топбаром с полосой прогрессии
var prog_widget: ProgBar
var toast_layer: VBoxContainer  # всплывающие тосты (уровень/новый гость/репутация)

var collection_panel: Control
var collection_list: VBoxContainer
var collection_tab: String = "stats"
var coll_tab_btns: Array = []
var char_panel: Control
var char_list: VBoxContainer
var chars_panel: Control       # список персонажей (кнопка 👥 в баре)
var chars_list: VBoxContainer
var account_panel: Control
var account_list: VBoxContainer
var _auth_tab: String = "login"

var seed_val: int = 0
var phase: String = "select"
var phase_left: float = 0.0
var phase_total: float = 1.0

# --- аркадный цикл (Шаг 3a) ---
const MAX_STAGE := 3            # STAGE_TABLE.size() - 1
var stage: int = 0
var day_num: int = 1
var cycle_days: int = 5         # длина цикла — из прогрессии (prog_cycle_days)
var cycle_active: bool = false
var cycle_score: int = 0
var perfect_streak_max: int = 0
var good_streak_max: int = 0
var last_grade: String = ""
var ir_pending: String = ""     # «Последний из Ир»: знак эффекта СЛЕДУЮЩЕМУ заказу ("buff"/"debuff"/"")
var ir_effect_id: String = ""   # конкретный эффект, выбранный ЭТОМУ заказу (пусто = нет)
var ir_effect_kind: String = "" # "buff"/"debuff" — для окраски чипа
var ir_chip: Label              # плашка активного эффекта под надписью фазы
# --- переигровка (Ир): «Второй рассвет» (optional) и «Дважды безупречно» (forced) ---
var ir_replay_mode: String = ""     # "" | "optional" | "forced" — что предложить на результате
var ir_replay_active: bool = false  # цепочка «Второго рассвета» держится, пока не идеал/не принял
var ir_force_extra: String = ""     # доп. дебафф форс-переигровке ("mono"/"time_minus")
var _is_replay_run: bool = false    # следующий _start_round — это переигровка того же заказа
var _replay_snapshot: Dictionary = {}  # снимок профиля+счётчиков для отката результата

# Пулы эффектов Ир (по знаку) и их метаданные для чипа. id совпадают с браузером.
const IR_POOL := {
	"buff": ["gift", "time_plus", "replay"],
	"debuff": ["mono", "time_minus", "force_replay"],
}
const IR_META := {
	"gift":         {"icon": "🌅", "name": "Рука Ир"},
	"time_plus":    {"icon": "⏱", "name": "Подаренные секунды"},
	"replay":       {"icon": "🔄", "name": "Второй рассвет"},
	"mono":         {"icon": "🌫", "name": "Выцветший мир"},
	"time_minus":   {"icon": "⏳", "name": "Украденные секунды"},
	"force_replay": {"icon": "♻", "name": "Дважды безупречно"},
}
var timer_rate: float = 1.0     # множитель хода таймера варки (Пит: «градус» замедляет до ×2)
var drunk_amount: float = 0.0   # «пьяный» эффект 0..1 (качка камеры + двоение) — от градуса Пита
var drunk_layer: CanvasLayer    # слой поверх экрана с шейдером-двойником
var drunk_rect: ColorRect
var drunk_mat: ShaderMaterial
var _dev_panel: Control          # дев-панель мгновенного теста любого гостя
var _dev_level: int = 4
var _dev_lvl_btns: Array = []

var day_panel: Control
var day_header: Label
var day_cards: VBoxContainer
var day_choices: Array = []      # зафиксированная тройка на текущий день

# постоянная верхняя панель (день/рейтинг/серия + иконки-кнопки) + стрип прогрессии
const TOPBAR_H := 48.0
const STRIP_TOP := 86.0          # верх стрипа прогрессии (под топбаром)
const STRIP_H := 66.0
const CONTENT_TOP := 162.0       # верх контента экранов — ниже топбара и стрипа

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
var topbar_coll_btn: Button      # иконка коллекции (гейт прогрессией)
var _tb_rating_shown: int = 0    # для count-up рейтинга

func _ready() -> void:
	randomize()
	theme = _make_theme()      # единый стиль (кнопки/шрифты) на всё дерево
	_build_ui()
	_show_start()
	_startup_restore()

# Восстановить онлайн-сессию (если вошёл) и подтянуть облачный прогресс.
func _startup_restore() -> void:
	await PotionAuth.restore()
	if start_panel.visible:
		_refresh_hud()

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

# Жирный вариант дефолтного шрифта (без .ttf — эмболдим встроенный).
var _bold_font_cache: FontVariation
func _bold_font() -> FontVariation:
	if _bold_font_cache == null:
		_bold_font_cache = FontVariation.new()
		_bold_font_cache.variation_embolden = 0.6
	return _bold_font_cache

# Стиль ВАЖНОЙ надписи: жир + неоновая обводка-подсветка + тень. Пока на
# встроенном шрифте; настоящий стильный шрифт — по .ttf (см. заметку в ответе).
func _glow_label(l: Label, glow: Color) -> void:
	l.add_theme_font_override("font", _bold_font())
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(glow.r, glow.g, glow.b, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))

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
	# «play» — камера ближе на время игры: окно крупнее, СТОЛ (передний слой) выше
	# (offset вверх синхронизирован с JarStage.TABLE_SCREEN_Y). Тюнится по скрину.
	"play":   [[1.12, 1.0, 0.0],   [1.22, 1.0, -30.0], [1.28, 1.0, -150.0]],
}
func _scene_state(state: String, dur: float = 0.55) -> void:
	var c: Array = SCENE_STATES.get(state, SCENE_STATES["game"])
	_tween_layer(layer_back, c[0], dur)
	_tween_layer(layer_mid, c[1], dur)
	_tween_layer(layer_front, c[2], dur)
	_slide_header(state == "play")     # на игре верхние панели уезжают вверх, иначе — на месте
	if state != "play":                # вне игры — снять «пьяную» качку/двоение
		drunk_amount = 0.0
		_apply_drunk(0.0)

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
	# expand_mode ДО size — иначе min size = размеру текстуры (1152x2048) и size
	# обрежется под него (слой рисуется во всю текстуру от угла = «уезжает»).
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE      # тот же 9:16 — без искажений
	t.texture = load(path)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	t.position = Vector2.ZERO
	t.size = Vector2(720, 1280)
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
	round_ui.offset_top = 18.0               # на игре топбар уезжает — лампы/надписи наверху
	round_ui.offset_right = -36.0
	round_ui.offset_bottom = -28.0
	round_ui.add_theme_constant_override("separation", 14)
	add_child(round_ui)

	# лампочки-таймер сверху (заполняются на «запомни», гаснут на «воссоздай»)
	bulb_bar = BulbBar.new()
	round_ui.add_child(bulb_bar)

	# надпись фазы — ПОД лампочками (в тёмном окне-космосе)
	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 30)
	round_ui.add_child(phase_label)
	_glow_label(phase_label, Color("6ec3ff"))

	# чип активного эффекта Ир (бафф/дебафф) — «висит» весь заказ под надписью фазы
	ir_chip = Label.new()
	ir_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ir_chip.add_theme_font_size_override("font_size", 18)
	ir_chip.visible = false
	round_ui.add_child(ir_chip)

	# банка «на сцене»: спот + барный стол + тень (даёт ей место и точку отсчёта)
	jar_stage = JarStage.new()
	jar_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	round_ui.add_child(jar_stage)
	jar = PotionJarScene.instantiate()
	jar_stage.set_jar(jar)

	var sliders_row := HBoxContainer.new()
	sliders_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sliders_row.add_theme_constant_override("separation", 8)   # плотнее — до 7 колонок влезает
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
		s.hue_track = key == "color" or key == "colorB"   # спектр/спектр Б — радужный градиент
		s.custom_minimum_size = Vector2(70, 300)   # уже — чтобы 7 колонок влезли в кадр
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_slider_changed.bind(key))
		col.add_child(s)
		sliders[key] = s

		var val_lbl := Label.new()
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(val_lbl)
		value_labels[key] = val_lbl

	done_btn = Button.new()
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
		diff_btns[lvl] = b

	# ---- экран результата (в проёме окна, прозрачный) ----
	result_panel = _make_center_panel(true)
	var rv := result_panel.get_node("Card/V") as VBoxContainer
	rv.add_theme_constant_override("separation", 8)

	# картинка-стикер (perfect/good/swill/bad)
	result_sticker_tex = TextureRect.new()
	result_sticker_tex.custom_minimum_size = Vector2(150, 150)
	result_sticker_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_sticker_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_sticker_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_sticker_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(result_sticker_tex)

	# грейд крупно (цветом), процент отдельной строкой ещё крупнее
	result_sticker = Label.new()      # грейд «ГОДНО» / «ИДЕАЛ!» и т.п.
	result_sticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sticker.add_theme_font_size_override("font_size", 36)
	rv.add_child(result_sticker)
	_glow_label(result_sticker, Color("6dff8f"))

	result_points = Label.new()       # «+128 к рейтингу» / чаевые
	result_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_points.add_theme_font_size_override("font_size", 22)
	rv.add_child(result_points)

	result_breakdown = VBoxContainer.new()   # аккуратная разбивка по параметрам
	result_breakdown.custom_minimum_size = Vector2(360, 0)
	result_breakdown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_breakdown.add_theme_constant_override("separation", 2)
	rv.add_child(result_breakdown)

	result_detail = Label.new()       # доп. текст (итог цикла)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail.custom_minimum_size = Vector2(420, 0)
	rv.add_child(result_detail)

	# «Переиграть» (Ир): показывается только когда активен бафф/дебафф переигровки
	result_replay_btn = Button.new()
	result_replay_btn.custom_minimum_size = Vector2(360, 52)
	result_replay_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_replay_btn.visible = false
	result_replay_btn.pressed.connect(_ir_replay)
	rv.add_child(result_replay_btn)

	result_next_btn = Button.new()
	result_next_btn.text = "Дальше →"
	result_next_btn.custom_minimum_size = Vector2(360, 52)
	result_next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_next_btn.pressed.connect(_result_next)
	rv.add_child(result_next_btn)

	var res_menu := Button.new()
	res_menu.text = "← В меню"
	res_menu.custom_minimum_size = Vector2(360, 44)
	res_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	res_menu.pressed.connect(_show_start)
	rv.add_child(res_menu)

	# ---- стартовый экран (главное меню + HUD профиля) ----
	_build_start()
	# ---- экран коллекции (репутация NPC + альбом стикеров + статистика) ----
	_build_collection()
	# ---- список персонажей (кнопка 👥) ----
	_build_chars()
	# ---- страница персонажа (досье, репутация-шкала, пассивки/ачивки) ----
	_build_char()
	# ---- экран профиля/аккаунта (гость / вход / регистрация) ----
	_build_account()
	# ---- экран дня (выбор одного из трёх посетителей) ----
	_build_day()
	# ---- постоянная верхняя панель (над экранами, под рамкой) ----
	_build_topbar()
	# ---- стрип прогрессии под топбаром (постоянный) ----
	_build_prog_strip()
	# ---- «пьяный» слой-двойник поверх всего (шейдер, вкл. по градусу Пита) ----
	drunk_layer = CanvasLayer.new()
	drunk_layer.layer = 5
	add_child(drunk_layer)
	drunk_rect = ColorRect.new()
	drunk_rect.size = Vector2(720, 1280)
	drunk_rect.color = Color(1, 1, 1, 1)
	drunk_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drunk_mat = ShaderMaterial.new()
	drunk_mat.shader = preload("res://shaders/drunk_ghost.gdshader")
	drunk_rect.material = drunk_mat
	drunk_rect.visible = false
	drunk_layer.add_child(drunk_rect)
	# ---- слой тостов (поверх всего) ----
	toast_layer = VBoxContainer.new()
	toast_layer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toast_layer.offset_top = CONTENT_TOP + 6.0
	toast_layer.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_layer.add_theme_constant_override("separation", 8)
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_layer)
	# ---- DEV-кнопка (справа снизу): много прогресса/чаевых/репутации для тестов ----
	var dev_btn := Button.new()
	dev_btn.text = "DEV"
	dev_btn.add_theme_font_size_override("font_size", 13)
	dev_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dev_btn.offset_left = -84.0
	dev_btn.offset_top = -58.0
	dev_btn.offset_right = -18.0
	dev_btn.offset_bottom = -18.0
	dev_btn.modulate = Color(1, 1, 1, 0.6)
	dev_btn.pressed.connect(_dev_open)
	add_child(dev_btn)
	_build_dev_panel()
	# рамкой служит сам бар-арт (bar_frame) — отдельная металлическая рамка не нужна

func _dev_boost() -> void:
	PotionProfile.dev_boost()
	_refresh_hud()
	if prog_strip.visible:
		prog_widget.refresh()
	_toast("DEV: +опыт лавки, +чаевые, реп. со всеми", Color("6dff8f"))

# Дев-панель: мгновенно прыгнуть в раунд любого гостя на любом УР (для теста механик).
func _build_dev_panel() -> void:
	_dev_panel = _make_center_panel()
	var v := _dev_panel.get_node("Card/V") as VBoxContainer
	v.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "DEV — тест гостя"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)
	# выбор уровня сложности
	var lvlrow := HBoxContainer.new()
	lvlrow.alignment = BoxContainer.ALIGNMENT_CENTER
	lvlrow.add_theme_constant_override("separation", 8)
	v.add_child(lvlrow)
	_dev_lvl_btns.clear()
	for l in [1, 2, 3, 4]:
		var b := Button.new()
		b.text = "УР.%d" % l
		b.toggle_mode = true
		b.button_pressed = (l == _dev_level)
		b.pressed.connect(_dev_set_level.bind(l))
		lvlrow.add_child(b)
		_dev_lvl_btns.append(b)
	var boost := Button.new()
	boost.text = "💰 BOOST (опыт/чаевые/реп)"
	boost.pressed.connect(_dev_boost)
	v.add_child(boost)
	# список всех гостей — по кнопке прыгаем прямо в раунд
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 560)
	v.add_child(scroll)
	var grid := VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 4)
	scroll.add_child(grid)
	for e in GameData.NPCS:
		var nb := Button.new()
		nb.text = "%s  ·  тир %d  ·  %s" % [String(e.get("name", e.get("id", "?"))), int(e.get("tier", 1)), String(e.get("id", ""))]
		nb.pressed.connect(_dev_start.bind(e))
		grid.add_child(nb)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(_dev_close)
	v.add_child(close)

func _dev_open() -> void:
	_dev_panel.visible = true

func _dev_close() -> void:
	_dev_panel.visible = false

func _dev_set_level(l: int) -> void:
	_dev_level = l
	for i in _dev_lvl_btns.size():
		_dev_lvl_btns[i].button_pressed = (i == l - 1)

func _dev_start(e: Dictionary) -> void:
	_dev_panel.visible = false
	npc = e
	# минимальный контекст цикла, чтобы топбар/переходы не падали
	if not cycle_active:
		cycle_active = true
		day_num = 1
		cycle_days = GameData.prog_cycle_days(_xp())
		stage = 0
	_start_round(_dev_level)

# Всплывающий тост: панель с текстом, влетает сверху, держится и уходит.
func _toast(text: String, col: Color = Color("6ec3ff"), delay: float = 0.0) -> void:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.11, 0.96)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = col
	sb.shadow_color = Color(col.r, col.g, col.b, 0.35)
	sb.shadow_size = 8
	sb.content_margin_left = 18.0; sb.content_margin_right = 18.0
	sb.content_margin_top = 10.0; sb.content_margin_bottom = 10.0
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_glow_label(l, col)
	p.modulate.a = 0.0
	p.scale = Vector2(0.85, 0.85)
	p.pivot_offset = Vector2(120, 22)
	toast_layer.add_child(p)
	var t := p.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.set_parallel(true)
	t.tween_property(p, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(2.4)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)

func _build_prog_strip() -> void:
	prog_strip = PanelContainer.new()
	prog_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	prog_strip.offset_left = 30.0
	prog_strip.offset_right = -30.0
	prog_strip.offset_top = STRIP_TOP
	prog_strip.offset_bottom = STRIP_TOP + STRIP_H
	prog_strip.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.30, 0.5, 0.6)
	sb.content_margin_left = 8.0; sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0; sb.content_margin_bottom = 4.0
	prog_strip.add_theme_stylebox_override("panel", sb)
	prog_widget = ProgBar.new()
	prog_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_strip.add_child(prog_widget)
	add_child(prog_strip)

func _build_start() -> void:
	start_panel = _make_center_panel(true)    # прозрачная — виден космос/бар
	var sv := start_panel.get_node("Card/V") as VBoxContainer
	sv.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "ЗЕЛЬЕВАРНЯ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	sv.add_child(title)
	_glow_label(title, Color("c07bff"))

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

	coll_btn = Button.new()
	coll_btn.text = "Коллекция"
	coll_btn.custom_minimum_size = Vector2(440, 52)
	coll_btn.pressed.connect(_show_collection)
	sv.add_child(coll_btn)

	var daily_btn := Button.new()      # заглушка под Фазу 2/3
	daily_btn.text = "Ежедневный заказ  (скоро)"
	daily_btn.custom_minimum_size = Vector2(440, 52)
	daily_btn.disabled = true
	sv.add_child(daily_btn)

	profile_btn = Button.new()
	profile_btn.custom_minimum_size = Vector2(440, 52)
	profile_btn.pressed.connect(_show_account)
	sv.add_child(profile_btn)

	# --- громкость: музыка / звуки ---
	var vol_spacer := Control.new()
	vol_spacer.custom_minimum_size = Vector2(0, 6)
	sv.add_child(vol_spacer)
	_audio_row(sv, "🎵 Музыка", true)
	_audio_row(sv, "🔊 Звуки", false)

# Ряд «ярлык + горизонтальный слайдер громкости». is_music → музыка, иначе SFX.
func _audio_row(sv: VBoxContainer, label_text: String, is_music: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(440, 44)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_font_size_override("font_size", 18)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 1.0
	sl.value = (Sfx.music_volume if is_music else Sfx.sfx_volume) * 100.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(280, 40)
	if is_music:
		sl.value_changed.connect(_on_music_vol)
		sl.drag_ended.connect(_on_vol_drag_end)
	else:
		sl.value_changed.connect(_on_sfx_vol)
		sl.drag_ended.connect(_on_sfx_drag_end)
	row.add_child(sl)
	sv.add_child(row)

func _on_music_vol(v: float) -> void:
	Sfx.set_music_volume(v / 100.0)

func _on_sfx_vol(v: float) -> void:
	Sfx.set_sfx_volume(v / 100.0)

func _on_vol_drag_end(_value_changed: bool) -> void:
	PotionProfile.save()             # сохраняем настройку по концу перетаскивания

func _on_sfx_drag_end(_value_changed: bool) -> void:
	PotionProfile.save()
	Sfx.play("tick")                 # превью громкости эффектов

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
	for tab in [["stats", "Статистика"], ["ribbon", "Лента"], ["stickers", "Стикеры"], ["ach", "Ачивки"]]:
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
	char_panel.visible = false
	chars_panel.visible = false
	account_panel.visible = false
	prog_strip.visible = false
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
		"ach": _fill_ach_tab()

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

# ---------- вкладка «Ачивки» (общие ачивки) ----------
func _fill_ach_tab() -> void:
	var opened := 0
	for a in GameData.GENERAL_ACHIEVEMENTS:
		if not a.get("manual", false):
			var val: int = _ach_value(a["id"])
			for th in (a["t"] as Array):
				if val >= int(th):
					opened += 1
	var head := Label.new()
	head.text = "Открыто ступеней: %d / %d" % [opened, GameData.ach_total_tiers()]
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	collection_list.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for a in GameData.GENERAL_ACHIEVEMENTS:
		grid.add_child(_ach_card(a))
	collection_list.add_child(grid)

# Значение метрики ачивки из профиля (порт value(p) из content.js).
func _ach_value(id: String) -> int:
	var st: Dictionary = PotionProfile.data.get("stats", {})
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	var tips: Dictionary = PotionProfile.data.get("tips", {})
	match id:
		"total_score": return int(st.get("total_score_earned", 0))
		"cycle_score": return int(st.get("best_cycle_score", 0))
		"progress": return int(st.get("weighted_progress", 0))
		"perfect_streak": return int(sk.get("perfect_best", 0))
		"goodplus_streak": return int(sk.get("goodplus_best", 0))
		"bad_streak": return int(sk.get("bad_best", 0))
		"swill_total": return int((st.get("stickers_lifetime", {}) as Dictionary).get("swill", 0))
		"tips_total": return int(tips.get("lifetime", 0))
		"cycles": return int(st.get("cycles_completed", 0))
		"orders": return int(st.get("total_orders", 0))
	return 0

# Карточка ачивки: иконка, имя, точки-ступени, прогресс до следующей.
func _ach_card(a: Dictionary) -> Control:
	var manual: bool = a.get("manual", false)
	var thresholds: Array = [] if manual else (a["t"] as Array)
	var n_tiers: int = int(a["tiers"]) if manual else thresholds.size()
	var val: int = 0 if manual else _ach_value(a["id"])
	var filled := 0
	for th in thresholds:
		if val >= int(th): filled += 1
	var unlocked: bool = filled > 0

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.16, 0.95)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color("ffb14d") if unlocked else Color(0.3, 0.32, 0.42, 0.6)
	sb.content_margin_left = 12.0; sb.content_margin_right = 12.0
	sb.content_margin_top = 12.0; sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(64, 64)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture = load(GameData.ach_icon_path(a["img"])) as Texture2D
	if not unlocked:
		ic.modulate = Color(1, 1, 1, 0.35)
	col.add_child(ic)

	var nm := Label.new()
	nm.text = a["name"] if unlocked else "???"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 15)
	nm.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.45)
	col.add_child(nm)

	# точки-ступени
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 4)
	for i in n_tiers:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(16, 16)
		var dsb := StyleBoxFlat.new()
		dsb.set_corner_radius_all(8)
		dsb.bg_color = Color("ffb14d") if i < filled else Color(1, 1, 1, 0.12)
		d.add_theme_stylebox_override("panel", dsb)
		dots.add_child(d)
	col.add_child(dots)

	# прогресс до следующей ступени
	if not manual and filled < thresholds.size():
		var pr := Label.new()
		pr.text = "%d / %d" % [val, int(thresholds[filled])]
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pr.add_theme_font_size_override("font_size", 13)
		pr.modulate = Color(1, 1, 1, 0.6)
		col.add_child(pr)
	return card

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

# Ряд NPC: портрет + имя + репутация ШКАЛОЙ. Встреченный — кликабелен (→ страница
# персонажа). Невстреченные скрыты («???») и некликабельны.
func _npc_row(npc_e: Dictionary) -> void:
	var id: String = npc_e["id"]
	var met: bool = PotionProfile.has_met(id)
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 108)
	btn.disabled = not met
	if met:
		btn.pressed.connect(_show_char.bind(npc_e))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12; row.offset_top = 8; row.offset_right = -12; row.offset_bottom = -8
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var tex: Texture2D = load(GameData.portrait_path(npc_e)) as Texture2D if met else null
	if tex:
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(84, 84)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = tex
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
	else:
		var e := Label.new()
		e.custom_minimum_size = Vector2(84, 84)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.add_theme_font_size_override("font_size", 46)
		e.text = npc_e.get("emoji", "❓") if met else "❓"
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(e)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Label.new()
	nm.text = npc_e["name"] if met else "???"
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", tcol if met else Color(1, 1, 1, 0.4))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	if met:
		col.add_child(_rep_bar_ctl(PotionProfile.get_rep(id), tcol, 15))
	else:
		var l := Label.new()
		l.text = "не встречен"
		l.modulate = Color(1, 1, 1, 0.5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	row.add_child(col)

	chars_list.add_child(btn)

# ---------- экран «Персонажи» (список гостей) ----------
func _build_chars() -> void:
	chars_panel = _make_center_panel()
	var cv := chars_panel.get_node("Card/V") as VBoxContainer
	cv.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Персонажи"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	cv.add_child(title)
	_glow_label(title, Color("6ec3ff"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)
	chars_list = VBoxContainer.new()
	chars_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chars_list.add_theme_constant_override("separation", 8)
	scroll.add_child(chars_list)
	var back := Button.new()
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(_close_overlay)
	cv.add_child(back)

func _show_chars() -> void:
	phase = "chars"
	start_panel.visible = false
	collection_panel.visible = false
	char_panel.visible = false
	account_panel.visible = false
	day_panel.visible = false
	chars_panel.visible = true
	_set_topbar(false)
	prog_strip.visible = false
	for c in chars_list.get_children():
		c.queue_free()
	for npc_e in GameData.NPCS:
		_npc_row(npc_e)
	Juice.fade_in(chars_panel)

# Возврат из оверлея: в день, если цикл активен, иначе в меню.
func _close_overlay() -> void:
	if cycle_active:
		_show_day()
	else:
		_show_start()

# Репутация шкалой-заполнением: «ур.N» + ProgressBar (прогресс внутри уровня).
func _rep_bar_ctl(value: float, tcol: Color, font: int = 16) -> Control:
	var rb: Dictionary = GameData.rep_bar(value)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font)
	lbl.modulate = Color(1, 1, 1, 0.8)
	lbl.text = "Репутация · ур.%d%s" % [int(rb["level"]), "  (макс.)" if rb.get("maxed", false) else ""]
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = float(rb["into"]) / maxf(1.0, float(rb["needed"]))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = tcol
	fsb.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fsb)
	box.add_child(bar)
	return box

# ---------- страница персонажа (досье / репутация-шкала / пассивки / ачивки) ----------
func _build_char() -> void:
	char_panel = _make_center_panel()
	var cv := char_panel.get_node("Card/V") as VBoxContainer
	cv.add_theme_constant_override("separation", 10)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)
	char_list = VBoxContainer.new()
	char_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_list.add_theme_constant_override("separation", 10)
	scroll.add_child(char_list)

	var back := Button.new()
	back.text = "← К списку"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(_show_chars)
	cv.add_child(back)

func _show_char(npc_e: Dictionary) -> void:
	phase = "char"
	chars_panel.visible = false
	collection_panel.visible = false
	char_panel.visible = true
	_set_topbar(false)
	var id: String = npc_e["id"]
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)
	var ns: Dictionary = PotionProfile.npc_stats(id)
	for c in char_list.get_children():
		c.queue_free()

	# шапка: аватар + имя + репутация-шкала
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(_card_avatar(npc_e, 120.0))
	var hcol := VBoxContainer.new()
	hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hcol.alignment = BoxContainer.ALIGNMENT_CENTER
	hcol.add_theme_constant_override("separation", 6)
	var nm := Label.new()
	nm.text = npc_e["name"]
	nm.add_theme_font_size_override("font_size", 26)
	nm.add_theme_color_override("font_color", tcol)
	hcol.add_child(nm)
	hcol.add_child(_rep_bar_ctl(PotionProfile.get_rep(id), tcol, 16))
	head.add_child(hcol)
	char_list.add_child(head)

	# досье
	_char_header("Досье", tcol)
	var doss := Label.new()
	doss.text = GameData.dossier(id)
	doss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	doss.modulate = Color(1, 1, 1, 0.9)
	doss.add_theme_font_size_override("font_size", 17)
	char_list.add_child(doss)

	# пассивки (5, открываются уровнями репутации; эффекты — Фаза 4)
	_char_header("Пассивки", tcol)
	var rep_lvl: int = PotionProfile.get_rep_level(id)
	for n in range(1, 6):
		var open: bool = rep_lvl >= n
		var p := Label.new()
		p.text = ("✓ Пассивка ур.%d — открыта" % n) if open else ("🔒 Пассивка ур.%d — нужна репутация ур.%d" % [n, n])
		p.modulate = Color(1, 1, 1, 0.9) if open else Color(1, 1, 1, 0.45)
		p.add_theme_font_size_override("font_size", 16)
		char_list.add_child(p)

	# ачивки гостя (по 3 градации: бронза/серебро/золото)
	var achs: Array = GameData.npc_achievements(id)
	if not achs.is_empty():
		var opened := 0
		for a in achs:
			opened += _npc_ach_tier(ns, a)
		_char_header("Ачивки  (%d / %d)" % [opened, achs.size() * 3], tcol)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for a in achs:
			grid.add_child(_npc_ach_card(a, ns))
		char_list.add_child(grid)

# Текущая градация NPC-ачивки (0..len(t)) по порогам.
func _npc_ach_tier(ns: Dictionary, ach: Dictionary) -> int:
	var v: int = _npc_ach_value(ns, ach)
	var tier := 0
	for th in (ach.get("t", []) as Array):
		if v >= int(th): tier += 1
	return tier

# Значение метрики NPC-ачивки (порт npcAchValue из game.js).
func _npc_ach_value(ns: Dictionary, ach: Dictionary) -> int:
	match String(ach.get("kind", "")):
		"orders": return int(ns.get("orders", 0))
		"perfects": return int(ns.get("perfects", 0))
		"perfect_streak": return int(ns.get("perfect_streak_best", 0))
		"no_bad_streak": return int(ns.get("no_bad_streak_best", 0))
		"bads": return int(ns.get("bads", 0))
		"picks_cycle": return int(ns.get("picks_cycle_best", 0))
		"hard_perfects": return int(ns.get("hard_perfects", 0))
		"fast_perfects": return int(ns.get("fast_perfects", 0))
		"level4_perfects": return int(ns.get("level4_perfects", 0))
		"weighted": return int(ns.get("weighted", 0))
		"focus_perfects":
			var fp: Dictionary = ns.get("focus_perfects", {})
			if ach.has("focus"):
				return int(fp.get(ach["focus"], 0))
			return int(fp.get("bubbles", 0)) + int(fp.get("color", 0)) + int(fp.get("size", 0))
		"stat":
			return int(ns.get(ach.get("stat", ""), 0)) if ach.has("stat") else 0
	return 0

const TIER_MEDAL := ["🥉", "🥈", "🥇"]
func _npc_ach_card(ach: Dictionary, ns: Dictionary) -> Control:
	var t_list: Array = ach.get("t", [])
	var val: int = _npc_ach_value(ns, ach)
	var tier := 0
	for th in t_list:
		if val >= int(th): tier += 1
	var unlocked: bool = tier > 0

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.16, 0.95)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color("ffb14d") if unlocked else Color(0.3, 0.32, 0.42, 0.6)
	sb.content_margin_left = 12.0; sb.content_margin_right = 12.0
	sb.content_margin_top = 12.0; sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)

	var ic := Label.new()   # иконка ачивки — эмодзи
	ic.text = String(ach.get("icon", "🏅")) if unlocked else "❓"
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.add_theme_font_size_override("font_size", 40)
	if not unlocked:
		ic.modulate = Color(1, 1, 1, 0.5)
	col.add_child(ic)

	var nm := Label.new()
	nm.text = String(ach.get("name", "")) if unlocked else "???"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", 15)
	nm.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.5)
	col.add_child(nm)

	# 3 медали-градации
	var medals := HBoxContainer.new()
	medals.alignment = BoxContainer.ALIGNMENT_CENTER
	medals.add_theme_constant_override("separation", 4)
	for i in t_list.size():
		var m := Label.new()
		m.text = TIER_MEDAL[i] if i < TIER_MEDAL.size() else "•"
		m.add_theme_font_size_override("font_size", 18)
		m.modulate = Color(1, 1, 1, 1) if i < tier else Color(1, 1, 1, 0.2)
		medals.add_child(m)
	col.add_child(medals)

	# подсказка (единственный ключ, если не открыто) или прогресс до следующей
	var sub := Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.55)
	if tier < t_list.size():
		if unlocked:
			sub.text = "%d / %d" % [val, int(t_list[tier])]
		else:
			sub.text = String(ach.get("hint", ""))     # намёк-условие
	else:
		sub.text = "✓ золото"
	col.add_child(sub)
	return card

func _char_header(text: String, tcol: Color) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", tcol)
	char_list.add_child(l)

# ---------- экран профиля/аккаунта ----------
func _build_account() -> void:
	account_panel = _make_center_panel()
	var cv := account_panel.get_node("Card/V") as VBoxContainer
	cv.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Профиль"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	cv.add_child(title)
	_glow_label(title, Color("6ec3ff"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)
	account_list = VBoxContainer.new()
	account_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_list.add_theme_constant_override("separation", 10)
	scroll.add_child(account_list)
	var back := Button.new()
	back.text = "← Меню"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(_show_start)
	cv.add_child(back)

func _show_account() -> void:
	phase = "account"
	start_panel.visible = false
	collection_panel.visible = false
	char_panel.visible = false
	day_panel.visible = false
	account_panel.visible = true
	_set_topbar(false)
	prog_strip.visible = false
	_populate_account()
	Juice.fade_in(account_panel)

func _populate_account() -> void:
	for c in account_list.get_children():
		c.queue_free()
	if PotionAuth.is_logged_in():
		_acc_line("Вошёл: %s" % PotionAuth.get_nickname(), Color("6dff8f"), 22)
		_acc_line("Прогресс синхронизируется между устройствами.", Color(1, 1, 1, 0.7))
		account_list.add_child(_acc_nick_row())
		var out := Button.new()
		out.text = "Выйти"
		out.custom_minimum_size = Vector2(0, 48)
		out.pressed.connect(_acc_logout)
		account_list.add_child(out)
		return

	# --- гость ---
	_acc_line("Гость: %s" % PotionAuth.get_nickname(), Color("ffcf5d"), 22)
	_acc_line("Прогресс сохраняется на этом устройстве.", Color(1, 1, 1, 0.7))
	account_list.add_child(_acc_nick_row())

	var rem := CheckBox.new()
	rem.text = "Запомнить это устройство"
	rem.button_pressed = PotionAuth.get_remember_device()
	rem.toggled.connect(PotionAuth.set_remember_device)
	account_list.add_child(rem)

	# вкладки Вход / Регистрация
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in [["login", "Вход"], ["register", "Регистрация"]]:
		var b := Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.modulate = Color(1, 1, 1, 1) if _auth_tab == t[0] else Color(1, 1, 1, 0.5)
		b.pressed.connect(_acc_set_tab.bind(t[0]))
		tabs.add_child(b)
	account_list.add_child(tabs)

	var is_reg: bool = _auth_tab == "register"
	var login_edit := _acc_input("Логин", false)
	account_list.add_child(login_edit)
	var pw_edit := _acc_input("Пароль", true)
	account_list.add_child(pw_edit)
	var nick_edit: LineEdit = null
	if is_reg:
		nick_edit = _acc_input("Ник (виден в лидерборде)", false)
		account_list.add_child(nick_edit)

	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.modulate = Color(1, 1, 1, 0.8)
	account_list.add_child(msg)

	var submit := Button.new()
	submit.text = "Создать аккаунт" if is_reg else "Войти"
	submit.custom_minimum_size = Vector2(0, 52)
	submit.pressed.connect(_submit_auth.bind(is_reg, login_edit, pw_edit, nick_edit, msg, submit))
	account_list.add_child(submit)

	var guest := Button.new()
	guest.text = "Играть гостем"
	guest.custom_minimum_size = Vector2(0, 48)
	guest.pressed.connect(_show_start)
	account_list.add_child(guest)

func _submit_auth(is_reg: bool, login_edit: LineEdit, pw_edit: LineEdit, nick_edit: LineEdit, msg: Label, submit: Button) -> void:
	submit.disabled = true
	msg.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	msg.text = "Соединение…"
	var res: Dictionary
	if is_reg:
		res = await PotionAuth.register(login_edit.text, pw_edit.text, nick_edit.text if nick_edit else "")
	else:
		res = await PotionAuth.login_user(login_edit.text, pw_edit.text)
	submit.disabled = false
	if bool(res.get("ok", false)):
		_refresh_hud()
		_populate_account()          # покажет «Вошёл: …»
	else:
		msg.add_theme_color_override("font_color", Color("ff6a6a"))
		msg.text = str(res.get("message", "Ошибка"))

func _acc_line(text: String, col: Color, font: int = 16) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", col)
	account_list.add_child(l)

func _acc_input(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(0, 46)
	return e

func _acc_nick_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var edit := LineEdit.new()
	edit.text = PotionAuth.get_nickname()
	edit.custom_minimum_size = Vector2(0, 46)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var btn := Button.new()
	btn.text = "Сменить"
	btn.pressed.connect(_acc_change_nick.bind(edit))
	row.add_child(btn)
	return row

func _acc_logout() -> void:
	PotionAuth.logout()
	_refresh_hud()
	_populate_account()

func _acc_set_tab(tab: String) -> void:
	_auth_tab = tab
	_populate_account()

func _acc_change_nick(edit: LineEdit) -> void:
	if PotionAuth.set_nickname(edit.text):
		_refresh_hud()
		_populate_account()

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
	_glow_label(hint, Color("ffcf5d"))

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

	# иконки-кнопки (Коллекция гейтится прогрессией; остальное — заглушки)
	topbar_coll_btn = _topbar_icon(row, "🗂", "Коллекция", _show_collection, true)
	_topbar_icon(row, "👥", "Персонажи", _show_chars, true)
	_topbar_icon(row, "⚡", "Пассивки", Callable(), false)
	_topbar_icon(row, "👤", "Профиль", _show_account, true)

func _topbar_icon(row: HBoxContainer, glyph: String, tip: String, cb: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = glyph
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(48, 40)
	b.add_theme_font_size_override("font_size", 20)
	b.disabled = not enabled
	if enabled and cb.is_valid():
		b.pressed.connect(cb)
	row.add_child(b)
	return b

func _set_topbar(on: bool) -> void:
	topbar.visible = on
	prog_strip.visible = on
	if on:
		_refresh_topbar()
		prog_widget.refresh()

func _refresh_topbar() -> void:
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	tb_day.text = "День %d / %d   ·   ст.%d" % [day_num, cycle_days, stage + 1]
	tb_streak.text = "🔥 %d" % int(sk.get("goodplus_current", 0))
	topbar_coll_btn.disabled = not GameData.prog_mech_unlocked("collection", _xp())
	if cycle_score != _tb_rating_shown:
		Juice.count_up(tb_rating, _tb_rating_shown, cycle_score, "Рейтинг: %d")
		_tb_rating_shown = cycle_score
	else:
		tb_rating.text = "Рейтинг: %d" % cycle_score

func _xp() -> int:
	return int(PotionProfile.data.get("progression", {}).get("xp", 0))

func _start_cycle() -> void:
	Sfx.enter_game()                 # цикл начался — игровой плейлист
	stage = 0
	day_num = 1
	cycle_score = 0
	perfect_streak_max = 0
	good_streak_max = 0
	cycle_active = true
	_tb_rating_shown = 0
	cycle_days = GameData.prog_cycle_days(_xp())   # длина цикла по прогрессии
	PotionProfile.reset_picks_cycle()
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

	day_header.text = "День %d / %d   ·   стадия %d" % [day_num, cycle_days, stage + 1]
	for c in day_cards.get_children():
		c.queue_free()
	for e in day_choices:
		day_cards.add_child(_day_card(e))
	_set_topbar(true)
	_scene_state("menu")
	Juice.stagger_fade(day_cards.get_children())   # карточки влетают по очереди

# Карточки дня: тиры = STAGE_TABLE[stage] (на макс.стадии серии дают тир-5),
# затем число тиров подгоняется под размер пула прогрессии (2→3→4). NPC берутся
# только из ОТКРЫТЫХ прогрессией; по возможности разные.
func _pick_day_npcs() -> Array:
	var xp: int = _xp()
	var unlocked: Dictionary = GameData.prog_unlocked_npcs(xp)
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
	# подгонка под размер пула (число карточек в дне)
	var pool_size: int = GameData.prog_pool_size(xp)
	if tiers.size() > pool_size:
		tiers = tiers.slice(0, pool_size)
	else:
		while tiers.size() < pool_size:
			tiers.append(tiers[tiers.size() - 1])

	var chosen: Array = []
	var used: Array = []
	for tier in tiers:
		var pool: Array = _npc_pool(tier, unlocked, used)   # открытые этого тира
		if pool.is_empty():
			pool = _npc_pool(-1, unlocked, used)            # любой открытый
		if pool.is_empty():
			pool = _npc_pool(tier, {}, used)                # крайний случай — любой тира
		if pool.is_empty():
			continue
		var pick: Dictionary = pool[randi() % pool.size()]
		used.append(pick["id"])
		chosen.append(pick)
	return chosen

# Пул NPC: tier (-1 = любой), unlocked (пусто = без фильтра открытости), не used.
func _npc_pool(tier: int, unlocked: Dictionary, used: Array) -> Array:
	var pool: Array = []
	for n in GameData.NPCS:
		if used.has(n["id"]):
			continue
		if tier != -1 and int(n.get("tier", 1)) != tier:
			continue
		if not unlocked.is_empty() and not unlocked.has(n["id"]):
			continue
		pool.append(n)
	return pool

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
	Sfx.play("cardPick")
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
	if day_num > cycle_days:
		_show_cycle_end()
	else:
		_new_day()

func _show_cycle_end() -> void:
	Sfx.play("weekEnd")              # итог цикла
	cycle_active = false
	# прогрессия: уровень и открытые NPC ДО начисления опыта
	var xp_before: int = _xp()
	var lvl_before: int = GameData.prog_level(xp_before)
	var unlocked_before: Dictionary = GameData.prog_unlocked_npcs(xp_before)
	var res: Dictionary = PotionProfile.end_cycle(cycle_score)
	var xp_after: int = int(res.get("xp_after", 0))
	var lvl_after: int = GameData.prog_level(xp_after)

	phase = "cycle_end"
	round_ui.visible = false
	result_sticker_tex.visible = false
	result_points.visible = false          # у итога цикла нет очков-за-заказ/разбивки
	result_breakdown.visible = false
	result_sticker.text = "Цикл пройден!"
	result_sticker.add_theme_color_override("font_color", Color("6dff8f"))
	var lines: Array = [
		"Рейтинг цикла: %d" % cycle_score,
		"Циклов всего: %d" % int(res.get("cycles", 0)),
		"Опыт: %d" % xp_after,
	]
	# каскад тостов «в моменте»: повышение уровня, затем новые гости
	var td: float = 0.5
	if lvl_after > lvl_before:
		for lv in range(lvl_before + 1, lvl_after + 1):
			_toast.call_deferred("★ Лавка выросла до ур.%d!" % lv, Color("ffcf5d"), td)
			td += 0.5
	var new_npcs: Array = []
	for id in GameData.prog_unlocked_npcs(xp_after):
		if not unlocked_before.has(id):
			var e: Dictionary = GameData.npc_by_id(id)
			if not e.is_empty():
				new_npcs.append(e["name"])
				var tc: Color = GameData.TIER_COLORS.get(int(e.get("tier", 1)), Color.WHITE)
				_toast.call_deferred("Новый гость: %s" % e["name"], tc, td)
				td += 0.5
	result_detail.text = "\n".join(lines)
	result_detail.visible = true
	if PotionAuth.is_logged_in():
		PotionAuth.push_profile()      # синк прогресса в облако в конце цикла
	# кнопки на экране результата переиспользуем: «Дальше →» стартует новый цикл
	result_replay_btn.visible = false   # переигровка Ир на экран итога цикла не попадает
	result_next_btn.visible = true
	result_panel.visible = true
	_set_topbar(true)
	_scene_state("select")          # итог цикла — тоже в проёме окна
	Juice.fade_in(result_panel)
	Juice.pop.call_deferred(result_sticker)

# ---------- стартовый экран ----------
func _show_start() -> void:
	Sfx.enter_menu()                 # главное меню — трек меню
	phase = "start"
	result_panel.visible = false
	round_ui.visible = false
	select_panel.visible = false
	collection_panel.visible = false
	char_panel.visible = false
	chars_panel.visible = false
	account_panel.visible = false
	day_panel.visible = false
	start_panel.visible = true
	cycle_active = false
	_set_topbar(false)
	prog_strip.visible = true          # на меню топбар скрыт, но прогрессию показываем
	prog_widget.refresh()
	_scene_state("menu")
	_refresh_hud()
	Juice.fade_in(start_panel)

func _refresh_hud() -> void:
	var xp: int = _xp()
	var t: Dictionary = PotionProfile.data.get("tips", {})
	var st: Dictionary = PotionProfile.data.get("stats", {})
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	# чаевые видны только после открытия механики (Ур.4)
	hud_tips.visible = GameData.prog_mech_unlocked("tips", xp)
	hud_tips.text = "%s %d" % [hud_tips.get_meta("icon"), int(t.get("balance", 0))]
	hud_orders.text = "%s %d" % [hud_orders.get_meta("icon"), int(st.get("total_orders", 0))]
	hud_streak.text = "%s %d" % [hud_streak.get_meta("icon"), int(sk.get("goodplus_current", 0))]
	# коллекция открывается прогрессией (Ур.1) — не прячем, а дизейблим с подписью
	var coll_ok: bool = GameData.prog_mech_unlocked("collection", xp)
	coll_btn.disabled = not coll_ok
	coll_btn.text = "Коллекция" if coll_ok else "Коллекция  (откроется на ур.%d)" % GameData.mech_unlock_level("collection")
	# профиль: ник + статус
	profile_btn.text = "👤 %s%s" % [PotionAuth.get_nickname(), "" if PotionAuth.is_logged_in() else "  (гость)"]

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
	var rep_now: int = PotionProfile.get_rep_level(npc["id"])
	tier_badge.text = "★ ТИР %d   ·   Репутация: %s" % [tier, "★".repeat(rep_now) if rep_now > 0 else "—"]
	tier_badge.add_theme_color_override("font_color", tcol)
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(tcol.r, tcol.g, tcol.b, 0.10)
	gsb.set_corner_radius_all(200)                 # большой радиус → круг
	gsb.shadow_color = Color(tcol.r, tcol.g, tcol.b, 0.55)
	gsb.shadow_size = 22
	tier_glow.add_theme_stylebox_override("panel", gsb)

	# УР.4 гейтится репутацией с этим гостем (>= REP_L4_UNLOCK_LEVEL) или флагом
	# level4 (стартовый дрон). Иначе кнопка заблокирована с подсказкой.
	var rep_lvl: int = PotionProfile.get_rep_level(npc["id"])
	var l4_ok: bool = bool(npc.get("level4", false)) or rep_lvl >= GameData.REP_L4_UNLOCK_LEVEL
	var b4: Button = diff_btns[4]
	b4.disabled = not l4_ok
	if l4_ok:
		b4.text = "УР.4 — всё + механика"
	else:
		b4.text = "УР.4 — нужна репутация ур.%d" % GameData.REP_L4_UNLOCK_LEVEL

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
	for ch in jar_stage.get_children():   # снять «залипшую» грязь Уборщика с прошлого заказа
		if ch is GrimeOverlay:
			ch.queue_free()
	for ch in jar.inner_holder().get_children():   # снять «залипшие» детали Роя из банки
		if ch is DragPart:
			ch.queue_free()
	jar.modulate = Color.WHITE     # общий сброс тона банки (страховка)
	jar.set_mono(false)            # снять «Выцветший мир» (ч-б) прошлого заказа
	jar.set_tilt(0.0)              # снять наклон (Сверхнова) прошлого заказа
	ir_effect_id = ""              # эффект прошлого заказа отыграл
	ir_effect_kind = ""
	ir_chip.visible = false
	var replaying: bool = _is_replay_run   # это переигровка того же заказа?
	_is_replay_run = false
	if not replaying:              # свежий заказ — цепочка переигровки сброшена
		ir_replay_active = false
		ir_force_extra = ""
		_replay_snapshot = {}
	jar.set_blur(0.0)              # сбросить размытие (градус Пита) от прошлого заказа
	timer_rate = 1.0               # сбросить замедление таймера (градус Пита)
	drunk_amount = 0.0             # сбросить «пьяный» эффект
	_set_topbar(true)
	_scene_state("play")           # камера ближе; верхние панели уезжают вверх
	_enter_jar()                   # банка выезжает справа на своё место
	Juice.fade_in(round_ui)

	# ВАЖНО: на фазе «ЗАПОМНИ» регуляторы и кнопку прячем целиком — иначе игрок
	# запомнит их положения, а не банку. Появятся на «ВОССОЗДАЙ» (_start_recreate).
	for key in ORDER:
		slider_cols[key].visible = false
	done_btn.visible = false
	_config_sliders_for_npc()      # число позиций ползунков — по тиру гостя

	# уникальная механика гостя (если активна на этом уровне)
	mech = null
	if GameData.mech_active(npc["id"], level):
		mech = NpcMech.make(npc["id"])
		if mech:
			mech.setup(self)

	seed_val = randi()
	target = _random_values()
	# Ир: эффект этого заказа. На переигровке прежний эффект уже отыграл — новый знак
	# не берём; форс-переигровка тащит доп. дебафф. Иначе ожидающий знак → случайный эффект.
	if replaying:
		if ir_force_extra != "":               # «Дважды безупречно»: доп. дебафф на редо
			ir_effect_id = ir_force_extra
			ir_effect_kind = "debuff"
			ir_force_extra = ""
			_show_ir_chip()
	elif ir_pending != "":
		var pool: Array = IR_POOL.get(ir_pending, [])
		if not pool.is_empty():
			ir_effect_id = pool[randi() % pool.size()]
			ir_effect_kind = ir_pending
			_show_ir_chip()
		ir_pending = ""
	# ВАЖНО: на ПЕРВОМ заказе раскладка ещё не посчитана → jar_stage.size == 0, и
	# механики (детали Роя, грязь, доска Векса…) лепят всё в угол. Ждём валидный
	# размер сцены, прежде чем механика начнёт расставлять свои узлы.
	var _sg: int = 0
	while jar_stage.size.x < 1.0 and _sg < 12:
		await get_tree().process_frame
		_sg += 1
	# Инспектор: фазы показа нет — цель описана в «Допусках», сразу к воссозданию
	if mech and mech.skip_memorize(self):
		Sfx.play("orderShow")
		_start_recreate()
		return
	_apply_to_jar(target)          # цель показываем целиком
	for key in ORDER:
		value_labels[key].text = "?"
	phase = "memorize"
	phase_total = MEMORIZE_S
	phase_left = MEMORIZE_S
	bulb_bar.set_fraction(0.0)      # лампы гаснут в начале, будут заполняться
	Sfx.play("orderShow")           # заказ появился
	if mech:
		mech.memorize_start(self)

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
	# теперь показываем регуляторы (стулья выезжают) и кнопку «ГОТОВО»
	for key in ORDER:
		slider_cols[key].visible = key in active
	done_btn.visible = true
	_set_sliders_interactable(true)
	_slide_in_stools()             # стулья выезжают слева направо
	_apply_to_jar(_current_values())
	_update_value_labels(_current_values())
	if mech:
		mech.craft_start(self)
	_apply_ir_effect()             # игровые эффекты выбранного заказу баффа/дебаффа

# «Пьяный» эффект: качка «камеры» (canvas_transform всего кадра) + двоение-призрак.
func _apply_drunk(g: float) -> void:
	if g <= 0.001:
		get_viewport().canvas_transform = Transform2D.IDENTITY
		if drunk_rect != null:
			drunk_rect.visible = false
		return
	var tt: float = Time.get_ticks_msec() / 1000.0
	var ang: float = (sin(tt * 1.7) * 0.020 + sin(tt * 0.9) * 0.010) * g
	var ox: float = (sin(tt * 1.3) * 11.0 + sin(tt * 0.7) * 5.0) * g
	var oy: float = sin(tt * 1.1 + 1.0) * 8.0 * g
	var c := Vector2(360, 640)
	var rot := Transform2D(ang, Vector2.ZERO)
	get_viewport().canvas_transform = Transform2D(ang, c + Vector2(ox, oy) - (rot * c))
	if drunk_rect != null:
		drunk_rect.visible = true
		drunk_mat.set_shader_parameter("amount", g)

# Чип активного эффекта Ир — «висит» весь заказ (иконка + название, цвет по знаку).
func _show_ir_chip() -> void:
	if ir_effect_id == "" or not IR_META.has(ir_effect_id):
		ir_chip.visible = false
		return
	var m: Dictionary = IR_META[ir_effect_id]
	ir_chip.text = "%s %s" % [m["icon"], m["name"]]
	ir_chip.add_theme_color_override("font_color",
		Color("6dff8f") if ir_effect_kind == "buff" else Color("ff9a6a"))
	ir_chip.visible = true

# «Последний из Ир»: игровые эффекты выбранного заказу баффа/дебаффа (по ir_effect_id).
# Вызывается на входе в фазу «ВОССОЗДАЙ», когда ползунки/таймер уже готовы.
func _apply_ir_effect() -> void:
	match ir_effect_id:
		"time_plus":
			phase_total += 4.0; phase_left += 4.0
			_toast("🌅 Подаренные секунды: +4с", Color("6dff8f"))
		"gift":
			var ks: Array = active.duplicate(); ks.shuffle()
			for i in mini(2, ks.size()):
				var k: String = ks[i]
				sliders[k].set_value_no_signal(float(target[k]))
				_on_slider_changed(float(target[k]), k)
			_toast("🌅 Рука Ир: 2 регулятора выставлены", Color("6dff8f"))
		"time_minus":
			phase_total = maxf(4.0, phase_total - 2.0); phase_left = maxf(2.0, phase_left - 2.0)
			_toast("🌫 Украденные секунды: −2с", Color("ff9a6a"))
		"mono":
			jar.set_mono(true)                    # банка ч-б + подмылена
			_toast("🌫 Выцветший мир", Color("ff9a6a"))

# ---------- таймеры фаз ----------
func _process(delta: float) -> void:
	var no_timer: bool = mech != null and mech.no_timer(self)   # Тот-Кто-Ждёт: без таймеров
	if phase == "memorize":
		if no_timer:
			phase_label.text = "ЗАПОМНИ — не спеши, жми ▸"
		else:
			phase_left -= delta
			# лампы ЗАПОЛНЯЮТСЯ по мере запоминания
			bulb_bar.set_fraction(1.0 - clampf(phase_left / phase_total, 0.0, 1.0))
			phase_label.text = "ЗАПОМНИ — %dс" % int(ceil(maxf(phase_left, 0.0)))
			if phase_left <= 0.0:
				_start_recreate()
	elif phase == "recreate":
		if mech:
			mech.process(self, delta)      # покадровый хук механики (таймеры/анимация)
		_apply_drunk(drunk_amount)         # «пьяная» качка камеры + двоение (градус Пита)
		if no_timer:
			phase_label.text = "ВОССОЗДАЙ — жми «Готово»"
		else:
			phase_left -= delta * timer_rate       # градус Пита замедляет ход
			# лампы ГАСНУТ по мере игры
			bulb_bar.set_fraction(clampf(phase_left / phase_total, 0.0, 1.0))
			phase_label.text = "ВОССОЗДАЙ — %dс" % int(ceil(maxf(phase_left, 0.0)))
			if phase_left <= 0.0:
				_finish()

# Насколько верно выставлен один ползунок (0..1) — та же формула, что в _do_finish.
# Нужно механикам (Хранитель Архива, Модница) для правила «выставлен верно».
func _key_score(key: String) -> float:
	var s: TouchSlider = sliders[key]
	var span: float = maxf(0.0001, s.max_value - s.min_value)
	var diff: float = abs(s.value - float(target[key])) / span
	return pow(clampf(1.0 - diff, 0.0, 1.0), 1.6)

# Текущий общий результат (0..1) по активным параметрам — для промежуточных
# замеров механик (чекпоинты Гонщицы и т.п.). Веса как в _do_finish, без мех-веса.
func _current_overall() -> float:
	var o: float = 0.0
	var w: float = 0.0
	for key in active:
		var ww: float = float(PARAMS[key]["weight"])
		o += _key_score(key) * ww
		w += ww
	return o / maxf(w, 0.001)

# ---------- завершение ----------
func _on_done() -> void:
	if phase != "recreate":
		return
	if mech and not mech.on_done(self):   # механика может отменить финиш (Гурман — переигровка)
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
	if mech:
		mech.pre_serve(self)   # напр. детали Роя переезжают внутрь банки перед отъездом
	_serve_jar()

# Банка ВЫЕЗЖАЕТ на своё место справа (зеркало отъезда) — на старте раунда.
func _enter_jar() -> void:
	# На 1-м заказе после запуска jar_stage ещё не разложен (size=0) → домашняя
	# позиция считается криво (банка «сбоку»). Ждём кадр и пересчитываем home.
	jar.visible = false
	await get_tree().process_frame
	jar_stage.reset_jar()
	jar.visible = true
	jar.pivot_offset = Vector2(jar.size.x * 0.5, jar.size.y * 0.92)
	var x0: float = jar.position.x
	jar.rotation = deg_to_rad(-9.0)                     # лёгкий наклон «толчка»
	jar.position.x = x0 - size.x - 300.0                # старт за ЛЕВЫМ краем — выезжает по столу
	var t := jar.create_tween()
	t.tween_property(jar, "position:x", x0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(jar, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Верхние панели (топбар + стрип прогрессии) уезжают вверх на игру и приезжают
# обратно после. hidden=true — вверх за экран; false — на место.
func _slide_header(hidden: bool, dur: float = 0.45) -> void:
	var dy: float = -190.0 if hidden else 0.0
	_tween_offsets(topbar, 30.0 + dy, 30.0 + TOPBAR_H + dy, dur)
	_tween_offsets(prog_strip, STRIP_TOP + dy, STRIP_TOP + STRIP_H + dy, dur)

func _tween_offsets(p: Control, top: float, bot: float, dur: float) -> void:
	if p == null:
		return
	var t := p.create_tween().set_parallel(true)
	t.tween_property(p, "offset_top", top, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "offset_bottom", bot, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Мультяшный отъезд: короткий замах влево, затем разгон вправо с наклоном.
func _serve_jar() -> void:
	Sfx.play("brew")                 # «сварено» — банка уезжает гостю
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
		var s: TouchSlider = sliders[key]
		var span: float = maxf(0.0001, s.max_value - s.min_value)
		var diff: float = abs(s.value - float(target[key])) / span
		var sc: float = pow(clampf(1.0 - diff, 0.0, 1.0), 1.6)
		comps[key] = sc
		# вес параметра может менять механика гостя (Тентаклоид зануляет все, кроме одного)
		var w: float = float(PARAMS[key]["weight"])
		if mech:
			w = mech.weight_for(key, w)
		overall += sc * w
		wsum += w
	overall = overall / maxf(wsum, 0.001)
	# механика может заменить общий результат (Коллекционер — верно/неверно)
	if mech:
		var ov: float = mech.override_overall(self)
		if ov >= 0.0:
			overall = ov
	# множитель рейтинга от механики — берём ДО stop() (таймеры/полоски ещё живы)
	var rating_mult: float = 1.0
	var no_points: bool = false
	if mech:
		rating_mult = mech.score_bonus(self)
		no_points = mech.blocks_points(self, overall)
		mech.stop(self)

	# грейд по порогам тира + запись результата в профиль
	var tier: int = int(npc.get("tier", 1))
	var grade: String = GameData.grade(overall, tier)
	var reward: int = int(GameData.npc_config(npc)["reward"])
	var cat: Array = GameData.STICKERS[grade]
	var sticker_name: String = cat[randi() % GameData.BASE_STICKERS]
	var time_frac: float = clampf(1.0 - phase_left / maxf(0.001, phase_total), 0.0, 1.0)

	# Ир: решаем, предложить ли переигровку ЭТОГО заказа (до записи результата,
	# чтобы можно было откатить профиль/счётчики к состоянию «до результата»).
	var perfect: bool = grade == "perfect"
	ir_replay_mode = ""
	if ir_effect_id == "replay" and not perfect:
		ir_replay_active = true                   # «Второй рассвет» держится, пока не идеал
	if ir_effect_id == "force_replay" and perfect:
		ir_replay_mode = "forced"                 # «Дважды безупречно»: идеал доказать заново
		ir_force_extra = "mono" if randf() < 0.5 else "time_minus"
	elif ir_replay_active and not perfect:
		ir_replay_mode = "optional"
	if ir_replay_mode != "":
		_replay_snapshot = {
			"profile": PotionProfile.data.duplicate(true),
			"cycle_score": cycle_score,
			"last_grade": last_grade,
		}

	var outcome: Dictionary = PotionProfile.record_result(
		npc["id"], tier, overall, grade, reward, sticker_name,
		time_frac, level, "", rating_mult, no_points)

	# «Последний из Ир» (УР.3+): идеал → бафф след. заказу, брак/пойло → дебафф
	if String(npc.get("id", "")) == "last_of_ir" and level >= 3:
		if grade == "perfect":
			ir_pending = "buff"
		elif grade != "good":
			ir_pending = "debuff"

	# для перехода дня/цикла
	last_grade = grade
	cycle_score += int(outcome.get("points", 0))

	_show_result(overall, comps, grade, outcome, sticker_name)

# «Дальше →» на экране результата: конец цикла → новый цикл, иначе → следующий день.
func _result_next() -> void:
	# принял результат — цепочка переигровки Ир закрыта, снимок больше не нужен
	ir_replay_active = false
	ir_force_extra = ""
	_replay_snapshot = {}
	ir_replay_mode = ""
	if phase == "cycle_end":
		_start_cycle()
	else:
		_after_order()

# «Переиграть» (Ир): откатываем профиль и счётчики цикла к «до результата» и
# заново запускаем ТОТ ЖЕ заказ (новая случайная цель). Эффект Ир уже отыграл;
# на форс-переигровке навешивается доп. дебафф (ir_force_extra), см. _start_round.
func _ir_replay() -> void:
	if not _replay_snapshot.is_empty():
		PotionProfile.data = _replay_snapshot["profile"]
		PotionProfile.save()                     # откат в профиле — на диск
		cycle_score = int(_replay_snapshot["cycle_score"])
		last_grade = String(_replay_snapshot["last_grade"])
		_replay_snapshot = {}
	_refresh_hud()                               # счёт/чаевые/репутация обратно к «до»
	ir_pending = ""                              # знак уже превратился в эффект
	ir_replay_mode = ""
	_is_replay_run = true
	_start_round(level)                          # тот же гость (npc), тот же уровень

const GRADE_LABEL := {"perfect": "ИДЕАЛ!", "good": "ГОДНО", "swill": "ПОЙЛО", "bad": "БРАК"}

const GRADE_COLOR := {
	"perfect": Color("6ec3ff"), "good": Color("6dff8f"),
	"swill": Color("ffcf5d"), "bad": Color("ff6a6a"),
}
func _show_result(overall: float, comps: Dictionary, grade: String, outcome: Dictionary, sticker_name: String) -> void:
	phase = "result"
	round_ui.visible = false
	var gcol: Color = GRADE_COLOR.get(grade, Color.WHITE)
	# звук по грейду: идеал/годно — позитив, пойло/брак — неудача
	Sfx.play("perfect" if grade == "perfect" else "good" if grade == "good" else "bad")
	if bool(outcome.get("level_up", false)):
		Sfx.play("achieve")

	# стикер-картинка + грейд крупно (цветом) с процентом
	var stex := load(GameData.sticker_path(sticker_name)) as Texture2D
	result_sticker_tex.texture = stex
	result_sticker_tex.visible = stex != null
	result_sticker.text = "%s   %d%%" % [GRADE_LABEL.get(grade, "БРАК"), int(round(overall * 100.0))]
	result_sticker.add_theme_color_override("font_color", gcol)
	result_sticker.add_theme_color_override("font_outline_color", Color(gcol.r, gcol.g, gcol.b, 0.5))

	# очки за заказ (+рейтинг) и чаевые — крупно и цветом
	var points: int = int(outcome.get("points", 0))
	var speed_pct: int = int(outcome.get("speed_pct", 0))
	result_points.visible = true
	if points > 0:
		var pparts: Array = ["+%d к рейтингу" % points]
		if int(outcome.get("tip", 0)) > 0:
			pparts.append("+%d 🪙" % int(outcome["tip"]))
		var txt := "   ".join(pparts)
		if speed_pct > 0:
			txt += "\n⚡ бонус за скорость: +%d%%" % speed_pct
		result_points.text = txt
		result_points.add_theme_color_override("font_color", Color("6dff8f"))
	elif points < 0:
		result_points.text = "%d к рейтингу" % points     # минус уже в числе
		result_points.add_theme_color_override("font_color", Color("ff6a6a"))
	else:
		result_points.text = "рейтинг не начислен"
		result_points.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))

	# аккуратная разбивка по параметрам: имя слева, % справа (цветом по значению)
	for c in result_breakdown.get_children():
		c.queue_free()
	for key in active:
		var pct: int = int(round(float(comps[key]) * 100.0))
		var rowb := HBoxContainer.new()
		var nl := Label.new()
		nl.text = PARAMS[key]["label"]
		nl.modulate = Color(1, 1, 1, 0.8)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rowb.add_child(nl)
		var vl := Label.new()
		vl.text = "%d%%" % pct
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.add_theme_color_override("font_color", _pct_color(pct))
		rowb.add_child(vl)
		result_breakdown.add_child(rowb)
	result_breakdown.visible = true

	# доп. строка: гость · уровень (+ пояснение механики, если есть)
	var det := "%s · %s" % [npc["name"], LEVEL_DESC[level]]
	if mech:
		var note: String = mech.result_note(self)
		if note != "":
			det += "\n" + note
	result_detail.text = det
	result_detail.visible = true
	if bool(outcome.get("level_up", false)):
		var tcol: Color = GameData.TIER_COLORS.get(int(npc.get("tier", 1)), Color.WHITE)
		_toast.call_deferred("★ Репутация с «%s»: ур.%d" % [npc["name"], int(outcome["level_after"])], tcol)

	# Ир: кнопки переигровки. forced — «Дальше» скрыта (идеал придётся доказать заново).
	result_replay_btn.visible = ir_replay_mode != ""
	if ir_replay_mode == "forced":
		result_replay_btn.text = "♻ Переиграть идеал"
	elif ir_replay_mode == "optional":
		result_replay_btn.text = "🔄 Ещё попытка"
	result_next_btn.visible = ir_replay_mode != "forced"

	result_panel.visible = true
	_set_topbar(true)
	_scene_state("select")          # результат — в проёме окна (как выбор)
	Juice.fade_in(result_panel)
	if result_sticker_tex.visible:
		Juice.pop.call_deferred(result_sticker_tex)
	if grade == "perfect" or grade == "good":
		_confetti_at.call_deferred(result_sticker_tex, gcol)

# Цвет процента: чем выше — тем «холоднее»/зеленее.
func _pct_color(pct: int) -> Color:
	if pct >= 95: return Color("6ec3ff")
	if pct >= 80: return Color("6dff8f")
	if pct >= 60: return Color("cfe86a")
	return Color("ff8a6a")

# Всплеск конфетти в центре узла (глобальные координаты берём после layout).
func _confetti_at(node: Control, col: Color) -> void:
	if node != null and node.visible:
		Juice.burst(self, node.get_global_rect().get_center(), col)

# ---------- вспомогательное ----------
# Число позиций каждого ползунка — по тиру гостя (colorSteps/sizeSteps/...).
# Чем выше тир — тем мельче деления (труднее попасть). Диапазоны значений те же.
func _config_sliders_for_npc() -> void:
	var cfg: Dictionary = GameData.npc_config(npc)
	for key in ORDER:
		var s: TouchSlider = sliders[key]
		match key:
			"color", "colorB":
				var n: int = maxi(2, int(cfg["color_steps"]))
				s.min_value = 0.0
				s.step = 360.0 / float(n)
				s.max_value = 360.0 - s.step        # n оттенков без дубля на 360°
			"volume":
				var n: int = maxi(2, int(cfg["size_steps"]))
				s.min_value = 10.0
				s.max_value = 100.0
				s.step = 90.0 / float(n - 1)
			"count":
				var n: int = maxi(1, int(cfg["count_max"]))
				s.min_value = 1.0
				s.max_value = float(n)
				s.step = 1.0
			"bsize":
				var n: int = maxi(2, int(cfg["bsize_steps"]))
				s.min_value = 10.0
				s.max_value = 100.0
				s.step = 90.0 / float(n - 1)

# Случайные значения на СЕТКЕ ползунков (после _config_sliders_for_npc).
func _random_values() -> Dictionary:
	var v: Dictionary = {}
	for key in ORDER:
		var s: TouchSlider = sliders[key]
		var steps: int = int(round((s.max_value - s.min_value) / s.step))
		v[key] = s.min_value + s.step * float(randi() % (steps + 1))
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
	# накал — только когда активен (УР.4); иначе прежняя константа 0.72.
	# ВАЖНО: пол насыщенности 30% (как satFromIdx=30+idx*70/9 в оригинале) —
	# иначе при нуле жидкость серая и целевой СПЕКТР невозможно считать на «ЗАПОМНИ».
	var sat_actual: float = 0.72
	if "sat" in active and vals.has("sat"):
		var sp: Dictionary = PARAMS["sat"]
		var f: float = (float(vals["sat"]) - float(sp["min"])) / (float(sp["max"]) - float(sp["min"]))
		sat_actual = 0.30 + f * 0.70
	# отдельная высота — только у Сверхновой (size2 активен); иначе равномерный масштаб
	var hfrac: float = -1.0
	if "size2" in active and vals.has("size2"):
		var hp: Dictionary = PARAMS["size2"]
		hfrac = (float(vals["size2"]) - float(hp["min"])) / (float(hp["max"]) - float(hp["min"]))
	# 2-й счётчик — только у Двуликой (countB активен); иначе 0 = обычная банка
	var c2: int = 0
	if "countB" in active and vals.has("countB"):
		c2 = int(vals["countB"])
	# уровень жидкости — только у Пита (fill активен); иначе -1 = уровень по умолчанию
	var fill_frac: float = -1.0
	if "fill" in active and vals.has("fill"):
		fill_frac = float(vals["fill"]) / 100.0
	# 2-й спектр — только у Двуликой (colorB активен); иначе -1 = одноцветная жидкость
	var hue2v: float = -1.0
	if "colorB" in active and vals.has("colorB"):
		hue2v = float(vals["colorB"])
	jar.set_potion(float(vals["color"]), vsize, int(vals["count"]), bfrac, seed_val, sat_actual, hfrac, c2, fill_frac, hue2v)
	# наклон сосуда — только у Сверхновой на УР.4 (rotation активен); иначе прямо
	var tilt_deg: float = 0.0
	if "rotation" in active and vals.has("rotation"):
		tilt_deg = float(vals["rotation"])
	jar.set_tilt(tilt_deg)

var _atmo_t: int = 0                 # троттлинг атмо-звука ползунков (110мс)
var _prev_slider: Dictionary = {}    # прошлое значение для направления (объём/высота)

func _on_slider_changed(value: float, key: String) -> void:
	if phase != "recreate":
		return
	_apply_to_jar(_current_values())
	value_labels[key].text = _fmt(key, sliders[key].value)
	Sfx.play("tick")
	_atmo_slider_sound(key, value)

# Атмосферный звук по типу параметра (порт atmoSliderSound): объём/высота →
# liquidUp/Down, спектр → colorShift, сгустки/размер → bubble, накал → stir.
func _atmo_slider_sound(key: String, v: float) -> void:
	var old: float = float(_prev_slider.get(key, v))
	_prev_slider[key] = v
	var now: int = Time.get_ticks_msec()
	if now - _atmo_t < 110:
		return
	var snd := ""
	match key:
		"volume", "size2": snd = "liquidUp" if v > old else "liquidDown"
		"color": snd = "colorShift"
		"sat": snd = "stir"
		"count", "bsize": snd = "bubble"
	if snd != "":
		_atmo_t = now
		Sfx.play(snd)

func _update_value_labels(vals: Dictionary) -> void:
	for key in ORDER:
		value_labels[key].text = _fmt(key, float(vals[key])) if key in active else "?"

func _fmt(key: String, value: float) -> String:
	return "%d%s" % [int(round(value)), PARAMS[key]["suffix"]]

func _set_sliders_interactable(on: bool) -> void:
	for key in ORDER:
		sliders[key].editable = on
		sliders[key].modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.45)
