import SwiftUI

/// Drives replay playback. The engine owns the frames and the parked live
/// game; this only decides when the next frame is shown.
@MainActor
final class ReplayPlayer: ObservableObject {
    @Published private(set) var progress: Progress?

    struct Progress: Equatable {
        let step: Int
        let total: Int
        let title: String
    }

    private var task: Task<Void, Never>?

    var isPlaying: Bool { progress != nil }

    func play(
        _ frames: [ReplayFrame],
        title: String,
        in game: ChessGame,
        secondsPerFrame: Double = 0.55
    ) {
        guard frames.count > 1 else { return }

        stop(in: game)
        game.beginReplay()

        task = Task { [weak self, weak game] in
            guard let game else { return }

            for (index, frame) in frames.enumerated() {
                guard !Task.isCancelled else { return }

                game.show(frame)
                self?.progress = Progress(
                    step: index,
                    total: frames.count - 1,
                    title: title
                )

                // The opening frame is a still, so only the moves are paced.
                if index < frames.count - 1 {
                    try? await Task.sleep(for: .seconds(secondsPerFrame))
                }
            }

            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            self?.finish(in: game)
        }
    }

    func stop(in game: ChessGame) {
        task?.cancel()
        task = nil
        finish(in: game)
    }

    private func finish(in game: ChessGame) {
        progress = nil
        game.endReplay()
    }
}

/// Shown over the board while a replay runs. Tapping it stops playback.
struct ReplayBadge: View {
    let progress: ReplayPlayer.Progress
    let stop: () -> Void

    var body: some View {
        Button(action: stop) {
            HStack(spacing: 10) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))

                Text(progress.title.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.2)

                Text("\(progress.step)/\(progress.total)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(progress.title), move \(progress.step) of \(progress.total)")
        .accessibilityHint("Stops the replay")
    }
}
