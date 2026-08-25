extends Node
## Персистентный профиль игрока. Автозагрузка (singleton `PotionProfile`).
## Сохраняется в user://profile.json. Портирован по структуре из profile.js
## (браузерная версия): та же идея deep-merge при загрузке — старый профиль
## сам дополняется недостающими полями новой схемы, лишнего не тащит.
##
## Фаза 1: перенесён персистентный костяк (статистика, серии, репутация,
## статы по NPC, прогрессия, чаевые, виденные стикеры). Пассивки персонажей —
## рабочие (см. ниже); лор/печати — поля заведены под будущие фазы.
## Формулы начисления репутации/чаевых — ПРЕДВАРИТЕЛЬНЫЕ (tunable, см. ниже).

const SCHEMA_VERSION := 1
const SAVE_PATH := "user://profile.json"

# --- tunable: начисление за один заказ по грейду ---
const REP_GAIN := {"perfect": 18.0, "good": 11.0, "swill": 3.0, "bad": -6.0}
const TIP_FACTOR := {"perfect": 1.0, "good": 0.6, "swill": 0.2, "bad": 0.0}

var data: Dictionary = {}
var _dirty: bool = false

func _ready() -> void:
	load_profile()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
			_write()

# ---------- схема пустого профиля ----------
func _empty_npc_stats() -> Dictionary:
	return {
		"orders": 0, "perfects": 0, "goods": 0, "bads": 0,
		"perfect_streak": 0, "perfect_streak_best": 0,
		"no_bad_streak": 0, "no_bad_streak_best": 0,
		"fast_perfects": 0, "hard_perfects": 0, "level4_perfects": 0,
		"focus_perfects": {"bubbles": 0, "color": 0, "size": 0},
		"weighted": 0.0, "picks_cycle": 0, "picks_cycle_best": 0,
	}

func _empty_profile() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"created_at": _now(),
		"last_seen_at": _now(),
		"stats": {
			"cycles_completed": 0,
			"total_score_earned": 0,
			"best_cycle_score": 0,
			"total_orders": 0,
			"stickers_lifetime": {"perfect": 0, "good": 0, "swill": 0, "bad": 0},
			"stickers_seen": {"perfect": [], "good": [], "swill": [], "bad": []},
			"weighted_progress": 0.0,
		},
		"streaks": {
			"perfect_current": 0, "perfect_best": 0,
			"goodplus_current": 0, "goodplus_best": 0,
			"bad_current": 0, "bad_best": 0,
		},
		"perfect_ribbon": {"count": 0.0, "platinum_count": 0},   # лента идеальных (дробная)
		"npc_reputation": {},   # id -> {value, level}
		"npc_stats": {},        # id -> _empty_npc_stats()
		"progression": {"xp": 0, "met_npcs": []},
		"tips": {"balance": 0, "lifetime": 0},
		"settings": {"music_vol": 0.6, "sfx_vol": 0.9},   # громкость (0..1)
		# заведено под будущие фазы (логики пока нет):
		"achievements": {"general": {}, "npc": {}},
		"lore_phrases": {"unlocked_by_npc": {}},
		"passives": {"unlocked_by_npc": {}, "active": []},
		# Фаза 7: умения игрока. charges — текущие заряды (0..3);
		# perfect_counter — идеалов накоплено в счёт бонусного заряда (сброс на 3).
		"skills": {"charges": 0, "perfect_counter": 0},
		# Связи NPC: grudge/offended/left — состояние ЗА ЦИКЛ (сброс в новом цикле).
		# discovered_relations — открытые пары "a|b", НАВСЕГДА.
		"npc_relations_state": {},
		"discovered_relations": [],
		# Постоянный клиент: гость, которого игрок «ведёт». Он обязательно
		# заглядывает раз в FAVOURITE_EVERY дней, иначе докачать репутацию до
		# верхних уровней нельзя — гостя надо ещё встретить.
		"favourite_npc": "",
	}

# ---------- Связи NPC ----------
func relation_state(npc_id: String) -> Dictionary:
	var st: Dictionary = data.get("npc_relations_state", {})
	if not st.has(npc_id):
		st[npc_id] = {"grudge": 0, "offended": false, "left": false}
	data["npc_relations_state"] = st
	return st[npc_id]

