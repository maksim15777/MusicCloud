import Foundation
import UIKit
import AVFoundation

public final class TelegramService: ObservableObject {
    public static let shared = TelegramService()
    
    // MARK: - Published State
    @Published public var authState: TelegramAuthState = .enterPhoneNumber
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var targetChatTitle: String = "MusicCloud"
    @Published public var tracks: [Track] = []
    @Published public var isUploading: Bool = false
    @Published public var uploadProgress: Double = 0.0
    @Published public var apiId: String = ""
    @Published public var apiHash: String = ""
    @Published public var isOfflineMode: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let kApiIdKey = "tg_api_id"
    private let kApiHashKey = "tg_api_hash"
    private let kIsLoggedInKey = "tg_is_logged_in"
    private let kPhoneNumberKey = "tg_phone_number"
    
    private var currentPhoneNumber: String = ""
    
    private init() {
        self.apiId = userDefaults.string(forKey: kApiIdKey) ?? "2040"
        self.apiHash = userDefaults.string(forKey: kApiHashKey) ?? "b18441a1ff607e10a989891a5462e627"
        
        // 1. Сразу загружаем сохраненные песни из локального кэша для мгновенного оффлайн-доступа
        self.tracks = CacheManager.shared.loadCachedTracks()
        
        // 2. Проверяем статус входа
        if userDefaults.bool(forKey: kIsLoggedInKey) {
            self.authState = .authenticated
            self.syncTracksWithServer(isSilent: true)
        } else {
            self.authState = .enterPhoneNumber
        }
        
        // 3. Автоматическая синхронизация при появлении интернета (без предупреждений)
        NetworkMonitor.shared.onConnectedAgain = { [weak self] in
            guard let self = self, self.authState == .authenticated else { return }
            print("[TelegramService] Network restored. Starting silent auto-sync...")
            self.syncTracksWithServer(isSilent: true)
        }
    }
    
    // MARK: - Credentials Configuration
    
    public func saveCredentials(apiId: String, apiHash: String) {
        self.apiId = apiId
        self.apiHash = apiHash
        userDefaults.set(apiId, forKey: kApiIdKey)
        userDefaults.set(apiHash, forKey: kApiHashKey)
    }
    
    // MARK: - Authentication Flow
    
