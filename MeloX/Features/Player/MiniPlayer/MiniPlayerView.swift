import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(PlayerStore.self) private var player

    let artworkTransitionID: String
    let artworkTransitionNamespace: Namespace.ID
    let onExpand: () -> Void

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: isInline ? 8 : 10) {
                Button(action: onExpand) {
                    HStack(spacing: isInline ? 8 : 10) {
                        ArtworkImage(url: song.album?.artworkURL, cornerRadius: 5)
                            .frame(width: artworkSize, height: artworkSize)
                            .matchedTransitionSource(
                                id: artworkTransitionID,
                                in: artworkTransitionNamespace
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if !isInline {
                                MiniPlayerArtistLabel(text: song.artistText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.6)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.2, extraBounce: 0),
                                value: player.isPlaying
                            )
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        player.isPlaying
                            ? L10n.string("ui.player.pause")
                            : L10n.string("ui.common.play")
                    )
                }

                if !isInline {
                    Button {
                        Task { await player.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ui.player.next")
                }
            }
            .padding(.leading, isInline ? 12 : 16)
            .padding(.trailing, isInline ? 8 : 12)
            .padding(.vertical, isInline ? 3 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .simultaneousGesture(trackSwipeGesture)
            .accessibilityAction(named: L10n.string("ui.player.previous")) {
                Task { await player.previous() }
            }
            .accessibilityAction(named: L10n.string("ui.player.next")) {
                Task { await player.next() }
            }
        }
    }

    private var isInline: Bool {
        placement == .inline
    }

    private var artworkSize: CGFloat {
        30
    }

    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    Task { await player.next() }
                } else {
                    Task { await player.previous() }
                }
            }
    }
}

private struct MiniPlayerArtistLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .contentTransition(.identity)
            .transition(.identity)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }

    private var textColor: Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let contrast: UIAccessibilityContrast = colorSchemeContrast == .increased ? .high : .normal
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.accessibilityContrast = contrast
        }
        // Capture a concrete system label color, bypassing the accessory's
        // hierarchical foreground-style resolution during the zoom return.
        let resolved = UIColor.secondaryLabel.resolvedColor(with: traits)
        return Color(cgColor: resolved.cgColor)
    }
}
