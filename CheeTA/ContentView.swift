import SwiftUI

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
    /// Every cut scene that fired this game, in order, for the reel.
    @State private var cutSceneLog: [CutSceneEvent] = []
    @State private var isReelPresented = false
    @StateObject private var replay = ReplayPlayer()

    var body: some View {
        VStack(spacing: 20) {
            board
                .overlay(alignment: .bottom) {
                    if let progress = replay.progress {
                        ReplayBadge(progress: progress) {
                            replay.stop(in: game)
                        }
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.24), value: replay.progress)
            controlBar
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
            if let promotion = game.pendingPromotion {
                PromotionPicker(player: promotion.pawn.player) { kind in
                    withAnimation(.snappy(duration: 0.18)) {
                        game.promote(to: kind)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(103)
            }
        }
        .overlay {
            if isReelPresented, !cutSceneLog.isEmpty {
                CutSceneReelView(events: cutSceneLog) {
                    withAnimation(.easeOut(duration: 0.26)) {
                        isReelPresented = false
                    }
                }
                .transition(.opacity)
                .zIndex(104)
            }
        }
        .sensoryFeedback(.warning, trigger: checkCutScene?.id)
        .sensoryFeedback(.impact(weight: .heavy), trigger: firstCaptureCutScene?.id)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: queenDownCutScene?.id)
        .onChange(of: game.captureCount) { _, newCount in
            guard newCount > 0, let capture = game.lastCapture else { return }

            // A queen outranks first blood, including when she *is* first blood.
            if capture.piece.kind == .queen {
                presentQueenDownCutScene(for: capture)
            } else if newCount == 1 {
                presentFirstCaptureCutScene(for: capture)
            }
        }
        .onChange(of: game.status) { _, newStatus in
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
        .onChange(of: game.plies.count) { _, newCount in
            // A restart or a preset load empties the history; the reel goes too.
            if newCount == 0 {
                cutSceneLog.removeAll()
            }
        }
    }

    private func startReplay(lastPlies: Int?) {
        let frames = game.replayFrames(lastPlies: lastPlies)
        replay.play(
            frames,
            title: lastPlies == nil ? "Replay" : "Last \(lastPlies!)",
            in: game
        )
    }

    private func record(_ kind: CutSceneEvent.Kind) {
        cutSceneLog.append(
            CutSceneEvent(kind: kind, moveNumber: max(1, (game.plies.count + 1) / 2))
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

    private func presentCheckCutScene(for checkedPlayer: Player) {
        guard firstCaptureCutScene == nil, queenDownCutScene == nil else { return }

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
                isLightLoose: isLightLoose
            )
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: 1100)
            .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
        case .twoD:
            ChessBoardView(
                game: game,
                threatDisplayMode: threatDisplayMode,
                piecePalette: piecePalette
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
                Section("Jump to a position") {
                    ForEach(PositionPreset.allCases) { preset in
                        Button {
                            game.load(preset)
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
                        game.reset()
                    } label: {
                        Label("Restart game", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                controlIcon("flag.checkered", tint: .blue)
            }
            .accessibilityLabel("Positions")

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
                            isSelected: game.selectedSquare == square,
                            isLegalTarget: game.legalTargets.contains(square),
                            isLastMove: game.lastMove?.from == square || game.lastMove?.to == square,
                            isCheckedKing: game.isKingInCheck(at: square),
                            isCandidate: game.candidatePulseSquares.contains(square),
                            piecePalette: piecePalette,
                            threatCorridors: visibleCorridors.filter {
                                marksThreatenedPiece($0, at: square)
                            }
                        ) {
                            game.tap(square)
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
