@echo off
title MusicCloud Backend Server
echo ===================================================
echo   MusicCloud Telegram MTProto Backend Proxy
echo ===================================================
echo.

cd /d "%~dp0"

echo [1/2] Checking Python dependencies...
python -m pip install -r requirements.txt

echo.
echo [2/2] Starting server on http://0.0.0.0:8000 ...
echo.
echo Your iPhone can connect to: http://YOUR_PC_LOCAL_IP:8000
echo (Example: http://192.168.1.50:8000)
echo.
python main.py

pause
