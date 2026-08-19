import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    public let onExpand: () -> Void
    
    public var body: some View {
        if let track = playerManager.currentTrack {
            VStack(spacing: 0) {
                // Тонкий прогресс-бар вверху мини-плеера
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: geo.size.width, height: 2)
                        .overlay(
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geo.size.width * CGFloat(playerManager.playbackProgress), height: 2),
                            alignment: .leading
                        )
                }
                .frame(height: 2)
                
                HStack(spacing: 12) {
                    // Мини-обложка
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.18))
                            .frame(width: 44, height: 44)
                        
                        if let artwork = CacheManager.shared.cachedArtwork(for: track.id) {
                            Image(uiImage: artwork)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundColor(Color.white.opacity(0.7))
                        }
                    }
                    
                    // Название и артист
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.performer)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(white: 0.5))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Кнопка Play/Pause
                    AnimatedPlayButton(
                        isPlaying: playerManager.isPlaying,
                        size: 38,
                        iconSize: 14,
                        foregroundColor: .white,
                        backgroundColor: Color(white: 0.22),
                        action: {
                            playerManager.togglePlayPause()
                        }
                    )
                    
                    // Кнопка Далее
                    Button(action: {
                        playerManager.next()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(white: 0.75))
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(white: 0.12).opacity(0.96))
                    .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onExpand()
            }
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
