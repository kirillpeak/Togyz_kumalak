extends Node2D

var websocket_client = preload("res://Scripts/configs/websocket_client.gd").new()
var game_logic = preload("res://Scripts/togyz_kumalak_core.gd").new()

var PLAYER1
var PLAYER2
var NUM_HOLES
var start_time = 0  # Для отслеживания времени
var lobby_id = Global.current_game_id
var my_user_id = ""

@onready var tuzduk_highlight = preload("res://assets/board/tuzduk_highlight.png")
@onready var connection_status_label = $CanvasLayer/ConnectionStatus
@onready var label_player1 = $CanvasLayer/WrapperTahaForPlayer1/LabelForPlayer1 #значения колодцев
@onready var label_player2 = $CanvasLayer/WrapperTahaForPlayer2/LabelForPlayer2
@onready var LabelForPlayer1 = $CanvasLayer/LabelForPlayer1 #отоброжение ника игрока
@onready var LabelForPlayer2 = $CanvasLayer/LabelForPlayer2 
@onready var taha_player1 = $CanvasLayer/TahaPlayer1
@onready var taha_player2 = $CanvasLayer/TahaPlayer2
@onready var kazan_player1 = $CanvasLayer/WrapperTahaForPlayer1
@onready var kazan_player2 = $CanvasLayer/WrapperTahaForPlayer2
@onready var popup_endgame = $CanvasLayer/PopupEndgame
@onready var label_endgame_info = $CanvasLayer/PopupEndgame/VBoxContainer/LabelInfo
@onready var button_return_menu = $CanvasLayer/PopupEndgame/VBoxContainer/GridContainer/ButtonReturnMenu
@onready var button_new_game = $CanvasLayer/PopupEndgame/VBoxContainer/GridContainer/ButtonNewGame

func _ready():
	PLAYER1 = game_logic.PLAYER1
	PLAYER2 = game_logic.PLAYER2
	NUM_HOLES = game_logic.NUM_HOLES
	start_time = Time.get_ticks_msec()  # Время начала игры
	game_logic.initialize_game()
	
	if Global.user_id == "":
		var token_parts = Global.user_token.split(".")
		if token_parts.size() > 1:
			var payload = JSON.parse_string(token_parts[1].base64_decode().get_string_from_utf8())
			Global.user_id = payload["sub"]
	my_user_id = Global.user_id
	print("ℹ️ Мой user_id:", my_user_id)
	
	add_child(websocket_client) # Добавляем в дерево
	
	# Подключаем WebSocket-обработчики
	websocket_client.connect("connected", Callable(self, "_on_connection_established"))
	websocket_client.connect("connection_failed", Callable(self, "_on_connection_failed"))
	websocket_client.connect("game_state_updated", Callable(self, "_update_game_state"))
	websocket_client.connect("move_received", Callable(self, "_on_move_received"))
	websocket_client.connect("game_ended", Callable(self, "_on_game_end"))
	websocket_client.connect("game_started", Callable(self, "_on_game_started"))
	websocket_client.connect("player_info_received", Callable(self, "_on_player_info_received"))
	websocket_client.connect_to_lobby(lobby_id)  
	
	setup_hole_buttons()
	update_board()

func _on_connection_established():
	connection_status_label.text = "Connected"
	connection_status_label.modulate = Color.GREEN

func _on_connection_failed():
	connection_status_label.text = "Connection Failed!"
	connection_status_label.modulate = Color.RED

func setup_hole_buttons():
	for i in range(NUM_HOLES):
		var slot1 = taha_player1.get_node("myArea2D" + str(i + 1))
		var slot2 = taha_player2.get_node("myArea2D" + str(i + 1))
		slot1.connect("input_event", Callable(self, "_on_slot_input_event").bind(PLAYER1, i))
		slot2.connect("input_event", Callable(self, "_on_slot_input_event").bind(PLAYER2, i))

# Игрок делает ход
func _on_slot_input_event(_area, event, _shape_idx, player, hole_index):
	if event is InputEventMouseButton and event.pressed:
		if player == game_logic.current_player:
			websocket_client.send_move(hole_index)  # Отправляем ход на сервер

# Обновление состояния игры с сервера
func _update_game_state(new_state):
	if not new_state.has("board") or not new_state.has("kazans"):
		print("❌ Invalid game state")
		return

	game_logic.board_state = new_state.board
	game_logic.kazans = new_state.kazans
	game_logic.current_player = new_state.current_player
	game_logic.tuz_declared = new_state.tuzdyk

	if new_state.get("winner", -1) != -1:
		show_endgame_popup(new_state.winner)

	update_board()  

func _on_player_info_received(data: Dictionary):
	print("ℹ️ Обработка player_info:", data)
	var player = data["player"]
	if my_user_id == player["id"]:
		LabelForPlayer1.text = player["username"]  # Отображаем ник текущего игрока
		LabelForPlayer2.text = "Waiting..."  # Ждём второго игрока
	print("✅ Установлен мой ник: ", LabelForPlayer1.text)

# Обработка сообщений от WebSocket
func _on_game_started(data: Dictionary):
	print("🎮 Обработка game_start:", data)
	var player1 = data["player1"]
	var player2 = data["player2"]
	if my_user_id == player1["id"]:
		LabelForPlayer1.text = player1["username"]  # Мой ник внизу слева
		LabelForPlayer2.text = player2["username"] if player2["username"] else "Waiting..."  # Противник вверху справа
	else:
		LabelForPlayer1.text = player2["username"]  # Мой ник внизу слева
		LabelForPlayer2.text = player1["username"]  # Противник вверху справа

