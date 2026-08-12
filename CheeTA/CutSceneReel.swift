import SwiftUI

/// One cut scene that actually fired, kept so the game can play its own
/// highlights back afterwards.
struct CutSceneEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case firstBlood(Capture)
        case queenDown(Capture)
        case enPassantAvailable(EnPassantOpportunity)
        case enPassantTaken(EnPassantCapture)
        case check(Player)
        case checkmate(winner: Player)
    }

    let id = UUID()
    let kind: Kind
    let moveNumber: Int
    /// Which ply triggered it, so a replay can drop the card back into the
    /// exact spot it happened. Negative when nothing had been played yet.
    let plyIndex: Int
}

extension CutSceneEvent {
    /// Rebuilds the scenes a game *would* have fired, from its history alone.
    /// A game loaded from the browser was never played live, so its reel has
    /// to be derived rather than recorded.
    ///
    /// En passant is not derived: the engine reports those moments live, and
    /// inventing them from a ply list would risk claiming the wrong one.
    static func derived(from plies: [RecordedPly]) -> [CutSceneEvent] {
        var events: [CutSceneEvent] = []
        var hasDrawnBlood = false

        for (index, ply) in plies.enumerated() {
            let moveNumber = max(1, (index + 2) / 2)

            if let capture = ply.capture {
                if capture.piece.kind == .queen {
                    events.append(
                        CutSceneEvent(kind: .queenDown(capture), moveNumber: moveNumber, plyIndex: index)
                    )
                } else if !hasDrawnBlood {
                    events.append(
                        CutSceneEvent(kind: .firstBlood(capture), moveNumber: moveNumber, plyIndex: index)
                    )
                }
                hasDrawnBlood = true
            }

            switch ply.statusAfter {
            case .check(let player):
                events.append(
                    CutSceneEvent(kind: .check(player), moveNumber: moveNumber, plyIndex: index)
                )
            case .checkmate(let winner):
                events.append(
                    CutSceneEvent(kind: .checkmate(winner: winner), moveNumber: moveNumber, plyIndex: index)
                )
            case .playing, .stalemate:
                break
            }
        }

        return events
    }
}

