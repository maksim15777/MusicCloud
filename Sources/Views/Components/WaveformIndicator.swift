import SwiftUI

public struct WaveformIndicator: View {
    public let isPlaying: Bool
    public var color: Color = .white
    
    @State private var bar1Height: CGFloat = 4
    @State private var bar2Height: CGFloat = 8
    @State private var bar3Height: CGFloat = 6
    @State private var bar4Height: CGFloat = 10
    
    public init(isPlaying: Bool, color: Color = .white) {
        self.isPlaying = isPlaying
        self.color = color
    }
    
    public var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 2.5, height: isPlaying ? bar1Height : 4)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 2.5, height: isPlaying ? bar2Height : 6)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 2.5, height: isPlaying ? bar3Height : 4)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 2.5, height: isPlaying ? bar4Height : 7)
        }
        .frame(height: 14)
        .onAppear {
            if isPlaying {
                startAnimation()
            }
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }
    
    private func startAnimation() {
        withAnimation(Animation.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
            bar1Height = 13
        }
        withAnimation(Animation.easeInOut(duration: 0.35).repeatForever(autoreverses: true).delay(0.1)) {
            bar2Height = 14
        }
        withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(0.2)) {
            bar3Height = 11
        }
        withAnimation(Animation.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(0.15)) {
            bar4Height = 14
        }
    }
    
    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            bar1Height = 4
            bar2Height = 6
            bar3Height = 4
            bar4Height = 7
        }
    }
}
