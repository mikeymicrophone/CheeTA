import Foundation

enum Player: String, CaseIterable, Hashable, Sendable {
    case white
    case black

    var opponent: Player {
        self == .white ? .black : .white
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum PieceKind: String, CaseIterable, Hashable, Sendable {
    case king
    case queen
    case rook
    case bishop
    case knight
    case pawn
}

struct Piece: Hashable, Sendable {
    let kind: PieceKind
    let player: Player

    var symbol: String {
        switch (player, kind) {
        case (.white, .king): "♔"
        case (.white, .queen): "♕"
        case (.white, .rook): "♖"
        case (.white, .bishop): "♗"
        case (.white, .knight): "♘"
        case (.white, .pawn): "♙"
        case (.black, .king): "♚"
        case (.black, .queen): "♛"
        case (.black, .rook): "♜"
        case (.black, .bishop): "♝"
        case (.black, .knight): "♞"
        case (.black, .pawn): "♟"
        }
    }
}

struct Square: Hashable, Sendable, Identifiable {
    let file: Int
    let rank: Int

    var id: String { algebraic }

    var algebraic: String {
        let fileName = String(UnicodeScalar(97 + file)!)
        return "\(fileName)\(rank + 1)"
    }

    init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.file = file
        self.rank = rank
    }

    init?(_ algebraic: String) {
        let characters = Array(algebraic.lowercased())
        guard characters.count == 2,
              let scalar = characters[0].unicodeScalars.first,
              let rankNumber = Int(String(characters[1])) else { return nil }

        self.init(file: Int(scalar.value) - 97, rank: rankNumber - 1)
    }

    func offset(file fileOffset: Int, rank rankOffset: Int) -> Square? {
        Square(file: file + fileOffset, rank: rank + rankOffset)
    }
}

/// One piece taken off the board, with enough context for a view to narrate it.
struct Capture: Hashable, Sendable {
    let piece: Piece
    let captor: Piece
    let square: Square
}

/// The one-ply pawn capture where the taken pawn is beside the destination,
/// rather than on it. Keeping that distinction explicit lets the board,
/// replay, and cut scenes all describe the same unusual move accurately.
struct EnPassantCapture: Hashable, Sendable, Identifiable {
    let captor: Piece
    let from: Square
    let landing: Square
    let capturedPawn: Square

    var id: String { "\(from.algebraic)-\(landing.algebraic)-\(capturedPawn.algebraic)" }
}

/// A legal en-passant response created by the immediately preceding
/// two-square pawn move. It lasts only for the side now to move.
struct EnPassantOpportunity: Hashable, Sendable, Identifiable {
    let target: Square
    let vulnerablePawn: Square
    let capturingPawns: Set<Square>
    let player: Player

    var id: String {
        "\(player.rawValue)-\(target.algebraic)-\(vulnerablePawn.algebraic)-\(capturingPawns.map(\.algebraic).sorted().joined(separator: ","))"
    }
}

/// One played ply, kept with the position it produced so a replay never has to
/// re-derive legality — it just shows the boards again, in order.
struct RecordedPly: Hashable, Sendable {
    let move: ChessMove
    let capture: Capture?
    let boardAfter: [Square: Piece]
    let playerToMoveAfter: Player
    /// The position's verdict once this ply landed, so a game loaded from
    /// history can tell where its checks and its ending were.
    let statusAfter: PositionStatus
}

/// A single step of playback.
struct ReplayFrame: Hashable, Sendable {
    let board: [Square: Piece]
    let move: ChessMove?
    let playerToMove: Player
}

struct ChessMove: Hashable, Sendable {
    let from: Square
    let to: Square
    /// Non-nil only when a pawn reaches the far rank and changes identity.
    let promotion: PieceKind?
    /// True when a pawn captured the adjacent pawn after its two-square move.
    let isEnPassant: Bool

    init(
        from: Square,
        to: Square,
        promotion: PieceKind? = nil,
        isEnPassant: Bool = false
    ) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.isEnPassant = isEnPassant
    }
}

enum CastlingSide: CaseIterable, Sendable {
    case kingSide
    case queenSide
}

/// Castling is determined by history, not merely by where the pieces happen to
/// stand. Positions loaded without history begin with no castling rights.
struct CastlingRights: Hashable, Sendable {
    var whiteKingSide: Bool
    var whiteQueenSide: Bool
    var blackKingSide: Bool
    var blackQueenSide: Bool

    static let standard = CastlingRights(
        whiteKingSide: true,
        whiteQueenSide: true,
        blackKingSide: true,
        blackQueenSide: true
    )
    static let none = CastlingRights(
        whiteKingSide: false,
        whiteQueenSide: false,
        blackKingSide: false,
        blackQueenSide: false
    )

    func allows(_ player: Player, side: CastlingSide) -> Bool {
        switch (player, side) {
        case (.white, .kingSide): whiteKingSide
        case (.white, .queenSide): whiteQueenSide
        case (.black, .kingSide): blackKingSide
        case (.black, .queenSide): blackQueenSide
        }
    }

    mutating func revokeAll(for player: Player) {
        switch player {
        case .white:
            whiteKingSide = false
            whiteQueenSide = false
        case .black:
            blackKingSide = false
            blackQueenSide = false
        }
    }

    mutating func revoke(_ player: Player, side: CastlingSide) {
        switch (player, side) {
        case (.white, .kingSide): whiteKingSide = false
        case (.white, .queenSide): whiteQueenSide = false
        case (.black, .kingSide): blackKingSide = false
        case (.black, .queenSide): blackQueenSide = false
        }
    }
}

/// A pawn has reached the far rank. The game stays on the same turn until the
/// player chooses which eligible piece replaces it.
struct PendingPromotion: Hashable, Sendable {
    let from: Square
    let to: Square
    let pawn: Piece

    static let choices: [PieceKind] = [.queen, .rook, .bishop, .knight]
}

/// A semantic description of one piece's passive threat projection.
///
/// Rendering deliberately lives outside the engine so the same corridor can
/// later be drawn with different colors, textures, animations, or themes.
struct ThreatCorridor: Hashable, Sendable, Identifiable {
    let origin: Square
    let endpoint: Square?
    let piece: Piece
    let threatenedSquares: Set<Square>

    var id: String { "\(origin.algebraic)-\(endpoint?.algebraic ?? "all")" }
}

enum ThreatDisplayMode: String, CaseIterable, Sendable, Identifiable {
    case enemyContact
    case allThreats

    var id: Self { self }

    var displayName: String {
        switch self {
        case .enemyContact: "Enemy contact"
        case .allThreats: "All threats"
        }
    }
}

enum PositionStatus: Hashable, Sendable {
    case playing
    case check(Player)
    case checkmate(winner: Player)
    case stalemate

    var isFinished: Bool {
        switch self {
        case .checkmate, .stalemate: true
        case .playing, .check: false
        }
    }
}

enum PositionPreset: String, CaseIterable, Sendable, Identifiable {
    case opening
    case midgame
    case endgame

    var id: Self { self }

    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .opening: "flag.checkered"
        case .midgame: "scope"
        case .endgame: "crown"
        }
    }
}
