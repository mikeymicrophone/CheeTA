import SwiftUI

struct ContentView: View {
    @StateObject private var game = ChessGame()
    @State private var threatDisplayMode: ThreatDisplayMode = .enemyContact
    @State private var boardDimension: BoardDimension = .threeD

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height

            Group {
                if isWide {
                    HStack(spacing: 28) {
                        board
                        gamePanel
                            .frame(width: min(310, geometry.size.width * 0.3))
                    }
                } else {
                    VStack(spacing: 22) {
                        board
                        gamePanel
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }

    private var board: some View {
        Group {
            switch boardDimension {
            case .threeD:
                RealityChessBoardView(game: game, threatDisplayMode: threatDisplayMode)
            case .twoD:
                ChessBoardView(game: game, threatDisplayMode: threatDisplayMode)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 720, maxHeight: 720)
        .shadow(color: .black.opacity(boardDimension == .threeD ? 0.42 : 0.2), radius: 18, y: 8)
    }

    private var gamePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CheeTA")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                Text("Local chess")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(game.currentPlayer == .white ? .white : .black)
                    .stroke(.secondary, lineWidth: 1)
                    .frame(width: 18, height: 18)
                Text(game.statusText)
                    .font(.title3.weight(.semibold))
            }

            if !game.status.isFinished {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Candidates", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                        candidateActions
                    }

                    Text(candidateGuidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
            }

            Picker("Board dimension", selection: $boardDimension) {
                ForEach(BoardDimension.allCases) { dimension in
                    Label(dimension.displayName, systemImage: dimension.systemImage)
                        .tag(dimension)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Switches between the 3D and classic board renderers")

            if boardDimension == .threeD {
                Label("Drag the board to orbit. Tap squares to play.", systemImage: "rotate.3d")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("Enemy Contact shows only directional corridors that end on an opposing piece. Border weight still shows stacking.")
                .foregroundStyle(.secondary)

            Picker("Threat display", selection: $threatDisplayMode) {
                ForEach(ThreatDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Switches between enemy-contact corridors and the complete threat map")

            VStack(alignment: .leading, spacing: 8) {
                Text("Jump to a position")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    ForEach(PositionPreset.allCases) { preset in
                        Button {
                            game.load(preset)
                        } label: {
                            Label(preset.displayName, systemImage: preset.systemImage)
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(game.positionPreset == preset ? .blue : .secondary)
                        .accessibilityHint("Loads a realistic \(preset.displayName.lowercased()) position")
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                game.reset()
            } label: {
                Label("Restart game", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Basic rules: no castling, en passant, or promotion yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: isCompactHeight ? nil : 620, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var isCompactHeight: Bool {
        UIScreen.main.bounds.height < 700
    }

    private var candidateGuidance: String {
        if game.isChoosingCandidates {
            if game.candidateSquares.isEmpty {
                return "Candidate picking is on. Tap the pieces you want to keep pulsing."
            }
            let noun = game.candidateSquares.count == 1 ? "piece" : "pieces"
            return "Choosing candidates: \(game.candidateSquares.count) \(noun) will pulse."
        }
        if game.candidateSquares.isEmpty {
            return "All \(game.candidatePulseSquares.count) \(game.currentPlayer.displayName.lowercased()) pieces with a legal move are pulsing."
        }
        let noun = game.candidateSquares.count == 1 ? "piece" : "pieces"
        return "\(game.candidateSquares.count) candidate \(noun) selected."
    }

    @ViewBuilder
    private var candidateActions: some View {
        if game.isChoosingCandidates {
            Button("Done") {
                game.finishChoosingCandidates()
            }
            .font(.subheadline.weight(.semibold))
        } else if game.candidateSquares.isEmpty {
            Button("Choose") {
                game.beginChoosingCandidates()
            }
            .font(.subheadline.weight(.semibold))
        } else {
            Button("Pulse all") {
                game.clearCandidates()
            }
            .font(.subheadline.weight(.semibold))
        }
    }

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

private struct ChessBoardView: View {
    @ObservedObject var game: ChessGame
    let threatDisplayMode: ThreatDisplayMode

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
                            threatCorridors: visibleCorridors.filter {
                                $0.threatenedSquares.contains(square)
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
}

private struct ChessSquareView: View {
    let square: Square
    let piece: Piece?
    let isSelected: Bool
    let isLegalTarget: Bool
    let isLastMove: Bool
    let isCheckedKing: Bool
    let isCandidate: Bool
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
                    Text(piece.symbol)
                        .font(.system(size: 54, weight: .regular, design: .serif))
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(piece.player == .white ? Color.white : Color.black)
                        .shadow(color: piece.player == .white ? .black.opacity(0.65) : .white.opacity(0.38), radius: 1, y: 1)
                        .padding(4)
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