# +1 к «обиде»; пороги 3 (offended) и 6 (left). Возвращает флаги перехода порога.
func bump_grudge(npc_id: String) -> Dictionary:
	var s: Dictionary = relation_state(npc_id)
	s["grudge"] = int(s.get("grudge", 0)) + 1
	var was_off: bool = bool(s.get("offended", false))
	var was_left: bool = bool(s.get("left", false))
	if s["grudge"] >= 3: s["offended"] = true
	if s["grudge"] >= 6: s["left"] = true
	_dirty = true
	save()
	return {"state": s, "just_offended": s["offended"] and not was_off, "just_left": s["left"] and not was_left}

func relation_left(npc_id: String) -> bool:
	return bool(relation_state(npc_id).get("left", false))

func reset_relations_cycle() -> void:
	data["npc_relations_state"] = {}
	_dirty = true

func discover_relation(key: String) -> bool:
	var arr: Array = data.get("discovered_relations", [])
	if key in arr:
		return false
	arr.append(key)
	data["discovered_relations"] = arr
	_dirty = true
	save()
	return true

# ---------- Фаза 7: заряды умений ----------
const SKILL_CHARGE_CAP := 3

func get_charges() -> int:
	return int(data.get("skills", {}).get("charges", 0))

func add_charge(n: int = 1) -> void:
	var s: Dictionary = data.get("skills", {})
	s["charges"] = clampi(int(s.get("charges", 0)) + n, 0, SKILL_CHARGE_CAP)
	data["skills"] = s
	_dirty = true
	save()

func spend_charge() -> bool:
	var s: Dictionary = data.get("skills", {})
	var c: int = int(s.get("charges", 0))
	if c <= 0:
		return false
	s["charges"] = c - 1
	data["skills"] = s
	_dirty = true
	save()
	return true

# +1 к счётчику идеалов; при достижении порога — сброс и +1 заряд (возвращает true, если заряд начислен)
func bump_perfect_charge(threshold: int) -> bool:
	var s: Dictionary = data.get("skills", {})
	var pc: int = int(s.get("perfect_counter", 0)) + 1
	if pc >= threshold:
		s["perfect_counter"] = 0
		var was: int = int(s.get("charges", 0))
		s["charges"] = clampi(was + 1, 0, SKILL_CHARGE_CAP)
		data["skills"] = s
		_dirty = true
		save()
		return s["charges"] > was
	s["perfect_counter"] = pc
	data["skills"] = s
	_dirty = true
	save()
	return false

# ---------- Постоянный клиент ----------
func favourite_npc() -> String:
	return String(data.get("favourite_npc", ""))

# Назначить/снять. Возвращает нового постоянного клиента ("" — снят).
func set_favourite(npc_id: String) -> String:
	var cur: String = favourite_npc()
	data["favourite_npc"] = "" if cur == npc_id else npc_id
	_dirty = true
	save()
	return String(data["favourite_npc"])

# Сколько ещё удачных заказов до следующего уровня репутации (0 — максимум).
func orders_to_next_rep(npc_id: String) -> int:
	var rb: Dictionary = GameData.rep_bar(get_rep(npc_id))
	if bool(rb.get("maxed", false)):
		return 0
	var left: float = float(rb["needed"]) - float(rb["into"])
	return int(ceil(left / float(REP_GAIN["good"])))

# ---------- Пассивки персонажей ----------
# Хранение: data.passives.active = [{"npc": id, "pid": "p3"}, ...] (до
# GameData.PASSIVE_SLOTS штук). Открытость считается ОТ РЕПУТАЦИИ — репутация
# может упасть, тогда пассивка закрывается обратно и вылетает из активных.

func passive_unlocked(npc_id: String, pid: String) -> bool:
	var idx: int = GameData.passive_index(npc_id, pid)
	if idx < 0:
		return false
	return get_rep_level(npc_id) >= idx + 1

# Активные пассивки после чистки от «больше не открытых» и лишних сверх слотов.
func active_passives() -> Array:
	var pv: Dictionary = data.get("passives", {})
	var act: Array = pv.get("active", [])
	var clean: Array = []
	for a in act:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var npc_id: String = String(a.get("npc", ""))
		var pid: String = String(a.get("pid", ""))
		if passive_unlocked(npc_id, pid) and clean.size() < GameData.PASSIVE_SLOTS:
			clean.append({"npc": npc_id, "pid": pid})
	if clean.size() != act.size():
		pv["active"] = clean
		data["passives"] = pv
		_dirty = true
		save()
	return clean

