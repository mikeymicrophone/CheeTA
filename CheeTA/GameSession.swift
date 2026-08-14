import Combine
import Foundation

struct DiscardedLine {
    let openingFEN: String
    let prefix: [ChessMove]
    let suffix: [ChessMove]
    let documentID: UUID?
    let parentID: UUID?
    let forkPlyIndex: Int?
    let title: String
    let lastSavedMoves: [ChessMove]
    let lastSavedOpeningFEN: String
    let lastSavedTitle: String
}

@MainActor
final class GameSession: ObservableObject {
    @Published private(set) var documentID: UUID?
    @Published var title: String = "New game"
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var parentID: UUID?
    @Published private(set) var forkPlyIndex: Int?
    @Published private(set) var discardedLine: DiscardedLine?

    private(set) var lastSavedMoves: [ChessMove] = []
    private(set) var lastSavedOpeningFEN: String = OpeningSnapshot.standardFEN
    private(set) var lastSavedTitle: String = "New game"

    func noteNewGame(title: String, openingFEN: String) {
        documentID = nil
        parentID = nil
        forkPlyIndex = nil
        self.title = title
        lastSavedMoves = []
        lastSavedOpeningFEN = openingFEN
        lastSavedTitle = title
        discardedLine = nil
        isDirty = false
    }

    func noteLoadedShelf(name: String, moves: [ChessMove], openingFEN: String) {
        documentID = nil
        parentID = nil
        forkPlyIndex = nil
        title = name
        lastSavedMoves = moves
        lastSavedOpeningFEN = openingFEN
        lastSavedTitle = name
        discardedLine = nil
        isDirty = false
    }

    func noteLoadedDocument(_ document: GameDocument) {
        documentID = document.id
        parentID = document.parentID
        forkPlyIndex = document.forkPlyIndex
        title = document.name
        lastSavedMoves = (try? document.decodedMoves()) ?? []
        lastSavedOpeningFEN = document.openingFEN
        lastSavedTitle = document.name
        isDirty = false
    }

    func markSaved(_ document: GameDocument) {
        documentID = document.id
        parentID = document.parentID
        forkPlyIndex = document.forkPlyIndex
        title = document.name
        lastSavedMoves = (try? document.decodedMoves()) ?? []
        lastSavedOpeningFEN = document.openingFEN
        lastSavedTitle = document.name
        isDirty = false
    }

    func noteForkCommitted(newID: UUID?, parentID: UUID?, forkPlyIndex: Int?, title: String) {
        documentID = newID
        self.parentID = parentID
        self.forkPlyIndex = forkPlyIndex
        self.title = title
        isDirty = true
    }

    func noteContentChanged(openingFEN: String, moves: [ChessMove], title: String) {
        self.title = title
        isDirty = fingerprint(openingFEN: openingFEN, moves: moves, title: title)
            != fingerprint(
                openingFEN: lastSavedOpeningFEN,
                moves: lastSavedMoves,
                title: lastSavedTitle
            )
    }

    func snapshotDiscarded(
        openingFEN: String,
        prefix: [ChessMove],
        suffix: [ChessMove]
    ) -> DiscardedLine {
        DiscardedLine(
            openingFEN: openingFEN,
            prefix: prefix,
            suffix: suffix,
            documentID: documentID,
            parentID: parentID,
            forkPlyIndex: forkPlyIndex,
            title: title,
            lastSavedMoves: lastSavedMoves,
            lastSavedOpeningFEN: lastSavedOpeningFEN,
            lastSavedTitle: lastSavedTitle
        )
    }

    func storeDiscarded(_ line: DiscardedLine) {
        discardedLine = line
    }

    func clearDiscarded() {
        discardedLine = nil
    }

    func restoreIdentity(from discarded: DiscardedLine) {
        documentID = discarded.documentID
        parentID = discarded.parentID
        forkPlyIndex = discarded.forkPlyIndex
        title = discarded.title
        lastSavedMoves = discarded.lastSavedMoves
        lastSavedOpeningFEN = discarded.lastSavedOpeningFEN
        lastSavedTitle = discarded.lastSavedTitle
    }

    func replaceDiscardedConfirmationNeeded() -> Bool {
        discardedLine != nil
    }

    private func fingerprint(openingFEN: String, moves: [ChessMove], title: String) -> String {
        let moveKey = moves.map {
            "\($0.from.algebraic)\($0.to.algebraic)\($0.promotion?.rawValue ?? "")\($0.isEnPassant ? "e" : "")"
        }.joined(separator: ",")
        return "\(openingFEN)|\(moveKey)|\(title)"
    }
}
