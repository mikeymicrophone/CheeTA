import SwiftUI

/// Fires once per game, on the first capture. Borrows the console-crime-drama
/// grade — desaturated scrim, red bleed, grain, letterbox, condensed caps with
/// a chromatic fringe — without copying anyone's death card.
struct FirstCaptureCutSceneView: View {
    let capture: Capture
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    private let scrim = Color(red: 0.055, green: 0.06, blue: 0.055)
    private let bleed = Color(red: 0.62, green: 0.07, blue: 0.05)
    private let bone = Color(red: 0.90, green: 0.89, blue: 0.84)
    private let rust = Color(red: 0.82, green: 0.16, blue: 0.10)

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)
            let barHeight = geometry.size.height * 0.11

            ZStack {
                scrim
                    .opacity(0.9)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [bleed.opacity(0.55), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: shortSide * 1.05
                )
                .blendMode(.screen)

                ghostGlyph(size: shortSide)

                grain
                    .opacity(0.5)
                    .blendMode(.overlay)

                card(shortSide: shortSide)

                letterbox(height: barHeight)
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
                .foregroundStyle(bone.opacity(0.62))

            fringedText(
                victimName.uppercased(),
                size: max(30, shortSide * 0.092),
                color: bone
            )

            fringedText(
                "OFF THE BOARD",
                size: max(20, shortSide * 0.058),
                color: rust
            )
            .padding(.top, -shortSide * 0.012)

            Rectangle()
                .fill(bone.opacity(0.22))
                .frame(width: shortSide * 0.42, height: 1)
                .padding(.vertical, shortSide * 0.022)

            Text("\(capture.square.algebraic.uppercased())   ·   TAKEN BY \(captorName.uppercased())")
                .font(.system(size: max(11, shortSide * 0.024), weight: .semibold, design: .monospaced))
                .foregroundStyle(bone.opacity(0.78))

            Text("TAP ANYWHERE TO SKIP")
                .font(.system(size: max(9, shortSide * 0.017), weight: .bold))
                .tracking(1.6)
                .foregroundStyle(bone.opacity(0.34))
                .padding(.top, shortSide * 0.05)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .scaleEffect(reduceMotion || hasLanded ? 1 : 1.14)
        .blur(radius: reduceMotion || hasLanded ? 0 : 14)
        .opacity(hasLanded ? 1 : 0)
    }

    /// Three passes offset a hair apart: the cheap cousin of a lens fringe.
    private func fringedText(_ text: String, size: CGFloat, color: Color) -> some View {
        let offset = max(1, size * 0.018)

        return ZStack {
            Text(text)
                .foregroundStyle(Color(red: 0.95, green: 0.1, blue: 0.1))
                .offset(x: -offset)
                .blendMode(.screen)
            Text(text)
                .foregroundStyle(Color(red: 0.1, green: 0.85, blue: 0.95))
                .offset(x: offset)
                .blendMode(.screen)
            Text(text)
                .foregroundStyle(color)
        }
        .font(.system(size: size, weight: .black))
        .fontWidth(.condensed)
        .tracking(size * 0.02)
    }

    private func ghostGlyph(size: CGFloat) -> some View {
        // The piece glyphs render as color emoji, which ignore foregroundStyle
        // entirely — grade and fade them at the view level instead.
        Text(capture.piece.symbol)
            .font(.system(size: size * 0.66))
            .grayscale(1)
            .opacity(0.22)
            .rotationEffect(.degrees(reduceMotion || hasLanded ? 13 : -5))
            .offset(y: size * 0.02)
            .allowsHitTesting(false)
    }

    private func letterbox(height: CGFloat) -> some View {
        VStack {
            Rectangle()
                .fill(.black)
                .frame(height: hasLanded ? height : 0)
            Spacer(minLength: 0)
            Rectangle()
                .fill(.black)
                .frame(height: hasLanded ? height : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Seeded so the noise holds still between redraws instead of shimmering.
    private var grain: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15

            func next() -> Double {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }

            for _ in 0..<2600 {
                let speck = CGRect(
                    x: next() * size.width,
                    y: next() * size.height,
                    width: 1.5,
                    height: 1.5
                )
                context.fill(
                    Path(ellipseIn: speck),
                    with: .color(.white.opacity(0.06 + next() * 0.2))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
