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
const BottleBlurShader := preload("res://shaders/jar_blur.gdshader")
const ScreenBlurShader := preload("res://shaders/jar_screenblur.gdshader")

# Набор посуды космо-бара. У каждого стакана свой арт и МАСКА ПО ФОРМЕ (жидкость
# клипается точно по чаше — ножки/основания в маску не входят), плюс UV-границы
# зоны жидкости, замеренные по этой маске.
const GLASSES := [
	{"id": "hi",     "tex": "res://assets/bottle/glass_hi.png",    "mask": "res://assets/bottle/glass_hi_int.png",
		"top": 0.0745, "bot": 0.8406, "left": 0.1526, "right": 0.8295},
	{"id": "curvy",  "tex": "res://assets/bottle/glass_curvy.png", "mask": "res://assets/bottle/glass_curvy_int.png",
		"top": 0.0406, "bot": 0.6953, "left": 0.1412, "right": 0.8263},
]
# Границы интерьера в UV — обновляются в set_glass().
var I_TOP := 0.0745
var I_BOT := 0.8406
var I_LEFT := 0.1526
var I_RIGHT := 0.8295
var glass_idx: int = -1
const FILL := 0.78     # уровень жидкости (ниже горлышка — видно, как плещется)
const MAX_BLOBS := 18  # потолок числа сгустков (должен совпадать с liquid.gdshader)

var hue: float = 120.0
var hue2: float = -1.0         # 2-й спектр (Двуликая, градиент); <0 = одноцветная жидкость
var saturation: float = 0.72   # насыщенность жидкости (накал); 0.72 — старый вид
var vsize: float = 0.6
var height_frac: float = -1.0  # отдельная высота (Дитя Сверхновой); <0 = масштаб равномерный
var count: int = 5
var count2: int = 0        # 2-й счётчик (Двуликая): >0 → банка делится на 2 половины
var fill_level: float = -1.0   # уровень жидкости (Пит); <0 = константа FILL
var blur_amt: float = 0.0      # «пьяное» размытие 0..1 (Пит, градус)
var mono_on: bool = false      # «Выцветший мир» (дебафф Ир): ч-б + постоянный блюр
const MONO_BLUR := 0.55        # базовый блюр банки в режиме «Выцветший мир»
var desat: float = 1.0         # «состояние пациента» (Аптекарь Мо): 1 цвет → 0.25 приглушённый
var tilt_deg: float = 0.0      # наклон сосуда (Дитя Сверхновой, УР.4)

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
var bottle_mat: ShaderMaterial
var blur_overlay: ColorRect
var blur_mat: ShaderMaterial

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
	var mask_tex := load("res://assets/bottle/glass_hi_int.png") as Texture2D
	if mask_tex:
		mat.set_shader_parameter("mask", mask_tex)
	liquid.material = mat
	sway.add_child(liquid)

	# слой настоящего размытия содержимого (Аптекарь Мо / градус Пита) — поверх
	# жидкости, но под стеклом; клипается маской интерьера (фон вокруг не трогает)
	blur_overlay = ColorRect.new()
	blur_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur_mat = ShaderMaterial.new()
	blur_mat.shader = ScreenBlurShader
	if mask_tex:
		blur_mat.set_shader_parameter("mask", mask_tex)
	blur_mat.set_shader_parameter("amount", 0.0)
	blur_overlay.material = blur_mat
	blur_overlay.visible = false          # включается только при блюре (Мо/Пит)
	sway.add_child(blur_overlay)

	bottle = TextureRect.new()
	bottle.texture = load("res://assets/bottle/glass_hi.png") as Texture2D
	bottle.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottle.stretch_mode = TextureRect.STRETCH_SCALE
	bottle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottle_mat = ShaderMaterial.new()          # box-размытие стекла (градус Пита)
	bottle_mat.shader = BottleBlurShader
	bottle.material = bottle_mat
	sway.add_child(bottle)

	# небольшой сдвиг фазы, чтобы разные банки качались вразнобой
	_t = float(pot_seed) * 0.7

	resized.connect(_apply)
	if glass_idx < 0:
		set_glass(0)
	_apply()

