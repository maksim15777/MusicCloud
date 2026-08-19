import Foundation
import AVFoundation
import MediaPlayer
import UIKit

public enum RepeatMode {
    case off
    case all
    case one
    
    public var iconName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

public final class AudioPlayerManager: NSObject, ObservableObject {
    public static let shared = AudioPlayerManager()
    
    // MARK: - Published State
    @Published public var currentTrack: Track?
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var playbackProgress: Double = 0.0 // 0.0 ... 1.0
    @Published public var isBuffering: Bool = false
    @Published public var repeatMode: RepeatMode = .off
    @Published public var isShuffled: Bool = false
    @Published public var playlist: [Track] = []
    
    // MARK: - Private Engine Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var originalPlaylist: [Track] = []
    private var isUserSeeking: Bool = false
    
    override private init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        setupNotificationObservers()
    }
    
    deinit {
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - AVAudioSession Setup
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("[AudioPlayerManager] AVAudioSession error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Remote Command Center (Lock Screen / Headphones)
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.resume()
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        // Toggle Play / Pause (Headphones button single-click)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        
        // Next Track (Headphones double-click)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.next()
            return .success
        }
        
        // Previous Track (Headphones triple-click)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.previous()
            return .success
        }
        
        // Scrubber / Seek on Lock Screen
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }
    
    // MARK: - Now Playing Info Center (Lock Screen Widget)
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.performer
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "MusicCloud"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // Artwork
        if let artwork = CacheManager.shared.cachedArtwork(for: track.id) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                return artwork
            }
        } else {
            // Default styled placeholder artwork
            let placeholderArtwork = generatePlaceholderArtwork(title: track.title, artist: track.performer)
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: placeholderArtwork.size) { _ in
                return placeholderArtwork
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func generatePlaceholderArtwork(title: String, artist: String) -> UIImage {
        let size = CGSize(width: 500, height: 500)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Dark elegant gradient background
            let colors = [
                UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor,
                UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0).cgColor
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            
            // Music Note Icon
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 140, weight: .light)
            if let icon = UIImage(systemName: "music.note", withConfiguration: iconConfig)?
                .withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                let iconRect = CGRect(x: (size.width - icon.size.width) / 2, y: 120, width: icon.size.width, height: icon.size.height)
                icon.draw(in: iconRect)
            }
            
            // Text attributes
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let artistAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.lightGray
            ]
            
            let titleRect = CGRect(x: 30, y: 340, width: 440, height: 40)
            let artistRect = CGRect(x: 30, y: 390, width: 440, height: 35)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byTruncatingTail
            
            var tAttrs = titleAttributes
            tAttrs[.paragraphStyle] = paragraphStyle
            var aAttrs = artistAttributes
            aAttrs[.paragraphStyle] = paragraphStyle
            
            (title as NSString).draw(in: titleRect, withAttributes: tAttrs)
            (artist as NSString).draw(in: artistRect, withAttributes: aAttrs)
        }
    }
    
    // MARK: - Notifications (Interruptions, Route Changes, End of Track)
    
    private func setupNotificationObservers() {
        // Interruption (Phone calls, Siri)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // Route change (Headphones unplugged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            DispatchQueue.main.async {
                self.pause()
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    DispatchQueue.main.async {
                        self.resume()
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        if reason == .oldDeviceUnavailable {
            // Headphones or bluetooth device disconnected -> auto pause
            DispatchQueue.main.async {
                self.pause()
            }
        }
    }
    
    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        DispatchQueue.main.async {
            switch self.repeatMode {
            case .one:
                self.seek(to: 0)
                self.resume()
            case .all:
                self.next()
            case .off:
                if self.isLastTrack {
                    self.pause()
                    self.seek(to: 0)
                } else {
                    self.next()
                }
            }
        }
    }
    
    // MARK: - Playback Control Methods
    
    public func play(track: Track, in newPlaylist: [Track]) {
        self.originalPlaylist = newPlaylist
        if isShuffled {
            var shuffled = newPlaylist.filter { $0.id != track.id }
            shuffled.shuffle()
            self.playlist = [track] + shuffled
        } else {
            self.playlist = newPlaylist
        }
        
        loadAndPlay(track: track)
    }
    
    public func togglePlayPause(for track: Track, in newPlaylist: [Track]) {
        if currentTrack?.id == track.id {
            togglePlayPause()
        } else {
            play(track: track, in: newPlaylist)
        }
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    public func resume() {
        guard let player = player else {
            if let first = playlist.first {
                loadAndPlay(track: first)
            }
            return
        }
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    public func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    public func next() {
        guard !playlist.isEmpty, let current = currentTrack else { return }
        if let currentIndex = playlist.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = (currentIndex + 1) % playlist.count
            loadAndPlay(track: playlist[nextIndex])
        }
    }
    
    public func previous() {
        guard !playlist.isEmpty, let current = currentTrack else { return }
        
        // If played more than 3 seconds, previous restarts the current track
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        
        if let currentIndex = playlist.firstIndex(where: { $0.id == current.id }) {
            let prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
            loadAndPlay(track: playlist[prevIndex])
        }
    }
    
    public func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let targetTime = CMTime(seconds: max(0, min(time, duration)), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = time
            self.playbackProgress = self.duration > 0 ? (time / self.duration) : 0
            self.updateNowPlayingInfo()
        }
    }
    
    public func seek(progress: Double) {
        let targetSeconds = duration * max(0.0, min(progress, 1.0))
        seek(to: targetSeconds)
    }
    
    public func toggleShuffle() {
        isShuffled.toggle()
        guard let current = currentTrack else { return }
        if isShuffled {
            var shuffled = originalPlaylist.filter { $0.id != current.id }
            shuffled.shuffle()
            playlist = [current] + shuffled
        } else {
            playlist = originalPlaylist
        }
    }
    
    public func toggleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
    
    // MARK: - Internal Player Loading
    
    private func loadAndPlay(track: Track) {
        currentTrack = track
        currentTime = 0
        duration = track.duration
        playbackProgress = 0
        isBuffering = true
        
        removeTimeObserver()
        
        // Determine audio URL (local cache or remote)
        guard let url = track.localFileURL ?? CacheManager.shared.cachedAudioURL(for: track.id) else {
            print("[AudioPlayerManager] No local audio file URL for track: \(track.title)")
            isBuffering = false
            return
        }
        
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        playerItem = AVPlayerItem(url: url)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
            player?.automaticallyWaitsToMinimizeStalling = false
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        addPeriodicTimeObserver()
        
        player?.play()
        isPlaying = true
        isBuffering = false
        
        // Fetch accurate duration from asset if available
        Task {
            let asset = AVURLAsset(url: url)
            if let assetDuration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(assetDuration)
                if seconds > 0 && !seconds.isNaN {
                    await MainActor.run {
                        self.duration = seconds
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
        
        updateNowPlayingInfo()
    }
    
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isUserSeeking else { return }
            let currentSeconds = CMTimeGetSeconds(time)
            if !currentSeconds.isNaN {
                self.currentTime = currentSeconds
                if self.duration > 0 {
                    self.playbackProgress = currentSeconds / self.duration
                }
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    private var isLastTrack: Bool {
        guard let current = currentTrack, let last = playlist.last else { return false }
        return current.id == last.id
    }
}
