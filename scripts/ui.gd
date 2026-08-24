extends Object
class_name UI
## Единая дизайн-система интерфейса: типошкала, палитра, шаг сетки и готовые
## подложки/кнопки. Заведена по итогам аудита 2026-08-25, где выяснилось, что
## в коде было 24 разных кегля, 304 цветовых литерала и 474 ручных override
## при одной общей теме.
##
## ПРАВИЛО: в UI-коде не должно появляться ни чисел кегля, ни `Color(...)`,
## ни произвольных отступов — только константы отсюда. Исключение — рисование
## арта в `_draw()` (стулья, калибратор, стаканы): это иллюстрация, а не
## интерфейс, у неё своя палитра по месту.

# ---------- Типошкала (7 ступеней, шаг ~1.3) ----------
const FS_XS := 14      # мелкая служебная подпись, счётчик на иконке
const FS_S := 17       # вторичный текст, подписи под элементом
const FS_M := 20       # основной текст интерфейса
const FS_L := 26       # подзаголовок, крупное число
const FS_XL := 34      # заголовок экрана
const FS_XXL := 46     # главный акцент (грейд, кнопка-герой)
const FS_HERO := 62    # эмодзи-глиф во всю кнопку

# ---------- Шаг сетки ----------
const SP_XS := 4
const SP_S := 8
const SP_M := 12
const SP_L := 16
const SP_XL := 24
const SP_XXL := 32

# ---------- Радиусы и толщины ----------
const R_S := 8
const R_M := 12
const R_L := 16
const BORDER := 2

# ---------- Палитра ----------
# Ground
const BG := Color(0.05, 0.055, 0.085, 1.0)          # фон панели на весь экран
const PANEL := Color(0.11, 0.12, 0.19, 1.0)         # карточка
const PANEL_2 := Color(0.07, 0.08, 0.13, 1.0)       # вложенная ячейка
const SCRIM := Color(0, 0, 0, 0.62)                 # затемнение арта под контентом
# Ink
const TXT := Color(0.95, 0.95, 1.0)                 # основной текст
const TXT_DIM := Color(1, 1, 1, 0.62)               # подпись
const TXT_MUTED := Color(1, 1, 1, 0.38)             # выключенное/подсказка
# Accent
const GOLD := Color("ffcf5d")                       # акцент: заголовки, валюта, главная кнопка
const GOLD_DIM := Color(0.95, 0.82, 0.5)
const CYAN := Color("6ec3ff")                       # выбранное состояние, ссылки-действия
# Semantic
const OK := Color("6dff8f")                         # успех
const WARN := Color("ffb36a")                       # предупреждение, заморожено
const BAD := Color("ff5d6a")                        # провал, штраф
# Lines
const BORDER_C := Color(0.34, 0.32, 0.5, 0.55)      # обводка панели
const BORDER_SOFT := Color(0.34, 0.32, 0.5, 0.28)   # разделитель

# ---------- Подложки ----------
enum Surface { PANEL, CARD, CELL }

# Подложка нужного уровня. level — Surface.*, accent — цвет обводки (пусто → штатная).
static func surface(level: int = Surface.CARD, accent: Color = BORDER_C) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match level:
		Surface.PANEL:
			sb.bg_color = BG
			sb.set_corner_radius_all(R_L)
			sb.set_border_width_all(BORDER)
			sb.set_content_margin_all(float(SP_XL))
		Surface.CELL:
			sb.bg_color = PANEL_2
			sb.set_corner_radius_all(R_S)
			sb.set_border_width_all(1)
			sb.set_content_margin_all(float(SP_M))
		_:
			sb.bg_color = PANEL
			sb.set_corner_radius_all(R_M)
			sb.set_border_width_all(BORDER)
			sb.set_content_margin_all(float(SP_L))
	sb.border_color = accent
	return sb

# ---------- Кнопки ----------
enum Btn { PRIMARY, NORMAL, QUIET }

static func button(kind: int = Btn.NORMAL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(R_M)
	sb.content_margin_left = float(SP_L)
	sb.content_margin_right = float(SP_L)
	sb.content_margin_top = float(SP_M)
	sb.content_margin_bottom = float(SP_M)
	match kind:
		Btn.PRIMARY:
			sb.bg_color = Color(0.17, 0.13, 0.06, 1.0)
			sb.set_border_width_all(3)
			sb.border_color = GOLD
		Btn.QUIET:
			sb.bg_color = Color(0.09, 0.09, 0.14, 1.0)
			sb.set_border_width_all(1)
			sb.border_color = BORDER_SOFT
		_:
			sb.bg_color = Color(0.13, 0.13, 0.19, 1.0)
			sb.set_border_width_all(BORDER)
			sb.border_color = BORDER_C
	return sb

# Навесить на кнопку все четыре состояния разом — вместо четырёх override по месту.
static func style_button(b: Button, kind: int = Btn.NORMAL) -> Button:
	var base := button(kind)
	b.add_theme_stylebox_override("normal", base)
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.06)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := base.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed.bg_color.darkened(0.12)
	b.add_theme_stylebox_override("pressed", pressed)
	var dis := base.duplicate() as StyleBoxFlat
	dis.bg_color = Color(dis.bg_color.r, dis.bg_color.g, dis.bg_color.b, 0.5)
	dis.border_color = Color(dis.border_color.r, dis.border_color.g, dis.border_color.b, 0.3)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if kind == Btn.PRIMARY:
		b.add_theme_color_override("font_color", GOLD)
	b.focus_mode = Control.FOCUS_NONE
	return b

# ---------- Общая тема ----------
# Всё, что можно задать один раз для всей игры, задаётся здесь: дальше виджеты
# создаются без единого override и уже выглядят правильно.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_M

	# Подписи: тень оставлена только как страховка поверх арта в раунде
	t.set_color("font_color", "Label", TXT)
	# Тень мягкая и без контура: раньше она была костылём читаемости поверх арта,
	# теперь за это отвечает скрим, а жирная тень только мутила текст на панелях.
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("shadow_outline_size", "Label", 0)

	# Кнопки: штатный вид — «обычная», чтобы override нужен был только на исключениях
	t.set_font_size("font_size", "Button", FS_M)
	t.set_color("font_color", "Button", TXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1, 1))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", TXT_MUTED)
	t.set_stylebox("normal", "Button", button(Btn.NORMAL))
	var bh := button(Btn.NORMAL)
	bh.bg_color = bh.bg_color.lightened(0.06)
	t.set_stylebox("hover", "Button", bh)
	var bp := button(Btn.NORMAL)
	bp.bg_color = bp.bg_color.darkened(0.12)
	t.set_stylebox("pressed", "Button", bp)
	var bd := button(Btn.NORMAL)
	bd.bg_color = Color(bd.bg_color.r, bd.bg_color.g, bd.bg_color.b, 0.5)
	bd.border_color = Color(bd.border_color.r, bd.border_color.g, bd.border_color.b, 0.3)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_stylebox("panel", "PanelContainer", surface(Surface.CARD))
	t.set_stylebox("panel", "Panel", surface(Surface.CARD))

	# Прокрутка: узкая ненавязчивая полоса
	t.set_constant("separation", "BoxContainer", SP_M)
	t.set_constant("h_separation", "GridContainer", SP_M)
	t.set_constant("v_separation", "GridContainer", SP_M)
	return t
