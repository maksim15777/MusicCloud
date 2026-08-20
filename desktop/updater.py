import os
import sys
import time
import json
import hashlib
import subprocess
import urllib.request
import urllib.error

SERVER_URL = os.getenv("MUSICCLOUD_SERVER", "http://199.83.103.63:8900")
LOCAL_DIR = os.path.dirname(os.path.abspath(__file__))
PLAYER_FILE = os.path.join(LOCAL_DIR, "desktop_player.py")
VERSION_FILE = os.path.join(LOCAL_DIR, "version.json")

def get_file_hash(filepath: str) -> str:
    if not os.path.exists(filepath):
        return ""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def get_local_version() -> str:
    if os.path.exists(VERSION_FILE):
        try:
            with open(VERSION_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("version", "0.0.0")
        except Exception:
            pass
    return "0.0.0"

def save_local_version(version: str, file_hash: str):
    try:
        with open(VERSION_FILE, "w", encoding="utf-8") as f:
            json.dump({"version": version, "hash": file_hash, "updated_at": time.time()}, f, indent=2)
    except Exception as e:
        print(f"[Updater] Error saving version file: {e}")

def check_and_update():
    print("==================================================")
    print("       MusicCloud Desktop Smart Updater")
    print("==================================================")
    print(f"[1/2] Checking updates from {SERVER_URL} ...")
    
    needs_download = False
    server_version = "1.0.0"
    server_hash = ""
    
    try:
        req = urllib.request.Request(
            f"{SERVER_URL}/api/version",
            headers={"User-Agent": "MusicCloudDesktopUpdater/1.0"}
        )
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            if resp.status == 200:
                data = json.loads(resp.read().decode("utf-8"))
                server_version = data.get("version", "1.0.0")
                server_hash = data.get("hash", "")
                changelog = data.get("changelog", "")
                
                local_ver = get_local_version()
                local_hash = get_file_hash(PLAYER_FILE)
                
                if not os.path.exists(PLAYER_FILE) or local_ver != server_version or (server_hash and local_hash != server_hash):
                    print(f"[*] New update found: v{server_version} (Local: v{local_ver})")
                    print(f"[*] Changelog: {changelog}")
                    needs_download = True
                else:
                    print(f"[OK] You have the latest version (v{local_ver}).")
    except Exception as e:
        print(f"[!] Server check skipped or offline ({e}). Using existing local player.")
        if not os.path.exists(PLAYER_FILE):
            print("[!] Critical: desktop_player.py is missing and server is offline!")
    
    if needs_download:
        print(f"[2/2] Downloading latest desktop app code from server...")
        download_url = f"{SERVER_URL}/api/desktop/latest"
        try:
            req = urllib.request.Request(download_url, headers={"User-Agent": "MusicCloudDesktopUpdater/1.0"})
            with urllib.request.urlopen(req, timeout=10.0) as resp:
                if resp.status == 200:
                    code_data = resp.read()
                    temp_file = PLAYER_FILE + ".tmp"
                    with open(temp_file, "wb") as f:
                        f.write(code_data)
                    
                    if os.path.exists(PLAYER_FILE):
                        try:
                            os.remove(PLAYER_FILE)
                        except Exception:
                            pass
                    os.rename(temp_file, PLAYER_FILE)
                    
                    new_hash = get_file_hash(PLAYER_FILE)
                    save_local_version(server_version, new_hash)
                    print(f"[SUCCESS] App updated to v{server_version} successfully on the fly!")
        except Exception as e:
            print(f"[!] Failed to download update: {e}")

    # Launch GUI
    print("[*] Launching MusicCloud Desktop...")
    if os.path.exists(PLAYER_FILE):
        subprocess.Popen([sys.executable, PLAYER_FILE], cwd=LOCAL_DIR)
    else:
        print("[!] Cannot start: desktop_player.py not found.")

if __name__ == "__main__":
    check_and_update()
