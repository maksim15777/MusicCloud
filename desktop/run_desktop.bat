@echo off
title MusicCloud Desktop
cd /d "%~dp0"

echo ==================================================
echo         MusicCloud Desktop Client Launcher
echo ==================================================
echo.

python -m pip install -q customtkinter pygame pillow requests

python updater.py
pause
