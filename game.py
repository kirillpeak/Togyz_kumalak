from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from database import get_db
from models import ActiveGame,User
from schemas import GameCreate, GameMove, GameResponse
from typing import Dict, List
from auth import get_current_user
from fastapi import Query
import uuid

router = APIRouter()  

# Активные игры
active_games: Dict[str, Dict[str, WebSocket]] = {}

# Создание игры
@router.post("/create")
async def create_game(db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    new_game = ActiveGame(player1_id=str(user.user_id), current_state={})  # UUID пользователя
    db.add(new_game)
    await db.commit()
    await db.refresh(new_game)
    return {"game_id": str(new_game.game_id)}

# Получение списка доступных игр
@router.get("/list", response_model=List[GameResponse])
async def list_games(db: AsyncSession = Depends(get_db)):
    print("Запрос списка игр")
    
    try:
        result = await db.execute(select(ActiveGame))
        games = result.scalars().all()
        print("Найдено игр: ", len(games))
    except Exception as e:
        print("Ошибка при получении игр:", str(e))
        games = []  # Инициализируем games пустым списком
    
    return [
        {
            "game_id": str(game.game_id),
            "owner": str(game.player1_id),
            "players": [str(game.player1_id)] + ([str(game.player2_id)] if game.player2_id else [])
        }
        for game in games
    ]

# Присоединение к игре
@router.post("/join/{game_id}")
async def join_game(
    game_id: str, 
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user)  # Получаем текущего пользователя
):
    game = await db.get(ActiveGame, uuid.UUID(game_id))
    if not game:
        raise HTTPException(status_code=404, detail="Игра не найдена")

    if game.player2_id:
        raise HTTPException(status_code=400, detail="Игра уже заполнена")

    # Используем ID текущего пользователя
    game.player2_id = str(user.user_id)  # Предполагая, что user.id уже UUID
    await db.commit()
    return {"game_id": game_id, "player2_id": game.player2_id}

# WebSocket соединение для игры
@router.websocket("/ws/game")
async def game_websocket(websocket: WebSocket, game_id: str, player_id: str, token: str):
    print(f"Подключение: game_id={game_id}, player_id={player_id}, token={token[:10]}...")
    try:
        user = await get_current_user(token)
        if not user:
            await websocket.close()
            print("WebSocket неподключен")
            return

        await websocket.accept()
        print(" WebSocket подключен")
        if game_id not in active_games:
            active_games[game_id] = {}

        active_games[game_id][player_id] = websocket
        print(f" Игрок {player_id} подключился к игре {game_id}")

        try:
            while True:
                data = await websocket.receive_json()
                print(f" Получен ход: {data}")  #  Логируем полученные данные

                game_state = await process_move(game_id, data["player_id"], data["hole_index"], db)
                
                print(f" Отправляем обновленный game_state: {game_state}")

                for player_ws in active_games[game_id].values():
                    await player_ws.send_json({"game_state": game_state})

        except WebSocketDisconnect:
            print(f" Игрок {player_id} отключился от игры {game_id}")
            del active_games[game_id][player_id]
    except Exception as e:
        print(f" Ошибка: {str(e)}")

    

async def process_move(game_id: str, player_id: str, hole_index: int, db: AsyncSession):
    game = await db.get(ActiveGame, uuid.UUID(game_id))
    if not game:
        return {"error": "Игра не найдена"}

    # Инициализация состояния игры
    if not game.current_state:
        game.current_state = {
            "board": [9] * 18,
            "kazans": [0, 0],
            "current_player": 0,
            "tuzdyk": [-1, -1],
            "winner": -1
        }

    # Применяем логику хода
    state = game.current_state
    success = handle_move(state, player_id, hole_index)
    
    if not success:
        return {"error": "Недопустимый ход"}

    game.current_state = state
    await db.commit()
    
    return game.current_state

def handle_move(state, player_id, hole_index):
    try:
        player = 0 if player_id == str(state["players"][0]) else 1
        index = hole_index + (9 * player)
        
        if state["board"][index] == 0:
            return False

        # Реализация логики перемещения камней
        stones = state["board"][index]
        state["board"][index] = 0
        
        current_index = index
        while stones > 0:
            current_index = (current_index + 1) % 18
            if current_index in [8, 17]:  # Пропуск казанов
                continue
            
            state["board"][current_index] += 1
            stones -= 1

        # Проверка захвата камней
        if state["board"][current_index] % 2 == 0:
            state["kazans"][player] += state["board"][current_index]
            state["board"][current_index] = 0

        # Смена игрока
        state["current_player"] = 1 - player
        return True

    except Exception as e:
        print(f"❌ Ошибка обработки хода: {str(e)}")
        return False
