import SwiftUI

/// One cut scene that actually fired, kept so the game can play its own
/// highlights back afterwards.
struct CutSceneEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case firstBlood(Capture)
        case queenDown(Capture)
        case check(Player)
        case checkmate(winner: Player)
    }

    let id = UUID()
    let kind: Kind
    let moveNumber: Int
}

/// Plays the recorded cut scenes back as a montage. Every card is built from
/// three layers that drift at different rates — the parallax does the work
/// that a camera move would do in an engine.
struct CutSceneReelView: View {
    let events: [CutSceneEvent]
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var drift: CGFloat = -1

    private let secondsPerCard: Double = 2.4

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)
            let barHeight = geometry.size.height * 0.12
            let card = card(for: events[min(index, events.count - 1)])

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
                cardBody(card, shortSide: shortSide)
                    .parallax(depth: 1, drift: drift)

                ticker(shortSide: shortSide, barHeight: barHeight)
            }
            .id(events[min(index, events.count - 1)].id)
            .transition(.opacity)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
        .task(id: index) {
            startDrift()
            try? await Task.sleep(for: .seconds(secondsPerCard))
            guard !Task.isCancelled else { return }
            advance()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Tap for the next cut scene")
        .accessibilityAddTraits(.isModal)
    }

    private var accessibilityText: String {
        let card = card(for: events[min(index, events.count - 1)])
        return "Cut scene \(index + 1) of \(events.count). \(card.headline), \(card.accent)."
    }

    /// Restarts the sweep for each card, so every one gets a fresh push.
    private func startDrift() {
        drift = -1
        guard !reduceMotion else { return }

        withAnimation(.linear(duration: secondsPerCard + 0.6)) {
            drift = 1
        }
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
    private func ticker(shortSide: CGFloat, barHeight: CGFloat) -> some View {
        VStack {
            HStack(spacing: 10) {
                Text("CUT SCENE REEL")
                    .font(.system(size: max(10, shortSide * 0.019), weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(2)

                Text("\(index + 1)/\(events.count)")
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

    private func cardBody(_ card: ReelCard, shortSide: CGFloat) -> some View {
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
    }

    private func card(for event: CutSceneEvent) -> ReelCard {
        switch event.kind {
        case .firstBlood(let capture):
            return ReelCard(
                eyebrow: "FIRST BLOOD ON THE BOARD",
                headline: "\(capture.piece.player.displayName) \(capture.piece.kind.rawValue)".uppercased(),
                accent: "OFF THE BOARD",
                accentColor: Color(red: 0.82, green: 0.16, blue: 0.10),
                footer: "MOVE \(event.moveNumber)   ·   \(capture.square.algebraic.uppercased())   ·   TAKEN BY \(captorName(capture))",
                glyph: capture.piece.symbol,
                symbol: nil,
                wash: Color(red: 0.62, green: 0.07, blue: 0.05),
                washCenter: .bottom
            )

        case .queenDown(let capture):
            return ReelCard(
                eyebrow: "THE CROWN FALLS",
                headline: "\(capture.piece.player.displayName) QUEEN".uppercased(),
                accent: "DETHRONED",
                accentColor: Color(red: 0.99, green: 0.87, blue: 0.52),
                footer: "MOVE \(event.moveNumber)   ·   \(capture.square.algebraic.uppercased())   ·   TAKEN BY \(captorName(capture))",
                glyph: capture.piece.symbol,
                symbol: "crown.fill",
                wash: Color(red: 0.87, green: 0.72, blue: 0.35),
                washCenter: .top
            )

        case .check(let player):
            return ReelCard(
                eyebrow: "TACTICAL EMERGENCY",
                headline: "\(player.displayName) KING".uppercased(),
                accent: "IN CHECK",
                accentColor: Color(red: 1.0, green: 0.84, blue: 0.08),
                footer: "MOVE \(event.moveNumber)   ·   THE KING IS IN TROUBLE",
                glyph: player == .white ? "♔" : "♚",
                symbol: "exclamationmark.triangle.fill",
                wash: Color(red: 0.72, green: 0.42, blue: 0.02),
                washCenter: .center
            )

        case .checkmate(let winner):
            return ReelCard(
                eyebrow: "NO WAY OUT",
                headline: "\(winner.opponent.displayName) KING".uppercased(),
                accent: "CHECKMATE",
                accentColor: Color(red: 1.0, green: 0.25, blue: 0.08),
                footer: "MOVE \(event.moveNumber)   ·   \(winner.displayName.uppercased()) TAKES IT",
                glyph: winner.opponent == .white ? "♔" : "♚",
                symbol: "flag.checkered",
                wash: Color(red: 0.7, green: 0.1, blue: 0.04),
                washCenter: .center
            )
        }
    }

    private func captorName(_ capture: Capture) -> String {
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
