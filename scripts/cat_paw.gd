extends Control
class_name CatPaw
## Кошачья лапа-помеха (Бабушка Мурра). Накрывает ползунок и НЕ уходит сама —
## согнать можно только СЕРИЕЙ из HITS_NEEDED быстрых тапов (пауза >GAP сбрасывает
## счётчик; одиночный тап — лапа дёргается). Перехватывает ввод (STOP) → пока
## висит, ползунок под ней недоступен. Картинка (assets/ui/pawN.png) с мягким краем
## и затуханием книзу (paw_fade.gdshader); если картинка не загрузилась — рисуется
## кодом. Порт l4Paw*.

signal shooed(key: String)

const HITS_NEEDED := 3
const GAP := 0.8            # с — серия прерывается, если пауза между тапами больше
const FadeShader := preload("res://shaders/paw_fade.gdshader")

var key: String = ""
var _hits: int = 0
var _last: float = 0.0
var _wob: float = 0.0       # наклон лапы (рад)
var _paw: TextureRect = null   # картинка лапы (если загрузилась)
var _fur: Color = Color(0.52, 0.42, 0.66)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 3
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := get_parent()
	if p is Control and (p as Control).size.x > 1.0:
		size = (p as Control).size
	_wob = deg_to_rad(randf_range(-14.0, 14.0))
	_fur = Color.from_hsv(randf_range(0.70, 0.80), randf_range(0.28, 0.42), randf_range(0.62, 0.78))
	var tex := load("res://assets/ui/paw%d.png" % (randi() % 3 + 1)) as Texture2D
	if tex != null:
		_paw = TextureRect.new()
		_paw.texture = tex
		_paw.set_anchors_preset(Control.PRESET_FULL_RECT)
		_paw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_paw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = FadeShader
		_paw.material = m
		add_child(_paw)
		_paw.rotation = _wob
	resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	if _paw != null:
		_paw.pivot_offset = _paw.size * 0.5
	queue_redraw()

# Процедурная лапа-заглушка (когда картинка не импортирована).
func _draw() -> void:
	if _paw != null or size.x < 4.0 or size.y < 4.0:
		return
	var w := size.x
	var h := size.y
	draw_set_transform(size * 0.5, _wob, Vector2.ONE)
	var fur := _fur
	var fur_d := Color(fur.r * 0.55, fur.g * 0.55, fur.b * 0.6)
	var clear := Color(fur.r, fur.g, fur.b, 0.0)
	var xt := w * 0.24
	var xb := w * 0.16
	var yt := -h * 0.52
	var yb := h * 0.34
	draw_polygon(
		PackedVector2Array([Vector2(-xt, yt), Vector2(xt, yt), Vector2(xb, yb), Vector2(-xb, yb)]),
		PackedColorArray([fur, fur, clear, clear]))
	var py := yb - h * 0.06
	for i in 4:
		var fx: float = lerpf(-xt * 0.72, xt * 0.72, float(i) / 3.0)
		draw_circle(Vector2(fx, py), w * 0.11, fur)
		draw_arc(Vector2(fx, py), w * 0.11, 0.0, TAU, 14, fur_d, 1.5, true)
	draw_circle(Vector2(0.0, py - h * 0.10), w * 0.17, fur)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	if not pressed:
		return
	accept_event()
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last > GAP:
		_hits = 0
	_last = now
	_hits += 1
	Sfx.play("pawClick")
	_wiggle()
	if _hits >= HITS_NEEDED:
		Sfx.play("meow")
		shooed.emit(key)

# дёрганье лапы при тапе
func _wiggle() -> void:
	if _paw != null:
		_paw.pivot_offset = _paw.size * 0.5
		var t := create_tween()
		t.tween_property(_paw, "rotation", _wob + deg_to_rad(15.0), 0.05)
		t.tween_property(_paw, "rotation", _wob - deg_to_rad(11.0), 0.06)
		t.tween_property(_paw, "rotation", _wob, 0.06)
	else:
		var t := create_tween()
		t.tween_method(_set_wob, _wob, _wob + deg_to_rad(15.0), 0.05)
		t.tween_method(_set_wob, _wob + deg_to_rad(15.0), _wob - deg_to_rad(11.0), 0.06)
		t.tween_method(_set_wob, _wob - deg_to_rad(11.0), _wob, 0.06)

func _set_wob(v: float) -> void:
	_wob = v
	queue_redraw()
