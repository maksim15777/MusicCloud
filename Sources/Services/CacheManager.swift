import Foundation
import UIKit
import AVFoundation

public final class CacheManager {
    public static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let audioDirectory: URL
    private let artworkDirectory: URL
    private let metadataFile: URL
    
    private init() {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MusicCloud", isDirectory: true)
        
        self.audioDirectory = cacheDir.appendingPathComponent("Audio", isDirectory: true)
        self.artworkDirectory = cacheDir.appendingPathComponent("Artwork", isDirectory: true)
        self.metadataFile = cacheDir.appendingPathComponent("tracks_metadata.json")
        
        createDirectoriesIfNeeded()
    }
    
    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Audio Cache
    
    public func cachedAudioURL(for trackId: String, fileExtension: String = "mp3") -> URL? {
        // Проверяем точное расширение или поиск любого файла с этим trackId
        let directURL = audioDirectory.appendingPathComponent("\(trackId).\(fileExtension)")
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }
        
        // Поиск с другим расширением (wav, m4a, etc.)
        if let files = try? fileManager.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) {
            if let matched = files.first(where: { $0.deletingPathExtension().lastPathComponent == trackId }) {
                return matched
            }
        }
        return nil
    }
    
    public func saveAudio(data: Data, for trackId: String, fileExtension: String = "mp3") -> URL? {
        let fileURL = audioDirectory.appendingPathComponent("\(trackId).\(fileExtension)")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("[CacheManager] Error saving audio: \(error)")
            return nil
        }
    }
    
    public func copyAudioFile(from sourceURL: URL, for trackId: String) -> URL? {
        let fileExt = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let destinationURL = audioDirectory.appendingPathComponent("\(trackId).\(fileExt)")
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            print("[CacheManager] Error copying audio: \(error)")
            return nil
        }
    }
    
    public func deleteAudio(for trackId: String) {
        if let files = try? fileManager.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.deletingPathExtension().lastPathComponent == trackId {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Artwork Cache
    
    public func saveArtwork(data: Data, for trackId: String) -> URL? {
        let fileURL = artworkDirectory.appendingPathComponent("\(trackId).jpg")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("[CacheManager] Error saving artwork: \(error)")
            return nil
        }
    }
    
    public func cachedArtwork(for trackId: String) -> UIImage? {
        let fileURL = artworkDirectory.appendingPathComponent("\(trackId).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    public func deleteArtwork(for trackId: String) {
        let fileURL = artworkDirectory.appendingPathComponent("\(trackId).jpg")
        try? fileManager.removeItem(at: fileURL)
    }
    
    /// Извлекает встроенную обложку (ID3 / MP4 artwork) из самого аудиофайла
    public func extractAndSaveArtwork(from audioURL: URL, for trackId: String) -> UIImage? {
        let asset = AVURLAsset(url: audioURL)
        for item in asset.metadata {
            if let commonKey = item.commonKey, commonKey == .commonKeyArtwork, let data = item.dataValue {
                if let image = UIImage(data: data) {
                    _ = saveArtwork(data: data, for: trackId)
                    return image
                }
            }
        }
        return nil
    }
    
    // MARK: - Metadata Cache
    
    public func saveTracksMetadata(_ tracks: [Track]) {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: metadataFile, options: .atomic)
        } catch {
            print("[CacheManager] Error saving tracks metadata: \(error)")
        }
    }
    
    public func loadCachedTracks() -> [Track] {
        guard let data = try? Data(contentsOf: metadataFile),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else {
            return []
        }
        return tracks
    }
    
    public func removeTrackFromMetadata(trackId: String) {
        var current = loadCachedTracks()
        current.removeAll(where: { $0.id == trackId })
        saveTracksMetadata(current)
        deleteAudio(for: trackId)
        deleteArtwork(for: trackId)
    }
    
    public func removeTracks(trackIds: Set<String>) {
        var current = loadCachedTracks()
        current.removeAll(where: { trackIds.contains($0.id) })
        saveTracksMetadata(current)
        for id in trackIds {
            deleteAudio(for: id)
            deleteArtwork(for: id)
        }
    }
    
    // MARK: - Cache Stats & Clean
    
    public func totalCacheSizeFormatted() -> String {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MusicCloud") else {
            return "0 MB"
        }
        
        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
    
    public func clearAllCache() {
        try? fileManager.removeItem(at: audioDirectory)
        try? fileManager.removeItem(at: artworkDirectory)
        try? fileManager.removeItem(at: metadataFile)
        createDirectoriesIfNeeded()
    }
}
