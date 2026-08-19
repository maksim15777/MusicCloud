import SwiftUI

public struct ContentView: View {
    @StateObject private var telegramService = TelegramService.shared
    @StateObject private var playerManager = AudioPlayerManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    @State private var isShowingFullPlayer: Bool = false
    @State private var isShowingDocumentPicker: Bool = false
    @State private var searchText: String = ""
    
    // Режим выбора и редактирования (Удаление)
    @State private var isEditMode: Bool = false
    @State private var selectedTrackIds: Set<String> = []
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if telegramService.authState != .authenticated {
                AuthView(telegramService: telegramService)
                    .transition(.opacity)
            } else {
                mainMusicCloudView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: telegramService.authState)
        .sheet(isPresented: $isShowingFullPlayer) {
            PlayerView(playerManager: playerManager)
        }
        .sheet(isPresented: $isShowingDocumentPicker) {
            DocumentPicker(
                onFilePicked: { fileURL in
                    isShowingDocumentPicker = false
                    uploadPickedAudio(fileURL: fileURL)
                },
                onCancel: {
                    isShowingDocumentPicker = false
                }
            )
        }
    }
    
    // MARK: - Main MusicCloud View
    
    private var mainMusicCloudView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if isEditMode {
                    editModeHeaderBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    normalHeaderBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Track List or Empty State
                if filteredTracks.isEmpty {
                    emptyStateView
                } else {
                    trackListView
                }
            }
            
            // Bottom Bar (Upload button / Mini player OR Delete action bar)
            if isEditMode {
                editModeBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                normalBottomBarOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isEditMode)
    }
    
    // MARK: - Normal Header Bar
    
    private var normalHeaderBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("MusicCloud")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Circle()
                            .fill(networkMonitor.isConnected ? Color.green.opacity(0.85) : Color(white: 0.4))
                            .frame(width: 8, height: 8)
                    }
                    
                    Text(networkMonitor.isConnected ? "Чат Telegram • \(telegramService.tracks.count) треков" : "Оффлайн-режим • \(telegramService.tracks.count) скачано")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(white: 0.5))
                }
                
                Spacer()
                
                // Refresh Button (Manual sync)
                Button(action: {
                    withAnimation {
                        telegramService.syncTracksWithServer(isSilent: false)
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.12))
                            .frame(width: 40, height: 40)
                        
                        if telegramService.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.45))
                
                TextField("Поиск по песням и артистам...", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .accentColor(.white)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.45))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.10))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.95))
    }
    
    // MARK: - Edit Mode Header Bar (Выбор песен)
    
    private var editModeHeaderBar: some View {
        HStack {
            // Кнопка назад / выхода из режима выбора
            Button(action: {
                exitEditMode()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Готово")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Color(white: 0.16)))
            }
            
            Spacer()
            
            Text(selectedTrackIds.isEmpty ? "Выберите песни" : "Выбрано: \(selectedTrackIds.count)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Кнопка "Выбрать все"
            Button(action: {
                if selectedTrackIds.count == filteredTracks.count {
                    selectedTrackIds.removeAll()
                } else {
                    selectedTrackIds = Set(filteredTracks.map { $0.id })
                }
            }) {
                Text(selectedTrackIds.count == filteredTracks.count ? "Снять" : "Все")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color(white: 0.16)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.95))
    }
    
    // MARK: - Track List
    
    private var trackListView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 8) {
                ForEach(filteredTracks) { track in
                    TrackRowView(
                        track: track,
                        isPlayingTrack: playerManager.currentTrack?.id == track.id,
                        isPlayingAudio: playerManager.isPlaying,
                        isEditMode: isEditMode,
                        isSelectedForEdit: selectedTrackIds.contains(track.id),
                        onPlayToggle: {
                            playerManager.togglePlayPause(for: track, in: filteredTracks)
                        },
                        onSelect: {
                            if playerManager.currentTrack?.id == track.id {
                                isShowingFullPlayer = true
                            } else {
                                playerManager.play(track: track, in: filteredTracks)
                            }
                        },
                        onLongPress: {
                            if !isEditMode {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isEditMode = true
                                    selectedTrackIds.insert(track.id)
                                }
                            }
                        },
                        onToggleEditSelection: {
                            if selectedTrackIds.contains(track.id) {
                                selectedTrackIds.remove(track.id)
                            } else {
                                selectedTrackIds.insert(track.id)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, playerManager.currentTrack != nil ? 130 : 90)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(white: 0.08))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundColor(Color(white: 0.4))
            }
            
            Text("Нет песен в MusicCloud")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Нажмите на три полоски внизу слева,\nчтобы загрузить аудиофайл в чат")
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Button(action: {
                isShowingDocumentPicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Выбрать музыку")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white))
            }
            .padding(.top, 6)
            
            Spacer()
        }
        .padding(.horizontal, 30)
    }
    
    // MARK: - Normal Bottom Bar Overlay (Три полоски + Mini Player)
    
    private var normalBottomBarOverlay: some View {
        VStack(spacing: 8) {
            if telegramService.isUploading {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    
                    Text("Отправка трека в MusicCloud...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(white: 0.20)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            HStack(alignment: .bottom, spacing: 10) {
                // Кнопка "три полоски" внизу слева
                Button(action: {
                    isShowingDocumentPicker = true
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(white: 0.14))
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                        
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 20, height: 2.5)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 14, height: 2.5)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 18, height: 2.5)
                        }
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Mini Player
                if playerManager.currentTrack != nil {
                    MiniPlayerView(playerManager: playerManager) {
                        isShowingFullPlayer = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.95), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - Edit Mode Bottom Bar (Удаление)
    
    private var editModeBottomBar: some View {
        VStack(spacing: 0) {
            Button(action: {
                deleteSelectedTracks()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(selectedTrackIds.isEmpty ? "Удалить" : "Удалить (\(selectedTrackIds.count))")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(selectedTrackIds.isEmpty ? Color(white: 0.16) : Color.red.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
            }
            .disabled(selectedTrackIds.isEmpty)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.95), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - Helper Methods
    
    private var filteredTracks: [Track] {
        if searchText.isEmpty {
            return telegramService.tracks
        }
        return telegramService.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.performer.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func exitEditMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isEditMode = false
            selectedTrackIds.removeAll()
        }
    }
    
    private func deleteSelectedTracks() {
        let toDelete = selectedTrackIds
        exitEditMode()
        
        // Если удаляется текущий играющий трек -> останавливаем плеер
        if let current = playerManager.currentTrack, toDelete.contains(current.id) {
            playerManager.pause()
            playerManager.currentTrack = nil
        }
        
        telegramService.deleteTracks(trackIds: toDelete)
    }
    
    private func uploadPickedAudio(fileURL: URL) {
        telegramService.uploadAudioFile(from: fileURL) { result in
            switch result {
            case .success(let newTrack):
                withAnimation {
                    playerManager.play(track: newTrack, in: telegramService.tracks)
                }
            case .failure(let error):
                print("[ContentView] Upload error: \(error.localizedDescription)")
            }
        }
    }
}
