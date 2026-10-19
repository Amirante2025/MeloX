"""Compile actual PlayerStore entry points against controlled engine/source doubles."""
from pathlib import Path
import re
import subprocess
import sys

repo = Path(__file__).resolve().parents[2]
import tempfile
_temporary = tempfile.TemporaryDirectory(prefix='Music-Playback-Checks-')
work = Path(_temporary.name)
source = (repo / 'MeloX/Core/Playback/Session/PlayerStore.swift').read_text()
names = ['loadCurrentSong', 'handlePlaybackClockSample', 'estimatedProgress',
         'clampedPlaybackPosition', 'reanchorPlaybackTimeline', 'next',
         'moveToNext', 'previous', 'playFromQueue', 'play', 'seek', 'stopAtQueueEnd',
         'resetQueueExpansion', 'playFavorites', 'replaceQueueAndPlay', 'toggleShuffle']
methods = []
for name in names:
    match = re.search(r'^    (?:private )?func ' + name + r'\(', source, re.M)
    if not match:
        raise RuntimeError(name)
    end = re.search(r'^    }$', source[match.start():], re.M)
    if not end:
        raise RuntimeError('No method end: ' + name)
    methods.append(source[match.start():match.start() + end.end()].replace('    private func ', '    func ', 1))

preamble = r'''
import Foundation

struct Song: Identifiable, Equatable { let id: Int; let durationMS: Int }
struct PlaybackSource { let id: Int; var quality: String? { nil } }
enum L10n { static func string(_ value: String) -> String { value } }
struct PlaybackIssue { init(song: Song, error: Error) {} }
struct Settings { var previousRestartsCurrentSong = false; var cookie = "test-account" }
struct FavoritePlaybackPlan {
    let songs: [Song]; let remainingSongIDs: [Int]; let accountCookie: String
    var songIDs: [Int] { songs.map(\.id) + remainingSongIDs }
}

@MainActor final class API {
    var holdDetails = false
    var detailRequests: [[Int]] = []
    var pendingDetails: [Int: CheckedContinuation<[Song], Error>] = [:]
    func songDetails(ids: [Int]) async throws -> [Song] {
        detailRequests.append(ids)
        if holdDetails {
            return try await withCheckedThrowingContinuation { pendingDetails[ids[0]] = $0 }
        }
        return ids.map { Song(id: $0, durationMS: 240_000) }
    }
    func completeDetails(_ firstID: Int, ids: [Int]) {
        pendingDetails.removeValue(forKey: firstID)!.resume(returning: ids.map { Song(id: $0, durationMS: 240_000) })
    }
    var holdRequests = false
    var pending: [Int: CheckedContinuation<PlaybackSource, Error>] = [:]
    func playbackSource(id: Int) async throws -> PlaybackSource {
        if holdRequests {
            return try await withCheckedThrowingContinuation { pending[id] = $0 }
        }
        await Task.yield()
        return PlaybackSource(id: id)
    }
    func playbackSource(for song: Song) async throws -> PlaybackSource {
        try await playbackSource(id: song.id)
    }
    func complete(_ id: Int) {
        pending.removeValue(forKey: id)!.resume(returning: PlaybackSource(id: id))
    }
}
@MainActor final class Downloads {
    var localIDs = Set<Int>()
    func localPlaybackSource(songID: Int) -> PlaybackSource? {
        localIDs.contains(songID) ? PlaybackSource(id: songID) : nil
    }
}
@MainActor final class Session {
    func updateQueue(index: Int, count: Int) {}
    func setSong(_ song: Song, duration: Double, queueIndex: Int, queueCount: Int,
                 lyricsDisplaySettings: Bool) {}
}
@MainActor final class Engine {
    var onClock: ((AudioPlaybackClockSample) -> Void)?
    var position = 0.0
    var hasCurrentItem = true
    var loaded: [(Int, Double)] = []
    func emit(_ value: Double) {
        onClock?(AudioPlaybackClockSample(position: value, rate: 0,
                                        sampledAt: Date(), origin: .stateChanged))
    }
    func unload() {
        // AutoMixDeckTransitionController.reset() pauses the old active deck
        // before clearing it, which synchronously publishes its last position.
        if hasCurrentItem { emit(position) }
        hasCurrentItem = false
        position = 0
    }
    func load(_ source: PlaybackSource, startAt: Double, autoplay: Bool) async {
        loaded.append((source.id, startAt))
        position = startAt
        hasCurrentItem = true
        emit(startAt)
    }
    func seek(to seconds: Double) { position = seconds; if hasCurrentItem { emit(seconds) } }
    func pause() { if hasCurrentItem { emit(position) } }
}

@MainActor final class Fixture {
    var playbackQueue = PlaybackQueue()
    let queueExpansion = PlaybackQueueExpansion()
    var queueID = UUID()
    var queue: [Song] { playbackQueue.songs }
    var currentIndex: Int { playbackQueue.currentIndex }
    var isShuffled: Bool { playbackQueue.isShuffled }
    var isListenTogetherSessionActive = false
    var queueModeIndicator: QueuePlaybackModeIndicator?
    var currentSong: Song?
    var duration = 0.0
    var progress = 0.0
    var playbackTimelineClock = PlaybackTimelineClock()
    var playbackDurationLimit: Double { duration }
    var loadGeneration = 0
    var detailedPlaybackSongs: [Int: Song] = [:]
    var isResolvingSource = false
    var isLoading = false
    var isPlaying = false
    var isUsingDownloadedSource = false
    var currentPlaybackSource: PlaybackSource?
    var effectivePlaybackQuality: String?
    var currentLoadShouldAutoplay = false
    var playbackIssue: PlaybackIssue?
    var nowPlayingLyricsSongID: Int?
    var nowPlayingLyrics: [Int] = []
    var publishedNowPlayingLyricID: Int?
    let engine = Engine()
    let api = API()
    let downloads = Downloads()
    let nowPlayingSession = Session()
    var nowPlayingLyricsDisplaySettings = false
    var lastPersistedSecond = -1
    var isAutoplayEnabled = false
    var repeatMode: RepeatMode = .off
    var hasRecordedCurrentStart = false
    var settings = Settings()
    var historySourceID: Int?
    var isHeartModeActive = false
    var seekRevision = 0
    init(index: Int = 0, progress: Double = 83) {
        let songs = (1...3).map { Song(id: $0, durationMS: 240_000) }
        playbackQueue.replace(with: songs, startingAt: index)
        currentSong = songs[index]
        duration = 240
        self.progress = progress
        engine.position = progress
        playbackTimelineClock.reanchor(to: progress, rate: 0)
        engine.onClock = { [weak self] sample in self?.handlePlaybackClockSample(sample) }
    }
    func cancelAutoMixPreparation() {}
    func updateQueueModeIndicator() {}
    func resolveCurrentSongAudioAvailability(for song: Song, generation: Int) {}
    func resetBeatAnalysis() {}
    func updateNowPlayingState(forceNowPlayingLyrics: Bool = false, forceLyricsLiveActivity: Bool = false) {}
    func persistSnapshot() {}
    func updateNowPlayingLyricMetadata() {}
    func updateLyricsLiveActivity() {}
    func updateLyricsNotification() {}
    func prepareAutoMixIfNeeded() {}
    func recordCurrentPlayback() {}
    func appendAutoplayRecommendationsIfNeeded() async {}
'''

