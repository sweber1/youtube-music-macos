import SwiftUI

struct MenuBarPlayer: View {
    let player: YouTubeMusicViewModel
    let playlists: PinnedPlaylists
    @Environment(\.openWindow) private var openWindow

    private let playTint = Color(red: 0.79, green: 0.14, blue: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                artworkTile(player.mediaKeys.artwork, symbol: "music.note", size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.trackTitle ?? "YouTube Music")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let artist = player.trackArtist {
                        Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    } else if player.trackTitle == nil {
                        Text("Nothing playing").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 20) {
                transportButton("Previous", symbol: "backward.fill", action: player.previousTrack)
                Button(action: player.playPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(playTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                transportButton("Next", symbol: "forward.fill", action: player.nextTrack)
            }
            .frame(maxWidth: .infinity)
            .disabled(player.trackTitle == nil && !player.isPlaying)
            .opacity(player.trackTitle == nil && !player.isPlaying ? 0.45 : 1)

            if !playlists.items.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinned Playlists")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    ForEach(playlists.items) { pin in
                        PlaylistPinRow(pin: pin, player: player) {
                            if player.webView.window == nil { openPlayer() }
                            player.playPlaylist(pin, in: playlists)
                        }
                    }
                    if let error = player.playlistError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack {
                Button(action: openPlayer) {
                    Label("Open Player", systemImage: "macwindow")
                }
                .buttonStyle(.borderless)

                Spacer()

                SettingsLink {
                    if playlists.items.isEmpty {
                        Label("Pin Playlists", systemImage: "plus")
                    } else {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Edit Pinned Playlists")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 308)
    }

    private func openPlayer() {
        if let window = player.webView.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "player")
        }
        NSApp.activate()
    }

    private func transportButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct PlaylistPinRow: View {
    let pin: PinnedPlaylist
    let player: YouTubeMusicViewModel
    let action: () -> Void
    @State private var cover: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                artworkTile(cover, symbol: "music.note.list", size: 28)
                Text(pin.name).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                if player.startingPlaylistID == pin.id {
                    ProgressView().controlSize(.small).accessibilityLabel("Starting playlist")
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(pin.name) from the beginning")
        .onHover { hovering = $0 }
        .task(id: pin.artworkURL) {
            cover = nil
            if let url = pin.artworkURL { cover = await player.mediaKeys.fetchArtwork(from: url) }
        }
    }
}

private func artworkTile(_ image: NSImage?, symbol: String, size: CGFloat) -> some View {
    Group {
        if let image {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: size, height: size)
    .background(Color.primary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    .accessibilityHidden(true)
}