func _on_move_received(hole_index: int):
	# Обработка принятого хода от другого игрока
	print("Получен ход игрока: ", hole_index)
	# Обновление  состояния игры
	update_board()

func _on_game_end(result: String):
	# Завершаем игру и показываем результаты
	show_endgame_popup(result)

func update_board():
	label_player1.text = str(game_logic.kazans[PLAYER1])
	label_player2.text = str(game_logic.kazans[PLAYER2])

	for player in [PLAYER1, PLAYER2]:
		for i in range(NUM_HOLES):
			clear_hole(player, i)
			add_stones_to_hole(player, i, game_logic.board_state[game_logic.get_hole_index(player, i)])
			# Обновление туздыка
			if game_logic.tuz_declared[player] == i:
				var slot = get_slot(1 - player, i)
				clear_tuzduk_highlight(slot)
				var highlight = Sprite2D.new()
				highlight.texture = tuzduk_highlight
				highlight.name = "TuzdukHighlight"
				highlight.scale.x = 1.558
				highlight.scale.y = 1.621
				slot.add_child(highlight)

	# Обновление туздука для обоих игроков
	for opponent in [PLAYER1, PLAYER2]:
		if game_logic.tuz_declared[opponent] != -1:
			var slot_opponent = get_slot(1 - opponent, game_logic.tuz_declared[opponent])
			clear_tuzduk_highlight(slot_opponent)
			var highlight_opponent = Sprite2D.new()
			highlight_opponent.texture = tuzduk_highlight
			highlight_opponent.name = "TuzdukHighlight"
			highlight_opponent.scale.x = 1.558
			highlight_opponent.scale.y = 1.621
			slot_opponent.add_child(highlight_opponent)

	update_kazan(PLAYER1)
	update_kazan(PLAYER2)

# Завершение игры
func show_endgame_popup(result):
	var total_time = (Time.get_ticks_msec() - start_time) / 1000.0  # Общее время в секундах
	var result_text = "Ничья!"
	if result == "player1":
		result_text = "Победил Игрок 1!"
	elif result == "player2":
		result_text = "Победил Игрок 2!"

	var info_text = "%s\nСчёт: %d - %d\nОбщее время партии: %.2f сек." % [result_text, game_logic.kazans[PLAYER1], game_logic.kazans[PLAYER2], total_time]
	label_endgame_info.text = info_text
	popup_endgame.popup_centered()
	popup_endgame.show()

func clear_tuzduk_highlight(slot):
	for child in slot.get_children():
		if child.name == "TuzdukHighlight":
			child.queue_free()

# Очистка лунки
func clear_hole(player, hole_index):
	var slot = get_slot(player, hole_index)
	for child in slot.get_children():
		if child.name != "Label" and child.name != "CollisionShape2D" and child.name != "TuzdukHighlight":
			child.queue_free()

# Добавление камней в лунку
func add_stones_to_hole(player, hole_index, num_stones):
	var slot = get_slot(player, hole_index)
	var label = slot.get_node("Label")
	label.text = str(num_stones)

	clear_hole(player, hole_index)
	var collision_shape = slot.get_node("CollisionShape2D")
	if collision_shape and collision_shape.shape:
		var shape_extents = collision_shape.shape.extents
		var center = Vector2(0, 0)
		var radius = min(shape_extents.x, shape_extents.y) * 0.8

		for i in range(num_stones):
			var angle = deg_to_rad(i * (360.0 / num_stones))
			var offset = Vector2(cos(angle) * radius, sin(angle) * radius)
			var stone = Sprite2D.new()
			stone.texture = preload("res://assets/board/stone_taha.png")
			stone.position = center + offset
			slot.add_child(stone)

# Очистка казана
func clear_kazan(kazan):
	for child in kazan.get_children():
		if child.name != "WrapperTahaForPlayer" and child.name != "CollisionShape2D" and child.name != "LabelForPlayer1" and child.name != "LabelForPlayer2":
			child.queue_free()

# Обновление казана
func update_kazan(player):
	var kazan = kazan_player1 if player == PLAYER1 else kazan_player2
	clear_kazan(kazan)

	var collision_shape = kazan.get_node("CollisionShape2D")
	if collision_shape and collision_shape.shape:
		var kazan_size = collision_shape.shape.extents * 2
		var kazan_width = kazan_size.x
		var kazan_height = kazan_size.y

		var row_height = kazan_height / 3
		var column_width = kazan_width / game_logic.KAZAN_COLUMNS
		var max_rows = 2

		for i in range(game_logic.kazans[player]):
			@warning_ignore("integer_division")
			var row = floor(i / game_logic.KAZAN_COLUMNS) % max_rows
			var col = i % game_logic.KAZAN_COLUMNS
			var stone = Sprite2D.new()
			stone.texture = preload("res://assets/board/stone_taha.png")

			var x_pos = col * column_width + column_width / 2 - kazan_width / 2
			var y_pos = row * row_height + row_height / 2 - kazan_height / 2

			stone.position = Vector2(x_pos, y_pos)
			kazan.add_child(stone)

func get_slot(player, hole_index):
	var slots = taha_player1 if player == PLAYER1 else taha_player2
	return slots.get_node("myArea2D" + str(hole_index + 1))
