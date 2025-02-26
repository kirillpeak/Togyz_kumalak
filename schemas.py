from pydantic import BaseModel, EmailStr
from typing import Optional, List, Dict
import uuid

class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str

class TokenData(BaseModel):
    user_id: uuid.UUID
    username: str

class GameCreate(BaseModel):
    player1_id: uuid.UUID

class GameMove(BaseModel):
    game_id: uuid.UUID
    player_id: uuid.UUID
    move: Dict

class UserLogin(BaseModel):
    email: str
    password: str

class GameResponse(BaseModel):
    game_id: str
    owner: str
    players: List[str]
