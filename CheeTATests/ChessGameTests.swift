import XCTest
@testable import CheeTA

@MainActor
final class ChessGameTests: XCTestCase {
    func testStartingPositionHasThirtyTwoPiecesAndWhiteMovesFirst() {
        let game = ChessGame()

        XCTAssertEqual(game.board.count, 32)
        XCTAssertEqual(game.currentPlayer, .white)
        XCTAssertEqual(game.status, .playing)
    }

    func testPawnCanMoveOneOrTwoSquaresFromStartingRank() {
        let game = ChessGame()
        let moves = Set(game.legalMoves(from: Square("e2")!))

        XCTAssertEqual(moves, Set([Square("e3")!, Square("e4")!]))
    }

    func testKnightCanJumpOverStartingPieces() {
        let game = ChessGame()
        let moves = Set(game.legalMoves(from: Square("g1")!))

        XCTAssertEqual(moves, Set([Square("f3")!, Square("h3")!]))
    }

    func testBlackMovablePiecesPulseAutomaticallyOnBlackTurn() {
        let game = ChessGame()

        play("e2", "e4", in: game)

        XCTAssertEqual(game.currentPlayer, .black)
        XCTAssertEqual(
            game.candidatePulseSquares,
            Set(["a7", "b7", "c7", "d7", "e7", "f7", "g7", "h7", "b8", "g8"].map { Square($0)! })
        )
    }

    func testWhiteMovablePiecesPulseAutomaticallyOnWhiteTurn() {
        let game = ChessGame()

        XCTAssertEqual(game.currentPlayer, .white)
        XCTAssertEqual(
            game.candidatePulseSquares,
            Set(["a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2", "b1", "g1"].map { Square($0)! })
        )
    }

    func testTappingWhitePiecesBuildsACandidatePulseSubset() {
        let game = ChessGame()
        game.beginChoosingCandidates()

        game.tap(Square("b1")!)
        game.tap(Square("g1")!)

        XCTAssertEqual(game.candidateSquares, Set([Square("b1")!, Square("g1")!]))
        XCTAssertEqual(game.candidatePulseSquares, game.candidateSquares)
    }

    func testTappingBlackPiecesBuildsACandidatePulseSubset() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        game.beginChoosingCandidates()

        game.tap(Square("b8")!)
        game.tap(Square("g8")!)

        XCTAssertEqual(game.candidateSquares, Set([Square("b8")!, Square("g8")!]))
        XCTAssertEqual(game.candidatePulseSquares, game.candidateSquares)

        game.clearCandidates()

