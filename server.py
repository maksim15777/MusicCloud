import os
import io
import sqlite3
import hashlib
import asyncio
from typing import Optional, List
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, FileResponse, PlainTextResponse
from pydantic import BaseModel
from telethon import TelegramClient
from telethon.errors import (
    SessionPasswordNeededError,
    PhoneCodeInvalidError,
    PasswordHashInvalidError,
    PhoneNumberInvalidError,
    FloodWaitError
)
from telethon.tl.types import DocumentAttributeAudio, DocumentAttributeFilename

# ==========================================
# Configurations & Constants
# ==========================================
API_ID = 35197117
API_HASH = "f92e244c8c272a00ae07551f08fd0427"
TARGET_CHAT = "MusicCloud"
SESSION_FILE = "musiccloud_session"
DB_FILE = "musiccloud.db"
DESKTOP_APP_FILE = "desktop_player.py"
CURRENT_DESKTOP_VERSION = "1.0.1"

# ==========================================
# Database Initialization (Ecosystem Accounts)
# ==========================================
def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # Таблица пользователей экосистемы MusicCloud
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        tg_phone TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    # Таблица метаданных и версий приложений
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS app_versions (
        platform TEXT PRIMARY KEY,
        version TEXT NOT NULL,
        changelog TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)
    
    cursor.execute("""
    INSERT OR REPLACE INTO app_versions (platform, version, changelog)
    VALUES ('desktop', ?, 'Initial release with Auto-Updater and Apple Dark UI')
    """, (CURRENT_DESKTOP_VERSION,))
    
    conn.commit()
    conn.close()

init_db()

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode("utf-8")).hexdigest()

# ==========================================
# Telethon Client Management
# ==========================================
client: Optional[TelegramClient] = None
pending_auth = {}

async def get_client() -> TelegramClient:
    global client
    if client is None:
        client = TelegramClient(
            SESSION_FILE,
            API_ID,
            API_HASH,
            device_model="iPhone 14 Pro",
            system_version="iOS 16.5",
            app_version="10.2.1",
            lang_code="ru",
            system_lang_code="ru"
        )
    if not client.is_connected():
        await client.connect()
    return client

@asynccontextmanager
async def lifespan(app: FastAPI):
    tg = await get_client()
    is_auth = await tg.is_user_authorized()
    print("==================================================")
    print(" [MusicCloud Ecosystem] Backend Server Started!")
    print(f" [MusicCloud] Telegram MTProto Connected: {is_auth}")
    print(f" [MusicCloud] Database: {DB_FILE} initialized")
    print(f" [MusicCloud] Desktop App Version: {CURRENT_DESKTOP_VERSION}")
    print("==================================================")
    yield
    if client and client.is_connected():
        await client.disconnect()

