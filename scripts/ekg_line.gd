extends Control
class_name EkgLine
## Линия сердцебиения (ЭКГ) поверх банки — Аптекарь Мо на УР.4. Бежит по горизонтали,
## учащается по мере ухудшения «состояния пациента» (set_rate). Рисуется кодом.

var rate: float = 1.0     # ударов/сек-фактор (1 = спокойно, выше = чаще)
var _phase: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_rate(r: float) -> void:
	rate = maxf(0.2, r)

func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * rate * 0.5, 1.0)
	queue_redraw()

# один «удар» на доле u (0..1): острый пик вверх с провалами по бокам (QRS)
func _wave(u: float) -> float:
	var d: float = u - 0.5
	if absf(d) < 0.02:
		return 1.0 - absf(d) / 0.02
	if absf(d) < 0.06:
		return -0.22 * (1.0 - (absf(d) - 0.02) / 0.04)
	return 0.0

func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var y0: float = size.y * 0.5
	var amp: float = size.y * 0.11
	var col := Color(1.0, 0.28, 0.34, 0.7)
	var pts := PackedVector2Array()
	var n: int = 140
	var beats: float = 4.0        # сколько ударов помещается по ширине
	for i in n + 1:
		var f: float = float(i) / float(n)
		var x: float = size.x * f
		var u: float = fposmod(f * beats - _phase * beats, 1.0)
		pts.append(Vector2(x, y0 - _wave(u) * amp))
	draw_polyline(pts, col, 2.5, true)
