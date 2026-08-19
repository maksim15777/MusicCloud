import Foundation

public struct TelegramConfig {
    public static let apiId: Int32 = 35197117
    public static let apiIdString: String = "35197117"
    public static let apiHash: String = "f92e244c8c272a00ae07551f08fd0427"
    public static let appTitle: String = "MusicCloud"
    public static let targetChatName: String = "MusicCloud"
    
    /// Адрес сервера-прослойки.
    /// По умолчанию: http://192.168.1.50:8000 (или ваш облачный адрес на Render / Railway)
    public static var defaultBackendURL: String {
        return UserDefaults.standard.string(forKey: "backend_server_url") ?? "http://199.83.103.63:8900"
    }
    
    public static func saveBackendURL(_ url: String) {
        var clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("/") {
            clean.removeLast()
        }
        UserDefaults.standard.set(clean, forKey: "backend_server_url")
    }
}
