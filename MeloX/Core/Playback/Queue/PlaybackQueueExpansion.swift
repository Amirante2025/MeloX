import Foundation
import Observation

/// Append ordered metadata batches without restarting the current song.
@MainActor
@Observable
final class PlaybackQueueExpansion {
    private(set) var isLoading = false
    private(set) var failureMessage: String?

    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var remainingIDs: [Int] = []
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var load: (@MainActor ([Int]) async throws -> [Song])?
    @ObservationIgnored private var unavailable: (@MainActor ([Int]) -> Void)?
    @ObservationIgnored private var append: (@MainActor ([Song]) -> Void)?

    func start(
        ids: [Int],
        load: @escaping @MainActor ([Int]) async throws -> [Song],
        unavailable: @escaping @MainActor ([Int]) -> Void = { _ in },
        append: @escaping @MainActor ([Song]) -> Void
    ) {
        cancel()
        remainingIDs = ids
        self.load = load
        self.unavailable = unavailable
        self.append = append
        loadNextPage()
    }

    func cancel() {
        generation = UUID()
        pageTask?.cancel()
        pageTask = nil
        remainingIDs = []
        load = nil
        unavailable = nil
        append = nil
        isLoading = false
        failureMessage = nil
    }

    func retry() {
        guard !isLoading, !remainingIDs.isEmpty else { return }
        loadNextPage()
    }

    /// Keep fetching the earliest unresolved slots after a mode/order change.
    func prioritize(_ ids: [Int]) {
        guard !ids.isEmpty, !remainingIDs.isEmpty, load != nil else { return }
        let remaining = Set(remainingIDs)
        let reordered = ids.filter { remaining.contains($0) }
        guard reordered != remainingIDs else { return }
        generation = UUID()
        pageTask?.cancel()
        pageTask = nil
        remainingIDs = reordered
        loadNextPage()
    }

    func waitForNextPage() async {
        // The task includes appending, so a boundary skip sees the new entries
        // before it tries to move the current queue index.
        await pageTask?.value
    }

    private func loadNextPage() {
        guard let load, !remainingIDs.isEmpty else {
            pageTask = nil
            isLoading = false
            return
        }
        let requestedIDs = Array(remainingIDs.prefix(100))
        let requestGeneration = generation
        isLoading = true
        failureMessage = nil
        pageTask = Task { @MainActor [weak self] in
            do {
                let songs = try await load(requestedIDs)
                try Task.checkCancellation()
                guard let self, self.generation == requestGeneration else { return }
                let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self.remainingIDs.removeFirst(requestedIDs.count)
                self.unavailable?(requestedIDs.filter { byID[$0] == nil })
                self.append?(requestedIDs.compactMap { byID[$0] })
                self.loadNextPage()
            } catch {
                guard let self, self.generation == requestGeneration else { return }
                if Task.isCancelled || error is CancellationError {
                    self.cancel()
                } else {
                    self.pageTask = nil
                    self.isLoading = false
                    self.failureMessage = error.localizedDescription
                }
            }
        }
    }
}
