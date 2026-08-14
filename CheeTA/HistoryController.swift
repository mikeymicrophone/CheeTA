import Combine
import Foundation

enum HistoryCursor: Equatable, Sendable {
    case live
    case opening
    case ply(Int)
}

@MainActor
final class HistoryController: ObservableObject {
    @Published private(set) var cursor: HistoryCursor = .live
    @Published var selectedSquare: Square?
    @Published var legalTargets: Set<Square> = []
    @Published var pendingPromotion: PendingPromotion?

    var isInspecting: Bool {
        if case .live = cursor { return false }
        return true
    }

    func show(_ target: HistoryCursor, in game: ChessGame) {
        switch target {
        case .live:
            returnToLive(in: game)
        case .opening, .ply:
            guard game.pendingPromotion == nil else { return }
            if !game.isReplaying { game.beginReplay() }
            guard let frame = frame(for: target, in: game) else { return }
            game.show(frame)
            cursor = target
        }
    }

    func returnToLive(in game: ChessGame) {
        if game.isReplaying { game.endReplay() }
        cursor = .live
        selectedSquare = nil
        legalTargets = []
        pendingPromotion = nil
    }

    func frame(for target: HistoryCursor, in game: ChessGame) -> ReplayFrame? {
        let opening = game.openingSnapshot
        switch target {
        case .live:
            return nil
        case .opening:
            return ReplayFrame(
                board: opening.board,
                move: nil,
                playerToMove: opening.playerToMove,
                status: ChessGame.positionStatus(
                    board: opening.board,
                    player: opening.playerToMove,
                    castlingRights: opening.castlingRights,
                    enPassantTarget: opening.enPassantTarget
                )
            )
        case .ply(let index):
            guard game.plies.indices.contains(index) else { return nil }
            let ply = game.plies[index]
            return ReplayFrame(
                board: ply.boardAfter,
                move: ply.move,
                playerToMove: ply.playerToMoveAfter,
                status: ply.statusAfter
            )
        }
    }
}
