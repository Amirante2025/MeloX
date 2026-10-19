import Foundation

extension NeteaseAPI {
    func searchSuggestions(_ keywords: String) async throws -> [String] {
        // The mobile weapi endpoint can return an empty HTTP 200 body.
        // Prefer the same eapi transport as full search, retaining weapi as a fallback.
        do {
            let response: SearchSuggestionsResponse = try await client.eapi(
                "/api/search/suggest/keyword",
                data: ["s": keywords]
            )
            try validate(responseCode: response.code, message: response.message)
            try Task.checkCancellation()
            if !response.keywords.isEmpty {
                return response.keywords
            }
        } catch {
            try Task.checkCancellation()
        }

        try Task.checkCancellation()
        let response: SearchSuggestionsResponse = try await client.weapi(
            "/api/search/suggest/keyword",
            data: ["s": keywords]
        )
        try validate(responseCode: response.code, message: response.message)
        try Task.checkCancellation()
        return response.keywords
    }
}

private struct SearchSuggestionsResponse: Decodable {
    let code: Int
    let result: Suggestions?
    let message: String?

    var keywords: [String] {
        var seen = Set<String>()
        return Array((result?.allMatch ?? [])
            .map { $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(8))
    }

    struct Suggestions: Decodable {
        let allMatch: [Match]?
    }

    struct Match: Decodable {
        let keyword: String
    }
}
