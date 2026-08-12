import Combine
import Foundation

/// A finished game, kept as the moves that produced it rather than a single
/// position — so loading one restores real history that can be replayed.
struct StoredGame: Identifiable, Sendable {
    let id: Int
    let name: String
    let moves: [ChessMove]
    let finalBoard: [Square: Piece]
    let result: PositionStatus
    let captureCount: Int
    let queenTaken: Bool
    /// Ended because neither side had the material to mate, which the engine
    /// does not treat as an ending — the generator stops rather than shuffle
    /// two bare kings until the ply limit.
    let endedWithoutMatingMaterial: Bool

    var moveCount: Int { (moves.count + 1) / 2 }

    var resultText: String {
        if endedWithoutMatingMaterial { return "Drawn — no mate left" }

        switch result {
        case .checkmate(let winner): return "\(winner.displayName) mates"
        case .stalemate: return "Stalemate"
        case .check: return "Adjourned in check"
        case .playing: return "Adjourned"
        }
    }
}

/// Deterministic, so the shelf looks the same every launch. A library the
/// user cannot return to would be a worse shelf.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Any nonzero state works; the mix keeps low seeds from correlating.
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF
        if state == 0 { state = 0xDEAD_BEEF }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [StoredGame] = []
    @Published private(set) var isGenerating = false

    /// Plies, not moves. Random play needs room to thin the board out before
    /// mates and stalemates start appearing; cut it short and every game on
    /// the shelf is an unfinished middlegame.
    private let plyLimit = 400

    func generateIfNeeded(count: Int = 9) async {
        guard games.isEmpty, !isGenerating else { return }
        isGenerating = true

        for seed in 0..<count {
            let game = Self.generate(seed: UInt64(seed), plyLimit: plyLimit)
            games.append(game)
            // Hand the run loop back so cards appear as they are built.
            await Task.yield()
        }

        isGenerating = false
    }

    func regenerate(count: Int = 9) async {
        games.removeAll()
        await generateIfNeeded(count: count)
    }

    /// Plays random legal moves through the real engine, so every generated
    /// game obeys every rule the app enforces — castling, promotion and all.
    static func generate(seed: UInt64, plyLimit: Int = 400) -> StoredGame {
        var random = SeededGenerator(seed: seed)
        let game = ChessGame()

        while !game.status.isFinished,
              game.plies.count < plyLimit,
              !hasOnlyDeadMaterial(game.board) {
            let origins = game.movableSquares(for: game.currentPlayer)
            guard let origin = origins.sorted(by: { $0.algebraic < $1.algebraic })
                .randomElement(using: &random) else { break }

            let targets = game.legalMoves(from: origin)
            guard let target = targets.sorted(by: { $0.algebraic < $1.algebraic })
                .randomElement(using: &random) else { break }

            game.tap(origin)
            game.tap(target)

            if game.pendingPromotion != nil {
                let choice = PendingPromotion.choices.randomElement(using: &random) ?? .queen
                game.promote(to: choice)
            }
        }

        let captures = game.plies.filter { $0.capture != nil }.count
        let queenTaken = game.plies.contains { $0.capture?.piece.kind == .queen }
        let dead = !game.status.isFinished && hasOnlyDeadMaterial(game.board)

        return StoredGame(
            id: Int(seed),
            name: name(
                for: game.status,
                plies: game.plies.count,
                captures: captures,
                dead: dead,
                seed: seed
            ),
            moves: game.plies.map(\.move),
            finalBoard: game.board,
            result: game.status,
            captureCount: captures,
            queenTaken: queenTaken,
            endedWithoutMatingMaterial: dead
        )
    }

    /// The strict, uncontroversial cases: bare kings, or a lone minor piece.
    /// Nothing here can deliver mate, so playing on only burns plies.
    static func hasOnlyDeadMaterial(_ board: [Square: Piece]) -> Bool {
        let survivors = board.values.filter { $0.kind != .king }

        guard survivors.count <= 1 else { return false }
        guard let last = survivors.first else { return true }
        return last.kind == .bishop || last.kind == .knight
    }

    /// Named for how it went, not numbered — a shelf reads better than a list.
    /// The seed picks among synonyms so nine games do not share one title.
    private static func name(
        for status: PositionStatus,
        plies: Int,
        captures: Int,
        dead: Bool,
        seed: UInt64
    ) -> String {
        let options: [String]

        if dead {
            let drawn = ["Bare Kings", "Nothing Left", "Both Hands Empty"]
            return "\(drawn[Int(seed) % drawn.count]) \(seed + 1)"
        }

        switch status {
        case .checkmate where plies <= 50:
            options = ["The Ambush", "Short Work", "The Quick Knife"]
        case .checkmate:
            options = ["The Long Hunt", "Last Rites", "The Closing Net"]
        case .stalemate:
            options = ["Deadlock", "Nobody Wins", "The Standoff"]
        case .check, .playing:
            if captures >= 24 {
                options = ["The Bloodbath", "Attrition", "Nothing Left"]
            } else if captures <= 8 {
                options = ["The Cold War", "Circling", "All Bark"]
            } else {
                options = ["The Grind", "The Long Night", "Unfinished"]
            }
        }

        let title = options[Int(seed) % options.count]
        return "\(title) \(seed + 1)"
    }
}
