import SwiftUI
import AppKit
import AVFoundation
import MediaPlayer

enum RepeatMode: Int {
    case off, all, one
}

struct Song: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String
    var artwork: NSImage?

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

class AudioEngine: ObservableObject {
    @Published var playlist: [Song] = []
    @Published var currentIndex: Int? = nil {
        didSet {
            if let index = currentIndex, playlist.indices.contains(index) {
                playSong(playlist[index])
            }
        }
    }
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var duration: Double = 1.0

    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffle = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObserver: NSObjectProtocol?

    var currentSong: Song? {
        guard let index = currentIndex, playlist.indices.contains(index) else { return nil }
        return playlist[index]
    }

    init() {
        setupRemoteTransportControls()
    }

    deinit {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func addFiles(urls: [URL]) {
        Task {
            var loadedSongs: [(url: URL, title: String, artist: String, artworkData: Data?)] = []

            for url in urls {
                let asset = AVURLAsset(url: url)
                var title = url.deletingPathExtension().lastPathComponent
                var artist = "Artiste Inconnu"
                var artworkData: Data? = nil

                do {
                    let metadata = try await asset.load(.metadata)
                    for item in metadata {
                        guard let commonKey = item.commonKey?.rawValue else { continue }
                        if commonKey == "title", let val = try? await item.load(.stringValue) {
                            title = val
                        } else if commonKey == "artist", let val = try? await item.load(.stringValue) {
                            artist = val
                        } else if commonKey == "artwork", let data = try? await item.load(.dataValue) {
                            artworkData = data
                        }
                    }
                } catch {}

                loadedSongs.append((url, title, artist, artworkData))
            }

            let newSongs = loadedSongs.map { item in
                Song(
                    url: item.url,
                    title: item.title,
                    artist: item.artist,
                    artwork: item.artworkData.flatMap { NSImage(data: $0) }
                )
            }

            await MainActor.run {
                let wasEmpty = self.playlist.isEmpty
                self.playlist.append(contentsOf: newSongs)
                if wasEmpty, !self.playlist.isEmpty {
                    self.currentIndex = 0
                }
            }
        }
    }

    func playSong(_ song: Song) {
        // Nettoyage des observateurs précédents
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        let asset = AVURLAsset(url: song.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let playerItem = AVPlayerItem(asset: asset)

        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.seek(to: .zero)
            player?.replaceCurrentItem(with: playerItem)
        }

        player?.play()
        isPlaying = true

        setupPlayerItemObserver(for: playerItem)

        Task {
            let finalDuration: Double

            do {
                let durationTime = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(durationTime)

                print("🎵 File:", song.url.lastPathComponent)
                print("🎵 Reported duration:", seconds)

                if durationTime.isNumeric,
                   seconds.isFinite,
                   seconds > 0 {
                    finalDuration = seconds
                } else {
                    finalDuration = 1.0
                }
            } catch {
                finalDuration = 1.0
            }

            await MainActor.run {
                self.duration = finalDuration
                self.updateNowPlayingInfo()
            }

        }

        setupTimeObserver()
        updateNowPlayingInfo()
    }

    private func setupPlayerItemObserver(for item: AVPlayerItem) {
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackFinished()
        }
    }

    private func handleTrackFinished() {
        switch repeatMode {
        case .one:
            if let song = currentSong {
                playSong(song)
            }
        case .all:
            if isShuffle {
                playRandTrack()
            } else {
                guard let index = currentIndex else { return }
                if index + 1 < playlist.count {
                    currentIndex = index + 1
                } else {
                    currentIndex = 0 // Boucle au début
                }
            }
        case .off:
            if isShuffle {
                playRandTrack()
            } else {
                guard let index = currentIndex else { return }
                if index + 1 < playlist.count {
                    currentIndex = index + 1
                } else {
                    isPlaying = false
                }
            }
        }
    }

    private func playRandTrack() {
        guard !playlist.isEmpty else { return }
        if playlist.count == 1 {
            currentIndex = 0
            return
        }
        var nextIndex = Int.random(in: 0..<playlist.count)
        if nextIndex == currentIndex {
            nextIndex = (nextIndex + 1) % playlist.count
        }
        currentIndex = nextIndex
    }


