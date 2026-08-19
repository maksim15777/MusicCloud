import SwiftUI
import MediaPlayer

public struct PlayerView: View {
    @ObservedObject var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        ZStack {
            // Dark elegant background
            Color(white: 0.05).ignoresSafeArea()
            
            // Background subtle gradient glow
            RadialGradient(
                gradient: Gradient(colors: [Color(white: 0.16), Color(white: 0.03)]),
                center: .top,
                startRadius: 50,
                endRadius: 600
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header (Dismiss button & Title)
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(white: 0.14)))
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("СЕЙЧАС ИГРАЕТ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(white: 0.45))
                            .tracking(1.5)
                        
                        Text("MusicCloud")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Empty placeholder to balance header
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                Spacer(minLength: 10)
                
                // Big Album Artwork Card
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.18), Color(white: 0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 280, height: 280)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 14)
                    
                    VStack(spacing: 16) {
                        Image(systemName: "music.note")
                            .font(.system(size: 80, weight: .light))
                            .foregroundColor(Color.white.opacity(0.75))
                        
                        if let track = playerManager.currentTrack {
                            Text(track.telegramCaptionBadge)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(white: 0.45))
                                .padding(.horizontal, 16)
                                .lineLimit(1)
                        }
                    }
                }
                .scaleEffect(playerManager.isPlaying ? 1.02 : 0.94)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: playerManager.isPlaying)
                
                Spacer(minLength: 10)
                
                // Track Info
                if let track = playerManager.currentTrack {
                    VStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                        
                        Text(track.performer)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(white: 0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                    }
                }
                
                // Scrubber & Timestamps
                VStack(spacing: 8) {
                    CustomSlider(value: $playerManager.playbackProgress) { isSeeking in
                        if !isSeeking {
                            playerManager.seek(progress: playerManager.playbackProgress)
                        }
                    }
                    
                    HStack {
                        Text(formatTime(playerManager.currentTime))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.45))
                        
                        Spacer()
                        
                        Text("-\(formatTime(max(0, playerManager.duration - playerManager.currentTime)))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.45))
                    }
                }
                .padding(.horizontal, 24)
                
                // Playback Controls
                HStack(spacing: 32) {
                    // Shuffle
                    Button(action: { playerManager.toggleShuffle() }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(playerManager.isShuffled ? .white : Color(white: 0.35))
                    }
                    
                    // Prev
                    Button(action: { playerManager.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                    
                    // Big Play/Pause
                    AnimatedPlayButton(
                        isPlaying: playerManager.isPlaying,
                        size: 72,
                        iconSize: 26,
                        foregroundColor: .black,
                        backgroundColor: .white,
                        action: {
                            playerManager.togglePlayPause()
                        }
                    )
                    
                    // Next
                    Button(action: { playerManager.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                    
                    // Repeat
                    Button(action: { playerManager.toggleRepeat() }) {
                        Image(systemName: playerManager.repeatMode.iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(playerManager.repeatMode != .off ? .white : Color(white: 0.35))
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 20)
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
