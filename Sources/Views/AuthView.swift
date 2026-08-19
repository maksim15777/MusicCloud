import SwiftUI

public struct AuthView: View {
    @ObservedObject var telegramService: TelegramService
    
    @State private var phoneNumber: String = ""
    @State private var authCode: String = ""
    @State private var password2FA: String = ""
    @State private var isShowingServerSheet: Bool = false
    @State private var currentServerInput: String = ""
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo & Cloud Icon
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.12))
                            .frame(width: 84, height: 84)
                        
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                    }
                    
                    Text("MusicCloud")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Музыкальный плеер для Telegram")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.bottom, 32)
                
                // Form Card based on Auth State
                VStack(spacing: 18) {
                    switch telegramService.authState {
                    case .enterPhoneNumber:
                        phoneStepView
                    case .enterCode(let phone):
                        codeStepView(phone: phone)
                    case .enterPassword(let hint):
                        passwordStepView(hint: hint)
                    case .loading(let status):
                        loadingStepView(status: status)
                    default:
                        phoneStepView
                    }
                    
                    if let error = telegramService.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(white: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Server URL indicator button at bottom
                Button(action: {
                    currentServerInput = telegramService.serverURL
                    isShowingServerSheet = true
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green.opacity(0.7))
                            .frame(width: 6, height: 6)
                        Text("Сервер: \(telegramService.serverURL)")
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(white: 0.08)))
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $isShowingServerSheet) {
            serverConfigSheet
        }
    }
    
    // MARK: - Step 1: Phone Number
    
    private var phoneStepView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ВХОД В АККАУНТ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                
                Text("Введите номер телефона")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .foregroundColor(Color(white: 0.45))
                
                TextField("+1 234 567 8900", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .foregroundColor(.white)
                    .accentColor(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
            )
            
            Button(action: {
                telegramService.sendPhoneNumber(phoneNumber)
            }) {
                HStack {
                    if telegramService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Text("Получить код")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
            .disabled(telegramService.isLoading || phoneNumber.isEmpty)
            .opacity(phoneNumber.isEmpty ? 0.5 : 1.0)
        }
    }
    
    // MARK: - Step 2: Confirmation Code
    
    private func codeStepView(phone: String) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ПОДТВЕРЖДЕНИЕ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                
                Text("Введите код из Telegram")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Код отправлен на номер \(phone)")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(Color(white: 0.45))
                
                TextField("Код подтверждения", text: $authCode)
                    .keyboardType(.numberPad)
                    .foregroundColor(.white)
                    .accentColor(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
            )
            
            Button(action: {
                telegramService.sendAuthCode(authCode)
            }) {
                HStack {
                    if telegramService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Text("Войти")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
            .disabled(telegramService.isLoading || authCode.isEmpty)
            .opacity(authCode.isEmpty ? 0.5 : 1.0)
            
            Button(action: {
                telegramService.authState = .enterPhoneNumber
            }) {
                Text("Изменить номер телефона")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
            }
        }
    }
    
    // MARK: - Step 3: 2FA Password
    
    private func passwordStepView(hint: String?) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("БЕЗОПАСНОСТЬ 2FA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                
                Text("Введите облачный пароль")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                if let hint = hint, !hint.isEmpty {
                    Text("Подсказка: \(hint)")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundColor(Color(white: 0.45))
                
                SecureField("Пароль двухфакторной аутентификации", text: $password2FA)
                    .foregroundColor(.white)
                    .accentColor(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
            )
            
            Button(action: {
                telegramService.sendPassword2FA(password2FA)
            }) {
                HStack {
                    if telegramService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Text("Подтвердить")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
            .disabled(telegramService.isLoading || password2FA.isEmpty)
            .opacity(password2FA.isEmpty ? 0.5 : 1.0)
        }
    }
    
    // MARK: - Loading Step
    
    private func loadingStepView(status: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text(status)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.8))
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Server URL Sheet
    
    private var serverConfigSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Адрес сервера MusicCloud")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Укажите IP вашего компьютера или адрес облачного сервера (например, http://192.168.1.50:8900):")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.6))
                
                TextField("http://192.168.1.50:8900", text: $currentServerInput)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
                    .foregroundColor(.white)
                
                Button(action: {
                    telegramService.updateServerURL(currentServerInput)
                    isShowingServerSheet = false
                }) {
                    Text("Сохранить")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
}
