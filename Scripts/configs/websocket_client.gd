extends Node

var websocket = WebSocketPeer.new()
var game_id = ""
var player_id = ""
var is_client_connected = false  # Переименована переменная

signal game_state_updated(new_state)
signal connection_established()
signal connection_failed()

func _ready():
	websocket.connect("connection_established", Callable(self, "_on_connected"))
	websocket.connect("data_received", Callable(self, "_on_message"))
	websocket.connect("connection_closed", Callable(self, "_on_disconnected"))
	websocket.connect("connection_error", Callable(self, "_on_error"))
	add_child(websocket)

func _process(_delta):
	websocket.poll()

	if websocket.get_ready_state() == WebSocketPeer.STATE_OPEN and not is_client_connected:
		is_client_connected = true
		emit_signal("connection_established")

func connect_to_game(game: String, player: String, auth_token: String):
	game_id = game
	player_id = player
	var ws_url = "%s/ws/game?game_id=%s&player_id=%s&token=%s" % [
		Config.WS_URL,
		game_id,
		player_id,
		auth_token
		]
	print("🔗 Подключаемся к WebSocket: ", ws_url)

	var error = websocket.connect_to_url(ws_url)
	if error != OK:
		print("❌ Ошибка подключения: ", error)
		emit_signal("connection_failed")
	else:
		print("⌛ Подключение...")

func send_move(hole_index: int):
	if is_client_connected:
		var move_data = {
			"game_id": game_id,
			"player_id": player_id,
			"hole_index": hole_index
		}
		websocket.send_text(JSON.stringify(move_data))
		print("📤 Отправлен ход: ", move_data)
	else:
		print("⚠️ Нет подключения!")

func _on_connected(protocol):
	print("✅ Подключено (", protocol, ")")

func _on_message():
	var pkt = websocket.get_packet()
	if pkt.size() > 0:
		var message = pkt.get_string_from_utf8()
		print("📩 Raw message: ", message)
		var data = JSON.parse_string(message)

		if data and data.has("game_state"):
			print("🔄 Получено состояние игры: ", data.game_state)
			emit_signal("game_state_updated", data.game_state)

func _on_disconnected(_was_clean, _code, reason):
	is_client_connected = false
	print("⚠️ Отключено: ", reason)

func _on_error():
	is_client_connected = false
	emit_signal("connection_failed")
