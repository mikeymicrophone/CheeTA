import SwiftUI

struct MoveHistoryPane: View {
    @ObservedObject var game: ChessGame
    @ObservedObject var history: HistoryController
    @ObservedObject var session: GameSession
    @ObservedObject var replay: ReplayPlayer
    let savedGames: SavedGameStore
    let canSave: Bool
    let onInspect: (HistoryCursor) -> Void
    let onReturnToLive: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onRestoreDiscarded: () -> Void
    let onOpenSibling: (GameDocument) -> Void

    @State private var showSiblings = false
    @State private var siblingBadge: SiblingBadge?

    private var rows: [HistoryRow] {
        PlyNotation.rows(from: game.plies, opening: game.openingSnapshot)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                if canSave {
                    saveButtons
                }
                columnHeader
                List {
                    startRow
                    ForEach(rows) { row in
                        moveRow(row)
                    }
                }
                .listStyle(.plain)
                footer
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        TextField("Game title", text: $session.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        if session.isDirty {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel("Unsaved changes")
                        }
                    }
                }
            }
            .sheet(item: $siblingBadge) { badge in
                siblingSheet(for: badge)
            }
        }
        .onChange(of: game.plies.count) { _, _ in
            // Keep the live tip in view after each ply.
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.statusText)
                .font(.subheadline.weight(.semibold))
            Text("\(game.plies.count) plies")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var saveButtons: some View {
        HStack {
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .disabled(!session.isDirty && session.documentID != nil)
            Button("Save As", action: onSaveAs)
                .buttonStyle(.bordered)
                .disabled(game.plies.isEmpty && session.documentID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 36, alignment: .trailing)
            Text("White")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            Text("Black")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var startRow: some View {
        HStack(spacing: 0) {
            Text("·")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
            cellChrome(
                title: "Opening position",
                marks: nil,
                highlight: highlight(for: .opening),
                accessibility: "Opening position"
            ) {
                onInspect(.opening)
            }
            Color.clear.frame(maxWidth: .infinity)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowSeparator(.hidden)
        .overlay(alignment: .leading) {
            if session.forkPlyIndex == nil, session.parentID != nil || hasSavedSiblings(forkPlyIndex: nil) {
                badgeButton(forkPlyIndex: nil)
            }
        }
    }

    private func moveRow(_ row: HistoryRow) -> some View {
        HStack(spacing: 0) {
            Text("\(row.moveNumber)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)

            if let white = row.white {
                plyCell(white)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .frame(minHeight: 44)
            }

            if let black = row.black {
                plyCell(black)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowSeparator(.hidden)
    }

    private func plyCell(_ cell: HistoryCell) -> some View {
        cellChrome(
            title: cell.notation,
            marks: cell.marks,
            highlight: highlight(for: .ply(cell.plyIndex)),
            accessibility: {
                if let ply = game.plies[safe: cell.plyIndex] {
                    return PlyNotation.accessibility(ply)
                }
                return cell.notation
            }()
        ) {
            onInspect(.ply(cell.plyIndex))
        }
        .overlay(alignment: .topTrailing) {
            if session.forkPlyIndex == cell.plyIndex || hasSavedSiblings(forkPlyIndex: cell.plyIndex) {
                badgeButton(forkPlyIndex: cell.plyIndex)
            }
        }
    }

    private func cellChrome(
        title: String,
        marks: PlyMarks?,
        highlight: CellHighlight,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .monospaced).weight(highlight == .now ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    if let marks {
                        markIcons(marks)
                    }
                }
                Spacer(minLength: 0)
                if highlight == .now {
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(alignment: .leading) {
                Rectangle()
                    .fill(highlight.barColor)
                    .frame(width: 2)
                    .opacity(highlight == .none ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility + highlight.accessibilitySuffix)
    }

    private func markIcons(_ marks: PlyMarks) -> some View {
        HStack(spacing: 4) {
            if marks.isCapture {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            if marks.isEnPassant {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .bold))
            }
            if marks.promotion != nil {
                Image(systemName: "arrow.up.circle").font(.system(size: 9, weight: .bold))
            }
            if marks.mate {
                Image(systemName: "flag.checkered").font(.system(size: 9, weight: .bold))
            } else if marks.check {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if game.plies.isEmpty {
                Text("No moves yet. \(game.openingSnapshot.playerToMove.displayName) to play.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if replay.isPlaying {
                Text(replayCaption)
                    .font(.caption.weight(.semibold))
            } else if history.isInspecting {
                Text(viewingCaption)
                    .font(.caption.weight(.semibold))
                Button("Return to live", action: onReturnToLive)
                    .buttonStyle(.bordered)
                Text("Return to live to play or undo.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if session.discardedLine != nil {
                Button("Restore discarded line", action: onRestoreDiscarded)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.bar)
    }

    private var viewingCaption: String {
        switch history.cursor {
        case .live:
            return ""
        case .opening:
            return "Viewing opening position"
        case .ply(let index):
            if let ply = game.plies[safe: index] {
                return "Viewing \(PlyNotation.coordinate(ply))"
            }
            return "Viewing ply \(index + 1)"
        }
    }

    private var replayCaption: String {
        if let index = replay.progress?.plyIndex,
           let ply = game.plies[safe: index] {
            return "Replay · \(PlyNotation.coordinate(ply))"
        }
        return "Replay · opening"
    }

    private func highlight(for target: HistoryCursor) -> CellHighlight {
        if replay.isPlaying {
            switch (replay.progress?.plyIndex, target) {
            case (nil, .opening): return .replay
            case let (index?, .ply(cell)) where index == cell: return .replay
            default: break
            }
        }
        if history.cursor == target {
            return history.isInspecting ? .viewing : .none
        }
        if case .live = history.cursor,
           case .ply(let index) = target,
           index == game.plies.count - 1,
           !game.plies.isEmpty {
            return .now
        }
        return .none
    }

    private func hasSavedSiblings(forkPlyIndex: Int?) -> Bool {
        let parent = session.parentID ?? session.documentID
        guard let parent else { return false }
        return !savedGames.siblings(parentID: parent, forkPlyIndex: forkPlyIndex)
            .filter { $0.id != session.documentID }
            .isEmpty
    }

    private func badgeButton(forkPlyIndex: Int?) -> some View {
        Button {
            siblingBadge = SiblingBadge(forkPlyIndex: forkPlyIndex)
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2.weight(.bold))
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Variations from this position")
    }

    private func siblingSheet(for badge: SiblingBadge) -> some View {
        let parent = session.parentID ?? session.documentID
        let siblings = parent.map {
            savedGames.siblings(parentID: $0, forkPlyIndex: badge.forkPlyIndex)
                .filter { $0.id != session.documentID }
        } ?? []

        return NavigationStack {
            List {
                if session.discardedLine != nil {
                    Button("Original line (unsaved)", action: onRestoreDiscarded)
                }
                ForEach(siblings) { document in
                    Button(document.name) {
                        onOpenSibling(document)
                    }
                }
            }
            .navigationTitle("Variations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { siblingBadge = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum CellHighlight {
    case none, now, viewing, replay

    var barColor: Color {
        switch self {
        case .none: .clear
        case .now: .accentColor
        case .viewing, .replay: .accentColor.opacity(0.55)
        }
    }

    var accessibilitySuffix: String {
        switch self {
        case .none: ""
        case .now: ", now"
        case .viewing: ", viewing"
        case .replay: ", replay"
        }
    }
}

private struct SiblingBadge: Identifiable {
    let forkPlyIndex: Int?
    var id: String { forkPlyIndex.map(String.init) ?? "opening" }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
