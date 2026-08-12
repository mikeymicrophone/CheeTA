import SwiftUI

/// A shelf of complete games. Each card shows the position a game ended in,
/// so the shelf is browsable by shape rather than by title alone.
struct GameBrowserView: View {
    @ObservedObject var library: GameLibrary
    let palette: PiecePalette
    let select: (StoredGame) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.games) { game in
                        Button {
                            select(game)
                            dismiss()
                        } label: {
                            card(for: game)
                        }
                        .buttonStyle(.plain)
                    }

                    if library.isGenerating {
                        placeholder
                    }
                }
                .padding(20)
            }
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.regenerate() }
                    } label: {
                        Label("New shelf", systemImage: "arrow.clockwise")
                    }
                    .disabled(library.isGenerating)
                }
            }
        }
        .task { await library.generateIfNeeded() }
    }

    private func card(for game: StoredGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniBoardView(board: game.finalBoard, palette: palette)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.black.opacity(0.15), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    badge(game.resultText, tint: resultTint(for: game.result))

                    if game.queenTaken {
                        badge("Queen down", tint: .orange)
                    }
                }

                Text("\(game.moveCount) moves · \(game.captureCount) captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Loads this game with its full history")
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary)
            .frame(height: 250)
            .overlay { ProgressView() }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private func resultTint(for status: PositionStatus) -> Color {
        switch status {
        case .checkmate: .red
        case .stalemate: .purple
        case .check: .yellow
        case .playing: .secondary
        }
    }
}

/// A static 8×8 board, small enough to sit on a card. It renders a position
/// only — no interaction, no game state.
struct MiniBoardView: View {
    let board: [Square: Piece]
    let palette: PiecePalette

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array((0..<8).reversed()), id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { file in
                        square(file: file, rank: rank)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
    }

    @ViewBuilder
    private func square(file: Int, rank: Int) -> some View {
        let isDark = (file + rank).isMultiple(of: 2)
        let piece = Square(file: file, rank: rank).flatMap { board[$0] }

        ZStack {
            (isDark
                ? Color(red: 0.24, green: 0.34, blue: 0.30)
                : Color(red: 0.84, green: 0.79, blue: 0.67))

            if let piece {
                Text(piece.symbol)
                    .font(.system(size: 200))
                    .minimumScaleFactor(0.01)
                    .foregroundStyle(palette.pieceColor(for: piece.player))
                    .padding(1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
