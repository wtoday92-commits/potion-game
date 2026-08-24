extends Control
class_name MosaicGame
## Миниигра Маркетолога «мозаика»: картинка (арт космо-бара) разрезана на n×n плиток
## и перемешана. Тап по двум плиткам — меняет их местами; собери картинку. Баффа нет
## (просто возня-пауза). УР.4: одной детали НЕ ХВАТАЕТ (тёмная дырка) — собрать можно
## только остальное. Кнопка «Готово» завершает в любой момент.

signal finished(ok: bool, accuracy: float)

const PICS := [
	"res://assets/market/puz_barmen.png", "res://assets/market/puz_catlady.png",
	"res://assets/market/puz_dj.png", "res://assets/market/puz_chef.png",
	"res://assets/market/puz_tentacloid.png", "res://assets/market/puz_gurman.png",
	"res://assets/market/puz_twofaced.png", "res://assets/market/puz_supernova.png",
]

var level: int = 1
var n: int = 3
var _pic: Texture2D
var _atlas: Array = []          # AtlasTexture по индексу исходной клетки
var _state: Array = []          # _state[pos] = индекс исходной клетки
var _tiles: Array = []          # Button по позиции
var _texs: Array = []           # TextureRect по позиции
var _missing: int = -1          # УР.4: индекс отсутствующей детали
var _sel: int = -1
var _timer: Label
var _prompt: Label
var _submit: Button
var _frame: Panel
var _solved: bool = false

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
	n = {1: 3, 2: 3, 3: 4, 4: 4}.get(lvl, 3)
	_pic = load(PICS[randi() % PICS.size()])
	var cs: int = int(_pic.get_width()) / n
	for s in n * n:
		var at := AtlasTexture.new()
		at.atlas = _pic
		at.region = Rect2((s % n) * cs, (s / n) * cs, cs, cs)
		_atlas.append(at)
	if lvl == 4:
		_missing = randi() % (n * n)
	# перемешать (не собранной)
	_state = range(n * n)
	for _try in 20:
		_state.shuffle()
		var same := true
		for i in _state.size():
			if _state[i] != i:
				same = false; break
		if not same:
			break
	_build_ui()

func _build_ui() -> void:
	_timer = _mk_label(22, Color(0.7, 0.85, 1.0))
	_timer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer.offset_top = 8.0; _timer.offset_bottom = 34.0
	add_child(_timer)

	_prompt = _mk_label(22, Color(0.95, 0.98, 1.0))
	_prompt.text = "Соберите картинку (меняйте плитки местами)"
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_top = 44.0; _prompt.offset_bottom = 80.0
	add_child(_prompt)

	for pos in n * n:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.pressed.connect(_on_tile.bind(pos))
		add_child(b)
		_tiles.append(b)
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(tr)
		_texs.append(tr)
		_refresh_tile(pos)

	_frame = Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.set_border_width_all(5)
	fsb.border_color = Color(1.0, 0.95, 0.4, 0.95)
	_frame.add_theme_stylebox_override("panel", fsb)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	_submit = Button.new()
	_submit.text = "Готово"
	_submit.focus_mode = Control.FOCUS_NONE
	_submit.add_theme_font_size_override("font_size", UI.FS_L)
	_submit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_submit.offset_top = -56.0; _submit.offset_bottom = -10.0
	_submit.offset_left = 40.0; _submit.offset_right = -40.0
	_submit.pressed.connect(_finish)
	add_child(_submit)

func _mk_label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l

func _refresh_tile(pos: int) -> void:
	var src: int = int(_state[pos])
	var tr: TextureRect = _texs[pos]
	if level == 4 and src == _missing:
		tr.texture = null                       # отсутствующая деталь — дырка
	else:
		tr.texture = _atlas[src]

func _grid_area() -> Rect2:
	var top: float = 92.0
	var bot: float = 78.0
	var avail: float = maxf(40.0, size.y - top - bot)
	var side: float = minf(size.x - 20.0, avail)
	return Rect2((size.x - side) * 0.5, top + (avail - side) * 0.5, side, side)

func _layout() -> void:
	var a := _grid_area()
	var cw: float = a.size.x / float(n)
	var ch: float = a.size.y / float(n)
	for pos in _tiles.size():
		var b: Button = _tiles[pos]
		b.position = a.position + Vector2((pos % n) * cw, (pos / n) * ch)
		b.size = Vector2(cw, ch)
	if _frame != null and _sel >= 0:
		_frame.position = a.position + Vector2((_sel % n) * cw, (_sel / n) * ch)
		_frame.size = Vector2(cw, ch)

func _process(_delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	if not size.is_equal_approx(vp):
		size = vp
	_layout()

func _on_tile(pos: int) -> void:
	if _solved:
		return
	if level == 4 and int(_state[pos]) == _missing:
		return                                  # дырку не двигаем
	if _sel < 0:
		_sel = pos
		_frame.visible = true
		_layout()
		Sfx.play("uiClick")
	elif _sel == pos:
		_sel = -1
		_frame.visible = false
	else:
		var t = _state[_sel]; _state[_sel] = _state[pos]; _state[pos] = t
		_refresh_tile(_sel); _refresh_tile(pos)
		_sel = -1
		_frame.visible = false
		Sfx.play("blobSnap")
		_check_solved()

func _check_solved() -> void:
	for i in _state.size():
		if int(_state[i]) != i:
			return
	_solved = true
	if _prompt != null:
		_prompt.text = "Готово!"
	get_tree().create_timer(0.5).timeout.connect(_finish)

func _finish() -> void:
	if not is_inside_tree():
		return
	finished.emit(true, 1.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.10, 1.0))
	var a := _grid_area()
	# тёмные ячейки-подложки + сетка
	draw_rect(a, Color(0.10, 0.11, 0.14, 1.0))
	var cw: float = a.size.x / float(n)
	var ch: float = a.size.y / float(n)
	var line := Color(0, 0, 0, 0.55)
	for k in range(n + 1):
		draw_line(a.position + Vector2(k * cw, 0), a.position + Vector2(k * cw, a.size.y), line, 2.0)
		draw_line(a.position + Vector2(0, k * ch), a.position + Vector2(a.size.x, k * ch), line, 2.0)
	draw_rect(a, Color(1, 1, 1, 0.7), false, 2.0)