func is_passive_active(npc_id: String, pid: String) -> bool:
	for a in active_passives():
		if String(a["npc"]) == npc_id and String(a["pid"]) == pid:
			return true
	return false

# Включить/выключить пассивку. Возвращает "on"|"off"|"locked"|"full".
func toggle_passive(npc_id: String, pid: String) -> String:
	if not passive_unlocked(npc_id, pid):
		return "locked"
	var act: Array = active_passives()
	var found := -1
	for i in act.size():
		if String(act[i]["npc"]) == npc_id and String(act[i]["pid"]) == pid:
			found = i
			break
	var res := "on"
	if found >= 0:
		act.remove_at(found)
		res = "off"
	elif act.size() >= GameData.PASSIVE_SLOTS:
		return "full"
	else:
		act.append({"npc": npc_id, "pid": pid})
	var pv: Dictionary = data.get("passives", {})
	pv["active"] = act
	data["passives"] = pv
	_dirty = true
	save()
	return res

# Суммарные числовые эффекты для заказа конкретного NPC: global-пассивки работают
# всегда, npc-пассивки — только «у своего» гостя. npc_id "" → только global.
func passive_fx(npc_id: String) -> Dictionary:
	var fx := {"score": 0.0, "craftTime": 0.0, "memTime": 0.0,
		"speedCap": 0.0, "rep": 0.0, "progress": 0.0, "tips": 0.0}
	for a in active_passives():
		var owner_id: String = String(a["npc"])
		var def: Dictionary = GameData.passive_def(owner_id, String(a["pid"]))
		if def.is_empty():
			continue
		if String(def["scope"]) == "npc" and owner_id != npc_id:
			continue
		for k in (def["fx"] as Dictionary):
			if fx.has(k) and typeof(def["fx"][k]) != TYPE_BOOL:
				fx[k] = float(fx[k]) + float(def["fx"][k])
	return fx

# Активна ли хоть одна пассивка-«уникалка» с булевым флагом (chargeAt2…).
func passive_flag(flag: String) -> bool:
	for a in active_passives():
		var def: Dictionary = GameData.passive_def(String(a["npc"]), String(a["pid"]))
		if not def.is_empty() and bool((def["fx"] as Dictionary).get(flag, false)):
			return true
	return false

