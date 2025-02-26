extends Node2D

func _on_button_pressed():
	get_tree().change_scene_to_file("res://scenes/gameBoard.tscn")


func _on_logout_button_pressed():
	get_tree().change_scene_to_file("res://scenes/AuthScene.tscn")


func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/LobbyScene.tscn")


func _on_button_4_pressed() -> void:
	Global.user_token = ""
	Global.is_logged_in = false
	var user_token = ""
	var is_logged_in = false
	var data = {"user_token": user_token, "is_logged_in": is_logged_in}
	var file = FileAccess.open_encrypted_with_pass("user://auth.dat", FileAccess.WRITE, "secret")
	file.store_string(JSON.stringify(data))
	file.close()
