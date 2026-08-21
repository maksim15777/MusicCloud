import Foundation
import UIKit
import SwiftUI
import AVFoundation

public struct ToastMessage: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let message: String?
    public let iconName: String
    public let isError: Bool
    
    public init(title: String, message: String? = nil, iconName: String = "info.circle.fill", isError: Bool = false) {
        self.title = title
        self.message = message
        self.iconName = iconName
        self.isError = isError
    }
}

public final class TelegramService: ObservableObject {
    public static let shared = TelegramService()
    
    // MARK: - Published State
    @Published public var authState: TelegramAuthState = .enterPhoneNumber
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var targetChatTitle: String = TelegramConfig.targetChatName
    @Published public var tracks: [Track] = []
    @Published public var isUploading: Bool = false
    @Published public var uploadProgress: Double = 0.0
    @Published public var downloadProgress: [String: Double] = [:] // [TrackId: Progress 0.0...1.0]
    @Published public var currentToast: ToastMessage? = nil
    @Published public var isOfflineMode: Bool = false
    @Published public var serverURL: String = TelegramConfig.defaultBackendURL
    
    private let userDefaults = UserDefaults.standard
    private let kIsLoggedInKey = "tg_is_logged_in"
    private let kPhoneNumberKey = "tg_phone_number"
    
    private var currentPhoneNumber: String = ""
    
    private init() {
        self.serverURL = TelegramConfig.defaultBackendURL
        self.tracks = CacheManager.shared.loadCachedTracks()
        
        if userDefaults.bool(forKey: kIsLoggedInKey) {
            self.authState = .authenticated
            self.syncTracksWithServer(isSilent: true)
        } else {
            self.authState = .enterPhoneNumber
            self.checkServerAuthStatus()
        }
        
        NetworkMonitor.shared.onConnectedAgain = { [weak self] in
            guard let self = self, self.authState == .authenticated else { return }
            print("[TelegramService] Network restored. Syncing with backend server...")
            self.syncTracksWithServer(isSilent: true)
        }
    }
    
    // MARK: - Toast Notifications
    
