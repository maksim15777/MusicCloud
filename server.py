import io
import asyncio
from typing import Optional, List
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from telethon import TelegramClient
from telethon.errors import (
    SessionPasswordNeededError,
    PhoneCodeInvalidError,
    PasswordHashInvalidError,
    PhoneNumberInvalidError
)
from telethon.tl.types import DocumentAttributeAudio, DocumentAttributeFilename

# ==========================================
# Telegram API Credentials
# ==========================================
API_ID = 35197117
API_HASH = "f92e244c8c272a00ae07551f08fd0427"
TARGET_CHAT = "MusicCloud"
SESSION_FILE = "musiccloud_session"

app = FastAPI(title="MusicCloud Proxy")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
pending_auth = {}

@app.on_event("startup")
async def startup():
    await client.connect()
    print(f"[MusicCloud] MTProto connected. Authorized: {await client.is_user_authorized()}")

@app.on_event("shutdown")
async def shutdown():
    await client.disconnect()

# ==========================================
# Auth Models & Endpoints
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

@app.get("/auth/status")
async def get_auth_status():
    return {"authorized": await client.is_user_authorized()}

@app.post("/auth/send-code")
async def send_code(req: SendCodeRequest):
    phone = req.phone.strip()
    try:
        result = await client.send_code_request(phone)
        pending_auth[phone] = result.phone_code_hash
        return {"status": "code_sent", "phone": phone}
    except PhoneNumberInvalidError:
        raise HTTPException(status_code=400, detail="Неверный номер телефона")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/auth/sign-in")
async def sign_in(req: SignInRequest):
    phone = req.phone.strip()
    code = req.code.strip()
    phone_code_hash = pending_auth.get(phone)
    try:
        await client.sign_in(phone=phone, code=code, phone_code_hash=phone_code_hash)
        return {"status": "authenticated"}
    except SessionPasswordNeededError:
        return {"status": "2fa_required"}
    except PhoneCodeInvalidError:
        raise HTTPException(status_code=400, detail="Неверный код подтверждения")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/auth/2fa")
async def sign_in_2fa(req: Password2FARequest):
    try:
        await client.sign_in(password=req.password)
        return {"status": "authenticated"}
    except PasswordHashInvalidError:
        raise HTTPException(status_code=400, detail="Неверный пароль 2FA")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# Chat & Audio Endpoints
# ==========================================
async def get_target_chat():
    if not await client.is_user_authorized():
        raise HTTPException(status_code=401, detail="Не авторизован в Telegram")
    async for dialog in client.iter_dialogs():
        if dialog.name == TARGET_CHAT or dialog.title == TARGET_CHAT:
            return dialog.entity
    raise HTTPException(status_code=404, detail=f"Чат/канал '{TARGET_CHAT}' не найден. Создайте его в Telegram.")

@app.get("/tracks")
async def list_tracks():
    chat = await get_target_chat()
    tracks = []
    async for msg in client.iter_messages(chat, limit=200):
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
    chat = await get_target_chat()
    msg = await client.get_messages(chat, ids=message_id)
    if not msg or not (msg.audio or msg.document):
        raise HTTPException(status_code=404, detail="Файл не найден")
    
    audio_bytes = await client.download_media(msg, file=bytes)
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
    chat = await get_target_chat()
    content = await file.read()
    t_name = title or file.filename or "Без названия"
    p_name = performer or "Неизвестный исполнитель"
    
    file_io = io.BytesIO(content)
    file_io.name = file.filename or "audio.mp3"
    
    msg = await client.send_file(
        chat,
        file_io,
        caption=f'{{"{t_name}", "{p_name}"}}',
        attributes=[DocumentAttributeAudio(duration=0, title=t_name, performer=p_name)]
    )
    return {"id": str(msg.id), "message_id": msg.id, "title": t_name, "performer": p_name}

@app.post("/tracks/delete")
async def delete_tracks(req: DeleteTracksRequest):
    chat = await get_target_chat()
    await client.delete_messages(chat, message_ids=req.message_ids)
    return {"status": "deleted"}

if __name__ == "__main__":
    import uvicorn
    print("Starting MusicCloud Server on 0.0.0.0:8900 ...")
    uvicorn.run(app, host="0.0.0.0", port=8900)