# Сумма плоских прибавок по ключу (tipsFlat…).
func passive_flat(flag: String) -> float:
	var sum := 0.0
	for a in active_passives():
		var def: Dictionary = GameData.passive_def(String(a["npc"]), String(a["pid"]))
		if def.is_empty():
			continue
		var v = (def["fx"] as Dictionary).get(flag, null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			sum += float(v)
	return sum

# Начислить чаевые «мимо заказа» (плоская пассивка в конце цикла).
func add_tips(n: int) -> void:
	if n <= 0:
		return
	data["tips"]["balance"] = int(data["tips"]["balance"]) + n
	data["tips"]["lifetime"] = int(data["tips"]["lifetime"]) + n
	_dirty = true
	save()

# ---------- загрузка/сохранение ----------
func load_profile() -> void:
	var base := _empty_profile()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var txt := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				base = _deep_merge(base, parsed)
	base["last_seen_at"] = _now()
	base["version"] = SCHEMA_VERSION
	data = base

func save() -> void:
	# помечаем «грязным» и пишем сразу — профиль небольшой, дебаунс не нужен
	_dirty = true
	_write()

func _write() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		_dirty = false

func reset() -> void:
	data = _empty_profile()
	save()

# DEV: сразу много прогресса — опыт (все NPC/механики/пул/цикл открыты), чаевые
# и максимальная репутация со всеми (открывает УР.4 у всех). Для тестов.
func dev_boost() -> void:
	# xp кумулятивный: до макс. уровня прогрессии нужно ~116k суммарно — берём с запасом
	data["progression"]["xp"] = maxi(int(data["progression"].get("xp", 0)), 200000)
	data["tips"]["balance"] = int(data["tips"].get("balance", 0)) + 9999
	data["tips"]["lifetime"] = int(data["tips"].get("lifetime", 0)) + 9999
	data["skills"] = {"charges": SKILL_CHARGE_CAP, "perfect_counter": 0}   # полные заряды умений для теста
	for n in GameData.NPCS:
		var id: String = n["id"]
		ensure_npc(id)
		data["npc_reputation"][id]["value"] = 300.0
		data["npc_reputation"][id]["level"] = GameData.rep_level(300.0)
		if not data["progression"]["met_npcs"].has(id):
			data["progression"]["met_npcs"].append(id)
	save()

# Для синка с облаком (PotionAuth): выгрузка/загрузка всего профиля.
func export_data() -> Dictionary:
	return data.duplicate(true)

func import_data(d: Dictionary) -> void:
	data = _deep_merge(_empty_profile(), d)
	data["version"] = SCHEMA_VERSION
	save()

# base — заготовка схемы, saved — с диска. Возвращает saved, наложенный на base.
func _deep_merge(base: Dictionary, saved: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in saved.keys():
		var sv: Variant = saved[k]
		if base.has(k) and base[k] is Dictionary and sv is Dictionary:
			out[k] = _deep_merge(base[k], sv)
		else:
			out[k] = sv        # включая динамические ключи (npc_reputation.drone и т.п.)
	return out

# ---------- репутация ----------
func ensure_npc(npc_id: String) -> void:
	if npc_id == "":
		return
	if not data["npc_reputation"].has(npc_id):
		data["npc_reputation"][npc_id] = {"value": 0.0, "level": 0}
	if not data["npc_stats"].has(npc_id):
		data["npc_stats"][npc_id] = _empty_npc_stats()

func get_rep(npc_id: String) -> float:
	if data["npc_reputation"].has(npc_id):
		return float(data["npc_reputation"][npc_id]["value"])
	return 0.0

func get_rep_level(npc_id: String) -> int:
	return GameData.rep_level(get_rep(npc_id))

# Изменить репутацию на delta (может быть отрицательной — «Погром»). Не ниже 0.
func adjust_rep(npc_id: String, delta: float) -> void:
	ensure_npc(npc_id)
	var rep: Dictionary = data["npc_reputation"][npc_id]
	rep["value"] = maxf(0.0, float(rep["value"]) + delta)
	rep["level"] = GameData.rep_level(float(rep["value"]))

func npc_stats(npc_id: String) -> Dictionary:
	ensure_npc(npc_id)
	return data["npc_stats"][npc_id]

# ---------- запись результата раунда ----------
# grade: "perfect"|"good"|"swill"|"bad". time_frac — доля потраченного времени
# (0..1), для «быстрых» идеалов. reg_level — выбранная сложность УР.1-4 (влияет
# на ленту и hard/level4). focus — "bubbles"|"color"|"size"|"" (фокус-заказ).
# Возвращает сводку изменений (для анимаций экрана результата).
func record_result(npc_id: String, tier: int, overall: float, grade: String,
		reward: int, sticker_name: String = "",
		time_frac: float = 1.0, reg_level: int = 1,
		focus: String = "", rating_mult: float = 1.0, no_points: bool = false,
		neg_mult: float = 1.0, tip_mult: float = 1.0, flat_bonus: int = 0,
		pfx: Dictionary = {}) -> Dictionary:
	ensure_npc(npc_id)
	# pfx — эффекты пассивок, зафиксированные на этот заказ (см. passive_fx)
	var pf_score: float = 1.0 + float(pfx.get("score", 0.0))
	var pf_speed: float = float(pfx.get("speedCap", 0.0))
	var pf_rep: float = 1.0 + float(pfx.get("rep", 0.0))
	var pf_prog: float = 1.0 + float(pfx.get("progress", 0.0))
	var pf_tips: float = 1.0 + float(pfx.get("tips", 0.0))
	# вклад в «коллекционный» прогресс (лента идеальных / взвешенные ачивки)
	var prog_w: float = GameData.ribbon_weight(reward, reg_level) * pf_prog
	var is_perfect := grade == "perfect"
	var is_good := grade == "good" or is_perfect     # «годнота+»
	var is_bad := grade == "bad"
	var hard := reg_level >= 3
	var level4 := reg_level == 4

	# --- общая статистика ---
	var st: Dictionary = data["stats"]
	st["total_orders"] += 1
	st["stickers_lifetime"][grade] += 1
	# дельта рейтинга (может быть отрицательной: пойло/брак отнимают)
	var sd: Dictionary = GameData.score_delta(overall, grade, tier, reward, reg_level, time_frac, pf_score, pf_speed)
	var points: int = int(sd["delta"])
	# множитель рейтинга: механика гостя + «Погром»/«Утка» на плюс; «Утка» усиливает и штраф
	if points > 0 and rating_mult != 1.0:
		points = int(round(points * rating_mult))
	elif points < 0 and neg_mult != 1.0:
		points = int(round(points * neg_mult))
	points += flat_bonus                       # «Звёздная соль» — фиксированная прибавка
	# Тот-Кто-Ждёт: при <99% рейтинг не начисляется (только стикер)
	if no_points:
		points = 0
	var speed_pct: int = int(sd["speed_pct"])
	if points > 0:
		st["total_score_earned"] += points     # lifetime — только заработанное
	if is_good:                                 # взвешенный прогресс (ачивка «Мастер смесей»)
		st["weighted_progress"] = float(st.get("weighted_progress", 0.0)) + prog_w

	# --- серии ---
	var sk: Dictionary = data["streaks"]
	sk["perfect_current"] = sk["perfect_current"] + 1 if is_perfect else 0
	sk["perfect_best"] = maxi(sk["perfect_best"], sk["perfect_current"])
	sk["goodplus_current"] = sk["goodplus_current"] + 1 if is_good else 0
	sk["goodplus_best"] = maxi(sk["goodplus_best"], sk["goodplus_current"])
	sk["bad_current"] = sk["bad_current"] + 1 if is_bad else 0
	sk["bad_best"] = maxi(sk["bad_best"], sk["bad_current"])

	# --- лента идеальных (вклад зависит от тира персонажа и сложности УР) ---
	if is_perfect:
		var rb: Dictionary = data["perfect_ribbon"]
		rb["count"] = float(rb["count"]) + prog_w
		while float(rb["count"]) >= GameData.RIBBON_FULL:
			rb["platinum_count"] = int(rb["platinum_count"]) + 1
			rb["count"] = float(rb["count"]) - GameData.RIBBON_FULL

	# --- статы по NPC ---
	var ns: Dictionary = data["npc_stats"][npc_id]
	ns["orders"] += 1
	ns["picks_cycle"] = int(ns.get("picks_cycle", 0)) + 1
	ns["picks_cycle_best"] = maxi(int(ns.get("picks_cycle_best", 0)), int(ns["picks_cycle"]))
	if is_perfect: ns["perfects"] += 1
	elif is_good: ns["goods"] += 1
	elif is_bad: ns["bads"] += 1
	ns["perfect_streak"] = ns["perfect_streak"] + 1 if is_perfect else 0
	ns["perfect_streak_best"] = maxi(ns["perfect_streak_best"], ns["perfect_streak"])
	ns["no_bad_streak"] = 0 if is_bad else ns["no_bad_streak"] + 1
	ns["no_bad_streak_best"] = maxi(ns["no_bad_streak_best"], ns["no_bad_streak"])
	if is_perfect:
		if time_frac <= 1.0 / 3.0: ns["fast_perfects"] += 1
		if hard: ns["hard_perfects"] += 1
		if level4: ns["level4_perfects"] += 1
		ns["weighted"] = float(ns.get("weighted", 0.0)) + prog_w
		if focus != "" and ns["focus_perfects"].has(focus):
			ns["focus_perfects"][focus] += 1

	# --- репутация ---
	var rep: Dictionary = data["npc_reputation"][npc_id]
	var lvl_before := GameData.rep_level(float(rep["value"]))
	var rep_before := float(rep["value"])
	var rep_gain: float = float(REP_GAIN.get(grade, 0.0))
	if rep_gain > 0.0:
		rep_gain *= pf_rep                     # пассивка rep — только на ПРИРОСТ
	rep["value"] = maxf(0.0, rep_before + rep_gain)
	var lvl_after := GameData.rep_level(float(rep["value"]))
	rep["level"] = lvl_after

	# --- чаевые ---
	var tip := int(round(reward * float(TIP_FACTOR.get(grade, 0.0)) * tip_mult * pf_tips))
	if tip > 0:
		data["tips"]["balance"] += tip
		data["tips"]["lifetime"] += tip

	# --- виденный стикер ---
	if sticker_name != "":
		mark_sticker_seen(grade, sticker_name)

	# --- встреченные NPC ---
	if not data["progression"]["met_npcs"].has(npc_id):
		data["progression"]["met_npcs"].append(npc_id)

	save()
	return {
		"points": points, "speed_pct": speed_pct, "tip": tip,
		"rep_before": rep_before, "rep_after": float(rep["value"]),
		"level_before": lvl_before, "level_after": lvl_after,
		"level_up": lvl_after > lvl_before,
	}

# Завершение цикла: рейтинг цикла идёт в опыт (прогрессия), счётчик циклов,
# рекорд. Возвращает {xp_before, xp_after, cycles}.
func end_cycle(cycle_score: int) -> Dictionary:
	var st: Dictionary = data["stats"]
	var pr: Dictionary = data["progression"]
	var xp_before := int(pr.get("xp", 0))
	pr["xp"] = maxi(0, xp_before + cycle_score)   # опыт не уходит ниже нуля
	st["cycles_completed"] = int(st.get("cycles_completed", 0)) + 1
	st["best_cycle_score"] = maxi(int(st.get("best_cycle_score", 0)), cycle_score)
	save()
	return {"xp_before": xp_before, "xp_after": int(pr["xp"]), "cycles": int(st["cycles_completed"])}

# ---------- Локальный лидерборд (fallback, когда не в аккаунте) ----------
func lb_local_all() -> Array:
	return data.get("leaderboard", [])

# Добавить/обновить запись (одна строка на ник — храним ВЫСШИЙ счёт).
func lb_local_add(nick: String, score: int) -> void:
	var lst: Array = (data.get("leaderboard", []) as Array).duplicate()
	var best: int = score
	var kept: Array = []
	for e in lst:
		if String(e.get("name", "")) == nick:
			best = maxi(best, int(e.get("score", 0)))
		else:
			kept.append(e)
	var d: Dictionary = Time.get_date_dict_from_system()
	kept.append({"name": nick, "score": best, "date": "%02d.%02d.%d" % [d["day"], d["month"], d["year"]]})
	kept.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	data["leaderboard"] = kept.slice(0, mini(50, kept.size()))
	save()

# ---------- Магазин / инвентарь (Фаза 6) ----------
func tips_balance() -> int:
	return int((data.get("tips", {}) as Dictionary).get("balance", 0))

func item_count(id: String, grade: int) -> int:
	return int((data.get("inventory", {}) as Dictionary).get("%s_%d" % [id, grade], 0))

func inventory_all() -> Dictionary:
	return data.get("inventory", {})

# Купить (списать чаевые, +1 в инвентарь). false = не хватило баланса.
func buy_item(id: String, grade: int, price: int) -> bool:
	if tips_balance() < price:
		return false
	data["tips"]["balance"] = tips_balance() - price
	var inv: Dictionary = data.get("inventory", {})
	var key: String = "%s_%d" % [id, grade]
	inv[key] = int(inv.get(key, 0)) + 1
	data["inventory"] = inv
	save()
	return true

# Потратить один предмет. false = нет в наличии.
func consume_item(id: String, grade: int) -> bool:
	var inv: Dictionary = data.get("inventory", {})
	var key: String = "%s_%d" % [id, grade]
	var c: int = int(inv.get(key, 0))
	if c <= 0:
		return false
	inv[key] = c - 1
	data["inventory"] = inv
	save()
	return true

# Сброс счётчика выборов гостя за цикл (вызывать в начале цикла).
func reset_picks_cycle() -> void:
	for id in data["npc_stats"].keys():
		data["npc_stats"][id]["picks_cycle"] = 0
	save()

func mark_sticker_seen(cat: String, name: String) -> void:
	var seen: Array = data["stats"]["stickers_seen"][cat]
	if not seen.has(name):
		seen.append(name)
		save()

func has_met(npc_id: String) -> bool:
	return data["progression"]["met_npcs"].has(npc_id)

func _now() -> int:
	return int(Time.get_unix_time_from_system())