# Выбрать посуду из набора GLASSES: меняет арт, маску шейдера и UV-границы.
func set_glass(idx: int) -> void:
	var i: int = clampi(idx, 0, GLASSES.size() - 1)
	if i == glass_idx:
		return
	glass_idx = i
	var g: Dictionary = GLASSES[i]
	I_TOP = float(g["top"]); I_BOT = float(g["bot"])
	I_LEFT = float(g["left"]); I_RIGHT = float(g["right"])
	var tex := load(String(g["tex"])) as Texture2D
	if tex != null and bottle != null:
		bottle.texture = tex
	var msk := load(String(g["mask"])) as Texture2D
	if msk != null:
		if mat != null: mat.set_shader_parameter("mask", msk)
		if blur_mat != null: blur_mat.set_shader_parameter("mask", msk)
	_apply()

# Индекс посуды по id ("hi" — прямой стакан Векса).
static func glass_index(id: String) -> int:
	for i in GLASSES.size():
		if String(GLASSES[i]["id"]) == id:
			return i
	return 0

func set_potion(h: float, v: float, c: int, b: float, s: int, sat: float = 0.72, height: float = -1.0, c2: int = 0, fill: float = -1.0, h2: float = -1.0) -> void:
	hue = h
	hue2 = h2                # <0 → без градиента
	saturation = clampf(sat, 0.0, 1.0)
	vsize = clampf(v, 0.0, 1.0)
	height_frac = height     # <0 → равномерный масштаб по vsize
	count2 = max(0, c2)      # >0 → две половины со своими счётчиками
	fill_level = fill        # <0 → уровень по умолчанию (FILL)
	count = max(0, c)
	bsize = clampf(b, 0.0, 1.0)
	pot_seed = s
	_t = float(pot_seed) * 0.7
	_apply()

# Дитя Сверхновой (УР.4): наклон сосуда. Крутим content вокруг основания (пивот у
# дна) — банка кренится влево/вправо, но остаётся стоять на столе.
func set_tilt(deg: float) -> void:
	tilt_deg = deg
	if content != null:
		content.rotation = deg_to_rad(deg)

# Узел, что качается вместе с банкой (Навигатор Роя вешает сюда детали, чтобы они
# качались и «жили» внутри сосуда, а не висели статично поверх него).
func inner_holder() -> Control:
	return sway

# Бармен: включить/выключить физику полёта (пере-инициализирует позиции).
func set_physics(on: bool) -> void:
	_phys_on = on
	_apply()

# Бармен: обновить скорость полёта без сброса позиций (читается каждый кадр).
func set_physics_speed(frac: float) -> void:
	_phys_speed = clampf(frac, 0.0, 1.0)

# Пит: «пьяное» размытие жидкости и сгустков (0..1), обновляется каждый кадр.
func set_blur(amt: float) -> void:
	blur_amt = clampf(amt, 0.0, 1.0)
	_refresh_blur()

# Ир «Выцветший мир»: банка чёрно-белая + постоянно подмылена (сложнее оценить
# габариты на глаз). Обесцвечиваем жидкость через насыщенность 0 (_apply), а
# стекло — через grayscale-uniform шейдера бутыли.
func set_mono(on: bool) -> void:
	mono_on = on
	_refresh_gray()
	_refresh_blur()
	_apply()             # пересчёт liquid_col с насыщенностью 0/обычной

# Аптекарь Мо: «состояние пациента» — банка постепенно теряет цвет (m: 1→0.25).
# Лёгкое обновление (без пересчёта сгустков) — вызывается каждый кадр.
func set_desat(m: float) -> void:
	desat = clampf(m, 0.0, 1.0)
	_refresh_gray()
	_refresh_color()

# Обесцвечивание стекла: max(полный ч-б от Ир, частичное от Аптекаря).
func _refresh_gray() -> void:
	if bottle_mat != null:
		bottle_mat.set_shader_parameter("grayscale", clampf(maxf(1.0 if mono_on else 0.0, 1.0 - desat), 0.0, 1.0))

