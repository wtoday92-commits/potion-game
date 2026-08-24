extends Control
class_name EngTrack
## Горизонтальный «калибратор» Инженера: по направляющей ходит каретка, СТОП её
## фиксирует — где встала, такое и значение. Цель показана зонами: широкая
## зелёная (годится) и узкое синее ядро (точно). На УР.4 добавляются красные
## зоны-ловушки: попал — по этой величине ноль.
##
## Оформление под барные стулья/мастерскую: стальная направляющая с заклёпками
## и насечкой, каретка — гайка с рукоятью.

signal fixed(value: float, hit_red: bool)

const PAD := 26.0            # поля слева/справа под торцы направляющей
const RAIL_H := 16.0         # толщина направляющей
const ZONE_H := 30.0         # высота цветных зон
const ZONE_GREEN := 0.26     # полуширина зелёной зоны (доля трека)
const ZONE_CORE := 0.085     # полуширина синего ядра
const RED_HALF := 0.05       # полуширина красной ловушки
const STOP_DELAY := 0.13     # каретка тормозит не мгновенно — так честнее ощущается

var min_v: float = 0.0
var max_v: float = 100.0
var step: float = 1.0
var target_frac: float = 0.5
var period: float = 1.9
var reds: Array = []         # центры красных зон (доли трека)
var active: bool = false     # каретка ходит только у активного трека
var hue_track: bool = false  # спектр — красим направляющую радугой

var _phase: float = 0.0
var _frac: float = 0.5
var _stopped: bool = false
var _stopping: float = -1.0  # обратный отсчёт до фиксации
var _hit_red: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase = -PI * 0.5          # старт от левого торца — трек явно «ещё не начат»
	_frac = 0.0
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(320, 58)

func setup(mn: float, mx: float, st: float, target_val: float, per: float, with_reds: bool) -> void:
	min_v = mn; max_v = mx; step = st; period = per
	target_frac = clampf((target_val - mn) / maxf(0.0001, mx - mn), 0.0, 1.0)
	reds = []
	if with_reds:
		_place_reds()
	queue_redraw()

# Две ловушки: одна вплотную к зелёной зоне (соблазн «чуть-чуть не долетел»),
# вторая — где угодно подальше от цели.
func _place_reds() -> void:
	var gap: float = ZONE_GREEN + RED_HALF + 0.015
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var near: float = target_frac + side * gap
	if near < RED_HALF or near > 1.0 - RED_HALF:
		near = target_frac - side * gap      # не влезла с этой стороны — ставим с другой
	near = clampf(near, RED_HALF, 1.0 - RED_HALF)
	reds.append(near)
	for _attempt in 24:
		var f: float = randf_range(RED_HALF, 1.0 - RED_HALF)
		if absf(f - target_frac) > ZONE_GREEN + RED_HALF + 0.04 and absf(f - near) > RED_HALF * 2.6:
			reds.append(f)
			return

func _process(delta: float) -> void:
	if _stopped:
		return
	if _stopping >= 0.0:
		_stopping -= delta
		if _stopping <= 0.0:
			_freeze()
			return
	elif not active:
		return
	_phase += TAU * delta / maxf(0.1, period)
	_frac = 0.5 + 0.5 * sin(_phase)
	queue_redraw()

# Запустить каретку (трек стал активным).
func arm() -> void:
	active = true
	set_process(true)

# Нажали СТОП: каретка идёт ещё STOP_DELAY и только потом встаёт.
func fix() -> void:
	if _stopped or _stopping >= 0.0:
		return
	_stopping = STOP_DELAY

func _freeze() -> void:
	_stopped = true
	_stopping = -1.0
	active = false
	for r in reds:
		if absf(_frac - float(r)) <= RED_HALF:
			_hit_red = true
			break
	var v: float = min_v + _frac * (max_v - min_v)
	if step > 0.0:
		v = min_v + roundf((v - min_v) / step) * step
	v = clampf(v, min_v, max_v)
	queue_redraw()
	fixed.emit(v, _hit_red)

func is_done() -> bool:
	return _stopped

# ---------- отрисовка ----------

func _x(f: float) -> float:
	return PAD + clampf(f, 0.0, 1.0) * maxf(1.0, size.x - PAD * 2.0)

func _zone(f_lo: float, f_hi: float, cy: float, h: float, col: Color) -> void:
	var x0: float = _x(f_lo)
	var x1: float = _x(f_hi)
	draw_rect(Rect2(x0, cy - h * 0.5, maxf(2.0, x1 - x0), h), col)

