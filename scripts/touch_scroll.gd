extends ScrollContainer
class_name TouchScroll
## ScrollContainer с «мобильным» скроллом: смахнул пальцем — поехало, где бы
## палец ни лёг, хоть на кнопке.
##
## Штатный ScrollContainer ловит перетаскивание только через `_gui_input`, а его
## забирает себе верхний контрол под пальцем. На экранах, где всё состоит из
## кнопок и карточек, попасть в «пустое место» почти невозможно — отсюда
## ощущение, что скролл не работает. Поэтому события ловим в `_input()`: он
## приходит РАНЬШЕ раздачи по GUI, так что жест виден всегда. Как только палец
## увёл дальше DRAG_START, помечаем событие обработанным — и кнопка под пальцем
## уже не сработает (иначе любой скролл случайно что-нибудь нажимал бы).

const DRAG_START := 10.0        # порог, после которого жест считается скроллом
const FLICK_DECAY := 6.0        # затухание инерции, 1/сек
const FLICK_MIN := 60.0         # ниже этой скорости инерцию не запускаем
const FLICK_MAX := 4200.0       # потолок скорости броска

var _press: bool = false        # палец опущен внутри нас
var _drag: bool = false         # жест уже признан скроллом
var _from: Vector2 = Vector2.ZERO
var _vel: float = 0.0           # текущая скорость инерции, px/сек
var _last_t: int = 0

func _ready() -> void:
	# штатный порог выключаем — тащим сами, иначе两 механизма дерутся
	scroll_deadzone = 0
	set_process(true)

func _scrollable() -> bool:
	var vs: VScrollBar = get_v_scroll_bar()
	return vs != null and vs.max_value - vs.min_value > vs.page + 1.0

func _pointer_pos(ev: InputEvent) -> Vector2:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		return ev.position
	if ev is InputEventMouseButton or ev is InputEventMouseMotion:
		return ev.position
	return Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _scrollable():
		return
	var press_ev: bool = event is InputEventScreenTouch or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	if press_ev:
		if event.pressed:
			if get_global_rect().has_point(_pointer_pos(event)):
				_press = true
				_drag = false
				_from = _pointer_pos(event)
				_vel = 0.0
				_last_t = Time.get_ticks_usec()
		else:
			if _drag:
				# гасим отпускание, чтобы кнопка под пальцем не «нажалась» после скролла
				get_viewport().set_input_as_handled()
			_press = false
			_drag = false
		return

	var move_ev: bool = event is InputEventScreenDrag or \
		(event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
	if not (move_ev and _press):
		return
	var p: Vector2 = _pointer_pos(event)
	if not _drag:
		if absf(p.y - _from.y) < DRAG_START:
			return
		_drag = true                       # порог взят — дальше это скролл, не тап
	var dy: float = event.relative.y if event is InputEventScreenDrag or event is InputEventMouseMotion else 0.0
	scroll_vertical -= int(round(dy))
	var now: int = Time.get_ticks_usec()
	var dt: float = float(now - _last_t) / 1_000_000.0
	_last_t = now
	if dt > 0.0005:
		_vel = clampf(-dy / dt, -FLICK_MAX, FLICK_MAX)
	get_viewport().set_input_as_handled()

# Инерция после броска: едем, пока скорость не затухнет или не упрёмся в край.
func _process(delta: float) -> void:
	if _press or absf(_vel) < FLICK_MIN:
		_vel = 0.0
		return
	var before: int = scroll_vertical
	scroll_vertical += int(round(_vel * delta))
	if scroll_vertical == before:          # доехали до края — инерцию гасим
		_vel = 0.0
		return
	_vel = move_toward(_vel, 0.0, absf(_vel) * FLICK_DECAY * delta)
