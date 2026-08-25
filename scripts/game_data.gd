extends Node
## Слой данных, портированный из браузерной игры (content.js). Автозагрузка
## (singleton `GameData`). Только константы/справочники — без состояния игрока
## (это в [PotionProfile]). RU-тексты; EN и фокус-фразы (ff) добавим позже.
##
## Источник: C:\Users\KDFX Modes\Documents\Potion_game_git\content.js

# ---------- Пороги результата (game.js finalizeResult) ----------
# У тир-5 пороги строже. grade() возвращает "perfect"/"good"/"swill"/"bad".
func good_threshold(tier: int) -> float: return 0.85 if tier >= 5 else 0.80
func perfect_threshold(tier: int) -> float: return 0.97 if tier >= 5 else 0.95
func swill_threshold(tier: int) -> float: return 0.62 if tier >= 5 else 0.55

func grade(overall: float, tier: int) -> String:
	if overall >= perfect_threshold(tier): return "perfect"
	if overall >= good_threshold(tier): return "good"
	if overall >= swill_threshold(tier): return "swill"
	return "bad"

# Множители рейтинга по выбранной сложности УР (content.js).
# Премия за риск: чем выше сложность, тем больше параметров (2 → 5) и тем ниже
# ожидаемое качество, поэтому множитель обязан расти. Но разброс был 4.7x и
# вместе с разбросом наград по тирам давал 32-кратную разницу между худшей и
# лучшей карточкой — выбор решал в разы больше, чем сама игра.
const REG_DIFF_REWARD_MULT := {1: 0.45, 2: 0.7, 3: 1.0, 4: 1.35}

# Качество входит в награду нелинейно: раньше идеал стоил всего на 20% дороже
# годноты, и стараться было незачем. Степень 1.8 плюс премия за идеал дают
# разницу в 1.8 раза.
const QUALITY_POWER := 1.8
const PERFECT_BONUS := 1.35
const SPEED_BONUS_MULT := {1: 0.0, 2: 0.35, 3: 0.65, 4: 0.5}

# Дельта рейтинга за заказ (game.js finalizeResult). МОЖЕТ БЫТЬ ОТРИЦАТЕЛЬНОЙ:
#  good/perfect → плюс (+ бонус за скорость), пойло → малый ±, брак → минус.
# time_frac — доля потраченного времени (0 быстро .. 1 весь таймер).
# Возвращает {delta, speed_pct}.
# score_mult / speed_cap_bonus — пассивки (score умножает награду, speedCap
# поднимает потолок бонуса за скорость).
func score_delta(overall: float, grade_str: String, tier: int, reward: int, reg_level: int, time_frac: float,
		score_mult: float = 1.0, speed_cap_bonus: float = 0.0) -> Dictionary:
	var eff: float = float(reward) * float(REG_DIFF_REWARD_MULT.get(reg_level, 1.0)) * score_mult
	var third: float = 1.0 / 3.0
	var time_factor: float = 1.0 if time_frac <= third else maxf(0.0, 1.0 - (time_frac - third) / (1.0 - third))
	var delta: int = 0
	var speed_pct: int = 0
	if grade_str == "good" or grade_str == "perfect":
		var speed_frac: float = (float(SPEED_BONUS_MULT.get(reg_level, 0.5)) + speed_cap_bonus) * overall * time_factor
		# Нелинейное качество + премия за идеал: линейный overall делал разницу
		# между «попал точно» и «попал примерно» почти незаметной.
		var q: float = pow(overall, QUALITY_POWER)
		if grade_str == "perfect":
			q *= PERFECT_BONUS
		delta = int(round(eff * q * (1.0 + speed_frac)))
		speed_pct = int(round(speed_frac * 100.0))
	elif grade_str == "swill":
		var band: float = maxf(0.0001, good_threshold(tier) - swill_threshold(tier))
		var f: float = clampf((overall - swill_threshold(tier)) / band, 0.0, 1.0)
		delta = int(round(eff * (f - 0.5) * 0.30))      # ±: у нижнего края полосы минус
	else:  # bad
		delta = -int(round(eff * (1.0 - overall)))
	return {"delta": delta, "speed_pct": speed_pct}


# ---------- Тайминги заказа ----------
# Оригинал хранил memorize_ms/craft_ms по тирам и умножал их на общие
# коэффициенты. Порт эти значения не читал вовсе и жил на двух константах
# (2.5 с / 14 с), из-за чего разница между тирами исчезла: показ был короче
# задуманного у всех, а варка — длиннее у всех, кроме первого тира (на пятом
# втрое). Здесь один источник времени для всей игры.
const MEM_TIME_SCALE := 0.7
const CRAFT_TIME_SCALE := 0.5

# Число оцениваемых параметров растёт с уровнем (2 → 5), а время — медленнее.
# На УР.4 на каждый параметр остаётся меньше секунд, чем на УР.1: в этом и
# состоит требование к умению, а не в том, что «стало мельче».
const MEM_LEVEL_MULT := {1: 0.78, 2: 0.92, 3: 1.06, 4: 1.20}
const CRAFT_LEVEL_MULT := {1: 0.72, 2: 0.88, 3: 1.04, 4: 1.18}

# Пол: ниже этого задача перестаёт быть выполнимой независимо от тира.
const MIN_MEM_PER_PARAM := 0.62
const MIN_CRAFT_PER_PARAM := 1.5
# Потолок на базу (до налога механики): у первого тира база и так длинная, и с
# ростом уровня заказ раздувался до 21 секунды — это уже не сложно, а долго.
const MAX_CRAFT_BASE := 13.5

# «Налог» механики — сколько секунд она съедает ДО того, как игрок вообще
# дотянется до регуляторов. Раньше шесть механик правили время сами, прямо в
# craft_start и вразнобой, а девятнадцать не правили никак — включая те, где
# работы руками больше всего.
const MECH_CRAFT_TAX := {
	# Тяжёлые: отдельная подзадача руками
	"guild_inspector": 8.0,   # фазы показа нет, цель вычитывается из листа допусков
	"swarm_navigator": 5.5,   # найти нужные детали среди полутора десятков и перетащить
	"nebula_chef": 5.0,       # угадать форму сосуда вдобавок к параметрам
	"janitor": 4.0,           # оттереть 79% окна: 1950-3250 px мазка по уровню
	"vex": 4.0,               # разложить 3-5 сгустков по узлам сетки
	"trucker_chrome": 4.0,    # было +4.0 прямо в механике
	"marketer": 3.5,          # полноэкранные миниигры 1-3 раза за заказ
	"logic9": 3.0,            # было ×1.5
	"archivist": 3.0,         # было ×1.5, глиф-дождь поверх окна
	# Средние: повторяющаяся помеха
	"catlady": 2.5,           # лапы возвращаются каждые 2.6-5.2 с
	"twofaced_priestess": 2.5,# два спектра и два счётчика
	"plasma_bartender": 2.5,  # сосуд летает, целиться сложнее
	# Лёгкие: помеха восприятию, лишних действий нет
	"apothecary_mo": 1.5,     # размытие и обесцвечивание — приходится переспрашивать глазами
	"supernova_child": 1.5,   # наклон плюс вторая высота
	"racer_kai": 1.5,
	"dj_pulsar": 1.5,
	"fashionista": 1.0,
	"pete": 1.0,              # «градус» мутит банку
	# Остальные — чистые ползунки, налога нет:
	# drone, tentacloid, gourmet_vega, perfumer, intern_beep, last_of_ir,
	# engineer (свой ввод вместо ползунков), collector_gz (сетка вместо ползунков),
	# the_waiter (таймера нет вовсе)
}

# Сколько параметров оценивается на уровне (для пола времени).
func _active_count(level: int) -> int:
	return 5 if level >= 4 else (level + 1)

# Время показа и варки для конкретного гостя на конкретной сложности, секунды.
# Гость может переопределить memorize_ms/craft_ms — тогда берётся его значение.
func order_times(npc: Dictionary, level: int) -> Dictionary:
	var cfg: Dictionary = npc_config(npc)
	var n: int = _active_count(level)
	var mem: float = float(cfg.get("memorize_ms", 5750)) * MEM_TIME_SCALE / 1000.0
	mem *= float(MEM_LEVEL_MULT.get(level, 1.0))
	mem = maxf(mem, MIN_MEM_PER_PARAM * float(n))
	var craft: float = float(cfg.get("craft_ms", 18354)) * CRAFT_TIME_SCALE / 1000.0
	craft *= float(CRAFT_LEVEL_MULT.get(level, 1.0))
	craft = clampf(craft, MIN_CRAFT_PER_PARAM * float(n), MAX_CRAFT_BASE)
	craft += float(MECH_CRAFT_TAX.get(String(npc.get("id", "")), 0.0))
	return {"mem": mem, "craft": craft}

# ---------- Цвета тиров (как в веб: t1..t5) ----------
const TIER_COLORS := {
	1: Color("6dff8f"), 2: Color("ffe14d"), 3: Color("ff9e3d"),
	4: Color("ff5d6a"), 5: Color("c07bff"),
}

# ---------- Прогрессия/репутация (content.js) ----------
const STAGE_TABLE := [[1, 1, 1], [2, 2, 3], [3, 4, 4], [4, 4, 4]]
const REP_LEVELS := [27, 67, 120, 185, 265]      # уровень N достигнут при value >= REP_LEVELS[N-1]

