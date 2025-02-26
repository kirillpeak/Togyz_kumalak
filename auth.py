from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from datetime import datetime, timedelta
from database import get_db
from jose import JWTError, jwt
from passlib.context import CryptContext
from config import SECRET_KEY, ALGORITHM, ACCESS_TOKEN_EXPIRE_MINUTES
from models import User
from schemas import UserCreate, UserLogin
from database import AsyncSessionLocal, get_db
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

router = APIRouter()

# Настройка контекста для хеширования паролей с использованием pbkdf2_sha256
pwd_context = CryptContext(
    schemes=["pbkdf2_sha256"],
    deprecated="auto",
    pbkdf2_sha256__default_rounds=120000
)

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password, hashed_password) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: timedelta):
    to_encode = data.copy()
    expire = datetime.utcnow() + expires_delta
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

async def get_current_user(token: str = Depends(oauth2_scheme), db: AsyncSession = Depends(get_db)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_email = payload.get("sub")

        if not user_email:
            raise HTTPException(status_code=401, detail="Invalid token")

        result = await db.execute(select(User).where(User.email == user_email))
        user = result.scalars().first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        return user
    except JWTError as e:
        raise HTTPException(status_code=401, detail="Token decoding error")

def decode_access_token(token: str):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None

@router.get("/me")
async def get_current_user_info(user: User = Depends(get_current_user)):
    return {"user_id": str(user.user_id), "email": user.email, "username": user.username}

@router.post("/register")
async def register_user(user_data: UserCreate, db: AsyncSession = Depends(get_db)):
    stmt_email = select(User).where(User.email == user_data.email)
    result_email = await db.execute(stmt_email)
    existing_user_email = result_email.scalar_one_or_none()

    if existing_user_email:
        raise HTTPException(status_code=400, detail="User with this email already exists")

    stmt_username = select(User).where(User.username == user_data.username)
    result_username = await db.execute(stmt_username)
    existing_user_username = result_username.scalar_one_or_none()

    if existing_user_username:
        raise HTTPException(status_code=400, detail="User with this username already exists")

    hashed_password = hash_password(user_data.password)

    new_user = User(
        username=user_data.username,
        email=user_data.email,
        password_hash=hashed_password,
        rating=1000.0
    )

    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)

    return {"message": "Registration successful", "user_id": str(new_user.user_id)}

@router.post("/login")
async def login_user(login_data: UserLogin, db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(User.email == login_data.email)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not verify_password(login_data.password, user.password_hash):
        raise HTTPException(status_code=400, detail="Incorrect password")

    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )

    return {"access_token": access_token, "token_type": "bearer"}
