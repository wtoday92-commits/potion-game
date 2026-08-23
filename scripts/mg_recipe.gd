extends Control
class_name RecipeBook
## Книга рецептов Шефа: стильный оверлей со вкладками-категориями (Жидкости/Специи/
## Продукты — только те, что участвуют на уровне). Внутри вкладки — ВСЕ ингредиенты
## категории с их значениями (и слогом на УР.4). Игрок находит показанные и выставляет
## по ним ползунки. Данные ингредиентов — здесь же (используются и ChefMech).

signal closed

# --- ДАННЫЕ ИНГРЕДИЕНТОВ (значения снапнуты под шаг ползунков) ---
const LIQUIDS := [
	{"name": "Вино",    "icon": "res://assets/chef/liq_wine.png",  "hue": 340.0, "sat": 80.0,  "syl": "Па"},
	{"name": "Масло",   "icon": "res://assets/chef/liq_oil.png",   "hue": 45.0,  "sat": 60.0,  "syl": "По"},
	{"name": "Вода",    "icon": "res://assets/chef/liq_water.png", "hue": 200.0, "sat": 20.0,  "syl": "На"},
	{"name": "Сок",     "icon": "res://assets/chef/liq_juice.png", "hue": 25.0,  "sat": 90.0,  "syl": "Ма"},
	{"name": "Кровь",   "icon": "res://assets/chef/liq_blood.png", "hue": 0.0,   "sat": 100.0, "syl": "Ка"},
	{"name": "Слизь",   "icon": "res://assets/chef/liq_slime.png", "hue": 110.0, "sat": 90.0,  "syl": "Та"},
	{"name": "Чернила", "icon": "res://assets/chef/liq_ink.png",   "hue": 260.0, "sat": 70.0,  "syl": "Ра"},
	{"name": "Лава",    "icon": "res://assets/chef/liq_lava.png",  "hue": 15.0,  "sat": 100.0, "syl": "Са"},
	{"name": "Молоко",  "icon": "res://assets/chef/liq_milk.png",  "hue": 40.0,  "sat": 10.0,  "syl": "Ла"},
	{"name": "Эфир",    "icon": "res://assets/chef/liq_ether.png", "hue": 180.0, "sat": 50.0,  "syl": "Ба"},
]
const ADDONS := [
	{"name": "Лимон", "icon": "res://assets/chef/add_lemon.png",  "vol": 30.0,  "syl": "Прол"},
	{"name": "Соль",  "icon": "res://assets/chef/add_salt.png",   "vol": 15.0,  "syl": "Трол"},
	{"name": "Перец", "icon": "res://assets/chef/add_pepper.png", "vol": 45.0,  "syl": "Крол"},
	{"name": "Лёд",   "icon": "res://assets/chef/add_ice.png",    "vol": 60.0,  "syl": "Плор"},
	{"name": "Сахар", "icon": "res://assets/chef/add_sugar.png",  "vol": 75.0,  "syl": "Прил"},
	{"name": "Мёд",   "icon": "res://assets/chef/add_honey.png",  "vol": 90.0,  "syl": "Прал"},
	{"name": "Мята",  "icon": "res://assets/chef/add_mint.png",   "vol": 100.0, "syl": "Брол"},
	{"name": "Уголь", "icon": "res://assets/chef/add_coal.png",   "vol": 22.0,  "syl": "Прул"},
]
const PRODUCTS := [
	{"name": "Кость", "icon": "res://assets/chef/prod_bone.png",     "bsize": 40.0, "count": 3, "syl": "Толк"},
	{"name": "Яйцо",  "icon": "res://assets/chef/prod_egg.png",      "bsize": 70.0, "count": 2, "syl": "Талк"},
	{"name": "Песок", "icon": "res://assets/chef/prod_sand.png",     "bsize": 20.0, "count": 8, "syl": "Толп"},
	{"name": "Икра",  "icon": "res://assets/chef/prod_caviar.png",   "bsize": 14.0, "count": 10, "syl": "Толт"},
	{"name": "Гриб",  "icon": "res://assets/chef/prod_mushroom.png", "bsize": 54.0, "count": 4, "syl": "Колт"},
	{"name": "Орех",  "icon": "res://assets/chef/prod_nut.png",      "bsize": 44.0, "count": 5, "syl": "Молт"},
	{"name": "Зерно", "icon": "res://assets/chef/prod_grain.png",    "bsize": 26.0, "count": 7, "syl": "Толм"},
	{"name": "Жук",   "icon": "res://assets/chef/prod_beetle.png",   "bsize": 60.0, "count": 3, "syl": "Нолт"},
	{"name": "Глаз",  "icon": "res://assets/chef/prod_eye.png",      "bsize": 80.0, "count": 2, "syl": "Толн"},
	{"name": "Семя",  "icon": "res://assets/chef/prod_seed.png",     "bsize": 30.0, "count": 6, "syl": "Солт"},
]

const CAT_LIQ := 0
const CAT_ADD := 1
const CAT_PROD := 2
const CAT_NAMES := ["Жидкости", "Специи", "Продукты"]

var _level: int = 1
var _snap: Dictionary = {}     # key -> {min,max,step} реальной сетки ползунков раунда
var _cats: Array = []          # какие категории показывать (индексы)
var _cur: int = 0
var _tabs: Array = []          # кнопки-вкладки
var _list_holder: VBoxContainer
var _scroll: ScrollContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# сами тянемся на вьюпорт (у корня main анкеры не дают полный размер — как в минииграх)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _process(_delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	if not size.is_equal_approx(vp):
		size = vp

