extends Node

# Константы
const PLAYER1 = 0
const PLAYER2 = 1
const NUM_HOLES = 9
const DRAW_POSITION_REPETITIONS = 73
const BASE_SCORE = 9
const KAZAN_COLUMNS = 28

# Игровые переменные
var board_state = []
var kazans = [0, 0]
var current_player = PLAYER1
var tuz_declared = [-1, -1]
var position_repetitions = {}
var turn_log = []
var total_turns = 0

func initialize_game():
	board_state = []
	for i in range(NUM_HOLES * 2):
		board_state.append(BASE_SCORE)
	kazans = [0, 0]
	current_player = PLAYER1
	tuz_declared = [-1, -1]
	position_repetitions.clear()
	turn_log.clear()
	total_turns = 0


func handle_hole_press(player: int, hole_index: int) -> bool:
	if player != current_player:
		return false

	var index = get_hole_index(player, hole_index)
	var stones = board_state[index]

	if stones == 0:
		return false

	turn_log.append([player, hole_index, stones])

	# Оставляем 1 коргоол, если их было больше одного
	if stones > 1:
		board_state[index] = 1
		stones -= 1
	else:
		board_state[index] = 0

	var current_index = index

	while stones > 0:
		current_index = (current_index + 1) % board_state.size()
		if is_kazan_skipped(player, current_index):
			continue

		if is_tuzduk(current_index):
			kazans[get_tuzduk_owner(current_index)] += 1
		else:
			board_state[current_index] += 1
		stones -= 1

	check_tuzduk(player, current_index)
	check_and_capture(player, current_index)
	finish_turn()
	return true

# Перемещение одного коргола в соседнюю лунку
func move_single_korgol(index: int):
	var next_index = (index + 1) % board_state.size()
	board_state[next_index] += board_state[index]
	board_state[index] = 0

# Получение индекса лунки
func get_hole_index(player: int, hole_index: int) -> int:
	return hole_index if player == PLAYER1 else NUM_HOLES + hole_index

func check_game_end() -> int:
	var player1_sum = 0
	var player2_sum = 0
	total_turns = len(turn_log)
	# Подсчёт коргоолов на стороне игроков
	for i in range(NUM_HOLES):
		player1_sum += board_state[i]
	for i in range(NUM_HOLES, NUM_HOLES * 2):
		player2_sum += board_state[i]

	# Проверка победителя по количеству коргоолов в казане
	if kazans[PLAYER1] >= 82:
		return PLAYER1
	elif kazans[PLAYER2] >= 82:
		return PLAYER2

	# Ситуация "ат сыроо" (игрок A лишён ходов)
	if player1_sum == 0:  # У игрока 1 все дома пустые
		if not can_return_stones_to_opponent(PLAYER2, PLAYER1):
			collect_all_stones_to_kazan(PLAYER2)
			return PLAYER2
	if player2_sum == 0:  # У игрока 2 все дома пустые
		if not can_return_stones_to_opponent(PLAYER1, PLAYER2):
			collect_all_stones_to_kazan(PLAYER1)
			return PLAYER1

	# Проверка ничьи по 81 коргоолу в казане
	if kazans[PLAYER1] == 81 and kazans[PLAYER2] == 81:
		return -1

	# Проверка ничьи по повторению позиции
	var key = str(board_state) + str(tuz_declared) + str(current_player)
	if position_repetitions.get(key, 0) >= DRAW_POSITION_REPETITIONS:
		return -1

	# Возвращаем специальное значение, означающее, что игра продолжается
	return -2

# Проверка, может ли игрок вернуть коргоолы противнику
func can_return_stones_to_opponent(active_player: int, _opponent_player):
	var opponent_start = NUM_HOLES if active_player == PLAYER1 else 0
	var opponent_end = NUM_HOLES * 2 if active_player == PLAYER1 else NUM_HOLES
	for i in range(opponent_start, opponent_end):
		# Если хоть один коргоол может попасть на сторону противника
		if board_state[i] > 0:
			return true
	return false

# Перенос всех коргоолов игрока в казан
func collect_all_stones_to_kazan(player):
	var player_start = 0 if player == PLAYER1 else NUM_HOLES
	var player_end = NUM_HOLES if player == PLAYER1 else NUM_HOLES * 2
	for i in range(player_start, player_end):
		kazans[player] += board_state[i]
		board_state[i] = 0

# Завершение хода
func finish_turn():
	record_position()
	current_player = 1 - current_player
	check_game_end()

# Запись текущей позиции
func record_position():
	var key = str(board_state) + str(tuz_declared) + str(current_player)
	position_repetitions[key] = position_repetitions.get(key, 0) + 1

# Проверка пропуска казана
func is_kazan_skipped(player: int, index: int) -> bool:
	return (player == PLAYER1 and index == NUM_HOLES * 2 - 1) or (player == PLAYER2 and index == NUM_HOLES - 1)

# Проверка туздыка
func check_tuzduk(player: int, last_index: int):
	if tuz_declared[player] != -1:
		return  # У игрока уже есть туздук
	
	var opponent = 1 - player
	var hole = last_index % NUM_HOLES
	
	# Проверка условий для туздука
	if (player == PLAYER1 and last_index >= NUM_HOLES) or (player == PLAYER2 and last_index < NUM_HOLES):
		if hole == NUM_HOLES - 1:  # Лунка №9 (ооз) не может быть туздуком
			return
		if tuz_declared[opponent] == (NUM_HOLES - 1 - hole):
			return 
		if board_state[last_index] == 3:  # 1 (последний) + 2 = 3 коргоола
			# Проверка уникальности номера лунки
			if tuz_declared[opponent] != hole:
				tuz_declared[player] = hole
				kazans[player] += board_state[last_index]
				board_state[last_index] = 0
   
# Захват камней
func check_and_capture(player: int, last_index: int):
	# Захват только на стороне соперника
	if (player == PLAYER1 and last_index >= NUM_HOLES) or (player == PLAYER2 and last_index < NUM_HOLES):
		if board_state[last_index] % 2 == 0:
			kazans[player] += board_state[last_index]
			board_state[last_index] = 0

# Проверка, является ли лунка туздуком
func is_tuzduk(index: int) -> bool:
	var hole = index % NUM_HOLES
	if index < NUM_HOLES:
		return tuz_declared[PLAYER2] == hole
	else:
		return tuz_declared[PLAYER1] == hole

# Получение владельца туздука
func get_tuzduk_owner(index: int) -> int:
	return PLAYER1 if index >= NUM_HOLES else PLAYER2
