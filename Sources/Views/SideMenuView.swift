import SwiftUI

public struct SideMenuView: View {
    @Binding var isOpen: Bool
    @ObservedObject var telegramService: TelegramService
    public let onAddTrack: () -> Void
    
    @State private var cacheSize: String = CacheManager.shared.totalCacheSizeFormatted()
    @State private var showClearCacheAlert: Bool = false
    @State private var showLogoutAlert: Bool = false
    
    public var body: some View {
        ZStack(alignment: .trailing) {
            if isOpen {
                // Dimmed background
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isOpen = false
                        }
                    }
                    .transition(.opacity)
                
                // Side Drawer Panel
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MusicCloud")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                Text("Чат Telegram активен")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(white: 0.55))
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isOpen = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(white: 0.7))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color(white: 0.12)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                    .padding(.bottom, 24)
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Menu Items
                    ScrollView {
                        VStack(spacing: 8) {
                            // 1. Добавить трек
                            Button(action: {
                                isOpen = false
                                onAddTrack()
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white)
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.black)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Добавить трек")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("Загрузить аудио в чат")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.5))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color(white: 0.35))
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
                            }
                            .padding(.top, 14)
                            
                            // 2. Синхронизировать
                            Button(action: {
                                isOpen = false
                                telegramService.syncTracksWithServer(isSilent: false)
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(white: 0.16))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Синхронизация")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("Обновить список треков")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.5))
                                    }
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.07)))
                            }
                            
                            // 3. Очистить кэш
                            Button(action: {
                                showClearCacheAlert = true
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(white: 0.16))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "internaldrive")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Память и кэш")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("Занято: \(cacheSize)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.5))
                                    }
                                    
                                    Spacer()
                                    
                                    Text("Очистить")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.red.opacity(0.85))
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.07)))
                            }
                            
                            // 4. Выйти
                            Button(action: {
                                showLogoutAlert = true
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.red.opacity(0.15))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.red)
                                    }
                                    
                                    Text("Выйти из аккаунта")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.red.opacity(0.9))
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.07)))
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    Spacer()
                    
                    Text("MusicCloud iOS v1.0")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.35))
                        .padding(20)
                }
                .frame(width: 290)
                .background(Color(white: 0.08).ignoresSafeArea())
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1),
                    alignment: .leading
                )
                .transition(.move(edge: .trailing))
            }
        }
        .alert("Очистить кэш?", isPresented: $showClearCacheAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                CacheManager.shared.clearAllCache()
                cacheSize = CacheManager.shared.totalCacheSizeFormatted()
                telegramService.syncTracksWithServer(isSilent: true)
            }
        } message: {
            Text("Все локально скачанные треки будут удалены с устройства. Они скачаются заново при воспроизведении.")
        }
        .alert("Выйти из Telegram?", isPresented: $showLogoutAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Выйти", role: .destructive) {
                isOpen = false
                telegramService.logOut()
            }
        } message: {
            Text("Вы выйдете из аккаунта MusicCloud.")
        }
    }
}
