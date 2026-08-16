extends RefCounted
class_name NpcMech
## Каркас уникальных механик гостей (аналог LEVEL4_FX из браузерной версии).
## Механика — подкласс NpcMech, переопределяет нужные хуки. Активна, если
## GameData.mech_active(id, level) (= level==4 или id ∈ MECH_FROM_L1).
##
## Хуки получают `g` — узел игры (main.gd): через него доступно состояние раунда
## (g.npc, g.level, g.active, g.target, g.sliders, g.PARAMS, g.jar ...).

# --- жизненный цикл заказа ---
func setup(_g) -> void: pass            # сразу после конфигурации ползунков (до показа)
func memorize_start(_g) -> void: pass   # начало фазы «ЗАПОМНИ»
func craft_start(_g) -> void: pass      # начало фазы «ВОССОЗДАЙ»
func process(_g, _delta: float) -> void: pass  # каждый кадр фазы «ВОССОЗДАЙ» (таймеры/анимация)
func on_done(_g) -> bool: return true   # нажата «ГОТОВО»; false = НЕ финишировать (Гурман)
func pre_serve(_g) -> void: pass        # перед отъездом банки (детали Роя уезжают внутри неё)
func skip_memorize(_g) -> bool: return false   # true = без фазы показа (Инспектор — цель в тексте)
func no_timer(_g) -> bool: return false        # true = без таймеров фаз (Тот-Кто-Ждёт)
func blocks_points(_g, _overall: float) -> bool: return false  # true = рейтинг не начислять (Тот-Кто-Ждёт при <99%)
func stop(_g) -> void: pass             # конец раунда (уборка)

# --- влияние на скоринг/результат ---
func weight_for(_key: String, base: float) -> float: return base   # вес параметра в оценке
func score_bonus(_g) -> float: return 1.0                          # множитель рейтинга (≥1; racer/apoth/janitor)
func override_overall(_g) -> float: return -1.0                    # ≥0 = заменить общий результат (Коллекционер)
func result_note(_g) -> String: return ""                          # строка-пояснение на результате

# Общая «большая стрелка справа» (переключатель/подтверждение) — плавает поверх
# round_ui у правого края. cb — что делать по нажатию.
static func make_arrow_btn(g, cb: Callable, anchor_y: float = 0.62) -> Button:
	var b := Button.new()
	b.text = "▸"
	b.add_theme_font_size_override("font_size", 72)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.12, 0.10, 0.9)
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.90, 0.72, 0.42)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	b.pressed.connect(cb)
	g.add_child(b)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = anchor_y
	b.anchor_bottom = anchor_y
	b.offset_left = -150.0
	b.offset_right = -30.0
	b.offset_top = -60.0
	b.offset_bottom = 60.0
	return b

# ---------- реестр реализованных механик ----------
static func make(id: String) -> NpcMech:
	match id:
		"tentacloid": return TentacloidMech.new()
		"trucker_chrome": return TruckerMech.new()
		"fashionista": return FashionMech.new()
		"archivist": return ArchivistMech.new()
		"catlady": return CatladyMech.new()
		"logic9": return LogicMech.new()
		"racer_kai": return RacerMech.new()
		"apothecary_mo": return ApothecaryMech.new()
		"janitor": return JanitorMech.new()
		"marketer": return MarketerMech.new()
		"dj_pulsar": return DjMech.new()
		"drone": return DroneMech.new()
		"perfumer": return PerfumerMech.new()
		"gourmet_vega": return GourmetMech.new()
		"swarm_navigator": return SwarmMech.new()
		"guild_inspector": return InspectorMech.new()
		"engineer": return EngineerMech.new()
		"collector_gz": return CollectorMech.new()
		"vex": return VexMech.new()
		"supernova_child": return SupernovaMech.new()
		"the_waiter": return WaiterMech.new()
		"twofaced_priestess": return TwofacedMech.new()
		"plasma_bartender": return PlasmaMech.new()
		"pete": return PeteMech.new()
		_: return null

# ============================================================
# Тентаклоид: считается только ОДИН случайный активный параметр (вес остальных
# = 0). Какой именно — раскрывается на экране результата.
# ============================================================
class TentacloidMech extends NpcMech:
	var counted: String = ""

	func setup(g) -> void:
		var a: Array = g.active
		if not a.is_empty():
			counted = a[randi() % a.size()]

	func weight_for(key: String, base: float) -> float:
		return base if key == counted else 0.0

	func result_note(g) -> String:
		if counted == "":
			return ""
		var label: String = g.PARAMS[counted]["label"]
		return "🐙 Щупальца оценивали только одно: %s" % label

# ============================================================
# Хромой Дальнобойщик: «коробка передач». Цвет остаётся обычным ползунком
# (левая колонка). Правая группа регуляторов (объём/сгустки/размер) заменяется
# на особый регулятор GearPath («рычаг КПП» — значение тянется по ломаной
# траектории). Виден и доступен по ОДНОМУ правому регулятору за раз, кнопка
# переключает «передачу» по кругу. Значения хранятся в исходных TouchSlider
# (оценка считает их как обычно). Порт TRUCKER_LEFT_KEYS / makeGearPathWidget.
# ============================================================
class TruckerMech extends NpcMech:
	const EXTRA_CRAFT_S := 4.0
	const LEFT_KEYS := ["color", "sat"]   # остаются обычными ползунками (TRUCKER_LEFT_KEYS)
	var g_ref                       # узел игры (main.gd)
	var keys: Array = []            # правые регуляторы (порядок ORDER), под КПП
	var gears: Dictionary = {}      # key -> GearPath
	var idx: int = 0
	var switch_btn: Button = null

	func craft_start(g) -> void:
		g_ref = g
		keys.clear()
		for k in g.ORDER:
			if k in g.active and not (k in LEFT_KEYS):
				keys.append(k)
		if keys.is_empty():
			return                  # нечего переводить в КПП — обычная игра
		g.phase_total += EXTRA_CRAFT_S
		g.phase_left += EXTRA_CRAFT_S
		# каждый правый регулятор → рычаг КПП поверх спрятанного слайдера
		for k in keys:
			_make_gear(k)
		idx = 0
		_show_only(idx)
		# переключатель передач — большая стрелка справа (только если правых >1)
		if keys.size() > 1:
			switch_btn = NpcMech.make_arrow_btn(g, _next_gear)

	func _make_gear(k: String) -> void:
		var col: VBoxContainer = g_ref.slider_cols[k]
		var s = g_ref.sliders[k]
		s.visible = false                          # прячем обычный слайдер
		var gear := GearPath.new()
		gear.custom_minimum_size = Vector2(300, 340)   # крупный тач-регулятор
		gear.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(gear)
		col.move_child(gear, s.get_index())        # на место слайдера (после ярлыка)
		gear.setup(s.min_value, s.max_value, s.step, s.value)
		gear.value_changed.connect(_on_gear.bind(k))
		gears[k] = gear

	# рычаг двигает значение → пишем в исходный слайдер и обновляем банку/ярлык
	func _on_gear(v: float, k: String) -> void:
		g_ref.sliders[k].set_value_no_signal(v)
		g_ref._on_slider_changed(v, k)

	func _show_only(i: int) -> void:
		for j in keys.size():
			g_ref.slider_cols[keys[j]].visible = (j == i)

	func _next_gear() -> void:
		idx = (idx + 1) % keys.size()
		_show_only(idx)
		Sfx.play("uiClick")

	func stop(g) -> void:
		if switch_btn != null and is_instance_valid(switch_btn):
			switch_btn.queue_free()
		switch_btn = null
		for k in gears:
			var gear = gears[k]
			if is_instance_valid(gear):
				gear.queue_free()
			if g.sliders.has(k):
				g.sliders[k].visible = true
			if g.slider_cols.has(k):
				g.slider_cols[k].visible = true
		gears.clear()

	func result_note(_g) -> String:
		if keys.is_empty():
			return ""
		return "🚚 Коробка передач: регуляторы — рычагами по одному"

