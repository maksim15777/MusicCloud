import os
import sys
import subprocess

def ensure_dependencies():
    packages = []
    try:
        import customtkinter
    except ImportError:
        packages.append("customtkinter")
    
    try:
        import requests
    except ImportError:
        packages.append("requests")
        
    try:
        from PIL import Image
    except ImportError:
        packages.append("pillow")
        
    if packages:
        print(f"[*] Installing required packages: {', '.join(packages)} ...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install"] + packages)
        except Exception as e:
            print(f"[!] Warning during package installation: {e}")

if __name__ == "__main__":
    ensure_dependencies()
    
    # Запускаем смарт-апдейтер, который проверит обновления и откроет плеер
    try:
        import updater
        updater.main()
    except Exception as e:
        print(f"[!] Error launching updater: {e}")
        # Если апдейтер упал, пробуем напрямую запустить desktop_player
        try:
            import desktop_player
            app = desktop_player.MusicCloudDesktop()
            app.mainloop()
        except Exception as err:
            print(f"[!] Critical launch error: {err}")
