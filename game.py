from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from database import get_db
from models import ActiveGame, User
from schemas import GameCreate, GameMove, GameResponse
from typing import Dict, List
from auth import get_current_user, get_user_from_token
from fastapi import Query
import uuid

router = APIRouter()

# Активные игры
active_games: Dict[str, Dict[str, WebSocket]] = {}

# 📌 Создание игры
@router.post("/create")
async def create_game(db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    existing_game = await db.execute(select(ActiveGame).where(ActiveGame.player1_id == str(user.user_id)))
    if existing_game.scalars().first():
        raise HTTPException(status_code=400, detail="Вы уже создали игру")
    new_game = ActiveGame(player1_id=str(user.user_id), current_state={})
    db.add(new_game)
    await db.commit()
    await db.refresh(new_game)
    return {"game_id": str(new_game.game_id), "player1_id": str(new_game.player1_id)}

# 📌 Получение списка доступных игр
@router.get("/list", response_model=List[GameResponse])
async def list_games(db: AsyncSession = Depends(get_db)):
    print("Запрос списка игр")
    
    try:
        result = await db.execute(select(ActiveGame))
        games = result.scalars().all()
        print("Найдено игр: ", len(games))
    except Exception as e:
        print("❌ Ошибка при получении игр:", str(e))
        games = []  # Инициализируем games пустым списком
    
    return [
        {
            "game_id": str(game.game_id),
            "owner": str(game.player1_id),
            "players": [str(game.player1_id)] + ([str(game.player2_id)] if game.player2_id else [])
        }
        for game in games
    ]

# 📌 Присоединение к игре
@router.post("/join/{game_id}")
async def join_game(
    game_id: str, 
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user)  # Получаем текущего пользователя
):
    try:
        game_uuid = uuid.UUID(game_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Некорректный UUID игры")

    game = await db.get(ActiveGame, game_uuid)
    if not game:
        raise HTTPException(status_code=404, detail="Игра не найдена")

    if game.player2_id:
        raise HTTPException(status_code=400, detail="Игра уже заполнена")

    # Используем ID текущего пользователя
    game.player2_id = str(user.user_id)  # Предполагая, что user.id уже UUID
    await db.commit()
    return {"game_id": game_id, "player2_id": game.player2_id}

async def get_game_from_db(game_id: str, db: AsyncSession = Depends(get_db)):
    query = await db.execute(select(ActiveGame).where(ActiveGame.game_id == game_id))
    game = query.scalar_one_or_none()
    return game

# 📌 WebSocket соединение для игры
@router.websocket("/ws/game/{game_id}")
async def game_websocket(websocket: WebSocket, game_id: str, token: str, db: AsyncSession = Depends(get_db)):
    try:
        print("🔧 WebSocket запрос получен")
        token = websocket.query_params.get("token")
        print(f" token = {token }")
        user = await get_user_from_token(token, db)  # Проверяем токен и получаем пользователя
        print(f"✅ Пользователь: {user}")
        if not user:
            print("❌ Пользователь не аутентифицирован")
            await websocket.close(code=1008)
            return

        await websocket.accept()
        print(f"🔌 Подключение игрока {user.username} к игре {game_id}")

        if game_id not in active_games:
            active_games[game_id] = {}
        active_games[game_id][str(user.user_id)] = websocket

        game = await get_game_from_db(game_id, db)
        if not game:
            print(f"❌ Игра {game_id} не найдена")
            await websocket.close(code=1008)
            return

        player1_query = await db.execute(select(User).where(User.user_id == game.player1_id))
        player1 = player1_query.scalar_one()
        player2_query = await db.execute(select(User).where(User.user_id == game.player2_id))
        player2 = player2_query.scalar_one_or_none()

        # Отправляем информацию о текущем игроке сразу после подключения
        player_info_message = {
            "type": "player_info",
            "player": {"id": str(user.user_id), "username": user.username},
            "game_id": game_id
        }
        await websocket.send_json(player_info_message)
        print(f"📤 Отправлено player_info для {user.username}")
        
        if len(active_games[game_id]) == 2:
            game_state = await get_game_state(game_id, db)
            game_start_message = {
                "type": "game_start",
                "player1": {"id": str(player1.user_id), "username": player1.username},
                "player2": {"id": str(player2.user_id) if player2 else None, "username": player2.username if player2 else None},
                "game_id": game_id,
                "game_state": game_state
            }
            for player_ws in active_games[game_id].values():
                await player_ws.send_json(game_start_message)
            print("🎮 Отправлено game_start обоим игрокам")
        else:
            await websocket.send_json({"message": "Ожидание второго игрока"})
        
        try:
            while True:
                print(f"⏳ Ожидание данных от {user.user_id}")
                data = await websocket.receive_json()
                print(f"📥 Получены данные: {data}")
                if "hole_index" in data:  # Если получен ход от игрока
                    game_state = await process_move(game_id, user.user_id, data["hole_index"], db)

                    # Отправляем обновленный state обоим игрокам
                    for player_ws in active_games[game_id].values():
                        await player_ws.send_json({"game_state": game_state})

                elif data.get("type") == "start_game":  # Если игра начинается
                    game_state = await start_game(game_id, db)
                    for player_ws in active_games[game_id].values():
                        await player_ws.send_json({"game_state": game_state, "message": "Игра началась"})

                elif data.get("type") == "end_game":  # Если игра заканчивается
                    game_state = await end_game(game_id, db)
                    for player_ws in active_games[game_id].values():
                        await player_ws.send_json({"game_state": game_state, "message": "Игра завершена"})

        except WebSocketDisconnect:
            for ws in active_games[game_id].values():
               await ws.send_json({"type": "opponent_disconnected"})
            del active_games[game_id][str(user.user_id)]
            if not active_games[game_id]:  # Если игра пустая, удалить из активных
                del active_games[game_id]

    except Exception as e:
        print(f"❌ Ошибка WebSocket: {e}")


# 📌 Обработка хода
async def process_move(game_id: str, player_id: str, hole_index: int, db: AsyncSession):
    game = await db.get(ActiveGame, uuid.UUID(game_id))
    if not game:
        raise HTTPException(status_code=404, detail="Игра не найдена")
    
    # Логика для обработки хода
    game.current_state["last_move"] = {"player_id": player_id, "hole_index": hole_index}
    await db.commit()
    return game.current_state

# 📌 Начало игры
async def start_game(game_id: str, db: AsyncSession):
    game = await db.get(ActiveGame, uuid.UUID(game_id))
    if not game:
        raise HTTPException(status_code=404, detail="Игра не найдена")
    
    # Логика для начала игры
    game.current_state["started"] = True
    await db.commit()
    return game.current_state

# 📌 Завершение игры
async def end_game(game_id: str, db: AsyncSession):
    game = await db.get(ActiveGame, uuid.UUID(game_id))
    if not game:
        raise HTTPException(status_code=404, detail="Игра не найдена")
    
    # Логика для завершения игры
    game.current_state["ended"] = True
    await db.commit()
    return game.current_state

# 📌 Получение состояния игры
async def get_game_state(game_id: str, db: AsyncSession):
    game = await db.get(ActiveGame, uuid.UUID(game_id))
    if not game:
        raise HTTPException(status_code=404, detail="Игра не найдена")
    return game.current_state

    

