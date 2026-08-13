extends Control
class_name CatPaw
## Кошачья лапа-помеха (Бабушка Мурра). Накрывает ползунок и НЕ уходит сама —
## согнать можно только СЕРИЕЙ из HITS_NEEDED быстрых тапов (пауза >GAP сбрасывает
## счётчик; одиночный тап — лапа лишь трясётся). Порт l4PawSpawnOne/onHit.
## Перехватывает ввод (mouse_filter STOP) → пока висит, ползунок под ней недоступен.

signal shooed(key: String)

const HITS_NEEDED := 3
const GAP := 0.8            # с — серия прерывается, если пауза между тапами больше

var key: String = ""       # какой ползунок накрывает (для отчёта при сгоне)
var _hits: int = 0
var _last: float = 0.0
var _paw: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_paw = Label.new()
	_paw.text = "🐾"
	_paw.add_theme_font_size_override("font_size", 96)
	_paw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_paw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paw.rotation = deg_to_rad(randf_range(-16.0, 16.0))
	add_child(_paw)

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
		_hits = 0                     # серия прервалась — считаем заново
	_last = now
	_hits += 1
	Sfx.play("pawClick")
	_wiggle()
	if _hits >= HITS_NEEDED:
		Sfx.play("meow")
		shooed.emit(key)              # мех уберёт лапу и освободит ползунок

func _wiggle() -> void:
	if _paw == null:
		return
	_paw.pivot_offset = _paw.size * 0.5    # вращаем вокруг центра (размер уже известен)
	var base: float = _paw.rotation
	var t := create_tween()
	t.tween_property(_paw, "rotation", base + deg_to_rad(14.0), 0.05)
	t.tween_property(_paw, "rotation", base - deg_to_rad(10.0), 0.06)
	t.tween_property(_paw, "rotation", base, 0.06)
