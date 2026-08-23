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
var order_focus: String = ""     # фокус-заказ ("bubbles"/"color"/"size"/"") — Фаза 3
var order_mods: Array = []       # поведенческие модификаторы заказа (timer/duck/rampage)
var day_order_mods: Dictionary = {}   # id гостя дня → {"focus":..., "mods":[...]} (для карточек выбора)
# Фаза 7: умения игрока (работают на экране дня, тратят заряды)
var guaranteed_npc: String = ""       # 👀 «Кто там?» — гость, гарантированно придёт
var banned_npcs: Dictionary = {}      # 🚫 «Не пускать» — id забанены до конца цикла
var skill_dock: HBoxContainer = null
var skill_btns: Dictionary = {}       # id умения → Button
var skill_pips: Array = []            # ColorRect-индикаторы зарядов
var skill_overlay: Control = null     # окно выбора гостя (who/ban)
# Ежедневный заказ: одна и та же тройка у всех по дате; прогресс не трогаем
var daily_mode: bool = false
var daily_diff: String = ""
var daily_seq: Array = []
var _daily_backup: Dictionary = {}
var _daily_end: bool = false
const DAILY_DAYS := 10
const DAILY_PROFILES := {
	"easy": {"tier": 3, "label": "Серьёзно?"},
	"mid":  {"tier": 4, "label": "Ок"},
	"hard": {"tier": 5, "label": "Так и было задумано"},
}
var item_fx: Dictionary = {}          # эффекты применённых предметов на ТЕКУЩИЙ заказ
var item_pending: Dictionary = {}     # эффекты «на следующий заказ» (Секундомер/Ясность)
var pogrom_removed: Array = []   # id гостей, выбывших из цикла из-за «Погрома»
var mod_chip: Label              # плашка фокуса/модификаторов под надписью фазы

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
var result_glow: Panel            # свечение-ореол за стикером (цвет грейда)
var result_points_box: PanelContainer   # награда в золотой панели
var result_breakdown_box: PanelContainer # разбивка в карточке
var result_info: VBoxContainer    # зона окна: стикер/грейд/награда/разбивка
var result_actions: VBoxContainer # зона стены: крупные кнопки

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
var _auto_finish: bool = false  # заказ завершён истёкшим таймером (не кнопкой) — для стикеров
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
var items_btn: Button            # «сумка» — применить предметы в игре (Фаза 6)
var _dev_level: int = 4
var _dev_lvl_btns: Array = []

var day_panel: Control
var day_header: Label
var day_cards: VBoxContainer
var day_choices: Array = []      # зафиксированная тройка на текущий день

# постоянная верхняя панель (день/рейтинг/серия + иконки-кнопки) + стрип прогрессии
const TOPBAR_H := 78.0           # выше — крупные тач-иконки
const STRIP_TOP := 116.0         # верх стрипа прогрессии (под топбаром)
const STRIP_H := 156.0           # прогресс-бар + строка день/серия/рейтинг + стикеры (крупно для телефона)
const CONTENT_TOP := 284.0       # верх контента экранов — ниже топбара и стрипа

# Три параллакс-слоя по Z: задний (космос) → средний (стена с окном) →
# передний (стол+пол). Окно среднего слоя прозрачно — сквозь него виден космос.
const WINDOW_UV := Rect2(0.045, 0.221, 0.910, 0.564)   # проём окна в UV арта (0..1): y 0.221..0.785
var layer_back: TextureRect      # космос (дальний)
var layer_mid: TextureRect       # стена с окном
var layer_front: TextureRect     # стол + пол (ближний)
var window_shutter: ColorRect    # шторка, падающая на окно во время игры
var topbar: PanelContainer
var tb_day: Label
var tb_rating: Label
var tb_streak: Label
var _tb_stickers: HBoxContainer   # иконки стикеров за цикл (под прогрессией)
var _tb_info: HBoxContainer        # строка день/серия/рейтинг/стикеры
var _tb_info_spacer: Control       # распорка между рейтингом и стикерами
var _sticker_icon_size: float = 34.0
var cycle_stickers: Dictionary = {"perfect": 0, "good": 0, "swill": 0, "bad": 0}
var topbar_coll_btn: Button      # иконка коллекции (гейт прогрессией)
var _topbar_nav: Array = []      # все nav-иконки (для гейтинга дейлика)
var settings_btn: Button = null  # кнопка настроек (язык/громкость)
var nav_lb_btn: Button = null    # кнопка лидерборда (в дейлике остаётся)
var settings_panel: Control = null
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

# Один фоновый слой: ПОКРЫВАЕТ весь реальный экран любой пропорции (кроп по краям),
# а не фиксированные 720×1280 — иначе на высоком телефоне снизу пустая полоса.
# Размер/пивот обновляются при ресайзе (см. _on_bg_resized). Камера тви́нит scale/position.
func _bg_layer(path: String) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # заполнить экран, обрезав лишнее
	t.texture = load(path)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	t.position = Vector2.ZERO
	var vp := get_viewport().get_visible_rect().size
	t.size = vp
	t.pivot_offset = vp * 0.5
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t

# Фон покрывает актуальный размер вьюпорта — обновляем при смене размера окна/экрана
# (ориентация, разворачивание в APK/браузере). scale/position камеры не трогаем.
func _on_bg_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	for l in [layer_back, layer_mid, layer_front]:
		if l != null:
			l.size = vp
			l.pivot_offset = vp * 0.5
	_layout_result()

# Экранные метрики фона (cover 9:16): прямоугольник проёма окна и Y линии стола —
# чтобы привязывать игровой UI к арту на ЛЮБОЙ пропорции (телефон/комп/APK).
const BG_ASPECT := 1152.0 / 2048.0   # 9:16
const TABLE_UV_Y := 0.519            # линия стола в UV арта (664/1280)
func _bg_metrics() -> Dictionary:
	var vp := get_viewport().get_visible_rect().size
	var disp_h: float = (vp.x / BG_ASPECT) if (vp.x / vp.y > BG_ASPECT) else vp.y
	var disp_w: float = disp_h * BG_ASPECT
	var off := Vector2((vp.x - disp_w) * 0.5, (vp.y - disp_h) * 0.5)
	var win := Rect2(off.x + WINDOW_UV.position.x * disp_w, off.y + WINDOW_UV.position.y * disp_h,
		WINDOW_UV.size.x * disp_w, WINDOW_UV.size.y * disp_h)
	return {"vp": vp, "win": win, "table_y": off.y + TABLE_UV_Y * disp_h}

# Разложить экран результата по зонам арта: инфо — в проёме окна, кнопки — на стене.
func _layout_result() -> void:
	if result_info == null:
		return
	var m := _bg_metrics()
	var win: Rect2 = m["win"]
	var vp: Vector2 = m["vp"]
	var table_y: float = m["table_y"]
	var pad := 18.0
	var win_bottom: float = win.position.y + win.size.y
	# инфо — в верхней части проёма окна (стикер/грейд/награда/разбивка)
	result_info.offset_left = win.position.x + pad
	result_info.offset_top = win.position.y + pad
	result_info.offset_right = win.position.x + win.size.x - pad
	result_info.offset_bottom = win_bottom - 8.0
	# кнопки — НИЖЕ низа окна (на «стене»), по центру, фикс. ширина
	var cx := vp.x * 0.5
	result_actions.offset_left = cx - 236.0
	result_actions.offset_right = cx + 236.0
	result_actions.offset_top = maxf(win_bottom, table_y) + 12.0
	result_actions.offset_bottom = vp.y - 20.0

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
	get_viewport().size_changed.connect(_on_bg_resized)   # фон следит за реальным размером экрана

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

	# плашка фокуса/модификаторов заказа (Фаза 3) — «висит» весь заказ
	mod_chip = Label.new()
	mod_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mod_chip.add_theme_font_size_override("font_size", 18)
	mod_chip.visible = false
	round_ui.add_child(mod_chip)

	# банка «на сцене»: спот + барный стол + тень (даёт ей место и точку отсчёта)
	jar_stage = JarStage.new()
	jar_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	round_ui.add_child(jar_stage)
	jar = PotionJarScene.instantiate()
	jar_stage.set_jar(jar)

	var sliders_row := HBoxContainer.new()
	sliders_row.add_theme_constant_override("separation", 6)
	sliders_row.size_flags_vertical = Control.SIZE_SHRINK_END   # прижат к низу (зона «под столом»)
	round_ui.add_child(sliders_row)

	for key in ORDER:
		var p: Dictionary = PARAMS[key]
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # колонки делят ширину поровну
		col.add_theme_constant_override("separation", 4)
		sliders_row.add_child(col)
		slider_cols[key] = col

		var name_lbl := Label.new()
		name_lbl.text = p["label"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 15)
		col.add_child(name_lbl)

		var s := TouchSlider.new()
		s.min_value = p["min"]
		s.max_value = p["max"]
		s.step = p["step"]
		s.value = p["min"]
		s.hue_track = key == "color" or key == "colorB"   # спектр/спектр Б — радужный градиент
		s.custom_minimum_size = Vector2(84, 330)   # выше + крупная тач-цель; по центру своей доли
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
	done_btn.custom_minimum_size = Vector2(460, 76)   # крупная тач-цель у самого низа
	done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done_btn.add_theme_font_size_override("font_size", 26)
	done_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		done_btn.add_theme_stylebox_override(st, _tab_sb(true))
	done_btn.add_theme_color_override("font_color", UI_GOLD)
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

	# ---- экран результата: инфо — в проёме окна, кнопки — ниже, на «стене», крупные ----
	result_panel = _make_center_panel(true)
	# ЗОНА ОКНА (проём) и ЗОНА КНОПОК (ниже, на стене) — позиции считает _layout_result()
	# по реальному экранному прямоугольнику окна/линии стола (см. _bg_metrics), чтобы
	# совпадать с артом на любой пропорции (телефон/комп/APK).
	result_info = VBoxContainer.new()
	result_info.set_anchors_preset(Control.PRESET_TOP_LEFT)   # абсолютные offset'ы
	result_info.alignment = BoxContainer.ALIGNMENT_CENTER
	result_info.add_theme_constant_override("separation", 10)
	result_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.add_child(result_info)
	result_actions = VBoxContainer.new()
	result_actions.set_anchors_preset(Control.PRESET_TOP_LEFT)
	result_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	result_actions.add_theme_constant_override("separation", 12)
	result_panel.add_child(result_actions)
	var rv := result_info
	var ract := result_actions

	# «герой»: стикер в круглом свечении-ореоле (цвет — по грейду в _show_result)
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(230, 230)
	hero.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(hero)
	result_glow = Panel.new()
	result_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_glow.offset_left = 24; result_glow.offset_top = 24
	result_glow.offset_right = -24; result_glow.offset_bottom = -24
	result_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(result_glow)
	result_sticker_tex = TextureRect.new()
	result_sticker_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_sticker_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_sticker_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_sticker_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(result_sticker_tex)

	# грейд крупно (цветом) + процент
	result_sticker = Label.new()      # грейд «ГОДНО» / «ИДЕАЛ!» и т.п.
	result_sticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sticker.add_theme_font_size_override("font_size", 46)
	rv.add_child(result_sticker)
	_glow_label(result_sticker, Color("6dff8f"))

	# награда — в золотой панели (крупно)
	result_points_box = PanelContainer.new()
	result_points_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_points_box.add_theme_stylebox_override("panel", _panel_sb(UI_GOLD, UI_PANEL, 14))
	result_points = Label.new()       # «+128 к рейтингу» / чаевые
	result_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_points.add_theme_font_size_override("font_size", 24)
	result_points.custom_minimum_size = Vector2(360, 0)
	result_points_box.add_child(result_points)
	rv.add_child(result_points_box)

	# разбивка по параметрам — в карточке
	result_breakdown_box = PanelContainer.new()
	result_breakdown_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_breakdown_box.add_theme_stylebox_override("panel", _panel_sb(UI_BORDER, UI_PANEL, 14))
	result_breakdown = VBoxContainer.new()   # аккуратная разбивка по параметрам
	result_breakdown.custom_minimum_size = Vector2(360, 0)
	result_breakdown.add_theme_constant_override("separation", 3)
	result_breakdown_box.add_child(result_breakdown)
	rv.add_child(result_breakdown_box)

	result_detail = Label.new()       # доп. текст (итог цикла)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail.custom_minimum_size = Vector2(420, 0)
	result_detail.add_theme_color_override("font_color", UI_TXT_DIM)
	rv.add_child(result_detail)

	# «Переиграть» (Ир): показывается только когда активен бафф/дебафф переигровки
	result_replay_btn = Button.new()
	result_replay_btn.custom_minimum_size = Vector2(468, 62)
	result_replay_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_replay_btn.add_theme_font_size_override("font_size", 19)
	result_replay_btn.focus_mode = Control.FOCUS_NONE
	result_replay_btn.visible = false
	result_replay_btn.pressed.connect(_ir_replay)
	ract.add_child(result_replay_btn)

	result_next_btn = Button.new()
	result_next_btn.text = "Дальше →"
	result_next_btn.custom_minimum_size = Vector2(468, 82)   # крупная primary у стены
	result_next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_next_btn.add_theme_font_size_override("font_size", 26)
	result_next_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		result_next_btn.add_theme_stylebox_override(st, _tab_sb(true))   # золотая «primary»
	result_next_btn.add_theme_color_override("font_color", UI_GOLD)
	result_next_btn.pressed.connect(_result_next)
	ract.add_child(result_next_btn)

	var res_menu := Button.new()
	res_menu.text = "← В меню"
	res_menu.custom_minimum_size = Vector2(468, 60)
	res_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	res_menu.add_theme_font_size_override("font_size", FS_BODY)
	res_menu.focus_mode = Control.FOCUS_NONE
	res_menu.pressed.connect(_show_start)
	ract.add_child(res_menu)

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

	# ---- кнопка «сумка» (слева снизу): применить предметы в игре (Фаза 6) ----
	items_btn = Button.new()
	var bag_tex := load("res://assets/ui/nav_bag.png") as Texture2D
	if bag_tex != null:
		items_btn.icon = bag_tex
		items_btn.expand_icon = true
	else:
		items_btn.text = "🎒"
		items_btn.add_theme_font_size_override("font_size", 40)
	items_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	items_btn.offset_left = 14.0
	items_btn.offset_top = -98.0
	items_btn.offset_right = 94.0
	items_btn.offset_bottom = -18.0
	items_btn.focus_mode = Control.FOCUS_NONE
	items_btn.tooltip_text = "Предметы"
	items_btn.visible = false
	items_btn.pressed.connect(_open_items)
	add_child(items_btn)
	# рамкой служит сам бар-арт (bar_frame) — отдельная металлическая рамка не нужна

