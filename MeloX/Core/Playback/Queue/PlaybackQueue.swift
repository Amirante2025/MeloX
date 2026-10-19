import Foundation

enum RepeatMode: String, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .off: L10n.string("ui.player.repeat.off")
        case .all: L10n.string("ui.player.repeat.all")
        case .one: L10n.string("ui.player.repeat.one")
        }
    }
}

enum QueuePlaybackModeIndicator: String {
    case shuffle
    case repeatAll
    case repeatOne
    case autoplay
    case autoMix

    var systemImage: String {
        switch self {
        case .shuffle:
            "shuffle"
        case .repeatAll:
            "repeat"
        case .repeatOne:
            "repeat.1"
        case .autoplay:
            "infinity"
        case .autoMix:
            "circle.circle.fill"
        }
    }
}

struct PlaybackQueue {
    private(set) var songs: [Song] = []
    private(set) var currentIndex = 0
    private(set) var isShuffled = false

    private var shuffledOrder: [Int] = []
    private var shuffledPosition = 0

    // Reserve the complete collection order before metadata arrives. Missing
    // details must not let already-cached songs jump ahead in shuffle mode.
    private var collectionSongIDs: [Int]?
    private var collectionShuffleIDs: [Int] = []

    var collectionPlaybackIDs: [Int]? {
        collectionSongIDs.map { isShuffled ? collectionShuffleIDs : $0 }
    }

    var pendingCollectionSongIDs: [Int] {
        let known = Set(songs.map(\.id))
        return (collectionPlaybackIDs ?? []).filter { !known.contains($0) }
    }

    mutating func cancelCollectionPlan() {
        collectionSongIDs = nil
        collectionShuffleIDs = []
    }

    var currentSong: Song? {
        guard songs.indices.contains(currentIndex) else { return nil }
        return songs[currentIndex]
    }

    var persistedShuffleOrder: [Int] {
        shuffledOrder
    }

    func upcomingIndices(wraps: Bool) -> [Int] {
        guard !songs.isEmpty else { return [] }
        if let order = collectionPlaybackIDs,
           let id = currentSong?.id,
           let position = order.firstIndex(of: id) {
            var remaining = Array(order.dropFirst(position + 1))
            if wraps, position > 0 {
                remaining += order.prefix(position)
            }
            let indices = Dictionary(uniqueKeysWithValues: songs.enumerated().map { ($0.element.id, $0.offset) })
            return remaining.prefix { indices[$0] != nil }.compactMap { indices[$0] }
        }
        let order = isShuffled
            ? shuffledOrder
            : Array(songs.indices)
        let position = isShuffled
            ? shuffledPosition
            : currentIndex
        let nextPosition = min(position + 1, order.count)
        let remaining = Array(order.dropFirst(nextPosition))
        guard wraps, position > 0 else { return remaining }
        return remaining + Array(order.prefix(position))
    }

    mutating func restore(
        songs: [Song],
        currentIndex: Int,
        isShuffled: Bool,
        shuffledOrder: [Int]
    ) {
        collectionSongIDs = nil
        collectionShuffleIDs = []
        self.songs = songs
        self.currentIndex = songs.isEmpty
            ? 0
            : min(max(currentIndex, 0), songs.count - 1)
        self.isShuffled = isShuffled

        if isShuffled, isValidShuffleOrder(shuffledOrder) {
            self.shuffledOrder = shuffledOrder
            shuffledPosition = shuffledOrder.firstIndex(of: self.currentIndex) ?? 0
        } else if isShuffled {
            rebuildShuffleOrder()
        } else {
            self.shuffledOrder = []
            shuffledPosition = 0
        }
    }

    mutating func replace(with songs: [Song], startingAt index: Int, collectionSongIDs: [Int]? = nil) {
        self.collectionSongIDs = nil
        collectionShuffleIDs = []
        self.songs = songs
        currentIndex = songs.isEmpty ? 0 : min(max(index, 0), songs.count - 1)
        if let collectionSongIDs,
           Set(collectionSongIDs).count == collectionSongIDs.count,
           Set(songs.map(\.id)).count == songs.count,
           Set(songs.map(\.id)).isSubset(of: Set(collectionSongIDs)) {
            self.collectionSongIDs = collectionSongIDs
        }
        if isShuffled {
            rebuildShuffleOrder()
        } else {
            alignCollectionIndices()
        }
    }

    mutating func select(index: Int) -> Bool {
        guard songs.indices.contains(index) else { return false }
        currentIndex = index
        alignShufflePosition()
        return true
    }

