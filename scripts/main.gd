extends Control
## Ядро игрового цикла (этап 1):
##   ЗАПОМНИ (показ цели) -> ВОССОЗДАЙ (ползунки) -> РЕЙТИНГ -> РЕЗУЛЬТАТ.
## UI пока строится кодом (надёжно для первого запуска). Позже вынесем в сцены.

const PotionJarScene := preload("res://scenes/potion_jar.tscn")

# Параметры зелья: границы/шаг/вес/подпись. Дот-доступ к словарям не используем —
# только через ["ключ"], так надёжнее.
const PARAMS := {
	"color":  {"min": 0.0,  "max": 360.0, "step": 5.0, "weight": 1.0, "label": "Спектр",  "suffix": "°"},
	"volume": {"min": 10.0, "max": 100.0, "step": 1.0, "weight": 1.0, "label": "Объём",   "suffix": "%"},
	"count":  {"min": 0.0,  "max": 12.0,  "step": 1.0, "weight": 0.8, "label": "Сгустки", "suffix": ""},
	"bsize":  {"min": 10.0, "max": 100.0, "step": 2.0, "weight": 0.6, "label": "Размер",  "suffix": "%"},
}
const ORDER: Array = ["color", "volume", "count", "bsize"]

const MEMORIZE_S := 2.5
const GOOD := 0.80
const PERFECT := 0.95

var target: Dictionary = {}
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var jar: Control
var phase_label: Label
var result_panel: Panel
var result_sticker: Label
var result_detail: Label
var seed_val: int = 0
var phase: String = "idle"

func _ready() -> void:
	randomize()
	_build_ui()
	_new_round()

# ---------- построение интерфейса ----------
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24.0
	root.offset_top = 24.0
	root.offset_right = -24.0
	root.offset_bottom = -24.0
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 28)
	root.add_child(phase_label)

	var jar_center := CenterContainer.new()
	jar_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(jar_center)
	jar = PotionJarScene.instantiate()
	jar_center.add_child(jar)

	var sliders_row := HBoxContainer.new()
	sliders_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sliders_row.add_theme_constant_override("separation", 24)
	root.add_child(sliders_row)

	for key in ORDER:
		var p: Dictionary = PARAMS[key]
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		sliders_row.add_child(col)

		var name_lbl := Label.new()
		name_lbl.text = p["label"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lbl)

		var s := VSlider.new()
		s.min_value = p["min"]
		s.max_value = p["max"]
		s.step = p["step"]
		s.custom_minimum_size = Vector2(44, 260)
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_slider_changed.bind(key))
		col.add_child(s)
		sliders[key] = s

		var val_lbl := Label.new()
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(val_lbl)
		value_labels[key] = val_lbl

	var done_btn := Button.new()
	done_btn.text = "ГОТОВО!"
	done_btn.custom_minimum_size = Vector2(0, 56)
	done_btn.pressed.connect(_on_done)
	root.add_child(done_btn)

	# ----- оверлей результата -----
	result_panel = Panel.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.visible = false
	add_child(result_panel)

	var rc := CenterContainer.new()
	rc.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(rc)

	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", 14)
	rc.add_child(rv)

	result_sticker = Label.new()
	result_sticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sticker.add_theme_font_size_override("font_size", 40)
	rv.add_child(result_sticker)

	result_detail = Label.new()
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_detail)

	var again := Button.new()
	again.text = "Ещё раз"
	again.custom_minimum_size = Vector2(0, 48)
	again.pressed.connect(_new_round)
	rv.add_child(again)

# ---------- цикл раунда ----------
func _new_round() -> void:
	result_panel.visible = false
	seed_val = randi()
	target = _random_values()
	_apply_to_jar(target)
	_set_sliders_interactable(false)
	for key in ORDER:
		value_labels[key].text = "?"    # в фазе показа числа скрыты — это игра на память
	phase = "memorize"
	phase_label.text = "ЗАПОМНИ ЗЕЛЬЕ…"
	await get_tree().create_timer(MEMORIZE_S).timeout
	if phase != "memorize":
		return
	_start_recreate()

func _start_recreate() -> void:
	phase = "recreate"
	phase_label.text = "ВОССОЗДАЙ ПО ПАМЯТИ"
	var start_vals: Dictionary = _random_values()
	for key in ORDER:
		sliders[key].set_value_no_signal(start_vals[key])
	_set_sliders_interactable(true)
	_apply_to_jar(_current_values())
	_update_value_labels(_current_values())

func _on_done() -> void:
	if phase != "recreate":
		return
	var comps: Dictionary = {}
	var overall: float = 0.0
	var wsum: float = 0.0
	for key in ORDER:
		var p: Dictionary = PARAMS[key]
		var span: float = float(p["max"]) - float(p["min"])
		var diff: float = abs(sliders[key].value - float(target[key])) / span   # 0..1
		var sc: float = pow(clampf(1.0 - diff, 0.0, 1.0), 1.6)                   # частичный успех, нелинейно
		comps[key] = sc
		overall += sc * float(p["weight"])
		wsum += float(p["weight"])
	overall = overall / wsum
	_show_result(overall, comps)

func _show_result(overall: float, comps: Dictionary) -> void:
	phase = "result"
	var sticker: String = "БРАК"
	if overall >= PERFECT:
		sticker = "ИДЕАЛ!"
	elif overall >= GOOD:
		sticker = "ГОДНО"
	result_sticker.text = "%s   %d%%" % [sticker, int(round(overall * 100.0))]
	var lines: Array = []
	for key in ORDER:
		lines.append("%s: %d%%" % [PARAMS[key]["label"], int(round(float(comps[key]) * 100.0))])
	result_detail.text = "\n".join(lines)
	result_panel.visible = true

# ---------- вспомогательное ----------
func _random_values() -> Dictionary:
	var v: Dictionary = {}
	for key in ORDER:
		var p: Dictionary = PARAMS[key]
		var steps: int = int((float(p["max"]) - float(p["min"])) / float(p["step"]))
		v[key] = float(p["min"]) + float(p["step"]) * float(randi() % (steps + 1))
	return v

func _current_values() -> Dictionary:
	var v: Dictionary = {}
	for key in ORDER:
		v[key] = sliders[key].value
	return v

func _apply_to_jar(vals: Dictionary) -> void:
	var vp: Dictionary = PARAMS["volume"]
	var fill: float = (float(vals["volume"]) - float(vp["min"])) / (float(vp["max"]) - float(vp["min"]))
	var bp: Dictionary = PARAMS["bsize"]
	var bfrac: float = (float(vals["bsize"]) - float(bp["min"])) / (float(bp["max"]) - float(bp["min"]))
	jar.set_potion(float(vals["color"]), fill, int(vals["count"]), bfrac, seed_val)

func _on_slider_changed(_value: float, key: String) -> void:
	if phase != "recreate":
		return
	_apply_to_jar(_current_values())
	value_labels[key].text = _fmt(key, sliders[key].value)

func _update_value_labels(vals: Dictionary) -> void:
	for key in ORDER:
		value_labels[key].text = _fmt(key, float(vals[key]))

func _fmt(key: String, value: float) -> String:
	return "%d%s" % [int(round(value)), PARAMS[key]["suffix"]]

func _set_sliders_interactable(on: bool) -> void:
	for key in ORDER:
		sliders[key].editable = on
		sliders[key].modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.45)