func _dev_reset() -> void:
	PotionProfile.reset()                        # профиль → пустой (с нуля)
	if PotionAuth.is_logged_in():
		PotionAuth.push_profile()                # затираем и облачную копию
	# сбрасываем состояние сессии
	daily_mode = false; daily_diff = ""; _daily_backup = {}; _daily_end = false
	banned_npcs = {}; guaranteed_npc = ""
	cycle_active = false; cycle_score = 0; _tb_rating_shown = 0
	stage = 0; day_num = 1; perfect_streak_max = 0; good_streak_max = 0
	_dev_close()
	_show_start()
	_toast("☢ Профиль сброшен — начинаем с нуля", Color("ff9a6a"))

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
	var reset := Button.new()
	reset.text = "☢ ПОЛНЫЙ СБРОС (с нуля)"
	reset.add_theme_color_override("font_color", Color("ff6a6a"))
	reset.pressed.connect(_dev_reset)
	v.add_child(reset)
	# список всех гостей — по кнопке прыгаем прямо в раунд
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
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
	day_order_mods[String(e.get("id", ""))] = _roll_order_mods(e, true)   # DEV: гарантируем модификатор
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
	sb.content_margin_left = 10.0; sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0; sb.content_margin_bottom = 5.0
	prog_strip.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	prog_strip.add_child(vb)
	prog_widget = ProgBar.new()
	prog_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(prog_widget)
	# строка под прогрессией: день/серия/рейтинг + стикеры за цикл (крупно для телефона)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	vb.add_child(info)
	_tb_info = info
	tb_day = Label.new()
	tb_day.add_theme_font_size_override("font_size", 22)
	info.add_child(tb_day)
	tb_streak = Label.new()
	tb_streak.add_theme_font_size_override("font_size", 22)
	tb_streak.modulate = Color(1.0, 0.7, 0.4)
	info.add_child(tb_streak)
	tb_rating = Label.new()
	tb_rating.add_theme_font_size_override("font_size", 22)
	info.add_child(tb_rating)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(sp)
	_tb_info_spacer = sp
	# иконки стикеров за цикл (идеал/годно/пойло/брак) с счётчиками
	_tb_stickers = HBoxContainer.new()
	_tb_stickers.add_theme_constant_override("separation", 9)
	info.add_child(_tb_stickers)
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

	# HUD профиля: чипы чаевые / заказы / серия (иконки + число)
	var hud := HBoxContainer.new()
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	hud.add_theme_constant_override("separation", 14)
	sv.add_child(hud)
	hud_tips = _hud_chip(hud, "stat_tips")
	hud_orders = _hud_chip(hud, "stat_orders")
	hud_streak = _hud_chip(hud, "stat_streak")

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	sv.add_child(spacer)

	var play := _menu_button("ИГРАТЬ", true, 66)
	play.pressed.connect(_start_cycle)
	sv.add_child(play)

	coll_btn = _menu_button("Коллекция")
	coll_btn.pressed.connect(_show_collection)
	sv.add_child(coll_btn)

	var daily_btn := _menu_button("Ежедневный заказ")
	daily_btn.pressed.connect(_open_daily_diff)
	sv.add_child(daily_btn)

	profile_btn = _menu_button("")
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
func _hud_chip(row: HBoxContainer, tex_name: String) -> Label:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _panel_sb(UI_BORDER, UI_PANEL2, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	chip.add_child(h)
	var ic := TextureRect.new()
	ic.texture = _ui(tex_name)
	ic.custom_minimum_size = Vector2(32, 32)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(ic)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", UI_GOLD)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text = "0"
	h.add_child(lbl)
	row.add_child(chip)
	return lbl

# Единая кнопка меню (primary — золотая заливка, secondary — обычная тема).
func _menu_button(text: String, primary: bool = false, h: float = 54.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(440, h)
	b.add_theme_font_size_override("font_size", 20 if primary else FS_BODY)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _tab_sb(true))
		b.add_theme_color_override("font_color", UI_GOLD)
	return b

# ---------- экран коллекции ----------
# Статичный каркас (заголовок, скролл, «назад») строится один раз; наполнение
# (статы/альбом/список NPC) пересобирается каждый показ из живого профиля.
# ============================================================
# Дизайн-система (ядро) — единые роли цветов, размеры и панели.
# Применяется в переверстанной Коллекции; далее раскатываем на остальные экраны.
# ============================================================
const UI_GOLD := Color("ffcf5d")          # акцент: заголовки, числа, валюта
const UI_GOLD_DIM := Color(0.95, 0.82, 0.5)
const UI_TXT := Color(0.95, 0.95, 1.0)     # основной текст
const UI_TXT_DIM := Color(1, 1, 1, 0.62)   # подписи
const UI_PANEL := Color(0.11, 0.12, 0.19, 0.96)  # карточка
const UI_PANEL2 := Color(0.07, 0.08, 0.13, 1.0)  # вложенная/фон-ячейка
const UI_BORDER := Color(0.34, 0.32, 0.5, 0.55)  # обводка панели
const UI_OK := Color("6dff8f")             # успех
const UI_BAD := Color("ff5d6a")            # штраф/провал
const FS_TITLE := 30
const FS_H := 22
const FS_BODY := 16
const FS_SMALL := 13

# Единый стайлбокс карточки-панели (скругление + тонкая обводка + мягкая тень).
func _panel_sb(accent: Color = UI_BORDER, bg: Color = UI_PANEL, radius: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = accent
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.set_content_margin_all(14.0)
	return sb

# Плитка статистики: иконка сверху, крупное число золотом, подпись снизу.
func _stat_tile(tex: Texture2D, number: String, label: String, accent: Color = UI_BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _panel_sb(accent))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	if tex != null:
		var ir := TextureRect.new()
		ir.texture = tex
		ir.custom_minimum_size = Vector2(52, 52)
		ir.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(ir)
	var num := Label.new()
	num.text = number
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 30)
	num.add_theme_color_override("font_color", UI_GOLD)
	v.add_child(num)
	var lbl := Label.new()
	lbl.text = label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", FS_SMALL)
	lbl.add_theme_color_override("font_color", UI_TXT_DIM)
	v.add_child(lbl)
	return p

# Стилизованный заголовок секции коллекции (золото, крупно).
func _coll_section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FS_H)
	l.add_theme_color_override("font_color", UI_GOLD)
	collection_list.add_child(l)

# Подсказки-условия выпадения стикеров (для закрытых ячеек альбома).
const STICKER_HINTS := {
	"perfect4": "серия 5+ идеалов подряд", "perfect5": "серия 10+ идеалов подряд",
	"perfect6": "все параметры ровно в цель", "perfect7": "идеал на градиенте",
	"perfect8": "идеал у Того-Кто-Ждёт", "perfect9": "идеал под дебаффом Ир",
	"perfect10": "идеал под печатью Хранителя", "perfect11": "идеал на УР.4",
	"perfect12": "рейтинг цикла 3500+", "perfect13": "Сверхнова: точная ширина и высота",
	"perfect14": "идеал в последний день цикла",
	"good4": "почти идеал (меньше 2%)", "good5": "8+ заказов подряд без брака",
	"good6": "годнота в последние 10% таймера", "good7": "прервал серию из 2+ браков",
	"good8": "1000+ чаевых за всё время", "good9": "10000+ чаевых за всё время",
	"swill4": "почти дотянул до годноты", "swill5": "прервал серию из 2+ браков",
	"bad4": "точность ниже 30%", "bad5": "брак на УР.1", "bad6": "третий брак подряд",
	"bad7": "таймер истёк сам", "bad8": "брак под печатью Хранителя",
	"bad9": "обиженный связями гость",
}

func _build_collection() -> void:
	collection_panel = _make_center_panel()
	# коллекция — на ВЕСЬ экран (топбар на ней скрыт), а не в окне с CONTENT_TOP
	var ccard := collection_panel.get_node("Card") as PanelContainer
	ccard.offset_top = PANEL_INSET
	var cv := collection_panel.get_node("Card/V") as VBoxContainer
	cv.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "КОЛЛЕКЦИЯ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", UI_GOLD)
	cv.add_child(title)
	_glow_label(title, UI_GOLD)

	# вкладки-пилюли (сегмент-контрол): активная — золото, остальные — приглушены
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 8)
	cv.add_child(tabrow)
	coll_tab_btns.clear()
	for tab in [["stats", "Статистика"], ["ribbon", "Лента"], ["stickers", "Стикеры"], ["ach", "Ачивки"]]:
		var b := Button.new()
		b.text = tab[1]
		b.custom_minimum_size = Vector2(0, 50)
		b.add_theme_font_size_override("font_size", FS_BODY)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("tab", tab[0])
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _tab_sb(false))
		b.pressed.connect(_set_collection_tab.bind(tab[0]))
		tabrow.add_child(b)
		coll_tab_btns.append(b)

	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)

	collection_list = VBoxContainer.new()
	collection_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_list.add_theme_constant_override("separation", 12)
	scroll.add_child(collection_list)

	var back := Button.new()
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(0, 54)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_close_collection)
	cv.add_child(back)

# Стайлбокс вкладки-пилюли (активная — золото-заливка + золотая кайма).
func _tab_sb(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.18) if active else UI_PANEL2
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2 if active else 1)
	sb.border_color = UI_GOLD if active else UI_BORDER
	sb.set_content_margin_all(8.0)
	return sb

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
	for b in coll_tab_btns:          # активная вкладка — золотой стиль + золотой текст
		var on: bool = b.get_meta("tab") == tab
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _tab_sb(on))
		b.add_theme_color_override("font_color", UI_GOLD if on else UI_TXT_DIM)
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
	var met: int = (PotionProfile.data.get("progression", {}).get("met_npcs", []) as Array).size()

	_coll_section("Всего")
	var g1 := _stat_grid(2)
	g1.add_child(_stat_tile(_ui("stat_orders"), str(int(st.get("total_orders", 0))), "Заказов"))
	g1.add_child(_stat_tile(_ui("stat_tips"), str(int(tips.get("lifetime", 0))), "Чаевых всего", UI_GOLD))
	g1.add_child(_stat_tile(_ui("stat_visitors"), "%d/%d" % [met, GameData.NPCS.size()], "Посетителей"))
	g1.add_child(_stat_tile(_ui("stat_cycles"), str(int(st.get("cycles_completed", 0))), "Циклов пройдено"))
	collection_list.add_child(g1)

	_coll_section("Лучшие серии")
	var g2 := _stat_grid(2)
	g2.add_child(_stat_tile(_ui("stat_streak"), str(int(sk.get("perfect_best", 0))), "Идеалов подряд", UI_GOLD))
	g2.add_child(_stat_tile(_ui("stat_shield"), str(int(sk.get("goodplus_best", 0))), "Без брака подряд", UI_OK))
	collection_list.add_child(g2)

	_coll_section("Смеси по грейдам")
	var g3 := _stat_grid(4)
	var gcol := {"perfect": UI_GOLD, "good": UI_OK, "swill": Color("ffa24d"), "bad": UI_BAD}
	for cat in ["perfect", "good", "swill", "bad"]:
		var thumb := load(GameData.sticker_path(String(GameData.STICKERS[cat][0]))) as Texture2D
		g3.add_child(_stat_tile(thumb, str(int(life.get(cat, 0))), GRADE_LABEL.get(cat, cat), gcol[cat]))
	collection_list.add_child(g3)

# Сетка плиток статистики (равные колонки, единые отступы).
func _stat_grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	return g

# Быстрая загрузка текстуры из assets/ui (null-безопасно).
func _ui(name: String) -> Texture2D:
	return load("res://assets/ui/%s.png" % name) as Texture2D

func _fill_stickers_tab() -> void:
	var seen: Dictionary = PotionProfile.data.get("stats", {}).get("stickers_seen", {})
	var tot: int = 0
	var have: int = 0
	for cat in ["perfect", "good", "swill", "bad"]:
		tot += (GameData.STICKERS[cat] as Array).size()
		have += mini((seen.get(cat, []) as Array).size(), (GameData.STICKERS[cat] as Array).size())
	_coll_section("Собрано  %d / %d" % [have, tot])
	for cat in ["perfect", "good", "swill", "bad"]:
		var all: Array = GameData.STICKERS[cat]
		var got: Array = seen.get(cat, [])
		var sub := Label.new()
		sub.text = "%s   ·   %d/%d" % [GRADE_LABEL.get(cat, cat), mini(got.size(), all.size()), all.size()]
		sub.add_theme_font_size_override("font_size", FS_BODY)
		sub.add_theme_color_override("font_color", UI_TXT_DIM)
		collection_list.add_child(sub)
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
	_coll_section("Открыто ступеней  %d / %d" % [opened, GameData.ach_total_tiers()])

	var grid := _stat_grid(2)
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

	var accent: Color = Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.85) if unlocked else UI_BORDER
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_sb(accent))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(60, 60)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture = load(GameData.ach_icon_path(a["img"])) as Texture2D
	if not unlocked:
		ic.modulate = Color(1, 1, 1, 0.30)
	col.add_child(ic)

	var nm := Label.new()
	nm.text = a["name"] if unlocked else "???"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", FS_SMALL + 1)
	nm.add_theme_color_override("font_color", UI_GOLD if unlocked else UI_TXT_DIM)
	col.add_child(nm)

	# точки-ступени
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 4)
	for i in n_tiers:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(14, 14)
		var dsb := StyleBoxFlat.new()
		dsb.set_corner_radius_all(7)
		dsb.bg_color = UI_GOLD if i < filled else Color(1, 1, 1, 0.12)
		d.add_theme_stylebox_override("panel", dsb)
		dots.add_child(d)
	col.add_child(dots)

	# прогресс-бар до следующей ступени + подпись val/next
	if not manual and filled < thresholds.size():
		var prev: int = int(thresholds[filled - 1]) if filled > 0 else 0
		var next: int = int(thresholds[filled])
		var frac: float = clampf(float(val - prev) / maxf(1.0, float(next - prev)), 0.0, 1.0)
		col.add_child(_mini_bar(frac, UI_GOLD))
		var pr := Label.new()
		pr.text = "%d / %d" % [val, next]
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pr.add_theme_font_size_override("font_size", FS_SMALL)
		pr.add_theme_color_override("font_color", UI_TXT_DIM)
		col.add_child(pr)
	return card