# ---------- Фаза 3: фокус-заказы и модификаторы ----------
# ФОКУС (открывается с прогрессии "modifiers", ур.3): выделяет группу параметров —
# их вес в оценке ×2.2, у остальных ×0.55, награда за заказ ×1.25.
const FOCUS_KEYS := {
	"bubbles": ["count", "bsize"],
	"color":   ["color", "colorB", "sat"],
	"size":    ["volume", "bsize"],
}
const FOCUS_META := {
	"bubbles": {"icon": "🫧", "name": "сгустки",
		"desc": "Строже к сгусткам, мягче к прочему. Награда выше."},
	"color":   {"icon": "🎨", "name": "спектр",
		"desc": "Строже к спектру, мягче к прочему. Награда выше."},
	"size":    {"icon": "📏", "name": "габариты",
		"desc": "Строже к габаритам, мягче к прочему. Награда выше."},
}
const FOCUS_W_ON := 2.2      # множитель веса фокусного параметра
const FOCUS_W_OFF := 0.55    # множитель веса нефокусных
const FOCUS_REWARD := 1.25   # награда за фокус-заказ
# «ПОВЕДЕНЧЕСКИЕ» модификаторы (открываются с "modifiers_new3", ур.4):
const MOD_META := {
	"timer":   {"icon": "⏱", "name": "Таймер",
		"desc": "Времени на воссоздание на 25% меньше."},
	"duck":    {"icon": "🦆", "name": "Важная утка",
		"desc": "Больше рейтинга за успех, больше штраф за брак."},
	"rampage": {"icon": "💥", "name": "Погром",
		"desc": "×2 награда. Гость уходит и портит репутацию другим."},
}
const MOD_FOCUS_EXCLUDE := ["vex", "perfumer", "collector_gz"]   # без фокуса/модов (кастомная раскладка)

# ---------- Фаза 6: магазин (предметы-расходники) ----------
# Каждый предмет — 3 грейда (сильнее+дороже). Грейд i доступен по прогрессии
# ("shop_grade_1/2/3" на ур.4/5/8). use: "select" (эффект след. заказу) или
# "craft" (текущему заказу). Значения эффекта — per-grade.
const SHOP_ITEMS := [
	{"id": "stopwatch", "icon": "⏱", "use": "select", "effect": "time",
		"name": "Секундомер", "desc": "Добавляет время на воссоздание следующего заказа.",
		"grades": [{"price": 80, "sec": 1.0, "label": "+1с"}, {"price": 260, "sec": 2.0, "label": "+2с"}, {"price": 700, "sec": 4.0, "label": "+4с"}]},
	{"id": "clarity", "icon": "💧", "use": "select", "effect": "memtime",
		"name": "Тоник ясности", "desc": "Добавляет время на запоминание следующего заказа.",
		"grades": [{"price": 90, "sec": 1.0, "label": "+1с"}, {"price": 300, "sec": 2.0, "label": "+2с"}, {"price": 800, "sec": 3.5, "label": "+3.5с"}]},
	{"id": "salt", "icon": "🧂", "use": "craft", "effect": "flatbonus",
		"name": "Звёздная соль", "desc": "Фиксированная прибавка рейтинга за годный+ заказ.",
		"grades": [{"price": 110, "flat": 40, "label": "+40"}, {"price": 340, "flat": 90, "label": "+90"}, {"price": 900, "flat": 180, "label": "+180"}]},
	{"id": "weight", "icon": "⚖", "use": "craft", "effect": "rewardmult",
		"name": "Утяжелённый шейкер", "desc": "Увеличивает рейтинг за годный/идеальный заказ.",
		"grades": [{"price": 160, "mult": 0.15, "label": "+15%"}, {"price": 520, "mult": 0.30, "label": "+30%"}, {"price": 1400, "mult": 0.50, "label": "+50%"}]},
	{"id": "chip", "icon": "🎲", "use": "craft", "effect": "chip",
		"name": "Фишка неудачника", "desc": "В конце меняет итоговый рейтинг на случайную величину.",
		"grades": [{"price": 100, "lo": -0.05, "hi": 0.05, "label": "−5%…+5%"}, {"price": 320, "lo": -0.03, "hi": 0.07, "label": "−3%…+7%"}, {"price": 850, "lo": 0.0, "hi": 0.10, "label": "0…+10%"}]},
	{"id": "paprika", "icon": "🌶", "use": "craft", "effect": "repboost",
		"name": "Космическая паприка", "desc": "За годноту+ гость даст больше репутации, за брак — сильнее обидится.",
		"grades": [{"price": 150, "rep": 2, "label": "±2 реп."}, {"price": 480, "rep": 4, "label": "±4 реп."}, {"price": 1300, "rep": 6, "label": "±6 реп."}]},
	{"id": "shield", "icon": "🪢", "use": "craft", "effect": "shield",
		"name": "Страховочный трос", "desc": "Смягчает потерю рейтинга, если заказ ушёл в брак.",
		"grades": [{"price": 130, "cut": 0.5, "label": "−½ штрафа"}, {"price": 420, "cut": 0.75, "label": "−¾ штрафа"}, {"price": 1100, "cut": 1.0, "label": "без потерь"}]},
	{"id": "eye", "icon": "👁", "use": "craft", "effect": "nudge",
		"name": "Барменский глаз", "desc": "В конце подвинет ползунки на деление ближе к верному.",
		"grades": [{"price": 180, "count": 1, "label": "1 ползунок"}, {"price": 560, "count": 2, "label": "2 ползунка"}, {"price": 1500, "count": 99, "label": "все"}]},
	{"id": "haste", "icon": "⚡", "use": "craft", "effect": "speedlock",
		"name": "Ускоритель варки", "desc": "Гарантирует минимальный бонус за скорость.",
		"grades": [{"price": 140, "lock": 0.5, "label": "½ бонуса"}, {"price": 450, "lock": 0.75, "label": "¾ бонуса"}, {"price": 1200, "lock": 1.0, "label": "полный"}]},
	{"id": "jigger", "icon": "🥃", "use": "craft", "effect": "jigger",
		"name": "Джиггер", "desc": "Отключает случайный регулятор — он больше не влияет на рейтинг.",
		"grades": [{"price": 120, "n": 1, "label": "1 регулятор"}, {"price": 380, "n": 1, "label": "1 регулятор"}, {"price": 1000, "n": 2, "label": "2 регулятора"}]},
]

func shop_item(id: String) -> Dictionary:
	for it in SHOP_ITEMS:
		if it["id"] == id:
			return it
	return {}

# доступен ли грейд i (0..2) по прогрессии: shop_grade_1/2/3 на ур.4/5/8
func shop_grade_unlocked(grade: int, xp: int) -> bool:
	return prog_mech_unlocked("shop_grade_%d" % (grade + 1), xp)

# ---------- Инспектор Гильдии: «Дело о приёмке» ----------
# Показа образца нет — цель зашифрована в бюрократическом тексте (значения как
# «отметка №X из N»), порядок фраз перемешан по сиду. Оценка — по допуску ±tol.
const INSPECTOR_TEMPLATES := [
	"Комиссия по приёмке рассмотрела образец и приобщила его к делу. {SENTENCES} Решением комиссии: любое отклонение от перечисленного, не превышающее {TOL} деления в ту или иную сторону по каждому пункту в отдельности, признаётся допустимым и не влияет на итоговую оценку приёмки.",
	"Форма 7-Б заполнена и заверена печатью Гильдии. {SENTENCES} Границы приёмки едины для всех пунктов и составляют {TOL} деления в любую сторону от указанного — превышение по отдельному пункту фиксируется как нарушение, но не отменяет заявку целиком.",
	"Плановая проверка, протокол №{TOL}7-К. {SENTENCES} Допуск по каждому из перечисленных показателей составляет {TOL} деления; всё, что уложилось в эти границы, комиссия принимает без возражений.",
	"Заявка на приёмку смеси принята к рассмотрению. {SENTENCES} Податель обязан удержать каждый из перечисленных показателей в границах ± {TOL} деления от указанного — прочие детали заявки на решение комиссии не влияют.",
]
const INSPECTOR_PHRASE := {
	"color":  "спектр смеси обязан лечь ровно на отметку {v}",
	"colorB": "второй спектр градиента должен встать на {v}",
	"volume": "объём сосуда обязан встать на отметке {v}",
	"size2":  "высота сосуда отдельно выставляется на {v}",
	"bsize":  "калибр каждого сгустка выставлен на отметке {v}",
	"count":  "внутри обязано плавать ровно {v} сгустков по счёту",
	"sat":    "накал цвета выставляется на отметке {v}",
}
const REP_L4_UNLOCK_LEVEL := 1                    # с какого ур. репутации открыт УР.4 персонажа

# ---------- Фаза 9: «грейд выше своего» ----------
# Персонаж низкого тира изредка выпадает как заказ более ВЫСОКОГО тира: числовые
# характеристики целевого тира (больше сгустков/мельче деления/накал) + повышенная
# награда. Личность/имя/механика/тайминги — родные. Вес выпадения по разрыву тиров.
const GRADE_WEIGHT := [1.0, 0.15, 0.05, 0.02, 0.008]   # [родной, +1 тир, +2, +3, +4]
const GRADE_REWARD_MULT := [1.0, 1.6, 2.3, 3.2, 4.5]

func grade_up_cfg(npc: Dictionary, target_tier: int) -> Dictionary:
	var base_tier: int = int(npc.get("tier", 1))
	var gap: int = mini(target_tier - base_tier, GRADE_REWARD_MULT.size() - 1)
	if gap <= 0:
		return npc
	var clone: Dictionary = npc.duplicate(true)
	clone["tier"] = target_tier
	clone["graded_from"] = base_tier
	var t: Dictionary = TIERS[target_tier]
	# «зернистость» регуляторов и число сгустков — целевого тира
	clone["color_steps"] = t["color_steps"]
	clone["size_steps"] = t["size_steps"]
	clone["count_max"] = t["count_max"]
	clone["bsize_steps"] = t["bsize_steps"]
	# тайминги — родные (личность персонажа не трогаем)
	clone["memorize_ms"] = int(npc.get("memorize_ms", TIERS[base_tier]["memorize_ms"]))
	clone["craft_ms"] = int(npc.get("craft_ms", TIERS[base_tier]["craft_ms"]))
	# награда масштабируется к целевому грейду
	var base_reward: int = int(npc.get("reward", TIERS[base_tier]["reward"]))
	clone["reward"] = int(round(float(base_reward) * GRADE_REWARD_MULT[gap]))
	return clone
