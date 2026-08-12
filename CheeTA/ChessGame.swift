import Combine
import Foundation

@MainActor
final class ChessGame: ObservableObject {
    @Published private(set) var board: [Square: Piece]
    @Published private(set) var currentPlayer: Player
    @Published private(set) var selectedSquare: Square?
    @Published private(set) var legalTargets: Set<Square>
    @Published private(set) var lastMove: ChessMove?
    @Published private(set) var lastCapture: Capture?
    /// Lets a view tell the first capture of the game from every later one.
    @Published private(set) var captureCount: Int
    @Published private(set) var status: PositionStatus
    @Published private(set) var positionPreset: PositionPreset?
    @Published private(set) var candidateSquares: Set<Square>
    @Published private(set) var isChoosingCandidates: Bool
    /// Every ply played since the position was set up, oldest first.
    @Published private(set) var plies: [RecordedPly]
    /// While true the published board is a replay frame, not the live game.
    @Published private(set) var isReplaying: Bool
    /// A display preference, so it survives restarts and preset loads.
    @Published private(set) var isPulseEnabled: Bool
    /// Historical permissions for the king and original corner rooks.
    @Published private(set) var castlingRights: CastlingRights
    /// Non-nil between selecting a pawn's final-rank move and choosing its role.
    @Published private(set) var pendingPromotion: PendingPromotion?
    /// The empty square behind a pawn that has just moved two squares.
    @Published private(set) var enPassantTarget: Square?
    /// Fires only when a played move creates a genuine, legal en-passant
    /// response. Loading a FEN can still make the move available, but does not
    /// pretend that the moment happened in this game.
    @Published private(set) var lastEnPassantOpportunity: EnPassantOpportunity?
    /// The latest en-passant capture, retained long enough for the UI to stage
    /// its aftermath cut scene.
    @Published private(set) var lastEnPassant: EnPassantCapture?
    @Published private(set) var halfmoveClock: Int
    @Published private(set) var fullmoveNumber: Int

    private var openingBoard: [Square: Piece]
    private var openingPlayer: Player
    private var liveState: LiveState?

    /// The live game, parked while a replay borrows the published position.
    private struct LiveState {
        let board: [Square: Piece]
        let currentPlayer: Player
        let lastMove: ChessMove?
        let selectedSquare: Square?
        let legalTargets: Set<Square>
        let candidateSquares: Set<Square>
        let castlingRights: CastlingRights
        let enPassantTarget: Square?
        let halfmoveClock: Int
        let fullmoveNumber: Int
    }

    init(
        board: [Square: Piece] = ChessGame.startingBoard(),
        currentPlayer: Player = .white,
        castlingRights: CastlingRights? = nil
    ) {
        self.board = board
        self.currentPlayer = currentPlayer
        self.selectedSquare = nil
        self.legalTargets = []
        self.lastMove = nil
        self.lastCapture = nil
        self.captureCount = 0
        self.status = .playing
        self.positionPreset = nil
        self.candidateSquares = []
        self.isChoosingCandidates = false
        self.plies = []
        self.isReplaying = false
        self.isPulseEnabled = true
        self.castlingRights = castlingRights ?? (board == ChessGame.startingBoard() ? .standard : .none)
        self.pendingPromotion = nil
        self.enPassantTarget = nil
        self.lastEnPassantOpportunity = nil
        self.lastEnPassant = nil
        self.halfmoveClock = 0
        self.fullmoveNumber = 1
        self.openingBoard = board
        self.openingPlayer = currentPlayer
        refreshStatus()
    }

    var statusText: String {
        switch status {
        case .playing:
            "\(currentPlayer.displayName) to move"
        case .check(let player):
            "\(player.displayName) is in check"
        case .checkmate(let winner):
            "Checkmate — \(winner.displayName) wins"
        case .stalemate:
            "Stalemate"
        }
    }

    /// The current player's movable pieces pulse until the player taps one.
    /// Once a manual set exists, only those chosen candidates pulse.
    var candidatePulseSquares: Set<Square> {
        guard isPulseEnabled, !status.isFinished else { return [] }
        let movable = movableSquares(for: currentPlayer)
        let chosen = candidateSquares.intersection(movable)
        return chosen.isEmpty ? movable : chosen
    }

    func reset() {
        endReplay()
        board = Self.startingBoard()
        currentPlayer = .white
        castlingRights = .standard
        pendingPromotion = nil
        enPassantTarget = nil
        lastEnPassantOpportunity = nil
        lastEnPassant = nil
        halfmoveClock = 0
        fullmoveNumber = 1
        openingBoard = board
        openingPlayer = .white
        plies = []
        selectedSquare = nil
        legalTargets = []
        lastMove = nil
        lastCapture = nil
        captureCount = 0
        positionPreset = nil
        candidateSquares = []
        isChoosingCandidates = false
        refreshStatus()
    }

