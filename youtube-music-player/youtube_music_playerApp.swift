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
    @State private var playlists = PinnedPlaylists()

    var body: some Scene {
        Window("YouTube Music", id: "player") {
            ContentView(viewModel: viewModel)
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
                Button("Back") { viewModel.webView.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!viewModel.canGoBack)
                Button("Forward") { viewModel.webView.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!viewModel.canGoForward)
                Divider()
                Button("Home") { viewModel.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Reload") { viewModel.webView.reload() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra("YouTube Music", systemImage: "play.circle") {
            MenuBarPlayer(player: viewModel, playlists: playlists)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PlaylistSettingsView(store: playlists)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "player" }) {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}