# Цвет/градиент/насыщенность жидкости в шейдере (без пересчёта сгустков).
func _refresh_color() -> void:
	if mat == null:
		return
	var sat_eff: float = (0.0 if mono_on else saturation) * desat   # Ир → серая; Аптекарь → приглушённая
	mat.set_shader_parameter("liquid_col", Color.from_hsv(fposmod(hue, 360.0) / 360.0, sat_eff, 0.95))
	var grad_on: float = 1.0 if hue2 >= 0.0 else 0.0
	var col2: Color = Color.from_hsv(fposmod(hue2, 360.0) / 360.0, sat_eff, 0.95) if hue2 >= 0.0 else Color.from_hsv(fposmod(hue, 360.0) / 360.0, sat_eff, 0.95)
	mat.set_shader_parameter("liquid_col2", col2)
	mat.set_shader_parameter("grad_on", grad_on)

# Эффективный блюр = max(градус Пита, базовый блюр «Выцветшего мира»).
func _refresh_blur() -> void:
	var eff: float = maxf(blur_amt, MONO_BLUR if mono_on else 0.0)
	if mat != null:
		mat.set_shader_parameter("blur", eff)
	if bottle_mat != null:
		bottle_mat.set_shader_parameter("amount", eff)   # мылим и само стекло
	if blur_mat != null:
		blur_mat.set_shader_parameter("amount", eff)     # настоящее размытие содержимого
	if blur_overlay != null:
		blur_overlay.visible = eff > 0.004               # без блюра слой выключен (нет backbuffer-copy)

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
		while arr.size() < MAX_BLOBS:
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
	var f: float = FILL if fill_level < 0.0 else clampf(fill_level, 0.05, 1.0)   # уровень жидкости (Пит)
	_refresh_color()   # цвет/градиент/насыщенность жидкости
	mat.set_shader_parameter("fill", f)
	mat.set_shader_parameter("interior_top", I_TOP)
	mat.set_shader_parameter("interior_bot", I_BOT)
	mat.set_shader_parameter("interior_left", I_LEFT)
	mat.set_shader_parameter("interior_right", I_RIGHT)
	mat.set_shader_parameter("aspect", ar)

	mat.set_shader_parameter("blur", clampf(blur_amt, 0.0, 1.0))
	# сгустки в зоне жидкости (в UV), каждая своего размера и с фазой w
	var liq_top: float = I_BOT - (I_BOT - I_TOP) * f
	_liq_top = liq_top
	# при низком уровне жидкости полоса тонкая — ограничиваем радиус капли, чтобы
	# они ВСЕГДА помещались (иначе rejection sampling их выкидывал → «исчезали»)
	var band: float = maxf(0.02, I_BOT - liq_top)
	var r_cap: float = maxf(0.014, band * 0.36)
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
	# размер сгустка привязан к ОБЪЁМУ банки: большая банка → крупнее сгустки (и min,
	# и max). Так в маленькой банке они не наползают друг на друга.
	var vol_f: float = lerpf(0.58, 1.0, vsize)
	for grp in groups:
		var k: int = grp[0]
		var gx0: float = grp[1]
		var gx1: float = grp[2]
		# адаптивный потолок радиуса: k сгустков должны уместиться в площадь группы
		# (иначе при многих/крупных сгустках в узкой банке они наползают)
		var grp_w: float = maxf(0.02, gx1 - gx0)
		var r_fit: float = sqrt(0.55 * grp_w * band * ar / (4.0 * float(maxi(1, k))))
		for i in k:
			if n_real >= MAX_BLOBS:
				break
			# базовый размер по «Размеру» × фактор объёма, но не больше, чем влезает
			var r_uv: float = minf(lerpf(0.032, 0.075, bsize) * vol_f, r_fit) * rng.randf_range(0.88, 1.12)
			r_uv = clampf(r_uv, 0.012, r_cap)
			var mx: float = r_uv / max(0.0001, ar)   # x сжат аспектом
			# запас под покачивание/дрейф капель + границы группы (половины)
			var minx: float = maxf(I_LEFT + mx + 0.015, gx0 + mx)
			var maxx: float = minf(I_RIGHT - mx - 0.015, gx1 - mx)
			var miny: float = liq_top + r_uv + 0.012
			var maxy: float = I_BOT - r_uv - 0.012
			if maxx <= minx:
				minx = (gx0 + gx1) * 0.5
				maxx = minx
			if maxy <= miny:
				miny = (liq_top + I_BOT) * 0.5
				maxy = miny
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
	while arr.size() < MAX_BLOBS:
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
