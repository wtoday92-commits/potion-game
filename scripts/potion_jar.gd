extends Control
## Банка = нарисованная бутыль (bottle.png) + живая жидкость/сгустки ВНУТРИ неё
## (liquid.gdshader, клип по маске интерьера). «Объём» масштабирует всю бутыль
## (сосуд всегда почти полон). Текстуры грузим через load() — если Godot ещё не
## импортировал их, банка просто пустая до импорта (без падения).
##
## Живость: sway-нода мягко покачивается маятником у основания, а жидкость
## внутри плещется по инерции (пружина-демпфер slosh, ведомая угловой скоростью
## банки). Форма сгустков и рябь анимируются в шейдере по TIME.

const LiquidShader := preload("res://shaders/liquid.gdshader")

# Границы интерьера стекла в UV (замерены по bottle_interior.png).
const I_TOP := 0.150
const I_BOT := 0.953
const I_LEFT := 0.240
const I_RIGHT := 0.746
const FILL := 0.78     # уровень жидкости (ниже горлышка — видно, как плещется)

var hue: float = 120.0
var saturation: float = 0.72   # насыщенность жидкости (накал); 0.72 — старый вид
var vsize: float = 0.6
var height_frac: float = -1.0  # отдельная высота (Дитя Сверхновой); <0 = масштаб равномерный
var count: int = 5
var count2: int = 0        # 2-й счётчик (Двуликая): >0 → банка делится на 2 половины

# --- физика летающих сгустков (Бармен плазма-бара) ---
var _phys_on: bool = false
var _phys_speed: float = 0.0        # 0..1 (доля от ползунка «Скорость»)
var _liq_top: float = 0.0
var _phys_pos: Array = []           # Vector2 — текущие позиции (UV)
var _phys_vel: Array = []           # Vector2 — направления (единичные)
var _phys_r: Array = []             # радиусы
var _phys_w: Array = []             # фазы для шейдера
var bsize: float = 0.5
var pot_seed: int = 1

var content: Control     # масштаб «объёма» (пивот по центру)
var sway: Control        # покачивание банки (пивот у основания)
var liquid: ColorRect
var bottle: TextureRect
var mat: ShaderMaterial

# --- состояние анимации ---
var _t: float = 0.0
var _jar_ang: float = 0.0        # текущий угол банки
var _jar_ang_prev: float = 0.0
var _slosh: float = 0.0          # смещение поверхности жидкости
var _slosh_vel: float = 0.0

func _ready() -> void:
	content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	sway = Control.new()
	sway.set_anchors_preset(Control.PRESET_FULL_RECT)
	sway.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(sway)

	liquid = ColorRect.new()
	liquid.set_anchors_preset(Control.PRESET_FULL_RECT)
	liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = LiquidShader
	var mask_tex := load("res://assets/bottle/bottle_interior.png") as Texture2D
	if mask_tex:
		mat.set_shader_parameter("mask", mask_tex)
	liquid.material = mat
	sway.add_child(liquid)

	bottle = TextureRect.new()
	bottle.texture = load("res://assets/bottle/bottle.png") as Texture2D
	bottle.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottle.stretch_mode = TextureRect.STRETCH_SCALE
	bottle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sway.add_child(bottle)

	# небольшой сдвиг фазы, чтобы разные банки качались вразнобой
	_t = float(pot_seed) * 0.7

	resized.connect(_apply)
	_apply()

func set_potion(h: float, v: float, c: int, b: float, s: int, sat: float = 0.72, height: float = -1.0, c2: int = 0) -> void:
	hue = h
	saturation = clampf(sat, 0.0, 1.0)
	vsize = clampf(v, 0.0, 1.0)
	height_frac = height     # <0 → равномерный масштаб по vsize
	count2 = max(0, c2)      # >0 → две половины со своими счётчиками
	count = max(0, c)
	bsize = clampf(b, 0.0, 1.0)
	pot_seed = s
	_t = float(pot_seed) * 0.7
	_apply()

# Бармен: включить/выключить физику полёта (пере-инициализирует позиции).
func set_physics(on: bool) -> void:
	_phys_on = on
	_apply()

# Бармен: обновить скорость полёта без сброса позиций (читается каждый кадр).
func set_physics_speed(frac: float) -> void:
	_phys_speed = clampf(frac, 0.0, 1.0)

func _process(delta: float) -> void:
	if sway == null or mat == null:
		return
	_t += delta

	# Плавное покачивание банки: сумма двух синусов = «живой», непериодичный вид.
	_jar_ang_prev = _jar_ang
	_jar_ang = 0.035 * sin(_t * 0.9) + 0.016 * sin(_t * 1.7 + 1.3)
	sway.rotation = _jar_ang

	var ang_vel: float = (_jar_ang - _jar_ang_prev) / max(0.0001, delta)

	# Плескание жидкости — пружина-демпфер, которую «толкает» движение банки.
	# Жидкость стремится остаться горизонтальной => целевой наклон = -_jar_ang.
	var target: float = -_jar_ang
	var k: float = 60.0      # жёсткость (частота колебаний)
	var c_damp: float = 7.0  # затухание
	var force: float = -3.5 * ang_vel
	_slosh_vel += (k * (target - _slosh) - c_damp * _slosh_vel + force) * delta
	_slosh += _slosh_vel * delta

	mat.set_shader_parameter("tilt", _slosh)
	mat.set_shader_parameter("slosh", clampf(absf(_slosh_vel) * 0.25, 0.0, 1.0))

	# Бармен: сгустки летают и отскакивают от стенок; скорость — с ползунка
	if _phys_on and not _phys_pos.is_empty():
		var ar2: float = size.x / size.y
		var sp: float = (0.05 + _phys_speed * 0.28) * delta   # UV/сек
		var arr := PackedVector4Array()
		for i in _phys_pos.size():
			var p: Vector2 = _phys_pos[i]
			var v: Vector2 = _phys_vel[i]
			var r: float = _phys_r[i]
			var mx: float = r / max(0.0001, ar2)
			p += v * sp
			if p.x < I_LEFT + mx: p.x = I_LEFT + mx; v.x = absf(v.x)
			if p.x > I_RIGHT - mx: p.x = I_RIGHT - mx; v.x = -absf(v.x)
			if p.y < _liq_top + r: p.y = _liq_top + r; v.y = absf(v.y)
			if p.y > I_BOT - r: p.y = I_BOT - r; v.y = -absf(v.y)
			_phys_pos[i] = p
			_phys_vel[i] = v
			arr.append(Vector4(p.x, p.y, r, _phys_w[i]))
		while arr.size() < 12:
			arr.append(Vector4(0.0, 0.0, 0.0, 0.0))
		mat.set_shader_parameter("blobs", arr)
		mat.set_shader_parameter("blob_n", _phys_pos.size())

