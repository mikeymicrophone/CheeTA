import XCTest
@testable import CheeTA

@MainActor
final class PlyNotationTests: XCTestCase {
    func testQuietKnightAndPawn() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("g8", "f6", in: game)

        XCTAssertEqual(PlyNotation.coordinate(game.plies[0]), "Pawn e2–e4")
        XCTAssertEqual(PlyNotation.coordinate(game.plies[1]), "Knight g8–f6")
    }

    func testCaptureAndCheckSuffixes() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("d7", "d5", in: game)
        play("e4", "d5", in: game)

        XCTAssertEqual(PlyNotation.coordinate(game.plies[2]), "Pawn e4×d5")
    }

    func testCastlingNotation() throws {
        let game = ChessGame(
            board: [
                Square("e1")!: Piece(kind: .king, player: .white),
                Square("h1")!: Piece(kind: .rook, player: .white),
                Square("e8")!: Piece(kind: .king, player: .black)
            ],
            currentPlayer: .white,
            castlingRights: .standard
        )
        play("e1", "g1", in: game)
        XCTAssertEqual(PlyNotation.coordinate(game.plies[0]), "King O-O")
    }

    func testPromotionNotation() throws {
        let game = ChessGame()
        try game.load(fen: "8/P7/8/8/8/8/8/4K1k1 w - - 0 1")
        game.tap(Square("a7")!)
        game.tap(Square("a8")!)
        game.promote(to: .queen)
        XCTAssertEqual(PlyNotation.coordinate(game.plies[0]), "Pawn a7–a8=Q")
    }

    func testRowGroupingFromBlackToMoveAndHighFullMove() throws {
        let game = ChessGame()
        try game.load(fen: "4k3/8/8/8/8/8/8/4K3 b - - 0 42")
        play("e8", "e7", in: game)
        play("e1", "e2", in: game)

        let rows = PlyNotation.rows(from: game.plies, opening: game.openingSnapshot)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].moveNumber, 42)
        XCTAssertNil(rows[0].white)
        XCTAssertEqual(rows[0].black?.notation, "King e8–e7")
        XCTAssertEqual(rows[1].moveNumber, 43)
        XCTAssertEqual(rows[1].white?.notation, "King e1–e2")
    }

    func testOpeningFENSurvivesPlayAndReset() throws {
        let game = ChessGame()
        XCTAssertEqual(game.openingFEN, OpeningSnapshot.standardFEN)
        play("e2", "e4", in: game)
        XCTAssertEqual(game.openingFEN, OpeningSnapshot.standardFEN)

        try game.load(fen: "4k3/8/8/8/8/8/8/4K3 b - - 0 42")
        XCTAssertTrue(game.openingFEN.hasPrefix("4k3/8/8/8/8/8/8/4K3 b"))
        XCTAssertEqual(game.openingSnapshot.fullmoveNumber, 42)
        XCTAssertEqual(game.openingSnapshot.playerToMove, .black)
    }

    func testLoadOpeningFENAndMovesMatchesLivePlay() throws {
        let live = ChessGame()
        play("e2", "e4", in: live)
        play("e7", "e5", in: live)
        play("g1", "f3", in: live)

        let loaded = ChessGame()
        try loaded.load(openingFEN: OpeningSnapshot.standardFEN, moves: live.plies.map(\.move))
        XCTAssertEqual(loaded.plies.map(\.move), live.plies.map(\.move))
        XCTAssertEqual(loaded.fen, live.fen)
    }

    func testIllegalMidListStopsAtPrefix() {
        let game = ChessGame()
        let illegal = ChessMove(from: Square("e2")!, to: Square("e5")!)
        XCTAssertThrowsError(
            try game.load(
                openingFEN: OpeningSnapshot.standardFEN,
                moves: [
                    ChessMove(from: Square("e2")!, to: Square("e4")!),
                    illegal
                ]
            )
        )
        XCTAssertEqual(game.plies.count, 1)
        XCTAssertEqual(game.plies[0].move.to.algebraic, "e4")
    }

    func testValidateFENDoesNotMutate() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        let before = game.fen
        XCTAssertThrowsError(try ChessGame.validateFEN("not-a-fen"))
        XCTAssertEqual(game.fen, before)
        XCTAssertNoThrow(try ChessGame.validateFEN(OpeningSnapshot.standardFEN))
        XCTAssertEqual(game.fen, before)
    }

    func testInspectRestoresStatusAndLeavesPlies() {
        let game = ChessGame()
        play("f2", "f3", in: game)
        play("e7", "e5", in: game)
        play("g2", "g4", in: game)
        play("d8", "h4", in: game)
        XCTAssertEqual(game.status, .checkmate(winner: .black))

        let history = HistoryController()
        let plyCount = game.plies.count
        history.show(.ply(0), in: game)

        XCTAssertTrue(game.isReplaying)
        XCTAssertEqual(game.plies.count, plyCount)
        XCTAssertFalse(game.isKingInCheck(at: Square("e1")!))
        XCTAssertEqual(history.cursor, .ply(0))

        history.returnToLive(in: game)
        XCTAssertFalse(game.isReplaying)
        XCTAssertEqual(history.cursor, .live)
        XCTAssertEqual(game.status, .checkmate(winner: .black))
    }

    func testGameDocumentRoundTripPromotionAndEnPassant() throws {
        let game = ChessGame()
        try game.load(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        play("e5", "d6", in: game)

        let document = GameDocument.make(
            from: game,
            name: "EP",
            forkPlyIndex: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameDocument.self, from: data)
        let moves = try decoded.decodedMoves()
        XCTAssertEqual(moves.count, 1)
        XCTAssertTrue(moves[0].isEnPassant)

        let reloaded = ChessGame()
        try reloaded.load(openingFEN: decoded.openingFEN, moves: moves)
        XCTAssertEqual(reloaded.plies.map(\.move), game.plies.map(\.move))
    }

    func testClearSelectionClearsParkedChoice() {
        let game = ChessGame()
        game.tap(Square("d1")!)
        XCTAssertEqual(game.selectedSquare, Square("d1")!)
        game.clearSelection()
        XCTAssertNil(game.selectedSquare)
        XCTAssertTrue(game.legalTargets.isEmpty)
    }
}

@MainActor
private func play(_ from: String, _ to: String, in game: ChessGame) {
    game.tap(Square(from)!)
    game.tap(Square(to)!)
    if game.pendingPromotion != nil {
        game.promote(to: .queen)
    }
}