func _draw() -> void:
	var cy: float = size.y * 0.5
	var x0: float = _x(0.0)
	var x1: float = _x(1.0)
	var dim: float = 1.0 if (active or _stopped) else 0.45

	# --- направляющая: стальная полоса с фаской ---
	draw_rect(Rect2(x0 - 8.0, cy - RAIL_H * 0.5 - 3.0, (x1 - x0) + 16.0, RAIL_H + 6.0), Color(0.07, 0.08, 0.11, 0.95 * dim))
	if hue_track:
		var seg: int = 34
		for i in seg:
			var f0: float = float(i) / float(seg)
			var c := Color.from_hsv(f0, 0.72, 0.95)
			c.a = 0.85 * dim
			_zone(f0, f0 + 1.0 / float(seg) + 0.004, cy, RAIL_H, c)
	else:
		draw_rect(Rect2(x0, cy - RAIL_H * 0.5, x1 - x0, RAIL_H), Color(0.30, 0.33, 0.40, dim))
		draw_rect(Rect2(x0, cy - RAIL_H * 0.5, x1 - x0, 4.0), Color(0.52, 0.56, 0.66, dim))   # блик-фаска
	# насечка по направляющей
	for i in 21:
		var tx: float = _x(float(i) / 20.0)
		var th: float = 9.0 if i % 5 == 0 else 5.0
		draw_line(Vector2(tx, cy + RAIL_H * 0.5 + 2.0), Vector2(tx, cy + RAIL_H * 0.5 + 2.0 + th),
			Color(0.62, 0.66, 0.78, 0.65 * dim), 2.0)
	# заклёпки на торцах — как на ножках барных стульев
	for ex in [x0 - 8.0, x1 + 8.0]:
		draw_circle(Vector2(ex, cy), 9.0, Color(0.24, 0.26, 0.32, dim))
		draw_circle(Vector2(ex, cy), 5.5, Color(0.58, 0.62, 0.72, dim))
		draw_circle(Vector2(ex - 1.5, cy - 1.5), 2.0, Color(0.85, 0.88, 0.95, dim))

	# --- зоны цели ---
	_zone(target_frac - ZONE_GREEN, target_frac + ZONE_GREEN, cy, ZONE_H, Color(0.36, 0.82, 0.34, 0.42 * dim))
	_zone(target_frac - ZONE_CORE, target_frac + ZONE_CORE, cy, ZONE_H, Color(0.25, 0.70, 1.0, 0.80 * dim))
	for r in reds:
		var rc: float = float(r)
		_zone(rc - RED_HALF, rc + RED_HALF, cy, ZONE_H, Color(0.95, 0.20, 0.22, 0.70 * dim))
		# косая штриховка — «опасно», читается даже без цвета
		var rx0: float = _x(rc - RED_HALF)
		var rx1: float = _x(rc + RED_HALF)
		var hx: float = rx0
		while hx < rx1:
			draw_line(Vector2(hx, cy + ZONE_H * 0.5), Vector2(minf(hx + 7.0, rx1), cy - ZONE_H * 0.5),
				Color(0.15, 0.02, 0.03, 0.55 * dim), 2.0)
			hx += 7.0

	# --- каретка: гайка с рукоятью ---
	var px: float = _x(_frac)
	var body := Color(0.95, 0.82, 0.5)
	if _stopped:
		if _hit_red:
			body = Color(1.0, 0.42, 0.40)                                  # ловушка
		elif absf(_frac - target_frac) <= ZONE_GREEN:
			body = Color(0.62, 0.90, 0.68)                                 # попал в зону
		else:
			body = Color(0.66, 0.68, 0.76)                                 # мимо
	draw_line(Vector2(px, cy - ZONE_H * 0.5 - 6.0), Vector2(px, cy + ZONE_H * 0.5 + 6.0), Color(body, 0.9 * dim), 3.0)
	var hex := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.26
		hex.append(Vector2(px, cy) + Vector2(cos(a), sin(a)) * 13.0)
	draw_colored_polygon(hex, Color(body, dim))
	var outline := hex.duplicate(); outline.append(hex[0])
	draw_polyline(outline, Color(0.12, 0.12, 0.16, dim), 2.5, true)
	draw_circle(Vector2(px, cy), 4.5, Color(0.12, 0.12, 0.16, dim))
