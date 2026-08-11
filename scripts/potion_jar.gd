extends Control
## Рисованная банка-зелье (этап 1). «Объём» масштабирует САМ сосуд (как в
## оригинале), а не уровень жидкости — сосуд всегда почти полон. Скруглённое
## тело + горлышко + крышка. Позже заменим на шейдер/красивый арт.

var hue: float = 120.0     # спектр 0..360
var vsize: float = 0.6     # объём/размер сосуда 0..1
var count: int = 5         # число сгустков
var bsize: float = 0.5     # размер сгустка 0..1
var pot_seed: int = 1      # сид раскладки сгустков

func set_potion(h: float, v: float, c: int, b: float, s: int) -> void:
	hue = h
	vsize = clampf(v, 0.0, 1.0)
	count = max(0, c)
	bsize = clampf(b, 0.0, 1.0)
	pot_seed = s
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	# сосуд масштабируется по объёму (45%..100% доступной области); место сверху
	# под горлышко/крышку.
	var scale: float = lerpf(0.45, 1.0, vsize)
	var bw: float = w * scale
	var bh: float = (h - 34.0) * scale
	var cx: float = w * 0.5
	var body_top: float = h - bh - 6.0
	var body := Rect2(cx - bw * 0.5, body_top, bw, bh)

	var glass := Color(0.09, 0.11, 0.2, 0.55)
	var col := Color.from_hsv(fposmod(hue, 360.0) / 360.0, 0.65, 0.92)

	# тело (скруглённое стекло)
	_rrect(body, glass, 16.0)

	# жидкость — сосуд почти полон (90%), низ скруглён
	var liq_full := body.grow(-4.0)
	var fill_frac := 0.90
	var liq := Rect2(
		liq_full.position.x,
		liq_full.position.y + liq_full.size.y * (1.0 - fill_frac),
		liq_full.size.x,
		liq_full.size.y * fill_frac)
	_rrect(liq, col, 12.0)

	# сгустки (детерминированно по сиду)
	var rng := RandomNumberGenerator.new()
	rng.seed = pot_seed
	var r: float = lerpf(4.0, 15.0, bsize)
	for i in count:
		if liq.size.x <= r * 2.0 or liq.size.y <= r * 2.0:
			break
		var bx: float = liq.position.x + r + rng.randf() * (liq.size.x - r * 2.0)
		var by: float = liq.position.y + r + rng.randf() * (liq.size.y - r * 2.0)
		draw_circle(Vector2(bx, by), r, col.lightened(0.35))
		draw_arc(Vector2(bx, by), r, 0.0, TAU, 20, Color(0, 0, 0, 0.4), 1.5)

	# горлышко + крышка
	var neck_w: float = bw * 0.32
	_rrect(Rect2(cx - neck_w * 0.5, body_top - 14.0, neck_w, 16.0), glass, 4.0)
	_rrect(Rect2(cx - neck_w * 0.6, body_top - 22.0, neck_w * 1.2, 10.0), Color(0.2, 0.5, 0.7, 0.95), 4.0)

	# контур тела
	_rrect_outline(body, Color(0.35, 0.88, 1.0, 0.9), 16.0, 2.0)

func _rrect(rect: Rect2, color: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)

func _rrect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)
