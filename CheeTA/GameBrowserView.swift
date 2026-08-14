import SwiftUI
import UniformTypeIdentifiers

/// A shelf of complete games. Each card shows the position a game ended in,
/// so the shelf is browsable by shape rather than by title alone.
enum BrowserCollection: String, CaseIterable, Identifiable {
    case saved = "Your games"
    case shelf = "Shelf"

    var id: Self { self }
}

struct GameBrowserView: View {
    @ObservedObject var library: GameLibrary
    @ObservedObject var savedGames: SavedGameStore
    let palette: PiecePalette
    let select: (BrowserPick) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var collection: BrowserCollection = .saved
    @State private var importing = false

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Collection", selection: $collection) {
                    ForEach(BrowserCollection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        switch collection {
                        case .saved:
                            ForEach(savedGames.documents) { document in
                                savedCard(document)
                            }
                            if savedGames.documents.isEmpty {
                                Text("Saved games appear here after you tap Save in the move list.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                        case .shelf:
                            ForEach(library.games) { game in
                                Button {
                                    select(.shelf(game))
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
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if collection == .shelf {
                        Button {
                            Task { await library.regenerate() }
                        } label: {
                            Label("New shelf", systemImage: "arrow.clockwise")
                        }
                        .disabled(library.isGenerating)
                    } else {
                        Button {
                            importing = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
        }
        .task {
            await library.generateIfNeeded()
            await savedGames.loadAll()
        }
    }

    private func savedCard(_ document: GameDocument) -> some View {
        let board = (try? ChessGame.board(fromFEN: document.finalFEN)) ?? [:]
        return Button {
            select(.saved(document))
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                MiniBoardView(board: board, palette: palette)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.black.opacity(0.15), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(document.result.resultText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("\(document.moves.count) plies · \(document.captureCount) captures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ShareLink(item: savedGames.fileURL(for: document.id))
            Button("Delete", role: .destructive) {
                try? savedGames.delete(id: document.id)
            }
        }
        .accessibilityHint("Loads this saved game")
    }

    private func importFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            savedGames.report(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= SavedGameStore.maxFileBytes else {
                    throw GameDocumentError.fileTooLarge
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var document = try decoder.decode(GameDocument.self, from: data)
                guard document.schemaVersion == GameDocument.currentSchemaVersion else {
                    throw GameDocumentError.unsupportedSchema(document.schemaVersion)
                }
                _ = try document.decodedMoves()
                document.id = UUID()
                document.parentID = nil
                document.forkPlyIndex = nil
                document.updatedAt = Date()
                try savedGames.save(document)
            } catch {
                savedGames.report(error.localizedDescription)
            }
        }
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
