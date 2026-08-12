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
func stop(_g) -> void: pass             # конец раунда (уборка)

# --- влияние на скоринг/результат ---
func weight_for(_key: String, base: float) -> float: return base   # вес параметра в оценке
func result_note(_g) -> String: return ""                          # строка-пояснение на результате

# ---------- реестр реализованных механик ----------
static func make(id: String) -> NpcMech:
	match id:
		"tentacloid": return TentacloidMech.new()
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