# ============================================================
# Модница: в фазе ВОССОЗДАЙ доступен только ОДИН ползунок за раз; кнопка-стрелка
# идёт по перемешанному кругу (каждый посещается 1 раз за круг). На УР.4 «Дальше»
# не пустит, пока текущий не выставлен ИДЕАЛЬНО (порт fashionista/l4FashionNextKey).
# Остальные ползунки видны (банка полная), но заблокированы.
# ============================================================
class FashionMech extends NpcMech:
	const DIM := Color(1, 1, 1, 0.4)
	const PERFECT := 0.98
	var g_ref
	var order: Array = []
	var idx: int = 0
	var btn: Button = null

	func craft_start(g) -> void:
		g_ref = g
		order = (g.active as Array).duplicate()
		if order.size() <= 1:
			return                  # переключать нечего
		order.shuffle()
		idx = 0
		_apply_locks()
		btn = NpcMech.make_arrow_btn(g, _next)

	func _apply_locks() -> void:
		for k in order:
			var s = g_ref.sliders[k]
			var on: bool = (k == order[idx])
			s.editable = on
			s.modulate = Color(1, 1, 1, 1) if on else DIM

	func _next() -> void:
		# УР.4: не пустит дальше, пока текущий не идеален
		if g_ref.level == 4 and g_ref._key_score(order[idx]) < PERFECT:
			g_ref._toast.call_deferred("👗 Модница: сначала доведи до идеала!", Color("ff9a6a"))
			Sfx.play("badPop")
			return
		idx = (idx + 1) % order.size()
		_apply_locks()
		Sfx.play("uiClick")

	func stop(g) -> void:
		if btn != null and is_instance_valid(btn):
			btn.queue_free()
		btn = null
		for k in order:
			if g.sliders.has(k):
				g.sliders[k].editable = true
				g.sliders[k].modulate = Color(1, 1, 1, 1)
		order.clear()

	func result_note(_g) -> String:
		if order.size() <= 1:
			return ""
		return "👗 Модница: по одному регулятору за раз"

# ============================================================
# Хранитель Архива (УР.4): каждые 5с «запечатывает» (блокирует) ОДИН ползунок.
# Первый — случайный; далее — только уже выставленный ВЕРНО (score ≥ 0.9), по
# кругу среди верных; если верных нет — печати нет (все свободны).
# Порт LEVEL4_FX.archivist / archivistReseal.
# ============================================================
class ArchivistMech extends NpcMech:
	const PERIOD := 5.0
	const CORRECT := 0.9
	var g_ref
	var keys: Array = []
	var sealed_key: String = ""
	var last_correct: String = ""
	var acc: float = 0.0
	var rain: MatrixRain = null

	# фирменный дождь глифов — уже в фазе показа (мешает разглядеть смесь)
	func memorize_start(g) -> void:
		rain = MatrixRain.new()
		g.jar_stage.add_child(rain)          # поверх банки, на всю область сцены

	func craft_start(g) -> void:
		g_ref = g
		keys = (g.active as Array).duplicate()
		acc = 0.0
		sealed_key = ""
		last_correct = ""
		if rain == null:                     # страховка, если показ был пропущен
			memorize_start(g)
		_reseal(true)

	func process(_g, delta: float) -> void:
		acc += delta
		if acc >= PERIOD:
			acc -= PERIOD
			_reseal(false)

	func _reseal(first: bool) -> void:
		_unseal()
		var next_key: String = ""
		if first:
			next_key = keys[randi() % keys.size()]
		else:
			var correct: Array = []
			for k in keys:
				if g_ref._key_score(k) >= CORRECT:
					correct.append(k)
			if not correct.is_empty():
				var pi: int = correct.find(last_correct)
				next_key = correct[(pi + 1) % correct.size()]
		if next_key == "":
			return                  # ни один не выставлен верно — печати нет
		sealed_key = next_key
		last_correct = next_key
		var s = g_ref.sliders[sealed_key]
		s.editable = false
		s.modulate = Color(0.65, 0.68, 0.85, 0.85)
		_name_label(sealed_key).text = "🔒 " + g_ref.PARAMS[sealed_key]["label"]
		Sfx.play("dock")             # печать «щёлкает»

	func _unseal() -> void:
		if sealed_key == "":
			return
		if g_ref.sliders.has(sealed_key):
			var s = g_ref.sliders[sealed_key]
			s.editable = true
			s.modulate = Color(1, 1, 1, 1)
			_name_label(sealed_key).text = g_ref.PARAMS[sealed_key]["label"]
		sealed_key = ""

	func _name_label(k: String) -> Label:
		return g_ref.slider_cols[k].get_child(0) as Label   # ярлык — первый в колонке

	func stop(_g) -> void:
		_unseal()
		if rain != null and is_instance_valid(rain):
			rain.queue_free()
		rain = null

	func result_note(_g) -> String:
		return "📜 Хранитель Архива: печати сходят с верно выставленных"

# ============================================================
# Бабушка Мурра: на фазе ВОССОЗДАЙ на ползунки лезут кошачьи лапы и НЕ уходят
# сами — согнать серией из 3 быстрых тапов. Согнанная возвращается через паузу;
# больше лап и короче пауза с уровнем. Скоринг не трогает — чистая помеха.
# Порт LEVEL4_FX.catlady.
# ============================================================
class CatladyMech extends NpcMech:
	const MAX_BY_LVL := {1: 1, 2: 2, 3: 2, 4: 3}
	const RETURN_BY_LVL := {1: 5.2, 2: 4.2, 3: 3.4, 4: 2.6}   # секунды до докидывания
	var g_ref
	var max_paws: int = 1
	var interval: float = 4.2
	var acc: float = 0.0
	var paws: Dictionary = {}          # key -> CatPaw

	func craft_start(g) -> void:
		g_ref = g
		max_paws = int(MAX_BY_LVL.get(g.level, 2))
		interval = float(RETURN_BY_LVL.get(g.level, 4.2))
		acc = 0.0
		for i in max_paws:
			_spawn_one()

	func process(_g, delta: float) -> void:
		acc += delta
		if acc >= interval:
			acc = 0.0
			if paws.size() < max_paws:
				_spawn_one()

	func _spawn_one() -> void:
		# свободный видимый ползунок (ещё не накрытый)
		var free: Array = []
		for k in g_ref.active:
			if not paws.has(k):
				free.append(k)
		if free.is_empty():
			return
		var key: String = free[randi() % free.size()]
		var paw := CatPaw.new()
		paw.key = key
		g_ref.sliders[key].add_child(paw)   # поверх самого ползунка (перекрывает ввод)
		paw.shooed.connect(_on_shooed)
		paws[key] = paw

	func _on_shooed(key: String) -> void:
		if paws.has(key):
			var paw = paws[key]
			if is_instance_valid(paw):
				paw.queue_free()
			paws.erase(key)

	func stop(_g) -> void:
		for k in paws:
			if is_instance_valid(paws[k]):
				paws[k].queue_free()
		paws.clear()

	func result_note(_g) -> String:
		return "🐾 Бабушка Мурра: лапы лезут на регуляторы"

# ============================================================
# Логик-9: ползунки заменены СТЕППЕРОМ (▲/▼ по одному делению); +50% времени на
# варку (степпер медленнее свободного слайдера). Порт LEVEL4_FX.logic9 (база).
# УР.4-бонус «сбей сгустки» — TODO (нужен score_bonus + мини-игра).
# ============================================================
class LogicMech extends NpcMech:
	var g_ref
	var keys: Array = []
	var steppers: Dictionary = {}      # key -> VBoxContainer

	func craft_start(g) -> void:
		g_ref = g
		keys = (g.active as Array).duplicate()
		g.phase_total *= 1.5
		g.phase_left *= 1.5
		for k in keys:
			_make_stepper(k)

	func _make_stepper(k: String) -> void:
		var col: VBoxContainer = g_ref.slider_cols[k]
		var s = g_ref.sliders[k]
		s.visible = false
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(84, 300)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 10)
		var up := _step_btn("▲")
		var down := _step_btn("▼")
		up.pressed.connect(_step.bind(k, 1))
		down.pressed.connect(_step.bind(k, -1))
		box.add_child(up)
		box.add_child(down)
		col.add_child(box)
		col.move_child(box, s.get_index())   # на место слайдера
		steppers[k] = box

	func _step_btn(txt: String) -> Button:
		var b := Button.new()
		b.text = txt
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 120)
		b.add_theme_font_size_override("font_size", 40)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		return b

	func _step(k: String, dir: int) -> void:
		var s = g_ref.sliders[k]
		var v: float = clampf(s.value + dir * s.step, s.min_value, s.max_value)
		if not is_equal_approx(v, s.value):
			s.set_value_no_signal(v)
			g_ref._on_slider_changed(v, k)   # обновит банку/ярлык + тик
		else:
			Sfx.play("tick")

	func stop(g) -> void:
		for k in steppers:
			if is_instance_valid(steppers[k]):
				steppers[k].queue_free()
			if g.sliders.has(k):
				g.sliders[k].visible = true
		steppers.clear()

	func result_note(_g) -> String:
		return "🔢 Логик-9: только пошагово (▲/▼)"

