import Foundation

enum Player: String, CaseIterable, Sendable {
    case white
    case black

    var opponent: Player {
        self == .white ? .black : .white
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum PieceKind: String, CaseIterable, Sendable {
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

struct ChessMove: Hashable, Sendable {
    let from: Square
    let to: Square
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

enum PositionStatus: Equatable, Sendable {
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
