import os
import sys
import io
import time
import json
import threading
import urllib.request
import urllib.parse
from typing import List, Optional, Dict

try:
    import customtkinter as ctk
    from PIL import Image, ImageTk
except ImportError:
    import tkinter as ctk
    from PIL import Image, ImageTk

try:
    import pygame
    pygame.mixer.init()
except Exception as e:
    print(f"[Warning] Pygame mixer init error: {e}")

SERVER_URL = os.getenv("MUSICCLOUD_SERVER", "http://199.83.103.63:8900")
CACHE_DIR = os.path.join(os.path.expanduser("~"), ".musiccloud", "cache")
os.makedirs(CACHE_DIR, exist_ok=True)

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

class MusicCloudDesktop(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("MusicCloud Desktop")
        self.geometry("980x680")
        self.minsize(840, 560)
        self.configure(fg_color="#0A0A0C")

        # Playback State
        self.tracks: List[Dict] = []
        self.filtered_tracks: List[Dict] = []
        self.current_track: Optional[Dict] = None
        self.is_playing: Bool = False
        self.is_shuffled: Bool = False
        self.repeat_mode: int = 0  # 0: off, 1: all, 2: one
        self.current_pos: float = 0.0
        self.track_duration: float = 0.0
        self.is_seeking: bool = False
        self.volume: float = 0.8

        self.setup_ui()
        self.load_tracks_async()
        self.start_timer()

    def setup_ui(self):
        self.grid_rowconfigure(1, weight=1)
        self.grid_columnconfigure(0, weight=1)

        # ------------------ TOP HEADER ------------------
        header_frame = ctk.CTkFrame(self, fg_color="#121216", height=68, corner_radius=0)
        header_frame.grid(row=0, column=0, sticky="ew")
        header_frame.grid_columnconfigure(1, weight=1)

        logo_label = ctk.CTkLabel(
            header_frame,
            text="☁️ MusicCloud",
            font=ctk.CTkFont(family="Segoe UI", size=22, weight="bold"),
            text_color="#FFFFFF"
        )
        logo_label.grid(row=0, column=0, padx=20, pady=16, sticky="w")

        # Search field
        self.search_var = ctk.StringVar()
        self.search_var.trace("w", self.on_search_changed)
        search_entry = ctk.CTkEntry(
            header_frame,
            placeholder_text="Поиск по песням и артистам...",
            textvariable=self.search_var,
            width=320,
            height=36,
            corner_radius=18,
            fg_color="#1A1A22",
            border_color="#2A2A35",
            text_color="#FFFFFF"
        )
        search_entry.grid(row=0, column=1, padx=10, pady=16, sticky="w")

        # Buttons on the right
        btn_frame = ctk.CTkFrame(header_frame, fg_color="transparent")
        btn_frame.grid(row=0, column=2, padx=20, pady=16, sticky="e")

        refresh_btn = ctk.CTkButton(
            btn_frame,
            text="🔄",
            width=38,
            height=36,
            corner_radius=18,
            fg_color="#1F1F28",
            hover_color="#2A2A38",
            command=self.load_tracks_async
        )
        refresh_btn.pack(side="left", padx=4)

        add_btn = ctk.CTkButton(
            btn_frame,
            text="+ Добавить трек",
            width=130,
            height=36,
            corner_radius=18,
            fg_color="#FFFFFF",
            text_color="#000000",
            hover_color="#E0E0E0",
            font=ctk.CTkFont(family="Segoe UI", size=13, weight="bold"),
            command=self.open_add_track_dialog
        )
        add_btn.pack(side="left", padx=4)

        # ------------------ CENTER TRACK LIST ------------------
        self.scroll_frame = ctk.CTkScrollableFrame(self, fg_color="transparent", corner_radius=0)
        self.scroll_frame.grid(row=1, column=0, sticky="nsew", padx=16, pady=8)
        self.scroll_frame.grid_columnconfigure(0, weight=1)

        # ------------------ BOTTOM PLAYER BAR ------------------
        player_bar = ctk.CTkFrame(self, fg_color="#14141A", height=88, corner_radius=0)
        player_bar.grid(row=2, column=0, sticky="ew")
        player_bar.grid_columnconfigure(1, weight=1)

        # Left: Current Track Info
        left_info_frame = ctk.CTkFrame(player_bar, fg_color="transparent", width=220)
        left_info_frame.grid(row=0, column=0, padx=16, pady=12, sticky="w")

        self.lbl_now_title = ctk.CTkLabel(
            left_info_frame,
            text="Выберите песню",
            font=ctk.CTkFont(family="Segoe UI", size=14, weight="bold"),
            text_color="#FFFFFF",
            anchor="w",
            width=200
        )
        self.lbl_now_title.pack(anchor="w")

        self.lbl_now_artist = ctk.CTkLabel(
            left_info_frame,
            text="MusicCloud",
            font=ctk.CTkFont(family="Segoe UI", size=12),
            text_color="#8E8E9A",
            anchor="w",
            width=200
        )
        self.lbl_now_artist.pack(anchor="w")

        # Center: Playback Controls & Slider
        center_frame = ctk.CTkFrame(player_bar, fg_color="transparent")
        center_frame.grid(row=0, column=1, padx=10, pady=8, sticky="ew")
        center_frame.grid_columnconfigure(0, weight=1)

        controls_row = ctk.CTkFrame(center_frame, fg_color="transparent")
        controls_row.pack()

        self.btn_shuffle = ctk.CTkButton(
            controls_row, text="🔀", width=32, height=32, fg_color="transparent",
            text_color="#8E8E9A", hover_color="#22222E", command=self.toggle_shuffle
        )
        self.btn_shuffle.pack(side="left", padx=6)

        btn_prev = ctk.CTkButton(
            controls_row, text="⏮", width=36, height=32, fg_color="transparent",
            text_color="#FFFFFF", hover_color="#22222E", font=ctk.CTkFont(size=16),
            command=self.play_previous
        )
        btn_prev.pack(side="left", padx=6)

        self.btn_play_pause = ctk.CTkButton(
            controls_row, text="▶", width=44, height=44, corner_radius=22,
            fg_color="#FFFFFF", text_color="#000000", hover_color="#E0E0E0",
            font=ctk.CTkFont(size=18, weight="bold"), command=self.toggle_play_pause
        )
        self.btn_play_pause.pack(side="left", padx=8)

        btn_next = ctk.CTkButton(
            controls_row, text="⏭", width=36, height=32, fg_color="transparent",
            text_color="#FFFFFF", hover_color="#22222E", font=ctk.CTkFont(size=16),
            command=self.play_next
        )
        btn_next.pack(side="left", padx=6)

        self.btn_repeat = ctk.CTkButton(
            controls_row, text="🔁", width=32, height=32, fg_color="transparent",
            text_color="#8E8E9A", hover_color="#22222E", command=self.toggle_repeat
        )
        self.btn_repeat.pack(side="left", padx=6)

        # Scrubber Row
        slider_row = ctk.CTkFrame(center_frame, fg_color="transparent")
        slider_row.pack(fill="x", padx=40, pady=(2, 0))

        self.lbl_time_cur = ctk.CTkLabel(slider_row, text="0:00", font=ctk.CTkFont(family="Consolas", size=11), text_color="#7A7A88")
        self.lbl_time_cur.pack(side="left", padx=4)

        self.slider = ctk.CTkSlider(
            slider_row,
            from_=0,
            to=100,
            number_of_steps=100,
            height=14,
            progress_color="#FFFFFF",
            button_color="#FFFFFF",
            button_hover_color="#DDDDDD",
            command=self.on_slider_seek
        )
        self.slider.set(0)
        self.slider.pack(side="left", fill="x", expand=True, padx=8)

        self.lbl_time_total = ctk.CTkLabel(slider_row, text="0:00", font=ctk.CTkFont(family="Consolas", size=11), text_color="#7A7A88")
        self.lbl_time_total.pack(side="left", padx=4)

        # Right: Volume Control
        right_frame = ctk.CTkFrame(player_bar, fg_color="transparent", width=160)
        right_frame.grid(row=0, column=2, padx=16, pady=12, sticky="e")

        vol_icon = ctk.CTkLabel(right_frame, text="🔊", text_color="#8E8E9A")
        vol_icon.pack(side="left", padx=4)

        self.vol_slider = ctk.CTkSlider(
            right_frame, from_=0, to=1, width=100, height=12,
            progress_color="#FFFFFF", button_color="#FFFFFF",
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
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    self.tracks = data.get("tracks", [])
                    self.after(0, self.update_track_list_ui)
        except Exception as e:
            print(f"[!] Error fetching tracks: {e}")

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
                text="Нет треков в MusicCloud\nНажмите '+ Добавить трек' вверху",
                font=ctk.CTkFont(size=16),
                text_color="#666677",
                pady=80
            )
            empty_lbl.pack()
            return

        for idx, track in enumerate(self.filtered_tracks):
            is_active = self.current_track and self.current_track.get("id") == track.get("id")
            card = ctk.CTkFrame(
                self.scroll_frame,
                fg_color="#181822" if is_active else "#101016",
                corner_radius=12,
                height=56
            )
            card.pack(fill="x", padx=4, pady=3)
            card.grid_columnconfigure(1, weight=1)

            # Play button
            btn_play = ctk.CTkButton(
                card,
                text="⏸" if (is_active and self.is_playing) else "▶",
                width=36,
                height=36,
                corner_radius=18,
                fg_color="#2A2A38" if is_active else "#1C1C26",
                text_color="#FFFFFF",
                hover_color="#363648",
                command=lambda t=track: self.play_track(t)
            )
            btn_play.grid(row=0, column=0, padx=12, pady=10)

            # Title & Artist
            info_frame = ctk.CTkFrame(card, fg_color="transparent")
            info_frame.grid(row=0, column=1, sticky="w", padx=6)

            lbl_t = ctk.CTkLabel(
                info_frame,
                text=track.get("title", "Без названия"),
                font=ctk.CTkFont(family="Segoe UI", size=14, weight="bold" if is_active else "normal"),
                text_color="#FFFFFF",
                anchor="w"
            )
            lbl_t.pack(anchor="w")

            lbl_a = ctk.CTkLabel(
                info_frame,
                text=track.get("performer", "Неизвестный"),
                font=ctk.CTkFont(family="Segoe UI", size=12),
                text_color="#7A7A8A",
                anchor="w"
            )
            lbl_a.pack(anchor="w")

            # Duration
            dur_sec = int(track.get("duration", 0))
            dur_str = f"{dur_sec//60:02d}:{dur_sec%60:02d}"
            lbl_d = ctk.CTkLabel(
                card,
                text=dur_str,
                font=ctk.CTkFont(family="Consolas", size=12),
                text_color="#606070"
            )
            lbl_d.grid(row=0, column=2, padx=16, pady=10)

    # ------------------ PLAYBACK LOGIC ------------------
    def play_track(self, track: Dict):
        if self.current_track and self.current_track.get("id") == track.get("id"):
            self.toggle_play_pause()
            return

        self.current_track = track
        self.lbl_now_title.configure(text=track.get("title", "Без названия"))
        self.lbl_now_artist.configure(text=track.get("performer", "MusicCloud"))
        self.track_duration = float(track.get("duration", 0))

        threading.Thread(target=self._download_and_play, args=(track,), daemon=True).start()

    def _download_and_play(self, track: Dict):
        track_id = track.get("id", "0")
        msg_id = track.get("message_id", 0)
        local_path = os.path.join(CACHE_DIR, f"{track_id}.mp3")

        if not os.path.exists(local_path):
            audio_url = f"{SERVER_URL}/tracks/{msg_id}/audio"
            try:
                urllib.request.urlretrieve(audio_url, local_path)
            except Exception as e:
                print(f"[!] Error downloading track: {e}")
                return

        try:
            pygame.mixer.music.load(local_path)
            pygame.mixer.music.set_volume(self.volume)
            pygame.mixer.music.play()
            self.is_playing = True
            self.current_pos = 0.0
            self.after(0, self._on_play_started)
        except Exception as e:
            print(f"[!] Audio play error: {e}")

    def _on_play_started(self):
        self.btn_play_pause.configure(text="⏸")
        self.update_track_list_ui()

    def toggle_play_pause(self):
        if not self.current_track:
            if self.filtered_tracks:
                self.play_track(self.filtered_tracks[0])
            return

        if self.is_playing:
            pygame.mixer.music.pause()
            self.is_playing = False
            self.btn_play_pause.configure(text="▶")
        else:
            pygame.mixer.music.unpause()
            self.is_playing = True
            self.btn_play_pause.configure(text="⏸")
        self.update_track_list_ui()

    def play_next(self):
        if not self.filtered_tracks or not self.current_track:
            return
        idx = next((i for i, t in enumerate(self.filtered_tracks) if t["id"] == self.current_track["id"]), 0)
        next_idx = (idx + 1) % len(self.filtered_tracks)
        self.play_track(self.filtered_tracks[next_idx])

    def play_previous(self):
        if not self.filtered_tracks or not self.current_track:
            return
        idx = next((i for i, t in enumerate(self.filtered_tracks) if t["id"] == self.current_track["id"]), 0)
        prev_idx = (idx - 1 + len(self.filtered_tracks)) % len(self.filtered_tracks)
        self.play_track(self.filtered_tracks[prev_idx])

    def toggle_shuffle(self):
        self.is_shuffled = not self.is_shuffled
        self.btn_shuffle.configure(text_color="#FFFFFF" if self.is_shuffled else "#8E8E9A")

    def toggle_repeat(self):
        self.repeat_mode = (self.repeat_mode + 1) % 3
        colors = ["#8E8E9A", "#FFFFFF", "#33AAFF"]
        icons = ["🔁", "🔁", "🔂"]
        self.btn_repeat.configure(text=icons[self.repeat_mode], text_color=colors[self.repeat_mode])

    def on_slider_seek(self, val):
        pass

    def on_volume_changed(self, val):
        self.volume = float(val)
        pygame.mixer.music.set_volume(self.volume)

    def on_search_changed(self, *args):
        self.update_track_list_ui()

    def start_timer(self):
        if self.is_playing:
            self.current_pos += 0.5
            if self.track_duration > 0:
                progress = min(100.0, (self.current_pos / self.track_duration) * 100.0)
                self.slider.set(progress)
                cur_m = int(self.current_pos) // 60
                cur_s = int(self.current_pos) % 60
                tot_m = int(self.track_duration) // 60
                tot_s = int(self.track_duration) % 60
                self.lbl_time_cur.configure(text=f"{cur_m}:{cur_s:02d}")
                self.lbl_time_total.configure(text=f"{tot_m}:{tot_s:02d}")

            if not pygame.mixer.music.get_busy() and self.is_playing and self.current_pos > 2:
                if self.repeat_mode == 2:  # Repeat One
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
        modal.geometry("440x360")
        modal.configure(fg_color="#121218")
        modal.grab_set()

        default_title = os.path.splitext(os.path.basename(file_path))[0]
        
        lbl_h = ctk.CTkLabel(modal, text="Редактирование трека", font=ctk.CTkFont(size=18, weight="bold"), text_color="#FFFFFF")
        lbl_h.pack(pady=(20, 10))

        lbl_t = ctk.CTkLabel(modal, text="Название трека:", text_color="#8E8E9A", anchor="w")
        lbl_t.pack(fill="x", padx=30, pady=(6, 2))
        entry_title = ctk.CTkEntry(modal, fg_color="#1C1C26", border_color="#2A2A38", text_color="#FFFFFF")
        entry_title.insert(0, default_title)
        entry_title.pack(fill="x", padx=30)

        lbl_a = ctk.CTkLabel(modal, text="Исполнитель:", text_color="#8E8E9A", anchor="w")
        lbl_a.pack(fill="x", padx=30, pady=(10, 2))
        entry_artist = ctk.CTkEntry(modal, fg_color="#1C1C26", border_color="#2A2A38", text_color="#FFFFFF")
        entry_artist.insert(0, "Неизвестный исполнитель")
        entry_artist.pack(fill="x", padx=30)

        def do_upload():
            t_name = entry_title.get().strip() or default_title
            p_name = entry_artist.get().strip() or "Неизвестный исполнитель"
            modal.destroy()
            threading.Thread(target=self._upload_file, args=(file_path, t_name, p_name), daemon=True).start()

        btn_send = ctk.CTkButton(
            modal, text="Отправить в MusicCloud", fg_color="#FFFFFF", text_color="#000000",
            hover_color="#E0E0E0", height=42, font=ctk.CTkFont(size=14, weight="bold"),
            command=do_upload
        )
        btn_send.pack(fill="x", padx=30, pady=(24, 10))

    def _upload_file(self, file_path: str, title: str, performer: str):
        try:
            import urllib.request
            # Multipart upload
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
