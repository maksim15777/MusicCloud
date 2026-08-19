import Foundation

public enum TelegramAuthState: Equatable {
    case enterPhoneNumber
    case enterCode(phoneNumber: String)
    case enterPassword(hint: String?)
    case authenticated
    case loading(status: String)
    case error(message: String)
    
    public var description: String {
        switch self {
        case .enterPhoneNumber:
            return "Ожидание номера телефона"
        case .enterCode(let phone):
            return "Код подтверждения отправлен на \(phone)"
        case .enterPassword:
            return "Требуется двухфакторный пароль (2FA)"
        case .authenticated:
            return "Авторизован"
        case .loading(let status):
            return status
        case .error(let message):
            return "Ошибка: \(message)"
        }
    }
}
