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

    func testPlayedMoveCanEnterCheckBeforeCheckmate() {
        let game = ChessGame()

        play("e2", "e4", in: game)
        play("f7", "f6", in: game)
        play("d1", "h5", in: game)

        XCTAssertEqual(game.status, .check(.black))
        XCTAssertEqual(game.currentPlayer, .black)
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

    func testTurningThePulseOffSilencesItAndSurvivesARestart() {
        let game = ChessGame()

        XCTAssertFalse(game.candidatePulseSquares.isEmpty)

        game.setPulse(enabled: false)
        XCTAssertTrue(game.candidatePulseSquares.isEmpty)

        // A display preference, not game state: a restart must not undo it.
        game.reset()
        XCTAssertFalse(game.isPulseEnabled)
        XCTAssertTrue(game.candidatePulseSquares.isEmpty)

        game.setPulse(enabled: true)
        XCTAssertFalse(game.candidatePulseSquares.isEmpty)
    }

    func testTurningThePulseOffKeepsChosenCandidatesForLater() {
        let game = ChessGame()
        game.beginChoosingCandidates()
        game.tap(Square("e2")!)

        game.setPulse(enabled: false)

        XCTAssertFalse(game.isChoosingCandidates)
        XCTAssertEqual(game.candidateSquares, [Square("e2")!])

        game.setPulse(enabled: true)
        XCTAssertEqual(game.candidatePulseSquares, [Square("e2")!])
    }

    func testCaptureRecordsVictimCaptorAndSquare() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white),
                ("e8", .king, .black),
                ("d4", .bishop, .white),
                ("g7", .knight, .black)
            ])
        )

        XCTAssertNil(game.lastCapture)
        XCTAssertEqual(game.captureCount, 0)

        play("d4", "g7", in: game)

        XCTAssertEqual(game.captureCount, 1)
        XCTAssertEqual(game.lastCapture?.piece, Piece(kind: .knight, player: .black))
        XCTAssertEqual(game.lastCapture?.captor, Piece(kind: .bishop, player: .white))
        XCTAssertEqual(game.lastCapture?.square, Square("g7")!)
    }

    func testQuietMovesLeaveTheCaptureCountAlone() {
        let game = ChessGame()

        play("e2", "e4", in: game)

        XCTAssertNil(game.lastCapture)
        XCTAssertEqual(game.captureCount, 0)
    }

    func testResetAndLoadClearCaptureHistory() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white),
                ("e8", .king, .black),
                ("d4", .bishop, .white),
                ("g7", .knight, .black)
            ])
        )
        play("d4", "g7", in: game)
        XCTAssertEqual(game.captureCount, 1)

        game.reset()
        XCTAssertNil(game.lastCapture)
        XCTAssertEqual(game.captureCount, 0)

        play("e2", "e4", in: game)
        game.load(.endgame)
        XCTAssertNil(game.lastCapture)
        XCTAssertEqual(game.captureCount, 0)
    }

    func testEveryPlyIsRecordedWithThePositionItProduced() {
        let game = ChessGame()

        play("e2", "e4", in: game)
        play("d7", "d5", in: game)

        XCTAssertEqual(game.plies.count, 2)
        XCTAssertEqual(game.plies[0].move, ChessMove(from: Square("e2")!, to: Square("e4")!))
        XCTAssertEqual(game.plies[0].playerToMoveAfter, .black)
        XCTAssertEqual(game.plies[0].boardAfter[Square("e4")!], Piece(kind: .pawn, player: .white))
        XCTAssertNil(game.plies[0].boardAfter[Square("e2")!])
        XCTAssertNil(game.plies[1].capture)
    }

    func testWholeGameReplayStartsFromTheOpeningPosition() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("d7", "d5", in: game)

        let frames = game.replayFrames()

        XCTAssertEqual(frames.count, 3)
        XCTAssertNil(frames[0].move)
        XCTAssertEqual(frames[0].playerToMove, .white)
        XCTAssertEqual(frames[0].board[Square("e2")!], Piece(kind: .pawn, player: .white))
        XCTAssertEqual(frames[2].board[Square("d5")!], Piece(kind: .pawn, player: .black))
    }

    func testLimitedReplayStartsFromThePositionBeforeItsFirstPly() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("d7", "d5", in: game)
        play("g1", "f3", in: game)

        let frames = game.replayFrames(lastPlies: 1)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].board[Square("g1")!], Piece(kind: .knight, player: .white))
        XCTAssertEqual(frames[1].board[Square("f3")!], Piece(kind: .knight, player: .white))
    }

    func testReplayParksTheLiveGameAndRestoresIt() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("d7", "d5", in: game)
        let liveBoard = game.board

        let frames = game.replayFrames()
        game.beginReplay()
        game.show(frames[0])

        XCTAssertTrue(game.isReplaying)
        XCTAssertEqual(game.board[Square("e2")!], Piece(kind: .pawn, player: .white))

        // Taps are inert while the board belongs to the replay.
        play("e2", "e4", in: game)
        XCTAssertEqual(game.plies.count, 2)

        game.endReplay()

        XCTAssertFalse(game.isReplaying)
        XCTAssertEqual(game.board, liveBoard)
        XCTAssertEqual(game.currentPlayer, .white)
    }

    func testReplayFramesAreEmptyBeforeAnyMove() {
        XCTAssertTrue(ChessGame().replayFrames().isEmpty)
    }

    func testKingSideCastlingMovesTheRookAndRevokesRights() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white), ("h1", .rook, .white),
                ("a8", .king, .black)
            ]),
            castlingRights: CastlingRights(
                whiteKingSide: true,
                whiteQueenSide: false,
                blackKingSide: false,
                blackQueenSide: false
            )
        )

        XCTAssertTrue(game.legalMoves(from: Square("e1")!).contains(Square("g1")!))

        play("e1", "g1", in: game)

        XCTAssertEqual(game.piece(at: Square("g1")!), Piece(kind: .king, player: .white))
        XCTAssertEqual(game.piece(at: Square("f1")!), Piece(kind: .rook, player: .white))
        XCTAssertNil(game.piece(at: Square("h1")!))
        XCTAssertFalse(game.castlingRights.whiteKingSide)
        XCTAssertFalse(game.castlingRights.whiteQueenSide)
    }

    func testCastlingCannotCrossAnAttackedSquare() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white), ("h1", .rook, .white),
                ("f8", .rook, .black), ("a8", .king, .black)
            ]),
            castlingRights: CastlingRights(
                whiteKingSide: true,
                whiteQueenSide: false,
                blackKingSide: false,
                blackQueenSide: false
            )
        )

        XCTAssertFalse(game.legalMoves(from: Square("e1")!).contains(Square("g1")!))
    }

    func testMovingCornerRookRevokesThatSideOfCastling() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white), ("h1", .rook, .white),
                ("a8", .king, .black)
            ]),
            castlingRights: CastlingRights(
                whiteKingSide: true,
                whiteQueenSide: false,
                blackKingSide: false,
                blackQueenSide: false
            )
        )

        play("h1", "h2", in: game)

        XCTAssertFalse(game.castlingRights.whiteKingSide)
    }

    func testPromotionWaitsForAChoiceAndRecordsTheNewPiece() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white), ("a7", .pawn, .white),
                ("e8", .king, .black)
            ])
        )

        play("a7", "a8", in: game)

        XCTAssertEqual(game.pendingPromotion?.to, Square("a8")!)
        XCTAssertEqual(game.piece(at: Square("a7")!), Piece(kind: .pawn, player: .white))
        XCTAssertTrue(game.plies.isEmpty)

        game.promote(to: .knight)

        XCTAssertNil(game.pendingPromotion)
        XCTAssertEqual(game.piece(at: Square("a8")!), Piece(kind: .knight, player: .white))
        XCTAssertEqual(game.currentPlayer, .black)
        XCTAssertEqual(game.plies.last?.move.promotion, .knight)
    }

    func testPromotionCaptureRecordsThePawnAsCaptor() {
        let game = ChessGame(
            board: makeBoard([
                ("e1", .king, .white), ("b7", .pawn, .white),
                ("a8", .rook, .black), ("e8", .king, .black)
            ])
        )

        play("b7", "a8", in: game)
        game.promote(to: .queen)

        XCTAssertEqual(game.piece(at: Square("a8")!), Piece(kind: .queen, player: .white))
        XCTAssertEqual(game.lastCapture?.piece, Piece(kind: .rook, player: .black))
        XCTAssertEqual(game.lastCapture?.captor, Piece(kind: .pawn, player: .white))
    }

    func testEnPassantIsOfferedForExactlyTheReplyAfterATwoSquarePawnMove() {
        let game = ChessGame()

        play("e2", "e4", in: game)
        play("a7", "a6", in: game)
        play("e4", "e5", in: game)
        play("d7", "d5", in: game)

        XCTAssertEqual(game.enPassantTarget, Square("d6")!)
        XCTAssertEqual(
            game.lastEnPassantOpportunity,
            EnPassantOpportunity(
                target: Square("d6")!,
                vulnerablePawn: Square("d5")!,
                capturingPawns: [Square("e5")!],
                player: .white
            )
        )
        XCTAssertTrue(game.legalMoves(from: Square("e5")!).contains(Square("d6")!))

        // Declining the option ends it; it cannot be taken a move later.
        play("g1", "f3", in: game)
        play("a6", "a5", in: game)

        XCTAssertNil(game.enPassantTarget)
        XCTAssertFalse(game.legalMoves(from: Square("e5")!).contains(Square("d6")!))
    }

    func testEnPassantRemovesThePawnBesideTheLandingSquareAndRecordsIt() throws {
        let game = ChessGame()
        try game.load(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")

        XCTAssertTrue(game.legalMoves(from: Square("e5")!).contains(Square("d6")!))

        play("e5", "d6", in: game)

        XCTAssertEqual(game.piece(at: Square("d6")!), Piece(kind: .pawn, player: .white))
        XCTAssertNil(game.piece(at: Square("d5")!))
        XCTAssertEqual(game.lastCapture?.square, Square("d5")!)
        XCTAssertEqual(game.lastCapture?.piece, Piece(kind: .pawn, player: .black))
        XCTAssertEqual(game.lastEnPassant?.capturedPawn, Square("d5")!)
        XCTAssertTrue(game.plies.last?.move.isEnPassant == true)
        XCTAssertEqual(game.captureCount, 1)
    }

    func testPinnedPawnCannotUseEnPassantToExposeItsKing() throws {
        let game = ChessGame()
        try game.load(fen: "4r1k1/8/8/3pP3/8/8/8/4K3 w - d6 0 1")

        XCTAssertFalse(game.legalMoves(from: Square("e5")!).contains(Square("d6")!))
    }

    func testStartingPositionExportsStandardFEN() {
        XCTAssertEqual(
            ChessGame().fen,
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
    }

    func testFENLoadPreservesAllSixFieldsAndRoundTrips() throws {
        let fen = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq e3 17 42"
        let game = ChessGame()

        try game.load(fen: fen)

        XCTAssertEqual(game.currentPlayer, .black)
        XCTAssertEqual(game.piece(at: Square("a1")!), Piece(kind: .rook, player: .white))
        XCTAssertEqual(game.piece(at: Square("h8")!), Piece(kind: .rook, player: .black))
        XCTAssertEqual(game.enPassantTarget, Square("e3")!)
        XCTAssertEqual(game.halfmoveClock, 17)
        XCTAssertEqual(game.fullmoveNumber, 42)
        XCTAssertEqual(game.fen, fen)
    }

    func testInvalidFENLeavesTheCurrentGameAlone() {
        let game = ChessGame()
        let before = game.fen

        XCTAssertThrowsError(try game.load(fen: "not a fen"))

        XCTAssertEqual(game.fen, before)
    }

    func testUndoLastMoveRebuildsThePriorEnPassantPositionFromSequence() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("e7", "e5", in: game)

        XCTAssertEqual(game.undo(plies: 1), 1)

        XCTAssertEqual(
            game.fen,
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        )
        XCTAssertEqual(game.plies.count, 1)
        XCTAssertEqual(game.lastMove, ChessMove(from: Square("e2")!, to: Square("e4")!))
    }

    func testUndoTurnRestoresTheOpeningWithoutKeepingPerPlyRuleSnapshots() {
        let game = ChessGame()
        let openingFEN = game.fen

        play("e2", "e4", in: game)
        play("e7", "e5", in: game)

        XCTAssertEqual(game.undoTurn(), 2)
        XCTAssertEqual(game.fen, openingFEN)
        XCTAssertTrue(game.plies.isEmpty)
        XCTAssertNil(game.lastMove)
        XCTAssertEqual(game.currentPlayer, .white)
    }

    func testUndoRetainsCastlingHistoryFromTheRemainingSequence() throws {
        let game = ChessGame()
        try game.load(fen: "4k3/8/8/8/8/8/8/4K2R w K - 6 9")

        play("h1", "h2", in: game)
        play("e8", "e7", in: game)

        XCTAssertEqual(game.undo(plies: 1), 1)
        XCTAssertFalse(game.castlingRights.whiteKingSide)
        XCTAssertEqual(game.halfmoveClock, 7)
        XCTAssertEqual(game.fullmoveNumber, 9)
        XCTAssertEqual(game.currentPlayer, .black)
    }

    /// A replay interleaves per-ply material (cut scenes) with the board
    /// frames, so the frame-to-ply mapping has to stay exact.
    func testReplayFramesLineUpWithPliesFromTheReportedStartIndex() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("d7", "d5", in: game)
        play("e4", "d5", in: game)

        for limit in [nil, 1, 2, 10] as [Int?] {
            let start = game.replayStartIndex(lastPlies: limit)
            let frames = game.replayFrames(lastPlies: limit)

            XCTAssertEqual(frames.count, game.plies.count - start + 1)

            // frames.dropFirst()[offset] must be the position after ply
            // start + offset — that is what pins a cut scene to its move.
            for (offset, frame) in frames.dropFirst().enumerated() {
                let ply = game.plies[start + offset]
                XCTAssertEqual(frame.board, ply.boardAfter)
                XCTAssertEqual(frame.move, ply.move)
                XCTAssertEqual(frame.playerToMove, ply.playerToMoveAfter)
            }
        }
    }

    func testReplayStartIndexClampsToTheAvailableHistory() {
        let game = ChessGame()
        play("e2", "e4", in: game)
        play("d7", "d5", in: game)

        XCTAssertEqual(game.replayStartIndex(lastPlies: nil), 0)
        XCTAssertEqual(game.replayStartIndex(lastPlies: 99), 0)
        XCTAssertEqual(game.replayStartIndex(lastPlies: 1), 1)
        XCTAssertEqual(game.replayStartIndex(lastPlies: 0), 2)
        XCTAssertEqual(game.replayStartIndex(lastPlies: -5), 2)
    }

    func testGeneratedGamesAreDeterministicAndLegal() {
        let first = GameLibrary.generate(seed: 7)
        let second = GameLibrary.generate(seed: 7)
        let other = GameLibrary.generate(seed: 8)

        XCTAssertEqual(first.moves, second.moves, "the same seed must produce the same game")
        XCTAssertNotEqual(first.moves, other.moves)
        XCTAssertFalse(first.moves.isEmpty)

        // Both kings survive: random play through the real rules can never
        // capture a king, because that is not a legal move.
        let kings = first.finalBoard.values.filter { $0.kind == .king }
        XCTAssertEqual(kings.count, 2)
    }

    func testLoadingAStoredGameRestoresItsFullHistory() {
        let stored = GameLibrary.generate(seed: 3)
        let game = ChessGame()

        game.load(stored)

        XCTAssertEqual(game.plies.count, stored.moves.count)
        XCTAssertEqual(game.plies.map(\.move), stored.moves)
        XCTAssertEqual(game.board, stored.finalBoard)
        XCTAssertEqual(game.status, stored.result)
        XCTAssertNil(game.positionPreset)

        // History is real, so the whole game can be replayed from move one.
        XCTAssertEqual(game.replayFrames().count, stored.moves.count + 1)
    }

    func testLoadingAStoredGameTwiceDoesNotAccumulateHistory() {
        let stored = GameLibrary.generate(seed: 4)
        let game = ChessGame()

        game.load(stored)
        game.load(stored)

        XCTAssertEqual(game.plies.count, stored.moves.count)
    }

    func testEveryPlyRecordsTheVerdictItProduced() {
        let game = ChessGame()

        play("f2", "f3", in: game)
        play("e7", "e5", in: game)
        play("g2", "g4", in: game)
        play("d8", "h4", in: game)

        XCTAssertEqual(game.plies.last?.statusAfter, .checkmate(winner: .black))
        XCTAssertEqual(game.plies.first?.statusAfter, .playing)
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