# Тонкий прогресс-бар (капсула фон + заливка), доля 0..1.
func _mini_bar(frac: float, col: Color, h: float = 8.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0; bar.max_value = 1.0; bar.value = clampf(frac, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, h)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.10); bg.set_corner_radius_all(int(h * 0.5))
	var fill := StyleBoxFlat.new()
	fill.bg_color = col; fill.set_corner_radius_all(int(h * 0.5))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

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
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(104, 104)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if got.has(name):
			cell.add_theme_stylebox_override("panel", _panel_sb(Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.4), UI_PANEL2, 12))
			var tr := TextureRect.new()
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture = load(GameData.sticker_path(name)) as Texture2D
			cell.add_child(tr)
		else:
			cell.add_theme_stylebox_override("panel", _panel_sb(UI_BORDER, Color(0.05, 0.05, 0.09, 0.7), 12))
			cell.tooltip_text = String(STICKER_HINTS.get(name, "выпадает случайно за этот грейд"))
			var lock := Label.new()
			lock.text = "🔒"
			lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lock.add_theme_font_size_override("font_size", 34)
			lock.modulate = Color(1, 1, 1, 0.28)
			cell.add_child(lock)
		grid.add_child(cell)
	collection_list.add_child(grid)

# ---------- вкладка «Лента идеальных» ----------
func _fill_ribbon_tab() -> void:
	var rb: Dictionary = PotionProfile.data.get("perfect_ribbon", {"count": 0.0, "platinum_count": 0})
	var count: float = float(rb.get("count", 0.0))
	var full: float = float(GameData.RIBBON_FULL)
	var plat: int = int(rb.get("platinum_count", 0))
	_coll_section("Лента идеалов  %.1f / %d" % [count, int(full)])
	col_add_mini_bar(count / maxf(1.0, full), 18.0)     # крупная полоса заполнения
	_ribbon_grid(count, int(full))
	_coll_hint("Идеалы на высоких тирах и сложностях заполняют ленту быстрее.")
	if plat > 0:
		_coll_section("Платиновых лент: %d" % plat)
		_plat_row(plat)

# добавить прогресс-бар прямо в список коллекции
func col_add_mini_bar(frac: float, h: float) -> void:
	collection_list.add_child(_mini_bar(frac, UI_GOLD, h))

# приглушённая подпись-подсказка в коллекции
func _coll_hint(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", FS_SMALL)
	l.add_theme_color_override("font_color", UI_TXT_DIM)
	collection_list.add_child(l)

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
	btn.custom_minimum_size = Vector2(0, 104)
	btn.disabled = not met
	btn.focus_mode = Control.FOCUS_NONE
	var accent: Color = Color(tcol.r, tcol.g, tcol.b, 0.5) if met else UI_BORDER
	for st in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(st, _panel_sb(accent, UI_PANEL if met else Color(0.07, 0.07, 0.11, 0.85)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
	# на ВЕСЬ экран (топбар скрыт), а не окном снизу
	(chars_panel.get_node("Card") as PanelContainer).offset_top = PANEL_INSET
	var cv := chars_panel.get_node("Card/V") as VBoxContainer
	cv.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "ПЕРСОНАЖИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", UI_GOLD)
	cv.add_child(title)
	_glow_label(title, UI_GOLD)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)
	chars_list = VBoxContainer.new()
	chars_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chars_list.add_theme_constant_override("separation", 10)
	scroll.add_child(chars_list)
	var back := Button.new()
	back.text = "← Назад"
	back.custom_minimum_size = Vector2(0, 54)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.focus_mode = Control.FOCUS_NONE
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
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
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

	# шапка: КРУПНЫЙ аватар по центру (без металлической рамки) + имя + репутация
	var head := VBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	var av := _big_avatar(npc_e, 240.0)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(av)
	var nm := Label.new()
	nm.text = npc_e["name"]
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 34)
	nm.add_theme_color_override("font_color", tcol)
	head.add_child(nm)
	var rep_ctl := _rep_bar_ctl(PotionProfile.get_rep(id), tcol, 18)
	rep_ctl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rep_ctl.custom_minimum_size.x = 360.0
	head.add_child(rep_ctl)
	char_list.add_child(head)

	# досье
	_char_header("Досье", tcol)
	var doss := Label.new()
	doss.text = GameData.dossier(id)
	doss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	doss.modulate = Color(1, 1, 1, 0.9)
	doss.add_theme_font_size_override("font_size", 19)
	char_list.add_child(doss)

	# пассивки (5, открываются уровнями репутации; эффекты — Фаза 4)
	_char_header("Пассивки", tcol)
	var rep_lvl: int = PotionProfile.get_rep_level(id)
	for n in range(1, 6):
		var open: bool = rep_lvl >= n
		var p := Label.new()
		p.text = ("✓ Пассивка ур.%d — открыта" % n) if open else ("🔒 Пассивка ур.%d — нужна репутация ур.%d" % [n, n])
		p.modulate = Color(1, 1, 1, 0.9) if open else Color(1, 1, 1, 0.45)
		p.add_theme_font_size_override("font_size", 18)
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

# Крупный круглый аватар без металлической рамки: свечение тира + тёмный диск +
# портрет + тонкая цветная окантовка.
func _big_avatar(npc_e: Dictionary, sz: float) -> Control:
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)
	var box := Control.new()
	box.custom_minimum_size = Vector2(sz, sz)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := Panel.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(tcol.r, tcol.g, tcol.b, 0.16)
	gsb.set_corner_radius_all(int(sz))
	gsb.shadow_color = Color(tcol.r, tcol.g, tcol.b, 0.55)
	gsb.shadow_size = 26
	glow.add_theme_stylebox_override("panel", gsb)
	box.add_child(glow)
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
		var ins: float = sz * 0.15                 # квадрат портрета вписан в круг
		pic.offset_left = ins; pic.offset_top = ins; pic.offset_right = -ins; pic.offset_bottom = -ins
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
	var ring := Panel.new()                        # тонкая цветная окантовка (не металл)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0)
	rsb.set_corner_radius_all(int(sz))
	rsb.set_border_width_all(4)
	rsb.border_color = Color(tcol.r, tcol.g, tcol.b, 0.85)
	ring.add_theme_stylebox_override("panel", rsb)
	box.add_child(ring)
	return box

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
	# затемнение фона — компактная карточка читается как модальный лист
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	account_panel.add_child(dim)
	account_panel.move_child(dim, 0)
	# карточку — компактной и по центру экрана (а не «прибитой» вниз)
	var card := account_panel.get_node("Card") as PanelContainer
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -322.0; card.offset_right = 322.0
	card.offset_top = -440.0; card.offset_bottom = 440.0
	card.add_theme_stylebox_override("panel", _panel_sb(UI_BORDER, UI_PANEL, 18))
	var cv := card.get_node("V") as VBoxContainer
	cv.alignment = BoxContainer.ALIGNMENT_BEGIN
	cv.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "ПРОФИЛЬ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", UI_GOLD)
	cv.add_child(title)
	_glow_label(title, UI_GOLD)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)
	account_list = VBoxContainer.new()
	account_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_list.add_theme_constant_override("separation", 12)
	scroll.add_child(account_list)
	var back := Button.new()
	back.text = "← Меню"
	back.custom_minimum_size = Vector2(0, 54)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_show_start)
	cv.add_child(back)

# Шапка профиля: крупная иконка + ник (золото) + статус.
func _acc_header(status: String, status_col: Color) -> void:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", _panel_sb(status_col, UI_PANEL2, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	head.add_child(h)
	var ic := TextureRect.new()
	ic.texture = _ui("nav_profile")
	ic.custom_minimum_size = Vector2(64, 64)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	var nick := Label.new()
	nick.text = PotionAuth.get_nickname()
	nick.add_theme_font_size_override("font_size", FS_H)
	nick.add_theme_color_override("font_color", UI_GOLD)
	v.add_child(nick)
	var stl := Label.new()
	stl.text = status
	stl.add_theme_font_size_override("font_size", FS_SMALL)
	stl.add_theme_color_override("font_color", status_col)
	v.add_child(stl)
	h.add_child(v)
	account_list.add_child(head)

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
		_acc_header("В аккаунте · синхронизация между устройствами", UI_OK)
		account_list.add_child(_acc_nick_row())
		var out := Button.new()
		out.text = "Выйти"
		out.custom_minimum_size = Vector2(0, 50)
		out.add_theme_font_size_override("font_size", FS_BODY)
		out.focus_mode = Control.FOCUS_NONE
		out.pressed.connect(_acc_logout)
		account_list.add_child(out)
		return

	# --- гость ---
	_acc_header("Гость · прогресс на этом устройстве", UI_GOLD)
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

	# карточки в прокрутке — чтобы при 4 картах умещались, а умения/«Меню» не уезжали
	var day_scroll := ScrollContainer.new()
	day_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	day_scroll.scroll_deadzone = 14
	day_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	day_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_child(day_scroll)
	day_cards = VBoxContainer.new()
	day_cards.add_theme_constant_override("separation", 18)
	day_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	day_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	day_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	day_scroll.add_child(day_cards)

	_build_skill_dock(dv)          # Фаза 7: панель умений (закреплена под прокруткой)

	# day_header скрыт в шапке экрана — держим ссылку живой (день виден в топбаре)
	day_header = Label.new()
	day_header.visible = false
	dv.add_child(day_header)

	var to_menu := Button.new()
	to_menu.text = "← Меню\n(бросить цикл)"
	to_menu.custom_minimum_size = Vector2(240, 74)   # компактная кнопка: выше и уже
	to_menu.add_theme_font_size_override("font_size", 19)
	to_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	to_menu.pressed.connect(_show_start)
	dv.add_child(to_menu)

# ---------- постоянная верхняя панель ----------
# ---------- Глобальный рейтинг (лидерборд) ----------
var lb_panel: Control = null
var lb_list: VBoxContainer = null

# Загрузка: онлайн-топ (Supabase) читаем ВСЕГДА, когда настроен бэкенд (чтение
# публичное — даже гостю); иначе локальный список.
func _lb_load() -> Array:
	var mode: String = "daily" if daily_mode else "arcade"
	if PotionAuth.configured():
		var rows: Array = await PotionAuth.leaderboard_load(mode)
		if not rows.is_empty():
			var out: Array = []
			for r in rows:
				out.append({"name": str(r.get("name", "?")), "score": int(r.get("score", 0)), "date": _lb_date(str(r.get("created_at", "")))})
			return out
	return [] if daily_mode else PotionProfile.lb_local_all()   # дейлик — только онлайн-топ дня

func _lb_date(created: String) -> String:
	if created.length() >= 10:
		var p: PackedStringArray = created.substr(0, 10).split("-")   # YYYY-MM-DD
		if p.size() == 3:
			return "%s.%s.%s" % [p[2], p[1], p[0]]
	return ""

# Сохранить счёт: онлайн (если в аккаунте) + всегда локально (fallback/гость).
func _lb_save(nick: String, score: int, mode: String = "arcade") -> void:
	if PotionAuth.is_logged_in():
		await PotionAuth.leaderboard_save(mode, nick, score)
	if mode == "arcade":
		PotionProfile.lb_local_add(nick, score)

var _lb_highlight: int = -1        # какой счёт подсветить при следующем открытии

func _open_leaderboard() -> void:
	if lb_panel == null:
		_build_leaderboard_panel()
	lb_panel.visible = true
	Sfx.play("uiClick")
	var hl: int = _lb_highlight
	_lb_highlight = -1
	_render_leaderboard([], hl)                  # «загрузка…» (пусто) до ответа
	var rows: Array = await _lb_load()
	if lb_panel != null and lb_panel.visible:
		_render_leaderboard(rows, hl)

func _build_leaderboard_panel() -> void:
	lb_panel = Control.new()
	lb_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	lb_panel.add_child(dim)
	var card := PanelContainer.new()
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -322.0; card.offset_right = 322.0; card.offset_top = -440.0; card.offset_bottom = 440.0
	var sb := _panel_sb(UI_GOLD, UI_PANEL, 18)
	sb.set_content_margin_all(20.0)
	card.add_theme_stylebox_override("panel", sb)
	lb_panel.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var title := Label.new()
	title.text = "ГЛОБАЛЬНЫЙ РЕЙТИНГ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", UI_GOLD)
	col.add_child(title)
	_glow_label(title, UI_GOLD)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	lb_list = VBoxContainer.new()
	lb_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_list.add_theme_constant_override("separation", 8)
	scroll.add_child(lb_list)
	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(0, 54)
	close.add_theme_font_size_override("font_size", FS_BODY)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): lb_panel.visible = false)
	col.add_child(close)
	add_child(lb_panel)

# Цвета медалей топ-3.
const LB_MEDAL := {1: Color("ffd54a"), 2: Color("cfd6e6"), 3: Color("e0954a")}

func _render_leaderboard(rows: Array, highlight: int) -> void:
	if lb_list == null:
		return
	for c in lb_list.get_children():
		c.queue_free()
	if rows.is_empty():
		var l := Label.new()
		l.text = "Пока пусто — стань первым!"
		l.add_theme_color_override("font_color", UI_TXT_DIM)
		l.add_theme_font_size_override("font_size", FS_BODY)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb_list.add_child(l)
		return
	var rank := 0
	for e in rows:
		rank += 1
		var me: bool = highlight >= 0 and int(e.get("score", -999)) == highlight
		var medal: Color = LB_MEDAL.get(rank, Color.TRANSPARENT)
		var accent: Color = UI_OK if me else (medal if rank <= 3 else UI_BORDER)
		var rowp := PanelContainer.new()
		rowp.add_theme_stylebox_override("panel", _panel_sb(accent, UI_PANEL2 if not me else Color(UI_OK.r, UI_OK.g, UI_OK.b, 0.12), 10))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		rowp.add_child(r)
		# ранг-бейдж (медаль у топ-3)
		var rk := Label.new()
		rk.text = "%d" % rank
		rk.custom_minimum_size = Vector2(38, 0)
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rk.add_theme_font_size_override("font_size", 20)
		rk.add_theme_color_override("font_color", medal if rank <= 3 else UI_TXT_DIM)
		r.add_child(rk)
		var n := Label.new()
		n.text = str(e.get("name", "?"))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_font_size_override("font_size", FS_BODY)
		n.add_theme_color_override("font_color", UI_OK if me else UI_TXT)
		r.add_child(n)
		var dt := Label.new()
		dt.text = str(e.get("date", ""))
		dt.add_theme_font_size_override("font_size", FS_SMALL)
		dt.add_theme_color_override("font_color", UI_TXT_DIM)
		dt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(dt)
		var s := Label.new()
		s.text = str(int(e.get("score", 0)))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.custom_minimum_size = Vector2(80, 0)
		s.add_theme_font_size_override("font_size", 20)
		s.add_theme_color_override("font_color", UI_GOLD)
		r.add_child(s)
		lb_list.add_child(rowp)

# ---------- Магазин (Фаза 6) ----------
var shop_panel: Control = null
var shop_list: VBoxContainer = null
var shop_balance: Label = null

