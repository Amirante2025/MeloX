import CryptoKit
import Foundation

nonisolated struct FavoriteLibrarySnapshot: Codable {
    let version: Int
    let profile: AccountProfile
    let likedPlaylistID: Int?
    let songIDs: [Int]
    let songs: [Song]
    let nextOffset: Int
}

/// Store only the first page of details, keeping launch-time decoding bounded.
/// All ordered IDs are retained so Play All can expand the queue afterward.
@MainActor
final class FavoriteLibraryCache {
    private let directory: URL
    private let ioQueue = DispatchQueue(label: "Music.FavoriteLibraryCache", qos: .utility)

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appending(path: "MeloX/FavoriteLibrary", directoryHint: .isDirectory)
    }

    func load(for cookie: String) -> FavoriteLibrarySnapshot? {
        guard !cookie.isEmpty else { return nil }
        let url = fileURL(for: cookie)
        let data = ioQueue.sync { try? Data(contentsOf: url) }
        guard let data,
              let snapshot = try? JSONDecoder().decode(FavoriteLibrarySnapshot.self, from: data),
              snapshot.version == 1, snapshot.profile.id > 0,
              snapshot.nextOffset >= 0,
              snapshot.nextOffset <= min(100, snapshot.songIDs.count),
              snapshot.songs.count <= 100,
              Set(snapshot.songIDs).count == snapshot.songIDs.count,
              snapshot.songIDs.allSatisfy({ $0 > 0 }) else { return nil }
        let pageIDs = Set(snapshot.songIDs.prefix(snapshot.nextOffset))
        guard snapshot.songs.allSatisfy({ pageIDs.contains($0.id) }),
              Set(snapshot.songs.map(\.id)).count == snapshot.songs.count else { return nil }
        return snapshot
    }

    func save(_ snapshot: FavoriteLibrarySnapshot, for cookie: String) {
        guard !cookie.isEmpty, let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = directory
        let url = fileURL(for: cookie)
        ioQueue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                // Cache failure must not prevent online loading or playback.
            }
        }
    }

    func clear(for cookie: String) {
        let url = fileURL(for: cookie)
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    private func fileURL(for cookie: String) -> URL {
        let key = SHA256.hash(data: Data(cookie.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(key).json", directoryHint: .notDirectory)
    }
}

struct FavoritePlaybackPlan {
    let songs: [Song]
    let remainingSongIDs: [Int]
    let accountCookie: String

    var songIDs: [Int] { songs.map(\.id) + remainingSongIDs }
}
