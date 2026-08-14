import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var game = ChessGame()
    @State private var threatDisplayMode: ThreatDisplayMode = .enemyContact
    @State private var boardDimension: BoardDimension = .threeD
    @State private var boardOpacity = 0.06
    @State private var piecePalette: PiecePalette = .arcade
    @State private var isLightLoose = false
    @State private var isSceneControlsPresented = false
    @State private var checkCutScene: CheckCutScene?
    @State private var firstCaptureCutScene: FirstCaptureCutScene?
    @State private var queenDownCutScene: QueenDownCutScene?
    @State private var enPassantOpportunityCutScene: EnPassantOpportunity?
    @State private var enPassantCaptureCutScene: EnPassantCapture?
    /// Every cut scene that fired this game, in order, for the reel.
    @State private var cutSceneLog: [CutSceneEvent] = []
    @State private var isReelPresented = false
    @State private var isFENTransferPresented = false
    @State private var isPieceGalleryPresented = false
    /// Reconstructing an earlier position should not replay its old cut scenes
    /// as if the player had just made those moves again.
    @State private var suppressCutSceneTriggers = false
    @State private var isGameBrowserPresented = false
    @StateObject private var replay = ReplayPlayer()
    @StateObject private var gameLibrary = GameLibrary()
    @StateObject private var history = HistoryController()
    @StateObject private var session = GameSession()
    @StateObject private var savedGames = SavedGameStore()
    @State private var inspectProbe: ChessGame?
    @State private var isApplyingCommittedMove = false
    @State private var windowIsLandscape = true
    @State private var fenSheetError: String?
    @State private var pendingReplacement: GameReplacement?
    @State private var abandonPrompt: AbandonPrompt?
    @State private var replaceDiscardedPrompt = false
    @State private var restoreDiscardedPrompt = false
    @AppStorage("historyPanePresented.compact") private var compactOverride: Bool?
    @AppStorage("historyPanePresented.regularPortrait") private var regularPortraitOverride: Bool?
    @AppStorage("historyPanePresented.regularLandscape") private var regularLandscapeOverride: Bool?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var autosaveTask: Task<Void, Never>?
    @State private var pendingCommit: PendingForkCommit?

    var body: some View {
        dialogs(attachedTo: stagedBoard)
    }

    private var stagedBoard: some View {
        gameStage
            .background { windowAspectReader }
            .onPreferenceChange(WindowAspectKey.self) { windowIsLandscape = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dialogs(attachedTo content: some View) -> some View {
        withScenes(withDialogs(content))
    }

    private func withDialogs<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: $isFENTransferPresented) {
            FENTransferSheet(
                currentFEN: game.fen,
                errorMessage: fenSheetError,
                onLoad: { notation in
                    fenSheetError = nil
                    replaceGame(.fen(notation))
                    if fenSheetError == nil, pendingReplacement == nil {
                        isFENTransferPresented = false
                    }
                }
            )
        }
        .sheet(isPresented: $isPieceGalleryPresented) {
            PieceGalleryView(palette: piecePalette)
        }
        .onChange(of: isPieceGalleryPresented) { _, isPresented in
            if isPresented, replay.isPlaying {
                replay.stop(in: game)
            }
        }
        .sheet(isPresented: $isGameBrowserPresented) {
            GameBrowserView(
                library: gameLibrary,
                savedGames: savedGames,
                palette: piecePalette
            ) { pick in
                switch pick {
                case .shelf(let stored):
                    replaceGame(.stored(stored))
                case .saved(let document):
                    replaceGame(.document(document))
                }
            }
        }
        .task { await savedGames.loadAll() }
        .alert("Save this game?", isPresented: abandonAlertPresented) {
            Button("Save") {
                saveCurrentGame(asCopy: false)
                if let pendingReplacement {
                    applyReplacement(pendingReplacement)
                    self.pendingReplacement = nil
                }
            }
            Button("Don't Save", role: .destructive) {
                if let pendingReplacement {
                    applyReplacement(pendingReplacement)
                    self.pendingReplacement = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingReplacement = nil
            }
        } message: {
            Text("“\(session.title)” has unsaved changes.")
        }
        .alert("Replace the discarded line?", isPresented: $replaceDiscardedPrompt) {
            Button("Replace", role: .destructive) {
                if let pendingCommit {
                    finishDifferentMoveCommit(pendingCommit, replacingDiscarded: true)
                    self.pendingCommit = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCommit = nil
            }
        }
        .alert("Replace the current game with the discarded line?", isPresented: $restoreDiscardedPrompt) {
            Button("Restore", role: .destructive) {
                if let discarded = session.discardedLine {
                    restoreDiscardedLine(discarded)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not load game", isPresented: storeErrorPresented) {
            Button("OK", role: .cancel) { savedGames.lastError = nil }
        } message: {
            Text(savedGames.lastError ?? "")
        }
        .onChange(of: session.title) { _, newTitle in
            session.noteContentChanged(
                openingFEN: game.openingFEN,
                moves: game.plies.map(\.move),
                title: newTitle
            )
            scheduleAutosave()
        }
        .onChange(of: game.plies) { _, _ in
            session.noteContentChanged(
                openingFEN: game.openingFEN,
                moves: game.plies.map(\.move),
                title: session.title
            )
            scheduleAutosave()
        }
    }

    private func withScenes<Content: View>(_ content: Content) -> some View {
        content
        .overlay {
            if let checkCutScene {
                CheckCutSceneView(checkedPlayer: checkCutScene.checkedPlayer) {
                    dismissCheckCutScene()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.08)))
                .zIndex(100)
                .task(id: checkCutScene.id) {
                    try? await Task.sleep(for: .seconds(2.4))
                    guard !Task.isCancelled else { return }
                    dismissCheckCutScene()
                }
            }
        }
        .overlay {
            if let firstCaptureCutScene {
                FirstCaptureCutSceneView(capture: firstCaptureCutScene.capture) {
                    dismissFirstCaptureCutScene()
                }
                .transition(.opacity)
                .zIndex(101)
                .task(id: firstCaptureCutScene.id) {
                    try? await Task.sleep(for: .seconds(2.9))
                    guard !Task.isCancelled else { return }
                    dismissFirstCaptureCutScene()
                }
            }
        }
        .overlay {
            if let queenDownCutScene {
                QueenDownCutSceneView(
                    capture: queenDownCutScene.capture,
                    moveNumber: queenDownCutScene.moveNumber
                ) {
                    dismissQueenDownCutScene()
                }
                .transition(.opacity)
                .zIndex(102)
                .task(id: queenDownCutScene.id) {
                    try? await Task.sleep(for: .seconds(3.6))
                    guard !Task.isCancelled else { return }
                    dismissQueenDownCutScene()
                }
            }
        }
        .overlay {
            if let enPassantOpportunityCutScene {
                EnPassantOpportunityCutSceneView(opportunity: enPassantOpportunityCutScene) {
                    dismissEnPassantOpportunityCutScene()
                }
                .transition(.opacity)
                .zIndex(103)
                .task(id: enPassantOpportunityCutScene.id) {
                    try? await Task.sleep(for: .seconds(3.1))
                    guard !Task.isCancelled else { return }
                    dismissEnPassantOpportunityCutScene()
                }
            }
        }
        .overlay {
            if let enPassantCaptureCutScene {
                EnPassantCaptureCutSceneView(capture: enPassantCaptureCutScene) {
                    dismissEnPassantCaptureCutScene()
                }
                .transition(.opacity)
                .zIndex(104)
                .task(id: enPassantCaptureCutScene.id) {
                    try? await Task.sleep(for: .seconds(3.3))
                    guard !Task.isCancelled else { return }
                    dismissEnPassantCaptureCutScene()
                }
            }
        }
        .overlay {
            if let promotion = history.isInspecting ? history.pendingPromotion : game.pendingPromotion {
                PromotionPicker(player: promotion.pawn.player) { kind in
                    withAnimation(.snappy(duration: 0.18)) {
                        if history.isInspecting {
                            inspectProbe?.promote(to: kind)
                            history.pendingPromotion = inspectProbe?.pendingPromotion
                            history.selectedSquare = inspectProbe?.selectedSquare
                            history.legalTargets = inspectProbe?.legalTargets ?? []
                            if let move = inspectProbe?.plies.last?.move {
                                commitInspectedMove(move)
                            }
                        } else {
                            game.promote(to: kind)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(105)
            }
        }
        .overlay {
            if let event = replay.activeCutScene {
                CutSceneCardView(event: event, secondsOnScreen: 2.2)
                    .id(event.id)
                    .transition(.opacity)
                .zIndex(105)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: replay.activeCutScene)
        .overlay {
            if isReelPresented, !cutSceneLog.isEmpty {
                CutSceneReelView(events: cutSceneLog) {
                    withAnimation(.easeOut(duration: 0.26)) {
                        isReelPresented = false
                    }
                }
                .transition(.opacity)
                .zIndex(106)
            }
        }
        .sensoryFeedback(.warning, trigger: checkCutScene?.id)
        .sensoryFeedback(.impact(weight: .heavy), trigger: firstCaptureCutScene?.id)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: queenDownCutScene?.id)
        .sensoryFeedback(.selection, trigger: enPassantOpportunityCutScene?.id)
        .sensoryFeedback(.success, trigger: enPassantCaptureCutScene?.id)
        .onChange(of: game.captureCount) { _, newCount in
            guard !suppressCutSceneTriggers,
                  newCount > 0,
                  let capture = game.lastCapture else { return }
            guard game.lastEnPassant == nil else { return }

            // A queen outranks first blood, including when she *is* first blood.
            if capture.piece.kind == .queen {
                presentQueenDownCutScene(for: capture)
            } else if newCount == 1 {
                presentFirstCaptureCutScene(for: capture)
            }
        }
        .onChange(of: game.status) { _, newStatus in
            guard !suppressCutSceneTriggers else { return }
            switch newStatus {
            case .check(let checkedPlayer):
                record(.check(checkedPlayer))
                presentCheckCutScene(for: checkedPlayer)
            case .checkmate(let winner):
                record(.checkmate(winner: winner))
                presentCheckCutScene(for: winner.opponent)
            case .playing, .stalemate:
                break
            }
        }
        .onChange(of: game.lastEnPassantOpportunity) { _, opportunity in
            guard !suppressCutSceneTriggers, let opportunity else { return }
            record(.enPassantAvailable(opportunity))
            presentEnPassantOpportunityCutScene(for: opportunity)
        }
        .onChange(of: game.lastEnPassant) { _, capture in
            guard !suppressCutSceneTriggers, let capture else { return }
            record(.enPassantTaken(capture))
            presentEnPassantCaptureCutScene(for: capture)
        }
        .onChange(of: game.plies.count) { _, newCount in
            // A restart or a preset load empties the history; the reel goes too.
            if newCount == 0 {
                cutSceneLog.removeAll()
            }
        }
        .onChange(of: replay.isPlaying) { _, playing in
            if !playing, !history.isInspecting {
                DispatchQueue.main.async { suppressCutSceneTriggers = false }
            }
        }
    }

    private func startReplay(lastPlies: Int?) {
        if isApplyingCommittedMove { return }
        if history.isInspecting {
            inspectProbe = nil
            history.returnToLive(in: game)
        }

        let frames = game.replayFrames(lastPlies: lastPlies)
        guard let opening = frames.first else { return }

        let start = game.replayStartIndex(lastPlies: lastPlies)
        var steps: [ReplayStep] = [.position(opening)]

        for (offset, frame) in frames.dropFirst().enumerated() {
            let plyIndex = start + offset
            steps.append(.position(frame))

            for event in cutSceneLog where event.plyIndex == plyIndex {
                steps.append(.cutScene(event))
            }
        }

        suppressCutSceneTriggers = true
        replay.play(
            steps,
            title: lastPlies == nil ? "Replay" : "Last \(lastPlies!)",
            in: game,
            replayStartIndex: start
        )
    }

    private func undo(plies: Int) {
        suppressCutSceneTriggers = true
        let undone = game.undo(plies: plies)
        guard undone > 0 else {
            suppressCutSceneTriggers = false
            return
        }

        cutSceneLog.removeAll { $0.plyIndex >= game.plies.count }
        isReelPresented = false
        checkCutScene = nil
        firstCaptureCutScene = nil
        queenDownCutScene = nil
        enPassantOpportunityCutScene = nil
        enPassantCaptureCutScene = nil

        // SwiftUI delivers the game publications in this update pass; release
        // suppression only after it has had a chance to observe them.
        DispatchQueue.main.async {
            suppressCutSceneTriggers = false
        }
    }

    private var canUndoFromMenu: Bool {
        !isApplyingCommittedMove && !game.plies.isEmpty && game.pendingPromotion == nil
    }

    private func undoFromMenu(plies: Int) {
        if isApplyingCommittedMove { return }
        if history.isInspecting {
            returnToLive()
        }
        undo(plies: plies)
    }

    private enum HistoryPaneSlot: String {
        case compact
        case regularPortrait
        case regularLandscape
    }

    private var historyPaneSlot: HistoryPaneSlot {
        if horizontalSizeClass == .compact { return .compact }
        return windowIsLandscape ? .regularLandscape : .regularPortrait
    }

    private var isHistoryPresented: Binding<Bool> {
        Binding(
            get: {
                switch historyPaneSlot {
                case .compact: compactOverride ?? false
                case .regularPortrait: regularPortraitOverride ?? false
                case .regularLandscape: regularLandscapeOverride ?? true
                }
            },
            set: { newValue in
                switch historyPaneSlot {
                case .compact: compactOverride = newValue
                case .regularPortrait: regularPortraitOverride = newValue
                case .regularLandscape: regularLandscapeOverride = newValue
                }
            }
        )
    }

    private var abandonAlertPresented: Binding<Bool> {
        Binding(
            get: { abandonPrompt != nil },
            set: { if !$0 { abandonPrompt = nil } }
        )
    }

    private var storeErrorPresented: Binding<Bool> {
        Binding(
            get: { savedGames.lastError != nil },
            set: { if !$0 { savedGames.lastError = nil } }
        )
    }

    private func handleBoardTap(_ square: Square) {
        if isApplyingCommittedMove { return }
        if replay.isPlaying {
            replay.stop(in: game)
            return
        }
        if history.isInspecting {
            handleInspectSelection(square)
            return
        }
        game.tap(square)
    }

    private func inspect(_ target: HistoryCursor) {
        if isApplyingCommittedMove { return }
        if replay.isPlaying { replay.stop(in: game) }
        suppressCutSceneTriggers = true
        history.show(target, in: game)
        prepareInspectProbe(for: target)
    }

    private func returnToLive() {
        if replay.isPlaying { replay.stop(in: game) }
        inspectProbe = nil
        history.returnToLive(in: game)
        DispatchQueue.main.async { suppressCutSceneTriggers = false }
    }

    private func prepareInspectProbe(for target: HistoryCursor) {
        do {
            inspectProbe = try makeInspectProbe(for: target, live: game)
            history.selectedSquare = inspectProbe?.selectedSquare
            history.legalTargets = inspectProbe?.legalTargets ?? []
            history.pendingPromotion = inspectProbe?.pendingPromotion
        } catch {
            savedGames.report(error.localizedDescription)
            returnToLive()
        }
    }

    private func makeInspectProbe(for cursor: HistoryCursor, live: ChessGame) throws -> ChessGame {
        let prefix: [ChessMove]
        switch cursor {
        case .live:
            preconditionFailure("not inspecting")
        case .opening:
            prefix = []
        case .ply(let n):
            prefix = Array(live.plies.prefix(n + 1).map(\.move))
        }
        let probe = ChessGame()
        try probe.load(openingFEN: live.openingFEN, moves: prefix)
        return probe
    }

    private func handleInspectSelection(_ square: Square) {
        guard let probe = inspectProbe else { return }
        probe.tap(square)
        history.selectedSquare = probe.selectedSquare
        history.legalTargets = probe.legalTargets
        history.pendingPromotion = probe.pendingPromotion
        if probe.pendingPromotion == nil, let move = probe.plies.last?.move,
           probe.plies.count == inspectPrefixCount + 1 {
            commitInspectedMove(move)
        }
    }

    private var inspectPrefixCount: Int {
        switch history.cursor {
        case .live: 0
        case .opening: 0
        case .ply(let n): n + 1
        }
    }

    private func commitInspectedMove(_ move: ChessMove) {
        let suffix: [ChessMove]
        let forkPlyIndex: Int?
        switch history.cursor {
        case .live:
            return
        case .opening:
            suffix = game.plies.map(\.move)
            forkPlyIndex = nil
        case .ply(let n):
            suffix = Array(game.plies.dropFirst(n + 1).map(\.move))
            forkPlyIndex = n
        }

        if suffix.first == move {
            if suffix.count == 1 {
                returnToLive()
            } else if case .ply(let n) = history.cursor {
                inspect(.ply(n + 1))
            } else {
                inspect(.ply(0))
            }
            return
        }

        if suffix.isEmpty {
            playCommittedMoveOnLiveLine(move, truncateBy: 0, onApplied: {})
            return
        }

        let pending = PendingForkCommit(move: move, suffix: suffix, forkPlyIndex: forkPlyIndex)
        if session.replaceDiscardedConfirmationNeeded() {
            pendingCommit = pending
            replaceDiscardedPrompt = true
            return
        }
        finishDifferentMoveCommit(pending, replacingDiscarded: false)
    }

    private func finishDifferentMoveCommit(_ pending: PendingForkCommit, replacingDiscarded: Bool) {
        if replacingDiscarded || session.discardedLine == nil {
            let prefix: [ChessMove]
            switch history.cursor {
            case .ply(let n): prefix = Array(game.plies.prefix(n + 1).map(\.move))
            case .opening: prefix = []
            case .live: prefix = game.plies.map(\.move)
            }
            session.storeDiscarded(
                session.snapshotDiscarded(
                    openingFEN: game.openingFEN,
                    prefix: prefix,
                    suffix: pending.suffix
                )
            )
        }

        let capturedParent = session.documentID
        let capturedFork = pending.forkPlyIndex
        let capturedTitle = session.title
        playCommittedMoveOnLiveLine(pending.move, truncateBy: pending.suffix.count) {
            if let parentID = capturedParent {
                let newID = UUID()
                session.noteForkCommitted(
                    newID: newID,
                    parentID: parentID,
                    forkPlyIndex: capturedFork,
                    title: capturedTitle
                )
                let doc = GameDocument.make(
                    from: game,
                    id: newID,
                    name: capturedTitle,
                    parentID: parentID,
                    forkPlyIndex: capturedFork
                )
                try? savedGames.save(doc)
                session.markSaved(doc)
            } else {
                session.noteForkCommitted(
                    newID: nil,
                    parentID: nil,
                    forkPlyIndex: capturedFork,
                    title: capturedTitle
                )
            }
        }
    }

    private func playCommittedMoveOnLiveLine(
        _ move: ChessMove,
        truncateBy suffixCount: Int,
        onApplied: @escaping () -> Void
    ) {
        suppressCutSceneTriggers = true
        inspectProbe = nil
        history.pendingPromotion = nil
        history.returnToLive(in: game)
        if suffixCount > 0 {
            let undone = game.undo(plies: suffixCount)
            if undone != suffixCount {
                savedGames.report("Could not fork from this position.")
                DispatchQueue.main.async { suppressCutSceneTriggers = false }
                return
            }
            cutSceneLog.removeAll { $0.plyIndex >= game.plies.count }
        }
        game.clearSelection()
        isApplyingCommittedMove = true
        DispatchQueue.main.async {
            suppressCutSceneTriggers = false
            apply(move, to: game)
            onApplied()
            isApplyingCommittedMove = false
        }
    }

    private func apply(_ move: ChessMove, to game: ChessGame) {
        game.tap(move.from)
        game.tap(move.to)
        if let promotion = move.promotion {
            game.promote(to: promotion)
        }
    }

    private func replaceGame(_ replacement: GameReplacement) {
        if isApplyingCommittedMove { return }
        switch replacement {
        case .fen(let notation):
            do {
                try ChessGame.validateFEN(notation)
            } catch {
                fenSheetError = error.localizedDescription
                return
            }
        case .document(let document):
            do {
                try ChessGame.validateFEN(document.openingFEN)
            } catch {
                savedGames.report("This game’s opening FEN is invalid.")
                return
            }
        default:
            break
        }

        if session.isDirty {
            pendingReplacement = replacement
            abandonPrompt = .abandon
            return
        }
        applyReplacement(replacement)
    }

    private func applyReplacement(_ replacement: GameReplacement) {
        if replay.isPlaying { replay.stop(in: game) }
        inspectProbe = nil
        history.returnToLive(in: game)
        suppressCutSceneTriggers = true
        dismissLiveCutScenes()
        switch replacement {
        case .reset:
            game.reset()
            session.noteNewGame(title: "New game", openingFEN: OpeningSnapshot.standardFEN)
        case .preset(let preset):
            game.load(preset)
            session.noteNewGame(title: preset.displayName, openingFEN: game.openingFEN)
        case .fen(let notation):
            try? game.load(fen: notation)
            session.noteNewGame(title: "Position", openingFEN: game.openingFEN)
        case .stored(let stored):
            game.load(stored)
            session.noteLoadedShelf(
                name: stored.name,
                moves: stored.moves,
                openingFEN: OpeningSnapshot.standardFEN
            )
        case .document(let document):
            do {
                try game.load(openingFEN: document.openingFEN, moves: try document.decodedMoves())
                session.noteLoadedDocument(document)
            } catch is GameLoadError {
                session.noteLoadedDocument(document)
                session.noteContentChanged(
                    openingFEN: game.openingFEN,
                    moves: game.plies.map(\.move),
                    title: document.name
                )
                savedGames.report("Loaded up to the last legal move.")
            } catch {
                savedGames.report(error.localizedDescription)
            }
        }
        cutSceneLog = CutSceneEvent.derived(from: game.plies)
        DispatchQueue.main.async { suppressCutSceneTriggers = false }
    }

    private func dismissLiveCutScenes() {
        checkCutScene = nil
        firstCaptureCutScene = nil
        queenDownCutScene = nil
        enPassantOpportunityCutScene = nil
        enPassantCaptureCutScene = nil
    }

    private func saveCurrentGame(asCopy: Bool) {
        let id = asCopy || session.documentID == nil ? UUID() : session.documentID!
        let createdAt = (!asCopy ? savedGames.document(id: id)?.createdAt : nil) ?? Date()
        let document = GameDocument.make(
            from: game,
            id: id,
            name: session.title.isEmpty ? Self.defaultGameTitle() : session.title,
            createdAt: createdAt,
            parentID: asCopy ? nil : session.parentID,
            forkPlyIndex: asCopy ? nil : session.forkPlyIndex
        )
        do {
            try savedGames.save(document)
            session.markSaved(document)
        } catch {
            savedGames.report(error.localizedDescription)
        }
    }

    private func scheduleAutosave() {
        guard session.documentID != nil, session.isDirty else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveCurrentGame(asCopy: false)
        }
    }

    private func requestRestoreDiscarded() {
        guard session.discardedLine != nil else { return }
        if session.documentID != nil {
            restoreDiscardedPrompt = true
        } else if let discarded = session.discardedLine {
            restoreDiscardedLine(discarded)
        }
    }

    private func restoreDiscardedLine(_ discarded: DiscardedLine) {
        if replay.isPlaying { replay.stop(in: game) }
        suppressCutSceneTriggers = true
        inspectProbe = nil
        history.returnToLive(in: game)
        do {
            try game.load(openingFEN: discarded.openingFEN, moves: discarded.prefix + discarded.suffix)
            cutSceneLog = CutSceneEvent.derived(from: game.plies)
            session.restoreIdentity(from: discarded)
            session.noteContentChanged(
                openingFEN: game.openingFEN,
                moves: game.plies.map(\.move),
                title: discarded.title
            )
            session.clearDiscarded()
        } catch {
            savedGames.report(error.localizedDescription)
        }
        DispatchQueue.main.async { suppressCutSceneTriggers = false }
    }

    private static func defaultGameTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Game \(formatter.string(from: Date()))"
    }

    private func record(_ kind: CutSceneEvent.Kind) {
        cutSceneLog.append(
            CutSceneEvent(
                kind: kind,
                moveNumber: max(1, (game.plies.count + 1) / 2),
                // The ply that just landed is the one that caused this.
                plyIndex: game.plies.count - 1
            )
        )
    }

    private func presentFirstCaptureCutScene(for capture: Capture) {
        record(.firstBlood(capture))

        withAnimation(.snappy(duration: 0.16)) {
            // A capture that also gives check gets one scene, not two.
            checkCutScene = nil
            firstCaptureCutScene = FirstCaptureCutScene(capture: capture)
        }
    }

    private func dismissFirstCaptureCutScene() {
        withAnimation(.easeOut(duration: 0.22)) {
            firstCaptureCutScene = nil
        }
    }

    private func presentQueenDownCutScene(for capture: Capture) {
        record(.queenDown(capture))

        withAnimation(.snappy(duration: 0.16)) {
            checkCutScene = nil
            firstCaptureCutScene = nil
            queenDownCutScene = QueenDownCutScene(
                capture: capture,
                moveNumber: (game.plies.count + 1) / 2
            )
        }
    }

    private func dismissQueenDownCutScene() {
        withAnimation(.easeOut(duration: 0.26)) {
            queenDownCutScene = nil
        }
    }

    private func presentEnPassantOpportunityCutScene(for opportunity: EnPassantOpportunity) {
        withAnimation(.snappy(duration: 0.16)) {
            checkCutScene = nil
            enPassantOpportunityCutScene = opportunity
        }
    }

    private func dismissEnPassantOpportunityCutScene() {
        withAnimation(.easeOut(duration: 0.22)) {
            enPassantOpportunityCutScene = nil
        }
    }

    private func presentEnPassantCaptureCutScene(for capture: EnPassantCapture) {
        withAnimation(.snappy(duration: 0.18)) {
            checkCutScene = nil
            firstCaptureCutScene = nil
            queenDownCutScene = nil
            enPassantOpportunityCutScene = nil
            enPassantCaptureCutScene = capture
        }
    }

    private func dismissEnPassantCaptureCutScene() {
        withAnimation(.easeOut(duration: 0.24)) {
            enPassantCaptureCutScene = nil
        }
    }

    private func presentCheckCutScene(for checkedPlayer: Player) {
        guard firstCaptureCutScene == nil,
              queenDownCutScene == nil,
              enPassantOpportunityCutScene == nil,
              enPassantCaptureCutScene == nil else { return }

        withAnimation(.snappy(duration: 0.18)) {
            checkCutScene = CheckCutScene(checkedPlayer: checkedPlayer)
        }
    }

    private func dismissCheckCutScene() {
        withAnimation(.easeOut(duration: 0.18)) {
            checkCutScene = nil
        }
    }

    @ViewBuilder
    private var gameStage: some View {
        ZStack {
            Color(.systemBackground)
            if !isPieceGalleryPresented {
                primaryColumn
            }
        }
    }

    private var primaryColumn: some View {
        NavigationStack {
            VStack(spacing: 20) {
                board
                    .overlay(alignment: .bottom) { replayOverlay }
                    .animation(.snappy(duration: 0.24), value: replay.progress)
                controlBar
            }
            .padding(24)
            .toolbar(.hidden, for: .navigationBar)
            .inspector(isPresented: isHistoryPresented) {
                historyPane
                    .inspectorColumnWidth(min: 260, ideal: 304, max: 380)
            }
        }
    }

    @ViewBuilder
    private var replayOverlay: some View {
        if let progress = replay.progress {
            ReplayBadge(progress: progress) {
                replay.stop(in: game)
            }
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var historyPane: some View {
        MoveHistoryPane(
            game: game,
            history: history,
            session: session,
            replay: replay,
            savedGames: savedGames,
            canSave: true,
            onInspect: inspect,
            onReturnToLive: returnToLive,
            onSave: { saveCurrentGame(asCopy: false) },
            onSaveAs: { saveCurrentGame(asCopy: true) },
            onRestoreDiscarded: requestRestoreDiscarded,
            onOpenSibling: { replaceGame(.document($0)) }
        )
    }

    private var windowAspectReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: WindowAspectKey.self,
                value: geo.size.width > geo.size.height
            )
        }
    }

    @ViewBuilder
    private var board: some View {
        switch boardDimension {
        case .threeD:
            // A wide frame: the 3D scene is a set, not a board, and the light
            // needs somewhere to fly.
            RealityChessBoardView(
                game: game,
                threatDisplayMode: threatDisplayMode,
                boardOpacity: Float(boardOpacity),
                piecePalette: piecePalette,
                isLightLoose: isLightLoose,
                onTap: handleBoardTap,
                inspectSelectedSquare: history.isInspecting ? history.selectedSquare : nil,
                inspectLegalTargets: history.isInspecting ? history.legalTargets : nil
            )
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: 1100)
            .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
        case .twoD:
            ChessBoardView(
                game: game,
                threatDisplayMode: threatDisplayMode,
                piecePalette: piecePalette,
                onTap: handleBoardTap,
                selectedSquare: history.isInspecting ? history.selectedSquare : game.selectedSquare,
                legalTargets: history.isInspecting ? history.legalTargets : game.legalTargets
            )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 720, maxHeight: 720)
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        }
    }

    /// Every control collapses to one icon. Pick-one settings live in menus;
    /// the scene group needs a popover because a knob cannot live in a menu.
    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                isSceneControlsPresented = true
            } label: {
                controlIcon(boardDimension.systemImage, isActive: isSceneControlsPresented)
            }
            .accessibilityLabel("Scene")
            .accessibilityHint("Board dimension, opacity, piece colors, and the light")
            .popover(isPresented: $isSceneControlsPresented) {
                sceneControls
                    .frame(idealWidth: 340)
                    .presentationCompactAdaptation(.popover)
            }

            Menu {
                Section("Threat display") {
                    Picker("Threat display", selection: $threatDisplayMode) {
                        ForEach(ThreatDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
                Text("Enemy Contact shows only corridors that end on an opposing piece. Border weight still shows stacking.")
            } label: {
                controlIcon(
                    "shield.lefthalf.filled",
                    tint: .teal,
                    isActive: threatDisplayMode == .allThreats
                )
            }
            .accessibilityLabel("Threats")

            if !game.status.isFinished {
                Menu {
                    Section("Candidates") {
                        candidateActions
                    }
                    // Picking candidates only decides what pulses.
                    .disabled(!game.isPulseEnabled)

                    Section {
                        Button {
                            game.setPulse(enabled: !game.isPulseEnabled)
                        } label: {
                            Label(
                                game.isPulseEnabled ? "Turn off pulsing" : "Turn on pulsing",
                                systemImage: game.isPulseEnabled ? "circle.slash" : "circle.dotted"
                            )
                        }
                    }
                } label: {
                    controlIcon(
                        "sparkles",
                        tint: .orange,
                        isActive: game.isChoosingCandidates || !game.candidateSquares.isEmpty
                    )
                }
                .accessibilityLabel("Candidates")
            }

            Menu {
                Button {
                    undoFromMenu(plies: 1)
                } label: {
                    Label("Undo last move", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    undoFromMenu(plies: 2)
                } label: {
                    Label("Undo local turn (2 moves)", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(game.plies.count < 2)
            } label: {
                controlIcon("arrow.uturn.backward", tint: .orange)
            }
            .disabled(!canUndoFromMenu)
            .accessibilityLabel("Undo")
            .accessibilityHint("Choose to undo the last move or the last local turn")

            Button {
                isHistoryPresented.wrappedValue.toggle()
            } label: {
                controlIcon("list.bullet.rectangle", tint: .indigo, isActive: isHistoryPresented.wrappedValue)
            }
            .accessibilityLabel("Move history")
            .accessibilityHint("Shows or hides the move list")

            Menu {
                Section {
                    Button {
                        isGameBrowserPresented = true
                    } label: {
                        Label("Browse games…", systemImage: "square.grid.2x2")
                    }
                }

                Section("Jump to a position") {
                    ForEach(PositionPreset.allCases) { preset in
                        Button {
                            replaceGame(.preset(preset))
                        } label: {
                            Label(
                                preset.displayName,
                                systemImage: game.positionPreset == preset
                                    ? "checkmark"
                                    : preset.systemImage
                            )
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        replaceGame(.reset)
                    } label: {
                        Label("Restart game", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                controlIcon("flag.checkered", tint: .blue)
            }
            .accessibilityLabel("Positions")

            Button {
                isFENTransferPresented = true
            } label: {
                controlIcon("arrow.left.arrow.right.square", tint: .indigo)
            }
            .accessibilityLabel("Position code")
            .accessibilityHint("Copy or load a FEN position")

            Button {
                isPieceGalleryPresented = true
            } label: {
                controlIcon("cube.transparent", tint: .purple)
            }
            .accessibilityLabel("Piece gallery")
            .accessibilityHint("Inspect each chess piece up close")

            Menu {
                Section("Replay") {
                    Button {
                        startReplay(lastPlies: nil)
                    } label: {
                        Label("Replay whole game", systemImage: "play.circle")
                    }

                    Button {
                        startReplay(lastPlies: 10)
                    } label: {
                        Label("Replay last 10 moves", systemImage: "gobackward.10")
                    }
                    .disabled(game.plies.count <= 1)
                }

                Section {
                    Button {
                        isReelPresented = true
                    } label: {
                        Label(
                            "Cut scene reel (\(cutSceneLog.count))",
                            systemImage: "film.stack"
                        )
                    }
                    .disabled(cutSceneLog.isEmpty)
                }
            } label: {
                controlIcon(
                    "play.rectangle",
                    tint: .green,
                    isActive: replay.isPlaying
                )
            }
            .disabled(game.plies.isEmpty && cutSceneLog.isEmpty)
            .accessibilityLabel("Replay")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func controlIcon(
        _ systemImage: String,
        tint: Color = .indigo,
        isActive: Bool = false
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .frame(width: 46, height: 46)
            .background {
                Circle()
                    .fill(isActive ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)))
            }
            .contentShape(Circle())
            .animation(.snappy(duration: 0.2), value: isActive)
    }

    private var sceneControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Board dimension", selection: $boardDimension) {
                ForEach(BoardDimension.allCases) { dimension in
                    Label(dimension.displayName, systemImage: dimension.systemImage)
                        .tag(dimension)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Switches between the 3D and classic board renderers")

            if boardDimension == .threeD {
                boardAppearanceControls
            }
        }
        .padding(20)
    }

    private var boardAppearanceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                BoardOpacityKnob(value: $boardOpacity)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Board opacity", systemImage: "square.opacity")
                        .font(.headline)
                    Text(boardOpacityHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            pieceColorControls

            Button {
                isLightLoose.toggle()
            } label: {
                Label(
                    isLightLoose ? "Catch the light" : "Loose the light",
                    systemImage: isLightLoose ? "lightbulb.slash.fill" : "lightbulb.max.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isLightLoose ? .pink : .indigo)
            .sensoryFeedback(.impact, trigger: isLightLoose)
            .accessibilityHint(
                isLightLoose
                    ? "Returns the light to a fixed position above the board"
                    : "Sends the light careening around the board"
            )
        }
    }

    /// Named palettes seed the four colors; the pickers take it from there.
    private var pieceColorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Piece colors", systemImage: "paintpalette")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(PiecePalette.presets) { preset in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            piecePalette = preset.palette
                        }
                    } label: {
                        presetSwatch(preset)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.name) palette")
                }
            }

            VStack(spacing: 8) {
                ColorPicker("White pieces", selection: $piecePalette.whitePiece, supportsOpacity: false)
                ColorPicker("White accents", selection: $piecePalette.whiteAccent, supportsOpacity: false)
                ColorPicker("Black pieces", selection: $piecePalette.blackPiece, supportsOpacity: false)
                ColorPicker("Black accents", selection: $piecePalette.blackAccent, supportsOpacity: false)
            }
            .font(.subheadline)
        }
    }

    private func presetSwatch(_ preset: PiecePalette.Preset) -> some View {
        let isActive = piecePalette == preset.palette

        return VStack(spacing: 5) {
            HStack(spacing: 0) {
                preset.palette.whitePiece
                preset.palette.whiteAccent
                preset.palette.blackAccent
                preset.palette.blackPiece
            }
            .frame(height: 26)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? Color.accentColor : .primary.opacity(0.18), lineWidth: isActive ? 2.5 : 1)
            }

            Text(preset.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var boardOpacityHint: String {
        if boardOpacity < 0.005 {
            return "Board hidden — pieces float in space. Squares are still tappable. Tap the hub to bring it back."
        }
        return "Twist the dial to fade the board. Tap the hub to hide it entirely."
    }

    @ViewBuilder
    private var candidateActions: some View {
        if game.isChoosingCandidates {
            Button {
                game.finishChoosingCandidates()
            } label: {
                Label("Done choosing", systemImage: "checkmark.circle")
            }
        } else {
            Button {
                game.beginChoosingCandidates()
            } label: {
                Label("Choose candidates", systemImage: "hand.tap")
            }

            if !game.candidateSquares.isEmpty {
                Button {
                    game.clearCandidates()
                } label: {
                    Label("Pulse all pieces", systemImage: "sparkles")
                }
            }
        }
    }

}

private struct CheckCutScene: Identifiable, Equatable {
    let id = UUID()
    let checkedPlayer: Player
}

private struct FirstCaptureCutScene: Identifiable, Equatable {
    let id = UUID()
    let capture: Capture
}

private struct QueenDownCutScene: Identifiable, Equatable {
    let id = UUID()
    let capture: Capture
    let moveNumber: Int
}

private enum BoardDimension: String, CaseIterable, Identifiable {
    case threeD
    case twoD

    var id: Self { self }

    var displayName: String {
        switch self {
        case .threeD: "3D"
        case .twoD: "2D"
        }
    }

    var systemImage: String {
        switch self {
        case .threeD: "cube"
        case .twoD: "square.grid.3x3"
        }
    }
}

/// Rotary control for board opacity. The value runs the full 0...1 range, and
/// the dial is driven by relative rotation so the pointer never jumps to the
/// finger or wraps through the gap at the bottom of the arc.
private struct BoardOpacityKnob: View {
    @Binding var value: Double

    var size: CGFloat = 104

    /// Degrees of travel, centered on 12 o'clock: -135° (off) to +135° (full).
    private let sweep: Double = 270
    private let trackWidth: CGFloat = 9

    @State private var lastAngle: Double?
    @State private var isDragging = false
    @State private var restoreValue: Double = 1

    var body: some View {
        ZStack {
            tickMarks

            Circle()
                .trim(from: 0, to: 0.75)
                .rotation(.degrees(135))
                .stroke(
                    Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                )
                .padding(trackWidth)

            Circle()
                .trim(from: 0, to: 0.75 * value)
                .rotation(.degrees(135))
                .stroke(
                    AngularGradient(
                        colors: [.indigo, .blue, .cyan, .mint],
                        center: .center,
                        startAngle: .degrees(135),
                        endAngle: .degrees(405)
                    ),
                    style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                )
                .padding(trackWidth)
                .shadow(color: .cyan.opacity(0.55 * value), radius: 7)

            knobBody

            pointer

            readout
        }
        .frame(width: size, height: size)
        .scaleEffect(isDragging ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isDragging)
        .contentShape(Circle())
        .gesture(rotation)
        .sensoryFeedback(.selection, trigger: Int((value * 20).rounded()))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Board opacity")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityHint("Adjust to fade the 3D board in and out.")
        .accessibilityAction(named: value > 0 ? "Hide board" : "Show board") {
            toggleOff()
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }

    private var knobBody: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.20, green: 0.22, blue: 0.28),
                        Color(red: 0.08, green: 0.09, blue: 0.12)
                    ],
                    center: .init(x: 0.35, y: 0.28),
                    startRadius: 1,
                    endRadius: size * 0.55
                )
            )
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            .padding(trackWidth * 2.5)
    }

    private var pointer: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(value > 0 ? Color.cyan : Color.white.opacity(0.45))
                .frame(width: 3, height: size * 0.13)
                .shadow(color: .cyan.opacity(value > 0 ? 0.9 : 0), radius: 4)
            Spacer(minLength: 0)
        }
        .padding(trackWidth * 3.1)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(pointerAngle))
    }

    private var readout: some View {
        VStack(spacing: 0) {
            if value < 0.005 {
                Text("OFF")
                    .font(.system(size: size * 0.17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("%")
                    .font(.system(size: size * 0.11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .fixedSize()
        .frame(width: size * 0.3, height: size * 0.3)
        .contentShape(Circle())
        // The hub is the dead zone of the rotation gesture, so a tap here is
        // unambiguous: it mutes the board and restores the previous setting.
        .onTapGesture { toggleOff() }
    }

    private func toggleOff() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            if value > 0 {
                restoreValue = value
                value = 0
            } else {
                value = restoreValue > 0 ? restoreValue : 1
            }
        }
    }

    private var tickMarks: some View {
        ForEach(0..<19) { index in
            let fraction = Double(index) / 18
            Capsule()
                .fill(
                    fraction <= value + 0.0001
                        ? Color.cyan.opacity(0.9)
                        : Color.primary.opacity(0.22)
                )
                .frame(width: 1.6, height: index.isMultiple(of: 6) ? 7 : 4)
                .frame(width: size, height: size, alignment: .top)
                .rotationEffect(.degrees(-sweep / 2 + sweep * fraction))
        }
        .allowsHitTesting(false)
    }

    private var pointerAngle: Double {
        -sweep / 2 + sweep * value
    }

    private var rotation: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                isDragging = true

                let dx = drag.location.x - size / 2
                let dy = drag.location.y - size / 2
                // Ignore the dead zone at the hub, where angles are unstable.
                guard dx * dx + dy * dy > pow(size * 0.15, 2) else { return }

                // Degrees clockwise from 12 o'clock, in -180...180.
                let angle = atan2(dx, -dy) * 180 / .pi
                defer { lastAngle = angle }

                guard let previous = lastAngle else { return }
                var delta = angle - previous
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }

                let updated = value + delta / sweep
                value = (min(1, max(0, updated)) * 100).rounded() / 100
            }
            .onEnded { _ in
                lastAngle = nil
                isDragging = false
            }
    }
}