func _open_shop() -> void:
	if not GameData.prog_mech_unlocked("shop", _xp()):
		_toast("Магазин откроется с ростом лавки (ур.4)", Color("ffcf5d"))
		return
	if shop_panel == null:
		_build_shop_panel()
	shop_panel.visible = true
	Sfx.play("uiClick")
	_render_shop()

func _build_shop_panel() -> void:
	shop_panel = Control.new()
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_panel.add_child(dim)
	var card := PanelContainer.new()
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -320.0; card.offset_right = 320.0; card.offset_top = -420.0; card.offset_bottom = 420.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.13, 0.98)
	sb.set_corner_radius_all(16); sb.set_border_width_all(2)
	sb.border_color = Color(0.90, 0.72, 0.42)
	sb.set_content_margin_all(18.0)
	card.add_theme_stylebox_override("panel", sb)
	shop_panel.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "🛒 ЛАВКА"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("ffcf5d"))
	head.add_child(title)
	shop_balance = Label.new()
	shop_balance.add_theme_font_size_override("font_size", 20)
	shop_balance.add_theme_color_override("font_color", Color("ffd75e"))
	head.add_child(shop_balance)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 10)
	scroll.add_child(shop_list)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): shop_panel.visible = false)
	col.add_child(close)
	add_child(shop_panel)

var shop_sel: Dictionary = {}     # item_id → выбранный грейд (тир предмета)

func _render_shop() -> void:
	shop_balance.text = "🪙 %d" % PotionProfile.tips_balance()
	for c in shop_list.get_children():
		c.queue_free()
	var xp: int = _xp()
	for it in GameData.SHOP_ITEMS:
		var id: String = String(it["id"])
		var grades: Array = it["grades"]
		# доступные грейды по прогрессии
		var avail: Array = []
		for gi in grades.size():
			if GameData.shop_grade_unlocked(gi, xp):
				avail.append(gi)
		if avail.is_empty():
			continue
		var sel: int = int(shop_sel.get(id, avail[0]))
		if not (sel in avail):
			sel = int(avail[0])
			shop_sel[id] = sel
		var g: Dictionary = grades[sel]
		# карточка-блок предмета
		var block := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.12, 0.12, 0.18, 0.9)
		bsb.set_corner_radius_all(12)
		bsb.set_content_margin_all(12.0)
		block.add_theme_stylebox_override("panel", bsb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 20)
		block.add_child(hb)
		# крупная иконка предмета (×2, картинка item_<id>.png, фолбэк — эмодзи)
		var ic := _item_icon_node(it, 120.0, 64)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
		# инфо выбранного грейда
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 3)
		hb.add_child(vb)
		var nm := Label.new()
		nm.text = "%s · Тир %d" % [it["name"], sel + 1]
		nm.add_theme_font_size_override("font_size", 17)
		nm.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0))
		vb.add_child(nm)
		var ds := Label.new()
		ds.text = String(it["desc"])
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.add_theme_font_size_override("font_size", 12)
		ds.modulate = Color(1, 1, 1, 0.55)
		vb.add_child(ds)
		var ef := Label.new()
		ef.text = "Эффект: %s" % String(g["label"])
		ef.add_theme_font_size_override("font_size", 14)
		ef.add_theme_color_override("font_color", Color("6dff8f"))
		vb.add_child(ef)
		var buyrow := HBoxContainer.new()
		buyrow.add_theme_constant_override("separation", 10)
		var buy := Button.new()
		buy.text = "Купить · 🪙 %d" % int(g["price"])
		buy.focus_mode = Control.FOCUS_NONE
		buy.pressed.connect(_buy_item.bind(id, sel, int(g["price"])))
		buyrow.add_child(buy)
		var have := Label.new()
		have.text = "в сумке: %d" % PotionProfile.item_count(id, sel)
		have.add_theme_font_size_override("font_size", 13)
		have.modulate = Color(1, 1, 1, 0.6)
		have.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		buyrow.add_child(have)
		vb.add_child(buyrow)
		# селектор тира 1/2/3 справа
		var sel_col := VBoxContainer.new()
		sel_col.add_theme_constant_override("separation", 4)
		for gi in grades.size():
			var gb := Button.new()
			gb.text = str(gi + 1)
			gb.custom_minimum_size = Vector2(40, 34)
			gb.focus_mode = Control.FOCUS_NONE
			gb.disabled = not (gi in avail)
			if gi == sel:
				gb.add_theme_color_override("font_color", Color("6ec3ff"))
			gb.pressed.connect(_shop_pick_grade.bind(id, gi))
			sel_col.add_child(gb)
		hb.add_child(sel_col)
		shop_list.add_child(block)

func _shop_pick_grade(id: String, grade: int) -> void:
	shop_sel[id] = grade
	Sfx.play("tick")
	_render_shop()

func _buy_item(id: String, grade: int, price: int) -> void:
	if PotionProfile.buy_item(id, grade, price):
		Sfx.play("brew")
		_render_shop()
	else:
		Sfx.play("bad")
		_toast("Не хватает чаевых", Color("ff6a6a"))

# Панель применения предметов в игре: показывает предметы из инвентаря, подходящие
# текущей фазе (select — эффекты след. заказу; craft — текущему).
var items_panel: Control = null
var items_list: VBoxContainer = null

func _open_items() -> void:
	if not GameData.prog_mech_unlocked("shop", _xp()):
		return
	if items_panel == null:
		_build_items_panel()
	items_panel.visible = true
	Sfx.play("uiClick")
	_render_items()

func _build_items_panel() -> void:
	items_panel = Control.new()
	items_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	items_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	items_panel.add_child(dim)
	var card := PanelContainer.new()
	card.anchor_left = 0.5; card.anchor_right = 0.5; card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -322.0; card.offset_right = 322.0; card.offset_top = -430.0; card.offset_bottom = 430.0
	var sb := _panel_sb(UI_BORDER, UI_PANEL, 18)
	sb.set_content_margin_all(20.0)
	card.add_theme_stylebox_override("panel", sb)
	items_panel.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	var title := Label.new()
	title.text = "ИНВЕНТАРЬ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FS_TITLE)
	title.add_theme_color_override("font_color", UI_GOLD)
	col.add_child(title)
	_glow_label(title, UI_GOLD)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = 14      # тач-драг пальцем поверх кнопок/карточек
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	items_list = VBoxContainer.new()
	items_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_list.add_theme_constant_override("separation", 12)
	scroll.add_child(items_list)
	var close := Button.new()
	close.text = "ЗАКРЫТЬ"
	close.custom_minimum_size = Vector2(0, 52)
	close.add_theme_font_size_override("font_size", 18)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): items_panel.visible = false)
	col.add_child(close)
	add_child(items_panel)

func _render_items() -> void:
	for c in items_list.get_children():
		c.queue_free()
	var kind: String = "select" if phase == "day" or phase == "select" else "craft"
	var any := false
	# показываем ВСЕ предметы в инвентаре (не только применимые сейчас); неподходящие
	# по фазе — с задизейбленной кнопкой и подсказкой, как в браузере.
	for it in GameData.SHOP_ITEMS:
		var grades: Array = it["grades"]
		for gi in grades.size():
			var cnt: int = PotionProfile.item_count(String(it["id"]), gi)
			if cnt <= 0:
				continue
			any = true
			items_list.add_child(_item_card(it, gi, cnt, kind))
	if not any:
		var l := Label.new()
		l.text = "Инвентарь пуст.\nКупи предметы в 🛒 Лавке."
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 17)
		l.modulate = Color(1, 1, 1, 0.55)
		items_list.add_child(l)

# Иконка предмета: картинка item_<id>.png, если есть; иначе эмодзи-фолбэк.
func _item_icon_node(it: Dictionary, sz: float, emoji_fs: int) -> Control:
	var tex := load("res://assets/ui/item_%s.png" % String(it.get("id", ""))) as Texture2D
	if tex != null:
		var ir := TextureRect.new()
		ir.texture = tex
		ir.custom_minimum_size = Vector2(sz, sz)
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return ir
	var l := Label.new()
	l.text = String(it.get("icon", "❓"))
	l.custom_minimum_size = Vector2(sz, sz)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", emoji_fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Карточка предмета инвентаря (как в браузере): крупная иконка, имя+грейд, описание,
# строка «Эффект:» зелёным, крупная кнопка «Применить» + счётчик + подсказка по фазе.
func _item_card(it: Dictionary, gi: int, cnt: int, kind: String) -> PanelContainer:
	var usable: bool = String(it["use"]) == kind
	var card := PanelContainer.new()
	# применимый сейчас — золотая рамка, иначе обычная
	card.add_theme_stylebox_override("panel", _panel_sb(UI_GOLD if usable else UI_BORDER, UI_PANEL, 12))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	# крупная иконка в скруглённой подложке
	var icon_box := PanelContainer.new()
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ibsb := StyleBoxFlat.new()
	ibsb.bg_color = UI_PANEL2
	ibsb.set_corner_radius_all(12)
	ibsb.set_content_margin_all(8.0)
	icon_box.add_theme_stylebox_override("panel", ibsb)
	icon_box.add_child(_item_icon_node(it, 56.0, 40))
	row.add_child(icon_box)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	row.add_child(body)

	# имя + грейд
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	var nm := Label.new()
	nm.text = String(it["name"])
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(0.97, 0.97, 1.0))
	name_row.add_child(nm)
	var gnote := Label.new()
	gnote.text = "· Грейд %d (%s)" % [gi + 1, String(it["grades"][gi]["label"])]
	gnote.add_theme_font_size_override("font_size", 13)
	gnote.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	gnote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(gnote)
	body.add_child(name_row)

	# описание
	var desc := Label.new()
	desc.text = String(it["desc"])
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)

	# строка эффекта — зелёным
	var eff := Label.new()
	eff.text = _item_effect_desc(it, gi)
	eff.add_theme_font_size_override("font_size", 13)
	eff.add_theme_color_override("font_color", Color("8affc0"))
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(eff)

	# действие: кнопка + счётчик + подсказка по фазе
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 10)
	var use := Button.new()
	use.text = "Применить"
	use.custom_minimum_size = Vector2(150, 44)
	use.add_theme_font_size_override("font_size", 16)
	use.focus_mode = Control.FOCUS_NONE
	use.disabled = not usable
	if usable:
		use.pressed.connect(_apply_item_and_close.bind(String(it["id"]), gi))
	act.add_child(use)
	var owned := Label.new()
	owned.text = "×%d" % cnt
	owned.add_theme_font_size_override("font_size", 15)
	owned.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	owned.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	act.add_child(owned)
	if not usable:
		var hint := Label.new()
		hint.text = "(во время варки)" if String(it["use"]) == "craft" else "(на выбор дня)"
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		act.add_child(hint)
	body.add_child(act)
	return card

# Фраза-эффект по грейду (число из параметров) — как gradeEffectDesc в браузере.
func _item_effect_desc(it: Dictionary, gi: int) -> String:
	var g: Dictionary = it["grades"][gi]
	match String(it["effect"]):
		"time", "memtime":
			return "Эффект: +%sс к таймеру." % _num_str(float(g.get("sec", 0.0)))
		"jigger":
			var n: int = int(g.get("n", 1))
			return "Эффект: отключает %d %s (не влияет на рейтинг)." % [n, "случайных регулятора" if n > 1 else "случайный регулятор"]
		"repboost":
			var r: int = int(g.get("rep", 0))
			return "Эффект: за годноту+ репутация +%d, за брак −%d сверх обычного." % [r, r]
		"nudge":
			var c: int = int(g.get("count", 1))
			var w: String = "все ползунки" if c >= 99 else ("%d ползунка" % c if c > 1 else "1 ползунок")
			return "Эффект: в конце подвинет %s на деление ближе к цели." % w
		"chip":
			var lo: int = int(round(float(g.get("lo", 0.0)) * 100.0))
			var hi: int = int(round(float(g.get("hi", 0.0)) * 100.0))
			return "Эффект: итог заказа сдвигается на %s%d%%…+%d%%." % ["+" if lo >= 0 else "", lo, hi]
		"flatbonus":
			return "Эффект: +%d рейтинга за годноту." % int(g.get("flat", 0))
		"rewardmult":
			return "Эффект: +%d%% рейтинга за годноту/идеал." % int(round(float(g.get("mult", 0.0)) * 100.0))
		"shield":
			return "Эффект: штраф за брак уменьшается на %d%%." % int(round(float(g.get("cut", 0.0)) * 100.0))
		"speedlock":
			return "Эффект: гарантирует минимум %d%% бонуса за скорость." % int(round(float(g.get("lock", 0.0)) * 100.0))
	return ""

# Число без хвостового «.0» (1.0 → «1», 3.5 → «3.5»).
func _num_str(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, float(int(v))) else str(v)

func _apply_item_and_close(id: String, grade: int) -> void:
	_use_item(id, grade)
	items_panel.visible = false

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
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	topbar.add_child(row)

	# крупные тач-иконки (день/серия/рейтинг переехали под прогрессию)
	_topbar_nav = []
	topbar_coll_btn = _topbar_icon(row, "nav_collection", "🗂", "Коллекция", _show_collection, true)
	_topbar_nav.append(topbar_coll_btn)
	_topbar_nav.append(_topbar_icon(row, "nav_shop", "🛒", "Лавка", _open_shop, true))
	nav_lb_btn = _topbar_icon(row, "nav_leaderboard", "🏆", "Рейтинг", _open_leaderboard, true)
	_topbar_nav.append(nav_lb_btn)
	_topbar_nav.append(_topbar_icon(row, "nav_characters", "👥", "Персонажи", _show_chars, true))
	_topbar_nav.append(_topbar_icon(row, "nav_skills", "⚡", "Пассивки", Callable(), false))
	_topbar_nav.append(_topbar_icon(row, "nav_profile", "👤", "Профиль", _show_account, true))
	settings_btn = _topbar_icon(row, "nav_settings", "⚙", "Настройки", _open_settings, true)

