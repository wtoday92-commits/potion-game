extends Control
class_name MatrixRain
## Дождь падающих глифов колонками — фирменный визуал Хранителя Архива
## (порт startMatrixRain из браузера). Полупрозрачные мятные символы сыплются
## сверху поверх банки, мешая разглядеть смесь. Не перехватывает ввод.
##
## Набор глифов — греческие буквы, цифры и матзнаки: широко есть в шрифтах.
## Эзотерический набор из оригинала (MATRIX_GLYPHS) можно подставить, если
## загружен шрифт с этими символами.

const GLYPHS := "0123456789ΞΔΘΛΨΩΦΣΠΓλδθψωφσπξμηζ✦✧◆◈●∆∇"
const COLS := 26                             # плотный дождь (было 14)
const MINT := Color(0.49, 1.0, 0.72, 0.48)   # #7dffb8 @ .48 (как .matrix-col)
const FADE_FRAC := 0.22                       # нижняя доля высоты — плавно в прозрачность (перед столом)
const FADE_TOP := 0.12                        # верхняя доля высоты — плавно проявляется (из-под надписи)

var _font: Font
var _cols: Array = []       # [{x, fs, speed, y, glyphs:Array}]
var _refill_acc: float = 0.0
var _placed: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # pointer-events:none
	clip_contents = true                         # колонки не вылезают за окно
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_init_cols()

func _init_cols() -> void:
	_cols.clear()
	for i in COLS:
		var c := {
			"x": 0.015 + float(i) * (0.97 / float(COLS - 1)),
			"fs": float(randi_range(13, 22)),
			"speed": randf_range(55.0, 150.0),
			"y": 0.0,
			"glyphs": _rand_glyphs(randi_range(22, 34)),
		}
		_cols.append(c)

func _rand_glyphs(n: int) -> Array:
	var arr: Array = []
	for j in n:
		arr.append(GLYPHS[randi() % GLYPHS.length()])
	return arr

func _col_h(c: Dictionary) -> float:
	return float(c["glyphs"].size()) * float(c["fs"]) * 1.02

func _recycle(c: Dictionary) -> void:
	c["glyphs"] = _rand_glyphs(randi_range(22, 34))
	c["fs"] = float(randi_range(13, 22))
	c["speed"] = randf_range(55.0, 150.0)
	c["y"] = -_col_h(c) - randf_range(0.0, 120.0)

func _process(delta: float) -> void:
	if size.y <= 0.0:
		return
	if not _placed:                              # первая раскладка — размазать по высоте
		for c in _cols:
			c["y"] = randf_range(-_col_h(c), size.y)
		_placed = true
	for c in _cols:
		c["y"] += c["speed"] * delta
		if c["y"] > size.y:                      # верхний глиф ушёл вниз — на новый круг сверху
			_recycle(c)
	_refill_acc += delta
	if _refill_acc >= 0.16:                       # мерцание глифов (как refill каждые 160мс)
		_refill_acc = 0.0
		for c in _cols:
			c["glyphs"] = _rand_glyphs(c["glyphs"].size())
	queue_redraw()

func _draw() -> void:
	if _font == null:
		return
	var fade_top: float = size.y * (1.0 - FADE_FRAC)   # ниже этой линии глифы тают в прозрачность (перед столом)
	var fade_in: float = size.y * FADE_TOP             # выше этой линии глифы плавно проявляются (у надписи)
	for c in _cols:
		var x: float = c["x"] * size.x
		var fs: int = int(c["fs"])
		var line_h: float = float(fs) * 1.02
		var g: Array = c["glyphs"]
		for j in g.size():
			var gy: float = c["y"] + float(j) * line_h
			if gy < -line_h or gy > size.y + line_h:
				continue
			# ведущий глиф ярче (голова «капли»)
			var col: Color = Color(0.8, 1.0, 0.9, 0.72) if j == g.size() - 1 else MINT
			if gy > fade_top:                          # плавное затухание к низу (не лезет на стол/ползунки)
				col.a *= clampf(1.0 - (gy - fade_top) / (size.y - fade_top), 0.0, 1.0)
			elif gy < fade_in:                         # плавное появление сверху (из-под надписи фазы)
				col.a *= clampf(gy / fade_in, 0.0, 1.0)
			draw_string(_font, Vector2(x, gy), g[j], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
