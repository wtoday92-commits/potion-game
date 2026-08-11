extends Control
## Банка-зелье через шейдер (jar.gdshader). Геометрию тела и позиции сгустков
## считаем здесь и передаём в шейдер униформами; вся отрисовка — в шейдере.

var hue: float = 120.0     # спектр 0..360
var vsize: float = 0.6     # объём/размер сосуда 0..1
var count: int = 5         # число сгустков
var bsize: float = 0.5     # размер сгустка 0..1
var pot_seed: int = 1      # сид раскладки сгустков

var glass: ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/jar.gdshader")
	glass = ColorRect.new()
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.material = mat
	add_child(glass)
	resized.connect(_apply)
	_apply()

func set_potion(h: float, v: float, c: int, b: float, s: int) -> void:
	hue = h
	vsize = clampf(v, 0.0, 1.0)
	count = max(0, c)
	bsize = clampf(b, 0.0, 1.0)
	pot_seed = s
	_apply()

func _apply() -> void:
	if mat == null:
		return
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	var scale: float = lerpf(0.5, 0.95, vsize)
	var bw_px: float = w * 0.7 * scale
	var bh_px: float = (h - 30.0) * scale
	var cx_px: float = w * 0.5
	var top_px: float = h - bh_px - 8.0

	mat.set_shader_parameter("liquid_col", Color.from_hsv(fposmod(hue, 360.0) / 360.0, 0.7, 0.95))
	mat.set_shader_parameter("body_min", Vector2((cx_px - bw_px * 0.5) / w, top_px / h))
	mat.set_shader_parameter("body_size", Vector2(bw_px / w, bh_px / h))
	mat.set_shader_parameter("fill", 0.9)
	mat.set_shader_parameter("corner", 14.0 / h)
	mat.set_shader_parameter("aspect", w / h)

	# сгустки: детерминированная раскладка в зоне жидкости
	var liq_top_px: float = top_px + bh_px * (1.0 - 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = pot_seed
	var r_px: float = lerpf(6.0, 18.0, bsize)
	var arr := PackedVector4Array()
	for i in count:
		if i >= 12:
			break
		var minx: float = (cx_px - bw_px * 0.5) + r_px + 2.0
		var maxx: float = (cx_px + bw_px * 0.5) - r_px - 2.0
		var miny: float = liq_top_px + r_px + 2.0
		var maxy: float = (top_px + bh_px) - r_px - 2.0
		if maxx <= minx or maxy <= miny:
			break
		var bx: float = minx + rng.randf() * (maxx - minx)
		var by: float = miny + rng.randf() * (maxy - miny)
		arr.append(Vector4(bx / w, by / h, r_px / h, 0.0))
	while arr.size() < 12:
		arr.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("blobs", arr)
	mat.set_shader_parameter("blob_n", mini(count, 12))
