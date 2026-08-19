# MusicCloud — Нативный iOS Telegram плеер (SwiftUI + AVFoundation)

Минималистичный и стильный нативный музыкальный плеер для iOS 16+ (iPhone X и новее), воспроизводящий треки из чата/группы **"MusicCloud"** в Telegram.

Разработан для сборки прямо из Windows через бесплатный CI/CD GitHub Actions и установки на iPhone через **Sideloadly** (без Mac и платного аккаунта Apple Developer).

---

## Особенности приложения

- **Полноценное фоновое воспроизведение**: настроенный `AVAudioSession` (`.playback`, `longFormAudio`), звук не прерывается при блокировке экрана или сворачивании.
- **Экран блокировки и Пункт управления**: полная интеграция с `MPNowPlayingInfoCenter` и `MPRemoteCommandCenter` (отображение названия, артиста, плавной перемотки со слайдера Lock Screen, управление с кнопок проводных и Bluetooth наушников).
- **Стильный минималистичный UI (Dark Theme)**: палитра из глубоких темных, темно-серых и белых тонов, анимация превращения кнопки Play в Pause при клике, подсветка играющего трека.
- **Поддержка Telegram**:
  1. Вход по номеру телефона.
  2. Запрос кода подтверждения.
  3. Поддержка двухфакторной аутентификации (2FA Cloud Password).
  4. Автоматическая загрузка треков из чата **"MusicCloud"**.
- **Кнопка «три полоски» внизу слева**: открывает выбор локального аудиофайла (`.mp3`, `.m4a`, `.wav`, `.flac`) и отправляет его в чат с бейджиком `{"имя песни", "исполнитель"}`.

---

## Структура проекта

```
player/
├── .github/workflows/build.yml   # Сборка .ipa на macOS через GitHub Actions
├── project.yml                   # Конфигурация XcodeGen (генерация .xcodeproj)
├── Sources/
│   ├── App/
│   │   ├── TGMusicPlayerApp.swift# Главная точка входа (@main)
│   │   └── Info.plist            # Фоновые режимы UIBackgroundModes (audio)
│   ├── Models/
│   │   ├── Track.swift           # Модель трека с бейджиком {"имя", "исполнитель"}
│   │   └── TelegramAuthState.swift# Состояния авторизации
│   ├── Services/
│   │   ├── AudioPlayerManager.swift # AVPlayer, Lock Screen, наушники
│   │   ├── TelegramService.swift    # API клиент, чат MusicCloud, отправка треков
│   │   └── CacheManager.swift       # Кэширование mp3 и обложек
│   └── Views/
│       ├── ContentView.swift        # Главный экран (поиск, треки, мини-плеер)
│       ├── AuthView.swift           # Экран авторизации (телефон -> код -> 2FA)
│       ├── TrackRowView.swift       # Бейджик трека с анимированным Play/Pause
│       ├── PlayerView.swift         # Полноэкранный плеер
│       ├── MiniPlayerView.swift     # Мини-плеер внизу
│       ├── DocumentPicker.swift     # Системный выбор файлов
│       └── Components/
│           ├── AnimatedPlayButton.swift # Морфинг Play <-> Pause
│           ├── WaveformIndicator.swift  # Анимированный эквалайзер
│           └── CustomSlider.swift       # Плавный слайдер перемотки
└── Resources/
    └── Assets.xcassets/             # Иконки и цветовые ресурсы
```

---

## Инструкция по сборке и установке на Windows

### Шаг 1. Загрузите код в свой GitHub репозиторий
Откройте терминал в папке `c:\1\player` и выполните:
```bash
git init
git add .
git commit -m "Initial commit: MusicCloud iOS player"
git branch -M main
git remote add origin https://github.com/ВАШ_НИК/ВАШ_РЕПОЗИТОРИЙ.git
git push -u origin main
```

### Шаг 2. Автоматическая сборка `.ipa` в GitHub Actions
1. Перейдите во вкладку **Actions** в вашем репозитории на GitHub.
2. Процесс **Build iOS IPA** запустится автоматически на виртуальной машине macOS.
3. По завершении сборки (через ~2-3 минуты) в разделе **Artifacts** появится файл `MusicCloud-IPA.zip`.
4. Скачайте его и распакуйте — внутри будет готовый файл `MusicCloud.ipa`.

### Шаг 3. Установка на iPhone X через Sideloadly
1. Скачайте и установите [Sideloadly](https://sideloadly.io/) на Windows.
2. Подключите iPhone X кабелем к компьютеру и выберите «Доверять этому компьютеру».
3. Перетащите скачанный `MusicCloud.ipa` в окно Sideloadly.
4. Введите свой Apple ID (для бесплатной подписи приложения) и нажмите **Start**.
5. После завершения установки на iPhone перейдите в:
   **Настройки -> Основные -> VPN и управление устройством** -> выберите ваш Apple ID и нажмите **«Доверять»**.
6. Готово! Запустите **MusicCloud** на вашем iPhone.