# ============================================================
# Гонщица Кай: 3 гоночных чекпоинта по ходу таймера варки. На каждом замеряется
# текущий результат; если ≥0.55 — +5% к множителю рейтинга. Отсчёт «3…2…GO!» +
# лёгкая тряска банки. Порт LEVEL4_FX.racer_kai (scoreBonus = 0.05·пройдено).
# ============================================================
class RacerMech extends NpcMech:
	const MARKS := [0.33, 0.66, 0.9]      # доли времени варки
	const PASS := 0.55                     # порог зачёта чекпоинта
	var g_ref
	var idx: int = 0
	var done: int = 0
	var label: Label = null

	func craft_start(g) -> void:
		g_ref = g
		idx = 0
		done = 0
		label = Label.new()
		label.add_theme_font_size_override("font_size", 84)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.modulate = Color("35e0ff")
		label.set_anchors_preset(Control.PRESET_FULL_RECT)   # на всю сцену, текст по центру
		label.visible = false
		g.jar_stage.add_child(label)

	func process(g, _delta: float) -> void:
		var elapsed: float = g.phase_total - g.phase_left
		while idx < MARKS.size() and elapsed >= MARKS[idx] * g.phase_total:
			if g._current_overall() >= PASS:
				done += 1
			var is_last: bool = idx == MARKS.size() - 1
			_flash("GO!" if is_last else str(3 - idx))
			_shake(g)
			Sfx.play("countdown")
			idx += 1

	func _flash(text: String) -> void:
		if label == null:
			return
		label.text = text
		label.visible = true
		label.scale = Vector2(0.5, 0.5)
		label.pivot_offset = label.size * 0.5
		var t := label.create_tween()
		t.tween_property(label, "scale", Vector2(1.3, 1.3), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.35)
		t.tween_property(label, "modulate:a", 0.0, 0.3)
		t.tween_callback(_flash_done)

	func _flash_done() -> void:
		if label == null:
			return
		label.visible = false
		label.modulate.a = 1.0

	func _shake(g) -> void:
		var jar: Control = g.jar
		var t := jar.create_tween()
		t.tween_property(jar, "rotation", deg_to_rad(4.0), 0.04)
		t.tween_property(jar, "rotation", deg_to_rad(-4.0), 0.05)
		t.tween_property(jar, "rotation", 0.0, 0.05)

	func score_bonus(_g) -> float:
		return 1.0 + 0.05 * float(done)

	func stop(_g) -> void:
		if label != null and is_instance_valid(label):
			label.queue_free()
		label = null

	func result_note(_g) -> String:
		if done <= 0:
			return "🏁 Гонщица Кай: чекпоинты не взяты"
		return "🏁 Гонщица Кай: +%d%% рейтинга за %d чекпоинта" % [done * 5, done]

# ============================================================
# Аптекарь Мо: полоска «состояние пациента» тает со временем варки (зелёная→
# красная). Чем раньше финиш — тем больше остаток → бонус к рейтингу
# (scoreBonus = 1 + 0.5·остаток). Порт LEVEL4_FX.apothecary_mo.
# ============================================================
class ApothecaryMech extends NpcMech:
	var g_ref
	var bar: Panel = null
	var fill: ColorRect = null

	func craft_start(g) -> void:
		g_ref = g
		bar = Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.10, 0.16, 0.9)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.4, 0.42, 0.52)
		bar.add_theme_stylebox_override("panel", sb)
		g.add_child(bar)
		# у левого края, по вертикали над областью сцены
		bar.anchor_left = 0.0
		bar.anchor_right = 0.0
		bar.anchor_top = 0.28
		bar.anchor_bottom = 0.72
		bar.offset_left = 16.0
		bar.offset_right = 40.0
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		fill = ColorRect.new()
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.offset_left = 3.0
		fill.offset_right = -3.0
		fill.offset_top = 3.0
		fill.offset_bottom = -3.0
		bar.add_child(fill)
		_update(1.0)

	func process(g, _delta: float) -> void:
		_update(clampf(g.phase_left / maxf(0.001, g.phase_total), 0.0, 1.0))

	func _update(frac: float) -> void:
		if fill == null:
			return
		# заполнение снизу: верхний отступ = (1-frac) высоты
		fill.anchor_top = 1.0 - frac
		fill.offset_top = 3.0
		# цвет: зелёный (полно) → красный (пусто)
		fill.color = Color.from_hsv(lerpf(0.0, 0.33, frac), 0.85, 0.95)

	func score_bonus(g) -> float:
		return 1.0 + 0.5 * clampf(g.phase_left / maxf(0.001, g.phase_total), 0.0, 1.0)

	func stop(_g) -> void:
		if bar != null and is_instance_valid(bar):
			bar.queue_free()
		bar = null
		fill = null

	func result_note(g) -> String:
		var pct: int = int(round(50.0 * clampf(g.phase_left / maxf(0.001, g.phase_total), 0.0, 1.0)))
		return "💉 Аптекарь Мо: +%d%% рейтинга за скорость" % pct

# ============================================================
# Уборщик Пятого Дока: банка залита грязью (в обе фазы), оттираешь пальцем-губкой.
# Доля отмытого → бонус к рейтингу. Размер губки меньше с уровнем.
# Порт LEVEL4_FX.janitor (scoreBonus = 0.5·clean).
# ============================================================
class JanitorMech extends NpcMech:
	const SPONGE := {1: 70.0, 2: 58.0, 3: 50.0, 4: 42.0}
	var g_ref
	var grime: GrimeOverlay = null
	var final_clean: float = 0.0

	func memorize_start(g) -> void:
		g_ref = g
		grime = GrimeOverlay.new()
		grime.sponge_r = float(SPONGE.get(g.level, 55.0))
		g.jar_stage.add_child(grime)      # статичное пятно на всё окно

	func craft_start(g) -> void:
		g_ref = g
		if grime == null:
			memorize_start(g)
		else:
			grime.reset()                 # свежая грязь на фазу игры
		grime.refog_on = (g.level == 4)   # УР.4: экран снова пачкается со временем

	func score_bonus(_g) -> float:
		return 1.0 + 0.5 * (grime.clean_fraction() if grime != null else 0.0)

	func stop(_g) -> void:
		if grime != null and is_instance_valid(grime):
			final_clean = grime.clean_fraction()
			grime.queue_free()
		grime = null

	func result_note(_g) -> String:
		return "🧽 Уборщик: +%d%% рейтинга за чистоту" % int(round(50.0 * final_clean))

