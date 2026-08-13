extends Control
class_name EngTrack
## Трек Инженера навигатора: цель показана ЗОНАМИ, по треку синусоидой бегает
## указатель (медленно у краёв, быстро в центре). «СТОП» фиксирует значение =
## позиция указателя. Порт eng* (без фазы показа — цель в зонах). Пишет во
## внешний TouchSlider через сигнал fixed(value). Оценка — обычная (по близости),
## красная зона-ловушка УР.4 — TODO.

signal fixed(value: float)

const PAD := 22.0
const BAR_W := 30.0
const ZONE_GREEN := 0.15    # полуширина зелёной зоны (доля трека)
const ZONE_CORE := 0.06     # полуширина ядра («в яблочко»)

var min_v: float = 0.0
var max_v: float = 100.0
var step: float = 1.0
var target_frac: float = 0.5
var period: float = 1.9
var _phase: float = 0.0
var _frac: float = 0.5
var _stopped: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase = randf() * TAU
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(84, 300)

func setup(mn: float, mx: float, st: float, target_val: float, per: float) -> void:
	min_v = mn; max_v = mx; step = st; period = per
	target_frac = clampf((target_val - mn) / maxf(0.0001, mx - mn), 0.0, 1.0)

func _process(delta: float) -> void:
	if _stopped:
		return
	_phase += TAU * delta / maxf(0.1, period)
	_frac = 0.5 + 0.5 * sin(_phase)
	queue_redraw()

func fix() -> void:
	if _stopped:
		return
	_stopped = true
	var v: float = min_v + _frac * (max_v - min_v)
	if step > 0.0:
		v = min_v + roundf((v - min_v) / step) * step
	v = clampf(v, min_v, max_v)
	queue_redraw()
	fixed.emit(v)

func _y(f: float) -> float:
	var top: float = PAD
	var bot: float = size.y - PAD
	return bot - clampf(f, 0.0, 1.0) * (bot - top)

func _band(f_lo: float, f_hi: float, cx: float, col: Color) -> void:
	var y0: float = _y(f_hi)
	var y1: float = _y(f_lo)
	draw_rect(Rect2(cx - BAR_W * 0.5, y0, BAR_W, y1 - y0), col)

func _draw() -> void:
	var cx: float = size.x * 0.5
	# фон-трек
	_band(0.0, 1.0, cx, Color(0.12, 0.13, 0.18))
	# зоны вокруг цели: зелёная (шире) + ядро (яблочко)
	_band(target_frac - ZONE_GREEN, target_frac + ZONE_GREEN, cx, Color(0.45, 0.85, 0.35, 0.55))
	_band(target_frac - ZONE_CORE, target_frac + ZONE_CORE, cx, Color(0.25, 0.7, 1.0, 0.85))
	# указатель — треугольник справа от трека
	var py: float = _y(_frac)
	var col: Color = Color(0.55, 0.6, 0.7) if _stopped else Color(0.95, 0.82, 0.5)
	var x: float = cx + BAR_W * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 26, py - 12), Vector2(x + 26, py + 12), Vector2(x + 4, py),
	]), col)
