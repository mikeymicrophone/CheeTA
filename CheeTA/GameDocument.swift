import Foundation

struct GameDocument: Codable, Identifiable, Sendable, Hashable {
    var schemaVersion: Int
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var openingFEN: String
    var moves: [PersistedMove]
    var result: PersistedResult
    var parentID: UUID?
    var forkPlyIndex: Int?
    var finalFEN: String
    var captureCount: Int
    var queenTaken: Bool
    var endedWithoutMatingMaterial: Bool

    static let currentSchemaVersion = 1

    func decodedMoves() throws -> [ChessMove] {
        try moves.map { try $0.chessMove() }
    }

    @MainActor
    static func make(
        from game: ChessGame,
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        parentID: UUID? = nil,
        forkPlyIndex: Int?
    ) -> GameDocument {
        let captures = game.plies.compactMap(\.capture)
        return GameDocument(
            schemaVersion: currentSchemaVersion,
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: Date(),
            openingFEN: game.openingFEN,
            moves: game.plies.map(\.move).map(PersistedMove.init),
            result: PersistedResult(game.status),
            parentID: parentID,
            forkPlyIndex: forkPlyIndex,
            finalFEN: game.fen,
            captureCount: captures.count,
            queenTaken: captures.contains { $0.piece.kind == .queen },
            endedWithoutMatingMaterial: !game.status.isFinished
                && GameLibrary.hasOnlyDeadMaterial(game.board)
        )
    }
}

struct PersistedMove: Codable, Hashable, Sendable {
    var from: String
    var to: String
    var promotion: String?
    var isEnPassant: Bool

    init(_ move: ChessMove) {
        from = move.from.algebraic
        to = move.to.algebraic
        promotion = move.promotion?.rawValue
        isEnPassant = move.isEnPassant
    }

    func chessMove() throws -> ChessMove {
        guard let fromSquare = Square(from), let toSquare = Square(to) else {
            throw GameDocumentError.invalidAlgebraic("\(from)-\(to)")
        }
        let promo: PieceKind?
        if let promotion {
            guard let kind = PieceKind(rawValue: promotion) else {
                throw GameDocumentError.invalidPromotion(promotion)
            }
            promo = kind
        } else {
            promo = nil
        }
        return ChessMove(from: fromSquare, to: toSquare, promotion: promo, isEnPassant: isEnPassant)
    }
}

enum PersistedResult: Codable, Hashable, Sendable {
    case playing
    case check(String)
    case checkmate(winner: String)
    case stalemate

    init(_ status: PositionStatus) {
        switch status {
        case .playing: self = .playing
        case .check(let player): self = .check(player.rawValue)
        case .checkmate(let winner): self = .checkmate(winner: winner.rawValue)
        case .stalemate: self = .stalemate
        }
    }

    var resultText: String {
        switch self {
        case .playing: "Adjourned"
        case .check(let player): "Adjourned in check (\(player))"
        case .checkmate(let winner): "\(winner.capitalized) mates"
        case .stalemate: "Stalemate"
        }
    }
}

enum GameDocumentError: LocalizedError {
    case unsupportedSchema(Int)
    case invalidAlgebraic(String)
    case invalidPromotion(String)
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "This game was saved by a newer CheeTA (schema \(version))"
        case .invalidAlgebraic(let text):
            "Invalid square in saved game: \(text)"
        case .invalidPromotion(let text):
            "Invalid promotion in saved game: \(text)"
        case .fileTooLarge:
            "Saved game file is too large"
        }
    }
}

enum BrowserPick {
    case shelf(StoredGame)
    case saved(GameDocument)
}

enum GameReplacement {
    case reset
    case preset(PositionPreset)
    case fen(String)
    case stored(StoredGame)
    case document(GameDocument)
}
