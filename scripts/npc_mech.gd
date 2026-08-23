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

	# фирменный дождь глифов — уже в фазе показа (мешает разглядеть смесь).
	# Кладём поверх всего, но ограничиваем прямоугольником ОКНА: покрывает банку и
	# упирается в подоконник (уходит «за стол»), не залезая на регуляторы.
	func memorize_start(g) -> void:
		g_ref = g
		rain = MatrixRain.new()
		g.add_child(rain)
		_place_rain(g)

	func _place_rain(g) -> void:
		if rain == null or not is_instance_valid(rain):
			return
		var m: Dictionary = g._bg_metrics()
		var win: Rect2 = m["win"]
		var table_y: float = m["table_y"]
		# верх дождя — сразу под надписью фазы (ВОССОЗДАЙ/ЗАПОМНИ), а не с середины окна
		var top_y: float = win.position.y
		if g.phase_label != null and is_instance_valid(g.phase_label):
			top_y = g.phase_label.global_position.y + g.phase_label.size.y + 6.0
		# от надписи ВНИЗ до линии стола: дождь мешает видеть банку, но не лезет на
		# стойку/ползунки/текст (верх плавно появляется, низ тает — см. MatrixRain)
		rain.set_anchors_preset(Control.PRESET_TOP_LEFT)
		rain.position = Vector2(win.position.x, top_y)
		rain.size = Vector2(win.size.x, maxf(40.0, table_y - top_y))

	func craft_start(g) -> void:
		g_ref = g
		keys = (g.active as Array).duplicate()
		acc = 0.0
		sealed_key = ""
		last_correct = ""
		if rain == null:                     # страховка, если показ был пропущен
			memorize_start(g)
		_place_rain(g)                       # переразместить под текущий размер экрана
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
		# ждём, пока стулья-ползунки доедут (иначе лапа спавнится в невидимой
		# колонке — modulate.a=0 на выезде — и «пропадает»)
		await g.get_tree().create_timer(0.55).timeout
		if not is_instance_valid(g) or g.phase != "recreate":
			return
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
	var ekg: EkgLine = null

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
		# УР.4: линия сердцебиения (ЭКГ) поверх сцены — учащается по мере ухудшения
		if g.level == 4:
			ekg = EkgLine.new()
			ekg.set_anchors_preset(Control.PRESET_FULL_RECT)
			ekg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			g.jar_stage.add_child(ekg)
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
		# «состояние пациента»: банка мутнеет и теряет цвет по мере убывания времени
		if g_ref != null and g_ref.jar != null:
			g_ref.jar.set_blur(1.0 - frac)
			g_ref.jar.set_desat(0.15 + frac * 0.85)
		if ekg != null and is_instance_valid(ekg):
			ekg.set_rate(1.0 + (1.0 - frac) * 2.0)   # чем хуже, тем чаще пульс

	func score_bonus(g) -> float:
		return 1.0 + 0.5 * clampf(g.phase_left / maxf(0.001, g.phase_total), 0.0, 1.0)

	func stop(g) -> void:
		if bar != null and is_instance_valid(bar):
			bar.queue_free()
		if ekg != null and is_instance_valid(ekg):
			ekg.queue_free()
		if g != null and g.jar != null:      # вернуть банке цвет/резкость
			g.jar.set_blur(0.0)
			g.jar.set_desat(1.0)
		bar = null
		fill = null
		ekg = null

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
		g.jar_stage.add_child(grime)
		grime.fit_window(g.jar_stage.size.x, g.jar_stage.table_line())   # только «стекло окна»

	func craft_start(g) -> void:
		g_ref = g
		if grime == null:
			memorize_start(g)
		else:
			grime.reset()                 # свежая грязь на фазу игры
		grime.fit_window(g.jar_stage.size.x, g.jar_stage.table_line())   # окно могло изменить высоту
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
# Маркетолог с безлюдного спутника: ползунки ОБЫЧНЫЕ (штатная прогрессия). Фишка —
# полноэкранные МИНИИГРЫ, которые вылезают 1/2/3 раза за заказ (по УР). Пока таймер
# заказа на них идёт ×0.2 (виден только он сверху). Капча: верно → буст рейтинга,
# неверно → штраф + сбивается случайный ползунок. Этап 1: реализована капча.
# ============================================================
class MarketerMech extends NpcMech:
	const MG_COUNT := {1: 1, 2: 1, 3: 2, 4: 2}
	var g_ref
	var active_game: Control = null
	var mg_bonus: float = 1.0
	var schedule: Array = []            # пороги elapsed (доли phase_total), по возрастанию
	var used_types: Dictionary = {}     # тип миниигры -> сколько раз был (повтор не >1)

	func craft_start(g) -> void:
		g_ref = g
		var cnt: int = int(MG_COUNT.get(g.level, 1))
		# доп.время НЕ добавляем: на время миниигры таймер и так ×0.2 (почти пауза)
		schedule.clear()
		var slots: Array = {1: [0.45], 2: [0.36, 0.68]}.get(cnt, [0.45])
		for s in slots:
			schedule.append(float(s))

	func process(g, _delta: float) -> void:
		if active_game != null:
			if is_instance_valid(active_game):
				active_game.set_timer(g.phase_left)
			return
		if schedule.is_empty():
			return
		var elapsed_frac: float = 1.0 - clampf(g.phase_left / maxf(0.001, g.phase_total), 0.0, 1.0)
		if elapsed_frac >= float(schedule[0]):
			schedule.remove_at(0)
			_launch(g)

	# выбрать тип миниигры: меньше всего использованный (повтор не более 1 раза за заказ)
	func _pick_type() -> String:
		var pool: Array = ["captcha", "ad", "puzzle"]     # мозаика временно отключена
		pool.shuffle()
		pool.sort_custom(func(a, b): return int(used_types.get(a, 0)) < int(used_types.get(b, 0)))
		return pool[0]

	# запуск миниигры (в КОРЕНЬ main — round_ui это VBox), таймер заказа ×0.2, UI скрыт
	func _launch(g) -> void:
		g.timer_rate = 0.2
		for k in g.active:
			if g.slider_cols.has(k):
				g.slider_cols[k].visible = false
		g.done_btn.visible = false
		var t: String = _pick_type()
		used_types[t] = int(used_types.get(t, 0)) + 1
		var game: Control
		if t == "ad":
			game = AdGame.new()
			game.finished.connect(_on_ad_done)
		elif t == "puzzle":
			game = PuzzleGame.new()
			game.finished.connect(_on_puzzle_done)
		elif t == "mosaic":
			game = MosaicGame.new()
			game.finished.connect(_on_ad_done)     # без баффа — как реклама
		else:
			game = CaptchaGame.new()
			game.finished.connect(_on_captcha_done)
		g.add_child(game)                    # прямо в main (Control на весь экран)
		game.setup(g.level)
		game.set_timer(g.phase_left)
		active_game = game

	func _on_captcha_done(ok: bool, acc: float) -> void:
		var g = g_ref
		if ok:
			mg_bonus *= 1.15                       # верно → буст рейтинга
		else:
			mg_bonus *= 0.82                       # неверно → штраф
			_knock_slider(g)                       # и сбиваем случайный ползунок
		# короткое сообщение «на сколько % закрыл», затем следующий шаг
		if active_game != null and is_instance_valid(active_game):
			active_game.show_result(int(round(acc * 100.0)), ok)
		g.get_tree().create_timer(1.3).timeout.connect(func(): _close_game(g))

	# реклама: баффа/штрафа нет, просто закрыли и продолжили
	func _on_ad_done(_ok: bool, _acc: float) -> void:
		_close_game(g_ref)

	# пазл: множитель по точности (0.85..1.15) + сообщение с процентом
	func _on_puzzle_done(_ok: bool, acc: float) -> void:
		var g = g_ref
		mg_bonus *= (0.85 + 0.30 * clampf(acc, 0.0, 1.0))
		if active_game != null and is_instance_valid(active_game):
			active_game.show_result(int(round(acc * 100.0)), acc >= 0.9)
		g.get_tree().create_timer(1.3).timeout.connect(func(): _close_game(g))

	# сбить случайный активный ползунок в неверное значение
	func _knock_slider(g) -> void:
		if g.active.is_empty():
			return
		var k: String = g.active[randi() % g.active.size()]
		var s = g.sliders[k]
		var nv: float = randf_range(s.min_value, s.max_value)
		s.set_value_no_signal(nv)
		g._on_slider_changed(nv, k)

	func _close_game(g) -> void:
		if active_game != null and is_instance_valid(active_game):
			active_game.queue_free()
		active_game = null
		g.timer_rate = 1.0
		for k in g.active:
			if g.slider_cols.has(k):
				g.slider_cols[k].visible = true
		g.done_btn.visible = true

	func score_bonus(_g) -> float:
		return mg_bonus

	func stop(g) -> void:
		if active_game != null and is_instance_valid(active_game):
			active_game.queue_free()
		active_game = null
		if g != null:
			g.timer_rate = 1.0
			for k in g.active:
				if g.slider_cols.has(k):
					g.slider_cols[k].visible = true

	func result_note(_g) -> String:
		return "📰 Маркетолог: миниигры-капчи между настройкой (×%.2f рейтинг)" % mg_bonus

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
	# зоны «обитания» деталей (доли слоя): стол снизу + стены + НАД банкой (верх окна).
	# Всё ВНЕ зоны сбора — детали летают в т.ч. над сосудом, не только по бокам.
	var ZONES := [
		Rect2(0.06, 0.83, 0.88, 0.11),   # стол (нижняя полоса)
		Rect2(0.02, 0.40, 0.13, 0.40),   # левая стена
		Rect2(0.85, 0.40, 0.13, 0.40),   # правая стена
		Rect2(0.14, 0.235, 0.72, 0.10),  # НАД банкой (верх окна)
	]
	# набор картинок-деталей (биомех-слаймы, стиль игры). Индекс = сигнатура.
	const SWARM_FILES := [
		"swarm_00_magenta.png", "swarm_01_lime.png", "swarm_02_cyan.png", "swarm_03_orange.png",
		"swarm_04_violet.png", "swarm_05_yellow.png", "swarm_06_red.png", "swarm_07_turquoise.png",
		"swarm_08_royalblue.png", "swarm_09_coral.png", "swarm_10_amber.png", "swarm_11_rust.png",
		"swarm_12_silver.png", "swarm_13_cream.png", "swarm_14_charcoal.png",
	]
	const S_MEM := 74.0     # размер детали-образца внутри банки
	const S_FLY := 92.0     # размер летающих деталей (крупно — читаемо на телефоне)
	var _texs: Array = []
	var g_ref
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
		g.active.erase("volume")         # банка ВСЕГДА крупная (иначе детали не влезают)
		g.sliders["count"].min_value = 0.0   # разрешаем 0 сгустков (иначе банка держит 1)

	func _load_texs() -> void:
		if not _texs.is_empty():
			return
		for f in SWARM_FILES:
			_texs.append(load("res://assets/swarm/" + f))

	# банку — в максимальный объём (детали крупные, должны помещаться и читаться)
	func _force_big_jar(g) -> void:
		g.target["volume"] = float(g.PARAMS["volume"]["max"])
		g.sliders["volume"].set_value_no_signal(g.target["volume"])

	func memorize_start(g) -> void:
		g_ref = g
		_load_texs()
		n_target = clampi(int(g.target["count"]), 3, 6)
		_force_big_jar(g)                          # банка максимальная — детали помещаются
		g.target["count"] = 0                      # жидких сгустков нет — «начинка» = детали
		g.sliders["count"].set_value_no_signal(0.0)
		g._apply_to_jar(g.target)                  # перерисовать банку без сгустков
		var pool: Array = range(_texs.size()); pool.shuffle()
		targets = pool.slice(0, n_target)
		# цели показываем ВНУТРИ банки — вешаем в качающийся узел (sway), чтобы детали
		# качались вместе с сосудом и стояли в жидкости (вразброс, не рядами)
		var holder: Control = g.jar.inner_holder()
		var jw: float = JarStage.JAR_W             # фиксированный размер банки (без завязки на layout)
		var jh: float = JarStage.JAR_H
		var placed: Array = []
		for i in n_target:
			var mp := DragPart.new()
			holder.add_child(mp)                           # _ready() ставит size/STOP
			mp.set_part_size(S_MEM)
			mp.set_texture_part(_texs[int(targets[i])], int(targets[i]))
			mp.mouse_filter = Control.MOUSE_FILTER_IGNORE  # образец не таскаем (после _ready)
			# rejection sampling в зоне жидкости (доли от размера банки)
			var best := Vector2(0.49 * jw, 0.62 * jh)
			for _attempt in 18:
				var cand := Vector2(randf_range(0.30, 0.68) * jw, randf_range(0.42, 0.84) * jh)
				best = cand
				var ok := true
				for pp in placed:
					if cand.distance_to(pp) < S_MEM * 0.9:
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
		_force_big_jar(g)                           # банка максимальная
		g.target["count"] = 0                       # никаких жидких сгустков — «начинка» = детали
		g.sliders["count"].set_value_no_signal(0.0)
		g._apply_to_jar(g._current_values())        # перерисовать банку пустой (без сгустков)
		var sz: Vector2 = g.jar_stage.size
		# 1) детали образца резко разлетаются за пределы экрана (из банки — в координаты сцены)
		for mp in mem_parts:
			mp.reparent(g.jar_stage)                       # keep_global → остаётся на месте
			var dir: Vector2 = (mp.center() - sz * 0.5)
			dir = dir.normalized() if dir.length() > 1.0 else Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			var tw: Tween = mp.create_tween()
			tw.tween_property(mp, "position", mp.position + dir * sz.length(), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(mp.queue_free)
		mem_parts.clear()
		# 2) влетают детали: все цели + обманки (все уникальны, максимум = число картинок)
		layer = Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.jar_stage.add_child(layer)
		var pool: Array = targets.duplicate()          # все цели по одному разу
		var extras: Array = range(_texs.size()); extras.shuffle()
		var want: int = clampi(n_target + 8, 12, _texs.size())   # крупные детали → не «десятки»
		for s in extras:
			if pool.size() >= want:
				break
			if not (s in targets):
				pool.append(s)
		pool.shuffle()
		var placed: Array = []                         # центры уже размещённых (анти-наложение)
		for i in pool.size():
			var part := DragPart.new()
			layer.add_child(part)
			part.set_part_size(S_FLY)
			part.set_texture_part(_texs[int(pool[i])], int(pool[i]))
			var zone: Rect2 = ZONES[i % ZONES.size()]
			part.home_zone = zone
			# позиция в зоне без наложения на уже поставленные детали
			var dst := _rand_in_zone(zone, sz)
			for _attempt in 22:
				var cand := _rand_in_zone(zone, sz)
				dst = cand
				var ok := true
				for pc in placed:
					if cand.distance_to(pc) < S_FLY * 0.95:
						ok = false
						break
				if ok:
					break
			placed.append(dst)
			var start := dst
			if zone.position.x < 0.2: start.x = -110.0            # влетает слева
			elif zone.position.x > 0.7: start.x = sz.x + 110.0    # справа
			elif zone.position.y < 0.3: start.y = -110.0          # НАД банкой → сверху
			else: start.y = sz.y + 120.0                          # снизу (стол)
			part.position = start - part.size * 0.5
			part.dropped.connect(_on_dropped)
			parts.append(part)
			var tw2: Tween = part.create_tween()
			tw2.tween_interval(0.06 * float(i))                   # с интервалами, не все разом
			tw2.tween_property(part, "position", dst - part.size * 0.5, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# детали слегка «летают» по своим зонам (на УР.4 — активнее)
		drift_timer = Timer.new()
		drift_timer.wait_time = 0.9
		drift_timer.timeout.connect(_drift)
		layer.add_child(drift_timer)
		drift_timer.start()

	# случайная точка-ЦЕНТР детали в зоне (доли → пиксели слоя)
	func _rand_in_zone(zone: Rect2, sz: Vector2) -> Vector2:
		var fx: float = zone.position.x + randf() * zone.size.x
		var fy: float = zone.position.y + randf() * zone.size.y
		return Vector2(fx * sz.x, fy * sz.y)

	# детали «летают» — мелкими шагами гоняем непойманные внутри их зоны (плавно тви́ном).
	# На УР.4 шаг больше (сложнее поймать).
	func _drift() -> void:
		if layer == null or layer.size.x <= 0.0:
			return
		var sz: Vector2 = layer.size
		var amp: float = 32.0 if (g_ref != null and g_ref.level == 4) else 16.0
		for p in parts:
			if p.is_dragging() or _inside(p):
				continue
			var z: Rect2 = p.home_zone
			var cur: Vector2 = p.center()
			var nc := cur + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
			nc.x = clampf(nc.x, z.position.x * sz.x, (z.position.x + z.size.x) * sz.x)
			nc.y = clampf(nc.y, z.position.y * sz.y, (z.position.y + z.size.y) * sz.y)
			var tw: Tween = p.create_tween()
			tw.tween_property(p, "position", nc - p.size * 0.5, 0.7).set_trans(Tween.TRANS_SINE)

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
		var holder: Control = g.jar.inner_holder()   # качающийся узел банки
		for p in parts:
			if is_instance_valid(p) and _inside(p):
				p.reparent(holder)         # keep_global → на месте; едет и качается с банкой
				served.append(p)
			elif is_instance_valid(p):
				p.queue_free()
		parts.clear()

	func override_overall(g) -> float:
		# 0.55·(цвет/накал/объём) + 0.45·(верно собранные детали)
		return 0.55 * g._current_overall() + 0.45 * final_acc

	func stop(g) -> void:
		drift_timer = null
		if g != null and g.sliders.has("count"):
			g.sliders["count"].min_value = 1.0     # вернуть штатный минимум сгустков
		for p in served:
			if is_instance_valid(p):
				p.queue_free()
		served.clear()
		for mp in mem_parts:               # если бросили заказ на «ЗАПОМНИ» — убрать из банки
			if is_instance_valid(mp):
				mp.queue_free()
		mem_parts.clear()
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
		layer = null
		parts.clear()

	func result_note(_g) -> String:
		return "🐝 Навигатор Роя: собрано верных деталей — %d%%" % int(round(final_acc * 100.0))

# ============================================================
# Инспектор Гильдии: фазы показа НЕТ — цель описана в листе «Допуски» (значения
# как «№X из N» по делениям ползунка). Кнопка открывает текст; время варки ×2.
# Порт LEVEL4_FX.guild_inspector (загадка-допрос УР.4 — TODO).
# ============================================================
class InspectorMech extends NpcMech:
	var g_ref
	var tol: int = 2
	var folder: DossierFolder = null   # закрытая папка на столе
	var dossier: Control = null        # открытое «дело» (поверх банки)

	func setup(_g) -> void:
		tol = randi() % 3 + 1              # допуск ±1..3 деления

	func skip_memorize(_g) -> bool:
		return true

	func craft_start(g) -> void:
		g_ref = g
		g.phase_total *= 2.0                # читать дольше, чем смотреть
		g.phase_left *= 2.0
		_build_dossier(g)
		# закрытая папка «ДЕЛО» — на столе (низ окна), по клику открывается досье
		folder = DossierFolder.new()
		g.jar_stage.add_child(folder)
		folder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		folder.anchor_left = 0.5; folder.anchor_right = 0.5
		folder.anchor_top = 1.0;  folder.anchor_bottom = 1.0
		folder.offset_left = -52.0; folder.offset_right = 52.0
		folder.offset_top = -96.0;  folder.offset_bottom = -14.0
		folder.opened.connect(_open_dossier)
		dossier.visible = false            # на старте закрыто — лежит папкой на столе

	func _open_dossier() -> void:
		if dossier != null:
			dossier.visible = true
		if folder != null and is_instance_valid(folder):
			folder.visible = false

	func _close_dossier() -> void:
		if dossier != null:
			dossier.visible = false
		if folder != null and is_instance_valid(folder):
			folder.visible = true
		Sfx.play("uiClick")

	# строка значения показателя: обычные — «отметка №X из N», сгустки — числом
	func _value_str(g, key: String) -> String:
		var s = g.sliders[key]
		if key == "count":
			return str(int(round(float(g.target[key]))))
		var st: float = s.step if s.step > 0.0 else 1.0
		var idx: int = int(round((float(g.target[key]) - s.min_value) / st))
		var n: int = int(round((s.max_value - s.min_value) / st)) + 1
		return "№%d из %d" % [idx + 1, n]

	func _build_text(g) -> String:
		var keys: Array = g.active.duplicate()
		# порядок фраз перемешан по сиду — нельзя запомнить «какой пункт по счёту»
		var rng := RandomNumberGenerator.new()
		rng.seed = int(g.seed_val) + 4271
		for i in range(keys.size() - 1, 0, -1):
			var j: int = rng.randi() % (i + 1)
			var tmp = keys[i]; keys[i] = keys[j]; keys[j] = tmp
		var clauses: Array = []
		for k in keys:
			if GameData.INSPECTOR_PHRASE.has(k):
				clauses.append(String(GameData.INSPECTOR_PHRASE[k]).replace("{v}", _value_str(g, k)))
		var sentences: String = ""
		if clauses.size() == 1:
			sentences = String(clauses[0])
		elif clauses.size() > 1:
			var head: Array = clauses.slice(0, clauses.size() - 1)
			sentences = ", ".join(head) + ", а " + String(clauses[-1])
		if sentences != "":
			sentences = sentences.substr(0, 1).to_upper() + sentences.substr(1) + "."
		var tpl: String = String(GameData.INSPECTOR_TEMPLATES[randi() % GameData.INSPECTOR_TEMPLATES.size()])
		return tpl.replace("{SENTENCES}", sentences).replace("{TOL}", str(tol))

	# оценка = доля показателей, попавших в допуск ±tol делений (порт скоринга УР.4)
	func override_overall(g) -> float:
		var missed: int = 0
		var n: int = 0
		for k in g.active:
			var s = g.sliders[k]
			var st: float = s.step if s.step > 0.0 else 1.0
			var tgt_idx: float = round((float(g.target[k]) - s.min_value) / st)
			var cur_idx: float = round((s.value - s.min_value) / st)
			n += 1
			if absf(cur_idx - tgt_idx) > float(tol):
				missed += 1
		if n == 0 or missed == 0:
			return 1.0
		return maxf(0.80, 0.94 - float(missed) * 0.03)

	# «Дело» — бумажный документ поверх окна (не над ползунками); клип по jar_stage
	func _build_dossier(g) -> void:
		dossier = Control.new()
		dossier.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.jar_stage.add_child(dossier)
		var paper := PanelContainer.new()
		paper.set_anchors_preset(Control.PRESET_FULL_RECT)
		paper.offset_left = 26.0; paper.offset_right = -26.0
		paper.offset_top = 20.0;  paper.offset_bottom = -26.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.93, 0.88, 0.76)            # бумага
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.55, 0.44, 0.26)
		sb.content_margin_left = 22.0; sb.content_margin_right = 22.0
		sb.content_margin_top = 18.0;  sb.content_margin_bottom = 18.0
		sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 12
		paper.add_theme_stylebox_override("panel", sb)
		dossier.add_child(paper)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		paper.add_child(col)
		var head := Label.new()
		head.text = "ДЕЛО О ПРИЁМКЕ · ГИЛЬДИЯ"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 20)
		head.add_theme_color_override("font_color", Color(0.42, 0.12, 0.10))
		col.add_child(head)
		var body := Label.new()
		body.text = _build_text(g)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_font_size_override("font_size", 19)
		body.add_theme_color_override("font_color", Color(0.16, 0.12, 0.08))
		col.add_child(body)
		var close := Button.new()
		close.text = "Убрать в папку"
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(_close_dossier)
		col.add_child(close)

	func stop(_g) -> void:
		if folder != null and is_instance_valid(folder):
			folder.queue_free()
		if dossier != null and is_instance_valid(dossier):
			dossier.queue_free()
		folder = null
		dossier = null

	func result_note(_g) -> String:
		return "📋 Инспектор: сверял по «Делу о приёмке»"

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

	# Векс (порт браузера): нет объёма/счётчика-ползунка. Сгустки (3/4/5/5 по УР)
	# раскладываются по сетке ВНУТРИ жидкости банки; сетка растёт по уровню. На УР.3+
	# в игре ползунок «Размер» (bsize), на УР.4 — «Накал» (sat). Доска висит в
	# качающемся узле банки (sway) → живёт и качается ВНУТРИ сосуда.
	const VEX_COUNTS := {1: 3, 2: 4, 3: 5, 4: 5}
	const VEX_GRID := {1: Vector2i(2, 2), 2: Vector2i(2, 3), 3: Vector2i(3, 3), 4: Vector2i(3, 4)}
	# UV-границы интерьера/уровня жидкости (зеркало констант potion_jar).
	const IL := 0.240
	const IR := 0.746
	const IB := 0.953
	const IT := 0.150
	const JAR_FILL := 0.78

	func setup(g) -> void:
		g.active.erase("count")          # счёт задаётся раскладкой
		g.active.erase("volume")         # размера банки у Векса нет

	# Зона жидкости в ЛОКАЛЬНЫХ координатах банки (px) — сюда вписываем сетку, чтобы
	# она ВСЕГДА была внутри зелья (узлы = центры ячеек, с отступом от стенок/поверхности).
	func _liquid_area(g) -> Rect2:
		var jw: float = g.jar.size.x
		var jh: float = g.jar.size.y
		var liq_top: float = IB - (IB - IT) * JAR_FILL
		var x0: float = IL + 0.05
		var x1: float = IR - 0.05
		var y0: float = liq_top + 0.05
		var y1: float = IB - 0.05
		return Rect2(Vector2(x0 * jw, y0 * jh), Vector2((x1 - x0) * jw, (y1 - y0) * jh))

	func memorize_start(g) -> void:
		g_ref = g
		# доска — в качающемся узле банки: живёт и качается ВНУТРИ сосуда
		board = VexBoard.new()
		g.jar.inner_holder().add_child(board)
		var grid: Vector2i = VEX_GRID.get(g.level, Vector2i(3, 3))
		board.build(_liquid_area(g), grid.x, grid.y)
		var k: int = mini(int(VEX_COUNTS.get(g.level, 3)), board.nodes.size())
		# банка МАКСИМАЛЬНОГО размера: сетка/пузыри крупнее → удобно тянуть пальцем
		# (объём не оценивается — он вырезан из active в setup)
		g.target["volume"] = float(g.PARAMS["volume"]["max"])
		g.sliders["volume"].set_value_no_signal(g.target["volume"])
		# банка без своих жидких сгустков (count=0 везде) — «начинка» = сгустки на сетке.
		# ВАЖНО: у слайдера count min=1 → set_value(0) клампится до 1 и в воссоздании
		# банка рисует 1 лишний сгусток. Временно опускаем min до 0 (вернём в stop()).
		g.sliders["count"].min_value = 0.0
		g.target["count"] = 0
		g.sliders["count"].set_value_no_signal(0.0)
		g._apply_to_jar(g.target)
		var idx: Array = range(board.nodes.size())
		idx.shuffle()
		target_nodes = idx.slice(0, k)
		var t_col: Color = _potion_color(g.target)
		var t_scale: float = _blob_scale(g.target)
		for ti in target_nodes:
			var b := DragPart.new()
			board.add_child(b)
			b.set_kind(DragPart.BLOB)
			b.set_blob_visual(t_scale, t_col)              # показываем цвет+размер цели
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # на показе не таскаем
			b.position = board.nodes[ti] - b.size * 0.5
			b.dropped.connect(_on_drop)
			blobs.append(b)

	# Цвет сгустка = цвет зелья (спектр/накал). На УР.1 даёт «Спектру» видимый эффект.
	func _potion_color(vals) -> Color:
		var hue: float = float(vals.get("color", 120.0))
		var s: float = 0.72
		if g_ref != null and ("sat" in g_ref.active):
			s = clampf(0.30 + (float(vals.get("sat", 72.0)) / 100.0) * 0.70, 0.18, 1.0)
		return Color.from_hsv(fposmod(hue, 360.0) / 360.0, s, 0.95)

	# Масштаб сгустка = ползунок «Размер» (bsize), если он активен (УР.3+); иначе 1.0.
	func _blob_scale(vals) -> float:
		if g_ref == null or not ("bsize" in g_ref.active):
			return 1.0
		var f: float = clampf((float(vals.get("bsize", 55.0)) - 10.0) / 90.0, 0.0, 1.0)
		return 0.62 + 0.7 * f

	# Стартовые узлы фазы «ВОССОЗДАЙ»: перемешанные, по возможности не совпадающие с
	# целевым набором (иначе нечего перекладывать).
	func _start_nodes(k: int) -> Array:
		var all_idx: Array = range(board.nodes.size())
		var best: Array = []
		for _try in 8:
			all_idx.shuffle()
			best = all_idx.slice(0, k)
			var same := true
			for i in best:
				if not (i in target_nodes):
					same = false
					break
			if not same:
				break
		return best

	func craft_start(g) -> void:
		board.set_hot(-1)
		# после «ЗАПОМНИ» сгустки БЫСТРО перепрыгивают на другие узлы (не рассыпаются),
		# игрок перекладывает их обратно на верные позиции
		var starts: Array = _start_nodes(blobs.size())
		var col: Color = _potion_color(g._current_values())
		var sc: float = _blob_scale(g._current_values())
		for j in blobs.size():
			var b = blobs[j]
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.set_blob_visual(sc, col)
			var dst: Vector2 = board.nodes[starts[j]] - b.size * 0.5
			var tw: Tween = b.create_tween()
			tw.tween_interval(0.04 * float(j))
			tw.tween_property(b, "position", dst, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# живой цвет/размер сгустков от текущих ползунков + подсветка ближайшего узла
	func process(g, _delta: float) -> void:
		if board == null or not is_instance_valid(board):
			return
		var vals: Dictionary = g._current_values()
		var col: Color = _potion_color(vals)
		var sc: float = _blob_scale(vals)
		var hi: int = -1
		for b in blobs:
			b.set_blob_visual(sc, col)
			if b.is_dragging():
				hi = board.nearest_index(b.center())
		board.set_hot(hi)

	func _on_drop(part) -> void:
		var i: int = board.nearest_index(part.center())
		if i >= 0:
			part.position = board.nodes[i] - part.size * 0.5   # «примагничивание» к узлу
			Sfx.play("blobSnap")
		board.set_hot(-1)

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

	func stop(g) -> void:
		if g != null and g.sliders.has("count"):
			g.sliders["count"].min_value = 1.0        # вернуть штатный минимум
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
	# gradient: ДВА СПЕКТРА (градиент банки) — базовая механика на ВСЕХ уровнях.
	# Два счётчика (countB, лево/право) — довесок только на УР.4.
	func setup(g) -> void:
		g.active.erase("sat")                     # у градиент-персонажа накала нет (вместо него 2-й спектр)
		if not ("colorB" in g.active):
			g.active.append("colorB")
		if g.level == 4:
			if not ("countB" in g.active):
				g.active.append("countB")
			g.sliders["count"].max_value = 7.0    # обе половины ограничены семью

	func memorize_start(g) -> void:
		_spread_hue(g)                            # развести спектры подальше друг от друга
		g._apply_to_jar(g.target)                 # перерисовать цель с разведённым 2-м спектром

	# Второй спектр разводим по цветовому кругу: в ~94% минимум на 30% круга от первого
	# (иначе часто выпадали почти одинаковые оттенки — не читалась разница). Порт Фазы 0.
	func _spread_hue(g) -> void:
		var s = g.sliders["colorB"]
		var step: float = s.step
		if step <= 0.0:
			return
		var n: int = int(round(360.0 / step))     # число оттенков
		if n <= 2:
			return
		var i1: int = int(round(float(g.target["color"]) / step)) % n
		var i2: int = int(round(float(g.target["colorB"]) / step)) % n
		if randf() > 0.06:
			var minsep: int = maxi(1, int(round(float(n) * 0.30)))
			var guard: int = 24
			while _circ_dist(i2, i1, n) < minsep and guard > 0:
				i2 = randi() % n
				guard -= 1
		g.target["colorB"] = float(i2) * step

	func _circ_dist(a: int, b: int, n: int) -> int:
		var d: int = abs(a - b)
		return mini(d, n - d)

	func result_note(g) -> String:
		if "countB" in g.active:
			return "🧿 Двуликая: два спектра (градиент) + два счётчика (УР.4)"
		return "🧿 Двуликая: градиент из двух спектров"

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