        XCTAssertEqual(game.candidatePulseSquares, game.movableSquares(for: .black))
    }

    func testOrdinaryPieceSelectionDoesNotNarrowAutomaticCandidates() {
        let game = ChessGame()
        let allMovableWhitePieces = game.movableSquares(for: .white)

        game.tap(Square("e2")!)

        XCTAssertTrue(game.candidateSquares.isEmpty)
        XCTAssertEqual(game.candidatePulseSquares, allMovableWhitePieces)
    }

    func testFinishingCandidateChoiceKeepsTheChosenPulseSubset() {
        let game = ChessGame()
        game.beginChoosingCandidates()
        game.tap(Square("b1")!)
        game.tap(Square("g1")!)

        game.finishChoosingCandidates()

        XCTAssertFalse(game.isChoosingCandidates)
        XCTAssertEqual(game.candidatePulseSquares, Set([Square("b1")!, Square("g1")!]))
    }

    func testCandidateSelectionClearsAndPassesToTheNextPlayerAfterAMove() {
        let game = ChessGame()
        play("e2", "e4", in: game)

        play("b8", "c6", in: game)

        XCTAssertEqual(game.currentPlayer, .white)
        XCTAssertTrue(game.candidateSquares.isEmpty)
        XCTAssertEqual(game.candidatePulseSquares, game.movableSquares(for: .white))
    }

    func testPinnedPieceCannotExposeItsKing() {
        let board = makeBoard([
            ("e1", .king, .white),
            ("e2", .rook, .white),
            ("e8", .rook, .black),
            ("a8", .king, .black)
        ])
        let game = ChessGame(board: board)
        let moves = Set(game.legalMoves(from: Square("e2")!))

        XCTAssertFalse(moves.contains(Square("d2")!))
        XCTAssertTrue(moves.contains(Square("e3")!))
        XCTAssertTrue(moves.contains(Square("e8")!))
    }

    func testCheckmateIsDetected() {
        let board = makeBoard([
            ("f6", .king, .white),
            ("g7", .queen, .white),
            ("h8", .king, .black)
        ])
        let game = ChessGame(board: board, currentPlayer: .black)

        XCTAssertEqual(game.status, .checkmate(winner: .white))
    }

    func testStalemateIsDetected() {
        let board = makeBoard([
            ("f7", .king, .white),
            ("g6", .queen, .white),
            ("h8", .king, .black)
        ])
        let game = ChessGame(board: board, currentPlayer: .black)

        XCTAssertEqual(game.status, .stalemate)
    }

    func testPlayedMovesCanReachFoolsMate() {
        let game = ChessGame()

        play("f2", "f3", in: game)
        play("e7", "e5", in: game)
        play("g2", "g4", in: game)
        play("d8", "h4", in: game)

        XCTAssertEqual(game.status, .checkmate(winner: .black))
        XCTAssertEqual(game.currentPlayer, .white)
    }

    func testThreatCorridorUsesAttacksRatherThanLegalMoves() {
        let board = makeBoard([
            ("e1", .king, .white),
            ("c1", .bishop, .white),
            ("b2", .pawn, .white),
            ("f4", .pawn, .black),
            ("e8", .king, .black)
        ])
        let game = ChessGame(board: board)

        XCTAssertEqual(
            game.threatCorridors.first { $0.origin == Square("c1")! }?.threatenedSquares,
            Set([Square("b2")!, Square("d2")!, Square("e3")!, Square("f4")!])
        )
    }

    func testPassiveThreatCorridorFollowsItsPieceAfterAMove() {
        let game = ChessGame()

        play("g1", "f3", in: game)

        XCTAssertNil(game.threatCorridors.first { $0.origin == Square("g1")! })
        let movedKnight = game.threatCorridors.first { $0.origin == Square("f3")! }
        XCTAssertEqual(movedKnight?.piece, Piece(kind: .knight, player: .white))
        XCTAssertTrue(movedKnight?.threatenedSquares.contains(Square("e5")!) == true)
    }

    func testBishopPassivelyProjectsThroughOpenSquaresToEnemyQueen() {
        let game = ChessGame()
        play("d2", "d4", in: game)
        play("e7", "e5", in: game)
        play("c1", "g5", in: game)

        let bishop = game.threatCorridors.first { $0.origin == Square("g5")! }

        XCTAssertEqual(bishop?.piece, Piece(kind: .bishop, player: .white))
        XCTAssertTrue(bishop?.threatenedSquares.contains(Square("f6")!) == true)
        XCTAssertTrue(bishop?.threatenedSquares.contains(Square("e7")!) == true)
        XCTAssertTrue(bishop?.threatenedSquares.contains(Square("d8")!) == true)
        XCTAssertEqual(game.piece(at: Square("d8")!), Piece(kind: .queen, player: .black))
        let queenCorridor = game.threatCorridors(for: .enemyContact).first {
            $0.origin == Square("g5")! && $0.endpoint == Square("d8")!
        }
        XCTAssertEqual(
            queenCorridor?.threatenedSquares,
            Set([Square("f6")!, Square("e7")!, Square("d8")!])
        )
        XCTAssertFalse(queenCorridor?.threatenedSquares.contains(Square("f4")!) == true)
    }

    func testEnemyContactModeHidesCorridorsWithoutAnEnemyPiece() {
        let game = ChessGame()

        XCTAssertTrue(game.threatCorridors(for: .enemyContact).isEmpty)
        XCTAssertEqual(game.threatCorridors(for: .allThreats).count, 32)
    }

    func testNonSlidingEnemyContactEndsOnTheEnemySquareOnly() {
        let board = makeBoard([
            ("e1", .king, .white),
            ("f3", .knight, .white),
            ("e5", .pawn, .black),
            ("e8", .king, .black)
        ])
        let game = ChessGame(board: board)

        let knightCorridor = game.threatCorridors(for: .enemyContact).first {
            $0.origin == Square("f3")! && $0.endpoint == Square("e5")!
        }

        XCTAssertEqual(knightCorridor?.threatenedSquares, Set([Square("e5")!]))
    }

    func testCapturedPieceStopsContributingPassiveThreats() {
        let board = makeBoard([
            ("e1", .king, .white),
            ("a1", .rook, .white),
            ("a8", .rook, .black),
            ("h8", .king, .black)
        ])
        let game = ChessGame(board: board)

        play("a1", "a8", in: game)

        XCTAssertNil(game.threatCorridors.first {
            $0.piece == Piece(kind: .rook, player: .black)
        })
        XCTAssertEqual(game.threatCorridors.count, game.board.count)
    }

    func testOverlappingThreatsRetainEveryContributingTeamAndPiece() {
        let board = makeBoard([
            ("e1", .king, .white),
            ("d1", .rook, .white),
            ("a1", .bishop, .white),
            ("d8", .rook, .black),
            ("h8", .king, .black)
        ])
        let game = ChessGame(board: board)

        let overlapping = game.threatCorridors(
            reaching: Square("d4")!,
            mode: .enemyContact
        )

        XCTAssertEqual(overlapping.count, 3)
        XCTAssertEqual(overlapping.filter { $0.piece.player == .white }.count, 2)
        XCTAssertEqual(overlapping.filter { $0.piece.player == .black }.count, 1)
    }

    func testPositionPresetsArePlayableAndContainBothKings() {
        for preset in PositionPreset.allCases {
            let game = ChessGame()
            game.load(preset)

            XCTAssertEqual(game.positionPreset, preset)
            XCTAssertEqual(game.currentPlayer, .white)
            XCTAssertFalse(game.status.isFinished, "\(preset) should be playable")
            XCTAssertFalse(game.isInCheck(.white), "\(preset) should not start with White in check")
            XCTAssertFalse(game.isInCheck(.black), "\(preset) should not start with Black in check")
            XCTAssertEqual(game.board.values.filter { $0.kind == .king }.count, 2)
        }
    }

    func testPositionPresetsUseRecognizableStageMaterial() {
        let game = ChessGame()

        game.load(.opening)
        XCTAssertEqual(game.board.count, 32)
        XCTAssertEqual(game.piece(at: Square("c4")!), Piece(kind: .bishop, player: .white))
        XCTAssertEqual(game.piece(at: Square("f6")!), Piece(kind: .knight, player: .black))

        game.load(.midgame)
        XCTAssertEqual(game.board.count, 30)
        XCTAssertEqual(game.piece(at: Square("g1")!), Piece(kind: .king, player: .white))
        XCTAssertEqual(game.piece(at: Square("f1")!), Piece(kind: .rook, player: .white))

        game.load(.endgame)
        XCTAssertEqual(game.board.count, 14)
        XCTAssertEqual(game.board.values.filter { $0.kind == .rook }.count, 2)
        XCTAssertEqual(game.board.values.filter { $0.kind == .queen }.count, 0)
    }

    func testLoadingPresetClearsTransientPlayStateAndRebuildsThreatMap() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        game.tap(Square("e7")!)

        game.load(.endgame)

        XCTAssertNil(game.selectedSquare)
        XCTAssertTrue(game.legalTargets.isEmpty)
        XCTAssertNil(game.lastMove)
        XCTAssertEqual(game.threatCorridors.count, game.board.count)
    }

    private func makeBoard(_ entries: [(String, PieceKind, Player)]) -> [Square: Piece] {
        Dictionary(uniqueKeysWithValues: entries.map { notation, kind, player in
            (Square(notation)!, Piece(kind: kind, player: player))
        })
    }

    private func play(_ from: String, _ to: String, in game: ChessGame) {
        game.tap(Square(from)!)
        game.tap(Square(to)!)
    }
}
