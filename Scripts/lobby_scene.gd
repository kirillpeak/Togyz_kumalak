extends Node2D

@onready var games_list = $CanvasLayer/VBoxContainer/GamesList
@onready var create_game_button = $CanvasLayer/VBoxContainer/HBoxContainer/CreateGameButton
@onready var refresh_button = $CanvasLayer/VBoxContainer/HBoxContainer/RefreshButton

var server_url = Config.SERVER_URL 
var user_token = Global.user_token # Здесь будет токен авторизации

func _ready():
	print("User Token: ", Global.user_token)
	load_games()

# 📌 Запрос списка игр с сервера
func load_games():
	var http_request = HTTPRequest.new()
	add_child(http_request)  # Убедитесь, что этот вызов присутствует
	http_request.request_completed.connect(_on_games_received)

	var url = server_url + "/game/list"
	var headers = ["Authorization: Bearer " + user_token]

	print("Запрос списка игр: ", url)
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("Ошибка запроса списка игр: ", error)

# 📌 Обработка полученного списка игр
func _on_games_received(_result, response_code, _headers, body):
	if response_code == 200:
		var raw_body = body.get_string_from_utf8()
		print("Raw response:", raw_body)
		var json = JSON.new()
		var parse_error = json.parse(raw_body)
		
		if parse_error != OK:
			print("❌ JSON parse error:", json.get_error_message())
			return
			
		var games = json.data
		print("Parsed games:", games)
		games_list.clear()
		for game in games:
			# Проверка структуры игры
			if not ("game_id" in game and "owner" in game and "players" in game):
				print("❌ Invalid game structure:", game)
				continue
				
			# Формирование текста
			var short_id = game["game_id"].substr(0, 8)
			var player_count = game["players"].size()
			var status = "Ожидание" if player_count < 2 else "Игра идет"
			var entry_text = "%s | %s | %d/2" % [short_id, status, player_count]
			
			# Добавление в список
			games_list.add_item(entry_text)
			var last_idx = games_list.get_item_count() - 1
			games_list.set_item_metadata(last_idx, game["game_id"])
			
			print("Added game:", entry_text, "| Metadata:", game["game_id"])
			# games_list.update() 
	else:
		print("❌ Ошибка загрузки игр! Код:", response_code, " Ответ:", body.get_string_from_utf8())


# 📌 Вход в игру по клику
func _on_GamesList_item_activated(index):
	var game_id = games_list.get_item_metadata(index)

	if "Игра идет" in games_list.get_item_text(index):
		print("❌ Эта игра уже началась!")
		return

	join_game(game_id)

# 📌 Создание новой игры
func _on_CreateGameButton_pressed():
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_game_created)

	var url = server_url + "/game/create"
	var headers = ["Authorization: Bearer " + user_token, "Content-Type: application/json"]
	var body = "{}"  
	print("Запрос создания игры: ", url)
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("Ошибка создания игры: ", error)

# 📌 Обработка созданной игры
func _on_game_created(_result, response_code, _headers, body):
	if response_code == 200:
		var game = JSON.parse_string(body.get_string_from_utf8())
		print("🎮 Игра создана! ID: ", game["game_id"])
		Global.current_game_id = game["game_id"]
		# Сохраняем player1_id в глобальной переменной, чтобы он не был пустым
		Global.user_id = game["player1_id"]
		get_tree().change_scene_to_file("res://scenes/gameBoardMultiplayer.tscn")
	else:
		print("❌ Ошибка создания игры! Код:", response_code, " Ответ:", body.get_string_from_utf8())

# 📌 Присоединение к игре
func join_game(game_id):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_game_joined)

	var url = server_url + "/game/join/" + game_id
	var headers = ["Authorization: Bearer " + user_token]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST)
	if error != OK:
		print("Ошибка подключения к игре: ", error)

# 📌 Обработка успешного входа в игру
func _on_game_joined(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.new()
		var parse_error = json.parse(body.get_string_from_utf8())
		
		if parse_error == OK:
			var game = json.data
			print("✅ Подключен к игре! Ответ:", game)
			Global.current_game_id = str(game.get("game_id"))
			Global.user_id = str(game.get("player2_id"))  # Сохраняем ID игрока
			get_tree().change_scene_to_file("res://scenes/gameBoardMultiplayer.tscn")
		else:
			print("❌ Ошибка парсинга ответа:", json.get_error_message())
	else:
		var error_body = body.get_string_from_utf8() if body else ""
		print("❌ Ошибка входа в игру! Код:", response_code, "Ответ:", error_body)

# 📌 Кнопка обновления списка игр
func _on_RefreshButton_pressed():
	load_games()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
