from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from database import engine, Base
import asyncio
from auth import router as auth_router  # Подключаем роутер авторизации
from game import router as game_router  # Подключаем роутер игровой логики
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)



@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Запуск FastAPI... Инициализация базы данных")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield  # Здесь можно добавить код для очистки ресурсов при завершении работы

    logger.info(" Завершение работы FastAPI...")

app = FastAPI(lifespan=lifespan)

app.include_router(auth_router, prefix="/auth", tags=["auth"])
app.include_router(game_router, prefix="/game", tags=["game"])

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Разрешить все источники
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def home():
    return {"message": "Server is running"}

if __name__ == "__main__":
    import uvicorn
    logger.info(f"Все маршруты после регистрации: {[route.path for route in app.routes]}")
    uvicorn.run(app, host="localhost", port=8000)
