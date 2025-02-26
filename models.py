from sqlalchemy import Column, String, ForeignKey, TIMESTAMP, JSON, Float, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import declarative_base
import uuid

Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    user_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String(50), unique=True, nullable=False)
    email = Column(String(100), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    rating = Column(Float, default=1000.0)

class ActiveGame(Base):
    __tablename__ = "active_games"
    game_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    player1_id = Column(UUID(as_uuid=True), ForeignKey("users.user_id"), nullable=True)
    player2_id = Column(UUID(as_uuid=True), ForeignKey("users.user_id"), nullable=True)
    current_state = Column(JSON, nullable=False, default={})
    start_time = Column(TIMESTAMP, nullable=True)
    last_update = Column(TIMESTAMP, nullable=True)

class WebSocketConnection(Base):
    __tablename__ = "websocket_connections"
    connection_id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.user_id"), nullable=False)
    session_id = Column(UUID(as_uuid=True), ForeignKey("active_games.game_id"), nullable=False)
    socket_id = Column(String(255), unique=True, nullable=False)
    connected_at = Column(TIMESTAMP, nullable=False)