# ============================================================
# Маркетолог с безлюдного спутника: обычные ползунки прячутся; хаос-панель из ~10
# случайных контролов, где для каждого параметра работает РОВНО ОДИН, остальные —
# обманки. +50% времени. Скоринг обычный (банка — единственный фидбэк).
# Порт LEVEL4_FX.marketer.
# ============================================================
class MarketerMech extends NpcMech:
	var g_ref
	var panel: PanelContainer = null

	func craft_start(g) -> void:
		g_ref = g
		g.phase_total *= 1.5
		g.phase_left *= 1.5
		for k in g.active:
			g.slider_cols[k].visible = false
		# спеки: по одному реальному контролу на активный параметр + обманки до ~10
		var specs: Array = []
		for k in g.active:
			specs.append({"real": true, "key": k, "type": _rand_type()})
		var decoys: int = maxi(6, 10 - g.active.size())
		for i in decoys:
			specs.append({"real": false, "key": "", "type": _rand_type()})
		specs.shuffle()
		# панель с сеткой контролов
		panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.11, 0.09, 0.92)
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(10.0)
		panel.add_theme_stylebox_override("panel", sb)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		panel.add_child(grid)
		for spec in specs:
			grid.add_child(_make_ctrl(spec))
		g.round_ui.add_child(panel)
		g.round_ui.move_child(panel, g.done_btn.get_index())

	func _rand_type() -> String:
		return ["stepper", "slider"][randi() % 2]

	# ячейка фиксированного размера с контролом; реальный пишет в слайдер, обманка — no-op
	func _make_ctrl(spec: Dictionary) -> Control:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(120, 120)
		var real: bool = spec["real"]
		var key: String = spec["key"]
		if spec["type"] == "slider":
			var hs := HSlider.new()
			hs.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
			hs.offset_left = 6.0
			hs.offset_right = -6.0
			if real:
				var s = g_ref.sliders[key]
				hs.min_value = s.min_value
				hs.max_value = s.max_value
				hs.step = s.step
				hs.value = s.value
				hs.value_changed.connect(_on_real_val.bind(key))
			else:
				hs.min_value = 0.0
				hs.max_value = 100.0
				hs.value = randf() * 100.0
				hs.value_changed.connect(_on_decoy)
			cell.add_child(hs)
		else:
			var box := VBoxContainer.new()
			box.set_anchors_preset(Control.PRESET_FULL_RECT)
			box.alignment = BoxContainer.ALIGNMENT_CENTER
			var up := _mk_btn("▲")
			var dn := _mk_btn("▼")
			if real:
				up.pressed.connect(_on_real_step.bind(key, 1))
				dn.pressed.connect(_on_real_step.bind(key, -1))
			else:
				up.pressed.connect(_on_decoy_btn)
				dn.pressed.connect(_on_decoy_btn)
			box.add_child(up)
			box.add_child(dn)
			cell.add_child(box)
		return cell

	func _mk_btn(txt: String) -> Button:
		var b := Button.new()
		b.text = txt
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(100, 48)
		b.add_theme_font_size_override("font_size", 24)
		return b

	func _on_real_val(v: float, key: String) -> void:
		g_ref.sliders[key].set_value_no_signal(v)
		g_ref._on_slider_changed(v, key)

	func _on_real_step(key: String, dir: int) -> void:
		var s = g_ref.sliders[key]
		var v: float = clampf(s.value + dir * s.step, s.min_value, s.max_value)
		if not is_equal_approx(v, s.value):
			s.set_value_no_signal(v)
			g_ref._on_slider_changed(v, key)
		else:
			Sfx.play("tick")

	func _on_decoy(_v: float) -> void:
		Sfx.play("uiClick")

	func _on_decoy_btn() -> void:
		Sfx.play("uiClick")

	func stop(g) -> void:
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
		panel = null
		for k in g.active:
			if g.slider_cols.has(k):
				g.slider_cols[k].visible = true

	func result_note(_g) -> String:
		return "📰 Маркетолог: настоящий регулятор — один из многих"

# ============================================================
# Диджей Пульсар: механики-игры нет — на его заказ идёт бит (синтезируется, без
# ассета) и весь интерфейс пульсирует в такт. Скоринг не трогает.
# Порт LEVEL4_FX.dj_pulsar (гравитация ползунков УР.4 — TODO).
# ============================================================
class DjMech extends NpcMech:
	const BEAT := 0.5                  # период бита, с
	var g_ref
	var acc: float = 0.0
	var player: AudioStreamPlayer = null

	func craft_start(g) -> void:
		g_ref = g
		acc = BEAT                       # первый удар почти сразу
		player = AudioStreamPlayer.new()
		player.bus = "SFX"
		player.stream = _make_kick()
		g.add_child(player)

	func process(g, delta: float) -> void:
		acc += delta
		if acc >= BEAT:
			acc -= BEAT
			if player != null:
				player.play()
			_pulse(g)

	func _pulse(g) -> void:
		_pop(g.jar)
		for k in g.active:
			_pop(g.slider_cols[k])

	func _pop(n: Control) -> void:
		if n == null or not is_instance_valid(n):
			return
		n.pivot_offset = n.size * 0.5
		var t := n.create_tween()
		t.tween_property(n, "scale", Vector2(1.06, 1.06), 0.11).set_trans(Tween.TRANS_SINE)
		t.tween_property(n, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE)

	# синтез кика: синус 140→46 Гц с экспоненциальным затуханием (аналог l4DjKick)
	func _make_kick() -> AudioStreamWAV:
		var sr := 22050
		var dur := 0.18
		var n := int(sr * dur)
		var data := PackedByteArray()
		data.resize(n * 2)
		var phase := 0.0
		for i in n:
			var t := float(i) / float(sr)
			var f := 140.0 * pow(46.0 / 140.0, t / dur)
			phase += TAU * f / float(sr)
			var amp := exp(-t / (dur * 0.32))
			var s := sin(phase) * amp * 0.7
			data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = sr
		w.stereo = false
		w.data = data
		return w

	func stop(g) -> void:
		if player != null and is_instance_valid(player):
			player.queue_free()
		player = null
		# вернуть масштаб (узлы переиспользуются в следующих заказах)
		if is_instance_valid(g.jar):
			g.jar.scale = Vector2.ONE
		for k in g.active:
			if g.slider_cols.has(k) and is_instance_valid(g.slider_cols[k]):
				g.slider_cols[k].scale = Vector2.ONE

	func result_note(_g) -> String:
		return "🎧 Диджей Пульсар: бит на весь заказ"

# ============================================================
# Служебный дрон: в фазе ВОССОЗДАЙ внутри банки растут «плохие» пузыри — лопни
# тапом до взрыва. Не успел — пузырь сбивает случайный активный регулятор на
# деление. Порт badBubble* / droneBombsActive. Скоринг косвенно (через сбой).
# ============================================================
class DroneMech extends NpcMech:
	const MAX_BY_LVL := {1: 2, 2: 2, 3: 3, 4: 3}
	const GROW_BY_LVL := {1: 3.0, 2: 2.6, 3: 2.3, 4: 2.0}
	const SPAWN_BY_LVL := {1: 1.6, 2: 1.4, 3: 1.2, 4: 1.0}
	var g_ref
	var layer: Control = null
	var alive: Array = []
	var max_alive: int = 2
	var grow: float = 2.6
	var spawn_int: float = 1.4
	var acc: float = 0.0

	func craft_start(g) -> void:
		g_ref = g
		max_alive = int(MAX_BY_LVL.get(g.level, 2))
		grow = float(GROW_BY_LVL.get(g.level, 2.6))
		spawn_int = float(SPAWN_BY_LVL.get(g.level, 1.4))
		acc = spawn_int
		layer = Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE   # сам слой прозрачен, пузыри — нет
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.jar_stage.add_child(layer)

	func process(_g, delta: float) -> void:
		acc += delta
		if acc >= spawn_int and alive.size() < max_alive:
			acc = 0.0
			_spawn()

	func _spawn() -> void:
		if layer == null or layer.size.x <= 0.0:
			return
		var b := BadBubble.new()
		b.grow = grow
		var x: float = randf_range(0.30, 0.70) * layer.size.x - BadBubble.R1
		var y: float = randf_range(0.42, 0.82) * layer.size.y - BadBubble.R1
		b.position = Vector2(x, y)
		layer.add_child(b)
		b.cleared.connect(_on_cleared)
		b.burst.connect(_on_burst)
		alive.append(b)

	func _on_cleared(b) -> void:
		alive.erase(b)
		Sfx.play("badClear")
		if is_instance_valid(b):
			b.queue_free()

	func _on_burst(b) -> void:
		alive.erase(b)
		Sfx.play("badPop")
		_jitter()
		if is_instance_valid(b):
			b.queue_free()

	# сбить случайный активный регулятор на одно деление в случайную сторону
	func _jitter() -> void:
		if g_ref.active.is_empty():
			return
		var key: String = g_ref.active[randi() % g_ref.active.size()]
		var s = g_ref.sliders[key]
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		var v: float = clampf(s.value + dir * s.step, s.min_value, s.max_value)
		if is_equal_approx(v, s.value):
			v = clampf(s.value - dir * s.step, s.min_value, s.max_value)
		if not is_equal_approx(v, s.value):
			s.set_value_no_signal(v)
			g_ref._on_slider_changed(v, key)

	func stop(_g) -> void:
		alive.clear()
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
		layer = null

	func result_note(_g) -> String:
		return "🛠 Дрон: не лопнешь пузырь — собьёт регулятор"

