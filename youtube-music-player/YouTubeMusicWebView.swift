import SwiftUI
import WebKit

@Observable
@MainActor
class YouTubeMusicViewModel {
    @ObservationIgnored lazy var webView = YouTubeMusicWebView.makePlayer(for: self)
    let mediaKeys = MediaKeyHandler()
    var canGoBack = false
    var canGoForward = false
    var navigationError: String?
    var onTrackChange: ((String?, String?, URL?, Bool) -> Void)?
    private(set) var trackTitle: String?
    private(set) var trackArtist: String?
    private(set) var isPlaying = false
    private(set) var startingPlaylistID: String?
    private(set) var playlistError: String?
    @ObservationIgnored private var playlistTask: Task<Void, Never>?

    init() {
        mediaKeys.setViewModel(self)
    }

    func goHome() {
        navigationError = nil
        webView.load(URLRequest(url: YouTubeMusicWebView.homeURL))
    }

    func updateTrack(title: String?, artist: String?, artwork: URL?, playing: Bool) {
        trackTitle = title.flatMap { $0.isEmpty ? nil : $0 }
        trackArtist = artist.flatMap { $0.isEmpty ? nil : $0 }
        isPlaying = playing
        onTrackChange?(trackTitle, trackArtist, artwork, playing)
    }

