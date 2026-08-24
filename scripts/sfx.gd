extends Node
## Аудио порта: звуковые эффекты (assets/sound/<key>.mp3) + фоновая музыка
## (меню + игровой плейлист с кросс-фейдом). Всё нативно в Godot, без сторонних
## библиотек. Порт браузерного SFX/Music (game.js). Autoload «Sfx».
##
## API: Sfx.play("tick"), Sfx.enter_menu(), Sfx.enter_game(), Sfx.duck(true/false),
## Sfx.set_sfx_volume(0..1), Sfx.set_music_volume(0..1).

const SFX_DIR := "res://assets/sound/"
# у ключа может быть несколько вариантов (<key>.mp3, <key>2.mp3, …) — рандом при игре
const SFX_VARIANTS := {"blobSnap": 3}
# все эффекты (имена = имена файлов). Ключей без файла (good/badClear в оригинале
# были на ZzFX) здесь нет — для них см. _FALLBACK.
const SFX_KEYS := [
	"achieve", "bad", "badPop", "blobDrag", "blobGrab", "blobSnap", "brew",
	"bubble", "cardPick", "colorShift", "countdown", "dock", "liquidDown",
	"liquidUp", "meow", "orderShow", "pawClick", "perfect", "stir", "tick",
	"uiClick", "weekEnd",
	# полоса поощрений цикла: установка отметки за результат дня
	"trackGood", "trackPerfect", "trackHundred", "trackSwill", "trackBad",
	"trackGrade", "trackSecret",
]
# события без своего файла → ближайший по смыслу существующий
const _FALLBACK := {"good": "perfect", "badClear": "badPop"}

const MENU_TRACK := "res://assets/track_6.mp3"
const GAME_TRACKS := [
	"res://assets/track_1.mp3", "res://assets/track_2.mp3", "res://assets/track_3.mp3",
	"res://assets/track_4.mp3", "res://assets/track_5.mp3", "res://assets/track_7.mp3",
]
const FADE := 2.5      # кросс-фейд меню↔игра / старт трека, с
const TAIL := 3.0      # за сколько секунд до конца заводить следующий трек

var sfx_volume: float = 0.9
var music_volume: float = 0.6

var _streams: Dictionary = {}      # key -> Array[AudioStream]
var _pool: Array = []              # пул плееров для полифонии
var _pool_i: int = 0

var _mus_a: AudioStreamPlayer
var _mus_b: AudioStreamPlayer
var _mus_cur: AudioStreamPlayer    # активный музыкальный плеер
var _mode: String = ""             # "menu" | "game"
var _queue: Array = []
var _ducked: bool = false
var _crossed: bool = false         # игровой трек уже начал кросс-фейд к следующему

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_sfx()
	# пул из 10 плееров эффектов
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_mus_a = _make_music_player()
	_mus_b = _make_music_player()
	# начальная громкость — из профиля
	var s: Dictionary = PotionProfile.data.get("settings", {})
	sfx_volume = float(s.get("sfx_vol", sfx_volume))
	music_volume = float(s.get("music_vol", music_volume))
	set_sfx_volume(sfx_volume)
	set_music_volume(music_volume)

# записать громкость в профиль (в память; PotionProfile.save() зовёт вызывающий)
func _store(key: String, val: float) -> void:
	if PotionProfile.data.has("settings"):
		PotionProfile.data["settings"][key] = val

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	return p

func _load_sfx() -> void:
	for k: String in SFX_KEYS:
		var arr: Array = []
		var main_path := SFX_DIR + k + ".mp3"
		if ResourceLoader.exists(main_path):
			arr.append(load(main_path))
		var n: int = int(SFX_VARIANTS.get(k, 0))
		for i in range(2, n + 1):
			var vp := SFX_DIR + k + str(i) + ".mp3"
			if ResourceLoader.exists(vp):
				arr.append(load(vp))
		if not arr.is_empty():
			_streams[k] = arr

# ---------- эффекты ----------
func play(key: String) -> void:
	var k := key
	if not _streams.has(k):
		k = String(_FALLBACK.get(key, key))     # подмена для good/badClear
	var arr: Array = _streams.get(k, [])
	if arr.is_empty():
		return                                   # нет файла — тишина (без ZzFX)
	var stream: AudioStream = arr[randi() % arr.size()]
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = stream
	p.play()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index("SFX")
	if idx != -1:
		AudioServer.set_bus_mute(idx, sfx_volume <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(sfx_volume, 0.0001)))
	_store("sfx_vol", sfx_volume)

# ---------- музыка ----------
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index("Music")
	if idx != -1:
		AudioServer.set_bus_mute(idx, music_volume <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(music_volume, 0.0001)))
	_store("music_vol", music_volume)

func enter_menu() -> void:
	if _mode == "menu":
		return
	_mode = "menu"
	_play_on(_free_player(), MENU_TRACK, true)

func enter_game() -> void:
	if _mode == "game":
		return
	_mode = "game"
	_shuffle_queue()
	_play_next_game()

func duck(on: bool) -> void:
	# Диджей Пульсар глушит музыку (target 0), иначе возврат к громкости шины
	_ducked = on
	if _mus_cur:
		_fade(_mus_cur, 0.0 if on else 1.0, 0.4)

func _shuffle_queue() -> void:
	_queue = GAME_TRACKS.duplicate()
	_queue.shuffle()

func _play_next_game() -> void:
	if _queue.is_empty():
		_shuffle_queue()
	_crossed = false
	_play_on(_free_player(), _queue.pop_front(), false)

func _free_player() -> AudioStreamPlayer:
	return _mus_b if _mus_cur == _mus_a else _mus_a

# запустить трек на плеере с фейдом-ин, старый — фейд-аут
func _play_on(p: AudioStreamPlayer, path: String, loop: bool) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		stream.loop = loop
	var prev := _mus_cur
	p.stream = stream
	p.volume_db = -40.0
	p.play()
	_mus_cur = p
	_fade(p, 0.0 if _ducked else 1.0, FADE)
	if prev and prev.playing:
		_fade(prev, 0.0, FADE, true)

# фейд плеера к доле (0..1) от полной громкости шины за t секунд
func _fade(p: AudioStreamPlayer, to_frac: float, t: float, stop_after: bool = false) -> void:
	var to_db: float = -40.0 if to_frac <= 0.001 else linear_to_db(to_frac)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, t)
	if stop_after:
		tw.tween_callback(p.stop)

func _process(_delta: float) -> void:
	# кросс-фейд игрового трека к следующему за TAIL секунд до конца
	if _mode != "game" or _mus_cur == null or not _mus_cur.playing or _crossed:
		return
	var stream := _mus_cur.stream
	if stream == null:
		return
	var length := stream.get_length()
	if length > 0.0 and (length - _mus_cur.get_playback_position()) <= TAIL:
		_crossed = true
		_play_next_game()
