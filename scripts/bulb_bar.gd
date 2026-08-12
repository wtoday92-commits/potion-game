extends Control
class_name BulbBar
## Ряд подвешенных барных лампочек вместо полоски таймера. Заполняются (зажигаются)
## на фазе «запомни», гаснут по одной с небольшим делэем на фазе «воссоздай».
## Лампы тёплые, слегка мерцают/потрескивают — бар, а не роскошный отель.
##
## Управление: set_fraction(0..1) — сколько ламп должно гореть. Загораются быстро,
## гаснут медленнее (остывание нити) + мерцание.

const COUNT := 14
const WARM := Color(1.0, 0.72, 0.32)      # тёплый ламповый свет
const GLASS_OFF := Color(0.16, 0.14, 0.13) # погашенное стекло

var _target: PackedFloat32Array
var _glow: PackedFloat32Array
var _seed: PackedFloat32Array
var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 58)
	_target.resize(COUNT)
	_glow.resize(COUNT)
	_seed.resize(COUNT)
	for i in COUNT:
		_seed[i] = randf() * TAU

# f — доля горящих ламп (0..1). Лампы слева направо.
func set_fraction(f: float) -> void:
	var lit: float = clampf(f, 0.0, 1.0) * float(COUNT)
	for i in COUNT:
		_target[i] = 1.0 if float(i) < lit else 0.0

func _process(delta: float) -> void:
	_t += delta
	for i in COUNT:
		var tgt: float = _target[i]
		# зажигается быстро, гаснет медленно (делэй остывания)
		var sp: float = 9.0 if tgt > _glow[i] else 3.0
		_glow[i] = move_toward(_glow[i], tgt, sp * delta)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var step: float = w / float(COUNT)
	var r: float = clampf(step * 0.28, 6.0, 16.0)
	var wire_y: float = 6.0
	var bulb_y: float = wire_y + r + 8.0

	# провод-гирлянда поверху
	draw_line(Vector2(0.0, wire_y), Vector2(w, wire_y), Color(0.10, 0.09, 0.08), 2.0)

	for i in COUNT:
		var cx: float = step * (float(i) + 0.5)
		var g: float = _glow[i]

		# мерцание/потрескивание: базовый дребезг + сильнее в момент угасания
		var lit: float = g
		if g > 0.02:
			var jitter: float = 0.06 * sin(_t * 12.0 + _seed[i] * 3.0)
			var dying: float = 0.35 * clampf(1.0 - absf(g - 0.4) / 0.4, 0.0, 1.0)
			jitter -= dying * maxf(0.0, sin(_t * 23.0 + _seed[i] * 7.0))
			lit = clampf(g + jitter, 0.0, 1.0)

		# провод к патрону + патрон
		draw_line(Vector2(cx, wire_y), Vector2(cx, bulb_y - r), Color(0.12, 0.11, 0.10), 2.0)
		draw_circle(Vector2(cx, bulb_y - r - 1.0), 2.6, Color(0.22, 0.2, 0.18))

		var c := Vector2(cx, bulb_y)
		# ореол свечения
		if lit > 0.02:
			draw_circle(c, r * (2.1 + 0.5 * lit), Color(WARM.r, WARM.g, WARM.b, 0.10 * lit))
			draw_circle(c, r * 1.5, Color(WARM.r, WARM.g, WARM.b, 0.16 * lit))
		# стекло: от погашенного к тёплому
		var glass: Color = GLASS_OFF.lerp(Color(1.0, 0.86, 0.55), lit)
		draw_circle(c, r, glass)
		# нить накала
		draw_line(c + Vector2(-r * 0.35, r * 0.15), c + Vector2(r * 0.35, r * 0.15),
			Color(1.0, 0.75, 0.4).lerp(Color(0.3, 0.22, 0.15), 1.0 - lit), 1.5)
		# блик
		if lit > 0.3:
			draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.18, Color(1, 1, 0.9, 0.5 * lit))