    func load(_ preset: PositionPreset) {
        endReplay()
        board = Self.board(for: preset)
        currentPlayer = Self.currentPlayer(for: preset)
        castlingRights = Self.castlingRights(for: preset)
        pendingPromotion = nil
        enPassantTarget = nil
        lastEnPassantOpportunity = nil
        lastEnPassant = nil
        halfmoveClock = 0
        fullmoveNumber = 1
        openingBoard = board
        openingPlayer = currentPlayer
        plies = []
        selectedSquare = nil
        legalTargets = []
        lastMove = nil
        lastCapture = nil
        captureCount = 0
        positionPreset = preset
        candidateSquares = []
        isChoosingCandidates = false
        refreshStatus()
    }

    /// A standard six-field Forsyth-Edwards Notation representation of the
    /// exact position currently on the board.
    var fen: String {
        Self.makeFEN(
            board: board,
            currentPlayer: currentPlayer,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget,
            halfmoveClock: halfmoveClock,
            fullmoveNumber: fullmoveNumber
        )
    }

    /// Replaces the game with a FEN position. Imported positions deliberately
    /// start a fresh replay history: FEN carries a position, not its moves.
    func load(fen notation: String) throws {
        let position = try Self.parseFEN(notation)

        endReplay()
        board = position.board
        currentPlayer = position.currentPlayer
        castlingRights = position.castlingRights
        enPassantTarget = position.enPassantTarget
        lastEnPassantOpportunity = nil
        lastEnPassant = nil
        halfmoveClock = position.halfmoveClock
        fullmoveNumber = position.fullmoveNumber
        pendingPromotion = nil
        openingBoard = board
        openingPlayer = currentPlayer
        plies = []
        selectedSquare = nil
        legalTargets = []
        lastMove = nil
        lastCapture = nil
        captureCount = 0
        positionPreset = nil
        candidateSquares = []
        isChoosingCandidates = false
        refreshStatus()
    }

    /// Every piece passively contributes a corridor. This semantic threat map
    /// is always current; the view decides whether the player sees it.
    var threatCorridors: [ThreatCorridor] {
        board.map { origin, piece in
            ThreatCorridor(
                origin: origin,
                endpoint: nil,
                piece: piece,
                threatenedSquares: Set(Self.attackSquares(from: origin, on: board))
            )
        }
    }

    func threatCorridors(for mode: ThreatDisplayMode) -> [ThreatCorridor] {
        switch mode {
        case .enemyContact:
            board.flatMap { origin, piece in
                Self.enemyContactCorridors(
                    from: origin,
                    piece: piece,
                    on: board
                )
            }
        case .allThreats:
            threatCorridors
        }
    }

    func threatCorridors(
        reaching square: Square,
        mode: ThreatDisplayMode = .allThreats
    ) -> [ThreatCorridor] {
        threatCorridors(for: mode).filter { $0.threatenedSquares.contains(square) }
    }

    func tap(_ square: Square) {
        guard !status.isFinished, !isReplaying, pendingPromotion == nil else { return }

        if let selectedSquare, legalTargets.contains(square) {
            makeMove(from: selectedSquare, to: square)
            return
        }

        if board[square]?.player == currentPlayer {
            if isChoosingCandidates, !legalMoves(from: square).isEmpty {
                toggleCandidate(square)
            }
            selectedSquare = square
            legalTargets = Set(legalMoves(from: square))
        } else {
            selectedSquare = nil
            legalTargets = []
        }
    }

    func piece(at square: Square) -> Piece? {
        board[square]
    }

    func isKingInCheck(at square: Square) -> Bool {
        guard case .check(let player) = status,
              board[square] == Piece(kind: .king, player: player) else {
            if case .checkmate = status,
               let piece = board[square],
               piece.kind == .king,
               piece.player == currentPlayer {
                return true
            }
            return false
        }
        return true
    }

    func legalMoves(from origin: Square) -> [Square] {
        Self.legalMoves(
            from: origin,
            on: board,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget
        )
    }

    func isInCheck(_ player: Player) -> Bool {
        Self.isInCheck(player, on: board)
    }

    func movableSquares(for player: Player) -> Set<Square> {
        Set(board.compactMap { square, piece in
            guard piece.player == player,
                  !Self.legalMoves(
                    from: square,
                    on: board,
                    castlingRights: castlingRights,
                    enPassantTarget: enPassantTarget
                  ).isEmpty else {
                return nil
            }
            return square
        })
    }

    func clearCandidates() {
        candidateSquares = []
        isChoosingCandidates = false
    }