# ============================================================
# Парфюмер: спектр и накал сведены в один 2D-пэд (X=накал, Y=спектр) вместо двух
# ползунков. Накал у него активен на ВСЕХ уровнях (флаг hasSat в оригинале) —
# добавляем "sat" в active в setup. Порт LEVEL4_FX.perfumer.
# ============================================================
class PerfumerMech extends NpcMech:
	var g_ref
	var pad: ColorPad = null
	var col: VBoxContainer = null    # колонка-обёртка пэда (встаёт в ряд регуляторов)

	func setup(g) -> void:
		# накал — часть заказа Парфюмера на любом уровне
		if not ("sat" in g.active):
			g.active.append("sat")

	func craft_start(g) -> void:
		g_ref = g
		# прячем колонки спектра и накала — их заменяет квадратный пэд в том же ряду
		g.slider_cols["color"].visible = false
		g.slider_cols["sat"].visible = false
		var cs = g.sliders["color"]
		var ss = g.sliders["sat"]
		var row: HBoxContainer = g.slider_cols["color"].get_parent()   # ряд регуляторов
		col = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var lbl := Label.new()
		lbl.text = "Спектр × Накал"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lbl)
		pad = ColorPad.new()
		pad.custom_minimum_size = Vector2(248, 248)   # компактный квадрат
		pad.config(cs.min_value, cs.max_value, cs.step, ss.min_value, ss.max_value, ss.step, cs.value, ss.value)
		pad.changed.connect(_on_pad)
		col.add_child(pad)
		row.add_child(col)
		row.move_child(col, 0)                        # слева, где были цвет/накал

	func _on_pad(hue: float, sat: float) -> void:
		g_ref.sliders["color"].set_value_no_signal(hue)
		g_ref.sliders["sat"].set_value_no_signal(sat)
		g_ref._on_slider_changed(hue, "color")   # обновит банку (читает оба) + тик

	func stop(g) -> void:
		if col != null and is_instance_valid(col):
			col.queue_free()
		col = null
		pad = null
		if g.slider_cols.has("color"):
			g.slider_cols["color"].visible = true
		if g.slider_cols.has("sat"):
			g.slider_cols["sat"].visible = true

	func result_note(_g) -> String:
		return "🌸 Парфюмер: спектр × накал одним пэдом"

# ============================================================
# Гурман с Веги: «ГОТОВО» → «ДЕГУСТИРОВАТЬ». Первая суб-годнота НЕ завершает
# раунд — одна переигровка тем же таймером; дальше проба финиширует как есть.
# По таймеру раунд всегда завершается. Порт LEVEL4_FX.gourmet_vega (база).
# ============================================================
class GourmetMech extends NpcMech:
	var used_retry: bool = false

	func craft_start(g) -> void:
		used_retry = false
		g.done_btn.text = "ДЕГУСТИРОВАТЬ"

	func on_done(g) -> bool:
		if used_retry:
			return true                       # переигровка уже была — финишируем
		var tier: int = int(g.npc.get("tier", 1))
		var grade: String = GameData.grade(g._current_overall(), tier)
		if grade == "good" or grade == "perfect":
			return true
		# первая «какашка» — не финишируем, даём доделать
		used_retry = true
		g._toast.call_deferred("👅 Гурман морщится — доводи!", Color("ff9a6a"))
		Sfx.play("badPop")
		return false

	func stop(g) -> void:
		g.done_btn.text = "ГОТОВО!"

	func result_note(_g) -> String:
		return "👅 Гурман: одна дегустация-переигровка"

