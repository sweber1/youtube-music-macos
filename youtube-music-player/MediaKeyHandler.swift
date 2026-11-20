import Foundation
import MediaPlayer
import AppKit

@Observable
@MainActor
class MediaKeyHandler {
    private var viewModel: YouTubeMusicViewModel?
    private var artworkURL: URL?
    private var artworkTask: Task<Void, Never>?
    private let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: ArtworkRedirectBlocker(), delegateQueue: nil)
    }()

    init() {
        setupRemoteCommandCenter()
    }

    func setViewModel(_ viewModel: YouTubeMusicViewModel) {
        self.viewModel = viewModel
        viewModel.onTrackChange = { [weak self] title, artist, artworkUrl, isPlaying in
            self?.updateNowPlaying(title: title, artist: artist, artworkUrl: artworkUrl, isPlaying: isPlaying)
        }
    }

    private func updateNowPlaying(title: String?, artist: String?, artworkUrl: URL?, isPlaying: Bool) {
        guard let title, !title.isEmpty else {
            clearNowPlaying()
            return
        }

        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = nowPlayingCenter.nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist ?? ""
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        let newArtworkURL = artworkUrl.flatMap { Self.isAllowedArtworkURL($0) ? $0 : nil }
        let artworkChanged = newArtworkURL != artworkURL
        if artworkChanged {
            artworkTask?.cancel()
            artworkURL = newArtworkURL
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
        nowPlayingCenter.playbackState = isPlaying ? .playing : .paused

        guard artworkChanged, let newArtworkURL else { return }
        artworkTask = Task { [weak self, artworkSession] in
            guard let data = try? await Self.loadArtwork(from: newArtworkURL, session: artworkSession),
                  !Task.isCancelled, self?.artworkURL == newArtworkURL,
                  let image = NSImage(data: data) else { return }

            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updatedInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
        }
    }

    func clearNowPlaying() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkURL = nil
        let nowPlayingCenter = MPNowPlayingInfoCenter.default()
        nowPlayingCenter.nowPlayingInfo = nil
        nowPlayingCenter.playbackState = .stopped
    }

    private static func isAllowedArtworkURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.port == nil || url.port == 443,
              url.user() == nil, url.password() == nil else { return false }
        switch url.host() {
        case "lh3.googleusercontent.com", "lh4.googleusercontent.com", "lh5.googleusercontent.com",
             "lh6.googleusercontent.com", "i.ytimg.com", "yt3.googleusercontent.com", "yt3.ggpht.com":
            return true
        default:
            return false
        }
    }

    nonisolated private static func loadArtwork(from url: URL, session: URLSession) async throws -> Data? {
        let sizeLimit = 2 * 1024 * 1024
        let (bytes, response) = try await session.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              httpResponse.mimeType?.hasPrefix("image/") == true,
              httpResponse.expectedContentLength <= Int64(sizeLimit) else { return nil }

        var data = Data()
        for try await byte in bytes {
            guard data.count < sizeLimit else { return nil }
            data.append(byte)
        }
        return data
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.playPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.nextTrack()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.previousTrack()
            }
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
    }
}

private final class ArtworkRedirectBlocker: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                                completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
