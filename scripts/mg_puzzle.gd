extends Control
class_name PuzzleGame
## Миниигра Маркетолога «пазл»: из картинки (в стиле игры) вырезан КРУГЛЫЙ кусок. Кусок
## (с тенью, чтобы выделялся) двигается по горизонтали слайдером — надо вернуть его в
## лунку (у неё лёгкая тень по краю). Точность в %. УР.4: второй слайдер — поворот куска.

signal finished(ok: bool, accuracy: float)

# сюжетные арты с персонажами игры (цветной точечный комикс, космо-бар)
const PICS := [
	"res://assets/market/puz_barmen.png", "res://assets/market/puz_catlady.png",
	"res://assets/market/puz_dj.png", "res://assets/market/puz_chef.png",
	"res://assets/market/puz_tentacloid.png", "res://assets/market/puz_gurman.png",
	"res://assets/market/puz_twofaced.png", "res://assets/market/puz_supernova.png",
]

var level: int = 1
var _pic: Texture2D
var _r: float = 60.0                 # радиус куска (px, в координатах области)
var _hole: Vector2 = Vector2()       # центр лунки (в координатах области)
var _cx: float = 0.0                 # текущий X центра куска (в координатах области)
var _rot: float = 0.0                # текущий поворот куска (рад), только УР.4
var _timer: Label
var _prompt: Label
var _xslider: HTouchSlider
var _rslider: HTouchSlider
var _submit: Button
var _piece: ColorRect
var _mat: ShaderMaterial
var _done_shown: bool = false

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D pic;
uniform vec2 uv_center;
uniform float uv_radius;
uniform float rot;
void fragment(){
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	if(d > 0.5){ COLOR = vec4(0.0); }
	else {
		float c = cos(rot); float s = sin(rot);
		vec2 pr = vec2(p.x*c - p.y*s, p.x*s + p.y*c);
		vec2 suv = uv_center + pr * (2.0*uv_radius);
		vec4 col = texture(pic, suv);
		float edge = smoothstep(0.5, 0.45, d);
		COLOR = vec4(col.rgb, col.a*edge);
	}
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func set_timer(sec: float) -> void:
	if _timer != null:
		_timer.text = "ВОССОЗДАЙ — %dс" % int(ceil(maxf(sec, 0.0)))

func setup(lvl: int) -> void:
	level = lvl
	_pic = load(PICS[randi() % PICS.size()])
	_build_ui()
	# начальные значения зададим после первой раскладки (в _process), когда известна область

func _area() -> Rect2:
	var top: float = 92.0
	var ctrl_h: float = 226.0 if level == 4 else 150.0
	var avail: float = maxf(60.0, size.y - top - ctrl_h)
	var side: float = minf(size.x - 24.0, avail)
	return Rect2((size.x - side) * 0.5, top, side, side)

func _build_ui() -> void:
	_timer = _mk_label(22, Color(0.7, 0.85, 1.0))
	_timer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer.offset_top = 8.0; _timer.offset_bottom = 34.0
	add_child(_timer)

	_prompt = _mk_label(22, Color(0.95, 0.98, 1.0))
	_prompt.text = "Верните кусочек на место"
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_top = 44.0; _prompt.offset_bottom = 80.0
	add_child(_prompt)

	_piece = ColorRect.new()
	_piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new(); sh.code = SHADER_CODE
	_mat.shader = sh
	_mat.set_shader_parameter("pic", _pic)
	_piece.material = _mat
	add_child(_piece)

	# крупные тач-слайдеры (под палец): X — всегда, поворот — на УР.4. Хорошо разнесены.
	_xslider = HTouchSlider.new()
	_xslider.min_value = 0.0; _xslider.max_value = 1.0; _xslider.step = 0.001
	_xslider.accent = Color(0.55, 0.85, 1.0)
	_xslider.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_xslider.offset_left = 24.0; _xslider.offset_right = -24.0
	_xslider.offset_top = -132.0 if level == 4 else -128.0
	_xslider.offset_bottom = _xslider.offset_top + 64.0
	add_child(_xslider)

	if level == 4:
		_rslider = HTouchSlider.new()
		_rslider.min_value = -0.6; _rslider.max_value = 0.6; _rslider.step = 0.01
		_rslider.accent = Color(1.0, 0.72, 0.42)
		_rslider.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_rslider.offset_left = 24.0; _rslider.offset_right = -24.0
		_rslider.offset_top = -210.0; _rslider.offset_bottom = -146.0
		add_child(_rslider)

	_submit = Button.new()
	_submit.text = "Проверить"
	_submit.focus_mode = Control.FOCUS_NONE
	_submit.add_theme_font_size_override("font_size", UI.FS_L)
	_submit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_submit.offset_top = -56.0; _submit.offset_bottom = -10.0
	_submit.offset_left = 40.0; _submit.offset_right = -40.0
	_submit.pressed.connect(_on_submit)
	add_child(_submit)

func _mk_label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l

var _inited: bool = false
func _process(_delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	if not size.is_equal_approx(vp):
		size = vp
	var a := _area()
	_r = a.size.x * 0.16
	if not _inited and a.size.x > 10.0:
		_inited = true
		# лунка — случайно, кусок отъезжает по X от неё
		_hole = a.size * Vector2(randf_range(0.25, 0.75), randf_range(0.3, 0.7))
		_xslider.value = 0.15 if _hole.x > a.size.x * 0.5 else 0.85
	if not _inited:
		return
	# позиция куска из X-слайдера (по горизонтали, Y = Y лунки)
	_cx = lerpf(_r, a.size.x - _r, _xslider.value)
	_rot = _rslider.value if (level == 4 and _rslider != null) else 0.0
	# UV центра лунки в картинке (область квадратная → uv = доля)
	_mat.set_shader_parameter("uv_center", Vector2(_hole.x / a.size.x, _hole.y / a.size.y))
	_mat.set_shader_parameter("uv_radius", _r / a.size.x)
	_mat.set_shader_parameter("rot", _rot)
	_piece.size = Vector2(_r * 2.0, _r * 2.0)
	_piece.position = a.position + Vector2(_cx - _r, _hole.y - _r)
	queue_redraw()

func _on_submit() -> void:
	if _done_shown:
		return
	var a := _area()
	var span: float = maxf(1.0, a.size.x - 2.0 * _r)
	var xacc: float = clampf(1.0 - absf(_cx - _hole.x) / span, 0.0, 1.0)
	var acc: float = xacc
	if level == 4:
		var racc: float = clampf(1.0 - absf(_rot) / 0.6, 0.0, 1.0)
		acc = (xacc + racc) * 0.5
	var ok: bool = acc >= 0.9
	Sfx.play("dock" if ok else "tick")
	finished.emit(ok, acc)

func show_result(pct: int, ok: bool) -> void:
	_done_shown = true
	if _xslider != null: _xslider.editable = false
	if _rslider != null: _rslider.editable = false
	if _submit != null: _submit.disabled = true
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.6)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var res := _mk_label(40, Color(0.55, 1.0, 0.65) if ok else Color(1.0, 0.65, 0.55))
	res.text = "Кусочек на месте: %d%%" % pct
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(res)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.10, 1.0))
	if not _inited:
		return
	var a := _area()
	if _pic:
		draw_texture_rect(_pic, a, false)
	# лунка: затемнение + лёгкая тень по краю внутрь
	var hole_s: Vector2 = a.position + _hole
	draw_circle(hole_s, _r, Color(0, 0, 0, 0.5))
	for i in 7:
		draw_arc(hole_s, _r - float(i) * 1.6, 0.0, TAU, 40, Color(0, 0, 0, 0.10), 2.0, true)
	draw_arc(hole_s, _r, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 2.0, true)
	# тень куска (кусок рисуется поверх — это его дочерний ColorRect)
	var pc: Vector2 = a.position + Vector2(_cx, _hole.y)
	draw_circle(pc + Vector2(5, 8), _r, Color(0, 0, 0, 0.4))
	# рамка области
	draw_rect(a, Color(1, 1, 1, 0.7), false, 2.0)