    /// Turning the pulse off leaves any chosen candidates alone, so flipping
    /// it back on restores the selection rather than starting over.
    func setPulse(enabled: Bool) {
        guard enabled != isPulseEnabled else { return }

        isPulseEnabled = enabled
        if !enabled {
            isChoosingCandidates = false
        }
    }

    func beginChoosingCandidates() {
        candidateSquares = []
        isChoosingCandidates = true
    }

    func finishChoosingCandidates() {
        isChoosingCandidates = false
    }

    // MARK: - Replay

    /// Frames for playing the game back: the position before the first ply
    /// shown, then one frame per ply. `lastPlies` nil replays everything.
    /// The ply a replay of this length begins at, so callers can line other
    /// per-ply material up with `replayFrames(lastPlies:)`.
    func replayStartIndex(lastPlies limit: Int? = nil) -> Int {
        limit.map { max(0, plies.count - max(0, $0)) } ?? 0
    }

    func replayFrames(lastPlies limit: Int? = nil) -> [ReplayFrame] {
        guard !plies.isEmpty else { return [] }

        let start = replayStartIndex(lastPlies: limit)
        let opening: ReplayFrame
        if start == 0 {
            opening = ReplayFrame(
                board: openingBoard,
                move: nil,
                playerToMove: openingPlayer
            )
        } else {
            let previous = plies[start - 1]
            opening = ReplayFrame(
                board: previous.boardAfter,
                move: previous.move,
                playerToMove: previous.playerToMoveAfter
            )
        }

        return [opening] + plies[start...].map {
            ReplayFrame(
                board: $0.boardAfter,
                move: $0.move,
                playerToMove: $0.playerToMoveAfter
            )
        }
    }

    /// Parks the live game so playback can borrow the published position.
    /// Taps are ignored until `endReplay()` puts it back.
    func beginReplay() {
        guard !isReplaying, pendingPromotion == nil else { return }

        liveState = LiveState(
            board: board,
            currentPlayer: currentPlayer,
            lastMove: lastMove,
            selectedSquare: selectedSquare,
            legalTargets: legalTargets,
            candidateSquares: candidateSquares,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget,
            halfmoveClock: halfmoveClock,
            fullmoveNumber: fullmoveNumber
        )
        selectedSquare = nil
        legalTargets = []
        isChoosingCandidates = false
        isReplaying = true
    }

    func show(_ frame: ReplayFrame) {
        guard isReplaying else { return }

        board = frame.board
        currentPlayer = frame.playerToMove
        lastMove = frame.move
    }

    func endReplay() {
        guard isReplaying, let liveState else { return }

        board = liveState.board
        currentPlayer = liveState.currentPlayer
        lastMove = liveState.lastMove
        selectedSquare = liveState.selectedSquare
        legalTargets = liveState.legalTargets
        candidateSquares = liveState.candidateSquares
        castlingRights = liveState.castlingRights
        enPassantTarget = liveState.enPassantTarget
        halfmoveClock = liveState.halfmoveClock
        fullmoveNumber = liveState.fullmoveNumber
        self.liveState = nil
        isReplaying = false
    }

    private func toggleCandidate(_ square: Square) {
        if candidateSquares.contains(square) {
            candidateSquares.remove(square)
        } else {
            candidateSquares.insert(square)
        }
    }

    private func makeMove(from origin: Square, to destination: Square) {
        guard let movingPiece = board[origin], movingPiece.player == currentPlayer else { return }

        if isPromotionMove(piece: movingPiece, to: destination) {
            pendingPromotion = PendingPromotion(from: origin, to: destination, pawn: movingPiece)
            selectedSquare = nil
            legalTargets = []
            return
        }

        completeMove(from: origin, to: destination, promotion: nil)
    }

    func promote(to kind: PieceKind) {
        guard PendingPromotion.choices.contains(kind),
              let pendingPromotion else { return }

        completeMove(
            from: pendingPromotion.from,
            to: pendingPromotion.to,
            promotion: kind
        )
    }

