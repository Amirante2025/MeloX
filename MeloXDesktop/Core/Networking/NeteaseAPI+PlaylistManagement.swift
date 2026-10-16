import Foundation

extension NeteaseAPI {
    func deletePlaylist(id: Int) async throws {
        // Mirrors @neteaseapireborn/api/module/playlist_delete.js.
        let response: APIStatusResponse = try await client.weapi(
            "/api/playlist/remove",
            data: ["ids": "[\(id)]"]
        )
        try validate(responseCode: response.code, message: response.message)
    }

    func createPlaylist(name: String, isPrivate: Bool) async throws -> Playlist {
        // Mirrors @neteaseapireborn/api/module/playlist_create.js.
        let response: PlaylistCreationResponse = try await client.weapi(
            "/api/playlist/create",
            data: ["name": name, "privacy": isPrivate ? "10" : "0", "type": "NORMAL"]
        )
        try validate(responseCode: response.code, message: response.message)
        guard let playlist = response.playlist, playlist.id > 0 else {
            throw APIError.invalidResponse
        }
        return playlist
    }
}

private struct PlaylistCreationResponse: Decodable {
    let code: Int
    let playlist: Playlist?
    let message: String?
}
