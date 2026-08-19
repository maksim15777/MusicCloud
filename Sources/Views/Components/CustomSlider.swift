import SwiftUI

public struct CustomSlider: View {
    @Binding public var value: Double // 0.0 ... 1.0
    public let onEditingChanged: (Bool) -> Void
    
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0.0
    
    public init(value: Binding<Double>, onEditingChanged: @escaping (Bool) -> Void) {
        self._value = value
        self.onEditingChanged = onEditingChanged
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let currentProgress = isDragging ? dragProgress : max(0.0, min(value, 1.0))
            let fillWidth = max(0, totalWidth * CGFloat(currentProgress))
            
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: isDragging ? 6 : 4)
                
                // Filled progress
                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth, height: isDragging ? 6 : 4)
                
                // Thumb knob
                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(fillWidth - (isDragging ? 8 : 5), totalWidth - (isDragging ? 16 : 10))))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let newProgress = max(0.0, min(gesture.location.x / totalWidth, 1.0))
                        dragProgress = Double(newProgress)
                    }
                    .onEnded { gesture in
                        let newProgress = max(0.0, min(gesture.location.x / totalWidth, 1.0))
                        value = Double(newProgress)
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 24)
    }
}