/// A single cut scene card. Three layers drift at different rates — the
/// parallax does the work a camera move would do in an engine. Used both by
/// the reel and inline in a move replay.
struct CutSceneCardView: View {
    let event: CutSceneEvent
    var secondsOnScreen: Double = 2.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)
            let card = ReelCard(event: event)

            ZStack {
                Color.black.ignoresSafeArea()

                // Far: the wash. Barely moves, like a painted backdrop.
                RadialGradient(
                    colors: [card.wash.opacity(0.5), .clear],
                    center: card.washCenter,
                    startRadius: 0,
                    endRadius: shortSide * 1.15
                )
                .blendMode(.screen)
                .parallax(depth: 0.18, drift: drift)

                // Mid: the piece, big and slow.
                CutSceneGhostGlyph(
                    symbol: card.glyph,
                    size: shortSide * 0.78,
                    opacity: 0.2,
                    rotation: 9
                )
                .parallax(depth: 0.62, drift: drift)

                CutSceneGrain()
                    .opacity(0.45)
                    .blendMode(.overlay)

                // Near: the type, moving most.
                body(of: card, shortSide: shortSide)
                    .parallax(depth: 1, drift: drift)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay {
                CutSceneLetterbox(
                    height: geometry.size.height * 0.12,
                    isClosed: true
                )
            }
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear(perform: startDrift)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            let card = ReelCard(event: event)
            return "\(card.headline), \(card.accent)."
        }())
    }

    /// Each card gets its own sweep, so none of them inherit a stale offset.
    private func startDrift() {
        drift = -1
        guard !reduceMotion else { return }

        withAnimation(.linear(duration: secondsOnScreen + 0.6)) {
            drift = 1
        }
    }

    private func body(of card: ReelCard, shortSide: CGFloat) -> some View {
        VStack(spacing: shortSide * 0.012) {
            if let symbol = card.symbol {
                Image(systemName: symbol)
                    .font(.system(size: max(22, shortSide * 0.07)))
                    .foregroundStyle(card.accentColor)
                    .shadow(color: card.accentColor.opacity(0.5), radius: shortSide * 0.025)
                    .padding(.bottom, shortSide * 0.016)
            }

            Text(card.eyebrow)
                .font(.system(size: max(11, shortSide * 0.022), weight: .bold))
                .fontWidth(.condensed)
                .tracking(shortSide * 0.011)
                .foregroundStyle(card.accentColor.opacity(0.8))

            FringedText(
                text: card.headline,
                size: max(28, shortSide * 0.088),
                color: CutSceneStyle.bone
            )

            FringedText(
                text: card.accent,
                size: max(20, shortSide * 0.058),
                color: card.accentColor
            )
            .padding(.top, -shortSide * 0.012)

            LinearGradient(
                colors: [.clear, card.accentColor.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: shortSide * 0.46, height: 1)
            .padding(.vertical, shortSide * 0.022)

            Text(card.footer)
                .font(.system(size: max(10, shortSide * 0.021), weight: .semibold, design: .monospaced))
                .foregroundStyle(CutSceneStyle.bone.opacity(0.74))
                .multilineTextAlignment(.center)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}

/// Plays the recorded cut scenes back as a montage, with nothing else between
/// them. The move replay shows the same cards in their original places.
struct CutSceneReelView: View {
    let events: [CutSceneEvent]
    let dismiss: () -> Void

    @State private var index = 0

    private let secondsPerCard: Double = 2.4

    var body: some View {
        let safeIndex = min(index, max(0, events.count - 1))

        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)

            ZStack {
                if events.indices.contains(safeIndex) {
                    CutSceneCardView(
                        event: events[safeIndex],
                        secondsOnScreen: secondsPerCard
                    )
                    .id(events[safeIndex].id)
                    .transition(.opacity)
                }

                ticker(
                    shortSide: shortSide,
                    barHeight: geometry.size.height * 0.12,
                    position: safeIndex
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
        .task(id: index) {
            try? await Task.sleep(for: .seconds(secondsPerCard))
            guard !Task.isCancelled else { return }
            advance()
        }
        .accessibilityHint("Tap for the next cut scene")
        .accessibilityAddTraits(.isModal)
    }

    private func advance() {
        guard index + 1 < events.count else {
            dismiss()
            return
        }

        withAnimation(.easeInOut(duration: 0.28)) {
            index += 1
        }
    }

    /// Sits just under the top letterbox bar rather than behind it.
    private func ticker(shortSide: CGFloat, barHeight: CGFloat, position: Int) -> some View {
        VStack {
            HStack(spacing: 10) {
                Text("CUT SCENE REEL")
                    .font(.system(size: max(10, shortSide * 0.019), weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(2)

                Text("\(position + 1)/\(events.count)")
                    .font(.system(size: max(10, shortSide * 0.019), weight: .semibold, design: .monospaced))
                    .foregroundStyle(CutSceneStyle.bone.opacity(0.6))

                Spacer()

                Text("TAP TO ADVANCE")
                    .font(.system(size: max(9, shortSide * 0.016), weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(CutSceneStyle.bone.opacity(0.34))
            }
            .foregroundStyle(CutSceneStyle.bone.opacity(0.8))
            .padding(.horizontal, shortSide * 0.06)
            .padding(.top, barHeight + shortSide * 0.03)

            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// The look of one card, derived from the event it describes.
private struct ReelCard {
    let eyebrow: String
    let headline: String
    let accent: String
    let accentColor: Color
    let footer: String
    let glyph: String
    let symbol: String?
    let wash: Color
    let washCenter: UnitPoint

    init(event: CutSceneEvent) {
        switch event.kind {
        case .firstBlood(let capture):
            eyebrow = "FIRST BLOOD ON THE BOARD"
            headline = "\(capture.piece.player.displayName) \(capture.piece.kind.rawValue)".uppercased()
            accent = "OFF THE BOARD"
            accentColor = Color(red: 0.82, green: 0.16, blue: 0.10)
            footer = "MOVE \(event.moveNumber)   ·   \(capture.square.algebraic.uppercased())   ·   TAKEN BY \(Self.captorName(capture))"
            glyph = capture.piece.symbol
            symbol = nil
            wash = Color(red: 0.62, green: 0.07, blue: 0.05)
            washCenter = .bottom

        case .queenDown(let capture):
            eyebrow = "THE CROWN FALLS"
            headline = "\(capture.piece.player.displayName) QUEEN".uppercased()
            accent = "DETHRONED"
            accentColor = Color(red: 0.99, green: 0.87, blue: 0.52)
            footer = "MOVE \(event.moveNumber)   ·   \(capture.square.algebraic.uppercased())   ·   TAKEN BY \(Self.captorName(capture))"
            glyph = capture.piece.symbol
            symbol = "crown.fill"
            wash = Color(red: 0.87, green: 0.72, blue: 0.35)
            washCenter = .top

        case .enPassantAvailable(let opportunity):
            eyebrow = "RULE WINDOW OPEN"
            headline = "EN PASSANT"
            accent = "NOW OR NEVER"
            accentColor = Color(red: 0.10, green: 0.86, blue: 0.96)
            footer = "MOVE \(event.moveNumber)   ·   TAKE \(opportunity.target.algebraic.uppercased())   ·   ONLY THIS TURN"
            glyph = "⇄"
            symbol = "arrow.left.arrow.right"
            wash = Color(red: 0.05, green: 0.56, blue: 0.72)
            washCenter = .bottom

        case .enPassantTaken(let capture):
            eyebrow = "THE WINDOW CLOSED"
            headline = "EN PASSANT"
            accent = "TAKEN"
            accentColor = Color(red: 0.62, green: 1.0, blue: 0.24)
            footer = "MOVE \(event.moveNumber)   ·   \(capture.from.algebraic.uppercased()) → \(capture.landing.algebraic.uppercased())   ·   PAWN LIFTED FROM \(capture.capturedPawn.algebraic.uppercased())"
            glyph = capture.captor.symbol
            symbol = "arrow.turn.down.right"
            wash = Color(red: 0.33, green: 0.72, blue: 0.10)
            washCenter = .bottom

        case .check(let player):
            eyebrow = "TACTICAL EMERGENCY"
            headline = "\(player.displayName) KING".uppercased()
            accent = "IN CHECK"
            accentColor = Color(red: 1.0, green: 0.84, blue: 0.08)
            footer = "MOVE \(event.moveNumber)   ·   THE KING IS IN TROUBLE"
            glyph = player == .white ? "♔" : "♚"
            symbol = "exclamationmark.triangle.fill"
            wash = Color(red: 0.72, green: 0.42, blue: 0.02)
            washCenter = .center

        case .checkmate(let winner):
            eyebrow = "NO WAY OUT"
            headline = "\(winner.opponent.displayName) KING".uppercased()
            accent = "CHECKMATE"
            accentColor = Color(red: 1.0, green: 0.25, blue: 0.08)
            footer = "MOVE \(event.moveNumber)   ·   \(winner.displayName.uppercased()) TAKES IT"
            glyph = winner.opponent == .white ? "♔" : "♚"
            symbol = "flag.checkered"
            wash = Color(red: 0.7, green: 0.1, blue: 0.04)
            washCenter = .center
        }
    }

    private static func captorName(_ capture: Capture) -> String {
        "\(capture.captor.player.displayName) \(capture.captor.kind.rawValue)".uppercased()
    }
}

private extension View {
    /// Layers drift by depth across the card's life. Near layers travel
    /// farthest, which is what sells the depth.
    func parallax(depth: CGFloat, drift: CGFloat) -> some View {
        offset(x: drift * 34 * depth, y: drift * -9 * depth)
            .scaleEffect(1 + 0.05 * depth)
    }
}