    mutating func move(by offset: Int, wraps: Bool) -> Bool {
        if collectionSongIDs != nil {
            guard let index = collectionDestination(by: offset, wraps: wraps) else { return false }
            currentIndex = index
            alignShufflePosition()
            return true
        }
        let order = isShuffled ? shuffledOrder : Array(songs.indices)
        guard !order.isEmpty else { return false }
        let position = isShuffled ? shuffledPosition : currentIndex
        var destination = position + offset
        if order.indices.contains(destination) {
            // Continue in the existing order.
        } else if wraps {
            destination = offset > 0 ? 0 : order.count - 1
        } else {
            return false
        }

        if isShuffled {
            shuffledPosition = destination
            currentIndex = order[destination]
        } else {
            currentIndex = destination
        }
        return true
    }

    func canMove(by offset: Int, wraps: Bool) -> Bool {
        if collectionSongIDs != nil {
            return collectionDestination(by: offset, wraps: wraps) != nil
        }
        let order = isShuffled ? shuffledOrder : Array(songs.indices)
        guard !order.isEmpty else { return false }
        let position = isShuffled ? shuffledPosition : currentIndex
        return order.indices.contains(position + offset) || wraps
    }

    mutating func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            rebuildShuffleOrder()
        } else {
            shuffledOrder = []
            shuffledPosition = 0
        }
    }

    /// Resolve metadata without generating another shuffle for each batch.
    mutating func resolveCollectionSongs(_ newSongs: [Song]) {
        guard let collectionSongIDs else {
            var known = Set(songs.map(\.id))
            append(contentsOf: newSongs.filter { known.insert($0.id).inserted })
            return
        }
        let allowed = Set(collectionSongIDs)
        var known = Set(songs.map(\.id))
        songs.append(contentsOf: newSongs.filter { allowed.contains($0.id) && known.insert($0.id).inserted })
        alignCollectionIndices()
    }

    /// A successful response may omit deleted/unavailable songs. Remove those
    /// slots so Next can continue, while request failures remain retryable.
    mutating func removeUnavailableCollectionSongs(_ ids: [Int]) {
        guard collectionSongIDs != nil else { return }
        let known = Set(songs.map(\.id))
        let unavailable = Set(ids).subtracting(known)
        collectionSongIDs?.removeAll { unavailable.contains($0) }
        collectionShuffleIDs.removeAll { unavailable.contains($0) }
        alignCollectionIndices()
    }

    mutating func append(_ song: Song) {
        append(contentsOf: [song])
    }

    mutating func append(contentsOf newSongs: [Song]) {
        guard !newSongs.isEmpty else { return }
        if collectionSongIDs != nil {
            let existing = Set(collectionSongIDs ?? [])
            let ids = newSongs.map(\.id)
            if Set(ids).count == ids.count, existing.isDisjoint(with: ids) {
                collectionSongIDs?.append(contentsOf: ids)
                collectionShuffleIDs.append(contentsOf: ids)
            } else {
                // Explicit duplicate queue entries retain the ordinary queue's
                // occurrence-based semantics rather than an ID-only plan.
                collectionSongIDs = nil
                collectionShuffleIDs = []
            }
        }
        let firstNewIndex = songs.count
        songs.append(contentsOf: newSongs)
        if collectionSongIDs != nil {
            alignCollectionIndices()
            return
        }
        guard isShuffled else { return }

        let newIndices = Array(firstNewIndex..<songs.count).shuffled()
        shuffledOrder.append(contentsOf: newIndices)
    }

    mutating func insertNext(_ song: Song) {
        guard !songs.isEmpty else {
            append(song)
            return
        }

        if let order = collectionSongIDs, let currentID = currentSong?.id {
            if order.contains(song.id) {
                collectionSongIDs = nil
                collectionShuffleIDs = []
            } else {
                let position = order.firstIndex(of: currentID) ?? (order.count - 1)
                collectionSongIDs?.insert(song.id, at: position + 1)
                if let shuffledPosition = collectionShuffleIDs.firstIndex(of: currentID) {
                    collectionShuffleIDs.insert(song.id, at: shuffledPosition + 1)
                }
            }
        }

        let insertionIndex = min(currentIndex + 1, songs.endIndex)
        songs.insert(song, at: insertionIndex)

        if collectionSongIDs != nil {
            alignCollectionIndices()
            return
        }

        guard isShuffled else { return }

        shuffledOrder = shuffledOrder.map { index in
            index >= insertionIndex ? index + 1 : index
        }
        let shuffledInsertionIndex = min(
            shuffledPosition + 1,
            shuffledOrder.endIndex
        )
        shuffledOrder.insert(
            insertionIndex,
            at: shuffledInsertionIndex
        )
    }

    mutating func moveUpcomingSongs(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        wraps: Bool
    ) {
        if var order = collectionPlaybackIDs,
           let id = currentSong?.id,
           let position = order.firstIndex(of: id) {
            var positions = Array(order.indices.dropFirst(position + 1))
            if wraps, position > 0 {
                positions += order.indices.prefix(position)
            }
            let known = Set(songs.map(\.id))
            positions = Array(positions.prefix { known.contains(order[$0]) })
            let ids = moved(positions.map { order[$0] }, fromOffsets: source, toOffset: destination)
            for (position, songID) in zip(positions, ids) { order[position] = songID }
            if isShuffled {
                collectionShuffleIDs = order
            } else {
                collectionSongIDs = order
            }
            alignCollectionIndices()
            return
        }
        if isShuffled {
            var positions = Array(
                shuffledOrder.indices.dropFirst(
                    min(shuffledPosition + 1, shuffledOrder.count)
                )
            )
            if wraps, shuffledPosition > 0 {
                positions.append(
                    contentsOf: shuffledOrder.indices.prefix(
                        shuffledPosition
                    )
                )
            }
            let upcomingOrder = moved(
                positions.map { shuffledOrder[$0] },
                fromOffsets: source,
                toOffset: destination
            )
            for (position, songIndex) in zip(
                positions,
                upcomingOrder
            ) {
                shuffledOrder[position] = songIndex
            }
            return
        }

        var positions = Array(
            songs.indices.dropFirst(
                min(currentIndex + 1, songs.count)
            )
        )
        if wraps, currentIndex > 0 {
            positions.append(
                contentsOf: songs.indices.prefix(currentIndex)
            )
        }
        let upcomingSongs = moved(
            positions.map { songs[$0] },
            fromOffsets: source,
            toOffset: destination
        )
        for (position, song) in zip(positions, upcomingSongs) {
            songs[position] = song
        }
    }

    private mutating func rebuildShuffleOrder() {
        guard songs.indices.contains(currentIndex) else {
            shuffledOrder = []
            shuffledPosition = 0
            return
        }
        if let collectionSongIDs {
            let id = songs[currentIndex].id
            collectionShuffleIDs = [id] + collectionSongIDs.filter { $0 != id }.shuffled()
            alignCollectionIndices()
            return
        }
        shuffledOrder = [currentIndex] + songs.indices.filter { $0 != currentIndex }.shuffled()
        shuffledPosition = 0
    }

    private mutating func alignShufflePosition() {
        guard isShuffled else { return }
        if let position = shuffledOrder.firstIndex(of: currentIndex) {
            shuffledPosition = position
        } else {
            rebuildShuffleOrder()
        }
    }

    private func isValidShuffleOrder(_ order: [Int]) -> Bool {
        order.count == songs.count && Set(order) == Set(songs.indices)
    }

    private func collectionDestination(by offset: Int, wraps: Bool) -> Int? {
        guard let order = collectionPlaybackIDs,
              let id = currentSong?.id,
              let position = order.firstIndex(of: id) else { return nil }
        var destination = position + offset
        if !order.indices.contains(destination) {
            guard wraps, !order.isEmpty else { return nil }
            destination = offset > 0 ? 0 : order.count - 1
        }
        return songs.firstIndex { $0.id == order[destination] }
    }

    private mutating func alignCollectionIndices() {
        guard let order = collectionSongIDs else { return }
        let currentID = currentSong?.id
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        songs.sort { positions[$0.id, default: order.count] < positions[$1.id, default: order.count] }
        currentIndex = currentID.flatMap { id in songs.firstIndex { $0.id == id } } ?? 0
        if isShuffled {
            let indices = Dictionary(uniqueKeysWithValues: songs.enumerated().map { ($0.element.id, $0.offset) })
            shuffledOrder = collectionShuffleIDs.compactMap { indices[$0] }
            shuffledPosition = shuffledOrder.firstIndex(of: currentIndex) ?? 0
        }
    }

    private func moved<Element>(
        _ elements: [Element],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Element] {
        let validSource = source
            .filter(elements.indices.contains)
            .sorted()
        guard !validSource.isEmpty else { return elements }

        var result = elements
        let movingElements = validSource.map { elements[$0] }
        for index in validSource.reversed() {
            result.remove(at: index)
        }

        let removedBeforeDestination = validSource.filter {
            $0 < destination
        }.count
        let insertionIndex = min(
            max(destination - removedBeforeDestination, 0),
            result.count
        )
        result.insert(contentsOf: movingElements, at: insertionIndex)
        return result
    }
}
