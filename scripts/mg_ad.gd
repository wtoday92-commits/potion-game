extends Control
class_name AdGame
## Миниигра Маркетолога «реклама»: по экрану лезут настоящие рекламные БАННЕРЫ (готовые
## креативы-картинки в стиле игры) разных размеров, слегка повёрнутые. Тап по ЛЮБОМУ месту
## баннера закрывает его. Фон НЕ затемняется, но кликаются только баннеры. Если не закрывать —
## завалят весь экран. Баффа/штрафа нет. Кол-во растёт с уровнем.

signal finished(ok: bool, accuracy: float)

const BANNERS := [
	"res://assets/market/adb_sale.png", "res://assets/market/adb_90.png",
	"res://assets/market/adb_won.png", "res://assets/market/adb_spin.png",
	"res://assets/market/adb_gift.png", "res://assets/market/adb_hot.png",
	"res://assets/market/adb_install.png", "res://assets/market/adb_last.png",
	"res://assets/market/adb_mega.png", "res://assets/market/adb_levelup.png",
	"res://assets/market/adb_vip.png", "res://assets/market/adb_x100.png",
	"res://assets/market/adb_skin.png", "res://assets/market/adb_daily.png",
	"res://assets/market/adb_lucky.png", "res://assets/market/adb_boss.png",
	"res://assets/market/adb_gems.png", "res://assets/market/adb_playfree.png",
]

var level: int = 1
var _timer: Label
var _to_spawn: int = 0
var _spawn_acc: float = 0.0
var _alive: int = 0
var _elapsed: float = 0.0
var _spawn_gap: float = 0.38
var _texs: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP        # фон не кликается (но и не затемняется)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func set_timer(sec: float) -> void:
	if _timer != null:
		_timer.text = "ВОССОЗДАЙ — %dс" % int(ceil(maxf(sec, 0.0)))

func setup(lvl: int) -> void:
	level = lvl
	_to_spawn = {1: 5, 2: 6, 3: 8, 4: 11}.get(lvl, 5)
	if lvl == 4:
		_spawn_gap = 0.3                             # УР.4: лезут чаще
	for p in BANNERS:
		var t = load(p)
		if t != null:
			_texs.append(t)
	_build_ui()

func _build_ui() -> void:
	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size", UI.FS_M)
	_timer.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_timer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_timer.add_theme_constant_override("outline_size", 5)
	_timer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer.offset_top = 8.0
	_timer.offset_bottom = 34.0
	add_child(_timer)

	var hint := Label.new()
	hint.text = "Закройте всю рекламу!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", UI.FS_M)
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 44.0
	hint.offset_bottom = 78.0
	add_child(hint)

func _process(delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	if not size.is_equal_approx(vp):
		size = vp
	_elapsed += delta
	if _to_spawn > 0:
		_spawn_acc += delta
		if _spawn_acc >= _spawn_gap:
			_spawn_acc = 0.0
			_spawn_one()
			_to_spawn -= 1
	if _to_spawn <= 0 and _alive <= 0:
		set_process(false)
		finished.emit(true, 1.0)
	elif _elapsed > 16.0:                            # страховка
		set_process(false)
		finished.emit(true, 1.0)

func _spawn_one() -> void:
	# крупный баннер (аспект ~3:2), разного размера, слегка повёрнут
	var w: float = randf_range(320.0, 480.0)
	w = minf(w, size.x - 16.0)
	var h: float = w * (2.0 / 3.0)
	var x: float = randf_range(8.0, maxf(10.0, size.x - w - 8.0))
	var y: float = randf_range(90.0, maxf(96.0, size.y - h - 14.0))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.flat = true
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.size = Vector2(w, h)
	b.position = Vector2(x, y)
	b.pivot_offset = b.size * 0.5
	b.rotation = deg_to_rad(randf_range(-5.0, 5.0))
	# сам баннер-креатив (картинка целиком) + тонкая белая рамка-обводка
	if not _texs.is_empty():
		var tex := TextureRect.new()
		tex.texture = _texs[randi() % _texs.size()]
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(tex)
	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.set_border_width_all(4)
	fsb.border_color = Color(1, 1, 1, 0.95)
	fsb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(frame)

	b.pressed.connect(_on_close.bind(b))
	add_child(b)
	_alive += 1

func _on_close(b: Button) -> void:
	if is_instance_valid(b):
		b.queue_free()
	_alive -= 1
	Sfx.play("uiClick")