# Кнопка топбара: картинка nav_<name>.png (масштабируется, дизейбл дим-ит её),
# фолбэк — эмодзи-глиф, если картинки нет.
func _topbar_icon(row: HBoxContainer, icon_name: String, glyph: String, tip: String, cb: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(74, 66)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	var tex := load("res://assets/ui/%s.png" % icon_name) as Texture2D
	if tex != null:
		b.icon = tex
		b.expand_icon = true                       # масштабировать под кнопку
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	else:
		b.text = glyph
		b.add_theme_font_size_override("font_size", 34)
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
	# Дейлик: на барах остаются только рейтинг (по центру), стикеры, лидерборд и настройки
	for b in _topbar_nav:
		if is_instance_valid(b):
			b.visible = (not daily_mode) or (b == nav_lb_btn)
	prog_widget.visible = not daily_mode
	tb_streak.visible = not daily_mode
	tb_day.visible = not daily_mode
	if _tb_stickers != null:
		_tb_stickers.visible = true
	# в дейлике рейтинг по центру: строку тянем по центру, спейсеры прячем
	if _tb_info_spacer != null:
		_tb_info_spacer.visible = not daily_mode
	_tb_info.alignment = BoxContainer.ALIGNMENT_CENTER if daily_mode else BoxContainer.ALIGNMENT_BEGIN
	tb_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if daily_mode else HORIZONTAL_ALIGNMENT_LEFT
	_sticker_icon_size = 48.0 if daily_mode else 34.0       # в дейлике крупнее
	var sk: Dictionary = PotionProfile.data.get("streaks", {})
	tb_day.text = "День %d / %d   ·   ст.%d" % [day_num, cycle_days, stage + 1]
	tb_streak.text = "🔥 %d" % int(sk.get("goodplus_current", 0))
	topbar_coll_btn.disabled = not GameData.prog_mech_unlocked("collection", _xp())
	if cycle_score != _tb_rating_shown:
		Juice.count_up(tb_rating, _tb_rating_shown, cycle_score, "Рейтинг: %d")
		_tb_rating_shown = cycle_score
	else:
		tb_rating.text = "Рейтинг: %d" % cycle_score
	_refresh_cycle_stickers()

# Иконки стикеров за цикл (идеал/годно/пойло/брак) + счётчики — как в браузере.
func _refresh_cycle_stickers() -> void:
	if _tb_stickers == null:
		return
	for c in _tb_stickers.get_children():
		c.queue_free()
	for cat in ["perfect", "good", "swill", "bad"]:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(_sticker_icon_size, _sticker_icon_size)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var names: Array = GameData.STICKERS.get(cat, [])
		if not names.is_empty():
			ic.texture = load(GameData.sticker_path(String(names[0]))) as Texture2D
		chip.add_child(ic)
		var l := Label.new()
		l.text = str(int(cycle_stickers.get(cat, 0)))
		l.add_theme_font_size_override("font_size", 26 if _sticker_icon_size >= 44.0 else 20)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		_tb_stickers.add_child(chip)

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
	cycle_stickers = {"perfect": 0, "good": 0, "swill": 0, "bad": 0}
	pogrom_removed = []              # «Погром»: выбывшие возвращаются в новый цикл
	banned_npcs = {}                # 🚫 баны умения сбрасываются на новый цикл
	guaranteed_npc = ""
	PotionProfile.reset_relations_cycle()   # связи: обиды/уходы — только за цикл
	cycle_days = GameData.prog_cycle_days(_xp())   # длина цикла по прогрессии
	PotionProfile.reset_picks_cycle()
	_new_day()

# Новый день: фиксируем тройку посетителей и показываем экран выбора.
func _new_day() -> void:
	day_choices = _pick_day_npcs()
	_apply_guaranteed()             # 👀 форс-включение гарантированного гостя
	# заранее бросаем фокус/модификаторы каждому гостю дня — чтобы показать на карточке
	day_order_mods = {}
	for e in day_choices:
		day_order_mods[String(e.get("id", ""))] = _roll_order_mods(e, false)
	_show_day()

func _show_day() -> void:
	phase = "day"
	start_panel.visible = false
	select_panel.visible = false
	result_panel.visible = false
	round_ui.visible = false
	collection_panel.visible = false
	chars_panel.visible = false      # иначе список персонажей «висит» за карточками дня
	char_panel.visible = false
	account_panel.visible = false
	day_panel.visible = true

	day_header.text = "День %d / %d   ·   стадия %d" % [day_num, cycle_days, stage + 1]
	for c in day_cards.get_children():
		c.queue_free()
	for e in day_choices:
		day_cards.add_child(_day_card(e))
	_set_topbar(true)
	_scene_state("menu")
	Juice.stagger_fade(day_cards.get_children())   # карточки влетают по очереди
	_refresh_skill_dock()

# ---------- Настройки (язык + громкость) ----------
func _open_settings() -> void:
	if settings_panel != null and is_instance_valid(settings_panel):
		settings_panel.queue_free()
		settings_panel = null
		return
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.6)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)
	ov.position = Vector2.ZERO
	ov.size = get_viewport_rect().size
	settings_panel = ov
	ov.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:   # тап по фону — закрыть
			ov.queue_free(); settings_panel = null)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.07, 0.08, 0.13, 0.98)
	psb.set_corner_radius_all(18)
	psb.set_border_width_all(2)
	psb.border_color = Color(0.4, 0.75, 0.85, 0.7)
	psb.content_margin_left = 26; psb.content_margin_right = 26
	psb.content_margin_top = 22; psb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", psb)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(460, 0)
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Настройки"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.72))
	vb.add_child(title)
	# язык (RU/EN) — переключатель (EN-тексты пока не портированы, храним выбор)
	var lang_btn := _diff_button("Язык:  RU", Color("6ec3ff"))
	var cur_lang: String = String(PotionProfile.data.get("settings", {}).get("lang", "ru"))
	lang_btn.text = "Язык:  %s" % cur_lang.to_upper()
	lang_btn.pressed.connect(func():
		var s: Dictionary = PotionProfile.data.get("settings", {})
		var nl: String = "en" if String(s.get("lang", "ru")) == "ru" else "ru"
		s["lang"] = nl; PotionProfile.data["settings"] = s; PotionProfile.save()
		lang_btn.text = "Язык:  %s" % nl.to_upper())
	vb.add_child(lang_btn)
	vb.add_child(_settings_slider("🎵 Музыка", true))
	vb.add_child(_settings_slider("🔊 Звуки", false))
	var close := _diff_button("Закрыть", Color(0.7, 0.72, 0.8))
	close.pressed.connect(func(): ov.queue_free(); settings_panel = null)
	vb.add_child(close)

func _settings_slider(label: String, is_music: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 20)
	l.custom_minimum_size = Vector2(140, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 100.0; sl.step = 1.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(220, 40)
	sl.value = (Sfx.music_volume if is_music else Sfx.sfx_volume) * 100.0
	if is_music:
		sl.value_changed.connect(_on_music_vol)
	else:
		sl.value_changed.connect(_on_sfx_vol)
	sl.drag_ended.connect(func(_c): PotionProfile.save())
	row.add_child(sl)
	return row

# ---------- Ежедневный особый заказ ----------
# Одна и та же тройка гостей у всех по дате (детерминированный сид). Прогресс
# (xp/репутация/статы) НЕ трогаем: снимаем бэкап профиля на входе и откатываем
# на выходе; в топ уходит только счёт (режим "daily").
func _open_daily_diff() -> void:
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.66)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)
	ov.position = Vector2.ZERO
	ov.size = get_viewport_rect().size
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	# подложка-панель (чтобы блок не сливался со стартовым меню)
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.07, 0.08, 0.13, 0.98)
	psb.set_corner_radius_all(18)
	psb.set_border_width_all(2)
	psb.border_color = Color(0.4, 0.75, 0.85, 0.7)
	psb.content_margin_left = 26; psb.content_margin_right = 26
	psb.content_margin_top = 22; psb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", psb)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(480, 0)
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Особый заказ дня"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.72))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Сегодня у всех одинаковый набор гостей.\nВыбери сложность:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	vb.add_child(sub)
	var diff_cols := {"easy": Color("5dff8f"), "mid": Color("6ec3ff"), "hard": Color("c07bff")}
	for key in ["easy", "mid", "hard"]:
		var b := _diff_button(String(DAILY_PROFILES[key]["label"]), diff_cols[key])
		b.pressed.connect(func():
			ov.queue_free()
			_enter_daily(key))
		vb.add_child(b)
	var back := _diff_button("Назад", Color(0.7, 0.72, 0.8))
	back.pressed.connect(ov.queue_free)
	vb.add_child(back)

# кнопка выбора сложности: тёмный фон + цветная рамка/текст (цвет = сложность)
func _diff_button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", col)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.11, 0.16, 1.0) if st != "hover" else Color(0.14, 0.16, 0.22, 1.0)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = col
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(st, sb)
	return b

func _enter_daily(diff: String) -> void:
	_daily_backup = PotionProfile.data.duplicate(true)   # прогресс откатим на выходе
	daily_mode = true
	daily_diff = diff
	daily_seq = _build_daily_seq()
	Sfx.enter_game()
	stage = 0
	day_num = 1
	cycle_score = 0
	perfect_streak_max = 0
	good_streak_max = 0
	cycle_active = true
	_tb_rating_shown = 0
	cycle_stickers = {"perfect": 0, "good": 0, "swill": 0, "bad": 0}
	pogrom_removed = []
	banned_npcs = {}
	guaranteed_npc = ""
	cycle_days = DAILY_DAYS
	_new_day()

