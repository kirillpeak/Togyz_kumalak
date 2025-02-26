from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from config import DATABASE_URL

# Создаем объект Base
Base = declarative_base()

# Создаем движок для асинхронного взаимодействия с PostgreSQL
engine = create_async_engine(DATABASE_URL, echo=True)

# Создаем фабрику сессий
AsyncSessionLocal = sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

# Функция для получения сессии
async def get_db():
    async with AsyncSessionLocal() as session:
        yield session