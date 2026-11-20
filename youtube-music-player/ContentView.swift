//
//  ContentView.swift
//  youtube-music-player
//
//  Created by Jem on 12/1/25.
//

import SwiftUI

struct ContentView: View {
    let viewModel: YouTubeMusicViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Window header for dragging
            WindowHeader()
                .frame(height: 32)

            YouTubeMusicWebView(viewModel: viewModel)
                .overlay {
                    if let error = viewModel.navigationError {
                        ContentUnavailableView {
                            Label("YouTube Music", systemImage: "exclamationmark.circle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Return to YouTube Music") { viewModel.goHome() }
                                .buttonStyle(.borderedProminent)
                            Button("Open in Browser") { NSWorkspace.shared.open(YouTubeMusicWebView.homeURL) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
        }
        .ignoresSafeArea()
    }
}

struct WindowHeader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableHeaderView()
        view.wantsLayer = true
        // Match YouTube Music's dark header (#212121)
        view.layer?.backgroundColor = NSColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1.0).cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggableHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

#Preview {
    ContentView(viewModel: YouTubeMusicViewModel())
}