    private func setupTimeObserver() {
        let interval = CMTime(
            seconds: 1,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }

            let currentTime = CMTimeGetSeconds(time)

            if time.isNumeric, currentTime.isFinite {
                self.progress = max(
                    0,
                    min(currentTime, self.duration)
                )

                var nowPlayingInfo =
                    MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

                nowPlayingInfo[
                    MPNowPlayingInfoPropertyElapsedPlaybackTime
                ] = self.progress

                MPNowPlayingInfoCenter.default().nowPlayingInfo =
                    nowPlayingInfo
            }
        }
    }


    func togglePlayPause() {
        guard let player = player else {
            if let index = currentIndex {
                playSong(playlist[index])
            } else if !playlist.isEmpty {
                currentIndex = 0
            }
            return
        }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        let targetTime = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: targetTime)
    }

    func skipNext() {
        guard !playlist.isEmpty else { return }
        if isShuffle {
            playRandTrack()
        } else {
            guard let index = currentIndex else {
                currentIndex = 0
                return
            }
            if index + 1 < playlist.count {
                currentIndex = index + 1
            } else {
                currentIndex = 0
            }
        }
    }

    func skipPrevious() {
        guard !playlist.isEmpty else { return }
        guard let index = currentIndex else {
            currentIndex = 0
            return
        }
        if index > 0 {
            currentIndex = index - 1
        } else {
            currentIndex = playlist.count - 1
        }
    }

    func toggleShuffle() {
        isShuffle.toggle()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                if self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in self.skipNext() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in self.skipPrevious() }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentSong?.title ?? "AmberolMac"
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentSong?.artist ?? "Artiste Inconnu"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let artwork = currentSong?.artwork {
            let artworkObj = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkObj
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

struct ContentView: View {
    @StateObject private var engine = AudioEngine()
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if let art = engine.currentSong?.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 40)
                    .opacity(0.5)
            } else {
                LinearGradient(colors: [.black, Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)
            }

            HStack(spacing: 0) {
                // Playlist à gauche
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    List(Array(engine.playlist.enumerated()), id: \.offset) { index, song in
                        HStack(spacing: 10) {
                            if let art = song.artwork {
                                Image(nsImage: art)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "music.note").font(.system(size: 12)))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.system(size: 12, weight: index == engine.currentIndex ? .bold : .medium))
                                    .foregroundColor(index == engine.currentIndex ? .accentColor : .primary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            engine.currentIndex = index
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                .frame(width: 240, height: 500)
                .background(Color.black.opacity(0.25))

                Divider().background(Color.white.opacity(0.15))

                // Lecteur principal à droite
                VStack(spacing: 16) {
                    Spacer()

                    ZStack {
                        if let art = engine.currentSong?.artwork {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(14)
                                .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 6)
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 50))
                                        .foregroundColor(.white.opacity(0.4))
                                )
                        }
                    }
                    .frame(width: 180, height: 180)

                    VStack(spacing: 4) {
                        Text(engine.currentSong?.title ?? "Aucune piste")
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)

                        Text(engine.currentSong?.artist ?? "Glisse des fichiers ici")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { engine.progress },
                            set: { newValue in engine.seek(to: newValue) }
                        ), in: 0...(engine.duration > 0 ? engine.duration : 1.0))
                        .accentColor(.white)

                        HStack {
                            Text(formatTime(engine.progress))
                            Spacer()
                            Text(formatTime(engine.duration))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 24)

                    // Commandes principales de lecture
                    HStack(spacing: 24) {
                        Button(action: { engine.skipPrevious() }) {
                            Image(systemName: "backward.fill").font(.system(size: 18))
                        }
                        .buttonStyle(.plain)

                        Button(action: { engine.togglePlayPause() }) {
                            Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: { engine.skipNext() }) {
                            Image(systemName: "forward.fill").font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                    }

                    // Boutons QoL en bas (Shuffle & Repeat inspirés d'Amberol)
                    HStack(spacing: 20) {
                        Button(action: { engine.toggleShuffle() }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(engine.isShuffle ? .accentColor : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        Button(action: { engine.cycleRepeatMode() }) {
                            Image(systemName: repeatIconName(for: engine.repeatMode))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(engine.repeatMode != .off ? .accentColor : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 8)

                    Spacer()
                }
                .frame(width: 320, height: 500)
            }
        }
        .frame(width: 560, height: 500)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()

            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url { urls.append(url) }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if !urls.isEmpty {
                    engine.addFiles(urls: urls)
                }
            }
            return true
        }
    }

    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func repeatIconName(for mode: RepeatMode) -> String {
        switch mode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

@main
struct AmberolMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