# ============================================================
# Навигатор Роя (игра на память): на «ЗАПОМНИ» в банке лежит НАБОР деталей — их надо
# запомнить. На старте «ВОССОЗДАЙ» они резко разлетаются за экран, а из-за краёв на
# стол и стены влетают ДЕСЯТКИ разных деталей. Задача — собрать в банку именно те,
# что были в образце (цвет/накал/объём — обычными ползунками). На УР.4 детали ещё и
# дрейфуют, как мухи. Собранные детали уезжают ВНУТРИ банки. Порт swarm_navigator.
# ============================================================
class SwarmMech extends NpcMech:
	# зона банки (куда собирать) в долях области сцены
	const ZX0 := 0.30
	const ZX1 := 0.70
	const ZY0 := 0.42
	const ZY1 := 0.82
	# зоны «обитания» деталей (доли слоя): стол снизу + левая/правая стена — всё ВНЕ
	# зоны банки, ВНЕ окна (верх-центр) и ВНЕ ползунков (ниже jar_stage).
	var ZONES := [
		Rect2(0.08, 0.83, 0.84, 0.11),   # стол (нижняя полоса)
		Rect2(0.02, 0.30, 0.14, 0.52),   # левая стена
		Rect2(0.84, 0.30, 0.14, 0.52),   # правая стена
	]
	var g_ref
	var mem_layer: Control = null       # образец: детали внутри банки на «ЗАПОМНИ»
	var layer: Control = null           # разлетевшиеся детали на «ВОССОЗДАЙ»
	var mem_parts: Array = []
	var parts: Array = []
	var targets: Array = []             # сигнатуры деталей, которые надо собрать
	var served: Array = []              # детали, уехавшие внутри банки (для уборки)
	var n_target: int = 4
	var drift_timer: Timer = null
	var final_acc: float = 0.0

	func setup(g) -> void:
		g.active.erase("count")          # «сгустки» и «размер» — это детали, не ползунки
		g.active.erase("bsize")

	func _all_sigs() -> Array:
		var a: Array = []
		for sh in DragPart.N_SHAPE:
			for ti in DragPart.N_COLOR:
				a.append(sh * 10 + ti)
		return a

	func memorize_start(g) -> void:
		g_ref = g
		n_target = clampi(int(g.target["count"]), 3, 7)
		g.target["count"] = 0                      # жидких сгустков нет — «начинка» = детали
		g.sliders["count"].set_value_no_signal(0.0)
		g._apply_to_jar(g.target)                  # перерисовать банку без сгустков
		var pool := _all_sigs(); pool.shuffle()
		targets = pool.slice(0, n_target)
		# показать цели ВНУТРИ банки — вразброс по объёму жидкости (как сгустки), не рядами
		mem_layer = Control.new()
		mem_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mem_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.jar_stage.add_child(mem_layer)
		var sz: Vector2 = g.jar_stage.size
		var placed: Array = []          # уже расставленные центры (для разнесения)
		for i in n_target:
			var mp := DragPart.new()
			mp.set_signature(int(targets[i]) / 10, int(targets[i]) % 10)
			mem_layer.add_child(mp)                        # _ready() ставит size/STOP
			mp.mouse_filter = Control.MOUSE_FILTER_IGNORE  # образец не таскаем (после _ready)
			mp.scale = Vector2(0.82, 0.82)                 # чуть мельче — «сгустки» в узком горле
			# rejection sampling: случайная точка в зоне жидкости, подальше от прочих
			var best := Vector2(0.5 * sz.x, 0.6 * sz.y)
			for _attempt in 14:
				var cand := Vector2(randf_range(0.42, 0.58) * sz.x, randf_range(0.50, 0.72) * sz.y)
				best = cand
				var ok := true
				for pp in placed:
					if cand.distance_to(pp) < 40.0:
						ok = false
						break
				if ok:
					break
			placed.append(best)
			mp.position = best - mp.size * 0.5
			mem_parts.append(mp)

	func craft_start(g) -> void:
		g_ref = g
		g.phase_total += 3.0
		g.phase_left += 3.0
		g.target["count"] = 0                       # никаких жидких сгустков — «начинка» = детали
		g.sliders["count"].set_value_no_signal(0.0)
		g._apply_to_jar(g._current_values())        # перерисовать банку пустой (без сгустков)
		var sz: Vector2 = g.jar_stage.size
		# 1) детали образца резко разлетаются за пределы экрана
		for mp in mem_parts:
			var dir: Vector2 = (mp.center() - sz * 0.5)
			dir = dir.normalized() if dir.length() > 1.0 else Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			var tw: Tween = mp.create_tween()
			tw.tween_property(mp, "position", mp.position + dir * sz.length(), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(mp.queue_free)
		mem_parts.clear()
		# 2) из-за краёв влетают десятки деталей: цели + обманки, почти все уникальны
		layer = Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.jar_stage.add_child(layer)
		var decoys := _all_sigs()
		decoys.shuffle()
		var pool: Array = targets.duplicate()          # все цели по одному разу
		var want: int = clampi(n_target + 12, 16, 24)  # «несколько десятков» разных
		for s in decoys:
			if pool.size() >= want:
				break
			if not (s in targets):
				pool.append(s)
		pool.shuffle()
		for i in pool.size():
			var part := DragPart.new()
			part.set_signature(int(pool[i]) / 10, int(pool[i]) % 10)
			var zone: Rect2 = ZONES[i % ZONES.size()]
			part.home_zone = zone
			var dst := _rand_in_zone(zone, sz)
			var start := dst
			if zone.position.x < 0.2: start.x = -80.0          # влетает слева
			elif zone.position.x > 0.7: start.x = sz.x + 80.0  # справа
			else: start.y = sz.y + 90.0                        # снизу (стол)
			part.position = start - part.size * 0.5
			layer.add_child(part)
			part.dropped.connect(_on_dropped)
			parts.append(part)
			var tw2: Tween = part.create_tween()
			tw2.tween_interval(0.02 * float(i))
			tw2.tween_property(part, "position", dst - part.size * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# УР.4: детали дрейфуют по своим зонам, как мухи (сложнее поймать)
		if g.level == 4:
			drift_timer = Timer.new()
			drift_timer.wait_time = 0.62
			drift_timer.timeout.connect(_drift)
			layer.add_child(drift_timer)
			drift_timer.start()

	# случайная точка-ЦЕНТР детали в зоне (доли → пиксели слоя)
	func _rand_in_zone(zone: Rect2, sz: Vector2) -> Vector2:
		var fx: float = zone.position.x + randf() * zone.size.x
		var fy: float = zone.position.y + randf() * zone.size.y
		return Vector2(fx * sz.x, fy * sz.y)

	# УР.4: мелкими шагами гоняем непойманные детали внутри их зоны (плавно тви́ном)
	func _drift() -> void:
		if layer == null or layer.size.x <= 0.0:
			return
		var sz: Vector2 = layer.size
		for p in parts:
			if p.is_dragging() or _inside(p):
				continue
			var z: Rect2 = p.home_zone
			var cur: Vector2 = p.center()
			var nc := cur + Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
			nc.x = clampf(nc.x, z.position.x * sz.x, (z.position.x + z.size.x) * sz.x)
			nc.y = clampf(nc.y, z.position.y * sz.y, (z.position.y + z.size.y) * sz.y)
			var tw: Tween = p.create_tween()
			tw.tween_property(p, "position", nc - p.size * 0.5, 0.5).set_trans(Tween.TRANS_SINE)

	func _inside(part) -> bool:
		if layer == null or layer.size.x <= 0.0:
			return false
		var c: Vector2 = part.center()
		var xf: float = c.x / layer.size.x
		var yf: float = c.y / layer.size.y
		return xf >= ZX0 and xf <= ZX1 and yf >= ZY0 and yf <= ZY1

	func _on_dropped(part) -> void:
		Sfx.play("blobSnap" if _inside(part) else "tick")

	# точность: доля верных целей в банке минус штраф за лишние (обманки)
	func _accuracy() -> float:
		if targets.is_empty():
			return 1.0
		var tset := {}
		for s in targets:
			tset[int(s)] = true
		var matched := {}
		var wrong: int = 0
		for p in parts:
			if _inside(p):
				var s: int = p.sig()
				if tset.has(s):
					matched[s] = true
				else:
					wrong += 1
		return clampf((float(matched.size()) - 0.5 * float(wrong)) / float(targets.size()), 0.0, 1.0)

	# перед отъездом: считаем точность и переносим собранные детали ВНУТРЬ банки,
	# чтобы они уехали вместе с ней (как сгустки у других). Лишние — убираем.
	func pre_serve(g) -> void:
		final_acc = _accuracy()
		for p in parts:
			if is_instance_valid(p) and _inside(p):
				p.reparent(g.jar)          # keep_global_transform → останется на месте, поедет с банкой
				served.append(p)
			elif is_instance_valid(p):
				p.queue_free()
		parts.clear()

	func override_overall(g) -> float:
		# 0.55·(цвет/накал/объём) + 0.45·(верно собранные детали)
		return 0.55 * g._current_overall() + 0.45 * final_acc

	func stop(_g) -> void:
		drift_timer = null
		for p in served:
			if is_instance_valid(p):
				p.queue_free()
		served.clear()
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
		layer = null
		if mem_layer != null and is_instance_valid(mem_layer):
			mem_layer.queue_free()
		mem_layer = null
		parts.clear()
		mem_parts.clear()

	func result_note(_g) -> String:
		return "🐝 Навигатор Роя: собрано верных деталей — %d%%" % int(round(final_acc * 100.0))

# ============================================================
# Инспектор Гильдии: фазы показа НЕТ — цель описана в листе «Допуски» (значения
# как «№X из N» по делениям ползунка). Кнопка открывает текст; время варки ×2.
# Порт LEVEL4_FX.guild_inspector (загадка-допрос УР.4 — TODO).
# ============================================================
class InspectorMech extends NpcMech:
	var g_ref
	var btn: Button = null
	var panel: PanelContainer = null

	func skip_memorize(_g) -> bool:
		return true

	func craft_start(g) -> void:
		g_ref = g
		g.phase_total *= 2.0                # читать дольше, чем смотреть
		g.phase_left *= 2.0
		_build_panel(g)
		# кнопка «ДОПУСКИ» — сверху, открывает/прячет лист
		btn = Button.new()
		btn.text = "📋 ДОПУСКИ"
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(_toggle)
		g.add_child(btn)
		btn.anchor_left = 0.5
		btn.anchor_right = 0.5
		btn.anchor_top = 0.0
		btn.anchor_bottom = 0.0
		btn.offset_left = -100.0
		btn.offset_right = 100.0
		btn.offset_top = 150.0
		btn.offset_bottom = 202.0
		panel.visible = true                # сразу показываем — это и есть «показ»

	func _spec_text() -> String:
		var lines: Array = []
		for k in g_ref.active:
			var s = g_ref.sliders[k]
			var steps: int = int(round((s.max_value - s.min_value) / s.step))
			var n: int = steps + 1
			var idx: int = int(round((float(g_ref.target[k]) - s.min_value) / s.step))
			lines.append("• %s — №%d из %d" % [g_ref.PARAMS[k]["label"], idx + 1, n])
		return "\n".join(lines)

	func _build_panel(g) -> void:
		panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.11, 0.16, 0.97)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.90, 0.72, 0.42)
		sb.set_content_margin_all(22.0)
		panel.add_theme_stylebox_override("panel", sb)
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.anchor_left = 0.5; panel.anchor_right = 0.5
		panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
		panel.offset_left = -220.0; panel.offset_right = 220.0
		panel.offset_top = -180.0; panel.offset_bottom = 180.0
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 14)
		panel.add_child(col)
		var title := Label.new()
		title.text = "ДОПУСКИ ГИЛЬДИИ"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Color("ffcf5d"))
		col.add_child(title)
		var body := Label.new()
		body.text = _spec_text() + "\n\n(допуск ±1 деление)"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 20)
		col.add_child(body)
		var close := Button.new()
		close.text = "Скрыть"
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(_toggle)
		col.add_child(close)
		g.add_child(panel)

	func _toggle() -> void:
		if panel != null:
			panel.visible = not panel.visible
			Sfx.play("uiClick")

	func stop(_g) -> void:
		if btn != null and is_instance_valid(btn):
			btn.queue_free()
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
		btn = null
		panel = null

	func result_note(_g) -> String:
		return "📋 Инспектор: сверял по «Допускам»"

