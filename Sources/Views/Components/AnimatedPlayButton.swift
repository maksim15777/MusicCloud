import SwiftUI

public struct AnimatedPlayButton: View {
    public let isPlaying: Bool
    public var size: CGFloat = 40
    public var iconSize: CGFloat = 16
    public var foregroundColor: Color = .white
    public var backgroundColor: Color = Color(white: 0.18)
    public let action: () -> Void
    
    public init(
        isPlaying: Bool,
        size: CGFloat = 40,
        iconSize: CGFloat = 16,
        foregroundColor: Color = .white,
        backgroundColor: Color = Color(white: 0.18),
        action: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.size = size
        self.iconSize = iconSize
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundColor(foregroundColor)
                    .offset(x: isPlaying ? 0 : 1.5) // Optical centering for play triangle
                    .rotationEffect(.degrees(isPlaying ? 0 : 0))
                    .scaleEffect(isPlaying ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPlaying)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

public struct ScaleButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
