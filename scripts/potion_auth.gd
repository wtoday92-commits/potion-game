extends Node
## Аккаунты игрока (порт PotionAuth из profile.js). Автозагрузка `PotionAuth`.
## Гость по умолчанию — прогресс хранится локально ([PotionProfile]). Опционально
## Вход/Регистрация через Supabase + синк профиля между устройствами.
##
## anon-ключ ПУБЛИЧНЫЙ (безопасно во фронтенде). service_role сюда НЕЛЬЗЯ.

const SUPABASE_URL := "https://ilkimncsophobhzhqidj.supabase.co"
const SUPABASE_ANON := "sb_publishable_Rad7Vj456OlLkaxnNuIj0w_vlogSoOo"
const EMAIL_DOMAIN := "@potion.local"
const AUTH_PATH := "user://auth.json"

var data: Dictionary = {}
var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_load()
	_ensure()

func configured() -> bool:
	return SUPABASE_URL != "" and SUPABASE_ANON != ""

# ---------- локальное состояние ----------
func _load() -> void:
	data = {}
	if FileAccess.file_exists(AUTH_PATH):
		var f := FileAccess.open(AUTH_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				data = parsed

func _save() -> void:
	var f := FileAccess.open(AUTH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func _ensure() -> void:
	var changed := false
	if not data.has("mode"): data["mode"] = "guest"; changed = true
	if not data.has("guest_nick") or String(data["guest_nick"]) == "":
		data["guest_nick"] = "Гость-%d" % (randi() % 9000 + 1000); changed = true
	if not data.has("nickname") or String(data["nickname"]) == "":
		data["nickname"] = data["guest_nick"]; changed = true
	if not data.has("remember"): data["remember"] = true; changed = true
	if changed: _save()

# ---------- публичное API ----------
func get_mode() -> String: return String(data.get("mode", "guest"))
func is_logged_in() -> bool: return get_mode() == "user"
func get_nickname() -> String:
	return String(data["nickname"]) if is_logged_in() else String(data.get("guest_nick", "Гость"))

func set_nickname(name: String) -> bool:
	name = name.strip_edges().substr(0, 20)
	if name == "":
		return false
	if is_logged_in():
		data["nickname"] = name
		_save()
		push_profile()          # ник аккаунта → в облако
	else:
		data["guest_nick"] = name
		_save()
	return true

func get_remember_device() -> bool: return bool(data.get("remember", true))
func set_remember_device(on: bool) -> void:
	data["remember"] = on
	_save()

func logout() -> void:
	data["mode"] = "guest"
	data["user_id"] = null
	data["token"] = null
	data["refresh"] = null
	data["expires_at"] = 0
	_save()

# ---------- сеть (Supabase) ----------
# Возвращает {ok, code, json}. Один запрос за раз (HTTPRequest сериализует).
func _req(method: int, url: String, hdrs: PackedStringArray, body: String = "") -> Dictionary:
	var err := _http.request(url, hdrs, method, body)
	if err != OK:
		return {"ok": false, "code": 0, "json": null}
	var r: Array = await _http.request_completed   # [result, code, headers, body]
	var code: int = r[1]
	var txt: String = (r[3] as PackedByteArray).get_string_from_utf8()
	var json: Variant = JSON.parse_string(txt)
	return {"ok": code >= 200 and code < 300, "code": code, "json": json}

func _headers(token: String = "") -> PackedStringArray:
	var t: String = token if token != "" else SUPABASE_ANON
	return PackedStringArray([
		"apikey: " + SUPABASE_ANON,
		"Content-Type: application/json",
		"Authorization: Bearer " + t,
	])

# Логин → детерминированный псевдо-e-mail (Supabase Auth работает по email).
func _login_to_email(login: String) -> String:
	var s := login.strip_edges().to_lower()
	var out := ""
	const OK_CH := "abcdefghijklmnopqrstuvwxyz0123456789"
	for i in s.length():
		var ch := s[i]
		if OK_CH.contains(ch):
			out += ch
		else:
			for b in ch.to_utf8_buffer():
				out += "-" + String.num_int64(b, 16)
	if out == "":
		out = "user"
	return "u" + out.substr(0, 60) + EMAIL_DOMAIN

func _apply_session(sess: Dictionary, nickname: String = "") -> void:
	data["mode"] = "user"
	var u: Dictionary = sess.get("user", {}) if sess.get("user") is Dictionary else {}
	data["user_id"] = u.get("id", data.get("user_id"))
	data["token"] = sess.get("access_token", data.get("token", ""))
	data["refresh"] = sess.get("refresh_token", data.get("refresh", ""))
	var exp: int = int(sess.get("expires_at", 0))
	data["expires_at"] = exp * 1000 if exp > 0 else Time.get_unix_time_from_system() * 1000 + 3500000
	if nickname != "":
		data["nickname"] = nickname.substr(0, 20)
	else:
		var meta: Dictionary = u.get("user_metadata", {}) if u.get("user_metadata") is Dictionary else {}
		if meta.has("nickname"):
			data["nickname"] = String(meta["nickname"]).substr(0, 20)
	_save()

# Регистрация. Возвращает {ok, message}.
func register(login: String, password: String, nickname: String) -> Dictionary:
	if not configured():
		return {"ok": false, "message": "Онлайн-профили выключены"}
	if login == "" or password == "":
		return {"ok": false, "message": "Впиши логин и пароль"}
	var nick := (nickname if nickname != "" else login).substr(0, 20)
	var body := JSON.stringify({"email": _login_to_email(login), "password": password, "data": {"nickname": nick}})
	var res := await _req(HTTPClient.METHOD_POST, SUPABASE_URL + "/auth/v1/signup", _headers(), body)
	var j: Variant = res["json"]
	if not res["ok"] or (j is Dictionary and (j.has("error") or j.has("msg") or j.has("code"))):
		var msg := "Ошибка регистрации"
		if j is Dictionary:
			msg = str(j.get("msg", j.get("error_description", j.get("error", msg))))
		return {"ok": false, "message": msg}
	if j is Dictionary and j.has("access_token"):
		_apply_session(j, nick)
		await push_profile()
		return {"ok": true, "message": ""}
	# сессии нет (включён confirm email) — пробуем войти
	return await login_user(login, password, nick)

# Вход. Возвращает {ok, message}.
func login_user(login: String, password: String, nickname: String = "") -> Dictionary:
	if not configured():
		return {"ok": false, "message": "Онлайн-профили выключены"}
	if login == "" or password == "":
		return {"ok": false, "message": "Впиши логин и пароль"}
	var body := JSON.stringify({"email": _login_to_email(login), "password": password})
	var res := await _req(HTTPClient.METHOD_POST, SUPABASE_URL + "/auth/v1/token?grant_type=password", _headers(), body)
	var j: Variant = res["json"]
	if not res["ok"] or not (j is Dictionary and j.has("access_token")):
		var msg := "Неверный логин или пароль"
		if j is Dictionary:
			msg = str(j.get("error_description", j.get("msg", j.get("error", msg))))
		return {"ok": false, "message": msg}
	_apply_session(j, nickname)
	await merge_pull()
	return {"ok": true, "message": ""}

func _refresh_session() -> bool:
	if not configured() or String(data.get("refresh", "")) == "":
		return false
	var body := JSON.stringify({"refresh_token": data["refresh"]})
	var res := await _req(HTTPClient.METHOD_POST, SUPABASE_URL + "/auth/v1/token?grant_type=refresh_token", _headers(), body)
	var j: Variant = res["json"]
	if res["ok"] and j is Dictionary and j.has("access_token"):
		_apply_session(j)
		return true
	return false

# Восстановление сессии при старте (держим вошедшим до ручного выхода).
func restore() -> void:
	if get_mode() == "user" and configured():
		var exp: int = int(data.get("expires_at", 0))
		if String(data.get("refresh", "")) != "" and (exp == 0 or exp < Time.get_unix_time_from_system() * 1000 + 60000):
			await _refresh_session()
		await merge_pull()

# Пуш локального профиля в облако (в конце цикла / смене ника).
func push_profile() -> bool:
	if get_mode() != "user" or String(data.get("user_id", "")) == "" or String(data.get("token", "")) == "":
		return false
	var body := JSON.stringify({
		"id": data["user_id"], "nickname": data["nickname"],
		"data": PotionProfile.export_data(),
		"updated_at": Time.get_datetime_string_from_system(true),
	})
	var hdrs := _headers(data["token"])
	hdrs.append("Prefer: resolution=merge-duplicates")
	var res := await _req(HTTPClient.METHOD_POST, SUPABASE_URL + "/rest/v1/profiles", hdrs, body)
	return res["ok"]

# Тянем облако ТОЛЬКО если оно впереди по xp (иначе локальный главнее — пушим его).
func merge_pull() -> void:
	if String(data.get("user_id", "")) == "" or String(data.get("token", "")) == "":
		return
	var url := SUPABASE_URL + "/rest/v1/profiles?id=eq." + str(data["user_id"]) + "&select=nickname,data"
	var res := await _req(HTTPClient.METHOD_GET, url, _headers(data["token"]))
	var rows: Variant = res["json"]
	if res["ok"] and rows is Array and rows.size() > 0:
		var row: Dictionary = rows[0]
		if row.get("nickname"):
			data["nickname"] = String(row["nickname"]).substr(0, 20)
			_save()
		var remote: Variant = row.get("data")
		if remote is Dictionary:
			var remote_xp: int = int((remote.get("progression", {}) as Dictionary).get("xp", 0))
			var local_xp: int = int((PotionProfile.export_data().get("progression", {}) as Dictionary).get("xp", 0))
			if remote_xp > local_xp:
				PotionProfile.import_data(remote)      # облако впереди → подтягиваем
			else:
				await push_profile()                   # локальный впереди/равен → пушим наверх

# ---------- лидерборд ----------
func leaderboard_load(board: String = "arcade") -> Array:
	if not configured():
		return []
	var url := SUPABASE_URL + "/rest/v1/leaderboard?board=eq." + board.uri_encode() + "&select=name,score,created_at&order=score.desc&limit=50"
	var res := await _req(HTTPClient.METHOD_GET, url, _headers(str(data.get("token", ""))))
	if res["ok"] and res["json"] is Array:
		return res["json"]
	return []

func leaderboard_save(board: String, name: String, score: int) -> bool:
	if get_mode() != "user" or str(data.get("token", "")) == "" or str(data.get("user_id", "")) == "":
		return false
	var b := board if board != "" else "arcade"
	var del := SUPABASE_URL + "/rest/v1/leaderboard?user_id=eq." + str(data["user_id"]).uri_encode() + "&board=eq." + b.uri_encode()
	await _req(HTTPClient.METHOD_DELETE, del, _headers(data["token"]))
	var hdrs := _headers(data["token"])
	hdrs.append("Prefer: return=minimal")
	var body := JSON.stringify({"board": b, "name": name.substr(0, 20), "score": int(round(score)), "user_id": data["user_id"]})
	var res := await _req(HTTPClient.METHOD_POST, SUPABASE_URL + "/rest/v1/leaderboard", hdrs, body)
	return res["ok"]
