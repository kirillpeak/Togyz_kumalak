extends Node
class_name WebSocketClient

signal connected()
signal connection_failed()
signal disconnected()
signal move_received(pit_index: int)
signal game_state_updated(game_state: Dictionary)
signal game_started(data: Dictionary)
signal game_ended(result: String)
signal reconnecting(attempt: int)
signal player_info_received(data: Dictionary)

var socket := WebSocketPeer.new()
var lobby_id: String = ""
var game_id: String = ""
var player_id: String = ""
var _connected: bool = false

# Reconnection logic
var auto_reconnect := true
var reconnect_attempts := 0
var max_reconnect_attempts := 5
var reconnect_delay := 2.0

func _ready():
	set_process(true)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			print("✅ WebSocket успешно подключён")
			emit_signal("connected")
		while socket.get_available_packet_count() > 0:
			var msg := socket.get_packet().get_string_from_utf8()
			var parsed = JSON.parse_string(msg)
			if parsed == null:
				print("⚠️ Ошибка парсинга JSON:", msg)
				continue
			if typeof(parsed) != TYPE_DICTIONARY:
				print("⚠️ Ожидался словарь, получено:", parsed)
				continue
			_on_message_received(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_handle_disconnection()

func connect_to_lobby(id: String):
	lobby_id = id
	_connected = false
	reconnect_attempts = 0

	var url = "%s/game/ws/game/%s?token=%s" % [Config.WS_URL, id, Global.user_token]
	if url == "":
		push_error("URL пустой!")
		return

	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(url)
	if err != OK:
		push_error("Не удалось инициировать подключение к серверу WebSocket")
		emit_signal("connection_failed")
		return

	print("🔌 Подключение к WebSocket:", url)

func _handle_disconnection():
	if connected:
		print("🔌 Соединение потеряно.")
		_connected = false
		emit_signal("disconnected")
		if auto_reconnect:
			_try_reconnect()

func _try_reconnect():
	if reconnect_attempts < max_reconnect_attempts:
		reconnect_attempts += 1
		print("🔁 Попытка переподключения #%d" % reconnect_attempts)
		emit_signal("reconnecting", reconnect_attempts)
		await get_tree().create_timer(reconnect_delay).timeout
		connect_to_lobby(lobby_id)
	else:
		print("⛔ Превышено количество попыток переподключения.")
		emit_signal("connection_failed")

func is_server_connected() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func send_json(data: Dictionary):
	if is_server_connected():
		var json := JSON.stringify(data)
		socket.send_text(json)
		print("📤 Отправлено:", json)
	else:
		push_warning("⚠️ Соединение не установлено — не удалось отправить сообщение.")

func disconnect_from_server():
	if is_server_connected():
		socket.close()
	_handle_disconnection()

func reconnect():
	if lobby_id != "":
		connect_to_lobby(lobby_id)

func send_move(hole_index: int):
	var move_data := {
		"type": "move",
		"game_id": game_id,
		"player_id": player_id,
		"hole_index": hole_index
	}
	send_json(move_data)

func _on_message_received(data: Dictionary):
	print("📩 Получено сообщение:", data)
	if "type" in data:
		print("ℹ️ Ключ 'type' найден, значение:", data["type"])
	else:
		print("⚠️ Ключ 'type' отсутствует в сообщении")
	var message_type = data.get("type", "")
	print("ℹ️ Тип сообщения (data.get('type', '')):", message_type)
	match message_type:
		"join_ack":
			_connected = true
			print("✅ Успешное подключение к комнате.")
			emit_signal("connected")

		"move":
			if data.has("hole_index"):
				print("🎯 Получен ход:", data["hole_index"])
				emit_signal("move_received", data["hole_index"])

		"game_start":
			print("🎮 Начало игры:", data)
			emit_signal("game_started", data)
		
		"player_info":
			print("ℹ️ Информация о текущем игроке:", data)
			emit_signal("player_info_received", data)  
		
		"end_game":
			var result = data.get("result", "unknown")
			print("🏁 Игра завершена:", result)
			emit_signal("game_ended", result)

		"state_sync":
			if data.has("game_state"):
				print("🔄 Обновление состояния:", data["game_state"])
				emit_signal("game_state_updated", data["game_state"])

		_:
			print("⚠️ Неизвестный тип сообщения:", data)

# === Опциональные методы ===

func set_player_info(game: String, player: String):
	game_id = game
	player_id = player

func enable_auto_reconnect(enabled: bool):
	auto_reconnect = enabled