# Детерминированная последовательность id по дате UTC (одна на день у всех).
func _build_daily_seq() -> Array:
	var ids: Array = []
	for n in GameData.NPCS:
		ids.append(String(n["id"]))
	var d: Dictionary = Time.get_datetime_dict_from_system(true)   # UTC
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])
	# Фишер-Йетс детерминированно
	for i in range(ids.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = ids[i]; ids[i] = ids[j]; ids[j] = t
	var seq: Array = ids.duplicate()
	while seq.size() < DAILY_DAYS * 3:              # добить до 30 слотов
		seq.append_array(ids)
	return seq

# Тройка гостей дня в дейлике: подмена tier по профилю сложности (tier задаёт
# число делений/тайминги/награду через npc_config).
func _daily_pool(day_idx: int) -> Array:
	var prof: Dictionary = DAILY_PROFILES.get(daily_diff, {"tier": 3})
	var out: Array = []
	for k in 3:
		var id: String = String(daily_seq[(day_idx * 3 + k) % daily_seq.size()])
		var cfg: Dictionary = _npc_by_id(id).duplicate(true)
		cfg["tier"] = int(prof["tier"])
		out.append(cfg)
	return out

func _restore_daily_backup() -> void:
	if not _daily_backup.is_empty():
		PotionProfile.data = _daily_backup
		PotionProfile.save()
	_daily_backup = {}

func _show_daily_end() -> void:
	Sfx.play("weekEnd")
	cycle_active = false
	var sc: int = cycle_score
	_lb_save(PotionAuth.get_nickname(), sc, "daily")   # отдельный топ дейлика
	_restore_daily_backup()                            # прогресс не пострадал
	daily_mode = false
	daily_diff = ""
	_daily_end = true
	phase = "cycle_end"
	round_ui.visible = false
	_layout_result()
	result_sticker_tex.visible = false
	result_glow.visible = false
	result_points_box.visible = false
	result_breakdown_box.visible = false
	result_sticker.text = "Дейлик пройден!"
	result_sticker.add_theme_color_override("font_color", Color("6dff8f"))
	result_detail.text = "Рейтинг дня: %d\n🏆 Отправлено в топ дейлика" % sc
	result_detail.visible = true
	result_replay_btn.visible = false
	result_next_btn.visible = true
	result_panel.visible = true
	_set_topbar(true)
	_scene_state("select")
	Juice.fade_in(result_panel)
	Juice.pop.call_deferred(result_sticker)

# ---------- Фаза 7: умения игрока (панель на экране дня) ----------
const SKILL_DEFS := [
	{"id": "who",     "icon": "👀", "flag": "skill_1", "title": "Кто там? — выбранный гость придёт в ближайших днях"},
	{"id": "ban",     "icon": "🚫", "flag": "skill_2", "title": "Не пускать — до 3 гостей не придут до конца цикла"},
	{"id": "refresh", "icon": "🔄", "flag": "skill_3", "title": "Вам уже пора — обновить всех гостей дня"},
	{"id": "grade",   "icon": "🔁", "flag": "skill_4", "title": "Повторите! — случайному гостю дня грейд выше"},
]
var _pick_mode: String = ""
var _pick_sel: Dictionary = {}
var _pick_max: int = 1

func _npc_by_id(id: String) -> Dictionary:
	for n in GameData.NPCS:
		if String(n.get("id", "")) == id:
			return n
	return {}

func _build_skill_dock(parent: Node) -> void:
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.add_theme_constant_override("separation", 10)
	parent.add_child(wrap)
	skill_dock = wrap
	skill_btns = {}
	for d in SKILL_DEFS:
		var b := Button.new()
		b.tooltip_text = d["title"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 70)
		b.pressed.connect(_use_skill.bind(String(d["id"])))
		# сгенерированная иконка умения (фолбэк — эмодзи, если арт не импортирован)
		var tex := load("res://assets/ui/skill_%s.png" % String(d["id"])) as Texture2D
		if tex:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.set_anchors_preset(Control.PRESET_FULL_RECT)
			ic.offset_left = 6; ic.offset_top = 6; ic.offset_right = -6; ic.offset_bottom = -6
			b.add_child(ic)
		else:
			b.text = d["icon"]
			b.add_theme_font_size_override("font_size", 30)
		wrap.add_child(b)
		skill_btns[String(d["id"])] = b
	var pipbox := HBoxContainer.new()
	pipbox.add_theme_constant_override("separation", 6)
	pipbox.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(pipbox)
	skill_pips = []
	for i in 3:
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(16, 16)
		pipbox.add_child(p)
		skill_pips.append(p)

func _refresh_skill_dock() -> void:
	if skill_dock == null:
		return
	var xp: int = _xp()
	var on: bool = cycle_active and not daily_mode and GameData.prog_mech_unlocked("skill_1", xp)
	skill_dock.visible = on
	if not on:
		return
	var charges: int = PotionProfile.get_charges()
	for d in SKILL_DEFS:
		var b: Button = skill_btns[String(d["id"])]
		b.visible = GameData.prog_mech_unlocked(String(d["flag"]), xp)
		b.disabled = charges <= 0
	for i in skill_pips.size():
		(skill_pips[i] as ColorRect).color = Color("ffd24d") if i < charges else Color(1, 1, 1, 0.18)

func _use_skill(id: String) -> void:
	if PotionProfile.get_charges() <= 0:
		Sfx.play("badPop"); _toast("Нет зарядов умений", Color("ff9a6a")); return
	match id:
		"refresh":
			if not PotionProfile.spend_charge():
				return
			_refresh_day()
			_toast("🔄 Гости дня обновлены", Color("6ec3ff"))
			_refresh_skill_dock()
		"grade":
			_grade_bump()
		_:
			_open_skill_picker(id)

# «Вам уже пора»: перевыбор всех гостей дня (стараемся без повторов текущих)
func _refresh_day() -> void:
	var avoid: Dictionary = {}
	for e in day_choices:
		avoid[String(e.get("id", ""))] = true
	for _try in 6:
		day_choices = _pick_day_npcs()
		var overlap: bool = false
		for e in day_choices:
			if avoid.has(String(e.get("id", ""))):
				overlap = true; break
		if not overlap:
			break
	_apply_guaranteed()
	day_order_mods = {}
	for e in day_choices:
		day_order_mods[String(e.get("id", ""))] = _roll_order_mods(e, false)
	_rebuild_day_cards()

# «Повторите!»: случайному гостю дня (тир<4) поднять грейд на +1
func _grade_bump() -> void:
	var idxs: Array = []
	for i in day_choices.size():
		if int(day_choices[i].get("tier", 1)) < 4:
			idxs.append(i)
	if idxs.is_empty():
		Sfx.play("badPop"); _toast("Некому поднимать грейд", Color("ff9a6a")); return
	if not PotionProfile.spend_charge():
		return
	var i: int = idxs[randi() % idxs.size()]
	var prev: Dictionary = day_choices[i]
	var pid: String = String(prev.get("id", ""))
	day_choices[i] = GameData.grade_up_cfg(prev, int(prev.get("tier", 1)) + 1)
	day_order_mods[String(day_choices[i].get("id", ""))] = day_order_mods.get(pid, {})
	_rebuild_day_cards()
	_toast("🔁 Грейд поднят: %s" % String(day_choices[i].get("name", "")), Color("ffd24d"))

func _rebuild_day_cards() -> void:
	for c in day_cards.get_children():
		c.queue_free()
	for e in day_choices:
		day_cards.add_child(_day_card(e))
	Juice.stagger_fade(day_cards.get_children())
	_refresh_skill_dock()

# 👀 форс-включение гарантированного гостя в тройку дня (если ещё не там)
func _apply_guaranteed() -> void:
	if guaranteed_npc == "" or day_choices.is_empty():
		return
	for e in day_choices:
		if String(e.get("id", "")) == guaranteed_npc:
			guaranteed_npc = ""; return
	var cfg: Dictionary = _npc_by_id(guaranteed_npc)
	if cfg.is_empty():
		guaranteed_npc = ""; return
	var slot: int = randi() % day_choices.size()
	var tier: int = int(day_choices[slot].get("tier", 1))
	day_choices[slot] = GameData.grade_up_cfg(cfg, tier) if int(cfg.get("tier", 1)) < tier else cfg
	guaranteed_npc = ""

# ---- окно выбора гостей для умений who/ban ----
func _open_skill_picker(mode: String) -> void:
	var xp: int = _xp()
	var unlocked: Dictionary = GameData.prog_unlocked_npcs(xp)
	var ids: Array = []
	for n in GameData.NPCS:
		var id: String = String(n.get("id", ""))
		if not unlocked.has(id):
			continue
		if mode == "ban" and banned_npcs.has(id):
			continue
		ids.append(id)
	if ids.is_empty():
		Sfx.play("badPop"); return
	_pick_mode = mode; _pick_sel = {}; _pick_max = 3 if mode == "ban" else 1
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.62)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)
	ov.position = Vector2.ZERO
	ov.size = get_viewport_rect().size          # страховка полного размера
	skill_overlay = ov
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24; box.offset_right = -24; box.offset_top = 80; box.offset_bottom = -24
	box.add_theme_constant_override("separation", 12)
	ov.add_child(box)
	var title := Label.new()
	title.text = "Кто там? Выбери гостя" if mode == "who" else "Этих не пускайте (до 3)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for id in ids:
		grid.add_child(_pick_cell(_npc_by_id(id)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = "Отмена"; cancel.add_theme_font_size_override("font_size", 22)
	cancel.custom_minimum_size = Vector2(160, 56)
	cancel.pressed.connect(_close_skill_picker)
	row.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Готово"; confirm.add_theme_font_size_override("font_size", 22)
	confirm.custom_minimum_size = Vector2(160, 56)
	confirm.pressed.connect(_skill_pick_confirm)
	row.add_child(confirm)

func _pick_cell(cfg: Dictionary) -> Control:
	var id: String = String(cfg.get("id", ""))
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggled.connect(_on_pick_toggle.bind(id, b))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	b.add_child(vb)
	var tex := load(GameData.portrait_path(cfg)) as Texture2D
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(0, 104)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(ic)
	var nm := Label.new()
	nm.text = String(cfg.get("name", ""))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 16)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	return b

func _on_pick_toggle(pressed: bool, id: String, b: Button) -> void:
	Sfx.play("uiClick")
	if pressed:
		if _pick_sel.size() >= _pick_max:
			if _pick_max == 1:
				_pick_sel.clear()
				for c in b.get_parent().get_children():
					if c is Button and c != b:
						(c as Button).button_pressed = false
			else:
				b.button_pressed = false
				Sfx.play("badPop")
				return
		_pick_sel[id] = true
	else:
		_pick_sel.erase(id)

func _skill_pick_confirm() -> void:
	var sel: Array = _pick_sel.keys()
	if sel.is_empty():
		Sfx.play("badPop"); return
	if not PotionProfile.spend_charge():
		return
	if _pick_mode == "who":
		guaranteed_npc = String(sel[0])
		_toast("👀 Гость придёт в ближайших днях", Color("6ec3ff"))
	else:
		for id in sel:
			banned_npcs[String(id)] = true
		_toast("🚫 Не появятся до конца цикла", Color("ff9a6a"))
	Sfx.play("cardPick")
	_close_skill_picker()
	_refresh_skill_dock()

func _close_skill_picker() -> void:
	if skill_overlay != null and is_instance_valid(skill_overlay):
		skill_overlay.queue_free()
	skill_overlay = null
	_pick_sel = {}

# Карточки дня: тиры = STAGE_TABLE[stage] (на макс.стадии серии дают тир-5),
# затем число тиров подгоняется под размер пула прогрессии (2→3→4). NPC берутся
# только из ОТКРЫТЫХ прогрессией; по возможности разные.
func _pick_day_npcs() -> Array:
	if daily_mode:
		return _daily_pool(day_num - 1)
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
		var e: Dictionary = _pick_config_for_tier(tier, unlocked, used)
		if e.is_empty():
			continue
		used.append(e["id"])
		chosen.append(e)
	return chosen

# Фаза 9: кандидаты слота — персонажи РОДНОГО тира (полный вес) + НИЖНИХ тиров
# «грейдом выше» (вес GRADE_WEIGHT[разрыв]); если выпал нижний — клонируем под целевой тир.
func _pick_config_for_tier(tier: int, unlocked: Dictionary, used: Array) -> Dictionary:
	var cands: Array = []            # [{npc, w}]
	for t in range(tier, 0, -1):
		var gap: int = tier - t
		var w: float = GameData.GRADE_WEIGHT[mini(gap, GameData.GRADE_WEIGHT.size() - 1)]
		for n in _npc_pool(t, unlocked, used):
			cands.append({"npc": n, "w": w})
	if cands.is_empty():
		# родной+нижние исчерпаны — добираем из верхних тиров, иначе любой
		for t in range(tier + 1, 6):
			var up: Array = _npc_pool(t, unlocked, used)
			if not up.is_empty():
				return up[randi() % up.size()]
		var any: Array = _npc_pool(-1, unlocked, used)
		if any.is_empty():
			any = _npc_pool(tier, {}, used)
		return any[randi() % any.size()] if not any.is_empty() else {}
	var picked: Dictionary = _weighted_pick(cands)
	if int(picked.get("tier", 1)) < tier:
		return GameData.grade_up_cfg(picked, tier)   # «грейд выше своего»
	return picked

func _weighted_pick(cands: Array) -> Dictionary:
	var total: float = 0.0
	for c in cands:
		total += float(c["w"])
	var r: float = randf() * total
	for c in cands:
		r -= float(c["w"])
		if r <= 0.0:
			return c["npc"]
	return cands[-1]["npc"]

# Пул NPC: tier (-1 = любой), unlocked (пусто = без фильтра открытости), не used.
func _npc_pool(tier: int, unlocked: Dictionary, used: Array) -> Array:
	var pool: Array = []
	for n in GameData.NPCS:
		if used.has(n["id"]):
			continue
		if pogrom_removed.has(n["id"]):    # выбыл из цикла из-за «Погрома»
			continue
		if banned_npcs.has(n["id"]):       # 🚫 забанен умением «Не пускать»
			continue
		if PotionProfile.relation_left(String(n["id"])):   # ушёл из цикла из-за обиды
			continue
		if tier != -1 and int(n.get("tier", 1)) != tier:
			continue
		if not unlocked.is_empty() and not unlocked.has(n["id"]):
			continue
		pool.append(n)
	return pool

const TIER_NAMES := {1: "НОВИЧОК", 2: "ЗАВСЕГДАТАЙ", 3: "ЦЕНИТЕЛЬ", 4: "ВИП-ГОСТЬ", 5: "ЛЕГЕНДА"}

# Крупная карточка посетителя: большая круглая аватарка (поверх всего; цвет её
# свечения = тир) и одна СПЛОШНАЯ (непрозрачная) панель с обводкой — реплика +
# модификаторы. Тап по карточке разворачивает выбор сложности прямо здесь (без
# отдельного окна): инфо-панель уезжает, портрет остаётся, появляется ЛИНИЯ блоков
# УР.1–4 (см. _toggle_card / _choose_diff). Переходы — плавный кроссфейд.
const CARD_AV := 180.0            # диаметр портрета на карточке дня
const CARD_INFO_LEFT := 150.0     # левый край инфо-панели (слегка заходит под портрет)
const CARD_PANEL_LMARGIN := 52.0  # левый отступ текста внутри панели — чтобы вышел из-под портрета
const CARD_DIFF_LEFT := 198.0     # линия блоков сложности — правее портрета

func _day_card(npc_e: Dictionary) -> Control:
	var tier: int = int(npc_e.get("tier", 1))
	var tcol: Color = GameData.TIER_COLORS.get(tier, Color.WHITE)

	var card := Control.new()
	# высота карточки = диаметр портрета (+рамка) — плашки не выше аватарки
	card.custom_minimum_size = Vector2(440, CARD_AV + 28.0)
	card.clip_contents = false

	# невидимый тач-слой на всю карточку — разворачивает/сворачивает выбор сложности
	var tap := Button.new()
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.focus_mode = Control.FOCUS_NONE
	tap.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tap.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	tap.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	tap.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tap.pressed.connect(_toggle_card.bind(card))
	card.add_child(tap)

	# ---- инфо-панель: сплошная непрозрачная плашка с обводкой в цвет тира
	var info := PanelContainer.new()
	info.set_anchors_preset(Control.PRESET_FULL_RECT)
	info.offset_left = CARD_INFO_LEFT
	info.offset_right = -12.0
	info.offset_top = 14.0
	info.offset_bottom = -14.0
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.09, 0.085, 0.13, 1.0)        # ПОЛНОСТЬЮ непрозрачно
	isb.set_corner_radius_all(14)
	isb.set_border_width_all(2)
	isb.border_color = Color(tcol.r, tcol.g, tcol.b, 0.9)
	isb.shadow_color = Color(tcol.r, tcol.g, tcol.b, 0.22)
	isb.shadow_size = 6
	isb.content_margin_left = CARD_PANEL_LMARGIN; isb.content_margin_right = 16.0
	isb.content_margin_top = 12.0; isb.content_margin_bottom = 12.0
	info.add_theme_stylebox_override("panel", isb)
	card.add_child(info)

	var icol := VBoxContainer.new()
	icol.alignment = BoxContainer.ALIGNMENT_CENTER
	icol.add_theme_constant_override("separation", 8)
	icol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(icol)

	var name_l := Label.new()
	name_l.text = String(npc_e["name"])
	name_l.add_theme_font_size_override("font_size", 23)
	name_l.add_theme_color_override("font_color", Color(0.98, 0.97, 1.0))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icol.add_child(name_l)

	var flavors: Array = npc_e.get("flavors", [""])
	var quote_l := Label.new()
	quote_l.text = "«%s»" % String(flavors[0])
	quote_l.add_theme_font_size_override("font_size", 20)
	quote_l.add_theme_color_override("font_color", Color(0.82, 0.83, 0.9))
	quote_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icol.add_child(quote_l)

	for row in _mod_rows(String(npc_e.get("id", ""))):    # модификаторы — полосы во всю ширину
		icol.add_child(row)

	# ---- линия блоков сложности (скрыта до тапа) — правее портрета
	var diff := HBoxContainer.new()
	diff.set_anchors_preset(Control.PRESET_FULL_RECT)
	diff.offset_left = CARD_DIFF_LEFT
	diff.offset_right = -12.0
	diff.offset_top = 16.0
	diff.offset_bottom = -16.0
	diff.alignment = BoxContainer.ALIGNMENT_CENTER
	diff.add_theme_constant_override("separation", 8)
	diff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diff.visible = false
	_fill_diff_group(diff, npc_e, tier, tcol)
	card.add_child(diff)

	# ---- портрет поверх всего (крупный), тап по нему проходит на тач-слой ниже
	var av := _card_avatar(npc_e, CARD_AV)
	av.anchor_left = 0.0; av.anchor_right = 0.0
	av.anchor_top = 0.5; av.anchor_bottom = 0.5
	av.offset_left = 6.0; av.offset_right = 6.0 + CARD_AV
	av.offset_top = -CARD_AV * 0.5; av.offset_bottom = CARD_AV * 0.5
	card.add_child(av)

	card.set_meta("info", info)
	card.set_meta("diff", diff)
	card.set_meta("expanded", false)
	return card

# Тап по карточке: развернуть выбор сложности (и свернуть остальные).
func _toggle_card(card: Control) -> void:
	var want: bool = not bool(card.get_meta("expanded", false))
	for c in day_cards.get_children():
		if c == card:
			continue
		_set_card_expanded(c, false)
	_set_card_expanded(card, want)
	Sfx.play("uiClick")

func _set_card_expanded(card: Control, on: bool) -> void:
	if not card.has_meta("info"):
		return
	if bool(card.get_meta("expanded", false)) == on:
		return                                  # состояние не меняется — не дёргаем анимацию
	card.set_meta("expanded", on)
	var info := card.get_meta("info") as Control
	var diff := card.get_meta("diff") as Control
	_anim_swap(info if on else diff, diff if on else info)

