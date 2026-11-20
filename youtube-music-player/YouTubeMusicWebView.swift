import SwiftUI
import WebKit

@Observable
@MainActor
class YouTubeMusicViewModel {
    weak var webView: WKWebView?
    var canGoBack = false
    var canGoForward = false
    var onTrackChange: ((String?, String?, URL?, Bool) -> Void)?

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
        webView?.callAsyncJavaScript(
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

    func makeNSView(context: Context) -> WKWebView {
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
        config.userContentController.add(context.coordinator, contentWorld: Self.playerContentWorld, name: "trackInfo")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // YouTube Music rejects the default WKWebView user agent.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        viewModel.webView = webView
        context.coordinator.observeHistory(in: webView)
        webView.load(URLRequest(url: Self.homeURL))

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    private static func allowsMainFrameURL(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host(),
              url.port == nil || url.port == 443,
              url.user() == nil, url.password() == nil else { return false }
        // Google returns to this endpoint before redirecting to YouTube Music.
        if host == "www.youtube.com" { return url.path == "/signin" }
        return allowedHosts.contains(host)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let viewModel: YouTubeMusicViewModel
        private var historyObservations: [NSKeyValueObservation] = []

        init(viewModel: YouTubeMusicViewModel) {
            self.viewModel = viewModel
        }

        func observeHistory(in webView: WKWebView) {
            historyObservations = [\WKWebView.canGoBack, \WKWebView.canGoForward].map { keyPath in
                webView.observe(keyPath, options: [.initial, .new]) { [weak self] observedView, _ in
                    Task { @MainActor [weak self, weak observedView] in
                        guard let self, let observedView, self.viewModel.webView === observedView else { return }
                        self.viewModel.canGoBack = observedView.canGoBack
                        self.viewModel.canGoForward = observedView.canGoForward
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let frame = action.targetFrame, !action.shouldPerformDownload else { return .cancel }
            return !frame.isMainFrame || allowsMainFrameURL(action.request.url) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            guard response.canShowMIMEType else { return .cancel }
            return !response.isForMainFrame || allowsMainFrameURL(response.response.url) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel.onTrackChange?(nil, nil, nil, false)
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
            viewModel.onTrackChange?(title, artist, artworkURL, isPlaying)
        }
    }
}