const LORE_PHRASE_CHANCE := 0.35

# Гости, у которых уникальная механика работает С УР.1 (а не только на УР.4).
# Остальные механики — только на УР.4. См. npc-mechanics в памяти / game.js.
const MECH_FROM_L1 := ["drone", "janitor", "trucker_chrome", "collector_gz",
	"fashionista", "tentacloid", "dj_pulsar", "logic9", "racer_kai", "apothecary_mo",
	"perfumer", "swarm_navigator", "vex", "guild_inspector", "gourmet_vega",
	"catlady", "engineer", "marketer",
	# особые типы (dual_size/no_timer/shape/gradient/moving/trust) — работают на ВСЕХ уровнях
	"supernova_child", "the_waiter", "nebula_chef", "twofaced_priestess",
	"plasma_bartender", "last_of_ir",
	"pete"]   # «уровень жидкости» (fill) — с УР.1

func mech_active(id: String, level: int) -> bool:
	return level == 4 or id in MECH_FROM_L1

# ---------- Лента идеальных (perfect ribbon) ----------
# За каждый ИДЕАЛ лента растёт на (reward / BASELINE_TIER_REWARD) * PROGRESS_DIFF_WEIGHT[УР].
# То есть вклад тем больше, чем выше тир персонажа И чем выше выбранная сложность.
# Дотянула до RIBBON_FULL → платиновая лента (+1), остаток переносится.
const BASELINE_TIER_REWARD := 150           # награда тира 3 = «вес 1.0»
const PROGRESS_DIFF_WEIGHT := {1: 0.12, 2: 0.4, 3: 1.0, 4: 1.3}
const RIBBON_FULL := 20.0

func ribbon_weight(reward: int, reg_level: int) -> float:
	var tier_w: float = float(reward) / float(BASELINE_TIER_REWARD)
	var diff_w: float = float(PROGRESS_DIFF_WEIGHT.get(reg_level, 1.0))
	return tier_w * diff_w

func rep_level(value: float) -> int:
	var lvl := 0
	for t in REP_LEVELS:
		if value >= float(t): lvl += 1
		else: break
	return lvl

# Прогресс репутации ВНУТРИ текущего уровня (для шкалы-заполнения):
# {level, into, needed, maxed}.
func rep_bar(value: float) -> Dictionary:
	var lvl: int = rep_level(value)
	var prev: float = float(REP_LEVELS[lvl - 1]) if lvl > 0 else 0.0
	if lvl >= REP_LEVELS.size():
		return {"level": lvl, "into": 1.0, "needed": 1.0, "maxed": true}
	var nxt: float = float(REP_LEVELS[lvl])
	return {"level": lvl, "into": value - prev, "needed": nxt - prev, "maxed": false}

# ---------- Числовые характеристики по тиру (DIFFICULTIES в content.js) ----------
# EXTRA_NPCS/SPECIAL_ORDERS наследуют числа по своему тиру; отдельные NPC
# переопределяют часть полей (см. overrides в самих записях).
const TIERS := {
	# reward: низ подтянут (50 → 75), верх не тронут — разброс по тирам с 4.8x до 3.2x.
	# Заодно это ускоряет раннюю прогрессию, которая была слишком медленной.
	1: {"memorize_ms": 6900, "craft_ms": 29260, "color_steps": 6,  "size_steps": 5,  "count_max": 5,  "bsize_steps": 5,  "reward": 75},
	2: {"memorize_ms": 6325, "craft_ms": 22610, "color_steps": 9,  "size_steps": 7,  "count_max": 7,  "bsize_steps": 7,  "reward": 110},
	3: {"memorize_ms": 5750, "craft_ms": 18354, "color_steps": 14, "size_steps": 11, "count_max": 10, "bsize_steps": 11, "reward": 150},
	4: {"memorize_ms": 5175, "craft_ms": 13300, "color_steps": 24, "size_steps": 19, "count_max": 12, "bsize_steps": 19, "reward": 195},
	5: {"memorize_ms": 4600, "craft_ms": 9975,  "color_steps": 37, "size_steps": 26, "count_max": 14, "bsize_steps": 26, "reward": 240},
}

# Итоговые числа для NPC = числа тира + переопределения из записи NPC.
func npc_config(npc: Dictionary) -> Dictionary:
	var cfg: Dictionary = (TIERS[int(npc.get("tier", 1))] as Dictionary).duplicate()
	for k in ["memorize_ms", "craft_ms", "color_steps", "size_steps", "count_max", "bsize_steps", "reward"]:
		if npc.has(k): cfg[k] = npc[k]
	return cfg

# ---------- Стикеры (content.js STICKERS) ----------
# Первые BASE_STICKERS в каждой категории — базовые (падают всегда, случайно),
# остальные — особые (по условиям STICKER_SPECIALS, портируем позже).
const BASE_STICKERS := 3
const STICKERS := {
	"perfect": ["perfect1", "perfect2", "perfect3", "perfect4", "perfect5", "perfect6", "perfect7", "perfect8", "perfect9", "perfect10", "perfect11", "perfect12", "perfect13", "perfect14", "perfect15"],
	"good": ["good1", "good2", "good3", "good4", "good5", "good6", "good7", "good8", "good9"],
	"swill": ["swill1", "swill2", "swill3", "swill4", "swill5"],
	"bad": ["bad1", "bad2", "bad3", "bad4", "bad5", "bad6", "bad7", "bad8", "bad9"],
}

func sticker_path(name: String) -> String:
	return "res://assets/ui/%s.png" % name

# ---------- Общие ачивки (content.js GENERAL_ACHIEVEMENTS) ----------
# id, img (assets/ach/N.png), name, desc, t=[пороги по возрастанию]. Значение
# метрики считает main._ach_value(id) из профиля. manual — открываются вручную
# (пока не реализовано): tiers = число ступеней-подсказок.
const GENERAL_ACHIEVEMENTS := [
	{"id": "total_score", "img": "1", "name": "Казна лавки", "desc": "Суммарный рейтинг за всю историю лавки.", "t": [1000, 5000, 20000, 50000, 100000, 200000, 350000, 600000, 1000000]},
	{"id": "cycle_score", "img": "2", "name": "Рекордный цикл", "desc": "Лучший рейтинг за один цикл.", "t": [800, 1500, 2500, 4000, 6000, 8500, 12000]},
	{"id": "progress", "img": "3", "name": "Мастер смесей", "desc": "Взвешенный прогресс: годные/идеальные смеси × сложность.", "t": [50, 150, 300, 600, 1000, 2500, 5000, 10000]},
	{"id": "perfect_streak", "img": "4", "name": "Безупречность", "desc": "Лучшая серия идеалов подряд.", "t": [3, 5, 10, 15, 20, 30, 50]},
	{"id": "goodplus_streak", "img": "5", "name": "Конвейер", "desc": "Лучшая серия без единого брака.", "t": [10, 25, 50, 100, 200, 400]},
	{"id": "bad_streak", "img": "6", "name": "Чёрная полоса", "desc": "Серия браков подряд. Носи с гордостью.", "t": [3, 5, 10]},
	{"id": "swill_total", "img": "12", "name": "Разливщик пойла", "desc": "Сколько «пойла» ты налил за всю историю.", "t": [10, 40, 120, 300, 700]},
	{"id": "tips_total", "img": "13", "name": "Звонкая касса", "desc": "Всего чаевых за всю историю лавки.", "t": [100, 500, 2000, 6000, 15000, 40000]},
	{"id": "cycles", "img": "8", "name": "Ветеран лавки", "desc": "Завершено полных циклов.", "t": [5, 20, 50, 100, 250]},
	{"id": "orders", "img": "7", "name": "Поток заказов", "desc": "Всего выполнено заказов.", "t": [50, 200, 500, 1500, 4000, 10000]},
	{"id": "speedrun", "img": "9", "name": "Молния на пределе", "desc": "Идеал тира 5 на макс. сложности в первую треть таймера.", "manual": true, "tiers": 1},
	{"id": "leaderboard", "img": "10", "name": "Слава галактики", "desc": "Твоё место в глобальном рейтинге.", "manual": true, "tiers": 2},
]

func ach_icon_path(img: String) -> String:
	return "res://assets/ach/%s.png" % img

# Всего ступеней во всех общих ачивках (для «ОТКРЫТО X/N»).
func ach_total_tiers() -> int:
	var n := 0
	for a in GENERAL_ACHIEVEMENTS:
		n += int(a["tiers"]) if a.get("manual", false) else (a["t"] as Array).size()
	return n

