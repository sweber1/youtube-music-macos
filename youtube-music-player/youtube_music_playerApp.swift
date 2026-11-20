//
//  youtube_music_playerApp.swift
//  youtube-music-player
//
//  Created by Jem on 12/1/25.
//

import SwiftUI
import WebKit

@main
struct youtube_music_playerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = YouTubeMusicViewModel()
    @State private var mediaKeyHandler = MediaKeyHandler()

    var body: some Scene {
        Window("YouTube Music", id: "player") {
            ContentView(viewModel: viewModel)
                .onAppear { mediaKeyHandler.setViewModel(viewModel) }
                .onDisappear { mediaKeyHandler.clearNowPlaying() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open YouTube Music in Browser") {
                    NSWorkspace.shared.open(YouTubeMusicWebView.homeURL)
                }
            }
            CommandMenu("Navigate") {
                Button("Back") { viewModel.webView?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!viewModel.canGoBack)
                Button("Forward") { viewModel.webView?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!viewModel.canGoForward)
                Divider()
                Button("Reload") { viewModel.webView?.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(viewModel.webView == nil)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)

            }
        }
    }
}
