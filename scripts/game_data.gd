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

# ---------- Цвета тиров (как в веб: t1..t5) ----------
const TIER_COLORS := {
	1: Color("5dff8f"), 2: Color("ffe14d"), 3: Color("ff9e3d"),
	4: Color("ff5d6a"), 5: Color("c07bff"),
}

# ---------- Прогрессия/репутация (content.js) ----------
const STAGE_TABLE := [[1, 1, 1], [2, 2, 3], [3, 4, 4], [4, 4, 4]]
const REP_LEVELS := [27, 67, 120, 185, 265]      # уровень N достигнут при value >= REP_LEVELS[N-1]
const REP_L4_UNLOCK_LEVEL := 1                    # с какого ур. репутации открыт УР.4 персонажа
const LORE_PHRASE_CHANCE := 0.35

# ---------- Лента идеальных (perfect ribbon) ----------
# За каждый ИДЕАЛ лента растёт на (reward / BASELINE_TIER_REWARD) * PROGRESS_DIFF_WEIGHT[УР].
# То есть вклад тем больше, чем выше тир персонажа И чем выше выбранная сложность.
# Дотянула до RIBBON_FULL → платиновая лента (+1), остаток переносится.
const BASELINE_TIER_REWARD := 130           # награда тира 3 = «вес 1.0»
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

# ---------- Числовые характеристики по тиру (DIFFICULTIES в content.js) ----------
# EXTRA_NPCS/SPECIAL_ORDERS наследуют числа по своему тиру; отдельные NPC
# переопределяют часть полей (см. overrides в самих записях).
const TIERS := {
	1: {"memorize_ms": 6900, "craft_ms": 29260, "color_steps": 6,  "size_steps": 5,  "count_max": 5,  "bsize_steps": 5,  "reward": 50},
	2: {"memorize_ms": 6325, "craft_ms": 22610, "color_steps": 9,  "size_steps": 7,  "count_max": 7,  "bsize_steps": 7,  "reward": 85},
	3: {"memorize_ms": 5750, "craft_ms": 18354, "color_steps": 14, "size_steps": 11, "count_max": 10, "bsize_steps": 11, "reward": 130},
	4: {"memorize_ms": 5175, "craft_ms": 13300, "color_steps": 24, "size_steps": 19, "count_max": 12, "bsize_steps": 19, "reward": 180},
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

# Индекс id -> запись (строится один раз).
var _by_id: Dictionary = {}

func _ready() -> void:
	for n in NPCS:
		_by_id[n["id"]] = n

func npc_by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})

func portrait_path(npc: Dictionary) -> String:
	return "res://assets/npc/%s.png" % npc.get("img", "")