# ---------- Ростер: 27 постоянных NPC (DIFFICULTIES + EXTRA_NPCS + SPECIAL_ORDERS) ----------
# type: normal|shape|gradient|moving. special: trust|matrix|dual_size|no_timer.
# Числовые поля указаны только там, где NPC переопределяет свой тир.
const NPCS := [
	# --- DIFFICULTIES (базовые пять, по одному на тир) ---
	{"id": "drone", "tier": 1, "type": "normal", "emoji": "🛰", "img": "drone", "level4": true,
		"name": "Служебный дрон", "flavors": [
			"Жидкость для омывателя звездолёта. Любая сойдёт.",
			"Смесь для протирки палубы. Без изысков.",
			"Стандартный заказ. Плюс-минус — не страшно."]},
	{"id": "tentacloid", "tier": 2, "type": "normal", "emoji": "🐙", "img": "tentacloid",
		"name": "Тентаклоид", "flavors": [
			"Моим щупальцам нравится, когда красиво. Сделай красиво.",
			"Смесь для настроения. Удиви меня, торговец.",
			"Что-нибудь эдакое. Ты понял. Или не понял. Сделай."]},
	{"id": "gourmet_vega", "tier": 3, "type": "normal", "emoji": "👾", "img": "gurman",
		"name": "Гурман с Веги", "flavors": [
			"Это приправа к ужину. Ошибёшься — ужин обидится.",
			"Тонкий вкус требует тонкой работы. Приступай.",
			"Мой прошлый поставщик плакал. Не повторяй его путь."]},
	{"id": "logic9", "tier": 4, "type": "normal", "emoji": "🤖", "img": "kai-9",
		"name": "Логик-9", "flavors": [
			"СМЕСЬ. ОХЛАЖДЕНИЕ. РЕАКТОР. ТОЧНОСТЬ. ОБЯЗАТЕЛЬНА.",
			"ОТКЛОНЕНИЕ. НЕДОПУСТИМО. ПОВТОРЯЮ. НЕДОПУСТИМО.",
			"ВВОД: ИДЕАЛ. ИНАЧЕ: ОТКАЗ. СИСТЕМА. ЖДЁТ."]},
	{"id": "last_of_ir", "tier": 5, "type": "normal", "special": "trust", "emoji": "👁", "img": "ir",
		"name": "Последний из Ир", "flavors": [
			"Моя раса угасает. Эта смесь — наш последний рассвет.",
			"Ты держишь в руках память миллиона поколений. Не урони.",
			"Сделай так, будто вселенная смотрит. Она смотрит."]},

	# --- EXTRA_NPCS ---
	{"id": "janitor", "tier": 1, "type": "normal", "emoji": "🪣", "img": "janitor",
		"name": "Уборщик Пятого Дока", "flavors": [
			"Ведро смеси для мытья шлюза. Только не пахучую.",
			"Мне бы попроще. Полы сами себя не отдраят.",
			"Что подешевле. Начальство всё равно не заметит."]},
	{"id": "intern_beep", "tier": 1, "type": "normal", "emoji": "📦", "img": "bip",
		"name": "Стажёр Бип", "flavors": [
			"Э-это мой первый заказ... Смесь. Пожалуйста. Любую?",
			"Шеф сказал взять смесь. Не сказал какую. Помогите.",
			"Я всё записал! Кажется. Смесь. Да. Смесь."]},
	{"id": "trucker_chrome", "tier": 1, "type": "normal", "emoji": "🚛", "img": "khrom",
		"name": "Дальнобойщик Хром", "flavors": [
			"Смесь в дорогу. Тыща парсеков впереди, не до изысков.",
			"Залей чего-нибудь. Гружёный стою, время — топливо.",
			"Как обычно. Ну, как обычно у вас тут наливают."]},
	{"id": "pete", "tier": 1, "type": "normal", "emoji": "🍺", "img": "pete",
		"name": "Пьяница Пит", "flavors": [
			"Плесни как обычно. И налей до краёв... или не до краёв, тебе решать.",
			"Смесь. Главное — сколько налито. Остальное я и не разгляжу уже.",
			"Ту же, что вчера. Уровень запомни — это важнее цвета, поверь старику."]},
	{"id": "fashionista", "tier": 2, "type": "normal", "emoji": "💅", "img": "fashionista",
		"name": "Модница с Кассиопеи", "flavors": [
			"Эта смесь пойдёт к моему новому панцирю. Постарайся.",
			"Хочу, чтобы все на станции обзавидовались.",
			"Сделай красиво. Красиво — это ты должен чувствовать."]},
	{"id": "collector_gz", "tier": 2, "type": "normal", "emoji": "🐌", "img": "collector",
		"name": "Коллекционер Гз", "flavors": [
			"В мою коллекцию не хватает... вот такой. Медленно повтори.",
			"Я собираю смеси триста лет. Удиви меня. Не спеша.",
			"Эта полка пустует уже decade. Заполни её достойно."]},
	{"id": "dj_pulsar", "tier": 2, "type": "normal", "emoji": "🎧", "img": "dj",
		"name": "Диджей Пульсар", "flavors": [
			"Нужна смесь под сегодняшний сет. Чтоб вайб совпал.",
			"Слушай ритм станции... вот под него и намешай.",
			"Сделай что-то, что звучит. Ты понял. Звучит!"]},
	{"id": "marketer", "tier": 2, "type": "normal", "emoji": "📺", "img": "marketer",
		"name": "Маркетолог с безлюдного спутника", "flavors": [
			"Смесь — по последнему тренду! Пульт настройки? О, он где-то там, ищи.",
			"Уникальное предложение! Регуляторы разбросаны — но работают не все, ха!",
			"Верю в тебя, партнёр! Крути что хочешь — сработает лишь то, что нужно."]},
	{"id": "perfumer", "tier": 3, "type": "normal", "emoji": "🧴", "img": "parfumer",
		"name": "Парфюмер Тысячи Лун", "flavors": [
			"Это база для аромата, который вспомнят через век.",
			"Нюанс. Всё решает нюанс. Приступай осторожно.",
			"Мои ноздри чувствуют ошибку до того, как ты её совершишь."]},
	{"id": "guild_inspector", "tier": 3, "type": "normal", "emoji": "🔍", "img": "inspector",
		"name": "Инспектор Гильдии", "flavors": [
			"Плановая проверка. Изготовьте образец по регламенту.",
			"Гильдия следит за качеством. Сегодня — за вашим.",
			"Отклонения фиксируются в протокол. Начинайте."]},
	{"id": "apothecary_mo", "tier": 3, "type": "normal", "emoji": "🦎", "img": "apothecary",
		"name": "Аптекарь Мо", "flavors": [
			"Это лекарство. Рука не должна дрогнуть. Твоя.",
			"Пациент ждёт. Дозировка — не место для творчества.",
			"Я доверяю тебе рецепт. Не заставляй жалеть."]},
	{"id": "engineer", "tier": 3, "type": "normal", "emoji": "🛰️", "img": "engineer",
		"name": "Инженер навигатора", "flavors": [
			"Смесь для юстировки курсографа. Ловить будешь на лету — образца я не дам.",
			"Настрой по зонам на шкалах. Стрелка бежит — жми «стоп» вовремя, вот и весь фокус.",
			"Мне некогда объяснять. Зелёное — верно. Указатель не ждёт. Работай."]},
	{"id": "swarm_navigator", "tier": 4, "type": "normal", "emoji": "🐝", "img": "swarm",
		"name": "Навигатор Роя", "flavors": [
			"МЫ говорим одним голосом. МЫ требуем точности.",
			"Рой чувствует фальшь тысячей рецепторов. МЫ ждём.",
			"Ошибка перед одним — ошибка перед всеми НАМИ."]},
	{"id": "vex", "tier": 4, "type": "normal", "emoji": "🔧", "img": "vex",
		"name": "Хирург-механик Векс", "flavors": [
			"Смесь пойдёт в открытый реактор. Представь мою руку. Не дрогни.",
			"Я не прощаю люфтов. Ни в железе, ни в людях.",
			"Пациент — крейсер на девять тысяч душ. Работай соответственно."]},
	{"id": "racer_kai", "tier": 4, "type": "normal", "emoji": "🏁", "img": "kai",
		"name": "Гонщица Кай", "flavors": [
			"Присадка в бак. Финал через час. Не тормози и не косячь.",
			"Мой болид чувствует смесь на первом же вираже. И я тоже.",
			"Секунды решают гонку. Точность решает секунды. Погнали."]},
	{"id": "catlady", "tier": 4, "type": "normal", "emoji": "🐈", "img": "catlady",
		"name": "Бабушка Мурра", "flavors": [
			"Смесь для моих деток. И не обращай внимания на лапки — они любопытные.",
			"Мурке нужна смесь. Точная. Если коты не мешают — значит, ты им не нравишься.",
			"Составь как надо, дорогуша. Только сперва прогони этих проглотов с прилавка."]},
	{"id": "archivist", "tier": 5, "type": "normal", "special": "matrix", "emoji": "📜", "img": "archivist",
		"name": "Хранитель Архива", "flavors": [
			"Эта смесь — закладка между главами вселенной. Не смажь чернила.",
			"Я записываю всё. Сегодня я запишу твою работу. Навсегда.",
			"Архив помнит каждую идеальную смесь. Их было четыре."]},
	{"id": "supernova_child", "tier": 5, "type": "normal", "special": "dual_size",
		"size_steps": 13, "memorize_ms": 6900, "craft_ms": 14963, "emoji": "🌟", "img": "supernova",
		"name": "Дитя Сверхновой", "flavors": [
			"я. родилось. вчера. из взрыва. хочу. попробовать. всё.",
			"ты. делаешь. красивое. сделай. мне. самое. красивое.",
			"мама. была. звездой. смесь. должна. быть. как. мама."]},
	{"id": "the_waiter", "tier": 5, "type": "normal", "special": "no_timer", "emoji": "⏳", "img": "waiter",
		"name": "Тот-Кто-Ждёт", "flavors": [
			"Я ждал этой смеси... дольше, чем существует твоя лавка. Подожду и точности — сколько нужно.",
			"Когда всё закончится — а всё закончится — останется только она. Пусть она будет точной, а не просто похожей.",
			"Спешить незачем — я никуда не тороплюсь. Но и снисхождения у меня почти не осталось."]},

	# --- SPECIAL_ORDERS (особый тип на всех уровнях; свои числа) ---
	{"id": "nebula_chef", "tier": 5, "type": "shape", "count_bias": "high", "emoji": "🦑", "img": "chef",
		"memorize_ms": 7475, "craft_ms": 26600, "color_steps": 10, "size_steps": 8, "count_max": 8, "bsize_steps": 8, "reward": 300,
		"name": "Шеф туманности", "flavors": [
			"Форма сосуда — часть рецепта. Мой соус этого требует!",
			"В моей кухне геометрия — это специя. Не перепутай силуэт!",
			"Сосуд не той формы испортит подачу. А подача — это всё."]},
	{"id": "twofaced_priestess", "tier": 5, "type": "gradient", "emoji": "🧿", "img": "twofaced",
		"memorize_ms": 8050, "craft_ms": 26600, "color_steps": 14, "size_steps": 8, "count_max": 8, "bsize_steps": 8, "reward": 300,
		"name": "Двуликая жрица", "flavors": [
			"Смесь должна переливаться, как двойной закат моего мира.",
			"Два спектра. Одно целое. Я почувствую фальшь кожей.",
			"Мои боги говорят двумя цветами. Передай их речь точно."]},
	{"id": "plasma_bartender", "tier": 5, "type": "moving", "emoji": "🍹", "img": "barmen",
		"memorize_ms": 8625, "craft_ms": 24073, "color_steps": 12, "size_steps": 8, "count_max": 10, "bsize_steps": 8, "reward": 300,
		"name": "Бармен плазма-бара", "flavors": [
			"Сгустки у меня в баре не сидят на месте! Лови ритм!",
			"Живая смесь! Живая! Считай на лету, торговец!",
			"Мой фирменный коктейль дышит и мечется. Уследи-ка."]},
]

