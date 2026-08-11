extends Control
## Банка = нарисованная бутыль (bottle.png) + живая жидкость/сгустки ВНУТРИ неё
## (liquid.gdshader, клип по маске интерьера). «Объём» масштабирует всю бутыль
## (сосуд всегда почти полон). Текстуры грузим через load() — если Godot ещё не
## импортировал их, банка просто пустая до импорта (без падения).

const LiquidShader := preload("res://shaders/liquid.gdshader")

# Границы интерьера стекла в UV (замерены по bottle_interior.png).
const I_TOP := 0.150
const I_BOT := 0.953
const I_LEFT := 0.240
const I_RIGHT := 0.746
const FILL := 0.88     # сосуд почти полон

var hue: float = 120.0
var vsize: float = 0.6
var count: int = 5
var bsize: float = 0.5
var pot_seed: int = 1

var content: Control
var liquid: ColorRect
var bottle: TextureRect
var mat: ShaderMaterial

func _ready() -> void:
	content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	liquid = ColorRect.new()
	liquid.set_anchors_preset(Control.PRESET_FULL_RECT)
	liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = LiquidShader
	var mask_tex := load("res://assets/bottle/bottle_interior.png") as Texture2D
	if mask_tex:
		mat.set_shader_parameter("mask", mask_tex)
	liquid.material = mat
	content.add_child(liquid)

	bottle = TextureRect.new()
	bottle.texture = load("res://assets/bottle/bottle.png") as Texture2D
	bottle.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottle.stretch_mode = TextureRect.STRETCH_SCALE
	bottle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bottle)

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
	if mat == null or content == null or size.x <= 0.0 or size.y <= 0.0:
		return
	# «Объём» масштабирует всю бутыль (вокруг центра)
	var sc: float = lerpf(0.62, 1.0, vsize)
	content.pivot_offset = size * 0.5
	content.scale = Vector2(sc, sc)

	var ar: float = size.x / size.y
	mat.set_shader_parameter("liquid_col", Color.from_hsv(fposmod(hue, 360.0) / 360.0, 0.72, 0.95))
	mat.set_shader_parameter("fill", FILL)
	mat.set_shader_parameter("interior_top", I_TOP)
	mat.set_shader_parameter("interior_bot", I_BOT)
	mat.set_shader_parameter("interior_left", I_LEFT)
	mat.set_shader_parameter("interior_right", I_RIGHT)
	mat.set_shader_parameter("aspect", ar)

	# сгустки в зоне жидкости (в UV)
	var liq_top: float = I_BOT - (I_BOT - I_TOP) * FILL
	var r_uv: float = lerpf(0.02, 0.055, bsize)
	var mx: float = r_uv / max(0.0001, ar)   # x сжат аспектом
	var rng := RandomNumberGenerator.new()
	rng.seed = pot_seed
	var arr := PackedVector4Array()
	for i in count:
		if i >= 12:
			break
		var minx: float = I_LEFT + mx
		var maxx: float = I_RIGHT - mx
		var miny: float = liq_top + r_uv
		var maxy: float = I_BOT - r_uv
		if maxx <= minx or maxy <= miny:
			break
		var bx: float = minx + rng.randf() * (maxx - minx)
		var by: float = miny + rng.randf() * (maxy - miny)
		arr.append(Vector4(bx, by, r_uv, 0.0))
	while arr.size() < 12:
		arr.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("blobs", arr)
	mat.set_shader_parameter("blob_n", mini(count, 12))
