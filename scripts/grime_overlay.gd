extends Control
class_name GrimeOverlay
## «Грязь» на стекле витрины (Уборщик Пятого Дока). Процедурное реалистичное пятно
## (grime.gdshader) СТАТИЧНО поверх окна — неровный лопастной блоб, не по форме банки
## и не качается с ней. Палец-«губка» стирает грязь по маске (сетка COLS×ROWS).
## clean_fraction() — доля отмытого (по ячейкам пятна), идёт в score_bonus.

const GrimeShader := preload("res://shaders/grime.gdshader")
const COLS := 44
const ROWS := 64
# Дозагрязняемость (УР.4): периодически снова «запотевает» — докидываем бляшки
# грязи на случайные места, приходится перечищать (порт l4JanitorRefogSome).
const REFOG_EVERY := 2.4            # период дозагрязнения, сек
const REFOG_BLOTCHES := 4           # сколько бляшек за тик
const REFOG_R := 66.0              # радиус бляшки (пиксели)

var sponge_r: float = 76.0          # радиус губки (пиксели)
var _last_p: Vector2 = Vector2.INF  # прошлая точка протирки (для непрерывного следа)
var refog_on: bool = false          # УР.4: экран снова пачкается со временем
var _refog_t: float = 0.0

var _dirty: Array = []              # ROWS*COLS bool: true = грязно
var _in_blob: Array = []            # ROWS*COLS bool: ячейка внутри пятна (форма грязи)
var _blob_seed: float = 0.0         # разброс лопастей кромки пятна
var _rect: ColorRect                # рисует шейдер грязи
var _mat: ShaderMaterial
var _mask_img: Image                # L8 COLS×ROWS: 255 грязно → 0 отмыто
var _mask_tex: ImageTexture

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# размер выставляет JanitorMech через fit_window() — грязь только на «стекле окна»
	# (сверху до линии стола), а не на всю высоту jar_stage (иначе пятно уезжает вниз)
	_mat = ShaderMaterial.new()
	_mat.shader = GrimeShader

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)

	_mask_img = Image.create(COLS, ROWS, false, Image.FORMAT_L8)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	_mat.set_shader_parameter("mask_tex", _mask_tex)
	reset()

# Занять «стекло окна»: от верха сцены до линии стола, во всю ширину.
func fit_window(w: float, h: float) -> void:
	position = Vector2.ZERO
	size = Vector2(maxf(w, 1.0), maxf(h, 1.0))

# Ячейка внутри пятна грязи: эллипс с лопастями (низкочастотный синус по углу) —
# кромка неровная, не прямоугольник и не ровный овал.
func _cell_in_blob(c: int, r: int) -> bool:
	var dx: float = (float(c) + 0.5) / float(COLS) - 0.5
	var dy: float = ((float(r) + 0.5) / float(ROWS) - 0.5) * 0.8
	var rad: float = sqrt(dx * dx + dy * dy)
	var ang: float = atan2(dy, dx)
	var r_edge: float = 0.47 + 0.07 * sin(ang * 3.0 + _blob_seed) + 0.04 * sin(ang * 7.0 + _blob_seed * 2.3)
	return rad < r_edge

func reset() -> void:
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_blob_seed = randf() * TAU
	_refog_t = 0.0
	_dirty.clear()
	_in_blob.clear()
	for r in ROWS:
		for c in COLS:
			var on: bool = _cell_in_blob(c, r)
			_in_blob.append(on)
			_dirty.append(on)
			_mask_img.set_pixel(c, r, Color(1, 1, 1) if on else Color(0, 0, 0))
	_mask_tex.update(_mask_img)

# УР.4: раз в REFOG_EVERY секунд снова пачкаем несколько случайных мест.
func _process(delta: float) -> void:
	if not refog_on:
		return
	_refog_t += delta
	if _refog_t >= REFOG_EVERY:
		_refog_t = 0.0
		_refog_some()

func _refog_some() -> void:
	var cs := _cell_size()
	if cs.x <= 0.0 or cs.y <= 0.0:
		return
	var changed := false
	for _b in REFOG_BLOTCHES:
		# центр бляшки — в пределах пятна (~центр окна), чтобы грязь появлялась на виду
		var blob := Vector2(size.x * randf_range(0.2, 0.8), size.y * randf_range(0.15, 0.85))
		for r in ROWS:
			for c in COLS:
				var i: int = r * COLS + c
				if _dirty[i] or not _in_blob[i]:
					continue
				var center := Vector2((float(c) + 0.5) * cs.x, (float(r) + 0.5) * cs.y)
				if center.distance_to(blob) <= REFOG_R:
					_dirty[i] = true
					_mask_img.set_pixel(c, r, Color(1, 1, 1))
					changed = true
	if changed:
		_mask_tex.update(_mask_img)

func clean_fraction() -> float:
	var total := 0
	var cleaned := 0
	for i in _dirty.size():
		if _in_blob[i]:                 # считаем только ячейки самого пятна
			total += 1
			if not _dirty[i]:
				cleaned += 1
	if total == 0:
		return 1.0
	return float(cleaned) / float(total)

func _cell_size() -> Vector2:
	return Vector2(size.x / float(COLS), size.y / float(ROWS))

# Стереть кружок в точке p. Перебираем только ячейки в габаритах кружка —
# полный обход 44×64 на каждый шаг следа был бы слишком дорогим.
func _wipe_dot(p: Vector2, cs: Vector2) -> bool:
	var c0: int = maxi(0, int(floorf((p.x - sponge_r) / cs.x)))
	var c1: int = mini(COLS - 1, int(ceilf((p.x + sponge_r) / cs.x)))
	var r0: int = maxi(0, int(floorf((p.y - sponge_r) / cs.y)))
	var r1: int = mini(ROWS - 1, int(ceilf((p.y + sponge_r) / cs.y)))
	var changed := false
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var i: int = r * COLS + c
			if not _dirty[i]:
				continue
			var center := Vector2((float(c) + 0.5) * cs.x, (float(r) + 0.5) * cs.y)
			if center.distance_to(p) <= sponge_r:
				_dirty[i] = false
				_mask_img.set_pixel(c, r, Color(0, 0, 0))
				changed = true
	return changed

# Протирка ОТРЕЗКОМ от прошлой точки к текущей: палец между кадрами проходит
# десятки пикселей, и стирание точками оставляло дырявый пунктир — казалось,
# что губка мелкая и тормозит.
func _wipe_to(p: Vector2) -> void:
	var cs := _cell_size()
	if cs.x <= 0.0 or cs.y <= 0.0:
		return
	var changed: bool = _wipe_dot(p, cs)
	if _last_p.x != INF:
		var d: float = _last_p.distance_to(p)
		var steps: int = mini(24, int(d / maxf(sponge_r * 0.45, 1.0)))
		for s in range(1, steps + 1):
			if _wipe_dot(_last_p.lerp(p, float(s) / float(steps + 1)), cs):
				changed = true
	_last_p = p
	if changed:
		_mask_tex.update(_mask_img)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_last_p = Vector2.INF        # новый мазок — след начинается заново
			_wipe_to(event.position)
		else:
			_last_p = Vector2.INF
		accept_event()
	elif event is InputEventScreenDrag:
		_wipe_to(event.position)
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_wipe_to(event.position)
		accept_event()