# Плавный кроссфейд двух слоёв карточки (одна инфа уезжает, другая приезжает).
func _anim_swap(hide_n: Control, show_n: Control) -> void:
	for n in [hide_n, show_n]:
		if n.has_meta("swap_tw"):
			var old := n.get_meta("swap_tw") as Tween
			if old != null and old.is_valid():
				old.kill()

	hide_n.pivot_offset = hide_n.size * 0.5
	var th := hide_n.create_tween()
	hide_n.set_meta("swap_tw", th)
	th.set_parallel(true)
	th.tween_property(hide_n, "modulate:a", 0.0, 0.13).set_ease(Tween.EASE_IN)
	th.tween_property(hide_n, "scale", Vector2(0.94, 0.94), 0.13).set_ease(Tween.EASE_IN)
	th.chain().tween_callback(func(): hide_n.visible = false)

	show_n.visible = true
	show_n.modulate.a = 0.0
	show_n.pivot_offset = show_n.size * 0.5
	show_n.scale = Vector2(0.94, 0.94)
	var ts := show_n.create_tween()
	show_n.set_meta("swap_tw", ts)
	ts.set_parallel(true)
	ts.tween_property(show_n, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_delay(0.07)
	ts.tween_property(show_n, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.07)

# Блоки сложности в ЛИНИЮ: УР.1–4 (метка / «за идеал:» / +NN), тап — сразу в раунд.
# УР.4 — красный (⚠), гейтится репутацией (как раньше в отдельном окне выбора).
func _fill_diff_group(diff: HBoxContainer, npc_e: Dictionary, tier: int, tcol: Color) -> void:
	var cfg: Dictionary = GameData.npc_config(npc_e)
	var base_reward: int = int(cfg.get("reward", 50))
	var om: Dictionary = day_order_mods.get(String(npc_e.get("id", "")), {})
	var focus_mult: float = GameData.FOCUS_REWARD if String(om.get("focus", "")) != "" else 1.0
	var rep_lvl: int = PotionProfile.get_rep_level(String(npc_e.get("id", "")))
	var l4_ok: bool = bool(npc_e.get("level4", false)) or rep_lvl >= GameData.REP_L4_UNLOCK_LEVEL
	for lvl in [1, 2, 3, 4]:
		var ideal: int = int(round(float(base_reward) * float(GameData.REG_DIFF_REWARD_MULT.get(lvl, 1.0)) * focus_mult))
		var locked: bool = (lvl == 4 and not l4_ok)
		diff.add_child(_diff_block(npc_e, lvl, tcol, ideal, locked))

# Один блок сложности — узкая тач-кнопка с вертикальным текстом.
func _diff_block(npc_e: Dictionary, lvl: int, tcol: Color, ideal: int, locked: bool) -> Button:
	var bc: Color = Color("ff5d6a") if lvl == 4 else tcol   # УР.4 — красный
	var b := Button.new()
	b.custom_minimum_size = Vector2(78, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = locked
	var k: float = 1.0 if lvl == 4 else 0.85
	b.add_theme_stylebox_override("normal", _diff_sb(bc, k if not locked else 0.4))
	b.add_theme_stylebox_override("hover", _diff_sb(bc, 1.0))
	b.add_theme_stylebox_override("pressed", _diff_sb(bc, 1.0))
	b.add_theme_stylebox_override("disabled", _diff_sb(bc, 0.4))

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Label.new()
	tag.text = "УР.%d%s" % [lvl, " ⚠" if lvl == 4 else ""]
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 19)
	tag.add_theme_color_override("font_color", bc if not locked else Color(bc.r, bc.g, bc.b, 0.6))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)
	var sub := Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if locked:
		sub.text = "нужна\nрепутация\nур.%d" % GameData.REP_L4_UNLOCK_LEVEL
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		v.add_child(sub)
	else:
		sub.text = "за идеал:"
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		v.add_child(sub)
		var val := Label.new()
		val.text = "+%d" % ideal
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 21)
		val.add_theme_color_override("font_color", Color(0.98, 0.97, 1.0))
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(val)
	b.add_child(v)
	if not locked:
		b.pressed.connect(_choose_diff.bind(npc_e, lvl))
	return b

func _diff_sb(bc: Color, k: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bc.r * 0.16, bc.g * 0.16, bc.b * 0.16, 1.0)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(bc.r, bc.g, bc.b, k)
	sb.content_margin_left = 6.0; sb.content_margin_right = 6.0
	sb.content_margin_top = 8.0; sb.content_margin_bottom = 8.0
	return sb

# Выбор сложности на карточке → сразу в раунд (без отдельного экрана выбора).
func _choose_diff(npc_e: Dictionary, lvl: int) -> void:
	Sfx.play("cardPick")
	_apply_relation_pick(String(npc_e.get("id", "")))   # связи: реакция других гостей дня
	npc = npc_e
	_start_round(lvl)

# Связи NPC открываются прогрессией (relations) + порогом репутации по тиру гостя
func _relation_unlocked(npc_id: String) -> bool:
	if daily_mode:
		return false                 # в дейлике связей нет
	if not GameData.prog_mech_unlocked("relations", _xp()):
		return false
	var cfg: Dictionary = _npc_by_id(npc_id)
	if cfg.is_empty():
		return false
	return PotionProfile.get_rep_level(npc_id) >= GameData.relation_rep_need(int(cfg.get("tier", 1)))

# При выборе гостя дня — реакция остальных двух: друг/собутыльник +репутация,
# враг/неприязнь копят «обиду» (grudge) и теряют репутацию (сильнее с ростом обиды).
func _apply_relation_pick(chosen_id: String) -> void:
	if not _relation_unlocked(chosen_id):
		return
	for e in day_choices:
		var other: String = String(e.get("id", ""))
		if other == chosen_id:
			continue
		var rel: Dictionary = GameData.find_relation(chosen_id, other)
		if rel.is_empty():
			continue
		match String(rel["kind"]):
			"friend":
				PotionProfile.adjust_rep(other, 3.0)
			"buddy":
				PotionProfile.adjust_rep(other, 1.0)
			"enemy", "dislike":
				var bump: Dictionary = PotionProfile.bump_grudge(other)
				var scale: int = mini(int(bump["state"]["grudge"]), 3)
				var base: float = 3.0 if String(rel["kind"]) == "enemy" else 1.0
				PotionProfile.adjust_rep(other, -base * float(scale))
				var nm: String = String(_npc_by_id(other).get("name", ""))
				if bump["just_left"]:
					_toast("🚪 %s обиделся и ушёл до конца цикла" % nm, Color("ff6a6a"))
				elif bump["just_offended"]:
					_toast("😤 %s обиделся — стикеры будут нечестные" % nm, Color("ff9a6a"))

# Модификаторы задания — полосы во всю ширину панели (иконка + название капсом),
# у каждого свой цвет; «без модификатора» — красным.
func _mod_rows(npc_id: String) -> Array:
	var om: Dictionary = day_order_mods.get(npc_id, {})
	var focus: String = String(om.get("focus", ""))
	var mods: Array = om.get("mods", [])
	var rows: Array = []
	if focus == "" and mods.is_empty():
		rows.append(_mod_row(null, "✕", "без модификатора", Color("ff5d6a")))
		return rows
	if focus != "":
		var fm: Dictionary = GameData.FOCUS_META[focus]
		var tex := load("res://assets/ui/%s.png" % FOCUS_IMG.get(focus, "bubble")) as Texture2D
		rows.append(_mod_row(tex, "", "фокус: %s" % fm["name"], Color("6ec3ff")))
	for m in mods:
		var mm: Dictionary = GameData.MOD_META[m]
		# картинка mod_<key>.png (иконка вместо эмодзи), фолбэк — эмодзи из MOD_META
		var mtex := load("res://assets/ui/mod_%s.png" % m) as Texture2D
		rows.append(_mod_row(mtex, String(mm["icon"]), String(mm["name"]), Color("ffcf5d")))
	return rows

func _mod_row(tex: Texture2D, emoji: String, text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.07, 1.0)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 4
	sb.border_color = col
	sb.content_margin_left = 10.0; sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0; sb.content_margin_bottom = 5.0
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var ir := TextureRect.new()
		ir.texture = tex
		ir.custom_minimum_size = Vector2(20, 20)
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(ir)
	elif emoji != "":
		var el := Label.new()
		el.text = emoji
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(el)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	p.add_child(h)
	return p

