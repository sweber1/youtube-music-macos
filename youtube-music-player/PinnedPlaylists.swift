import SwiftUI

struct PinnedPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    var artworkURL: URL?

    var url: URL {
        URL(string: "https://music.youtube.com/playlist?list=\(id)")!
    }

    static func id(from link: String) -> String? {
        guard let parts = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host,
              ["music.youtube.com", "www.youtube.com", "youtube.com"].contains(host),
              parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil,
              parts.path == "/playlist" || parts.path == "/watch",
              let id = parts.queryItems?.first(where: { $0.name == "list" })?.value,
              isValidID(id) else { return nil }
        return id
    }

    static func isValidID(_ id: String) -> Bool {
        id.wholeMatch(of: #/[A-Za-z0-9_-]{2,128}/#) != nil
    }
}

@Observable
final class PinnedPlaylists {
    static let limit = 4
    private static let storageKey = "pinnedPlaylists"
    private(set) var items: [PinnedPlaylist] = []

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([PinnedPlaylist].self, from: data) else { return }
        items = Array(saved.filter { PinnedPlaylist.isValidID($0.id) }.prefix(Self.limit))
    }

    func save(_ playlists: [PinnedPlaylist]) {
        items = playlists.map { pin in
            var updated = pin
            updated.artworkURL = items.first { $0.id == pin.id }?.artworkURL
            return updated
        }
        persist()
    }

    func updateArtwork(_ url: URL, for id: String) {
        guard MediaKeyHandler.isAllowedArtworkURL(url),
              let index = items.firstIndex(where: { $0.id == id }), items[index].artworkURL != url else { return }
        items[index].artworkURL = url
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct PlaylistSettingsView: View {
    let store: PinnedPlaylists
    @State private var drafts: [Draft] = []
    @State private var message: String?
    @State private var didSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pinned Playlists").font(.title2.bold())

            ForEach($drafts) { $draft in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 7) {
                        TextField("Playlist name", text: $draft.name)
                        TextField("YouTube Music playlist link", text: $draft.link)
                    }
                    Button(role: .destructive) {
                        drafts.removeAll { $0.id == draft.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove playlist")
                }
            }

            HStack {
                Button("Add Playlist", systemImage: "plus") { drafts.append(Draft()) }
                    .disabled(drafts.count >= PinnedPlaylists.limit)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(didSave ? Color.secondary : Color.red)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            drafts = store.items.map { Draft(name: $0.name, link: $0.url.absoluteString) }
            message = nil
            didSave = false
            if drafts.isEmpty { drafts.append(Draft()) }
        }
        .onChange(of: drafts) {
            message = nil
            didSave = false
        }
    }

    private func save() {
        var pins: [PinnedPlaylist] = []
        var ids = Set<String>()
        for draft in drafts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty && link.isEmpty { continue }
            guard !name.isEmpty, let id = PinnedPlaylist.id(from: link) else {
                message = "Each pin needs a name and a valid YouTube playlist link."
                return
            }
            guard ids.insert(id).inserted else {
                message = "Each playlist can be pinned once."
                return
            }
            pins.append(PinnedPlaylist(id: id, name: name))
        }
        store.save(pins)
        didSave = true
        message = "Saved"
    }

    private struct Draft: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var link = ""
    }
}
