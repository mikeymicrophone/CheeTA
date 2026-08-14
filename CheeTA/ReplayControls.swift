import SwiftUI

/// Drives replay playback. The engine owns the frames and the parked live
/// game; this only decides when the next frame is shown.
/// One beat of a replay: either a position to show on the board, or a cut
/// scene card to cut away to before play resumes.
enum ReplayStep {
    case position(ReplayFrame)
    case cutScene(CutSceneEvent)
}

@MainActor
final class ReplayPlayer: ObservableObject {
    @Published private(set) var progress: Progress?
    /// Non-nil while the replay has cut away to a scene it recorded live.
    @Published private(set) var activeCutScene: CutSceneEvent?

    struct Progress: Equatable {
        let step: Int
        let total: Int
        let title: String
        /// nil only for the true opening frame (start == 0, step == 0).
        let plyIndex: Int?
    }

    private var task: Task<Void, Never>?

    var isPlaying: Bool { progress != nil }

    func play(
        _ steps: [ReplayStep],
        title: String,
        in game: ChessGame,
        replayStartIndex: Int = 0,
        secondsPerFrame: Double = 0.55,
        secondsPerCutScene: Double = 2.2
    ) {
        let positionCount = steps.reduce(into: 0) { count, step in
            if case .position = step { count += 1 }
        }
        guard positionCount > 1 else { return }

        stop(in: game)
        game.beginReplay()

        task = Task { [weak self, weak game] in
            guard let game else { return }
            var shown = 0

            for step in steps {
                guard !Task.isCancelled else { return }

                switch step {
                case .position(let frame):
                    self?.activeCutScene = nil
                    game.show(frame)
                    let plyIndex: Int?
                    if shown == 0 {
                        plyIndex = replayStartIndex == 0 ? nil : replayStartIndex - 1
                    } else {
                        plyIndex = replayStartIndex + shown - 1
                    }
                    self?.progress = Progress(
                        step: shown,
                        total: positionCount - 1,
                        title: title,
                        plyIndex: plyIndex
                    )
                    shown += 1

                    // The opening frame is a still, so only the moves are paced.
                    if shown < positionCount {
                        try? await Task.sleep(for: .seconds(secondsPerFrame))
                    }

                case .cutScene(let event):
                    // The board is already showing the position the scene
                    // fired on, so the card cuts in over the right moment.
                    self?.activeCutScene = event
                    try? await Task.sleep(for: .seconds(secondsPerCutScene))
                    self?.activeCutScene = nil
                }
            }

            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            self?.finish(in: game)
        }
    }

    func stop(in game: ChessGame) {
        guard isPlaying else { return }
        task?.cancel()
        task = nil
        finish(in: game)
    }

    private func finish(in game: ChessGame) {
        progress = nil
        activeCutScene = nil
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