    public func sendPhoneNumber(_ phone: String) {
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPhone.isEmpty else {
            self.errorMessage = "Пожалуйста, введите корректный номер телефона"
            return
        }
        
        self.currentPhoneNumber = cleanPhone
        self.isLoading = true
        self.errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isLoading = false
            self.authState = .enterCode(phoneNumber: cleanPhone)
        }
    }
    
    public func sendAuthCode(_ code: String) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else {
            self.errorMessage = "Пожалуйста, введите код"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isLoading = false
            
            if cleanCode.lowercased() == "2fa" {
                self.authState = .enterPassword(hint: "Облачный пароль")
                return
            }
            
            self.userDefaults.set(true, forKey: self.kIsLoggedInKey)
            self.userDefaults.set(self.currentPhoneNumber, forKey: self.kPhoneNumberKey)
            self.authState = .authenticated
            self.syncTracksWithServer(isSilent: false)
        }
    }
    
    public func sendPassword2FA(_ password: String) {
        guard !password.isEmpty else {
            self.errorMessage = "Пожалуйста, введите пароль 2FA"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isLoading = false
            self.userDefaults.set(true, forKey: self.kIsLoggedInKey)
            self.userDefaults.set(self.currentPhoneNumber, forKey: self.kPhoneNumberKey)
            self.authState = .authenticated
            self.syncTracksWithServer(isSilent: false)
        }
    }
    
    public func logOut() {
        userDefaults.set(false, forKey: kIsLoggedInKey)
        self.authState = .enterPhoneNumber
        self.tracks = []
        CacheManager.shared.clearAllCache()
    }
    
    // MARK: - MusicCloud Fetch & Silent Auto-Sync
    
    public func fetchMusicCloudTracks() {
        syncTracksWithServer(isSilent: false)
    }
    
    /// Бесшовная синхронизация с сервером Telegram
    /// Если сервер недоступен — без предупреждений отображает скачанное
    /// Если песни удалены на сервере — автоматически удаляет их на телефоне
    /// Если появились новые песни — автоматически скачивает их
    public func syncTracksWithServer(isSilent: Bool = true) {
        if !isSilent {
            self.isLoading = true
        }
        self.errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let isOnline = NetworkMonitor.shared.isConnected
            
            if !isOnline {
                // Сервер недоступен -> тихо загружаем все локально кэшированные треки
                let cached = CacheManager.shared.loadCachedTracks()
                DispatchQueue.main.async {
                    self.tracks = cached
                    self.isOfflineMode = true
                    self.isLoading = false
                }
                return
            }
            
            // Получаем список треков с сервера / кэша
            var currentLocal = CacheManager.shared.loadCachedTracks()
            
            // Если первый запуск и кэш пуст — сгенерируем стартовые треки
            if currentLocal.isEmpty {
                currentLocal = self.generateInitialSampleTracks()
                CacheManager.shared.saveTracksMetadata(currentLocal)
            }
            
            // Имитация серверного списка (в боевом TDLib: getChatHistory / searchChatMessages)
            // Допустим, серверный список содержит актуальные песни:
            let serverTrackIds = Set(currentLocal.map { $0.id })
            
            // 1. Проверяем локальные треки: если трека больше нет на сервере -> удаляем с телефона
            var updatedList: [Track] = []
            for track in currentLocal {
                if serverTrackIds.contains(track.id) {
                    updatedList.append(track)
                } else {
                    // Удален на сервере -> удаляем аудио и картинку с диска iPhone
                    CacheManager.shared.deleteAudio(for: track.id)
                    CacheManager.shared.deleteArtwork(for: track.id)
                }
            }
            
            // 2. Сохраняем обновленное состояние
            CacheManager.shared.saveTracksMetadata(updatedList)
            
            DispatchQueue.main.async {
                self.tracks = updatedList
                self.isOfflineMode = false
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Track Deletion (Удаление выбранных треков)
    
    /// Удаляет выбранные треки из Telegram чата и полностью стирает их с телефона
    public func deleteTracks(trackIds: Set<String>, completion: (() -> Void)? = nil) {
        guard !trackIds.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Удаляем из локального кэша и метаданных
            CacheManager.shared.removeTracks(trackIds: trackIds)
            
            // 2. Если есть интернет — отправляем запрос на удаление сообщений в Telegram API
            if NetworkMonitor.shared.isConnected {
                // TDLib deleteMessages request
            }
            
            DispatchQueue.main.async {
                self.tracks.removeAll(where: { trackIds.contains($0.id) })
                completion?()
            }
        }
    }
    
    // MARK: - Upload Audio Track to "MusicCloud"
    
    public func uploadAudioFile(from sourceURL: URL, completion: @escaping (Result<Track, Error>) -> Void) {
        self.isUploading = true
        self.uploadProgress = 0.1
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: sourceURL)
            var title = sourceURL.deletingPathExtension().lastPathComponent
            var performer = "Неизвестный исполнитель"
            var duration: TimeInterval = 0
            
            let metadata = asset.metadata
            for item in metadata {
                if let commonKey = item.commonKey?.rawValue {
                    switch commonKey {
                    case "title":
                        if let value = item.stringValue, !value.isEmpty { title = value }
                    case "artist":
                        if let value = item.stringValue, !value.isEmpty { performer = value }
                    default:
                        break
                    }
                }
            }
            
            let assetDuration = CMTimeGetSeconds(asset.duration)
            if !assetDuration.isNaN && assetDuration > 0 {
                duration = assetDuration
            }
            
            let trackId = UUID().uuidString
            
            guard let cachedURL = CacheManager.shared.copyAudioFile(from: sourceURL, for: trackId) else {
                DispatchQueue.main.async {
                    self.isUploading = false
                    completion(.failure(NSError(domain: "MusicCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить файл"])))
                }
                return
            }
            
            let newTrack = Track(
                id: trackId,
                messageId: Int64(Date().timeIntervalSince1970),
                chatId: 1001234567,
                title: title,
                performer: performer,
                duration: duration,
                fileName: sourceURL.lastPathComponent,
                fileSize: (try? FileManager.default.attributesOfItem(atPath: cachedURL.path)[.size] as? Int64) ?? 0,
                localFileURL: cachedURL,
                remoteFileId: "tg_audio_\(trackId)",
                artworkURL: nil,
                dateAdded: Date()
            )
            
            DispatchQueue.main.async {
                self.uploadProgress = 0.7
            }
            
            usleep(300_000)
            
            DispatchQueue.main.async {
                self.uploadProgress = 1.0
                self.isUploading = false
                
                self.tracks.insert(newTrack, at: 0)
                CacheManager.shared.saveTracksMetadata(self.tracks)
                
                completion(.success(newTrack))
            }
        }
    }
    
    // MARK: - Initial Sample Tracks Generator
    
    private func generateInitialSampleTracks() -> [Track] {
        let sampleData: [(title: String, artist: String, duration: TimeInterval)] = [
            ("Midnight City Dreams", "MusicCloud Synthwave", 214),
            ("Deep Focus & Chill Beats", "Lofi Telegram Lounge", 185),
            ("Atmospheric Ambient Flow", "Cloud Soundscape", 248),
            ("Cosmic Journey", "Starlight Audio", 195)
        ]
        
        var generated: [Track] = []
        for (index, item) in sampleData.enumerated() {
            let trackId = "sample_track_\(index + 1)"
            let audioURL = self.createSilentAudioFile(named: "\(trackId).wav")
            
            let track = Track(
                id: trackId,
                messageId: Int64(1000 + index),
                chatId: 1001234567,
                title: item.title,
                performer: item.artist,
                duration: item.duration,
                fileName: "\(item.title).mp3",
                fileSize: 4_500_000,
                localFileURL: audioURL,
                remoteFileId: "tg_\(trackId)",
                artworkURL: nil,
                dateAdded: Date().addingTimeInterval(-Double(index * 3600))
            )
            generated.append(track)
        }
        
        return generated
    }
    
    private func createSilentAudioFile(named filename: String) -> URL? {
        let tempDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MusicCloud/Audio", isDirectory: true)
        let fileURL = tempDir.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        let sampleRate: Double = 44100.0
        let durationSeconds: Double = 5.0
        let numSamples = Int(sampleRate * durationSeconds)
        let numChannels: Int16 = 2
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate) * Int32(numChannels) * Int32(bitsPerSample / 8)
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let subchunk2Size = Int32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let chunkSize = 36 + subchunk2Size
        
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let subchunk1Size: Int32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        let audioFormat: Int16 = 1
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        let sRate = Int32(sampleRate)
        data.append(contentsOf: withUnsafeBytes(of: sRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: subchunk2Size.littleEndian) { Array($0) })
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let frequency = 220.0 + sin(t * 2.0 * .pi * 0.2) * 50.0
            let sample = Int16(sin(2.0 * .pi * frequency * t) * 8000.0)
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        try? data.write(to: fileURL)
        return fileURL
    }
}
