extends Node

var user_token: String = ""
var user_id: String  = ""
var is_logged_in: bool = false
var current_game_id: String  = ""

func _ready():
	load_auth_data()

func load_auth_data():
	if FileAccess.file_exists("user://auth.dat"):
		var file = FileAccess.open_encrypted_with_pass("user://auth.dat", FileAccess.READ, "secret")
		var data = JSON.parse_string(file.get_as_text())
		user_token = data["user_token"]
		is_logged_in = data["is_logged_in"]

func save_auth_data():
	var data = {"user_token": user_token, "is_logged_in": is_logged_in}
	var file = FileAccess.open_encrypted_with_pass("user://auth.dat", FileAccess.WRITE, "secret")
	file.store_string(JSON.stringify(data))
	file.close()
