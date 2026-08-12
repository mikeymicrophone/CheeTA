import SwiftUI

/// The big one. Same film stock as the first-capture scene, escalated: gold
/// instead of rust, a spotlight from above instead of a bleed from below, a
/// crown that topples, and a slow push in. Fires whenever a queen is taken.
struct QueenDownCutSceneView: View {
    let capture: Capture
    let moveNumber: Int
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false
    @State private var isPushingIn = false

    private let gold = Color(red: 0.87, green: 0.72, blue: 0.35)
    private let brightGold = Color(red: 0.99, green: 0.87, blue: 0.52)

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)

            ZStack {
                CutSceneStyle.scrim
                    .opacity(0.93)
                    .ignoresSafeArea()

                spotlight(size: shortSide)

                CutSceneGhostGlyph(
                    symbol: capture.piece.symbol,
                    size: shortSide * 0.72,
                    opacity: 0.16,
                    rotation: reduceMotion || hasLanded ? 9 : -4
                )
                .offset(y: shortSide * 0.04)

                CutSceneGrain()
                    .opacity(0.5)
                    .blendMode(.overlay)

                card(shortSide: shortSide)
            }
            // A slow push in: the scene keeps creeping the whole time it holds.
            .scaleEffect(reduceMotion ? 1 : (isPushingIn ? 1.05 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 3.4),
                value: isPushingIn
            )
            .overlay {
                CutSceneLetterbox(
                    height: geometry.size.height * 0.13,
                    isClosed: hasLanded
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                hasLanded = true
            }
            isPushingIn = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "The \(victimName) is down, taken on \(capture.square.algebraic) by \(captorName) at move \(moveNumber)."
        )
        .accessibilityHint("Tap anywhere to skip")
        .accessibilityAddTraits(.isModal)
    }

    private var victimName: String {
        "\(capture.piece.player.displayName) queen"
    }

    private var captorName: String {
        "\(capture.captor.player.displayName) \(capture.captor.kind.rawValue)"
    }

    private func card(shortSide: CGFloat) -> some View {
        VStack(spacing: shortSide * 0.012) {
            crown(size: shortSide)
                .padding(.bottom, shortSide * 0.02)

            Text("THE CROWN FALLS")
                .font(.system(size: max(11, shortSide * 0.023), weight: .bold))
                .fontWidth(.condensed)
                .tracking(shortSide * 0.012)
                .foregroundStyle(gold.opacity(0.78))

            FringedText(
                text: victimName.uppercased(),
                size: max(30, shortSide * 0.095),
                color: CutSceneStyle.bone
            )

            FringedText(
                text: "DETHRONED",
                size: max(22, shortSide * 0.066),
                color: brightGold
            )
            .padding(.top, -shortSide * 0.014)

            LinearGradient(
                colors: [.clear, gold.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: shortSide * 0.5, height: 1)
            .padding(.vertical, shortSide * 0.024)

            Text("MOVE \(moveNumber)   ·   \(capture.square.algebraic.uppercased())   ·   TAKEN BY \(captorName.uppercased())")
                .font(.system(size: max(10, shortSide * 0.022), weight: .semibold, design: .monospaced))
                .foregroundStyle(CutSceneStyle.bone.opacity(0.76))
                .multilineTextAlignment(.center)

            Text("TAP ANYWHERE TO SKIP")
                .font(.system(size: max(9, shortSide * 0.017), weight: .bold))
                .tracking(1.6)
                .foregroundStyle(CutSceneStyle.bone.opacity(0.32))
                .padding(.top, shortSide * 0.045)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .scaleEffect(reduceMotion || hasLanded ? 1 : 1.16)
        .blur(radius: reduceMotion || hasLanded ? 0 : 16)
        .opacity(hasLanded ? 1 : 0)
    }

    /// It lands crooked, the way a dropped crown would.
    private func crown(size: CGFloat) -> some View {
        Image(systemName: "crown.fill")
            .font(.system(size: max(26, size * 0.085)))
            .foregroundStyle(
                LinearGradient(
                    colors: [brightGold, gold],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: gold.opacity(0.5), radius: size * 0.03)
            .rotationEffect(.degrees(reduceMotion || hasLanded ? -11 : 26))
            .offset(y: reduceMotion || hasLanded ? 0 : -size * 0.06)
    }

    private func spotlight(size: CGFloat) -> some View {
        RadialGradient(
            colors: [gold.opacity(0.4), .clear],
            center: .top,
            startRadius: 0,
            endRadius: size * 1.15
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}
