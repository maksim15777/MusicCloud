import io
import os
import asyncio
from typing import Optional, List
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
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
# Telegram API Credentials
# ==========================================
API_ID = 35197117
API_HASH = "f92e244c8c272a00ae07551f08fd0427"
TARGET_CHAT = "MusicCloud"
SESSION_FILE = "musiccloud_session"

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
    print(f"==================================================")
    print(f" [MusicCloud] Telegram MTProto connected successfully!")
    print(f" [MusicCloud] Authorized: {is_auth}")
    print(f"==================================================")
    yield
    if client and client.is_connected():
        await client.disconnect()

app = FastAPI(title="MusicCloud Proxy", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# Auth Models & Helpers
# ==========================================
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

@app.get("/auth/status")
async def get_auth_status():
    tg = await get_client()
    return {"authorized": await tg.is_user_authorized()}

@app.post("/auth/send-code")
async def send_code(req: SendCodeRequest):
    phone = clean_phone_number(req.phone)
    tg = await get_client()
    
    # Если сервер уже авторизован в Telegram
    if await tg.is_user_authorized():
        print(f"[MusicCloud] User already authorized! Skipping code request.")
        return {"status": "authenticated", "message": "Already authorized"}
        
    try:
        result = await tg.send_code_request(phone, force_sms=False)
        pending_auth[phone] = result.phone_code_hash
        print(f"[MusicCloud] Code successfully sent to Telegram for {phone}")
        return {"status": "code_sent", "phone": phone}
    except PhoneNumberInvalidError:
        raise HTTPException(status_code=400, detail="Неверный номер телефона. Укажите номер с кодом страны (например +380... или +7...)")
    except FloodWaitError as e:
        raise HTTPException(status_code=429, detail=f"Слишком много попыток. Подождите {e.seconds} секунд")
    except Exception as e:
        err_str = str(e)
        print(f"[send_code error]: {err_str}")
        if "already used" in err_str.lower() or "all available options" in err_str.lower():
            err_str = "Код уже был отправлен в ваш Telegram. Проверьте сообщения в приложении Telegram или подождите 1-2 минуты перед повторным запросом."
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
        raise HTTPException(status_code=400, detail="Неверный пароль двухфакторной аутентификации")
    except Exception as e:
        print(f"[2fa error]: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/auth/logout")
async def logout():
    tg = await get_client()
    try:
        if await tg.is_user_authorized():
            await tg.log_out()
    except Exception as e:
        print(f"[logout error]: {e}")
    return {"status": "logged_out"}

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
    return Response(
        content=audio_bytes,
        media_type="audio/mpeg",
        headers={
            "Content-Disposition": f'inline; filename="track_{message_id}.mp3"',
            "Content-Length": str(len(audio_bytes)),
            "Accept-Ranges": "bytes"
        }
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
    print("Starting MusicCloud Server on 0.0.0.0:8900 ...")
    uvicorn.run("server:app", host="0.0.0.0", port=8900, reload=False)
