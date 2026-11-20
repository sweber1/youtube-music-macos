import SwiftUI
import WebKit

@Observable
@MainActor
class YouTubeMusicViewModel {
    weak var webView: WKWebView?
    var onTrackChange: ((String?, String?, URL?, Bool) -> Void)?

    func playPause() {
        clickPlayerButton("#play-pause-button")
    }

    func nextTrack() {
        clickPlayerButton(".next-button")
    }

    func previousTrack() {
        clickPlayerButton(".previous-button")
    }

    private func clickPlayerButton(_ selector: String) {
        webView?.callAsyncJavaScript(
            """
            if (location.origin === 'https://music.youtube.com') {
                document.querySelector(selector)?.click();
            }
            """,
            arguments: ["selector": selector],
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
                let lastTitle = '';
                let lastPlayState = null;

                function sendTrackInfo() {
                    const titleEl = document.querySelector('.title.ytmusic-player-bar, .title.style-scope.ytmusic-player-bar');
                    const artistEl = document.querySelector('.byline.ytmusic-player-bar a, .subtitle .byline a');
                    const imgEl = document.querySelector('.image.ytmusic-player-bar img, img.image.style-scope.ytmusic-player-bar');
                    const video = document.querySelector('video');

                    const title = titleEl?.textContent?.trim() || '';
                    const artist = artistEl?.textContent?.trim() || '';
                    const isPlaying = video ? !video.paused : false;

                    // Get larger artwork
                    let artwork = imgEl?.src || '';
                    if (artwork) {
                        artwork = artwork.replace(/=w\d+-h\d+-.*$/, '=w500-h500-l90-rj');
                        if (!artwork.includes('=w500')) {
                            artwork = artwork.replace(/=s\d+/, '=s500');
                        }
                    }

                    // Send track info when title changes
                    if (title && title !== lastTitle) {
                        lastTitle = title;
                        window.webkit.messageHandlers.trackInfo.postMessage({
                            title: title,
                            artist: artist,
                            artwork: artwork,
                            isPlaying: isPlaying
                        });
                    }

                    // Send play state when it changes
                    if (isPlaying !== lastPlayState) {
                        lastPlayState = isPlaying;
                        window.webkit.messageHandlers.trackInfo.postMessage({
                            title: title || lastTitle,
                            artist: artist,
                            artwork: artwork,
                            isPlaying: isPlaying
                        });
                    }
                }

                // Check periodically for track changes
                setInterval(sendTrackInfo, 500);

                // Also observe DOM changes
                const observer = new MutationObserver(sendTrackInfo);
                observer.observe(document.body, { childList: true, subtree: true, characterData: true });
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
        var viewModel: YouTubeMusicViewModel

        init(viewModel: YouTubeMusicViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let frame = action.targetFrame, !action.shouldPerformDownload else { return .cancel }
            return !frame.isMainFrame || allowsMainFrameURL(action.request.url) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            guard response.canShowMIMEType else { return .cancel }
            return !response.isForMainFrame || allowsMainFrameURL(response.response.url) ? .allow : .cancel
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
