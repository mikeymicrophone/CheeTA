import Foundation

struct PlyMarks: Equatable, Sendable {
    var isCapture: Bool
    var isEnPassant: Bool
    var isCastling: CastlingSide?
    var promotion: PieceKind?
    var check: Bool
    var mate: Bool

    init(_ ply: RecordedPly) {
        isCapture = ply.capture != nil
        isEnPassant = ply.move.isEnPassant
        isCastling = PlyNotation.castlingSide(of: ply)
        promotion = ply.move.promotion
        if case .check = ply.statusAfter {
            check = true
        } else {
            check = false
        }
        if case .checkmate = ply.statusAfter {
            mate = true
        } else {
            mate = false
        }
    }
}

struct HistoryCell: Identifiable, Equatable, Sendable {
    let plyIndex: Int
    let notation: String
    let marks: PlyMarks

    var id: Int { plyIndex }
}

struct HistoryRow: Identifiable, Equatable, Sendable {
    let moveNumber: Int
    let white: HistoryCell?
    let black: HistoryCell?

    var id: Int { moveNumber }
}

enum PlyNotation {
    static func coordinate(_ ply: RecordedPly) -> String {
        let piece = movingKind(ply).displayName
        let body: String
        if let side = castlingSide(of: ply) {
            body = "\(piece) \(side == .kingSide ? "O-O" : "O-O-O")"
        } else if let promotion = ply.move.promotion {
            body = "\(piece) \(ply.move.from.algebraic)\(ply.capture == nil ? "–" : "×")\(ply.move.to.algebraic)=\(letter(for: promotion))"
        } else if ply.move.isEnPassant {
            body = "\(piece) \(ply.move.from.algebraic)×\(ply.move.to.algebraic) e.p."
        } else if ply.capture != nil {
            body = "\(piece) \(ply.move.from.algebraic)×\(ply.move.to.algebraic)"
        } else {
            body = "\(piece) \(ply.move.from.algebraic)–\(ply.move.to.algebraic)"
        }

        if case .checkmate = ply.statusAfter {
            return body + "#"
        }
        if case .check = ply.statusAfter {
            return body + "+"
        }
        return body
    }

    static func accessibility(_ ply: RecordedPly) -> String {
        let mover = ply.playerToMoveAfter.opponent
        let side = mover.displayName
        if let castle = castlingSide(of: ply) {
            let castleWords = castle == .kingSide ? "castles short" : "castles long"
            return "\(side) king \(castleWords)\(suffixWords(ply))"
        }

        let pieceWords = movingKind(ply).rawValue

        var phrase = "\(side) \(pieceWords) from \(ply.move.from.algebraic) to \(ply.move.to.algebraic)"
        if ply.move.isEnPassant {
            phrase += ", en passant"
        } else if ply.capture != nil {
            phrase += ", capture"
        }
        if let promotion = ply.move.promotion {
            phrase += ", promotes to \(promotion.rawValue)"
        }
        phrase += suffixWords(ply)
        return phrase
    }

    static func rows(from plies: [RecordedPly], opening: OpeningSnapshot) -> [HistoryRow] {
        var rows: [HistoryRow] = []
        var moveNumber = opening.fullmoveNumber
        var white: HistoryCell?
        var black: HistoryCell?

        func flush() {
            rows.append(HistoryRow(moveNumber: moveNumber, white: white, black: black))
            white = nil
            black = nil
            moveNumber += 1
        }

        for (index, ply) in plies.enumerated() {
            let cell = HistoryCell(
                plyIndex: index,
                notation: coordinate(ply),
                marks: PlyMarks(ply)
            )
            let side: Player = index.isMultiple(of: 2)
                ? opening.playerToMove
                : opening.playerToMove.opponent
            if side == .white {
                if white != nil || black != nil { flush() }
                white = cell
            } else {
                black = cell
                flush()
            }
        }
        if white != nil && black == nil { flush() }
        return rows
    }

    static func castlingSide(of ply: RecordedPly) -> CastlingSide? {
        guard let piece = ply.boardAfter[ply.move.to], piece.kind == .king else { return nil }
        guard ply.move.from.rank == ply.move.to.rank else { return nil }
        let delta = ply.move.to.file - ply.move.from.file
        if delta == 2 { return .kingSide }
        if delta == -2 { return .queenSide }
        return nil
    }

    static func movingKind(_ ply: RecordedPly) -> PieceKind {
        if ply.move.promotion != nil { return .pawn }
        return ply.boardAfter[ply.move.to]?.kind ?? .pawn
    }

    private static func letter(for kind: PieceKind) -> String {
        switch kind {
        case .king: "K"
        case .queen: "Q"
        case .rook: "R"
        case .bishop: "B"
        case .knight: "N"
        case .pawn: ""
        }
    }

    private static func suffixWords(_ ply: RecordedPly) -> String {
        if case .checkmate = ply.statusAfter { return ", checkmate" }
        if case .check = ply.statusAfter { return ", check" }
        return ""
    }
}
