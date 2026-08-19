import Foundation

public struct Track: Identifiable, Hashable, Codable, Equatable {
    public let id: String
    public let messageId: Int64
    public let chatId: Int64
    public var title: String
    public var performer: String
    public var duration: TimeInterval
    public var fileName: String
    public var fileSize: Int64
    public var localFileURL: URL?
    public var remoteFileId: String?
    public var artworkURL: URL?
    public var dateAdded: Date
    
    public init(
        id: String = UUID().uuidString,
        messageId: Int64 = 0,
        chatId: Int64 = 0,
        title: String,
        performer: String,
        duration: TimeInterval,
        fileName: String,
        fileSize: Int64 = 0,
        localFileURL: URL? = nil,
        remoteFileId: String? = nil,
        artworkURL: URL? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.messageId = messageId
        self.chatId = chatId
        self.title = title.isEmpty ? "Без названия" : title
        self.performer = performer.isEmpty ? "Неизвестный исполнитель" : performer
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.localFileURL = localFileURL
        self.remoteFileId = remoteFileId
        self.artworkURL = artworkURL
        self.dateAdded = dateAdded
    }
    
    /// Форматированная длительность: "03:45"
    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Формат подписи для отправки в Telegram: {"имя песни", "исполнитель"}
    public var telegramCaptionBadge: String {
        return "{\"\(title)\", \"\(performer)\"}"
    }
    
    public static func == (lhs: Track, rhs: Track) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
