import os
import sys
import io
import time
import json
import random
import ctypes
import tempfile
import threading
import urllib.request
import urllib.parse
import urllib.error
from typing import List, Optional, Dict

# GUI Import
try:
    import customtkinter as ctk
except ImportError:
    import tkinter as ctk

# Audio Player Engine (Windows Native MCI + Pygame fallback)
class AudioEngine:
    def __init__(self):
        self.backend = "none"
        self.is_playing = False
        self.current_file = None
        self.volume = 0.8
        
        try:
            import pygame
            pygame.mixer.init()
            self.backend = "pygame"
            self.pygame = pygame
            print("[AudioEngine] Using Pygame mixer")
        except Exception:
            if sys.platform == "win32":
                self.backend = "win_mci"
                self.winmm = ctypes.windll.winmm
                print("[AudioEngine] Using Windows Native Audio Engine (MCI)")
            else:
                print("[AudioEngine] No audio backend available")

    def load_and_play(self, filepath: str):
        self.current_file = filepath
        if self.backend == "pygame":
            try:
                self.pygame.mixer.music.load(filepath)
                self.pygame.mixer.music.set_volume(self.volume)
                self.pygame.mixer.music.play()
                self.is_playing = True
            except Exception as e:
                print(f"[AudioEngine] Pygame play error: {e}")
                self.is_playing = False
        elif self.backend == "win_mci":
            try:
                self.winmm.mciSendStringW("close mc_audio", None, 0, None)
                short_path = filepath.replace('"', '')
                cmd = f'open "{short_path}" type mpegvideo alias mc_audio'
                res = self.winmm.mciSendStringW(cmd, None, 0, None)
                if res != 0:
                    cmd = f'open "{short_path}" alias mc_audio'
                    self.winmm.mciSendStringW(cmd, None, 0, None)
                
                self.set_volume(self.volume)
                self.winmm.mciSendStringW("play mc_audio", None, 0, None)
                self.is_playing = True
            except Exception as e:
                print(f"[AudioEngine] MCI play error: {e}")
                self.is_playing = False

    def pause(self):
        if self.backend == "pygame":
            self.pygame.mixer.music.pause()
        elif self.backend == "win_mci":
            self.winmm.mciSendStringW("pause mc_audio", None, 0, None)
        self.is_playing = False

    def unpause(self):
        if self.backend == "pygame":
            self.pygame.mixer.music.unpause()
        elif self.backend == "win_mci":
            self.winmm.mciSendStringW("resume mc_audio", None, 0, None)
        self.is_playing = True

    def stop(self):
        if self.backend == "pygame":
            self.pygame.mixer.music.stop()
        elif self.backend == "win_mci":
            self.winmm.mciSendStringW("stop mc_audio", None, 0, None)
            self.winmm.mciSendStringW("close mc_audio", None, 0, None)
        self.is_playing = False

    def set_volume(self, vol: float):
        self.volume = max(0.0, min(1.0, vol))
        if self.backend == "pygame":
            self.pygame.mixer.music.set_volume(self.volume)
        elif self.backend == "win_mci":
            mci_vol = int(self.volume * 1000)
            self.winmm.mciSendStringW(f"setaudio mc_audio volume to {mci_vol}", None, 0, None)

    def is_busy(self) -> bool:
        if self.backend == "pygame":
            return self.pygame.mixer.music.get_busy()
        elif self.backend == "win_mci":
            buf = ctypes.create_unicode_buffer(128)
            self.winmm.mciSendStringW("status mc_audio mode", buf, 128, None)
            return buf.value.lower() == "playing"
        return False

SERVER_URL = os.getenv("MUSICCLOUD_SERVER", "http://199.83.103.63:8900")
CACHE_DIR = os.path.join(tempfile.gettempdir(), "MusicCloud_AudioCache")
os.makedirs(CACHE_DIR, exist_ok=True)

if hasattr(ctk, "set_appearance_mode"):
    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("dark-blue")

# Gradients & Colors for Track Placeholders
ARTWORK_GRADIENTS = [
    ("#2E1065", "#7C3AED"),
    ("#064E3B", "#059669"),
    ("#831843", "#DB2777"),
    ("#1E3A8A", "#2563EB"),
    ("#78350F", "#D97706"),
    ("#134E4A", "#0D9488"),
]

WAVE_FRAMES = [" ▃▅█ ", " ▅█▃ ", " █▃▅ ", " ▃█▅ ", " ▅▃█ "]

