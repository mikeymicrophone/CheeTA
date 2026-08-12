import SwiftUI

/// Fires once per game, on the first capture. Borrows the console-crime-drama
/// grade — desaturated scrim, red bleed, grain, letterbox, condensed caps with
/// a chromatic fringe — without copying anyone's death card.
struct FirstCaptureCutSceneView: View {
    let capture: Capture
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    private let bleed = Color(red: 0.62, green: 0.07, blue: 0.05)
    private let rust = Color(red: 0.82, green: 0.16, blue: 0.10)

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)

            ZStack {
                CutSceneStyle.scrim
                    .opacity(0.9)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [bleed.opacity(0.55), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: shortSide * 1.05
                )
                .blendMode(.screen)

                CutSceneGhostGlyph(
                    symbol: capture.piece.symbol,
                    size: shortSide * 0.66,
                    rotation: reduceMotion || hasLanded ? 13 : -5
                )
                .offset(y: shortSide * 0.02)

                CutSceneGrain()
                    .opacity(0.5)
                    .blendMode(.overlay)

                card(shortSide: shortSide)

                CutSceneLetterbox(
                    height: geometry.size.height * 0.11,
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.42)) {
                hasLanded = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "First capture. \(victimName) taken on \(capture.square.algebraic) by \(captorName)."
        )
        .accessibilityHint("Tap anywhere to skip")
        .accessibilityAddTraits(.isModal)
    }

    private var victimName: String {
        "\(capture.piece.player.displayName) \(capture.piece.kind.rawValue)"
    }

    private var captorName: String {
        "\(capture.captor.player.displayName) \(capture.captor.kind.rawValue)"
    }

    private func card(shortSide: CGFloat) -> some View {
        VStack(spacing: shortSide * 0.012) {
            Text("FIRST BLOOD ON THE BOARD")
                .font(.system(size: max(11, shortSide * 0.023), weight: .bold))
                .fontWidth(.condensed)
                .tracking(shortSide * 0.011)
                .foregroundStyle(CutSceneStyle.bone.opacity(0.62))

            FringedText(
                text: victimName.uppercased(),
                size: max(30, shortSide * 0.092),
                color: CutSceneStyle.bone
            )

            FringedText(
                text: "OFF THE BOARD",
                size: max(20, shortSide * 0.058),
                color: rust
            )
            .padding(.top, -shortSide * 0.012)

            Rectangle()
                .fill(CutSceneStyle.bone.opacity(0.22))
                .frame(width: shortSide * 0.42, height: 1)
                .padding(.vertical, shortSide * 0.022)

            Text("\(capture.square.algebraic.uppercased())   ·   TAKEN BY \(captorName.uppercased())")
                .font(.system(size: max(11, shortSide * 0.024), weight: .semibold, design: .monospaced))
                .foregroundStyle(CutSceneStyle.bone.opacity(0.78))

            Text("TAP ANYWHERE TO SKIP")
                .font(.system(size: max(9, shortSide * 0.017), weight: .bold))
                .tracking(1.6)
                .foregroundStyle(CutSceneStyle.bone.opacity(0.34))
                .padding(.top, shortSide * 0.05)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .scaleEffect(reduceMotion || hasLanded ? 1 : 1.14)
        .blur(radius: reduceMotion || hasLanded ? 0 : 14)
        .opacity(hasLanded ? 1 : 0)
    }
}