tests = r'''
}

enum CheckError: Error { case failed(String) }
@main struct Checks {
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw CheckError.failed(message) }
    }
    @MainActor static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<20_000 {
            if condition() { return }
            await Task.yield()
        }
        throw CheckError.failed("Timed out waiting for controlled request")
    }
    @MainActor static func finishDetails(_ player: Fixture) async throws {
        while player.queueExpansion.isLoading {
            try await until { !player.api.pendingDetails.isEmpty || !player.queueExpansion.isLoading }
            if !player.queueExpansion.isLoading { break }
            let requestCount = player.api.detailRequests.count
            let request = player.api.detailRequests.last!
            player.api.completeDetails(request[0], ids: Array(request.reversed()))
            try await until { player.api.detailRequests.count > requestCount || !player.queueExpansion.isLoading }
        }
    }
    @MainActor static func waitForSource(_ id: Int, in fixture: Fixture) async throws {
        for _ in 0..<1000 {
            if fixture.api.pending[id] != nil { return }
            await Task.yield()
        }
        throw CheckError.failed("Source request did not start: \(id)")
    }
    @MainActor static func main() async throws {
        let next = Fixture()
        await next.next()
        try expect(next.currentSong?.id == 2, "Next did not select song 2")
        try expect(next.progress == 0, "Next inherited old progress: \(next.progress)")
        try expect(next.engine.loaded.last?.1 == 0, "Next audio started at old position")
        print("PASS next resets display and actual audio start")

        let previous = Fixture(index: 1, progress: 127)
        await previous.previous()
        try expect(previous.currentSong?.id == 1 && previous.progress == 0, "Previous did not reset")
        try expect(previous.engine.loaded.last?.1 == 0, "Previous audio did not start at zero")
        print("PASS previous resets display and actual audio start")

        let queue = Fixture()
        await queue.playFromQueue(at: 2)
        try expect(queue.currentSong?.id == 3 && queue.progress == 0, "Queue selection inherited progress")
        try expect(queue.engine.loaded.last?.1 == 0, "Queue audio did not start at zero")
        print("PASS queue selection resets progress")

        let tapped = Fixture()
        await tapped.play(tapped.queue[1], in: tapped.queue)
        try expect(tapped.progress == 0 && tapped.engine.loaded.last?.1 == 0, "Tapped song inherited progress")
        print("PASS tapping a song starts at zero")

        let resume = Fixture(progress: 131)
        await resume.loadCurrentSong(autoplay: false, startAt: 42)
        try expect(resume.progress == 42 && resume.engine.loaded.last?.1 == 42, "Explicit resume position was overwritten")
        print("PASS explicit resume/quality reload position is preserved")

        let resolving = Fixture()
        resolving.api.holdRequests = true
        let loading = Task { await resolving.next() }
        try await waitForSource(2, in: resolving)
        try expect(resolving.progress == 0 && resolving.estimatedProgress() == 0, "Progress was not zero while resolving")
        resolving.engine.emit(91)
        try expect(resolving.progress == 0, "Late outgoing clock overwrote the new track")
        resolving.seek(to: 17)
        resolving.engine.emit(96)
        try expect(resolving.progress == 17, "Late outgoing clock overwrote an explicit pending seek")
        resolving.api.complete(2)
        await loading.value
        try expect(resolving.engine.loaded.last?.1 == 17, "Pending seek was not respected on load")
        print("PASS stale clock samples are ignored while resolving; pending seeks still work")

        let rapid = Fixture()
        rapid.api.holdRequests = true
        let first = Task { await rapid.next() }
        try await waitForSource(2, in: rapid)
        let second = Task { await rapid.next() }
        try await waitForSource(3, in: rapid)
        rapid.api.complete(2)
        await first.value
        try expect(rapid.engine.loaded.isEmpty, "Stale source request started playback")
        rapid.api.complete(3)
        await second.value
        try expect(rapid.currentSong?.id == 3 && rapid.engine.loaded.last?.0 == 3 && rapid.progress == 0,
                   "Rapid switches selected wrong song or position")
        print("PASS rapid next ignores the superseded source request")

        let local = Fixture()
        local.downloads.localIDs.insert(2)
        await local.next()
        try expect(local.isUsingDownloadedSource && local.progress == 0 && local.engine.loaded.last?.1 == 0,
                   "Downloaded song inherited progress")
        print("PASS downloaded song starts at zero")
        let progressive = Fixture()
        progressive.api.holdDetails = true
        let initial = (1...100).map { Song(id: $0, durationMS: 240_000) }
        await progressive.playFavorites(FavoritePlaybackPlan(songs: initial, remainingSongIDs: Array(101...205), accountCookie: "test-account"))
        for _ in 0..<1000 {
            if progressive.api.pendingDetails[101] != nil { break }
            await Task.yield()
        }
        try expect(progressive.currentSong?.id == 1 && progressive.queue.count == 100 && progressive.engine.loaded.count == 1,
                   "First song waited for the full favorite collection")
        progressive.api.completeDetails(101, ids: Array((101...200).reversed()))
        for _ in 0..<1000 {
            if progressive.api.pendingDetails[201] != nil { break }
            await Task.yield()
        }
        progressive.api.completeDetails(201, ids: Array(201...205))
        while progressive.queueExpansion.isLoading { await progressive.queueExpansion.waitForNextPage() }
        try expect(progressive.queue.map(\.id) == Array(1...205) && progressive.engine.loaded.count == 1 && progressive.progress == 0,
                   "Background fill changed order, restarted audio, or lost entries")
        print("PASS first song starts before remaining metadata; background fill preserves order and audio")

        let changed = Fixture()
        changed.api.holdDetails = true
        await changed.playFavorites(FavoritePlaybackPlan(songs: [changed.queue[0]], remainingSongIDs: [4], accountCookie: "test-account"))
        for _ in 0..<1000 { if changed.api.pendingDetails[4] != nil { break }; await Task.yield() }
        let oldPage = Task { await changed.queueExpansion.waitForNextPage() }
        await Task.yield()
        await changed.play(Song(id: 99, durationMS: 240_000))
        changed.api.completeDetails(4, ids: [4])
        await oldPage.value
        try expect(changed.queue.map(\.id) == [99] && changed.currentSong?.id == 99,
                   "Late favorite metadata polluted a newly selected queue")
        print("PASS selecting another song cancels stale favorite expansion")

        let boundary = Fixture()
        boundary.api.holdDetails = true
        boundary.repeatMode = .all
        await boundary.playFavorites(FavoritePlaybackPlan(songs: [boundary.queue[0]], remainingSongIDs: [2], accountCookie: "test-account"))
        for _ in 0..<1000 { if boundary.api.pendingDetails[2] != nil { break }; await Task.yield() }
        let skip = Task { await boundary.next() }
        await Task.yield()
        try expect(boundary.currentSong?.id == 1, "Queue wrapped before pending favorites arrived")
        boundary.api.completeDetails(2, ids: [2])
        await skip.value
        try expect(boundary.currentSong?.id == 2 && boundary.progress == 0, "Boundary skip did not use the appended page")
        print("PASS boundary skip waits for a page before wrapping or ending")

        let invalidated = Fixture()
        invalidated.api.holdDetails = true
        await invalidated.playFavorites(FavoritePlaybackPlan(songs: [invalidated.queue[0]], remainingSongIDs: [2], accountCookie: "test-account"))
        for _ in 0..<1000 { if invalidated.api.pendingDetails[2] != nil { break }; await Task.yield() }
        let pendingSkip = Task { await invalidated.next() }
        await Task.yield()
        await invalidated.play(Song(id: 99, durationMS: 240_000))
        invalidated.api.completeDetails(2, ids: [2])
        await pendingSkip.value
        try expect(invalidated.currentSong?.id == 99 && invalidated.queue.map(\.id) == [99], "A waiting skip advanced another queue")
        print("PASS pending boundary skip cannot advance a newly selected collection")
        let shuffled = Fixture()
        shuffled.api.holdDetails = true
        shuffled.toggleShuffle()
        await shuffled.playFavorites(FavoritePlaybackPlan(songs: initial, remainingSongIDs: Array(101...350), accountCookie: "test-account"))
        let planned = shuffled.playbackQueue.collectionPlaybackIDs!
        let expectedRequests = planned.filter { $0 > 100 }
        try expect(planned.first == 1 && Set(planned) == Set(1...350) && planned.count == 350,
                   "Shuffle did not reserve the complete collection or changed the existing first song")
        try await until { !shuffled.api.detailRequests.isEmpty }
        try expect(shuffled.api.detailRequests[0] == Array(expectedRequests.prefix(100)),
                   "Metadata requests followed collection pages instead of the complete shuffle plan")
        try expect(shuffled.playbackQueue.upcomingIndices(wraps: false).map { shuffled.queue[$0].id }
                   == Array(planned.dropFirst().prefix { $0 <= 100 }),
                   "Cached songs jumped ahead of unresolved shuffle slots")
        try expect(shuffled.currentSong?.id == 1 && shuffled.engine.loaded.count == 1,
                   "Global shuffle waited for all metadata before starting cached audio")
        try await finishDetails(shuffled)
        try expect(shuffled.queue.map(\.id) == Array(1...350)
                   && shuffled.playbackQueue.persistedShuffleOrder.map { shuffled.queue[$0].id } == planned
                   && shuffled.engine.loaded.count == 1 && shuffled.progress == 0,
                   "Batch completion reshuffled groups, reordered the canonical collection, or restarted audio")
        var heard = [shuffled.currentSong!.id]
        for _ in 1..<planned.count { await shuffled.next(); heard.append(shuffled.currentSong!.id) }
        try expect(heard == planned && Set(heard).count == 350,
                   "Actual playback diverged from the full shuffle plan, repeated or skipped songs")
        print("PASS complete collection shuffled once; cached audio starts immediately; all 350 actual skips follow the same plan")

        var gap = PlaybackQueue()
        gap.toggleShuffle()
        gap.replace(with: initial, startingAt: 0, collectionSongIDs: Array(1...350))
        let gapPlan = gap.collectionPlaybackIDs!
        let prefix = gapPlan.prefix { $0 <= 100 }
        let beforeGap = prefix.last!
        let nextMissing = gapPlan[prefix.count]
        _ = gap.select(index: gap.songs.firstIndex { $0.id == beforeGap }!)
        try expect(!gap.canMove(by: 1, wraps: true), "Next bypassed a reserved song to use another cached song")
        gap.resolveCollectionSongs([Song(id: nextMissing, durationMS: 240_000)])
        try expect(gap.canMove(by: 1, wraps: false) && gap.move(by: 1, wraps: false) && gap.currentSong?.id == nextMissing,
                   "Resolved next shuffle slot was not the next actual song")
        gap.resolveCollectionSongs((101...350).reversed().map { Song(id: $0, durationMS: 240_000) })
        try expect(gap.currentSong?.id == nextMissing && gap.collectionPlaybackIDs == gapPlan
                   && Set(gap.persistedShuffleOrder) == Set(gap.songs.indices),
                   "Later metadata changed the active song or invalidated persisted shuffle indices")
        gap.toggleShuffle()
        try expect(gap.currentSong?.id == nextMissing && gap.collectionPlaybackIDs == Array(1...350),
                   "Turning shuffle off lost the active song or original collection order")
        print("PASS unresolved slots block skipping; metadata preserves current song and canonical order")

        let reprioritized = Fixture()
        reprioritized.api.holdDetails = true
        await reprioritized.playFavorites(FavoritePlaybackPlan(songs: initial, remainingSongIDs: Array(101...350), accountCookie: "test-account"))
        try await until { reprioritized.api.pendingDetails[101] != nil }
        let obsolete = reprioritized.api.pendingDetails.removeValue(forKey: 101)!
        reprioritized.toggleShuffle()
        let replacementPlan = reprioritized.playbackQueue.collectionPlaybackIDs!
        let replacementIDs = replacementPlan.filter { $0 > 100 }
        try await until { reprioritized.api.detailRequests.count == 2 }
        try expect(reprioritized.api.detailRequests[1] == Array(replacementIDs.prefix(100)),
                   "Mode change did not prioritize the earliest unresolved shuffle slots")
        obsolete.resume(returning: (101...200).map { Song(id: $0, durationMS: 240_000) })
        for _ in 0..<20 { await Task.yield() }
        try expect(reprioritized.queue.count == 100 && reprioritized.currentSong?.id == 1,
                   "Cancelled metadata response changed the queue")
        try await finishDetails(reprioritized)
        try expect(reprioritized.playbackQueue.persistedShuffleOrder.map { reprioritized.queue[$0].id } == replacementPlan
                   && reprioritized.engine.loaded.count == 1,
                   "Reprioritization changed the planned order or restarted the current audio")
        print("PASS changing mode reprioritizes pending metadata and discards the cancelled page")

        let unavailable = Fixture()
        unavailable.api.holdDetails = true
        await unavailable.playFavorites(FavoritePlaybackPlan(songs: [unavailable.queue[0]], remainingSongIDs: [2, 3, 4], accountCookie: "test-account"))
        try await until { unavailable.api.pendingDetails[2] != nil }
        unavailable.api.completeDetails(2, ids: [4, 3])
        try await until { !unavailable.queueExpansion.isLoading }
        try expect(unavailable.playbackQueue.collectionPlaybackIDs == [1, 3, 4],
                   "Successful response with an unavailable song left a blocking slot")
        await unavailable.next()
        try expect(unavailable.currentSong?.id == 3 && unavailable.progress == 0,
                   "Unavailable metadata stopped playback before later available songs")
        print("PASS unavailable songs do not leave permanent holes in the reserved order")

        var edited = PlaybackQueue()
        edited.replace(with: (1...4).map { Song(id: $0, durationMS: 240_000) }, startingAt: 0, collectionSongIDs: Array(1...8))
        edited.moveUpcomingSongs(fromOffsets: IndexSet(integer: 1), toOffset: 0, wraps: false)
        edited.insertNext(Song(id: 99, durationMS: 240_000))
        edited.append(Song(id: 100, durationMS: 240_000))
        edited.resolveCollectionSongs((5...8).map { Song(id: $0, durationMS: 240_000) })
        try expect(edited.collectionPlaybackIDs == [1, 99, 3, 2, 4, 5, 6, 7, 8, 100]
                   && edited.upcomingIndices(wraps: false).map { edited.songs[$0].id } == [99, 3, 2, 4, 5, 6, 7, 8, 100],
                   "Background resolution overwrote manual next, append or drag order")
        edited.toggleShuffle()
        edited.append(Song(id: 1, durationMS: 240_000))
        try expect(edited.songs.filter { $0.id == 1 }.count == 2
                   && Set(edited.persistedShuffleOrder) == Set(edited.songs.indices),
                   "Explicit duplicate queue entries lost occurrence-based shuffle semantics")
        print("PASS manual queue edits survive metadata fill and explicit duplicate entries remain valid")
        let reselected = Fixture()
        reselected.api.holdDetails = true
        reselected.toggleShuffle()
        await reselected.playFavorites(FavoritePlaybackPlan(songs: initial, remainingSongIDs: Array(101...350), accountCookie: "test-account"))
        try await until { !reselected.api.pendingDetails.isEmpty }
        let abandoned = reselected.api.detailRequests[0]
        await reselected.play(initial[0])
        try expect(!reselected.queueExpansion.isLoading && reselected.playbackQueue.collectionPlaybackIDs == nil
                   && reselected.playbackQueue.canMove(by: 1, wraps: false),
                   "Cancelling expansion kept unresolved slots in a reused queue")
        await reselected.next()
        reselected.api.completeDetails(abandoned[0], ids: abandoned)
        for _ in 0..<20 { await Task.yield() }
        try expect(reselected.queue.count == 100 && reselected.currentSong?.id != 1 && reselected.progress == 0,
                   "Reselecting a cached song stalled at a cancelled slot or accepted stale metadata")
        print("PASS reselecting a cached song cancels unresolved slots and keeps the remaining queue usable")
        print("18 track-switch, progressive-playback and global-shuffle checks passed")
    }
}
'''

generated = work / 'TrackSwitchChecks.swift'
generated.write_text(preamble + '\n\n'.join(methods) + tests)
command = ['xcrun', 'swiftc', '-swift-version', '5', '-default-isolation', 'MainActor', '-parse-as-library',
           '-module-cache-path', str(work / 'track-switch-module-cache'), str(generated),
           str(repo / 'MeloX/Core/Playback/Queue/PlaybackQueue.swift'),
           str(repo / 'MeloX/Core/Playback/Queue/PlaybackQueueExpansion.swift'),
           str(repo / 'MeloX/Core/Playback/Session/PlaybackTimelineClock.swift'),
           str(repo / 'MeloX/Core/Playback/Engine/AudioPlaybackClockSample.swift'),
           '-o', str(work / 'track-switch-checks')]
subprocess.run(command, check=True)
result = subprocess.run([str(work / 'track-switch-checks')], capture_output=True, text=True)
print(result.stdout, end='')
if result.returncode:
    print(result.stderr[:2400], end='')
sys.exit(result.returncode)