class MusicCloudDesktop(ctk.CTk if hasattr(ctk, "CTk") else ctk.Tk):
    def __init__(self):
        super().__init__()

        self.title("MusicCloud")
        self.geometry("1040x720")
        self.minsize(880, 600)
        self.configure(fg_color="#08080B")

        self.audio = AudioEngine()

        # Playback State
        self.tracks: List[Dict] = []
        self.filtered_tracks: List[Dict] = []
        self.current_track: Optional[Dict] = None
        self.is_playing: bool = False
        self.is_downloading: bool = False
        self.has_playback_started: bool = False
        self.is_shuffled: bool = False
        self.repeat_mode: int = 0
        self.current_pos: float = 0.0
        self.track_duration: float = 0.0
        self.volume: float = 0.8
        self.is_auth_modal_open: bool = False
        self.wave_idx = 0
        self.active_wave_label = None

        self.setup_ui()
        self.load_tracks_async()
        self.start_timer()

    def setup_ui(self):
        self.grid_rowconfigure(1, weight=1)
        self.grid_columnconfigure(0, weight=1)

        # ------------------ TOP MODERN HEADER ------------------
        header_frame = ctk.CTkFrame(self, fg_color="#0E0E14", height=74, corner_radius=0)
        header_frame.grid(row=0, column=0, sticky="ew")
        header_frame.grid_columnconfigure(1, weight=1)

        # Left Branding
        brand_frame = ctk.CTkFrame(header_frame, fg_color="transparent")
        brand_frame.grid(row=0, column=0, padx=24, pady=16, sticky="w")

        logo_icon = ctk.CTkLabel(
            brand_frame,
            text="☁",
            font=ctk.CTkFont(size=24),
            text_color="#FFFFFF"
        )
        logo_icon.pack(side="left", padx=(0, 8))

        logo_title = ctk.CTkLabel(
            brand_frame,
            text="MusicCloud",
            font=ctk.CTkFont(family="Segoe UI", size=22, weight="bold"),
            text_color="#FFFFFF"
        )
        logo_title.pack(side="left")

        # Pill Status Badge
        self.badge_status = ctk.CTkLabel(
            brand_frame,
            text="● ОНЛАЙН",
            font=ctk.CTkFont(family="Segoe UI", size=10, weight="bold"),
            text_color="#10B981",
            fg_color="#064E3B",
            corner_radius=10,
            padx=8,
            pady=2
        )
        self.badge_status.pack(side="left", padx=12)

        # Center Search Bar
        search_box = ctk.CTkFrame(header_frame, fg_color="#181822", corner_radius=20, border_width=1, border_color="#252534")
        search_box.grid(row=0, column=1, padx=20, pady=16, sticky="ew")

        search_icon = ctk.CTkLabel(search_box, text="🔍", font=ctk.CTkFont(size=13), text_color="#71717A")
        search_icon.pack(side="left", padx=(12, 4))

        self.search_var = ctk.StringVar()
        if hasattr(self.search_var, "trace_add"):
            self.search_var.trace_add("write", lambda *args: self.on_search_changed())
        else:
            self.search_var.trace("w", lambda *args: self.on_search_changed())

        search_entry = ctk.CTkEntry(
            search_box,
            placeholder_text="Поиск треков, альбомов и артистов...",
            placeholder_text_color="#71717A",
            textvariable=self.search_var,
            border_width=0,
            fg_color="transparent",
            text_color="#FFFFFF",
            font=ctk.CTkFont(size=13),
            height=34
        )
        search_entry.pack(side="left", fill="x", expand=True, padx=4)

        # Right Action Buttons
        btn_frame = ctk.CTkFrame(header_frame, fg_color="transparent")
        btn_frame.grid(row=0, column=2, padx=24, pady=16, sticky="e")

        self.btn_auth = ctk.CTkButton(
            btn_frame,
            text="🔑 Войти",
            width=90,
            height=36,
            corner_radius=18,
            fg_color="#1F1F2C",
            hover_color="#2D2D3F",
            font=ctk.CTkFont(family="Segoe UI", size=12, weight="bold"),
            command=self.open_telegram_auth_dialog
        )
        self.btn_auth.pack(side="left", padx=5)

        refresh_btn = ctk.CTkButton(
            btn_frame,
            text="↻",
            width=36,
            height=36,
            corner_radius=18,
            fg_color="#181824",
            hover_color="#28283C",
            font=ctk.CTkFont(size=16, weight="bold"),
            command=self.load_tracks_async
        )
        refresh_btn.pack(side="left", padx=5)

        add_btn = ctk.CTkButton(
            btn_frame,
            text="＋ Добавить трек",
            width=140,
            height=36,
            corner_radius=18,
            fg_color="#FFFFFF",
            text_color="#08080B",
            hover_color="#E2E8F0",
            font=ctk.CTkFont(family="Segoe UI", size=13, weight="bold"),
            command=self.open_add_track_dialog
        )
        add_btn.pack(side="left", padx=5)

        # ------------------ CENTER TRACK LIST ------------------
        self.scroll_frame = ctk.CTkScrollableFrame(self, fg_color="transparent", corner_radius=0)
        self.scroll_frame.grid(row=1, column=0, sticky="nsew", padx=20, pady=10)
        self.scroll_frame.grid_columnconfigure(0, weight=1)

        # ------------------ BOTTOM MODERN GLASS PLAYER ------------------
        player_bar = ctk.CTkFrame(self, fg_color="#0F0F16", height=94, corner_radius=0, border_width=1, border_color="#1E1E2C")
        player_bar.grid(row=2, column=0, sticky="ew")
        player_bar.grid_columnconfigure(1, weight=1)

        # Left: Current Track Info with Artwork Thumbnail
        left_info_frame = ctk.CTkFrame(player_bar, fg_color="transparent")
        left_info_frame.grid(row=0, column=0, padx=20, pady=12, sticky="w")

        self.art_thumb = ctk.CTkLabel(
            left_info_frame,
            text="🎵",
            width=50,
            height=50,
            corner_radius=12,
            fg_color="#252536",
            font=ctk.CTkFont(size=20)
        )
        self.art_thumb.pack(side="left", padx=(0, 12))

        meta_col = ctk.CTkFrame(left_info_frame, fg_color="transparent")
        meta_col.pack(side="left")

        self.lbl_now_title = ctk.CTkLabel(
            meta_col,
            text="Выберите песню для воспроизведения",
            font=ctk.CTkFont(family="Segoe UI", size=14, weight="bold"),
            text_color="#FFFFFF",
            anchor="w",
            width=220
        )
        self.lbl_now_title.pack(anchor="w")

        self.lbl_now_artist = ctk.CTkLabel(
            meta_col,
            text="MusicCloud Cloud Player",
            font=ctk.CTkFont(family="Segoe UI", size=12),
            text_color="#94A3B8",
            anchor="w",
            width=220
        )
        self.lbl_now_artist.pack(anchor="w")

        # Center: Playback Controls & Slider
        center_frame = ctk.CTkFrame(player_bar, fg_color="transparent")
        center_frame.grid(row=0, column=1, padx=10, pady=10, sticky="ew")
        center_frame.grid_columnconfigure(0, weight=1)

        controls_row = ctk.CTkFrame(center_frame, fg_color="transparent")
        controls_row.pack()

        self.btn_shuffle = ctk.CTkButton(
            controls_row, text="⇄", width=34, height=34, corner_radius=17, fg_color="transparent",
            text_color="#64748B", hover_color="#1E1E2C", font=ctk.CTkFont(size=16, weight="bold"),
            command=self.toggle_shuffle
        )
        self.btn_shuffle.pack(side="left", padx=6)

        btn_prev = ctk.CTkButton(
            controls_row, text="⏮", width=36, height=36, corner_radius=18, fg_color="transparent",
            text_color="#F1F5F9", hover_color="#1E1E2C", font=ctk.CTkFont(size=16),
            command=self.play_previous
        )
        btn_prev.pack(side="left", padx=6)

        self.btn_play_pause = ctk.CTkButton(
            controls_row, text="▶", width=46, height=46, corner_radius=23,
            fg_color="#FFFFFF", text_color="#08080B", hover_color="#E2E8F0",
            font=ctk.CTkFont(size=18, weight="bold"), command=self.toggle_play_pause
        )
        self.btn_play_pause.pack(side="left", padx=10)

        btn_next = ctk.CTkButton(
            controls_row, text="⏭", width=36, height=36, corner_radius=18, fg_color="transparent",
            text_color="#F1F5F9", hover_color="#1E1E2C", font=ctk.CTkFont(size=16),
            command=self.play_next
        )
        btn_next.pack(side="left", padx=6)

        self.btn_repeat = ctk.CTkButton(
            controls_row, text="↻", width=34, height=34, corner_radius=17, fg_color="transparent",
            text_color="#64748B", hover_color="#1E1E2C", font=ctk.CTkFont(size=16, weight="bold"),
            command=self.toggle_repeat
        )
        self.btn_repeat.pack(side="left", padx=6)

        # Scrubber Row
        slider_row = ctk.CTkFrame(center_frame, fg_color="transparent")
        slider_row.pack(fill="x", padx=30, pady=(4, 0))

        self.lbl_time_cur = ctk.CTkLabel(slider_row, text="0:00", font=ctk.CTkFont(family="Consolas", size=11), text_color="#64748B")
        self.lbl_time_cur.pack(side="left", padx=6)

        self.slider = ctk.CTkSlider(
            slider_row,
            from_=0,
            to=100,
            number_of_steps=100,
            height=12,
            progress_color="#FFFFFF",
            button_color="#FFFFFF",
            button_hover_color="#E2E8F0",
            button_length=12,
            corner_radius=6,
            command=self.on_slider_seek
        )
        self.slider.set(0)
        self.slider.pack(side="left", fill="x", expand=True, padx=4)

        self.lbl_time_total = ctk.CTkLabel(slider_row, text="0:00", font=ctk.CTkFont(family="Consolas", size=11), text_color="#64748B")
        self.lbl_time_total.pack(side="left", padx=6)

        # Right: Volume Control
        right_frame = ctk.CTkFrame(player_bar, fg_color="transparent", width=180)
        right_frame.grid(row=0, column=2, padx=20, pady=12, sticky="e")

        vol_icon = ctk.CTkLabel(right_frame, text="🔊", text_color="#94A3B8")
        vol_icon.pack(side="left", padx=4)

        self.vol_slider = ctk.CTkSlider(
            right_frame, from_=0, to=1, width=100, height=10,
            progress_color="#FFFFFF", button_color="#FFFFFF",
            button_length=10, corner_radius=5,
            command=self.on_volume_changed
        )
        self.vol_slider.set(self.volume)
        self.vol_slider.pack(side="left", padx=4)

    # ------------------ DATA FETCHING ------------------
    def load_tracks_async(self):
        threading.Thread(target=self._fetch_tracks, daemon=True).start()

    def _fetch_tracks(self):
        try:
            req = urllib.request.Request(f"{SERVER_URL}/tracks", headers={"User-Agent": "MusicCloudDesktop/1.0"})
            with urllib.request.urlopen(req, timeout=8.0) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    self.tracks = data.get("tracks", [])
                    self.after(0, self._on_tracks_loaded)
        except urllib.error.HTTPError as e:
            if e.code == 401:
                print("[!] Server requires Telegram authentication (401)")
                self.after(0, self.open_telegram_auth_dialog)
            else:
                print(f"[!] HTTP Error fetching tracks: {e}")
        except Exception as e:
            print(f"[!] Error fetching tracks: {e}")

    def _on_tracks_loaded(self):
        self.btn_auth.configure(text="● Подключено", fg_color="#064E3B", text_color="#10B981")
        self.update_track_list_ui()

    def update_track_list_ui(self):
        for widget in self.scroll_frame.winfo_children():
            widget.destroy()

        search_query = self.search_var.get().lower()
        self.filtered_tracks = [
            t for t in self.tracks
            if search_query in t.get("title", "").lower() or search_query in t.get("performer", "").lower()
        ]

        if not self.filtered_tracks:
            empty_lbl = ctk.CTkLabel(
                self.scroll_frame,
                text="🎵 Музыка не найдена\nНажмите '＋ Добавить трек' вверху",
                font=ctk.CTkFont(family="Segoe UI", size=16, weight="bold"),
                text_color="#475569",
                pady=100
            )
            empty_lbl.pack()
            return

        for idx, track in enumerate(self.filtered_tracks):
            is_active = self.current_track and self.current_track.get("id") == track.get("id")
            
            card = ctk.CTkFrame(
                self.scroll_frame,
                fg_color="#181824" if is_active else "#0F0F16",
                corner_radius=14,
                border_width=1,
                border_color="#3B82F6" if is_active else "#1A1A26",
                height=62
            )
            card.pack(fill="x", padx=4, pady=4)
            card.grid_columnconfigure(2, weight=1)

            # Track number or Animated Soundwave
            if is_active and self.is_playing:
                wave_lbl = ctk.CTkLabel(
                    card,
                    text=WAVE_FRAMES[self.wave_idx % len(WAVE_FRAMES)],
                    font=ctk.CTkFont(family="Consolas", size=14, weight="bold"),
                    text_color="#60A5FA",
                    width=40
                )
                wave_lbl.grid(row=0, column=0, padx=(12, 4), pady=12)
                self.active_wave_label = wave_lbl
            else:
                num_lbl = ctk.CTkLabel(
                    card,
                    text=f"{idx+1:02d}",
                    font=ctk.CTkFont(family="Consolas", size=12, weight="bold"),
                    text_color="#475569" if not is_active else "#93C5FD",
                    width=40
                )
                num_lbl.grid(row=0, column=0, padx=(12, 4), pady=12)

            # Play / Pause Round Button
            btn_play = ctk.CTkButton(
                card,
                text="⏸" if (is_active and self.is_playing) else "▶",
                width=38,
                height=38,
                corner_radius=19,
                fg_color="#2563EB" if is_active else "#1E1E2C",
                text_color="#FFFFFF",
                hover_color="#3B82F6" if is_active else "#2D2D42",
                font=ctk.CTkFont(size=14, weight="bold"),
                command=lambda t=track: self.play_track(t)
            )
            btn_play.grid(row=0, column=1, padx=(4, 12), pady=12)

            # Track Title & Performer
            info_frame = ctk.CTkFrame(card, fg_color="transparent")
            info_frame.grid(row=0, column=2, sticky="w", padx=4)

            lbl_t = ctk.CTkLabel(
                info_frame,
                text=track.get("title", "Без названия"),
                font=ctk.CTkFont(family="Segoe UI", size=14, weight="bold"),
                text_color="#FFFFFF" if is_active else "#F1F5F9",
                anchor="w"
            )
            lbl_t.pack(anchor="w")

            lbl_a = ctk.CTkLabel(
                info_frame,
                text=track.get("performer", "Неизвестный исполнитель"),
                font=ctk.CTkFont(family="Segoe UI", size=12),
                text_color="#94A3B8" if is_active else "#64748B",
                anchor="w"
            )
            lbl_a.pack(anchor="w")

            # Duration badge
            dur_sec = int(track.get("duration", 0))
            dur_str = f"{dur_sec//60:02d}:{dur_sec%60:02d}"
            lbl_d = ctk.CTkLabel(
                card,
                text=dur_str,
                font=ctk.CTkFont(family="Consolas", size=12),
                text_color="#64748B"
            )
            lbl_d.grid(row=0, column=3, padx=18, pady=12)

    # ------------------ TELEGRAM AUTH DIALOG ------------------
    def open_telegram_auth_dialog(self):
        if self.is_auth_modal_open:
            return
        self.is_auth_modal_open = True

        modal = ctk.CTkToplevel(self)
        modal.title("Вход в Telegram")
        modal.geometry("420x420")
        modal.configure(fg_color="#0F0F16")
        modal.grab_set()

        def on_close():
            self.is_auth_modal_open = False
            modal.destroy()

        modal.protocol("WM_DELETE_WINDOW", on_close)

        lbl_h = ctk.CTkLabel(modal, text="🔑 Вход в Telegram", font=ctk.CTkFont(family="Segoe UI", size=20, weight="bold"), text_color="#FFFFFF")
        lbl_h.pack(pady=(24, 8))

        lbl_desc = ctk.CTkLabel(modal, text="Введите номер телефона для получения кода в Telegram", font=ctk.CTkFont(size=12), text_color="#94A3B8")
        lbl_desc.pack(pady=(0, 16))

        entry_phone = ctk.CTkEntry(modal, placeholder_text="+380... или +7...", width=320, height=42, fg_color="#181824", border_color="#252534")
        entry_phone.pack(pady=6)

        lbl_status = ctk.CTkLabel(modal, text="", font=ctk.CTkFont(size=12), text_color="#F59E0B", wraplength=340)
        lbl_status.pack(pady=4)

        entry_code = ctk.CTkEntry(modal, placeholder_text="Код из чата Telegram", width=320, height=42, fg_color="#181824", border_color="#252534")
        entry_2fa = ctk.CTkEntry(modal, placeholder_text="Пароль 2FA", show="*", width=320, height=42, fg_color="#181824", border_color="#252534")

        def send_phone():
            phone = entry_phone.get().strip()
            if not phone:
                lbl_status.configure(text="Введите номер телефона!", text_color="#EF4444")
                return
            lbl_status.configure(text="Отправка запроса в Telegram...", text_color="#F59E0B")
            
            def _req():
                try:
                    data = json.dumps({"phone": phone}).encode("utf-8")
                    req = urllib.request.Request(f"{SERVER_URL}/auth/send-code", data=data, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=20.0) as resp:
                        if resp.status == 200:
                            modal.after(0, _step_code)
                except urllib.error.HTTPError as he:
                    err_msg = str(he)
                    try:
                        err_json = json.loads(he.read().decode("utf-8"))
                        err_msg = err_json.get("detail", str(he))
                    except Exception:
                        pass
                    modal.after(0, lambda msg=err_msg: lbl_status.configure(text=f"Ошибка: {msg}", text_color="#EF4444"))
                except Exception as e:
                    err_msg = str(e)
                    modal.after(0, lambda msg=err_msg: lbl_status.configure(text=f"Ошибка: {msg}", text_color="#EF4444"))

            threading.Thread(target=_req, daemon=True).start()

        def _step_code():
            lbl_status.configure(text="Код отправлен в ваш Telegram!", text_color="#10B981")
            btn_action.configure(text="Войти с кодом", command=send_code)
            entry_code.pack(pady=6)

        def send_code():
            phone = entry_phone.get().strip()
            code = entry_code.get().strip()
            if not code:
                lbl_status.configure(text="Введите код подтверждения!", text_color="#EF4444")
                return
            lbl_status.configure(text="Проверка кода...", text_color="#F59E0B")

            def _req():
                try:
                    data = json.dumps({"phone": phone, "code": code}).encode("utf-8")
                    req = urllib.request.Request(f"{SERVER_URL}/auth/sign-in", data=data, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=20.0) as resp:
                        res = json.loads(resp.read().decode("utf-8"))
                        if res.get("status") == "authenticated":
                            modal.after(0, _success)
                        elif res.get("status") == "2fa_required":
                            modal.after(0, _step_2fa)
                except urllib.error.HTTPError as he:
                    err_msg = str(he)
                    try:
                        err_json = json.loads(he.read().decode("utf-8"))
                        err_msg = err_json.get("detail", str(he))
                    except Exception:
                        pass
                    modal.after(0, lambda msg=err_msg: lbl_status.configure(text=f"Ошибка: {msg}", text_color="#EF4444"))
                except Exception as e:
                    err_msg = str(e)
                    modal.after(0, lambda msg=err_msg: lbl_status.configure(text=f"Ошибка: {msg}", text_color="#EF4444"))

            threading.Thread(target=_req, daemon=True).start()

        def _step_2fa():
            lbl_status.configure(text="Требуется облачный пароль (2FA)", text_color="#F59E0B")
            entry_2fa.pack(pady=6)
            btn_action.configure(text="Подтвердить 2FA", command=send_2fa)

        def send_2fa():
            pwd = entry_2fa.get()
            def _req():
                try:
                    data = json.dumps({"password": pwd}).encode("utf-8")
                    req = urllib.request.Request(f"{SERVER_URL}/auth/2fa", data=data, headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=20.0) as resp:
                        res = json.loads(resp.read().decode("utf-8"))
                        if res.get("status") == "authenticated":
                            modal.after(0, _success)
                except urllib.error.HTTPError as he:
                    err_msg = str(he)
                    try:
                        err_json = json.loads(he.read().decode("utf-8"))
                        err_msg = err_json.get("detail", str(he))
                    except Exception:
                        pass
                    modal.after(0, lambda msg=err_msg: lbl_status.configure(text=f"Ошибка 2FA: {msg}", text_color="#EF4444"))
                except Exception as e:
                    err_msg = str(e)
                    modal.after(0, lambda msg=err_msg: lbl_status.configure(text=f"Ошибка 2FA: {msg}", text_color="#EF4444"))
            threading.Thread(target=_req, daemon=True).start()

        def _success():
            lbl_status.configure(text="Успешный вход!", text_color="#10B981")
            modal.after(1000, lambda: [on_close(), self.load_tracks_async()])

        btn_action = ctk.CTkButton(
            modal, text="Получить код", width=320, height=44, fg_color="#FFFFFF",
            text_color="#08080B", hover_color="#E2E8F0", font=ctk.CTkFont(size=14, weight="bold"),
            command=send_phone
        )
        btn_action.pack(pady=(18, 10))

    # ------------------ PLAYBACK LOGIC ------------------
    def play_track(self, track: Dict):
        if self.current_track and self.current_track.get("id") == track.get("id") and self.has_playback_started:
            self.toggle_play_pause()
            return

        self.current_track = track
        self.is_downloading = True
        self.has_playback_started = False
        self.current_pos = 0.0
        self.track_duration = float(track.get("duration", 0))

        title = track.get("title", "Без названия")
        self.lbl_now_title.configure(text=f"⏳ Загрузка: {title}...")
        self.lbl_now_artist.configure(text=track.get("performer", "MusicCloud"))
        self.btn_play_pause.configure(text="⏳")
        self.update_track_list_ui()

        threading.Thread(target=self._download_and_play, args=(track,), daemon=True).start()

    def _download_and_play(self, track: Dict):
        track_id = track.get("id", "0")
        msg_id = track.get("message_id", 0)
        local_path = os.path.join(CACHE_DIR, f"{track_id}.mp3")

        if not os.path.exists(local_path) or os.path.getsize(local_path) < 1024:
            audio_url = f"{SERVER_URL}/tracks/{msg_id}/audio"
            try:
                temp_download_file = local_path + ".tmp"
                req = urllib.request.Request(audio_url, headers={"User-Agent": "MusicCloudDesktop/1.0"})
                with urllib.request.urlopen(req, timeout=25.0) as resp:
                    with open(temp_download_file, "wb") as f:
                        f.write(resp.read())
                if os.path.exists(local_path):
                    try:
                        os.remove(local_path)
                    except Exception:
                        pass
                os.rename(temp_download_file, local_path)
            except Exception as e:
                print(f"[!] Error downloading track: {e}")
                self.after(0, lambda: self._on_play_failed(track, str(e)))
                return

        try:
            self.audio.load_and_play(local_path)
            self.is_playing = True
            self.is_downloading = False
            self.has_playback_started = True
            self.current_pos = 0.0
            self.after(0, lambda: self._on_play_started(track))
        except Exception as e:
            print(f"[!] Audio play error: {e}")
            self.after(0, lambda: self._on_play_failed(track, str(e)))

    def _on_play_started(self, track: Dict):
        self.lbl_now_title.configure(text=track.get("title", "Без названия"))
        self.lbl_now_artist.configure(text=track.get("performer", "MusicCloud"))
        self.btn_play_pause.configure(text="⏸")
        self.update_track_list_ui()

    def _on_play_failed(self, track: Dict, error: str):
        self.is_playing = False
        self.is_downloading = False
        self.has_playback_started = False
        self.lbl_now_title.configure(text=f"❌ {track.get('title', '')}")
        self.lbl_now_artist.configure(text="Ошибка загрузки трека")
        self.btn_play_pause.configure(text="▶")
        self.update_track_list_ui()

    def toggle_play_pause(self):
        if not self.current_track:
            if self.filtered_tracks:
                self.play_track(self.filtered_tracks[0])
            return

        if self.is_playing:
            self.audio.pause()
            self.is_playing = False
            self.btn_play_pause.configure(text="▶")
        else:
            self.audio.unpause()
            self.is_playing = True
            self.btn_play_pause.configure(text="⏸")
        self.update_track_list_ui()

    def play_next(self):
        if not self.filtered_tracks or not self.current_track or self.is_downloading:
            return
        idx = next((i for i, t in enumerate(self.filtered_tracks) if t["id"] == self.current_track["id"]), 0)
        next_idx = (idx + 1) % len(self.filtered_tracks)
        self.play_track(self.filtered_tracks[next_idx])

    def play_previous(self):
        if not self.filtered_tracks or not self.current_track or self.is_downloading:
            return
        idx = next((i for i, t in enumerate(self.filtered_tracks) if t["id"] == self.current_track["id"]), 0)
        prev_idx = (idx - 1 + len(self.filtered_tracks)) % len(self.filtered_tracks)
        self.play_track(self.filtered_tracks[prev_idx])

    def toggle_shuffle(self):
        self.is_shuffled = not self.is_shuffled
        self.btn_shuffle.configure(text_color="#38BDF8" if self.is_shuffled else "#64748B")

    def toggle_repeat(self):
        self.repeat_mode = (self.repeat_mode + 1) % 3
        colors = ["#64748B", "#38BDF8", "#F43F5E"]
        icons = ["↻", "↻", "🔂"]
        self.btn_repeat.configure(text=icons[self.repeat_mode], text_color=colors[self.repeat_mode])

    def on_slider_seek(self, val):
        pass

    def on_volume_changed(self, val):
        self.volume = float(val)
        self.audio.set_volume(self.volume)

    def on_search_changed(self, *args):
        self.update_track_list_ui()

    def start_timer(self):
        if self.is_playing and self.has_playback_started and not self.is_downloading:
            self.current_pos += 0.5
            self.wave_idx += 1
            if self.active_wave_label:
                try:
                    self.active_wave_label.configure(text=WAVE_FRAMES[self.wave_idx % len(WAVE_FRAMES)])
                except Exception:
                    pass

            if self.track_duration > 0:
                progress = min(100.0, (self.current_pos / self.track_duration) * 100.0)
                self.slider.set(progress)
                cur_m = int(self.current_pos) // 60
                cur_s = int(self.current_pos) % 60
                tot_m = int(self.track_duration) // 60
                tot_s = int(self.track_duration) % 60
                self.lbl_time_cur.configure(text=f"{cur_m}:{cur_s:02d}")
                self.lbl_time_total.configure(text=f"{tot_m}:{tot_s:02d}")

            if not self.audio.is_busy() and self.track_duration > 0 and self.current_pos >= max(1.0, self.track_duration - 1.5):
                if self.repeat_mode == 2:
                    self.play_track(self.current_track)
                else:
                    self.play_next()

        self.after(500, self.start_timer)

    # ------------------ ADD TRACK MODAL ------------------
    def open_add_track_dialog(self):
        from tkinter import filedialog
        file_path = filedialog.askopenfilename(
            title="Выберите аудиотрек",
            filetypes=[("Audio Files", "*.mp3 *.m4a *.wav *.flac *.aac")]
        )
        if not file_path:
            return

        modal = ctk.CTkToplevel(self)
        modal.title("Добавить трек в MusicCloud")
        modal.geometry("460x380")
        modal.configure(fg_color="#0F0F16")
        modal.grab_set()

        default_title = os.path.splitext(os.path.basename(file_path))[0]
        
        lbl_h = ctk.CTkLabel(modal, text="＋ Добавление трека", font=ctk.CTkFont(family="Segoe UI", size=20, weight="bold"), text_color="#FFFFFF")
        lbl_h.pack(pady=(24, 12))

        lbl_t = ctk.CTkLabel(modal, text="Название трека:", text_color="#94A3B8", anchor="w")
        lbl_t.pack(fill="x", padx=32, pady=(6, 2))
        entry_title = ctk.CTkEntry(modal, fg_color="#181824", border_color="#252534", text_color="#FFFFFF", height=38)
        entry_title.insert(0, default_title)
        entry_title.pack(fill="x", padx=32)

        lbl_a = ctk.CTkLabel(modal, text="Исполнитель:", text_color="#94A3B8", anchor="w")
        lbl_a.pack(fill="x", padx=32, pady=(10, 2))
        entry_artist = ctk.CTkEntry(modal, fg_color="#181824", border_color="#252534", text_color="#FFFFFF", height=38)
        entry_artist.insert(0, "Неизвестный исполнитель")
        entry_artist.pack(fill="x", padx=32)

        def do_upload():
            t_name = entry_title.get().strip() or default_title
            p_name = entry_artist.get().strip() or "Неизвестный исполнитель"
            modal.destroy()
            threading.Thread(target=self._upload_file, args=(file_path, t_name, p_name), daemon=True).start()

        btn_send = ctk.CTkButton(
            modal, text="Загрузить в чат Telegram", fg_color="#FFFFFF", text_color="#08080B",
            hover_color="#E2E8F0", height=44, font=ctk.CTkFont(size=14, weight="bold"),
            corner_radius=22, command=do_upload
        )
        btn_send.pack(fill="x", padx=32, pady=(28, 10))

    def _upload_file(self, file_path: str, title: str, performer: str):
        try:
            boundary = "----WebKitFormBoundaryMusicCloud"
            body = bytearray()
            
            with open(file_path, "rb") as f:
                file_bytes = f.read()

            body.extend(f"--{boundary}\r\n".encode("utf-8"))
            body.extend(f'Content-Disposition: form-data; name="file"; filename="{os.path.basename(file_path)}"\r\n'.encode("utf-8"))
            body.extend(b"Content-Type: audio/mpeg\r\n\r\n")
            body.extend(file_bytes)
            body.extend(b"\r\n")

            body.extend(f"--{boundary}\r\n".encode("utf-8"))
            body.extend(b'Content-Disposition: form-data; name="title"\r\n\r\n')
            body.extend(title.encode("utf-8"))
            body.extend(b"\r\n")

            body.extend(f"--{boundary}\r\n".encode("utf-8"))
            body.extend(b'Content-Disposition: form-data; name="performer"\r\n\r\n')
            body.extend(performer.encode("utf-8"))
            body.extend(b"\r\n")
            body.extend(f"--{boundary}--\r\n".encode("utf-8"))

            req = urllib.request.Request(
                f"{SERVER_URL}/tracks/upload",
                data=bytes(body),
                headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
            )
            with urllib.request.urlopen(req, timeout=30.0) as resp:
                if resp.status == 200:
                    print("[OK] Uploaded track successfully!")
                    self.load_tracks_async()
        except Exception as e:
            print(f"[!] Upload error: {e}")

if __name__ == "__main__":
    app = MusicCloudDesktop()
    app.mainloop()
