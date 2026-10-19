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
         'resetQueueExpansion', 'playFavorites', 'replaceQueueAndPlay']
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
struct FavoritePlaybackPlan { let songs: [Song]; let remainingSongIDs: [Int]; let accountCookie: String }

@MainActor final class API {
    var holdDetails = false
    var pendingDetails: [Int: CheckedContinuation<[Song], Error>] = [:]
    func songDetails(ids: [Int]) async throws -> [Song] {
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
        print("12 track-switch and progressive-playback checks passed")
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