    public func showToast(title: String, message: String? = nil, iconName: String = "info.circle.fill", isError: Bool = false) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentToast = ToastMessage(title: title, message: message, iconName: iconName, isError: isError)
        }
        
        let toastId = self.currentToast?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            if self.currentToast?.id == toastId {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.currentToast = nil
                }
            }
        }
    }
    
    public func dismissToast() {
        withAnimation(.easeOut(duration: 0.2)) {
            self.currentToast = nil
        }
    }
    
    public func checkServerAuthStatus() {
        guard let url = URL(string: "\(serverURL)/auth/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let authorized = json["authorized"] as? Bool,
                  authorized == true else { return }
            
            DispatchQueue.main.async {
                self.userDefaults.set(true, forKey: self.kIsLoggedInKey)
                self.authState = .authenticated
                self.syncTracksWithServer(isSilent: true)
            }
        }.resume()
    }
    
    public func updateServerURL(_ newURL: String) {
        self.serverURL = newURL
        TelegramConfig.saveBackendURL(newURL)
        if authState == .authenticated {
            syncTracksWithServer(isSilent: false)
        }
    }
    
    // MARK: - Real Authentication Flow via Backend Proxy
    
    public func sendPhoneNumber(_ phone: String) {
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPhone.isEmpty else {
            self.errorMessage = "Пожалуйста, введите корректный номер телефона"
            return
        }
        
        self.currentPhoneNumber = cleanPhone
        self.isLoading = true
        self.errorMessage = nil
        
        guard let url = URL(string: "\(serverURL)/auth/send-code") else {
            self.isLoading = false
            self.errorMessage = "Некорректный адрес сервера: \(serverURL)"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["phone": cleanPhone]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Не удалось связаться с сервером: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Сервер не отвечает"
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String,
                       status == "authenticated" {
                        self.userDefaults.set(true, forKey: self.kIsLoggedInKey)
                        self.userDefaults.set(cleanPhone, forKey: self.kPhoneNumberKey)
                        self.authState = .authenticated
                        self.showToast(title: "Вход выполнен", message: "Подключено к Telegram", iconName: "checkmark.circle.fill")
                        self.syncTracksWithServer(isSilent: false)
                    } else {
                        self.authState = .enterCode(phoneNumber: cleanPhone)
                    }
                } else {
                    let errDetail = self.extractErrorDetail(from: data) ?? "Ошибка запроса кода"
                    self.errorMessage = errDetail
                }
            }
        }.resume()
    }
    
    public func sendAuthCode(_ code: String) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else {
            self.errorMessage = "Пожалуйста, введите код"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        guard let url = URL(string: "\(serverURL)/auth/sign-in") else {
            self.isLoading = false
            self.errorMessage = "Некорректный адрес сервера"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["phone": self.currentPhoneNumber, "code": cleanCode]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Ошибка связи: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Неверный ответ сервера"
                    return
                }
                
                let status = json["status"] as? String ?? ""
                if status == "2fa_required" {
                    self.authState = .enterPassword(hint: "Облачный пароль 2FA")
                } else if status == "authenticated" {
                    self.userDefaults.set(true, forKey: self.kIsLoggedInKey)
                    self.userDefaults.set(self.currentPhoneNumber, forKey: self.kPhoneNumberKey)
                    self.authState = .authenticated
                    self.showToast(title: "Вход выполнен", message: "Добро пожаловать в MusicCloud!", iconName: "checkmark.circle.fill")
                    self.syncTracksWithServer(isSilent: false)
                } else {
                    let errDetail = self.extractErrorDetail(from: data) ?? "Ошибка авторизации"
                    self.errorMessage = errDetail
                }
            }
        }.resume()
    }
    
    public func sendPassword2FA(_ password: String) {
        guard !password.isEmpty else {
            self.errorMessage = "Пожалуйста, введите пароль 2FA"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        guard let url = URL(string: "\(serverURL)/auth/2fa") else {
            self.isLoading = false
            self.errorMessage = "Некорректный адрес сервера"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Ошибка: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Неверный ответ сервера"
                    return
                }
                
                let status = json["status"] as? String ?? ""
                if status == "authenticated" {
                    self.userDefaults.set(true, forKey: self.kIsLoggedInKey)
                    self.userDefaults.set(self.currentPhoneNumber, forKey: self.kPhoneNumberKey)
                    self.authState = .authenticated
                    self.showToast(title: "Вход выполнен", message: "Добро пожаловать в MusicCloud!", iconName: "checkmark.circle.fill")
                    self.syncTracksWithServer(isSilent: false)
                } else {
                    let errDetail = self.extractErrorDetail(from: data) ?? "Неверный пароль 2FA"
                    self.errorMessage = errDetail
                }
            }
        }.resume()
    }
    
    public func logOut() {
        userDefaults.set(false, forKey: kIsLoggedInKey)
        self.authState = .enterPhoneNumber
        self.tracks = []
        CacheManager.shared.clearAllCache()
        self.showToast(title: "Выход из аккаунта", message: "Кэш очищен", iconName: "rectangle.portrait.and.arrow.right")
        
        if let url = URL(string: "\(serverURL)/auth/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            URLSession.shared.dataTask(with: request).resume()
        }
    }
    
    // MARK: - Server Tracks Fetch & Auto-Sync
    
    public func fetchMusicCloudTracks() {
        syncTracksWithServer(isSilent: false)
    }
    
    public func syncTracksWithServer(isSilent: Bool = true) {
        if !isSilent {
            self.isLoading = true
        }
        self.errorMessage = nil
        
        guard let url = URL(string: "\(serverURL)/tracks") else {
            let cached = CacheManager.shared.loadCachedTracks()
            self.tracks = cached
            self.isOfflineMode = true
            self.isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            guard let self = self else { return }
            
            if error != nil || (response as? HTTPURLResponse)?.statusCode != 200 {
                let cached = CacheManager.shared.loadCachedTracks()
                DispatchQueue.main.async {
                    self.tracks = cached
                    self.isOfflineMode = true
                    self.isLoading = false
                    if !isSilent {
                        self.showToast(title: "Оффлайн режим", message: "Доступны сохраненные треки (\(cached.count))", iconName: "wifi.slash")
                    }
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tracksArray = json["tracks"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            var serverTracks: [Track] = []
            for item in tracksArray {
                let id = String(describing: item["id"] ?? UUID().uuidString)
                let messageId = (item["message_id"] as? Int64) ?? Int64(String(describing: item["message_id"] ?? 0)) ?? 0
                let chatId = (item["chat_id"] as? Int64) ?? Int64(String(describing: item["chat_id"] ?? 0)) ?? 0
                let title = item["title"] as? String ?? "Без названия"
                let performer = item["performer"] as? String ?? "Неизвестный исполнитель"
                let duration = (item["duration"] as? Double) ?? Double(String(describing: item["duration"] ?? 0)) ?? 0.0
                let fileName = item["file_name"] as? String ?? "audio.mp3"
                let fileSize = (item["file_size"] as? Int64) ?? Int64(String(describing: item["file_size"] ?? 0)) ?? 0
                
                let localURL = CacheManager.shared.cachedAudioURL(for: id)
                
                let track = Track(
                    id: id,
                    messageId: messageId,
                    chatId: chatId,
                    title: title,
                    performer: performer,
                    duration: duration,
                    fileName: fileName,
                    fileSize: fileSize,
                    localFileURL: localURL,
                    remoteFileId: "\(self.serverURL)/tracks/\(messageId)/audio",
                    artworkURL: nil,
                    dateAdded: Date()
                )
                serverTracks.append(track)
                
                // Начинаем фоновое скачивание в кэш с отслеживанием прогресса
                if localURL == nil && messageId > 0 {
                    self.downloadAudioToCache(track: track)
                }
            }
            
            // Синхронизируем удаленные треки
            let serverIds = Set(serverTracks.map { $0.id })
            let currentCached = CacheManager.shared.loadCachedTracks()
            for cachedTrack in currentCached {
                if !serverIds.contains(cachedTrack.id) {
                    CacheManager.shared.deleteAudio(for: cachedTrack.id)
                    CacheManager.shared.deleteArtwork(for: cachedTrack.id)
                }
            }
            
            CacheManager.shared.saveTracksMetadata(serverTracks)
            
            DispatchQueue.main.async {
                self.tracks = serverTracks
                self.isOfflineMode = false
                self.isLoading = false
                if !isSilent {
                    self.showToast(title: "Синхронизация завершена", message: "Песен в облаке: \(serverTracks.count)", iconName: "arrow.clockwise.circle.fill")
                }
            }
        }.resume()
    }
    
    private func downloadAudioToCache(track: Track) {
        guard let downloadURL = URL(string: "\(serverURL)/tracks/\(track.messageId)/audio") else { return }
        let trackId = track.id
        let fileName = track.fileName
        
        DispatchQueue.main.async { [weak self] in
            self?.downloadProgress[trackId] = 0.2
        }
        
        let task = URLSession.shared.dataTask(with: downloadURL) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.downloadProgress.removeValue(forKey: trackId)
                }
                return
            }
            
            let ext = (fileName as NSString).pathExtension.isEmpty ? "mp3" : (fileName as NSString).pathExtension
            if let localURL = CacheManager.shared.saveAudio(data: data, for: trackId, fileExtension: ext) {
                _ = CacheManager.shared.extractAndSaveArtwork(from: localURL, for: trackId)
                
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.downloadProgress[trackId] = 1.0
                    if let index = self.tracks.firstIndex(where: { $0.id == trackId }) {
                        self.tracks[index].localFileURL = localURL
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation {
                            self.downloadProgress.removeValue(forKey: trackId)
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.downloadProgress.removeValue(forKey: trackId)
                }
            }
        }
        task.resume()
    }
    
    @MainActor
    public func fetchMusicCloudTracksAsync() async {
        await withCheckedContinuation { continuation in
            self.syncTracksWithServer(isSilent: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                continuation.resume()
            }
        }
    }
    
    // MARK: - Track Deletion
    
    public func deleteTracks(trackIds: Set<String>, completion: (() -> Void)? = nil) {
        guard !trackIds.isEmpty else { return }
        
        let count = trackIds.count
        let messageIds = self.tracks
            .filter { trackIds.contains($0.id) && $0.messageId > 0 }
            .map { Int($0.messageId) }
        
        CacheManager.shared.removeTracks(trackIds: trackIds)
        self.tracks.removeAll(where: { trackIds.contains($0.id) })
        
        self.showToast(title: "Треки удалены", message: "Успешно удалено: \(count)", iconName: "trash.circle.fill")
        
        if !messageIds.isEmpty, let url = URL(string: "\(serverURL)/tracks/delete") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["message_ids": messageIds]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request).resume()
        }
        
        completion?()
    }
    
    // MARK: - Upload Audio File via Backend Proxy
    
    public func uploadAudioFile(
        from sourceURL: URL,
        title customTitle: String? = nil,
        performer customPerformer: String? = nil,
        customArtwork: UIImage? = nil,
        completion: @escaping (Result<Track, Error>) -> Void
    ) {
        self.isUploading = true
        self.uploadProgress = 0.1
        self.showToast(title: "Отправка трека...", message: customTitle ?? sourceURL.lastPathComponent, iconName: "arrow.up.circle.fill")
        
        guard let url = URL(string: "\(serverURL)/tracks/upload") else {
            self.isUploading = false
            self.showToast(title: "Ошибка", message: "Некорректный адрес сервера", iconName: "exclamationmark.triangle.fill", isError: true)
            completion(.failure(NSError(domain: "MusicCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес сервера"])))
            return
        }
        
        let asset = AVURLAsset(url: sourceURL)
        var title = customTitle ?? sourceURL.deletingPathExtension().lastPathComponent
        var performer = customPerformer ?? "Неизвестный исполнитель"
        
        if customTitle == nil || customPerformer == nil {
            for item in asset.metadata {
                if let key = item.commonKey?.rawValue {
                    if key == "title", let val = item.stringValue, !val.isEmpty, customTitle == nil { title = val }
                    if key == "artist", let val = item.stringValue, !val.isEmpty, customPerformer == nil { performer = val }
                }
            }
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let audioData = try? Data(contentsOf: sourceURL) else {
            self.isUploading = false
            self.showToast(title: "Ошибка", message: "Не удалось прочитать файл", iconName: "exclamationmark.triangle.fill", isError: true)
            completion(.failure(NSError(domain: "MusicCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать аудиофайл"])))
            return
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(sourceURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(title)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"performer\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(performer)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUploading = false
                
                if let error = error {
                    self.showToast(title: "Ошибка загрузки", message: error.localizedDescription, iconName: "exclamationmark.triangle.fill", isError: true)
                    completion(.failure(error))
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.showToast(title: "Ошибка", message: "Неверный ответ сервера", iconName: "exclamationmark.triangle.fill", isError: true)
                    completion(.failure(NSError(domain: "MusicCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка ответа сервера"])))
                    return
                }
                
                let id = String(describing: json["id"] ?? UUID().uuidString)
                let messageId = (json["message_id"] as? Int64) ?? Int64(String(describing: json["message_id"] ?? 0)) ?? 0
                let t = json["title"] as? String ?? title
                let p = json["performer"] as? String ?? performer
                let fn = json["file_name"] as? String ?? sourceURL.lastPathComponent
                
                let cachedURL = CacheManager.shared.saveAudio(data: audioData, for: id)
                
                if let customArtwork = customArtwork, let artData = customArtwork.jpegData(compressionQuality: 0.85) {
                    _ = CacheManager.shared.saveArtwork(data: artData, for: id)
                } else if let cachedURL = cachedURL {
                    _ = CacheManager.shared.extractAndSaveArtwork(from: cachedURL, for: id)
                }
                
                let newTrack = Track(
                    id: id,
                    messageId: messageId,
                    chatId: 1001234567,
                    title: t,
                    performer: p,
                    duration: CMTimeGetSeconds(asset.duration),
                    fileName: fn,
                    fileSize: Int64(audioData.count),
                    localFileURL: cachedURL,
                    remoteFileId: "\(self.serverURL)/tracks/\(messageId)/audio",
                    artworkURL: nil,
                    dateAdded: Date()
                )
                
                self.tracks.insert(newTrack, at: 0)
                CacheManager.shared.saveTracksMetadata(self.tracks)
                
                self.showToast(title: "Трек сохранен в MusicCloud", message: "\(t) — \(p)", iconName: "checkmark.circle.fill")
                completion(.success(newTrack))
            }
        }.resume()
    }
    
    private func extractErrorDetail(from data: Data?) -> String? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["detail"] as? String ?? json["message"] as? String
    }
}