private struct ChessBoardView: View {
    @ObservedObject var game: ChessGame
    let threatDisplayMode: ThreatDisplayMode
    let piecePalette: PiecePalette
    var onTap: ((Square) -> Void)? = nil
    var selectedSquare: Square? = nil
    var legalTargets: Set<Square>? = nil

    var body: some View {
        let visibleCorridors = game.threatCorridors(for: threatDisplayMode)

        VStack(spacing: 0) {
            ForEach(Array((0..<8).reversed()), id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { file in
                        let square = Square(file: file, rank: rank)!
                        ChessSquareView(
                            square: square,
                            piece: game.piece(at: square),
                            isSelected: (selectedSquare ?? game.selectedSquare) == square,
                            isLegalTarget: (legalTargets ?? game.legalTargets).contains(square),
                            isLastMove: game.lastMove?.from == square || game.lastMove?.to == square,
                            isCheckedKing: game.isKingInCheck(at: square),
                            isCandidate: game.candidatePulseSquares.contains(square),
                            piecePalette: piecePalette,
                            threatCorridors: visibleCorridors.filter {
                                marksThreatenedPiece($0, at: square)
                            }
                        ) {
                            (onTap ?? { game.tap($0) })(square)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.black.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chess board")
    }

    /// Enemy-contact corridors have a concrete endpoint; the optional broad
    /// threat map does not. Both presentations mark a piece, never open path.
    private func marksThreatenedPiece(_ corridor: ThreatCorridor, at square: Square) -> Bool {
        guard game.piece(at: square)?.player == corridor.piece.player.opponent else {
            return false
        }

        return corridor.endpoint == square || (
            corridor.endpoint == nil && corridor.threatenedSquares.contains(square)
        )
    }
}

private struct ChessSquareView: View {
    let square: Square
    let piece: Piece?
    let isSelected: Bool
    let isLegalTarget: Bool
    let isLastMove: Bool
    let isCheckedKing: Bool
    let isCandidate: Bool
    let piecePalette: PiecePalette
    let threatCorridors: [ThreatCorridor]
    let action: () -> Void

    private var isDark: Bool {
        (square.file + square.rank).isMultiple(of: 2)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                squareColor

                if !threatCorridors.isEmpty {
                    ThreatCorridorOverlay(corridors: threatCorridors)
                }

                if isLastMove {
                    Color.yellow.opacity(0.28)
                }

                if isCheckedKing {
                    Color.red.opacity(0.55)
                }

                if isSelected {
                    Rectangle()
                        .strokeBorder(Color.yellow, lineWidth: 4)
                }

                if isCandidate {
                    CandidatePulse2D()
                }

                if let piece {
                    if piece.kind == .pawn {
                        FlatPawnView(piece: piece, palette: piecePalette)
                            .padding(5)
                    } else {
                        Text(piece.symbol)
                            .font(.system(size: 54, weight: .regular, design: .serif))
                            .minimumScaleFactor(0.4)
                            .foregroundStyle(Color(uiColor: piecePalette.colors(for: piece.player).piece))
                            .shadow(color: pieceShadowColor(for: piece.player), radius: 1, y: 1)
                            .padding(4)
                    }
                }

                if isLegalTarget {
                    if piece == nil {
                        Circle()
                            .fill(Color.blue.opacity(0.72))
                            .frame(width: 18, height: 18)
                    } else {
                        Circle()
                            .stroke(Color.red.opacity(0.82), lineWidth: 5)
                            .padding(5)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHint)
    }

    private var squareColor: Color {
        isDark
            ? Color(red: 0.24, green: 0.34, blue: 0.30)
            : Color(red: 0.84, green: 0.79, blue: 0.67)
    }

    private func pieceShadowColor(for player: Player) -> Color {
        player == .white ? .black.opacity(0.68) : .white.opacity(0.42)
    }

    private var accessibilityText: String {
        let contents: String
        if let piece {
            contents = "\(square.algebraic), \(piece.player.displayName) \(piece.kind.rawValue)"
        } else {
            contents = "\(square.algebraic), empty"
        }
        let candidateDescription = isCandidate ? ", candidate" : ""
        guard !threatCorridors.isEmpty else { return contents + candidateDescription }
        let suffix = threatCorridors.count == 1 ? "piece" : "pieces"
        return "\(contents)\(candidateDescription), threatened by \(threatCorridors.count) \(suffix)"
    }

    private var accessibilityHint: String {
        return isLegalTarget ? "Moves the selected piece here" : "Selects this square"
    }
}

/// A deliberately simple pawn that shares the 3D renderer's round head,
/// tapered body, and contrasting collar instead of falling back to a font glyph.
private struct FlatPawnView: View {
    let piece: Piece
    let palette: PiecePalette

    private var colors: (piece: UIColor, accent: UIColor) {
        palette.colors(for: piece.player)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Capsule()
                    .fill(Color(uiColor: colors.piece))
                    .frame(width: size * 0.66, height: size * 0.17)
                    .offset(y: size * 0.29)

                PawnTaper()
                    .fill(Color(uiColor: colors.piece))
                    .frame(width: size * 0.42, height: size * 0.44)
                    .offset(y: size * 0.07)

                Capsule()
                    .fill(Color(uiColor: colors.accent))
                    .frame(width: size * 0.47, height: size * 0.09)
                    .offset(y: size * 0.23)

                Circle()
                    .fill(Color(uiColor: colors.piece))
                    .frame(width: size * 0.31, height: size * 0.31)
                    .offset(y: -size * 0.25)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .shadow(
                color: piece.player == .white ? .black.opacity(0.62) : .white.opacity(0.4),
                radius: 1,
                y: 1
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct PawnTaper: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PromotionPicker: View {
    let player: Player
    let choose: (PieceKind) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("PROMOTION")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text("Who does this pawn become?")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))

                HStack(spacing: 12) {
                    ForEach(PendingPromotion.choices, id: \.self) { kind in
                        Button {
                            choose(kind)
                        } label: {
                            VStack(spacing: 8) {
                                Text(Piece(kind: kind, player: player).symbol)
                                    .font(.system(size: 48, weight: .regular, design: .serif))
                                Text(kind.rawValue.capitalized)
                                    .font(.caption.weight(.bold))
                            }
                            .frame(width: 88, height: 106)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(player == .white ? .cyan : .purple)
                        .accessibilityLabel("Promote to \(kind.rawValue.capitalized)")
                    }
                }
            }
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
            .padding(24)
        }
    }
}

private struct FENTransferSheet: View {
    let currentFEN: String
    var errorMessage: String?
    let onLoad: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Current position") {
                    Text(currentFEN)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = currentFEN
                        copied = true
                    } label: {
                        Label(copied ? "FEN copied" : "Copy FEN", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }

                Section("Load a FEN") {
                    TextEditor(text: $input)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Button("Paste") {
                            input = UIPasteboard.general.string ?? ""
                        }
                        Spacer()
                        Button("Load position") {
                            onLoad(input)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Loading a FEN starts a fresh local game. It preserves the side to move, castling rights, clocks, and en-passant target.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Position code")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            input = currentFEN
        }
    }
}

private struct WindowAspectKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

private enum AbandonPrompt {
    case abandon
}

private struct PendingForkCommit {
    let move: ChessMove
    let suffix: [ChessMove]
    let forkPlyIndex: Int?
}

private struct CandidatePulse2D: View {
    var body: some View {
        PhaseAnimator([false, true]) { expanded in
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.78))
                Circle()
                    .stroke(Color.yellow.opacity(0.95), lineWidth: 3)
            }
            .scaleEffect(expanded ? 0.98 : 0.58)
            .opacity(expanded ? 0.42 : 0.94)
            .padding(4)
        } animation: { _ in
            .easeInOut(duration: 0.82)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Placeholder presentation for semantic corridor data. This is intentionally
/// isolated so a future skin can replace it without changing chess behavior.
private struct ThreatCorridorOverlay: View {
    let corridors: [ThreatCorridor]

    var body: some View {
        let whiteCount = corridors.filter { $0.piece.player == .white }.count
        let blackCount = corridors.count - whiteCount

        GeometryReader { geometry in
            let lineWidth = borderWidth(
                threatCount: corridors.count,
                squareSize: min(geometry.size.width, geometry.size.height)
            )

            if whiteCount > 0 && blackCount > 0 {
                ThreatStripeBorder(lineWidth: lineWidth)
            } else {
                Rectangle()
                    .strokeBorder(
                        whiteCount > 0 ? Color.cyan : Color.purple,
                        lineWidth: lineWidth
                    )
            }
        }
        .opacity(0.86)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func borderWidth(threatCount: Int, squareSize: CGFloat) -> CGFloat {
        switch threatCount {
        case 1:
            max(4, squareSize * 0.07)
        case 2:
            squareSize * 0.22
        case 3:
            squareSize * 0.42
        default:
            squareSize * 0.49
        }
    }
}

private struct ThreatStripeBorder: View {
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            var border = Path()
            border.addRect(CGRect(origin: .zero, size: size))

            let innerRect = CGRect(origin: .zero, size: size)
                .insetBy(dx: lineWidth, dy: lineWidth)
            if innerRect.width > 0, innerRect.height > 0 {
                border.addRect(innerRect)
            }
            context.clip(to: border, style: FillStyle(eoFill: true))

            let stripeWidth = max(6, min(size.width, size.height) * 0.12)
            var stripeIndex = 0
            var startX = -size.height

            while startX < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: startX, y: 0))
                stripe.addLine(to: CGPoint(x: startX + stripeWidth, y: 0))
                stripe.addLine(to: CGPoint(x: startX + size.height + stripeWidth, y: size.height))
                stripe.addLine(to: CGPoint(x: startX + size.height, y: size.height))
                stripe.closeSubpath()

                context.fill(
                    stripe,
                    with: .color(stripeIndex.isMultiple(of: 2) ? .cyan : .purple)
                )

                stripeIndex += 1
                startX += stripeWidth
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