# ---------- Прогрессия (content.js PROGRESSION) ----------
# Всё производное считается из накопленного xp (хранится в PotionProfile).
# Уровень открывает: больше карточек в дне (pool_size), длиннее цикл (cycle_days),
# новых NPC в пуле (npc_marks — доля at внутри шкалы уровня), механики.
const PROG_START_CYCLE_DAYS := 5
const PROG_START_POOL := 2
const PROG_START_NPCS := ["drone", "janitor", "intern_beep", "trucker_chrome", "pete", "collector_gz", "guild_inspector"]
# Механики, доступные с первого заказа. Раньше первая из них открывалась только
# на третьем уровне лавки — у слабого игрока это одиннадцать циклов голого ядра,
# и всё, чем игра отличается от других, он до этого просто не видел.
const PROG_START_MECHS := ["collection", "modifiers", "skill_1", "tips"]
const PROG_BEYOND_STEP := 5000    # рост требуемого xp за уровень сверх последнего
const PROG_BEYOND_TIPS := 200     # чаевые за уровень сверх последнего
# каждый уровень: xp (прирост до него), cycle_days/pool_size (переопределения),
# mechanics (что открывает), npc_marks [[доля_шкалы, id]...].
const PROG_LEVELS := [
	{"xp": 1200,  "cycle_days": 6, "mechanics": ["characters", "modifiers_new3"],
		"npc_marks": [[0.25, "tentacloid"], [0.5, "marketer"], [0.72, "fashionista"], [0.9, "dj_pulsar"]]},
	{"xp": 2400,  "mechanics": ["shop", "shop_grade_1"],
		"npc_marks": [[0.4, "gourmet_vega"], [0.85, "perfumer"]]},
	{"xp": 4000,  "cycle_days": 7, "mechanics": ["skill_2", "relations"],
		"npc_marks": [[0.3, "engineer"], [0.6, "apothecary_mo"]]},
	{"xp": 6400,  "mechanics": ["shop_grade_2", "modifiers_multi"],
		"npc_marks": [[0.4, "logic9"], [0.85, "swarm_navigator"]]},
	{"xp": 9600,  "cycle_days": 8, "pool_size": 3, "mechanics": ["skill_3"],
		"npc_marks": [[0.4, "vex"], [0.62, "catlady"], [0.85, "racer_kai"]]},
	{"xp": 14000, "mechanics": ["shop_grade_3"],
		"npc_marks": [[0.25, "last_of_ir"], [0.5, "archivist"], [0.72, "supernova_child"], [0.92, "the_waiter"]]},
	{"xp": 19000, "cycle_days": 10, "mechanics": ["unique_items"],
		"npc_marks": [[0.35, "nebula_chef"], [0.65, "twofaced_priestess"], [0.9, "plasma_bartender"]]},
	{"xp": 26000, "mechanics": ["skill_4"], "npc_marks": []},
	{"xp": 34000, "pool_size": 4, "mechanics": [], "npc_marks": []},
]

# Индекс id -> запись + кумулятивный xp по уровням (строятся один раз).
var _by_id: Dictionary = {}
var _prog_cum: Array = []          # _prog_cum[i] = сумма xp уровней 0..i
var NPC_ACH: Dictionary = {}       # id -> [{kind, t, icon, name, hint, focus?, stat?}]

func _ready() -> void:
	for n in NPCS:
		_by_id[n["id"]] = n
	var s := 0
	for lv in PROG_LEVELS:
		s += int(lv["xp"])
		_prog_cum.append(s)
	# NPC-ачивки (извлечены из content.js в JSON)
	if FileAccess.file_exists("res://assets/data/npc_ach.json"):
		var f := FileAccess.open("res://assets/data/npc_ach.json", FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				NPC_ACH = parsed

func npc_achievements(id: String) -> Array:
	return NPC_ACH.get(id, [])

func npc_by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})

func portrait_path(npc: Dictionary) -> String:
	return "res://assets/npc/%s.png" % npc.get("img", "")

# Досье персонажей (NPC_LORE_DESC, RU) — короткое художественное описание.
const DOSSIERS := {
	"drone": "Служебный дрон снабжения. Летает между доками дольше, чем помнит его гарантийный талон. Кажется, у него начали появляться предпочтения.",
	"tentacloid": "Эстет с планеты-океана. Считает красоту базовой потребностью, как кислород. Щупалец восемь, мнений — больше.",
	"gourmet_vega": "Легендарный дегустатор с Веги. Его отзыв может закрыть ресторан на трёх планетах. Или открыть.",
	"logic9": "Судовой вычислитель девятого поколения. Обслуживает реактор и не признаёт слова «примерно».",
	"last_of_ir": "Последний представитель расы Ир. Хранит память своего народа в смесях — других носителей не осталось.",
	"nebula_chef": "Шеф-повар ресторана, дрейфующего внутри туманности. Уверен, что геометрия — это специя.",
	"twofaced_priestess": "Жрица культа двойного заката. Говорит от имени двух богов и различает их по оттенку.",
	"plasma_bartender": "Держит бар, где напитки живые в буквальном смысле. Ритм для него — единица измерения всего.",
	"janitor": "Уборщик Пятого Дока. Знает станцию лучше её строителей, потому что отмывал каждый её угол.",
	"pete": "Пьяница Пит. Когда-то был кем-то важным на этой станции — теперь важен только уровень в его стакане. Уверяет, что так честнее.",
	"intern_beep": "Стажёр без имени в накладных — все зовут его Бип. Очень старается. Очень.",
	"trucker_chrome": "Дальнобойщик с тысячей парсеков за плечами. Дом для него — кабина, а вот кофе и смеси — только тут.",
	"fashionista": "Икона стиля с Кассиопеи. Меняет панцири по сезону и считает лавку своим тайным бутиком.",
	"collector_gz": "Коллекционер смесей с трёхсотлетним стажем. Никуда не торопится. Совсем.",
	"dj_pulsar": "Диджей, сводящий сеты из излучения настоящих пульсаров. Ищет вайб во всём, включая жидкости.",
	"marketer": "Маркетолог рекламного спутника, с которого давно все улетели. Он продолжает вещать акции в пустоту — и, кажется, не заметил, что аудитории нет.",
	"perfumer": "Парфюмер Тысячи Лун. Утверждает, что запах — это память, разлитая по флаконам.",
	"guild_inspector": "Инспектор Гильдии зельеваров. Живёт по регламенту и носит его с собой. Весь.",
	"apothecary_mo": "Аптекарь с окраины сектора. За каждым его заказом — чей-то пациент.",
	"engineer": "Инженер-юстировщик при флотском навигаторе. Живёт по приборам: если стрелка в зелёном — мир в порядке. Ни секунды лишней.",
	"swarm_navigator": "Голос Роя — коллективного разума из миллионов особей. Говорит «МЫ» и не преувеличивает.",
	"vex": "Хирург-механик. Оперирует корабли, как живых существ — потому что для него они живые.",
	"racer_kai": "Пилот плазменных гонок. Всё в её жизни делится на «до финиша» и «после».",
	"catlady": "Бабушка Мурра, хозяйка девяти (а может, и девяноста) космических котов. Куда идёт она — туда и лапы. Спорить бесполезно.",
	"archivist": "Хранитель Архива на краю вселенной. Записывает всё. Вообще всё.",
	"supernova_child": "Существо, родившееся из вспышки сверхновой. Вчера. Учится всему сразу.",
	"the_waiter": "Никто не знает, чего он ждёт. Известно только, что уже очень давно.",
}

func dossier(id: String) -> String:
	return DOSSIERS.get(id, "")

# xp, нужный чтобы ДОСТИЧЬ уровня (1-based). Сверх последнего — линейный рост.
func prog_level_increment(level: int) -> int:
	var pm: int = PROG_LEVELS.size()
	if level <= pm:
		return int(PROG_LEVELS[level - 1]["xp"])
	return int(PROG_LEVELS[pm - 1]["xp"]) + (level - pm) * PROG_BEYOND_STEP

