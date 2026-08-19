import SwiftUI
import PhotosUI
import AVFoundation

public struct UploadTrackSheet: View {
    public let sourceFileURL: URL
    public let onUpload: (URL, String, String, UIImage?) -> Void
    public let onCancel: () -> Void
    
    @State private var trackTitle: String = ""
    @State private var performer: String = ""
    @State private var selectedArtwork: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var durationString: String = "00:00"
    @State private var fileSizeString: String = "0 MB"
    
    public init(
        sourceFileURL: URL,
        onUpload: @escaping (URL, String, String, UIImage?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceFileURL = sourceFileURL
        self.onUpload = onUpload
        self.onCancel = onCancel
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Artwork Preview & Change Button
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color(white: 0.12))
                                    .frame(width: 170, height: 170)
                                
                                if let image = selectedArtwork {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 170, height: 170)
                                        .clipShape(RoundedRectangle(cornerRadius: 22))
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 50, weight: .light))
                                            .foregroundColor(Color.white.opacity(0.6))
                                        Text("Нет обложки")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.4))
                                    }
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
                            
                            // PhotosPicker for custom cover
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.badge.plus")
                                    Text(selectedArtwork == nil ? "Выбрать обложку" : "Изменить обложку")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.9))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color(white: 0.16)))
                            }
                            .onChange(of: selectedPhotoItem) { newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        await MainActor.run {
                                            self.selectedArtwork = image
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 10)
                        
                        // Metadata Edit Fields
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("НАЗВАНИЕ ТРЕКА")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(white: 0.45))
                                    .tracking(1.2)
                                
                                TextField("Введите название песни", text: $trackTitle)
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ИСПОЛНИТЕЛЬ")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(white: 0.45))
                                    .tracking(1.2)
                                
                                TextField("Введите имя исполнителя", text: $performer)
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
                                    .foregroundColor(.white)
                            }
                            
                            // File info summary
                            HStack {
                                Text("Файл: \(sourceFileURL.lastPathComponent)")
                                    .lineLimit(1)
                                Spacer()
                                Text("\(durationString) • \(fileSizeString)")
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(white: 0.45))
                            .padding(.horizontal, 4)
                        }
                        .padding(.horizontal, 20)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: {
                                onUpload(sourceFileURL, trackTitle, performer, selectedArtwork)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                    Text("Отправить в MusicCloud")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                            }
                            
                            Button(action: {
                                onCancel()
                            }) {
                                Text("Отмена")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(white: 0.55))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Информация о треке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        onCancel()
                    }
                    .foregroundColor(Color(white: 0.7))
                }
            }
        }
        .onAppear {
            extractInitialMetadata()
        }
    }
    
    private func extractInitialMetadata() {
        let asset = AVURLAsset(url: sourceFileURL)
        var t = sourceFileURL.deletingPathExtension().lastPathComponent
        var p = "Неизвестный исполнитель"
        
        for item in asset.metadata {
            if let key = item.commonKey?.rawValue {
                if key == "title", let val = item.stringValue, !val.isEmpty { t = val }
                if key == "artist", let val = item.stringValue, !val.isEmpty { p = val }
            }
            if item.commonKey == .commonKeyArtwork, let data = item.dataValue, let img = UIImage(data: data) {
                self.selectedArtwork = img
            }
        }
        
        self.trackTitle = t
        self.performer = p
        
        let seconds = Int(CMTimeGetSeconds(asset.duration))
        if seconds > 0 {
            self.durationString = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceFileURL.path),
           let size = attrs[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useKB]
            formatter.countStyle = .file
            self.fileSizeString = formatter.string(fromByteCount: size)
        }
    }
}