func _apply() -> void:
	if mat == null or content == null or size.x <= 0.0 or size.y <= 0.0:
		return
	# «Объём» масштабирует бутыль ОТ ОСНОВАНИЯ вверх (банка стоит на плите,
	# растёт/убывает по высоте — так плита работает точкой отсчёта размера).
	var sc: float = lerpf(0.62, 1.0, vsize)
	var h_sc: float = sc if height_frac < 0.0 else lerpf(0.62, 1.0, clampf(height_frac, 0.0, 1.0))
	var base := Vector2(size.x * 0.5, size.y * 0.92)
	content.pivot_offset = base
	content.scale = Vector2(sc, h_sc)   # ширина = «объём», высота = size2 (Сверхнова)
	# покачивание — вокруг того же основания (как стоящий сосуд)
	sway.pivot_offset = base

	var ar: float = size.x / size.y
	mat.set_shader_parameter("liquid_col", Color.from_hsv(fposmod(hue, 360.0) / 360.0, saturation, 0.95))
	mat.set_shader_parameter("fill", FILL)
	mat.set_shader_parameter("interior_top", I_TOP)
	mat.set_shader_parameter("interior_bot", I_BOT)
	mat.set_shader_parameter("interior_left", I_LEFT)
	mat.set_shader_parameter("interior_right", I_RIGHT)
	mat.set_shader_parameter("aspect", ar)

	# сгустки в зоне жидкости (в UV), каждая своего размера и с фазой w
	var liq_top: float = I_BOT - (I_BOT - I_TOP) * FILL
	_liq_top = liq_top
	var rng := RandomNumberGenerator.new()
	rng.seed = pot_seed
	var arr := PackedVector4Array()
	var n_real: int = 0
	var placed: Array = []          # уже поставленные капли [Vector3(x, y, r)]
	# группы капель: (сколько, x_min, x_max). При count2>0 — две половины банки.
	var cxm: float = (I_LEFT + I_RIGHT) * 0.5
	var groups: Array = []
	if count2 > 0:
		groups = [[mini(count, 7), cxm + 0.015, I_RIGHT], [mini(count2, 7), I_LEFT, cxm - 0.015]]
	else:
		groups = [[count, I_LEFT, I_RIGHT]]
	for grp in groups:
		var k: int = grp[0]
		var gx0: float = grp[1]
		var gx1: float = grp[2]
		for i in k:
			if n_real >= 12:
				break
			# размер каждой капли слегка разный
			var r_uv: float = lerpf(0.02, 0.055, bsize) * rng.randf_range(0.72, 1.28)
			var mx: float = r_uv / max(0.0001, ar)   # x сжат аспектом
			# запас под покачивание/дрейф капель + границы группы (половины)
			var minx: float = maxf(I_LEFT + mx + 0.02, gx0 + mx)
			var maxx: float = minf(I_RIGHT - mx - 0.02, gx1 - mx)
			var miny: float = liq_top + r_uv + 0.03
			var maxy: float = I_BOT - r_uv - 0.02
			if maxx <= minx or maxy <= miny:
				continue
			# rejection sampling: позиция подальше от уже стоящих капель
			var bx: float = 0.0
			var by: float = 0.0
			var best_gap: float = -1.0
			for _attempt in 28:
				var cx: float = minx + rng.randf() * (maxx - minx)
				var cy: float = miny + rng.randf() * (maxy - miny)
				var gap: float = 1.0
				for pb in placed:
					var dx: float = (cx - pb.x) * ar        # аспект-коррекция как в шейдере
					var dy: float = cy - pb.y
					var need: float = (r_uv + pb.z) * 1.12 + 0.02
					gap = min(gap, sqrt(dx * dx + dy * dy) - need)
				if gap > best_gap:
					best_gap = gap
					bx = cx
					by = cy
				if gap >= 0.0:
					break                                   # нашли непересекающуюся — берём
			placed.append(Vector3(bx, by, r_uv))
			arr.append(Vector4(bx, by, r_uv, rng.randf()))
			n_real += 1
	while arr.size() < 12:
		arr.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("blobs", arr)
	mat.set_shader_parameter("blob_n", n_real)
	# физика: запоминаем стартовые позиции и раздаём случайные направления
	if _phys_on:
		_phys_pos.clear(); _phys_vel.clear(); _phys_r.clear(); _phys_w.clear()
		for i in n_real:
			var b: Vector4 = arr[i]
			_phys_pos.append(Vector2(b.x, b.y))
			var a: float = randf() * TAU
			_phys_vel.append(Vector2(cos(a), sin(a)))
			_phys_r.append(b.z)
			_phys_w.append(b.w)