func open(level: int, cats: Array, snap: Dictionary = {}) -> void:
	_level = level
	_cats = cats
	_snap = snap
	_cur = cats[0]
	_build()
	# анимация появления
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.18)

func _build() -> void:
	# затемнение фона
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	# «книга» — тёплая панель
	var book := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.19, 0.13, 0.09)
	sb.border_color = Color(0.85, 0.62, 0.32)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	book.add_theme_stylebox_override("panel", sb)
	book.set_anchors_preset(Control.PRESET_FULL_RECT)
	book.offset_left = 20; book.offset_right = -20
	book.offset_top = 70; book.offset_bottom = -20
	book.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(book)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 16; vb.offset_right = -16; vb.offset_top = 12; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 10)
	book.add_child(vb)

	# шапка
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "📖 Книга рецептов"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.98, 0.90, 0.72))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 24)
	close.custom_minimum_size = Vector2(48, 48)
	close.pressed.connect(_on_close)
	head.add_child(close)
	vb.add_child(head)

	# вкладки категорий (только участвующие на уровне)
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 8)
	_tabs.clear()
	for cat in _cats:
		var tb := Button.new()
		tb.text = CAT_NAMES[cat]
		tb.focus_mode = Control.FOCUS_NONE
		tb.toggle_mode = true
		tb.add_theme_font_size_override("font_size", 20)
		tb.custom_minimum_size = Vector2(0, 44)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_on_tab.bind(cat))
		tabrow.add_child(tb)
		_tabs.append(tb)
	vb.add_child(tabrow)

	# список
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll)
	_list_holder = VBoxContainer.new()
	_list_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_holder.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list_holder)

	_refresh_tabs()
	_fill_list()

func _on_tab(cat: int) -> void:
	if cat == _cur:
		return
	_cur = cat
	_refresh_tabs()
	# анимация смены вкладки: список гаснет и появляется
	var t := _list_holder.create_tween()
	t.tween_property(_list_holder, "modulate:a", 0.0, 0.08)
	t.tween_callback(_fill_list)
	t.tween_property(_list_holder, "modulate:a", 1.0, 0.14)

func _refresh_tabs() -> void:
	for i in _tabs.size():
		var tb: Button = _tabs[i]
		var active: bool = (_cats[i] == _cur)
		tb.button_pressed = active
		tb.modulate = Color(1, 1, 1, 1) if active else Color(0.7, 0.66, 0.6, 1)

func _items_for(cat: int) -> Array:
	match cat:
		CAT_LIQ: return LIQUIDS
		CAT_ADD: return ADDONS
		_: return PRODUCTS

func _fill_list() -> void:
	for c in _list_holder.get_children():
		c.queue_free()
	var items := _items_for(_cur)
	for it in items:
		_list_holder.add_child(_make_row(it, _cur))

func _make_row(it: Dictionary, cat: int) -> Control:
	var row := Panel.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.26, 0.19, 0.13)
	rsb.set_corner_radius_all(10)
	rsb.content_margin_left = 8; rsb.content_margin_right = 12
	rsb.content_margin_top = 6; rsb.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", rsb)
	row.custom_minimum_size = Vector2(0, 72)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	# иконка в «лунке»
	var well := Panel.new()
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.12, 0.09, 0.06)
	wsb.set_corner_radius_all(10)
	well.add_theme_stylebox_override("panel", wsb)
	well.custom_minimum_size = Vector2(60, 60)
	var icon := TextureRect.new()
	icon.texture = load(it["icon"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.add_child(icon)
	hb.add_child(well)
	# название + значения
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := Label.new()
	nm.text = it["name"]
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78))
	col.add_child(nm)
	var val := Label.new()
	val.text = _values_text(it, cat)
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0))
	col.add_child(val)
	hb.add_child(col)
	# слог (только УР.4) — крупно справа
	if _level == 4:
		var syl := Label.new()
		syl.text = "«%s»" % it["syl"]
		syl.add_theme_font_size_override("font_size", 26)
		syl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
		syl.custom_minimum_size = Vector2(90, 0)
		syl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		syl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(syl)
	return row

# значение, снапнутое к реальной сетке ползунка раунда (чтобы игрок мог его выставить)
func _snap_v(key: String, v: float) -> float:
	if not _snap.has(key):
		return v
	var c: Dictionary = _snap[key]
	var step: float = float(c.get("step", 0.0))
	var r: float = v
	if step > 0.0:
		r = float(c["min"]) + roundf((v - float(c["min"])) / step) * step
	return clampf(r, float(c["min"]), float(c["max"]))

func _values_text(it: Dictionary, cat: int) -> String:
	match cat:
		CAT_LIQ: return "Спектр %d°   ·   Накал %d%%" % [int(_snap_v("color", it["hue"])), int(_snap_v("sat", it["sat"]))]
		CAT_ADD: return "Объём %d%%" % int(_snap_v("volume", it["vol"]))
		_: return "Размер %d%%   ·   Сгустки %d" % [int(_snap_v("bsize", it["bsize"])), int(_snap_v("count", it["count"]))]

func _on_close() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.14)
	t.tween_callback(func():
		closed.emit()
		queue_free())