# ============================================================
# Инженер навигатора: фазы показа нет — цель показана ЗОНАМИ на треках. Ползунок
# не тянется: по треку синусоидой бегает указатель, «СТОП» фиксирует значение =
# его позиция. Оценка обычная (по близости). Порт LEVEL4_FX.engineer.
# Красная зона-ловушка (УР.4) — TODO.
# ============================================================
class EngineerMech extends NpcMech:
	const PERIOD := {1: 2.2, 2: 1.9, 3: 1.6, 4: 1.4}
	var g_ref
	var tracks: Dictionary = {}     # key -> EngTrack
	var btns: Array = []

	func skip_memorize(_g) -> bool:
		return true

	func craft_start(g) -> void:
		g_ref = g
		var per: float = float(PERIOD.get(g.level, 1.9))
		for k in g.active:
			_make_track(k, per)

	func _make_track(k: String, per: float) -> void:
		var col: VBoxContainer = g_ref.slider_cols[k]
		var s = g_ref.sliders[k]
		s.visible = false
		var track := EngTrack.new()
		track.custom_minimum_size = s.custom_minimum_size
		track.setup(s.min_value, s.max_value, s.step, float(g_ref.target[k]), per)
		col.add_child(track)
		col.move_child(track, s.get_index())
		track.fixed.connect(_on_fixed.bind(k))
		var btn := Button.new()
		btn.text = "СТОП"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(_stop_track.bind(track, btn))
		col.add_child(btn)
		tracks[k] = track
		btns.append(btn)

	func _stop_track(track, btn) -> void:
		track.fix()
		btn.disabled = true
		Sfx.play("uiClick")

	func _on_fixed(value: float, k: String) -> void:
		g_ref.sliders[k].set_value_no_signal(value)
		g_ref._on_slider_changed(value, k)

	func stop(g) -> void:
		for b in btns:
			if is_instance_valid(b):
				b.queue_free()
		btns.clear()
		for k in tracks:
			if is_instance_valid(tracks[k]):
				tracks[k].queue_free()
			if g.sliders.has(k):
				g.sliders[k].visible = true
		tracks.clear()

	func result_note(_g) -> String:
		return "🎯 Инженер: лови указатель кнопкой «СТОП»"

# ============================================================
# Коллекционер Гз: регуляторов нет — сетка готовых зелий, найди совпадающее с
# образцом (по спектру и числу сгустков). Верно → идеал, иначе → брак. Фаза
# показа обычная (образец запоминаем). Порт LEVEL4_FX.collector_gz.
# ============================================================
class CollectorMech extends NpcMech:
	const N_BY_LVL := {1: 4, 2: 9, 3: 16, 4: 16}
	var g_ref
	var overlay: Control = null
	var chosen_correct: bool = false

	# отступ сетки от верха (лампы + надпись фазы) и снизу — банки не лезут на них
	const TOP_RESERVE := 260.0
	const BOT_RESERVE := 64.0
	const SIDE_MARGIN := 28.0
	const GAP := 10.0
	const JAR_ASPECT := 215.0 / 385.0   # пропорции банки из potion_jar.tscn (ш/в)

	func craft_start(g) -> void:
		g_ref = g
		# прячем обычную игру — ни ползунков, ни банки, ни «Готово»
		for k in g.ORDER:
			g.slider_cols[k].visible = false
		g.done_btn.visible = false
		g.jar_stage.visible = false
		var n: int = int(N_BY_LVL.get(g.level, 9))
		var cols: int = int(ceil(sqrt(float(n))))
		var rows: int = int(ceil(float(n) / float(cols)))
		# параметры образца
		var tcolor: float = float(g.target["color"])
		var tcount: int = int(g.target["count"])
		var correct_idx: int = randi() % n
		# размер ячейки считаем от доступной области (низ экрана под шапкой), а не
		# фиксированно — иначе на сетке 4×4 банки не вмещаются и лезут из блоков.
		var vp: Vector2 = g.get_viewport_rect().size
		var avail_w: float = vp.x - SIDE_MARGIN * 2.0 - float(cols - 1) * GAP
		var avail_h: float = vp.y - TOP_RESERVE - BOT_RESERVE - float(rows - 1) * GAP
		var cw: float = avail_w / float(cols)
		var ch: float = avail_h / float(rows)
		# держим пропорции банки: берём ограничивающую сторону
		var w: float = minf(cw, ch * JAR_ASPECT)
		var cell := Vector2(floorf(w), floorf(w / JAR_ASPECT))
		# оверлей с сеткой, прижатой под шапку (лампы/надпись фазы)
		overlay = Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.add_child(overlay)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.offset_top = TOP_RESERVE
		center.offset_bottom = -BOT_RESERVE
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(center)
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", int(GAP))
		grid.add_theme_constant_override("v_separation", int(GAP))
		center.add_child(grid)
		for i in n:
			var is_correct: bool = (i == correct_idx)
			var cvals: Array = [tcolor, tcount] if is_correct else _decoy(tcolor, tcount)
			grid.add_child(_cell(cell, cvals[0], int(cvals[1]), is_correct))

	# ячейка = кнопка с мини-банкой (банка клипается по блоку — не вылезает)
	func _cell(cell: Vector2, color_v: float, count_v: int, is_correct: bool) -> Button:
		var btn := Button.new()
		btn.custom_minimum_size = cell
		btn.clip_contents = true
		btn.focus_mode = Control.FOCUS_NONE
		var jar = g_ref.PotionJarScene.instantiate()
		# сцена банки задаёт min 215×385 — в маленькой ячейке его надо снять, иначе
		# банка не ужимается до блока и вылезает за него.
		jar.custom_minimum_size = Vector2.ZERO
		jar.set_anchors_preset(Control.PRESET_FULL_RECT)
		jar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(jar)
		var vp: Dictionary = g_ref.PARAMS["volume"]
		var vsize: float = (float(g_ref.target["volume"]) - float(vp["min"])) / (float(vp["max"]) - float(vp["min"]))
		var bp: Dictionary = g_ref.PARAMS["bsize"]
		var bfrac: float = (float(g_ref.target["bsize"]) - float(bp["min"])) / (float(bp["max"]) - float(bp["min"]))
		jar.set_potion(color_v, vsize, count_v, bfrac, randi(), 0.72)
		btn.pressed.connect(_choose.bind(is_correct))
		return btn

	# near-miss: сдвигаем спектр и/или счётчик, но не оба в ноль (иначе = образец)
	func _decoy(tcolor: float, tcount: int) -> Array:
		var cs = g_ref.sliders["color"]
		var cc = g_ref.sliders["count"]
		var color_v: float = tcolor
		var count_v: int = tcount
		var mode: int = randi() % 3
		if mode != 1:
			color_v = fposmod(tcolor + [-2.0, -1.0, 1.0, 2.0][randi() % 4] * cs.step, cs.max_value + cs.step)
		if mode != 0:
			count_v = int(clampf(tcount + (1 if randf() < 0.5 else -1), cc.min_value, cc.max_value))
		if is_equal_approx(color_v, tcolor) and count_v == tcount:
			count_v = int(clampf(tcount + 1, cc.min_value, cc.max_value))
			if count_v == tcount:
				count_v = int(clampf(tcount - 1, cc.min_value, cc.max_value))
		return [color_v, count_v]

	func _choose(is_correct: bool) -> void:
		chosen_correct = is_correct
		Sfx.play("brew" if is_correct else "bad")
		g_ref._finish()

	func override_overall(_g) -> float:
		return 1.0 if chosen_correct else 0.2

	func stop(g) -> void:
		if overlay != null and is_instance_valid(overlay):
			overlay.queue_free()
		overlay = null
		for k in g.ORDER:
			if g.slider_cols.has(k):
				g.slider_cols[k].visible = (k in g.active)
		g.done_btn.visible = true
		g.jar_stage.visible = true

	func result_note(_g) -> String:
		return "🔍 Коллекционер: %s" % ("верная банка!" if chosen_correct else "не та банка")

