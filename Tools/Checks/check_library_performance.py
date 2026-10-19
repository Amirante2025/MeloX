"""Run the real library/cache/queue-expansion code with deterministic API doubles."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
sources = [
    'Tools/Checks/LibraryPerformanceChecks.swift',
    'MeloX/Core/Library/LibraryStore.swift',
    'MeloX/Core/Library/FavoriteLibraryCache.swift',
    'MeloX/Core/Playback/Queue/PlaybackQueueExpansion.swift',
    'MeloX/Core/Models/Account/AccountModels.swift',
    'MeloX/Core/Models/Music/MusicModels.swift',
    'MeloX/Core/Models/Music/SongAudioAvailability.swift',
    'MeloX/Core/Models/Music/SongCollectionPage.swift',
]
with tempfile.TemporaryDirectory(prefix='Music-Library-Checks-') as temporary:
    build = Path(temporary)
    executable = build / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-default-isolation', 'MainActor',
                    '-parse-as-library', '-module-cache-path', str(build / 'modules'),
                    *[str(repo / path) for path in sources], '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