const FOCUS_IMG := {"bubbles": "bubble", "color": "color", "size": "size"}

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
	if daily_mode:
		_show_daily_end()
		return
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
	_layout_result()
	result_sticker_tex.visible = false
	result_glow.visible = false
	result_points_box.visible = false      # у итога цикла нет очков-за-заказ/разбивки
	result_breakdown_box.visible = false
	result_sticker.text = "Цикл пройден!"
	result_sticker.add_theme_color_override("font_color", Color("6dff8f"))
	# отправляем рейтинг цикла в глобальный топ (онлайн если в аккаунте + локально)
	_lb_save(PotionAuth.get_nickname(), cycle_score)
	var lines: Array = [
		"Рейтинг цикла: %d" % cycle_score,
		"Циклов всего: %d" % int(res.get("cycles", 0)),
		"Опыт: %d" % xp_after,
		"🏆 Рейтинг отправлен в топ (открой 🏆)",
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
	if daily_mode:                   # вышли из дейлика — откатываем прогресс-профиль
		_restore_daily_backup()
		daily_mode = false; daily_diff = ""; _daily_end = false
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
	# чаевые видны только после открытия механики (Ур.4) — прячем весь чип
	hud_tips.get_parent().get_parent().visible = GameData.prog_mech_unlocked("tips", xp)
	hud_tips.text = str(int(t.get("balance", 0)))
	hud_orders.text = str(int(st.get("total_orders", 0)))
	hud_streak.text = str(int(sk.get("goodplus_current", 0)))
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
	jar.set_desat(1.0)             # вернуть цвет (Аптекарь Мо) от прошлого заказа
	jar.set_tilt(0.0)              # снять наклон (Сверхнова) прошлого заказа
	ir_effect_id = ""              # эффект прошлого заказа отыграл
	ir_effect_kind = ""
	_auto_finish = false           # новый заказ — сбрасываем флаг «истёк таймер»
	ir_chip.visible = false
	order_focus = ""               # фокус/модификаторы прошлого заказа сброшены
	order_mods = []
	mod_chip.visible = false
	item_fx = {}                   # эффекты предметов прошлого заказа сброшены
	if item_pending.has("memtime"): item_fx["memtime"] = item_pending["memtime"]  # Ясность → память
	if item_pending.has("time"): item_fx["time"] = item_pending["time"]           # Секундомер → варка
	item_pending = {}
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
	if not replaying:
		_load_order_mods()          # фокус/модификаторы, назначенные при формировании дня
	_show_mod_chip()
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
	phase_total = MEMORIZE_S + float(item_fx.get("memtime", 0.0))   # Тоник ясности
	phase_left = phase_total
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
	phase_total = CRAFT_S + float(item_fx.get("time", 0.0))   # Секундомер
	phase_left = phase_total
	bulb_bar.set_fraction(1.0)      # все горят, дальше гаснут по таймеру
	# активные ползунки — в случайное; неактивные держим на цели (не участвуют)
	var start_vals: Dictionary = _random_values()
	for key in ORDER:
		var v: float = start_vals[key] if key in active else float(target[key])
		sliders[key].set_value_no_signal(v)
	# теперь показываем регуляторы (стулья выезжают) и кнопку «ГОТОВО»
	for key in ORDER:
		slider_cols[key].visible = key in active
		slider_cols[key].modulate = Color.WHITE      # сброс «отключения» джиггером
	done_btn.visible = true
	_set_sliders_interactable(true)
	_slide_in_stools()             # стулья выезжают слева направо
	_apply_to_jar(_current_values())
	_update_value_labels(_current_values())
	if mech:
		mech.craft_start(self)
	_apply_ir_effect()             # игровые эффекты выбранного заказу баффа/дебаффа
	if "timer" in order_mods:      # модификатор «Таймер»: −25% времени (после всех аддитивов)
		phase_total = maxf(3.0, phase_total * 0.75)
		phase_left = maxf(2.0, phase_left * 0.75)

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

# ---------- Фаза 3: фокус-заказы и модификаторы ----------
# Бросок модификаторов для КОНКРЕТНОГО гостя (при формировании дня, чтобы показать
# их на карточке выбора). Всё гейтится прогрессией: фокус — с «modifiers» (ур.3),
# timer/duck/rampage — с «modifiers_new3» (ур.4), несколько — с «modifiers_multi» (ур.7).
func _roll_order_mods(npc_e: Dictionary, force: bool) -> Dictionary:
	var res: Dictionary = {"focus": "", "mods": []}
	var xp: int = _xp()
	if not GameData.prog_mech_unlocked("modifiers", xp):
		return res
	var tier: int = int(npc_e.get("tier", 1))
	if tier < 2 or String(npc_e.get("id", "")) == "tentacloid":
		return res
	if not force and randf() >= 0.4:            # DEV-форс обходит шанс, но не гейтинг прогрессии
		return res
	var new3: bool = GameData.prog_mech_unlocked("modifiers_new3", xp)
	var multi: bool = GameData.prog_mech_unlocked("modifiers_multi", xp)
	var kinds: Array = []
	if String(npc_e.get("type", "normal")) == "normal" and not (String(npc_e.get("id", "")) in GameData.MOD_FOCUS_EXCLUDE):
		kinds.append("focus")
	if new3:
		if String(npc_e.get("special", "")) != "no_timer":
			kinds.append("timer")
		kinds.append("duck")
		kinds.append("rampage")
	if kinds.is_empty():
		return res
	var count: int = 1
	if multi and tier >= 4:
		var r: float = randf()
		if r < 0.015: count = 3
		elif r < 0.12: count = 2
	count = mini(count, kinds.size())
	kinds.shuffle()
	for i in count:
		var k: String = kinds[i]
		if k == "focus":
			var opts: Array = ["color", "size"] if String(npc_e.get("id", "")) == "swarm_navigator" else ["bubbles", "color", "size"]
			res["focus"] = String(opts[randi() % opts.size()])
		else:
			(res["mods"] as Array).append(k)
	return res

# Применить назначенные модификаторы к текущему заказу (из day_order_mods по id гостя).
func _load_order_mods() -> void:
	var om: Dictionary = day_order_mods.get(String(npc.get("id", "")), {})
	order_focus = String(om.get("focus", ""))
	order_mods = (om.get("mods", []) as Array).duplicate()
	# фокус на низких УР бесполезен, если его регуляторы не активны — добавляем их
	# (только обычные оцениваемые: спектр/объём/сгустки/размер; sat/colorB и т.п. не трогаем)
	if order_focus != "" and level < 3:
		for fk in GameData.FOCUS_KEYS[order_focus]:
			if fk in ["color", "volume", "count", "bsize"] and fk in ORDER and not (fk in active):
				active.append(fk)

# ---------- Фаза 6: применение предметов ----------
func _use_item(id: String, grade: int) -> void:
	if not PotionProfile.consume_item(id, grade):
		Sfx.play("bad")
		return
	var it: Dictionary = GameData.shop_item(id)
	if it.is_empty():
		return
	var g: Dictionary = it["grades"][grade]
	match String(it["effect"]):
		"time": item_pending["time"] = float(item_pending.get("time", 0.0)) + float(g["sec"])
		"memtime": item_pending["memtime"] = float(item_pending.get("memtime", 0.0)) + float(g["sec"])
		"flatbonus": item_fx["flat"] = int(g["flat"])
		"rewardmult": item_fx["mult"] = float(g["mult"])
		"chip": item_fx["chip"] = {"lo": g["lo"], "hi": g["hi"]}
		"shield": item_fx["shield"] = float(g["cut"])
		"nudge": item_fx["nudge"] = int(g["count"])
		"repboost": item_fx["rep"] = int(g["rep"])
		"speedlock": item_fx["speedlock"] = float(g["lock"])
		"jigger": _apply_jigger(int(g["n"]))
	Sfx.play("uiClick")
	_toast("%s %s применён" % [it["icon"], it["name"]], Color("6dff8f"))

# «Джиггер»: отключает n случайных активных регуляторов — они больше не оцениваются.
func _apply_jigger(n: int) -> void:
	var pool: Array = active.duplicate(); pool.shuffle()
	for i in mini(n, pool.size()):
		var k: String = pool[i]
		active.erase(k)
		if slider_cols.has(k):
			slider_cols[k].modulate = Color(1, 1, 1, 0.35)   # визуально «отключён»

# Плашка фокуса/модификаторов заказа: иконки + названия, «висит» весь заказ.
func _show_mod_chip() -> void:
	var parts: Array = []
	if order_focus != "":
		var fm: Dictionary = GameData.FOCUS_META[order_focus]
		parts.append("%s фокус: %s" % [fm["icon"], fm["name"]])
	for m in order_mods:
		var mm: Dictionary = GameData.MOD_META[m]
		parts.append("%s %s" % [mm["icon"], mm["name"]])
	if parts.is_empty():
		mod_chip.visible = false
		return
	mod_chip.text = "   ".join(parts)
	mod_chip.add_theme_color_override("font_color", Color("ffcf5d"))
	mod_chip.visible = true

# ---------- таймеры фаз ----------
func _process(delta: float) -> void:
	if items_btn != null:          # «сумка» видна в игре/выборе, если магазин открыт
		items_btn.visible = not daily_mode and GameData.prog_mech_unlocked("shop", _xp()) and (phase == "day" or phase == "select" or phase == "memorize" or phase == "recreate")
	# инвентарь открыт (применяем предметы) — ставим таймер/механику на паузу
	if items_panel != null and items_panel.visible:
		return
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
				_auto_finish = true          # таймер истёк сам — для стикера bad7
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
	_auto_finish = false                  # игрок нажал «Готово» сам
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
	# уводим ПОЛНОСТЬЮ за верхний край (стрип высокий) — иначе низ стрипа лезет к лампам
	var dy: float = -(STRIP_TOP + STRIP_H + 24.0) if hidden else 0.0
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
	# Барменский глаз: подвигаем ползунки на деление ближе к цели (до подсчёта)
	if item_fx.has("nudge"):
		var cnt: int = int(item_fx["nudge"])
		var keys: Array = active.duplicate(); keys.shuffle()
		if cnt >= 99:
			cnt = keys.size()
		for i in mini(cnt, keys.size()):
			var sl: TouchSlider = sliders[keys[i]]
			var tgt: float = float(target[keys[i]])
			if absf(sl.value - tgt) > 0.001:
				sl.set_value_no_signal(clampf(sl.value + signf(tgt - sl.value) * sl.step, sl.min_value, sl.max_value))
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
		# фокус-заказ: фокусные параметры весят ×2.2, остальные ×0.55
		if order_focus != "":
			w *= GameData.FOCUS_W_ON if key in GameData.FOCUS_KEYS[order_focus] else GameData.FOCUS_W_OFF
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
	# Фаза 3: множители от модификаторов заказа (фокус +25% награды; Утка усиливает
	# плюс и штраф; Погром — ×2 рейтинг и чаевые)
	if order_focus != "":
		reward = int(round(float(reward) * GameData.FOCUS_REWARD))
	var pos_mult: float = rating_mult
	var neg_mult: float = 1.0
	var tip_mult: float = 1.0
	if "duck" in order_mods:
		pos_mult *= 1.6; neg_mult *= 1.6
	if "rampage" in order_mods:
		pos_mult *= 2.0; tip_mult *= 2.0
	# предметы магазина: шейкер (×+% на плюс), фишка (случайно ±% на итог),
	# трос (−штраф), соль (+flat за годноту)
	var good_res: bool = grade == "perfect" or grade == "good"
	var flat_bonus: int = 0
	if item_fx.has("mult") and good_res:
		pos_mult *= (1.0 + float(item_fx["mult"]))
	if item_fx.has("chip"):
		var ch: Dictionary = item_fx["chip"]
		var f: float = float(ch["lo"]) + randf() * (float(ch["hi"]) - float(ch["lo"]))
		pos_mult *= (1.0 + f); neg_mult *= (1.0 + f)
	if item_fx.has("shield"):
		neg_mult *= (1.0 - float(item_fx["shield"]))
	if item_fx.has("flat") and good_res:
		flat_bonus = int(item_fx["flat"])
	var time_frac: float = clampf(1.0 - phase_left / maxf(0.001, phase_total), 0.0, 1.0)
	# серии ДО записи результата (record_result их инкрементирует) — для особых стикеров
	var sk0: Dictionary = PotionProfile.data["streaks"]
	var perfect_run: int = (int(sk0.get("perfect_current", 0)) + 1) if grade == "perfect" else 0
	var good_run: int = (int(sk0.get("goodplus_current", 0)) + 1) if good_res else 0
	var bad_before: int = int(sk0.get("bad_current", 0))
	var sticker_name: String = ""     # выберем после record_result (нужен рейтинг цикла)

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
		npc["id"], tier, overall, grade, reward, "",
		time_frac, level, order_focus, pos_mult, no_points, neg_mult, tip_mult, flat_bonus)

	# Фаза 7: заряд умения за каждые 3 идеала за цикл
	if grade == "perfect" and cycle_active:
		if PotionProfile.bump_perfect_charge(3):
			_toast("✨ +1 заряд умения", Color("ffd24d"))

	# особый стикер по условию (или базовый случайный) — рейтинг цикла уже известен
	var score_after: int = cycle_score + int(outcome.get("points", 0))
	sticker_name = _pick_sticker(grade, overall, comps, tier, time_frac, score_after,
		perfect_run, good_run, bad_before)
	# Связи: обиженный гость (grudge≥3) форсит «нечестный» стикер-брак (💩 = bad9),
	# очки/серии/репутация считаются по НАСТОЯЩЕМУ результату — спойлится только вид.
	var sticker_grade: String = grade
	if _relation_unlocked(String(npc.get("id", ""))) and bool(PotionProfile.relation_state(String(npc["id"])).get("offended", false)):
		sticker_grade = "bad"
		sticker_name = "bad9"
	PotionProfile.mark_sticker_seen(sticker_grade, sticker_name)

	# «Последний из Ир» (УР.3+): идеал → бафф след. заказу, брак/пойло → дебафф
	if String(npc.get("id", "")) == "last_of_ir" and level >= 3:
		if grade == "perfect":
			ir_pending = "buff"
		elif grade != "good":
			ir_pending = "debuff"

	# «Погром»: гость дерётся — выбывает из цикла и портит репутацию другим гостям дня
	if "rampage" in order_mods:
		var myid: String = String(npc.get("id", ""))
		if not (myid in pogrom_removed):
			pogrom_removed.append(myid)
		for e in day_choices:
			var oid: String = String(e.get("id", ""))
			if oid != "" and oid != myid:
				PotionProfile.adjust_rep(oid, -2.0)
		_toast.call_deferred("💥 Погром: «%s» ушёл и подпортил репутацию гостям дня" % String(npc.get("name", "")), Color("ff9a6a"))

	# для перехода дня/цикла
	last_grade = grade
	cycle_stickers[grade] = int(cycle_stickers.get(grade, 0)) + 1   # стикеры за цикл
	cycle_score += int(outcome.get("points", 0))

	_show_result(overall, comps, grade, outcome, sticker_name)

# Выбор стикера: особый — ТОЛЬКО по условию (порт STICKER_SPECIALS из content.js),
# приоритет ещё не собранным; иначе случайный из первых BASE_STICKERS «базовых».
func _pick_sticker(grade: String, overall: float, comps: Dictionary, tier: int,
		time_frac: float, score_after: int, perfect_run: int, good_run: int, bad_before: int) -> String:
	var arr: Array = GameData.STICKERS[grade]
	var special_idx: Array = _sticker_special_idx(grade, overall, comps, tier, time_frac,
		score_after, perfect_run, good_run, bad_before)
	# отбрасываем индексы вне диапазона (страховка, если картинок в категории меньше)
	special_idx = special_idx.filter(func(i): return int(i) < arr.size())
	if not special_idx.is_empty():
		var seen: Array = PotionProfile.data["stats"]["stickers_seen"][grade]
		var unseen: Array = special_idx.filter(func(i): return not seen.has(String(arr[i])))
		var pool: Array = unseen if not unseen.is_empty() else special_idx
		return String(arr[pool[randi() % pool.size()]])
	return String(arr[randi() % GameData.BASE_STICKERS])

# Индексы особых стикеров, чьё условие выполнено (см. STICKER_SPECIALS в браузере).
# Часть условий (печать Хранителя `sealed`, форс по связям НПС) ждёт портирования
# своих механик — помечено TODO и пока не срабатывает.
func _sticker_special_idx(grade: String, overall: float, comps: Dictionary, tier: int,
		time_frac: float, score_after: int, perfect_run: int, good_run: int, bad_before: int) -> Array:
	var out: Array = []
	var special: String = String(npc.get("special", ""))
	var has_gradient: bool = String(npc.get("type", "")) == "gradient"
	var ir_debuff: bool = ir_effect_kind == "debuff"
	var sealed: bool = false     # TODO: печать Хранителя Архива не портирована
	match grade:
		"perfect":
			var all_exact: bool = true
			for v in comps.values():
				if float(v) < 0.999:
					all_exact = false
					break
			var nova_exact: bool = special == "dual_size" and comps.has("size2") \
				and float(comps.get("size2", 0.0)) >= 0.999 and float(comps.get("volume", 1.0)) >= 0.999
			if perfect_run >= 5 and perfect_run < 10: out.append(3)   # серия 5–9 идеалов
			if perfect_run >= 10: out.append(4)                       # серия 10+
			if all_exact: out.append(5)                               # все параметры ровно
			if has_gradient: out.append(6)                            # идеал на градиенте
			if special == "no_timer" and overall >= 0.99: out.append(7)  # Тот-Кто-Ждёт
			if time_frac <= 1.0 / 6.0: out.append(8)                  # в первую 1/6 таймера
			if ir_debuff: out.append(9)                               # под дебаффом Ир
			if sealed: out.append(10)                                 # под печатью Хранителя
			if level == 4: out.append(11)                             # на УР.4
			if score_after >= 3500: out.append(12)                    # рейтинг цикла 3500+
			if nova_exact: out.append(13)                             # Сверхнова: ширина И высота
			if day_num >= cycle_days: out.append(14)                  # последний день цикла
		"good":
			if overall >= GameData.perfect_threshold(tier) - 0.02: out.append(3)  # почти идеал
			if good_run >= 8: out.append(4)                           # 8+ годнот подряд
			if time_frac >= 0.9: out.append(5)                        # в последние 10% таймера
			if bad_before >= 2: out.append(6)                         # прервал серию 2+ браков
			var tl: int = int((PotionProfile.data.get("tips", {}) as Dictionary).get("lifetime", 0))
			if tl >= 1000: out.append(7)                              # 1000+ чаевых за историю
			if tl >= 10000: out.append(8)                             # 10000+ чаевых
		"swill":
			if overall >= GameData.good_threshold(tier) - 0.03: out.append(3)   # почти годнота
			if bad_before >= 2: out.append(4)                         # прервал серию 2+ браков
		"bad":
			if overall < 0.3: out.append(3)                           # точность < 30%
			if level == 1: out.append(4)                              # брак на УР.1
			if bad_before >= 2: out.append(5)                         # третий брак подряд
			if _auto_finish: out.append(6)                            # таймер истёк сам
			if sealed: out.append(7)                                  # брак под печатью
			# idx 8 (bad9) — форс обиженным НПС по связям; TODO (связи-форс не портирован)
	return out

# «Дальше →» на экране результата: конец цикла → новый цикл, иначе → следующий день.
func _result_next() -> void:
	# принял результат — цепочка переигровки Ир закрыта, снимок больше не нужен
	ir_replay_active = false
	ir_force_extra = ""
	_replay_snapshot = {}
	ir_replay_mode = ""
	if _daily_end:
		_daily_end = false
		_show_start()
	elif phase == "cycle_end":
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
	_layout_result()          # разложить зоны под текущий размер экрана
	var gcol: Color = GRADE_COLOR.get(grade, Color.WHITE)
	# звук по грейду: идеал/годно — позитив, пойло/брак — неудача
	Sfx.play("perfect" if grade == "perfect" else "good" if grade == "good" else "bad")
	if bool(outcome.get("level_up", false)):
		Sfx.play("achieve")

	# стикер-картинка + грейд крупно (цветом) с процентом
	var stex := load(GameData.sticker_path(sticker_name)) as Texture2D
	result_sticker_tex.texture = stex
	result_sticker_tex.visible = stex != null
	# круглое свечение-ореол за стикером в цвет грейда
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(gcol.r, gcol.g, gcol.b, 0.16)
	gsb.set_corner_radius_all(200)
	gsb.shadow_color = Color(gcol.r, gcol.g, gcol.b, 0.55)
	gsb.shadow_size = 26
	result_glow.add_theme_stylebox_override("panel", gsb)
	result_glow.visible = stex != null
	result_points_box.visible = true
	result_breakdown_box.visible = true
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
	var focus_keys: Array = GameData.FOCUS_KEYS.get(order_focus, []) if order_focus != "" else []
	for key in active:
		var pct: int = int(round(float(comps[key]) * 100.0))
		var rowb := HBoxContainer.new()
		var nl := Label.new()
		var focused: bool = key in focus_keys
		nl.text = ("%s " % GameData.FOCUS_META[order_focus]["icon"] if focused else "") + PARAMS[key]["label"]
		nl.modulate = Color("ffcf5d") if focused else Color(1, 1, 1, 0.8)
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
	Juice.pop.call_deferred(result_points_box)
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