app = FastAPI(title="MusicCloud Ecosystem Server", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# Models
# ==========================================
class UserRegisterRequest(BaseModel):
    username: str
    password: str
    phone: Optional[str] = None

class UserLoginRequest(BaseModel):
    username: str
    password: str

class SendCodeRequest(BaseModel):
    phone: str

class SignInRequest(BaseModel):
    phone: str
    code: str

class Password2FARequest(BaseModel):
    password: str

class DeleteTracksRequest(BaseModel):
    message_ids: List[int]

def clean_phone_number(raw_phone: str) -> str:
    cleaned = raw_phone.strip().replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
    if not cleaned.startswith("+"):
        cleaned = "+" + cleaned
    return cleaned

# ==========================================
# Ecosystem Account Endpoints
# ==========================================
@app.post("/api/accounts/register")
async def register_account(req: UserRegisterRequest):
    u = req.username.strip().lower()
    if len(u) < 3:
        raise HTTPException(status_code=400, detail="Имя пользователя должно содержать минимум 3 символа")
    if len(req.password) < 4:
        raise HTTPException(status_code=400, detail="Пароль должен содержать минимум 4 символа")
    
    p_hash = hash_password(req.password)
    phone = clean_phone_number(req.phone) if req.phone else None
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO users (username, password_hash, tg_phone) VALUES (?, ?, ?)", (u, p_hash, phone))
        conn.commit()
        user_id = cursor.lastrowid
        return {"status": "registered", "user_id": user_id, "username": u}
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Пользователь с таким именем уже существует")
    finally:
        conn.close()

@app.post("/api/accounts/login")
async def login_account(req: UserLoginRequest):
    u = req.username.strip().lower()
    p_hash = hash_password(req.password)
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT id, username, tg_phone FROM users WHERE username = ? AND password_hash = ?", (u, p_hash))
    user = cursor.fetchone()
    conn.close()
    
    if not user:
        raise HTTPException(status_code=401, detail="Неверное имя пользователя или пароль")
    
    return {
        "status": "authenticated",
        "user": {
            "id": user[0],
            "username": user[1],
            "tg_phone": user[2]
        }
    }

# ==========================================
# Desktop Auto-Updater Endpoints
# ==========================================
@app.get("/api/version")
async def get_version():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT version, changelog FROM app_versions WHERE platform = 'desktop'")
    row = cursor.fetchone()
    conn.close()
    
    v = row[0] if row else CURRENT_DESKTOP_VERSION
    changelog = row[1] if row else "Latest update"
    
    # Считаем хэш файла приложения
    app_hash = ""
    if os.path.exists(DESKTOP_APP_FILE):
        with open(DESKTOP_APP_FILE, "rb") as f:
            app_hash = hashlib.sha256(f.read()).hexdigest()
            
    return {
        "version": v,
        "hash": app_hash,
        "changelog": changelog,
        "download_url": "/api/desktop/latest"
    }

@app.get("/api/desktop/latest")
async def download_latest_desktop_code():
    if not os.path.exists(DESKTOP_APP_FILE):
        raise HTTPException(status_code=404, detail="Файл обновления desktop_player.py не найден на сервере")
    return FileResponse(
        DESKTOP_APP_FILE,
        media_type="text/x-python",
        filename="desktop_player.py"
    )

# ==========================================
# Telegram MTProto Auth Endpoints
# ==========================================
@app.get("/auth/status")
async def get_auth_status():
    tg = await get_client()
    return {"authorized": await tg.is_user_authorized()}

@app.post("/auth/send-code")
async def send_code(req: SendCodeRequest):
    phone = clean_phone_number(req.phone)
    tg = await get_client()
    try:
        result = await tg.send_code_request(phone, force_sms=False)
        pending_auth[phone] = result.phone_code_hash
        print(f"[MusicCloud] Code sent to Telegram app for {phone}")
        return {"status": "code_sent", "phone": phone}
    except PhoneNumberInvalidError:
        raise HTTPException(status_code=400, detail="Неверный номер телефона. Укажите номер с кодом страны (например +380... или +7...)")
    except FloodWaitError as e:
        raise HTTPException(status_code=429, detail=f"Слишком много попыток. Подождите {e.seconds} сек.")
    except Exception as e:
        err_str = str(e)
        print(f"[send_code error]: {err_str}")
        if "all available options" in err_str.lower():
            err_str = "Telegram не смог отправить код. Убедитесь, что открыто приложение Telegram (код приходит в чат) и номер начинается с '+'."
        raise HTTPException(status_code=400, detail=err_str)

@app.post("/auth/sign-in")
async def sign_in(req: SignInRequest):
    phone = clean_phone_number(req.phone)
    code = req.code.strip().replace(" ", "").replace("-", "")
    phone_code_hash = pending_auth.get(phone)
    tg = await get_client()
    
    try:
        await tg.sign_in(phone=phone, code=code, phone_code_hash=phone_code_hash)
        print(f"[MusicCloud] User {phone} successfully authenticated!")
        return {"status": "authenticated"}
    except SessionPasswordNeededError:
        return {"status": "2fa_required"}
    except PhoneCodeInvalidError:
        raise HTTPException(status_code=400, detail="Неверный код подтверждения")
    except Exception as e:
        print(f"[sign_in error]: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/auth/2fa")
async def sign_in_2fa(req: Password2FARequest):
    tg = await get_client()
    try:
        await tg.sign_in(password=req.password)
        print("[MusicCloud] 2FA password accepted, logged in!")
        return {"status": "authenticated"}
    except PasswordHashInvalidError:
        raise HTTPException(status_code=400, detail="Неверный пароль 2FA")
    except Exception as e:
        print(f"[2fa error]: {e}")
        raise HTTPException(status_code=400, detail=str(e))

# ==========================================
# Chat & Audio Endpoints
# ==========================================
async def get_target_chat(tg: TelegramClient):
    if not await tg.is_user_authorized():
        raise HTTPException(status_code=401, detail="Не авторизован в Telegram")
        
    async for dialog in tg.iter_dialogs():
        if dialog.name == TARGET_CHAT or dialog.title == TARGET_CHAT:
            return dialog.entity
            
    raise HTTPException(
        status_code=404, 
        detail=f"Чат/канал '{TARGET_CHAT}' не найден. Создайте чат или группу с названием '{TARGET_CHAT}' в Telegram."
    )

@app.get("/tracks")
async def list_tracks():
    tg = await get_client()
    chat = await get_target_chat(tg)
    tracks = []
    async for msg in tg.iter_messages(chat, limit=200):
        if msg.audio or (msg.document and any(isinstance(x, DocumentAttributeAudio) for x in msg.document.attributes)):
            doc = msg.audio or msg.document
            title = "Без названия"
            performer = "Неизвестный исполнитель"
            duration = 0
            file_name = "audio.mp3"
            
            for attr in doc.attributes:
                if isinstance(attr, DocumentAttributeAudio):
                    if attr.title: title = attr.title
                    if attr.performer: performer = attr.performer
                    if attr.duration: duration = attr.duration
                elif isinstance(attr, DocumentAttributeFilename):
                    file_name = attr.file_name
            
            tracks.append({
                "id": str(msg.id),
                "message_id": msg.id,
                "chat_id": chat.id,
                "title": title,
                "performer": performer,
                "duration": duration,
                "file_name": file_name,
                "file_size": doc.size,
                "date_added": msg.date.isoformat()
            })
    return {"tracks": tracks}

@app.get("/tracks/{message_id}/audio")
async def get_audio(message_id: int):
    tg = await get_client()
    chat = await get_target_chat(tg)
    msg = await tg.get_messages(chat, ids=message_id)
    if not msg or not (msg.audio or msg.document):
        raise HTTPException(status_code=404, detail="Файл не найден")
    
    audio_bytes = await tg.download_media(msg, file=bytes)
    return StreamingResponse(
        io.BytesIO(audio_bytes),
        media_type="audio/mpeg",
        headers={"Content-Disposition": f'inline; filename="track_{message_id}.mp3"'}
    )

@app.post("/tracks/upload")
async def upload_track(
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    performer: Optional[str] = Form(None)
):
    tg = await get_client()
    chat = await get_target_chat(tg)
    content = await file.read()
    t_name = title or file.filename or "Без названия"
    p_name = performer or "Неизвестный исполнитель"
    
    file_io = io.BytesIO(content)
    file_io.name = file.filename or "audio.mp3"
    
    msg = await tg.send_file(
        chat,
        file_io,
        caption=None,
        attributes=[DocumentAttributeAudio(duration=0, title=t_name, performer=p_name)]
    )
    return {"id": str(msg.id), "message_id": msg.id, "title": t_name, "performer": p_name}

@app.post("/tracks/delete")
async def delete_tracks(req: DeleteTracksRequest):
    tg = await get_client()
    chat = await get_target_chat(tg)
    await tg.delete_messages(chat, message_ids=req.message_ids)
    return {"status": "deleted"}

if __name__ == "__main__":
    import uvicorn
    print("Starting MusicCloud Ecosystem Server on 0.0.0.0:8900 ...")
    uvicorn.run("server:app", host="0.0.0.0", port=8900, reload=False)
