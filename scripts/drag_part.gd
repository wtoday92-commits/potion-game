extends Control
class_name DragPart
## Деталь Навигатора Роя — перетаскиваемая иконка. Тащишь пальцем; на отпускании
## сообщает механике (dropped), та считает, сколько деталей внутри зоны банки.
## Порт l4Fly* (детали-магниты).

signal dropped(part)

const SZ := 64.0
var _drag: bool = false
var _lbl: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(SZ, SZ)
	custom_minimum_size = size
	_lbl = Label.new()
	_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl.add_theme_font_size_override("font_size", 40)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

func set_symbol(sym: String) -> void:
	if _lbl != null:
		_lbl.text = sym

func center() -> Vector2:
	return position + size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_drag = true
			z_index = 1
			Sfx.play("blobGrab")
		else:
			if _drag:
				_drag = false
				z_index = 0
				dropped.emit(self)
		accept_event()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _drag:
		position += event.relative
		accept_event()