# ============================================================
# Хирург-механик Векс: сгустки расставляются по узлам сетки внутри банки. На показе
# — целевая раскладка; на игре сгустки рассыпаны, тащишь каждый на узел. Оценка =
# 0.6·(обычные параметры) + 0.4·(доля верных позиций). Порт LEVEL4_FX.vex.
# ============================================================
class VexMech extends NpcMech:
	var g_ref
	var board: VexBoard = null
	var blobs: Array = []
	var target_nodes: Array = []
	var final_pos: float = 0.0

	func setup(g) -> void:
		g.active.erase("count")          # счёт задаётся раскладкой, не ползунком

	func memorize_start(g) -> void:
		g_ref = g
		board = VexBoard.new()
		g.jar_stage.add_child(board)
		board.build(g.jar_stage.size)
		var k: int = clampi(int(g.target["count"]), 1, 6)
		g.target["count"] = k
		g.sliders["count"].set_value_no_signal(float(k))
		g._apply_to_jar(g.target)        # банка показывает k сгустков (согласовано)
		# целевые узлы (случайные k из 9) — их и надо запомнить
		var idx: Array = range(board.nodes.size())
		idx.shuffle()
		target_nodes = idx.slice(0, k)
		for ti in target_nodes:
			var b := DragPart.new()
			board.add_child(b)
			b.set_kind(DragPart.BLOB)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # на показе не таскаем
			b.position = board.nodes[ti] - b.size * 0.5
			b.dropped.connect(_on_drop)
			blobs.append(b)

	func craft_start(g) -> void:
		g.sliders["count"].set_value_no_signal(float(target_nodes.size()))
		# рассыпаем сгустки (сверху, не на узлах) и разрешаем таскать
		for b in blobs:
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.position = Vector2(randf_range(0.10, 0.90) * board.size.x, randf_range(0.08, 0.30) * board.size.y) - b.size * 0.5

	func _on_drop(part) -> void:
		var i: int = board.nearest_index(part.center())
		if i >= 0:
			part.position = board.nodes[i] - part.size * 0.5   # «примагничивание» к узлу
			Sfx.play("blobSnap")

	func _position_score() -> float:
		if target_nodes.is_empty():
			return 1.0
		var covered: Dictionary = {}
		for b in blobs:
			var i: int = board.nearest_index(b.center())
			if i in target_nodes:
				covered[i] = true
		return float(covered.size()) / float(target_nodes.size())

	func override_overall(g) -> float:
		final_pos = _position_score()     # кэшируем до stop() (board освободится)
		return 0.6 * g._current_overall() + 0.4 * final_pos

	func stop(_g) -> void:
		if board != null and is_instance_valid(board):
			board.queue_free()
		board = null
		blobs.clear()

	func result_note(_g) -> String:
		return "🔧 Векс: сгустки — по узлам (%d%% позиций)" % int(round(final_pos * 100.0))

# ============================================================
# Дитя Сверхновой (dual_size): габарит распадается на ширину («Объём») и высоту
# («Высота», size2) — два независимых регулятора. На УР.4 добавляется «Наклон» —
# банка кренится (в пределах ±15°, остаётся стоять). Порт special:'dual_size' +
# эксклюзивный rotation УР.4.
# ============================================================
class SupernovaMech extends NpcMech:
	func setup(g) -> void:
		if not ("size2" in g.active):
			g.active.append("size2")     # высота — часть заказа на всех уровнях
		if g.level == 4 and not ("rotation" in g.active):
			g.active.append("rotation")  # наклон — эксклюзив УР.4

	func result_note(g) -> String:
		if "rotation" in g.active:
			return "💫 Дитя Сверхновой: ширина, высота и наклон"
		return "💫 Дитя Сверхновой: ширина и высота раздельно"

# ============================================================
# Пьяница Пит: «уровень жидкости» (fill) — отдельный регулятор, активен С УР.1.
# Порт cfg.id==='pete' (fill в activeKeys). Градус (degree, УР.4) — TODO.
# ============================================================
class PeteMech extends NpcMech:
	var g_ref

	func setup(g) -> void:
		if not ("fill" in g.active):
			g.active.append("fill")     # уровень жидкости — часть заказа на всех уровнях

	# УР.4: эксклюзивный «Градус» — риск-дайл (не в active → не оценивается)
	func craft_start(g) -> void:
		g_ref = g
		if g.level != 4:
			return
		g.slider_cols["degree"].visible = true
		g.sliders["degree"].set_value_no_signal(0.0)     # с нуля — трезвый

	func _degree_frac() -> float:
		if g_ref == null or g_ref.level != 4:
			return 0.0
		return clampf(g_ref.sliders["degree"].value / 100.0, 0.0, 1.0)

	func process(g, _delta: float) -> void:
		if g.level != 4:
			return
		var gd: float = _degree_frac()
		g.timer_rate = 1.0 - 0.5 * gd                    # до ×2 медленнее
		g.jar.set_blur(gd)                               # настоящее размытие жидкости+сгустков
		g.drunk_amount = gd                              # «пьяная» качка камеры + двоение

	func score_bonus(_g) -> float:
		return 1.0 - 0.5 * _degree_frac()                # выше градус — меньше рейтинга

	func stop(g) -> void:
		g.timer_rate = 1.0
		g.drunk_amount = 0.0
		if is_instance_valid(g.jar):
			g.jar.set_blur(0.0)
		if g.slider_cols.has("degree"):
			g.slider_cols["degree"].visible = false

	func result_note(_g) -> String:
		return "🍺 Пьяница Пит: важен уровень жидкости"

# ============================================================
# Тот-Кто-Ждёт (no_timer): таймеров нет — «ЗАПОМНИ» и «ВОССОЗДАЙ» переключаются
# вручную (стрелка ▸ / «ГОТОВО»). Рейтинг начисляется ТОЛЬКО при точности >99%,
# иначе — только стикер. Порт special:'no_timer'. Форма-часы (shape) — TODO.
# ============================================================
class WaiterMech extends NpcMech:
	var g_ref
	var go_btn: Button = null

	func no_timer(_g) -> bool:
		return true

	func memorize_start(g) -> void:
		g_ref = g
		g.bulb_bar.visible = false             # таймера нет — лампы не нужны
		go_btn = NpcMech.make_arrow_btn(g, _to_craft)   # ▸ — перейти к воссозданию вручную

	func _to_craft() -> void:
		if go_btn != null and is_instance_valid(go_btn):
			go_btn.queue_free()
		go_btn = null
		g_ref._start_recreate()

	func craft_start(g) -> void:
		if go_btn != null and is_instance_valid(go_btn):
			go_btn.queue_free()
		go_btn = null
		g.bulb_bar.visible = false

	func blocks_points(_g, overall: float) -> bool:
		return overall <= 0.99                 # рейтинг только за идеал

	func stop(g) -> void:
		if go_btn != null and is_instance_valid(go_btn):
			go_btn.queue_free()
		go_btn = null
		g.bulb_bar.visible = true

	func result_note(_g) -> String:
		return "⏳ Тот-Кто-Ждёт: рейтинг только при идеале (>99%)"

# ============================================================
# Двуликая жрица (gradient + dual count): банка делится на 2 половины, у каждой
# свой счётчик сгустков (право = «Сгустки», лево = «Сгустки Б», макс. 7).
# Порт special:'gradient' + LEVEL4_FX.twofaced. Градиент (2-й цвет) — TODO.
# ============================================================
class TwofacedMech extends NpcMech:
	func setup(g) -> void:
		if not ("countB" in g.active):
			g.active.append("countB")
		g.sliders["count"].max_value = 7.0   # обе половины ограничены семью

	func result_note(_g) -> String:
		return "🧿 Двуликая: два счётчика (лево/право)"

# ============================================================
# Бармен плазма-бара (moving + speed): сгустки летают внутри банки, скорость полёта
# — эксклюзивный ползунок «Скорость», читается в реальном времени. Порт
# special:'moving' + LEVEL4_FX.plasma_bartender.
# ============================================================
class PlasmaMech extends NpcMech:
	var g_ref

	func setup(g) -> void:
		if not ("speed" in g.active):
			g.active.append("speed")

	func _speed_frac(g, key_source: Dictionary) -> float:
		var sp: Dictionary = g.PARAMS["speed"]
		return (float(key_source["speed"]) - float(sp["min"])) / (float(sp["max"]) - float(sp["min"]))

	func memorize_start(g) -> void:
		g_ref = g
		g.jar.set_physics(true)
		g.jar.set_physics_speed(_speed_frac(g, g.target))   # на показе — целевая скорость

	func craft_start(g) -> void:
		g_ref = g
		g.jar.set_physics(true)

	func process(g, _delta: float) -> void:
		g.jar.set_physics_speed(_speed_frac(g, g._current_values()))   # игрок крутит скорость вживую

	func stop(g) -> void:
		g.jar.set_physics(false)

	func result_note(_g) -> String:
		return "🍸 Бармен: сгустки летают — лови скорость"