    private func completeMove(from origin: Square, to destination: Square, promotion: PieceKind?) {
        guard let movingPiece = board[origin], movingPiece.player == currentPlayer else { return }

        let enPassant = Self.enPassantCapture(
            from: origin,
            to: destination,
            piece: movingPiece,
            on: board,
            target: enPassantTarget
        )
        var capture: Capture?
        if let enPassant,
           let takenPiece = board[enPassant.capturedPawn] {
            capture = Capture(
                piece: takenPiece,
                captor: movingPiece,
                square: enPassant.capturedPawn
            )
        } else if let takenPiece = board[destination] {
            capture = Capture(
                piece: takenPiece,
                captor: movingPiece,
                square: destination
            )
        }
        if capture != nil {
            lastCapture = capture
            captureCount += 1
        }

        let resultingPiece = promotion.map { Piece(kind: $0, player: movingPiece.player) } ?? movingPiece
        board = Self.applyingMove(
            from: origin,
            to: destination,
            piece: resultingPiece,
            on: board,
            enPassantTarget: enPassantTarget
        )
        revokeCastlingRights(
            for: movingPiece,
            from: origin,
            to: destination,
            captured: capture?.piece
        )

        let move = ChessMove(
            from: origin,
            to: destination,
            promotion: promotion,
            isEnPassant: enPassant != nil
        )
        lastMove = move
        lastEnPassant = enPassant
        selectedSquare = nil
        legalTargets = []
        pendingPromotion = nil
        enPassantTarget = movingPiece.kind == .pawn && abs(destination.rank - origin.rank) == 2
            ? origin.offset(file: 0, rank: movingPiece.player == .white ? 1 : -1)
            : nil
        halfmoveClock = movingPiece.kind == .pawn || capture != nil ? 0 : halfmoveClock + 1
        if movingPiece.player == .black {
            fullmoveNumber += 1
        }
        currentPlayer = currentPlayer.opponent
        lastEnPassantOpportunity = Self.enPassantOpportunity(
            on: board,
            player: currentPlayer,
            target: enPassantTarget,
            castlingRights: castlingRights
        )
        candidateSquares = []
        isChoosingCandidates = false
        plies.append(
            RecordedPly(
                move: move,
                capture: capture,
                boardAfter: board,
                playerToMoveAfter: currentPlayer
            )
        )
        refreshStatus()
    }

    private func refreshStatus() {
        let inCheck = Self.isInCheck(currentPlayer, on: board)
        let hasLegalMove = board.contains { square, piece in
            piece.player == currentPlayer && !Self.legalMoves(
                from: square,
                on: board,
                castlingRights: castlingRights,
                enPassantTarget: enPassantTarget
            ).isEmpty
        }

        if inCheck && !hasLegalMove {
            status = .checkmate(winner: currentPlayer.opponent)
        } else if !inCheck && !hasLegalMove {
            status = .stalemate
        } else if inCheck {
            status = .check(currentPlayer)
        } else {
            status = .playing
        }
    }

    private func isPromotionMove(piece: Piece, to destination: Square) -> Bool {
        piece.kind == .pawn && destination.rank == (piece.player == .white ? 7 : 0)
    }

    private func revokeCastlingRights(
        for movingPiece: Piece,
        from origin: Square,
        to destination: Square,
        captured: Piece?
    ) {
        if movingPiece.kind == .king {
            castlingRights.revokeAll(for: movingPiece.player)
        }

        if movingPiece.kind == .rook, let side = Self.castlingSide(forCorner: origin, player: movingPiece.player) {
            castlingRights.revoke(movingPiece.player, side: side)
        }

        if captured?.kind == .rook,
           let side = Self.castlingSide(forCorner: destination, player: movingPiece.player.opponent) {
            castlingRights.revoke(movingPiece.player.opponent, side: side)
        }
    }
}

private struct FENPosition {
    let board: [Square: Piece]
    let currentPlayer: Player
    let castlingRights: CastlingRights
    let enPassantTarget: Square?
    let halfmoveClock: Int
    let fullmoveNumber: Int
}

private enum FENError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): "Invalid FEN: \(message)"
        }
    }
}

