extends Control
## Рисованная банка-зелье (этап 1). Параметры задаются set_potion(),
## отрисовка — через _draw(). Позже заменим на шейдер/красивый арт.

var hue: float = 120.0      # спектр 0..360
var fill: float = 0.6       # объём жидкости 0..1
var count: int = 5          # число сгустков
var bsize: float = 0.5      # размер сгустка 0..1
var pot_seed: int = 1       # сид раскладки сгустков (одинаковый = одинаковая раскладка)

func set_potion(h: float, f: float, c: int, b: float, s: int) -> void:
	hue = h
	fill = clampf(f, 0.0, 1.0)
	count = max(0, c)
	bsize = clampf(b, 0.0, 1.0)
	pot_seed = s
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var m: float = 8.0
	var jar := Rect2(m, m, w - m * 2.0, h - m * 2.0)

	# стекло
	draw_rect(jar, Color(0.09, 0.11, 0.2, 0.55), true)

	# жидкость (снизу вверх по объёму)
	var liq_h: float = jar.size.y * fill
	var liq := Rect2(jar.position.x + 4.0, jar.position.y + jar.size.y - liq_h, jar.size.x - 8.0, liq_h)
	var col := Color.from_hsv(fposmod(hue, 360.0) / 360.0, 0.65, 0.92)
	if liq_h > 1.0:
		draw_rect(liq, col, true)

	# сгустки (детерминированная раскладка по сиду)
	var rng := RandomNumberGenerator.new()
	rng.seed = pot_seed
	var r: float = lerpf(4.0, 16.0, bsize)
	for i in count:
		if liq.size.x <= r * 2.0 or liq.size.y <= r * 2.0:
			break
		var bx: float = liq.position.x + r + rng.randf() * (liq.size.x - r * 2.0)
		var by: float = liq.position.y + r + rng.randf() * (liq.size.y - r * 2.0)
		draw_circle(Vector2(bx, by), r, col.lightened(0.35))
		draw_arc(Vector2(bx, by), r, 0.0, TAU, 20, Color(0, 0, 0, 0.4), 1.5)

	# контур банки
	draw_rect(jar, Color(0.35, 0.88, 1.0, 0.9), false, 2.0)