# Число завершённых шкал прогрессии (0..9 и выше — бесконечно).
func prog_level(xp: int) -> int:
	var lvl := 0
	var s := 0
	var l := 1
	while l < 10000:
		s += prog_level_increment(l)
		if xp >= s:
			lvl = l
		else:
			break
		l += 1
	return lvl

func prog_cycle_days(xp: int) -> int:
	var d := PROG_START_CYCLE_DAYS
	var lvl: int = mini(prog_level(xp), PROG_LEVELS.size())
	for i in lvl:
		if PROG_LEVELS[i].has("cycle_days"):
			d = int(PROG_LEVELS[i]["cycle_days"])
	return d

func prog_pool_size(xp: int) -> int:
	var p := PROG_START_POOL
	var lvl: int = mini(prog_level(xp), PROG_LEVELS.size())
	for i in lvl:
		if PROG_LEVELS[i].has("pool_size"):
			p = int(PROG_LEVELS[i]["pool_size"])
	return p

func prog_mech_unlocked(name: String, xp: int) -> bool:
	if name in PROG_START_MECHS:
		return true
	var lvl: int = mini(prog_level(xp), PROG_LEVELS.size())
	for i in lvl:
		if name in (PROG_LEVELS[i]["mechanics"] as Array):
			return true
	return false

# На каком уровне (1-based) открывается механика; 0 — если нигде.
func mech_unlock_level(name: String) -> int:
	for i in PROG_LEVELS.size():
		if name in (PROG_LEVELS[i]["mechanics"] as Array):
			return i + 1
	return 0

# Множество открытых NPC id (стартовые + отпертые xp-марками внутри шкал).
func prog_unlocked_npcs(xp: int) -> Dictionary:
	var set: Dictionary = {}
	for id in PROG_START_NPCS:
		set[id] = true
	for i in PROG_LEVELS.size():
		var lv: Dictionary = PROG_LEVELS[i]
		var bar_start: int = _prog_cum[i - 1] if i > 0 else 0
		for m in (lv["npc_marks"] as Array):
			if float(xp) >= float(bar_start) + float(m[0]) * float(lv["xp"]):
				set[m[1]] = true
	return set

func is_npc_unlocked(id: String, xp: int) -> bool:
	return prog_unlocked_npcs(xp).has(id)

# Прогресс до следующего уровня: {level, into, needed} для полоски «Лавка ур.N».
func prog_bar(xp: int) -> Dictionary:
	var lvl: int = prog_level(xp)
	var cum_prev := 0
	for l in range(1, lvl + 1):
		cum_prev += prog_level_increment(l)
	var needed: int = prog_level_increment(lvl + 1)
	return {"level": lvl, "into": xp - cum_prev, "needed": needed}

# ---------- Связи NPC (Фаза: relations, откр. с xp 14000) ----------
# kind: friend | enemy | buddy | dislike. Обе стороны читают связь одинаково.
const NPC_RELATIONS := [
	{"a": "drone", "b": "janitor", "kind": "friend"},
	{"a": "pete", "b": "trucker_chrome", "kind": "buddy"},
	{"a": "pete", "b": "janitor", "kind": "dislike"},
	{"a": "last_of_ir", "b": "archivist", "kind": "friend"},
	{"a": "engineer", "b": "swarm_navigator", "kind": "friend"},
	{"a": "engineer", "b": "racer_kai", "kind": "dislike"},
	{"a": "tentacloid", "b": "fashionista", "kind": "enemy"},
	{"a": "racer_kai", "b": "guild_inspector", "kind": "enemy"},
	{"a": "plasma_bartender", "b": "racer_kai", "kind": "buddy"},
	{"a": "plasma_bartender", "b": "swarm_navigator", "kind": "buddy"},
	{"a": "plasma_bartender", "b": "nebula_chef", "kind": "buddy"},
	{"a": "plasma_bartender", "b": "twofaced_priestess", "kind": "buddy"},
	{"a": "plasma_bartender", "b": "the_waiter", "kind": "buddy"},
	{"a": "gourmet_vega", "b": "perfumer", "kind": "buddy"},
	{"a": "apothecary_mo", "b": "vex", "kind": "buddy"},
	{"a": "catlady", "b": "apothecary_mo", "kind": "buddy"},
	{"a": "catlady", "b": "guild_inspector", "kind": "dislike"},
	{"a": "intern_beep", "b": "trucker_chrome", "kind": "buddy"},
	{"a": "marketer", "b": "dj_pulsar", "kind": "buddy"},
	{"a": "marketer", "b": "fashionista", "kind": "dislike"},
	{"a": "twofaced_priestess", "b": "supernova_child", "kind": "buddy"},
	{"a": "guild_inspector", "b": "dj_pulsar", "kind": "dislike"},
	{"a": "guild_inspector", "b": "vex", "kind": "dislike"},
	{"a": "guild_inspector", "b": "collector_gz", "kind": "dislike"},
	{"a": "tentacloid", "b": "dj_pulsar", "kind": "dislike"},
	{"a": "tentacloid", "b": "perfumer", "kind": "dislike"},
	{"a": "nebula_chef", "b": "swarm_navigator", "kind": "dislike"},
	{"a": "fashionista", "b": "collector_gz", "kind": "dislike"},
	{"a": "vex", "b": "racer_kai", "kind": "dislike"},
	{"a": "archivist", "b": "supernova_child", "kind": "dislike"},
	{"a": "plasma_bartender", "b": "intern_beep", "kind": "buddy"},
	{"a": "plasma_bartender", "b": "trucker_chrome", "kind": "buddy"},
	{"a": "plasma_bartender", "b": "dj_pulsar", "kind": "buddy"},
	{"a": "the_waiter", "b": "collector_gz", "kind": "buddy"},
	{"a": "guild_inspector", "b": "nebula_chef", "kind": "dislike"},
	{"a": "tentacloid", "b": "janitor", "kind": "dislike"},
	{"a": "tentacloid", "b": "intern_beep", "kind": "dislike"},
	{"a": "nebula_chef", "b": "gourmet_vega", "kind": "dislike"},
]
const REL_KIND_LABEL := {"friend": "Друг", "enemy": "Враг", "buddy": "Собутыльник", "dislike": "Неприязнь"}

func relation_rep_need(tier: int) -> int:
	if tier <= 1: return 1
	if tier <= 3: return 2
	return 3

func find_relation(a: String, b: String) -> Dictionary:
	for r in NPC_RELATIONS:
		if (r["a"] == a and r["b"] == b) or (r["a"] == b and r["b"] == a):
			return r
	return {}

func relation_key(a: String, b: String) -> String:
	var arr := [a, b]
	arr.sort()
	return "%s|%s" % [arr[0], arr[1]]

# ---------- Пассивки персонажей (Фаза J + реворк Фазы 11) ----------
# По 5 пассивок на NPC; пассивка с индексом i открывается уровнем репутации i+1
# (пороги — REP_LEVELS). Игрок держит активными до PASSIVE_SLOTS штук; состав
# фиксируется после первого выполненного заказа цикла.
#   scope "npc"    — работает ТОЛЬКО в заказах этого NPC (эффект сильнее);
#   scope "global" — работает во ВСЕХ заказах (слабее).
#   fx (числовые ключи складываются между активными пассивками):
#     score     — множитель к награде за очки (+0.15 = +15%)
#     craftTime — множитель к таймеру «воссоздай» (может быть < 0 — риск)
#     memTime   — множитель к таймеру запоминания
#     speedCap  — прибавка к потолку бонуса за скорость (абсолютная)
#     rep       — множитель к ПРИРОСТУ репутации
#     progress  — множитель к весу «коллекционного» прогресса (лента/ачивки)
#     tips      — множитель к чаевым за заказ
#   Уникалки (не складываются, читаются флагом/суммой):
#     chargeAt2 — бонусный заряд умения за 2 идеала вместо 3
#     tipsFlat  — плоская прибавка чаевых в конце цикла
const PASSIVE_SLOTS := 3
const PASSIVE_SCOPE_LABEL := {"npc": "только этот гость", "global": "все заказы"}