extension ChessGame {
    private static func makeFEN(
        board: [Square: Piece],
        currentPlayer: Player,
        castlingRights: CastlingRights,
        enPassantTarget: Square?,
        halfmoveClock: Int,
        fullmoveNumber: Int
    ) -> String {
        let placement = (0..<8).reversed().map { rank in
            var emptyCount = 0
            var field = ""
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)!
                guard let piece = board[square] else {
                    emptyCount += 1
                    continue
                }
                if emptyCount > 0 {
                    field += String(emptyCount)
                    emptyCount = 0
                }
                field.append(fenCharacter(for: piece))
            }
            if emptyCount > 0 { field += String(emptyCount) }
            return field
        }.joined(separator: "/")

        var rights = ""
        if castlingRights.whiteKingSide { rights += "K" }
        if castlingRights.whiteQueenSide { rights += "Q" }
        if castlingRights.blackKingSide { rights += "k" }
        if castlingRights.blackQueenSide { rights += "q" }

        return [
            placement,
            currentPlayer == .white ? "w" : "b",
            rights.isEmpty ? "-" : rights,
            enPassantTarget?.algebraic ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber)
        ].joined(separator: " ")
    }

    private static func parseFEN(_ notation: String) throws -> FENPosition {
        let fields = notation.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 6 else {
            throw FENError.invalid("use six space-separated fields")
        }

        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else {
            throw FENError.invalid("piece placement must contain eight ranks")
        }

        var board: [Square: Piece] = [:]
        for (fenRank, field) in ranks.enumerated() {
            let rank = 7 - fenRank
            var file = 0
            for character in field {
                if let emptyCount = character.wholeNumberValue {
                    guard (1...8).contains(emptyCount) else {
                        throw FENError.invalid("rank \(8 - fenRank) has an invalid empty-square count")
                    }
                    file += emptyCount
                } else if let piece = piece(forFENCharacter: character) {
                    guard file < 8 else {
                        throw FENError.invalid("rank \(8 - fenRank) is too wide")
                    }
                    board[Square(file: file, rank: rank)!] = piece
                    file += 1
                } else {
                    throw FENError.invalid("\(character) is not a valid piece character")
                }
            }
            guard file == 8 else {
                throw FENError.invalid("rank \(8 - fenRank) must describe exactly eight squares")
            }
        }

        guard board.values.filter({ $0 == Piece(kind: .king, player: .white) }).count == 1,
              board.values.filter({ $0 == Piece(kind: .king, player: .black) }).count == 1 else {
            throw FENError.invalid("a playable position needs exactly one king per side")
        }

        let currentPlayer: Player
        switch fields[1] {
        case "w": currentPlayer = .white
        case "b": currentPlayer = .black
        default: throw FENError.invalid("active color must be w or b")
        }

        let castlingRights = try parseCastlingRights(String(fields[2]))
        let enPassantTarget = try parseEnPassantTarget(String(fields[3]), on: board)
        guard let halfmoveClock = Int(fields[4]), halfmoveClock >= 0 else {
            throw FENError.invalid("half-move clock must be zero or greater")
        }
        guard let fullmoveNumber = Int(fields[5]), fullmoveNumber > 0 else {
            throw FENError.invalid("full-move number must be greater than zero")
        }

        return FENPosition(
            board: board,
            currentPlayer: currentPlayer,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget,
            halfmoveClock: halfmoveClock,
            fullmoveNumber: fullmoveNumber
        )
    }

    private static func fenCharacter(for piece: Piece) -> Character {
        let character: Character
        switch piece.kind {
        case .king: character = "k"
        case .queen: character = "q"
        case .rook: character = "r"
        case .bishop: character = "b"
        case .knight: character = "n"
        case .pawn: character = "p"
        }
        return piece.player == .white ? Character(String(character).uppercased()) : character
    }

    private static func piece(forFENCharacter character: Character) -> Piece? {
        let player: Player = character.isUppercase ? .white : .black
        let kind: PieceKind
        switch character.lowercased() {
        case "k": kind = .king
        case "q": kind = .queen
        case "r": kind = .rook
        case "b": kind = .bishop
        case "n": kind = .knight
        case "p": kind = .pawn
        default: return nil
        }
        return Piece(kind: kind, player: player)
    }

    private static func parseCastlingRights(_ field: String) throws -> CastlingRights {
        if field == "-" { return .none }
        var rights = CastlingRights.none
        var seen: Set<Character> = []
        for character in field {
            guard seen.insert(character).inserted else {
                throw FENError.invalid("castling rights cannot repeat \(character)")
            }
            switch character {
            case "K": rights.whiteKingSide = true
            case "Q": rights.whiteQueenSide = true
            case "k": rights.blackKingSide = true
            case "q": rights.blackQueenSide = true
            default: throw FENError.invalid("\(character) is not a castling-rights code")
            }
        }
        return rights
    }

    private static func parseEnPassantTarget(
        _ field: String,
        on board: [Square: Piece]
    ) throws -> Square? {
        if field == "-" { return nil }
        guard let square = Square(field), [2, 5].contains(square.rank), board[square] == nil else {
            throw FENError.invalid("en-passant target must be an empty square on rank 3 or 6")
        }
        return square
    }

    static func startingBoard() -> [Square: Piece] {
        var board: [Square: Piece] = [:]
        let backRank: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]

        for file in 0..<8 {
            board[Square(file: file, rank: 0)!] = Piece(kind: backRank[file], player: .white)
            board[Square(file: file, rank: 1)!] = Piece(kind: .pawn, player: .white)
            board[Square(file: file, rank: 6)!] = Piece(kind: .pawn, player: .black)
            board[Square(file: file, rank: 7)!] = Piece(kind: backRank[file], player: .black)
        }

        return board
    }

    static func board(for preset: PositionPreset) -> [Square: Piece] {
        switch preset {
        case .opening:
            // Italian Game after 1.e4 e5 2.Nf3 Nc6 3.Bc4 Nf6.
            return board([
                ("a1", .rook, .white), ("b1", .knight, .white),
                ("c1", .bishop, .white), ("d1", .queen, .white),
                ("e1", .king, .white), ("h1", .rook, .white),
                ("c4", .bishop, .white), ("f3", .knight, .white),
                ("a2", .pawn, .white), ("b2", .pawn, .white),
                ("c2", .pawn, .white), ("d2", .pawn, .white),
                ("e4", .pawn, .white), ("f2", .pawn, .white),
                ("g2", .pawn, .white), ("h2", .pawn, .white),

                ("a8", .rook, .black), ("c8", .bishop, .black),
                ("d8", .queen, .black), ("e8", .king, .black),
                ("f8", .bishop, .black), ("h8", .rook, .black),
                ("c6", .knight, .black), ("f6", .knight, .black),
                ("a7", .pawn, .black), ("b7", .pawn, .black),
                ("c7", .pawn, .black), ("d7", .pawn, .black),
                ("e5", .pawn, .black), ("f7", .pawn, .black),
                ("g7", .pawn, .black), ("h7", .pawn, .black)
            ])

        case .midgame:
            // A Catalan-style middlegame after the c- and d-pawns trade,
            // with both kings castled and the center open for the major pieces.
            return board([
                ("g1", .king, .white), ("c2", .queen, .white),
                ("a1", .rook, .white), ("f1", .rook, .white),
                ("c1", .bishop, .white), ("g2", .bishop, .white),
                ("c3", .knight, .white), ("f3", .knight, .white),
                ("a2", .pawn, .white), ("b2", .pawn, .white),
                ("d4", .pawn, .white), ("e3", .pawn, .white),
                ("f2", .pawn, .white), ("g3", .pawn, .white),
                ("h2", .pawn, .white),

                ("g8", .king, .black), ("d8", .queen, .black),
                ("a8", .rook, .black), ("f8", .rook, .black),
                ("c8", .bishop, .black), ("g7", .bishop, .black),
                ("c6", .knight, .black), ("f6", .knight, .black),
                ("a7", .pawn, .black), ("b7", .pawn, .black),
                ("c7", .pawn, .black), ("d5", .pawn, .black),
                ("f7", .pawn, .black), ("g6", .pawn, .black),
                ("h7", .pawn, .black)
            ])

        case .endgame:
            // A balanced rook-and-pawn ending with active kings and targets
            // on both wings.
            return board([
                ("f3", .king, .white), ("c5", .rook, .white),
                ("a4", .pawn, .white), ("b3", .pawn, .white),
                ("f4", .pawn, .white), ("g3", .pawn, .white),
                ("h4", .pawn, .white),

                ("e6", .king, .black), ("c2", .rook, .black),
                ("a6", .pawn, .black), ("b6", .pawn, .black),
                ("f7", .pawn, .black), ("g6", .pawn, .black),
                ("h5", .pawn, .black)
            ])
        }
    }

    static func castlingRights(for preset: PositionPreset) -> CastlingRights {
        switch preset {
        case .opening:
            // The Italian setup has not moved either king or corner rook.
            .standard
        case .midgame, .endgame:
            .none
        }
    }

    static func currentPlayer(for preset: PositionPreset) -> Player {
        switch preset {
        case .opening, .midgame, .endgame: .white
        }
    }

    private static func board(
        _ entries: [(String, PieceKind, Player)]
    ) -> [Square: Piece] {
        Dictionary(uniqueKeysWithValues: entries.map { notation, kind, player in
            (Square(notation)!, Piece(kind: kind, player: player))
        })
    }

    static func legalMoves(
        from origin: Square,
        on board: [Square: Piece],
        castlingRights: CastlingRights = .none,
        enPassantTarget: Square? = nil
    ) -> [Square] {
        guard let movingPiece = board[origin] else { return [] }

        return pseudoLegalMoves(
            from: origin,
            on: board,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget
        ).filter { destination in
            let simulatedBoard = applyingMove(
                from: origin,
                to: destination,
                piece: movingPiece,
                on: board,
                enPassantTarget: enPassantTarget
            )
            return !isInCheck(movingPiece.player, on: simulatedBoard)
        }
    }

    static func isInCheck(_ player: Player, on board: [Square: Piece]) -> Bool {
        guard let kingSquare = board.first(where: {
            $0.value == Piece(kind: .king, player: player)
        })?.key else {
            return true
        }

        return board.contains { origin, piece in
            piece.player == player.opponent && attackSquares(from: origin, on: board).contains(kingSquare)
        }
    }

    static func pseudoLegalMoves(
        from origin: Square,
        on board: [Square: Piece],
        castlingRights: CastlingRights = .none,
        enPassantTarget: Square? = nil
    ) -> [Square] {
        guard let piece = board[origin] else { return [] }

        if piece.kind == .pawn {
            return pawnMoves(
                from: origin,
                piece: piece,
                on: board,
                enPassantTarget: enPassantTarget
            )
        }

        var moves = attackSquares(from: origin, on: board).filter { target in
            guard let occupant = board[target] else { return true }
            return occupant.player != piece.player && occupant.kind != .king
        }

        if piece.kind == .king {
            moves += castlingMoves(
                from: origin,
                piece: piece,
                on: board,
                castlingRights: castlingRights
            )
        }

        return moves
    }

    private static func castlingMoves(
        from origin: Square,
        piece: Piece,
        on board: [Square: Piece],
        castlingRights: CastlingRights
    ) -> [Square] {
        let homeRank = piece.player == .white ? 0 : 7
        guard piece.kind == .king,
              origin == Square(file: 4, rank: homeRank),
              !isInCheck(piece.player, on: board) else {
            return []
        }

        return CastlingSide.allCases.compactMap { side in
            guard castlingRights.allows(piece.player, side: side),
                  let rookFrom = rookCorner(for: piece.player, side: side),
                  board[rookFrom] == Piece(kind: .rook, player: piece.player),
                  let destination = kingDestination(for: piece.player, side: side) else {
                return nil
            }

            let betweenFiles = side == .kingSide ? [5, 6] : [1, 2, 3]
            guard betweenFiles.allSatisfy({ board[Square(file: $0, rank: homeRank)!] == nil }) else {
                return nil
            }

            let kingTravelFiles = side == .kingSide ? [5, 6] : [3, 2]
            let kingCanTravel = kingTravelFiles.allSatisfy { file in
                let square = Square(file: file, rank: homeRank)!
                var kingOnlyBoard = board
                kingOnlyBoard[square] = piece
                kingOnlyBoard[origin] = nil
                return !isInCheck(piece.player, on: kingOnlyBoard)
            }
            return kingCanTravel ? destination : nil
        }
    }

    private static func applyingMove(
        from origin: Square,
        to destination: Square,
        piece: Piece,
        on board: [Square: Piece],
        enPassantTarget: Square? = nil
    ) -> [Square: Piece] {
        var updated = board
        updated[destination] = piece
        updated[origin] = nil

        if let enPassant = enPassantCapture(
            from: origin,
            to: destination,
            piece: piece,
            on: board,
            target: enPassantTarget
        ) {
            updated[enPassant.capturedPawn] = nil
        }

        if let rookMove = castlingRookMove(for: piece, from: origin, to: destination),
           updated[rookMove.from] == Piece(kind: .rook, player: piece.player) {
            updated[rookMove.to] = updated[rookMove.from]
            updated[rookMove.from] = nil
        }

        return updated
    }

    private static func castlingRookMove(
        for piece: Piece,
        from origin: Square,
        to destination: Square
    ) -> (from: Square, to: Square)? {
        guard piece.kind == .king, origin.rank == destination.rank,
              abs(destination.file - origin.file) == 2 else {
            return nil
        }

        let side: CastlingSide = destination.file > origin.file ? .kingSide : .queenSide
        guard let rookFrom = rookCorner(for: piece.player, side: side),
              let rookTo = Square(
                file: side == .kingSide ? 5 : 3,
                rank: origin.rank
              ) else {
            return nil
        }
        return (rookFrom, rookTo)
    }

    private static func rookCorner(for player: Player, side: CastlingSide) -> Square? {
        Square(file: side == .kingSide ? 7 : 0, rank: player == .white ? 0 : 7)
    }

    private static func kingDestination(for player: Player, side: CastlingSide) -> Square? {
        Square(file: side == .kingSide ? 6 : 2, rank: player == .white ? 0 : 7)
    }

    static func castlingSide(forCorner square: Square, player: Player) -> CastlingSide? {
        guard square.rank == (player == .white ? 0 : 7) else { return nil }
        switch square.file {
        case 0: return .queenSide
        case 7: return .kingSide
        default: return nil
        }
    }

    static func attackSquares(from origin: Square, on board: [Square: Piece]) -> [Square] {
        guard let piece = board[origin] else { return [] }

        let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

        switch piece.kind {
        case .rook:
            return raySquares(from: origin, directions: orthogonal, on: board)
        case .bishop:
            return raySquares(from: origin, directions: diagonal, on: board)
        case .queen:
            return raySquares(from: origin, directions: orthogonal + diagonal, on: board)
        case .knight:
            return [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
                .compactMap { origin.offset(file: $0.0, rank: $0.1) }
        case .king:
            return (orthogonal + diagonal).compactMap { origin.offset(file: $0.0, rank: $0.1) }
        case .pawn:
            let step = piece.player == .white ? 1 : -1
            return [-1, 1].compactMap { origin.offset(file: $0, rank: step) }
        }
    }

    private static func enemyContactCorridors(
        from origin: Square,
        piece: Piece,
        on board: [Square: Piece]
    ) -> [ThreatCorridor] {
        let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

        let slidingDirections: [(Int, Int)]?
        switch piece.kind {
        case .rook:
            slidingDirections = orthogonal
        case .bishop:
            slidingDirections = diagonal
        case .queen:
            slidingDirections = orthogonal + diagonal
        case .king, .knight, .pawn:
            slidingDirections = nil
        }

        if let slidingDirections {
            return slidingDirections.compactMap { direction in
                let path = raySquares(
                    from: origin,
                    directions: [direction],
                    on: board
                )
                guard let endpoint = path.last,
                      board[endpoint]?.player == piece.player.opponent else {
                    return nil
                }
                return ThreatCorridor(
                    origin: origin,
                    endpoint: endpoint,
                    piece: piece,
                    threatenedSquares: Set(path)
                )
            }
        }

        return attackSquares(from: origin, on: board).compactMap { endpoint in
            guard board[endpoint]?.player == piece.player.opponent else {
                return nil
            }
            return ThreatCorridor(
                origin: origin,
                endpoint: endpoint,
                piece: piece,
                threatenedSquares: [endpoint]
            )
        }
    }

    private static func pawnMoves(
        from origin: Square,
        piece: Piece,
        on board: [Square: Piece],
        enPassantTarget: Square?
    ) -> [Square] {
        let step = piece.player == .white ? 1 : -1
        let startingRank = piece.player == .white ? 1 : 6
        var moves: [Square] = []

        if let oneForward = origin.offset(file: 0, rank: step), board[oneForward] == nil {
            moves.append(oneForward)

            if origin.rank == startingRank,
               let twoForward = origin.offset(file: 0, rank: step * 2),
               board[twoForward] == nil {
                moves.append(twoForward)
            }
        }

        for target in attackSquares(from: origin, on: board) {
            if let occupant = board[target],
               occupant.player != piece.player,
               occupant.kind != .king {
                moves.append(target)
            }
        }

        if let enPassantTarget,
           enPassantCapture(
            from: origin,
            to: enPassantTarget,
            piece: piece,
            on: board,
            target: enPassantTarget
           ) != nil {
            moves.append(enPassantTarget)
        }

        return moves
    }

    /// Validates the special capture without assuming the calling side can
    /// legally expose its king. That final safety test happens in
    /// `legalMoves`, after `applyingMove` removes the pawn beside the landing
    /// square.
    private static func enPassantCapture(
        from origin: Square,
        to destination: Square,
        piece: Piece,
        on board: [Square: Piece],
        target: Square?
    ) -> EnPassantCapture? {
        let step = piece.player == .white ? 1 : -1
        guard piece.kind == .pawn,
              destination == target,
              board[destination] == nil,
              abs(destination.file - origin.file) == 1,
              destination.rank - origin.rank == step,
              let capturedPawn = Square(file: destination.file, rank: origin.rank),
              board[capturedPawn] == Piece(kind: .pawn, player: piece.player.opponent) else {
            return nil
        }

        return EnPassantCapture(
            captor: piece,
            from: origin,
            landing: destination,
            capturedPawn: capturedPawn
        )
    }

    /// There may be one or two adjacent pawns, but each candidate must also
    /// pass the king-safety test (for example, a pinned pawn cannot take).
    private static func enPassantOpportunity(
        on board: [Square: Piece],
        player: Player,
        target: Square?,
        castlingRights: CastlingRights
    ) -> EnPassantOpportunity? {
        guard let target,
              let vulnerablePawn = Square(
                file: target.file,
                rank: target.rank + (player == .white ? -1 : 1)
              ),
              board[vulnerablePawn] == Piece(kind: .pawn, player: player.opponent) else {
            return nil
        }

        let capturingPawns = [-1, 1].compactMap { fileOffset -> Square? in
            guard let origin = target.offset(file: fileOffset, rank: player == .white ? -1 : 1),
                  board[origin] == Piece(kind: .pawn, player: player),
                  legalMoves(
                    from: origin,
                    on: board,
                    castlingRights: castlingRights,
                    enPassantTarget: target
                  ).contains(target) else {
                return nil
            }
            return origin
        }

        guard !capturingPawns.isEmpty else { return nil }
        return EnPassantOpportunity(
            target: target,
            vulnerablePawn: vulnerablePawn,
            capturingPawns: Set(capturingPawns),
            player: player
        )
    }

    private static func raySquares(
        from origin: Square,
        directions: [(Int, Int)],
        on board: [Square: Piece]
    ) -> [Square] {
        var squares: [Square] = []

        for direction in directions {
            var distance = 1
            while let target = origin.offset(
                file: direction.0 * distance,
                rank: direction.1 * distance
            ) {
                squares.append(target)
                if board[target] != nil { break }
                distance += 1
            }
        }

        return squares
    }
}
