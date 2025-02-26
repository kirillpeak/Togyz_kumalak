extends Node2D

@onready var username_input = $CanvasLayer/VBoxContainer/UsernameInput
@onready var email_input = $CanvasLayer/VBoxContainer/EmailInput
@onready var password_input = $CanvasLayer/VBoxContainer/PasswordInput
@onready var confirm_password_input = $CanvasLayer/VBoxContainer/ConfirmPasswordInput
@onready var register_button = $CanvasLayer/VBoxContainer/RegisterButton
@onready var back_button = $CanvasLayer/VBoxContainer/BackButton
@onready var error_label = $CanvasLayer/VBoxContainer/ErrorLabel

var server_url = Config.SERVER_URL  # URL из Config.gd

# 📌 Регистрация нового аккаунта
func _on_RegisterButton_pressed():
	var username = username_input.text.strip_edges()
	var email = email_input.text.strip_edges()
	var password = password_input.text.strip_edges()
	var confirm_password = confirm_password_input.text.strip_edges()

	if username.is_empty() or email.is_empty() or password.is_empty():
		error_label.text = "Заполните все поля!"
		return

	if password != confirm_password:
		error_label.text = "Пароли не совпадают!"
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_register_response)

	var url = server_url + "/auth/register"  # <-- Проверь этот путь
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"username": username, "email": email, "password": password})

	print("📡 Отправка запроса: ", url, " | Данные: ", body)

	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("❌ Ошибка запроса регистрации: ", error)

# 📌 Обработка ответа сервера
func _on_register_response(_result, response_code, _headers, body):
	print("🔍 Ответ сервера (код): ", response_code)
	print("📜 Тело ответа: ", body.get_string_from_utf8())

	if response_code == 200:
		print("✅ Регистрация успешна!")
		_attempt_login(email_input.text, password_input.text)
	else:
		error_label.text = "❌ Ошибка регистрации! Сервер ответил: " + body.get_string_from_utf8()

func _attempt_login(email: String, password: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_login_response)
	var url = server_url + "/auth/login"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"email": email, "password": password})

	print("📡 Отправка запроса входа: ", url, " | Данные: ", body)

	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("❌ Ошибка запроса входа: ", error)

func _on_login_response(_result, response_code, _headers, body):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and "access_token" in response:
			Global.user_token = response["access_token"]
			Global.is_logged_in = true
			print("✅ Авторизация успешна! Токен: ", Global.user_token)
			Global.save_auth_data()
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		else:
			error_label.text = "❌ Ошибка: неверный формат ответа сервера!"
	else:
		error_label.text = "❌ Неверный email или пароль!"

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/AuthScene.tscn") 