const NPC_PASSIVES := {
	"drone": [
		{"id": "p1", "scope": "npc", "icon": "📦", "fx": {"progress": 0.12},
			"name": "Оптовый контракт", "desc": "+12% прогресса в заданиях дрона"},
		{"id": "p2", "scope": "global", "icon": "🗺", "fx": {"memTime": 0.06},
			"name": "Свежие карты доков", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "⏱", "fx": {"craftTime": 0.15},
			"name": "Стыковка без очереди", "desc": "+15% времени на воссоздание в заданиях дрона"},
		{"id": "p4", "scope": "global", "icon": "📡", "fx": {"rep": 0.08},
			"name": "Рассылка по дронам", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🧨", "fx": {"score": 0.2, "progress": 0.2},
			"name": "Сверхнормативная смена", "desc": "+20% очков и +20% прогресса в заданиях дрона"},
	],
	"tentacloid": [
		{"id": "p1", "scope": "npc", "icon": "💝", "fx": {"score": 0.15},
			"name": "Щедрые чаевые", "desc": "+15% очков за задания тентаклоида"},
		{"id": "p2", "scope": "global", "icon": "🌊", "fx": {"craftTime": 0.05},
			"name": "Спокойствие прилива", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "👁", "fx": {"memTime": 0.2},
			"name": "Показ без спешки", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "✨", "fx": {"progress": 0.06},
			"name": "Чувство прекрасного", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🐙", "fx": {"score": 0.25, "craftTime": -0.12},
			"name": "Восемь рук помощи", "desc": "−12% времени, но +25% очков в его заданиях"},
	],
	"gourmet_vega": [
		{"id": "p1", "scope": "global", "icon": "⭐", "fx": {"tips": 0.08},
			"name": "Рекомендация гида", "desc": "+8% чаевых в конце цикла"},
		{"id": "p2", "scope": "global", "icon": "👅", "fx": {"memTime": 0.06},
			"name": "Тренированный вкус", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🍷", "fx": {"craftTime": 0.15},
			"name": "Дегустация не спешит", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "📖", "fx": {"rep": 0.08},
			"name": "Сарафанное радио", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🎩", "fx": {"score": 0.2, "speedCap": 0.15},
			"name": "Ужин от шефа", "desc": "+20% очков и +15 п.п. к бонусу скорости в его заданиях"},
	],
	"logic9": [
		{"id": "p1", "scope": "global", "icon": "🧮", "fx": {"speedCap": 0.05},
			"name": "ПРЕМИЯ ЗА ТОЧНОСТЬ", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p2", "scope": "global", "icon": "⏲", "fx": {"craftTime": 0.05},
			"name": "ОПТИМИЗАЦИЯ ТАКТА", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "📊", "fx": {"memTime": 0.2},
			"name": "РАСШИРЕННЫЙ БУФЕР", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "⚡", "fx": {"speedCap": 0.05},
			"name": "ПАРАЛЛЕЛЬНЫЙ ПОТОК", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p5", "scope": "global", "icon": "🔋", "fx": {"chargeAt2": true},
			"name": "СЧЁТЧИК ИДЕАЛОВ: −1", "desc": "УНИКАЛЬНО: доп. заряд умения за 2 идеала вместо 3 (во всех заданиях)"},
	],
	"last_of_ir": [
		{"id": "p1", "scope": "global", "icon": "🌅", "fx": {"rep": 0.08},
			"name": "Дар угасающих", "desc": "+8% к приросту репутации у всех"},
		{"id": "p2", "scope": "global", "icon": "🕯", "fx": {"progress": 0.06},
			"name": "Память поколений", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🌌", "fx": {"memTime": 0.2},
			"name": "Небо, которого нет", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "💠", "fx": {"rep": 0.08},
			"name": "Слово последнего", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🏺", "fx": {"score": 0.2, "progress": 0.25},
			"name": "Наследие Ир", "desc": "+20% очков и +25% прогресса в его заданиях"},
	],
	"nebula_chef": [
		{"id": "p1", "scope": "npc", "icon": "💰", "fx": {"craftTime": 0.12},
			"name": "Процент с банкета", "desc": "+12% времени на воссоздание в заданиях шефа"},
		{"id": "p2", "scope": "global", "icon": "📐", "fx": {"memTime": 0.06},
			"name": "Глазомер кухни", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🍳", "fx": {"craftTime": 0.15},
			"name": "Медленный огонь", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🍽", "fx": {"progress": 0.06},
			"name": "Мишленовская выучка", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🔥", "fx": {"score": 0.25, "craftTime": -0.12},
			"name": "Час пик на кухне", "desc": "−12% времени, но +25% очков в его заданиях"},
	],
	"twofaced_priestess": [
		{"id": "p1", "scope": "npc", "icon": "🙏", "fx": {"memTime": 0.15},
			"name": "Подношение храма", "desc": "+15% времени на запоминание в заданиях жрицы"},
		{"id": "p2", "scope": "global", "icon": "🌗", "fx": {"memTime": 0.06},
			"name": "Взгляд двух богов", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🕊", "fx": {"craftTime": 0.15},
			"name": "Благословение заката", "desc": "+15% времени на воссоздание в её заданиях"},
		{"id": "p4", "scope": "global", "icon": "💠", "fx": {"rep": 0.08},
			"name": "Молва прихода", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🧿", "fx": {"score": 0.2, "rep": 0.3},
			"name": "Милость близнецов", "desc": "+20% очков и +30% репутации в её заданиях"},
	],
	"plasma_bartender": [
		{"id": "p1", "scope": "global", "icon": "🍹", "fx": {"tips": 0.08},
			"name": "За счёт заведения", "desc": "+8% чаевых в конце цикла"},
		{"id": "p2", "scope": "global", "icon": "🎵", "fx": {"speedCap": 0.05},
			"name": "Чувство ритма", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🕺", "fx": {"memTime": 0.2},
			"name": "Замедленный бит", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🎧", "fx": {"craftTime": 0.05},
			"name": "Фоновый грув", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "⚡", "fx": {"score": 0.2, "speedCap": 0.15},
			"name": "Хэдлайнер вечера", "desc": "+20% очков и +15 п.п. к бонусу скорости в его заданиях"},
	],
	"pete": [
		{"id": "p1", "scope": "npc", "icon": "🍺", "fx": {"craftTime": 0.12},
			"name": "Постоянный клиент", "desc": "+12% времени на воссоздание в заданиях Пита"},
		{"id": "p2", "scope": "global", "icon": "🍶", "fx": {"craftTime": 0.05},
			"name": "Твёрдая рука наливалы", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "👁", "fx": {"memTime": 0.2},
			"name": "На глаз до капли", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🍻", "fx": {"rep": 0.08},
			"name": "Душа компании", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🥃", "fx": {"score": 0.2, "speedCap": 0.15},
			"name": "На посошок", "desc": "+20% очков и +15 п.п. к бонусу скорости в его заданиях"},
	],
	"janitor": [
		{"id": "p1", "scope": "npc", "icon": "🪙", "fx": {"craftTime": 0.12},
			"name": "Премия из тумбочки", "desc": "+12% времени на воссоздание в заданиях уборщика"},
		{"id": "p2", "scope": "global", "icon": "🧽", "fx": {"craftTime": 0.05},
			"name": "Прибранное рабочее место", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🗝", "fx": {"memTime": 0.2},
			"name": "Знает все углы", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🤝", "fx": {"rep": 0.08},
			"name": "Свой человек на станции", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🪣", "fx": {"score": 0.2, "progress": 0.2},
			"name": "Генеральная уборка", "desc": "+20% очков и +20% прогресса в его заданиях"},
	],
	"intern_beep": [
		{"id": "p1", "scope": "npc", "icon": "🍬", "fx": {"memTime": 0.15},
			"name": "Сэкономил на обеде", "desc": "+15% времени на запоминание в заданиях стажёра"},
		{"id": "p2", "scope": "global", "icon": "📝", "fx": {"memTime": 0.06},
			"name": "Конспект под рукой", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "⏰", "fx": {"craftTime": 0.15},
			"name": "Шеф ушёл на совещание", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🌱", "fx": {"progress": 0.06},
			"name": "Учимся вместе", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🎓", "fx": {"score": 0.2, "rep": 0.3},
			"name": "Первая похвала шефа", "desc": "+20% очков и +30% репутации в его заданиях"},
	],
	"trucker_chrome": [
		{"id": "p1", "scope": "global", "icon": "💵", "fx": {"speedCap": 0.05},
			"name": "Оплата наличными", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p2", "scope": "global", "icon": "🛣", "fx": {"craftTime": 0.05},
			"name": "Дорожная выдержка", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "📻", "fx": {"memTime": 0.2},
			"name": "Разговор под рацию", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🤝", "fx": {"rep": 0.08},
			"name": "Слухи с трассы", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🚛", "fx": {"score": 0.25, "craftTime": -0.12},
			"name": "Срочный груз", "desc": "−12% времени, но +25% очков в его заданиях"},
	],
	"fashionista": [
		{"id": "p1", "scope": "global", "icon": "💳", "fx": {"rep": 0.08},
			"name": "Платит не глядя", "desc": "+8% к приросту репутации у всех"},
		{"id": "p2", "scope": "global", "icon": "👁", "fx": {"memTime": 0.06},
			"name": "Намётанный глаз", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "💅", "fx": {"craftTime": 0.15},
			"name": "Примерка не к спеху", "desc": "+15% времени на воссоздание в её заданиях"},
		{"id": "p4", "scope": "global", "icon": "📸", "fx": {"rep": 0.08},
			"name": "Упоминание в ленте", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "👑", "fx": {"score": 0.2, "rep": 0.3},
			"name": "Икона сезона", "desc": "+20% очков и +30% репутации в её заданиях"},
	],
	"collector_gz": [
		{"id": "p1", "scope": "npc", "icon": "💰", "fx": {"progress": 0.12},
			"name": "Цена коллекционера", "desc": "+12% прогресса в заданиях коллекционера"},
		{"id": "p2", "scope": "global", "icon": "🐌", "fx": {"craftTime": 0.05},
			"name": "Никакой спешки", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🔍", "fx": {"memTime": 0.2},
			"name": "Осмотр с лупой", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🏺", "fx": {"progress": 0.06},
			"name": "Коллекционная ценность", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "📚", "fx": {"score": 0.2, "progress": 0.25},
			"name": "Место на полке 44", "desc": "+20% очков и +25% прогресса в его заданиях"},
	],
	"dj_pulsar": [
		{"id": "p1", "scope": "global", "icon": "🎟", "fx": {"speedCap": 0.05},
			"name": "Гонорар за сет", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p2", "scope": "global", "icon": "🎚", "fx": {"speedCap": 0.05},
			"name": "Держать темп", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🎛", "fx": {"craftTime": 0.15},
			"name": "Затянутый переход", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "📢", "fx": {"rep": 0.08},
			"name": "Шаутаут со сцены", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "💿", "fx": {"score": 0.2, "speedCap": 0.15},
			"name": "Пиковый час", "desc": "+20% очков и +15 п.п. к бонусу скорости в его заданиях"},
	],
	"marketer": [
		{"id": "p1", "scope": "global", "icon": "📺", "fx": {"tips": 0.08},
			"name": "Рекламный бюджет", "desc": "+8% чаевых в конце цикла"},
		{"id": "p2", "scope": "global", "icon": "🔎", "fx": {"craftTime": 0.06},
			"name": "Глаз на рабочие ручки", "desc": "+6% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🕰", "fx": {"craftTime": 0.2},
			"name": "Продлённый эфир", "desc": "+20% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "📢", "fx": {"rep": 0.08},
			"name": "Вирусный охват", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "global", "icon": "💵", "fx": {"tipsFlat": 150},
			"name": "Прямая рекламная выручка", "desc": "УНИКАЛЬНО: +150 чаевых в конце каждого цикла (сверх процента)"},
	],
	"perfumer": [
		{"id": "p1", "scope": "npc", "icon": "💎", "fx": {"memTime": 0.15},
			"name": "Плата за нюанс", "desc": "+15% времени на запоминание в заданиях парфюмера"},
		{"id": "p2", "scope": "global", "icon": "👃", "fx": {"memTime": 0.06},
			"name": "Память обоняния", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🫗", "fx": {"craftTime": 0.15},
			"name": "Выдержка аромата", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "🌙", "fx": {"progress": 0.06},
			"name": "Школа Тысячи Лун", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🌸", "fx": {"score": 0.2, "progress": 0.25},
			"name": "Формула века", "desc": "+20% очков и +25% прогресса в его заданиях"},
	],
	"guild_inspector": [
		{"id": "p1", "scope": "global", "icon": "🏛", "fx": {"rep": 0.08},
			"name": "Гильдейская ставка", "desc": "+8% к приросту репутации у всех"},
		{"id": "p2", "scope": "global", "icon": "📋", "fx": {"memTime": 0.06},
			"name": "Работа по чек-листу", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🖋", "fx": {"craftTime": 0.15},
			"name": "Продлённая приёмка", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "📜", "fx": {"rep": 0.08},
			"name": "Гильдейская рекомендация", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🎖", "fx": {"score": 0.2, "rep": 0.3},
			"name": "Знак качества", "desc": "+20% очков и +30% репутации в его заданиях"},
	],
	"apothecary_mo": [
		{"id": "p1", "scope": "npc", "icon": "💊", "fx": {"craftTime": 0.12},
			"name": "Аптечная наценка", "desc": "+12% времени на воссоздание в заданиях аптекаря"},
		{"id": "p2", "scope": "global", "icon": "🧘", "fx": {"craftTime": 0.05},
			"name": "Твёрдая рука", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "📖", "fx": {"memTime": 0.2},
			"name": "Рецепт наизусть", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "❤️", "fx": {"rep": 0.08},
			"name": "Благодарные пациенты", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "⚗️", "fx": {"score": 0.2, "progress": 0.2},
			"name": "Горькое чудо", "desc": "+20% очков и +20% прогресса в его заданиях"},
	],
	"engineer": [
		{"id": "p1", "scope": "global", "icon": "🛰️", "fx": {"speedCap": 0.05},
			"name": "Флотский подряд", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p2", "scope": "global", "icon": "🎯", "fx": {"speedCap": 0.06},
			"name": "Намётанный глаз", "desc": "+6 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🕹", "fx": {"craftTime": 0.18},
			"name": "Медленный ход стрелки", "desc": "+18% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "📡", "fx": {"rep": 0.08},
			"name": "Слово навигатора", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🟢", "fx": {"score": 0.25, "craftTime": 0.1},
			"name": "Стрелка сама в зелёном", "desc": "+10% времени и +25% очков в его заданиях"},
	],
	"swarm_navigator": [
		{"id": "p1", "scope": "npc", "icon": "🍯", "fx": {"progress": 0.12},
			"name": "Доля улья", "desc": "+12% прогресса в заданиях Роя"},
		{"id": "p2", "scope": "global", "icon": "👀", "fx": {"memTime": 0.06},
			"name": "Тысяча глаз", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🕸", "fx": {"craftTime": 0.15},
			"name": "Рой не торопит", "desc": "+15% времени на воссоздание в заданиях Роя"},
		{"id": "p4", "scope": "global", "icon": "📡", "fx": {"rep": 0.08},
			"name": "Сигнал по всей сети", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🐝", "fx": {"score": 0.2, "progress": 0.2},
			"name": "Признание Роя", "desc": "+20% очков и +20% прогресса в заданиях Роя"},
	],
	"vex": [
		{"id": "p1", "scope": "npc", "icon": "🩺", "fx": {"craftTime": 0.12},
			"name": "Хирургический тариф", "desc": "+12% времени на воссоздание в заданиях Векса"},
		{"id": "p2", "scope": "global", "icon": "🔩", "fx": {"craftTime": 0.05},
			"name": "Без люфтов", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "💡", "fx": {"memTime": 0.2},
			"name": "Свет операционной", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "⚡", "fx": {"speedCap": 0.05},
			"name": "Отточенные движения", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🫀", "fx": {"score": 0.25, "craftTime": -0.12},
			"name": "Экстренная операция", "desc": "−12% времени, но +25% очков в его заданиях"},
	],
	"racer_kai": [
		{"id": "p1", "scope": "global", "icon": "🏆", "fx": {"speedCap": 0.05},
			"name": "Призовые за этап", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p2", "scope": "global", "icon": "⚡", "fx": {"speedCap": 0.05},
			"name": "Рефлексы пилота", "desc": "+5 п.п. к потолку бонуса скорости во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🔧", "fx": {"craftTime": 0.15},
			"name": "Техпауза в боксах", "desc": "+15% времени на воссоздание в её заданиях"},
		{"id": "p4", "scope": "global", "icon": "📣", "fx": {"rep": 0.08},
			"name": "Интервью после финиша", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "🏁", "fx": {"score": 0.25, "craftTime": -0.12},
			"name": "Финальный круг", "desc": "−12% времени, но +25% очков в её заданиях"},
	],
	"catlady": [
		{"id": "p1", "scope": "npc", "icon": "🐈", "fx": {"score": 0.15},
			"name": "Гостинец от бабушки", "desc": "+15% очков за задания Бабушки Мурры"},
		{"id": "p2", "scope": "global", "icon": "🧶", "fx": {"craftTime": 0.05},
			"name": "Тёплые варежки", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🐾", "fx": {"craftTime": 0.18},
			"name": "Коты не торопятся", "desc": "+18% времени на воссоздание в её заданиях"},
		{"id": "p4", "scope": "global", "icon": "😽", "fx": {"rep": 0.08},
			"name": "Знакома со всеми", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "😻", "fx": {"score": 0.25, "memTime": 0.15},
			"name": "Мурлыканье под руку", "desc": "+15% времени на запоминание и +25% очков в её заданиях"},
	],
	"archivist": [
		{"id": "p1", "scope": "npc", "icon": "🖋", "fx": {"memTime": 0.15},
			"name": "Гонорар летописца", "desc": "+15% времени на запоминание в заданиях Хранителя"},
		{"id": "p2", "scope": "global", "icon": "📖", "fx": {"memTime": 0.06},
			"name": "Архивная выучка", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🕰", "fx": {"craftTime": 0.15},
			"name": "История подождёт", "desc": "+15% времени на воссоздание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "📜", "fx": {"progress": 0.06},
			"name": "Вписано в летопись", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🏛", "fx": {"score": 0.2, "progress": 0.25},
			"name": "Глава о лавке", "desc": "+20% очков и +25% прогресса в его заданиях"},
	],
	"supernova_child": [
		{"id": "p1", "scope": "npc", "icon": "🌟", "fx": {"score": 0.15},
			"name": "звёздная. пыль. в подарок", "desc": "+15% очков за задания Дитя"},
		{"id": "p2", "scope": "global", "icon": "💫", "fx": {"memTime": 0.06},
			"name": "память. света", "desc": "+6% времени на запоминание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🌠", "fx": {"memTime": 0.2},
			"name": "смотрит. не. моргая", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "✨", "fx": {"rep": 0.08},
			"name": "все. любят. дитя", "desc": "+8% к приросту репутации у всех"},
		{"id": "p5", "scope": "npc", "icon": "💥", "fx": {"score": 0.2, "rep": 0.3},
			"name": "как. мама", "desc": "+20% очков и +30% репутации в его заданиях"},
	],
	"the_waiter": [
		{"id": "p1", "scope": "global", "icon": "🪙", "fx": {"rep": 0.08},
			"name": "Монеты из ниоткуда", "desc": "+8% к приросту репутации у всех"},
		{"id": "p2", "scope": "global", "icon": "⏳", "fx": {"craftTime": 0.05},
			"name": "Одолженное время", "desc": "+5% времени на воссоздание во всех заданиях"},
		{"id": "p3", "scope": "npc", "icon": "🌒", "fx": {"memTime": 0.2},
			"name": "Пауза между мгновениями", "desc": "+20% времени на запоминание в его заданиях"},
		{"id": "p4", "scope": "global", "icon": "♾", "fx": {"progress": 0.06},
			"name": "Терпение как ландшафт", "desc": "+6% к весу прогресса во всех заданиях"},
		{"id": "p5", "scope": "npc", "icon": "🔮", "fx": {"score": 0.2, "progress": 0.25},
			"name": "Один из хороших вариантов", "desc": "+20% очков и +25% прогресса в его заданиях"},
	],
}

func passive_defs(npc_id: String) -> Array:
	return NPC_PASSIVES.get(npc_id, [])

# Определение пассивки по паре id-ов (пусто, если такой нет).
func passive_def(npc_id: String, pid: String) -> Dictionary:
	for pv in passive_defs(npc_id):
		if String(pv["id"]) == pid:
			return pv
	return {}

# Индекс пассивки в списке NPC (−1, если нет). Нужен для «нужен реп. ур. N».
func passive_index(npc_id: String, pid: String) -> int:
	var arr: Array = passive_defs(npc_id)
	for i in arr.size():
		if String(arr[i]["id"]) == pid:
			return i
	return -1
