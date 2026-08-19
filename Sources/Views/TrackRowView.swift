import SwiftUI

public struct TrackRowView: View {
    public let track: Track
    public let isPlayingTrack: Bool
    public let isPlayingAudio: Bool
    public let isEditMode: Bool
    public let isSelectedForEdit: Bool
    public let onPlayToggle: () -> Void
    public let onSelect: () -> Void
    public let onLongPress: () -> Void
    public let onToggleEditSelection: () -> Void
    
    public init(
        track: Track,
        isPlayingTrack: Bool,
        isPlayingAudio: Bool,
        isEditMode: Bool,
        isSelectedForEdit: Bool,
        onPlayToggle: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        onToggleEditSelection: @escaping () -> Void
    ) {
        self.track = track
        self.isPlayingTrack = isPlayingTrack
        self.isPlayingAudio = isPlayingAudio
        self.isEditMode = isEditMode
        self.isSelectedForEdit = isSelectedForEdit
        self.onPlayToggle = onPlayToggle
        self.onSelect = onSelect
        self.onLongPress = onLongPress
        self.onToggleEditSelection = onToggleEditSelection
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // В режиме редактирования: Чекбокс выбора
            if isEditMode {
                ZStack {
                    Circle()
                        .stroke(isSelectedForEdit ? Color.white : Color(white: 0.35), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelectedForEdit {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                    }
                }
                .frame(width: 28, height: 28)
                .transition(.scale.combined(with: .opacity))
            } else {
                // В обычном режиме: Кнопка Play / Pause с плавной анимацией превращения
                AnimatedPlayButton(
                    isPlaying: isPlayingTrack && isPlayingAudio,
                    size: 42,
                    iconSize: 15,
                    foregroundColor: isPlayingTrack ? .white : Color(white: 0.85),
                    backgroundColor: isPlayingTrack ? Color(white: 0.24) : Color(white: 0.12),
                    action: onPlayToggle
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            // Название песни (главным) и имя исполнителя (ниже)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 16, weight: isPlayingTrack ? .semibold : .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if isPlayingTrack && isPlayingAudio && !isEditMode {
                        WaveformIndicator(isPlaying: true, color: Color(white: 0.9))
                    }
                }
                
                Text(track.performer)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Длительность песни в самом конце бейджика
            Text(track.formattedDuration)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.08))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isEditMode && isSelectedForEdit
                        ? Color(white: 0.22) // Выделение при выборе для удаления
                        : (isPlayingTrack && !isEditMode
                            ? Color(white: 0.16) // Приглушенный темно-серый для играющего трека
                            : Color(white: 0.08)) // Глубокий темный для остальных
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            (isEditMode && isSelectedForEdit)
                                ? Color.white.opacity(0.35)
                                : (isPlayingTrack && !isEditMode ? Color.white.opacity(0.18) : Color.white.opacity(0.04)),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onToggleEditSelection()
            } else {
                onSelect()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            onLongPress()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEditMode)
        .animation(.easeInOut(duration: 0.2), value: isSelectedForEdit)
        .animation(.easeInOut(duration: 0.25), value: isPlayingTrack)
    }
}