    func playPlaylist(_ playlist: PinnedPlaylist, in store: PinnedPlaylists) {
        playlistTask?.cancel()
        let player = webView
        startingPlaylistID = playlist.id
        playlistError = nil
        navigationError = nil
        player.load(URLRequest(url: playlist.url))

        playlistTask = Task { [weak self] in
            do {
                for _ in 0..<40 {
                    try await Task.sleep(for: .milliseconds(250))
                    guard !player.isLoading, player.url?.path() == "/playlist" else { continue }
                    let result = try await player.callAsyncJavaScript(
                        Self.startPlaylistScript,
                        arguments: ["playlistID": playlist.id],
                        in: nil,
                        contentWorld: YouTubeMusicWebView.playerContentWorld
                    )
                    try Task.checkCancellation()
                    guard let result = result as? [String: Any] else { continue }
                    if let cover = result["artwork"] as? String, let url = URL(string: cover) {
                        store.updateArtwork(url, for: playlist.id)
                    }
                    self?.startingPlaylistID = nil
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
            }
            self?.startingPlaylistID = nil
            self?.playlistError = "Couldn’t start the playlist. Open the player to check access."
        }
    }

    private static let startPlaylistScript = #"""
        const page = new URL(location.href);
        if (page.origin !== 'https://music.youtube.com' || page.pathname !== '/playlist' ||
            page.searchParams.get('list') !== playlistID) return null;

        const shelf = document.querySelector('ytmusic-playlist-shelf-renderer');
        const rows = shelf?.querySelectorAll('ytmusic-responsive-list-item-renderer') ?? [];
        for (const row of rows) {
            if (row.hasAttribute('is-unplayable') || row.getAttribute('aria-disabled') === 'true') continue;
            const link = row.querySelector('a[href*="watch?"]');
            if (!link) continue;
            const target = new URL(link.href);
            if (target.origin !== page.origin || target.pathname !== '/watch' ||
                target.searchParams.get('list') !== playlistID) continue;
            const image = document.querySelector(
                'ytmusic-responsive-header-renderer ytmusic-thumbnail-renderer img, ' +
                'ytmusic-detail-header-renderer ytmusic-thumbnail-renderer img'
            );
            link.click();
            return { artwork: image?.currentSrc || image?.src || '' };
        }
        return null;
        """#

    func play() {
        clickPlayerButton("#play-pause-button", playing: true)
    }

    func pause() {
        clickPlayerButton("#play-pause-button", playing: false)
    }

    func playPause() {
        clickPlayerButton("#play-pause-button")
    }

    func nextTrack() {
        clickPlayerButton(".next-button")
    }

    func previousTrack() {
        clickPlayerButton(".previous-button")
    }

    private func clickPlayerButton(_ selector: String, playing: Bool? = nil) {
        webView.callAsyncJavaScript(
            """
            if (location.origin !== 'https://music.youtube.com') return;
            if (playing !== null) {
                const video = document.querySelector('video');
                if (!video || (!video.paused && !video.ended) === playing) return;
            }
            document.querySelector(selector)?.click();
            """,
            arguments: ["selector": selector, "playing": playing as Any? ?? NSNull()],
            in: nil,
            in: YouTubeMusicWebView.playerContentWorld,
            completionHandler: nil
        )
    }
}

struct YouTubeMusicWebView: NSViewRepresentable {
    static let homeURL = URL(string: "https://music.youtube.com")!
    static let playerContentWorld = WKContentWorld.world(name: "YouTubeMusicPlayer")
    private static let allowedHosts: Set<String> = [
        "music.youtube.com", "accounts.google.com", "consent.youtube.com", "consent.google.com"
    ]

    var viewModel: YouTubeMusicViewModel

    func makeNSView(context: Context) -> NSView {
        PlayerHostView(player: viewModel.webView)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func makePlayer(for viewModel: YouTubeMusicViewModel) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Inject scrollbar CSS at document start
        let css = """
            *, *::before, *::after {
                scrollbar-width: thin !important;
                scrollbar-color: rgba(255,255,255,0.15) transparent !important;
            }
            ::-webkit-scrollbar {
                width: 14px !important;
                height: 14px !important;
            }
            ::-webkit-scrollbar-track {
                background: transparent !important;
            }
            ::-webkit-scrollbar-thumb {
                background: rgba(255, 255, 255, 0.15) !important;
                border-radius: 100px !important;
                border-right: 3px solid transparent !important;
                background-clip: padding-box !important;
            }
            ::-webkit-scrollbar-thumb:hover {
                background: rgba(255, 255, 255, 0.25) !important;
                border-right: 3px solid transparent !important;
                background-clip: padding-box !important;
            }
            ::-webkit-scrollbar-corner {
                background: transparent !important;
            }
        """
        let cssJs = """
            (function() {
                if (location.origin !== 'https://music.youtube.com') return;
                var style = document.createElement('style');
                style.textContent = `\(css)`;
                document.documentElement.appendChild(style);
            })();
        """
        let cssScript = WKUserScript(source: cssJs, injectionTime: .atDocumentStart,
                                     forMainFrameOnly: true, in: Self.playerContentWorld)
        config.userContentController.addUserScript(cssScript)

        // Track info observer script
        let trackObserverJs = #"""
            (function() {
                if (location.origin !== 'https://music.youtube.com') return;
                let player;
                let lastTrack;
                let updateTimer;

                function sendTrackInfo() {
                    updateTimer = undefined;
                    const titleEl = player?.querySelector('.title.ytmusic-player-bar');
                    const artistEl = player?.querySelector('.byline.ytmusic-player-bar a, .subtitle .byline a');
                    const imgEl = player?.querySelector('.image.ytmusic-player-bar img, img.image.style-scope.ytmusic-player-bar');
                    const video = document.querySelector('video');

                    const title = titleEl?.textContent?.trim() || '';
                    const artist = artistEl?.textContent?.trim() || '';
                    const isPlaying = video ? !video.paused && !video.ended : false;

                    // Get larger artwork
                    let artwork = imgEl?.currentSrc || imgEl?.src || '';
                    if (artwork) {
                        artwork = artwork.replace(/=w\d+-h\d+-.*$/, '=w500-h500-l90-rj');
                        if (!artwork.includes('=w500')) {
                            artwork = artwork.replace(/=s\d+/, '=s500');
                        }
                    }

                    if (lastTrack && title === lastTrack.title && artist === lastTrack.artist &&
                        artwork === lastTrack.artwork && isPlaying === lastTrack.isPlaying) return;
                    lastTrack = { title, artist, artwork, isPlaying };
                    window.webkit.messageHandlers.trackInfo.postMessage(lastTrack);
                }

                function scheduleUpdate() {
                    if (updateTimer === undefined) updateTimer = setTimeout(sendTrackInfo, 50);
                }

                const playerObserver = new MutationObserver(scheduleUpdate);
                const playerDiscovery = new MutationObserver(attachPlayer);
                function attachPlayer() {
                    player = document.querySelector('ytmusic-player-bar');
                    if (!player) return;
                    playerDiscovery.disconnect();
                    playerObserver.observe(player, {
                        childList: true, subtree: true, characterData: true, attributeFilter: ['src', 'srcset']
                    });
                    scheduleUpdate();
                }

                for (const event of ['play', 'pause', 'ended', 'loadedmetadata', 'emptied']) {
                    document.addEventListener(event, scheduleUpdate, true);
                }
                playerDiscovery.observe(document.body, { childList: true, subtree: true });
                attachPlayer();
            })();
        """#
        let trackScript = WKUserScript(source: trackObserverJs, injectionTime: .atDocumentEnd,
                                       forMainFrameOnly: true, in: Self.playerContentWorld)
        config.userContentController.addUserScript(trackScript)
        let coordinator = PlayerDelegate(viewModel: viewModel)
        config.userContentController.add(coordinator, contentWorld: Self.playerContentWorld, name: "trackInfo")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        // YouTube Music rejects the default WKWebView user agent.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        coordinator.observeHistory(in: webView)
        webView.load(URLRequest(url: Self.homeURL))

        return webView
    }

    static func allowsMainFrameURL(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host(),
              url.port == nil || url.port == 443,
              url.user() == nil, url.password() == nil else { return false }
        switch host {
        case "accounts.youtube.com":
            return url.path(percentEncoded: true) == "/accounts/SetSID"
        case "www.youtube.com":
            return url.path(percentEncoded: true) == "/signin"
        default:
            return allowedHosts.contains(host)
        }
    }

    private final class PlayerDelegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private weak var viewModel: YouTubeMusicViewModel?
        private var historyObservations: [NSKeyValueObservation] = []
        private weak var currentNavigation: WKNavigation?

        init(viewModel: YouTubeMusicViewModel) {
            self.viewModel = viewModel
        }

        func observeHistory(in webView: WKWebView) {
            historyObservations = [\WKWebView.canGoBack, \WKWebView.canGoForward].map { keyPath in
                webView.observe(keyPath, options: [.initial, .new]) { [weak self] observedView, _ in
                    Task { @MainActor [weak self, weak observedView] in
                        guard let observedView else { return }
                        self?.viewModel?.canGoBack = observedView.canGoBack
                        self?.viewModel?.canGoForward = observedView.canGoForward
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let frame = action.targetFrame, !action.shouldPerformDownload else { return .cancel }
            guard frame.isMainFrame else { return .allow }
            if allowsMainFrameURL(action.request.url) { return .allow }
            showBlockedSignInIfNeeded(in: webView)
            return .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            guard response.canShowMIMEType else { return .cancel }
            guard response.isForMainFrame else { return .allow }
            if allowsMainFrameURL(response.response.url) { return .allow }
            showBlockedSignInIfNeeded(in: webView)
            return .cancel
        }

        private func showBlockedSignInIfNeeded(in webView: WKWebView) {
            guard let url = webView.backForwardList.currentItem?.url,
                  allowsMainFrameURL(url), url.host() != homeURL.host() else { return }
            viewModel?.navigationError = "The sign-in page could not return to YouTube Music."
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            currentNavigation = navigation
            viewModel?.navigationError = nil
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel?.updateTrack(title: nil, artist: nil, artwork: nil, playing: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showLoadFailure(for: navigation, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showLoadFailure(for: navigation, error: error)
        }

        private func showLoadFailure(for navigation: WKNavigation?, error: Error) {
            guard let navigation, currentNavigation === navigation, viewModel?.navigationError == nil,
                  (error as? URLError)?.code != .cancelled else { return }
            viewModel?.navigationError = "The page could not be loaded."
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            viewModel?.updateTrack(title: nil, artist: nil, artwork: nil, playing: false)
            viewModel?.navigationError = "The player stopped responding."
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let origin = message.frameInfo.securityOrigin
            guard message.name == "trackInfo", message.frameInfo.isMainFrame,
                  origin.`protocol` == "https", origin.host == "music.youtube.com",
                  origin.port == 0 || origin.port == 443,
                  let body = message.body as? [String: Any] else { return }

            let title = body["title"] as? String
            let artist = body["artist"] as? String
            let artworkURL = (body["artwork"] as? String).flatMap { URL(string: $0) }
            let isPlaying = body["isPlaying"] as? Bool ?? false
            viewModel?.updateTrack(title: title, artist: artist, artwork: artworkURL, playing: isPlaying)
        }
    }
}

private final class PlayerHostView: NSView {
    private let closeDelegate = KeepPlayerWindowDelegate()

    init(player: WKWebView) {
        super.init(frame: .zero)
        player.translatesAutoresizingMaskIntoConstraints = false
        addSubview(player)
        NSLayoutConstraint.activate([
            player.leadingAnchor.constraint(equalTo: leadingAnchor),
            player.trailingAnchor.constraint(equalTo: trailingAnchor),
            player.topAnchor.constraint(equalTo: topAnchor),
            player.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  window.delegate !== self.closeDelegate else { return }
            self.closeDelegate.original = window.delegate
            window.delegate = self.closeDelegate
        }
    }
}

private final class KeepPlayerWindowDelegate: NSObject, NSWindowDelegate {
    weak var original: (any NSWindowDelegate)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Keep the WebKit view attached so it can start another track in the background.
        sender.orderOut(nil)
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
