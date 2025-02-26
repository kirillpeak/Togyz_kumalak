extends Node2D

@onready var username_input = $CanvasLayer/VBoxContainer/UsernameInput
@onready var password_input = $CanvasLayer/VBoxContainer/PasswordInput
@onready var login_button = $CanvasLayer/VBoxContainer/HBoxContainer/LoginButton
@onready var register_button = $CanvasLayer/VBoxContainer/HBoxContainer/RegisterButton
@onready var error_label = $CanvasLayer/VBoxContainer/ErrorLabel

var server_url = Config.SERVER_URL # Убедитесь, что это правильный URL
var user_token = ""
var is_logged_in = false

func _ready():
	load_auth_data()
	if is_logged_in and user_token != "":
		validate_token()

# 📌 Загрузка сохраненных данных
func load_auth_data():
	if FileAccess.file_exists("user://auth.dat"):
		var file = FileAccess.open_encrypted_with_pass("user://auth.dat", FileAccess.READ, "secret")
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data and "user_token" in data and "is_logged_in" in data:
			user_token = data["user_token"]
			is_logged_in = data["is_logged_in"]

# 📌 Проверка токена (авто-вход)
func validate_token():
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_token_validation)

	var url = server_url + "/auth/me"
	var headers = ["Authorization: Bearer " + user_token]

	print("Проверка токена: URL=", url, " Headers=", headers)
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("Ошибка проверки токена: ", error)

# 📌 Обработка проверки токена
func _on_token_validation(_result, response_code, _headers, body):
	print("Ответ на проверку токена: Code=", response_code, " Body=", body.get_string_from_utf8())
	if response_code == 200:
		print("✅ Токен действителен. Вход в главное меню...")
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		print("❌ Токен недействителен. Требуется повторный вход.")

# 📌 Вход по кнопке "Войти"
func _on_LoginButton_pressed():
	var email = username_input.text.strip_edges()  # Используем email
	var password = password_input.text.strip_edges()

	if email.is_empty() or password.is_empty():
		error_label.text = "Введите email и пароль!"
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_login_response)

	var url = server_url + "/auth/login"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"email": email, "password": password})  # Используем email

	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("Ошибка запроса авторизации: ", error)

# 📌 Обработка ответа от сервера
func _on_login_response(_result, response_code, _headers, body):
	print("Ответ сервера: Code=", response_code, " Body=", body.get_string_from_utf8())
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and "access_token" in response:
			user_token = response["access_token"]
			is_logged_in = true
			print("✅ Авторизация успешна! Токен: ", user_token)
			Global.save_auth_data()
			print("✅ Токен сохранен!")
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		else:
			error_label.text = "❌ Ошибка: неверный формат ответа сервера!"
	else:
		error_label.text = "❌ Неверный email или пароль!"

# 📌 Переход к регистрации
func _on_RegisterButton_pressed():
	get_tree().change_scene_to_file("res://scenes/register_scene.tscn")

# 📌 Возврат в главное меню
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
