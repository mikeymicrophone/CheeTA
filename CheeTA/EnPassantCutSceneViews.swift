import SwiftUI

/// Two intentionally over-serious interstitials for chess's strangest pawn
/// rule: one announces the narrow opening; the other celebrates taking it.
struct EnPassantOpportunityCutSceneView: View {
    let opportunity: EnPassantOpportunity
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLive = false

    private let cyan = Color(red: 0.10, green: 0.86, blue: 0.96)
    private let magenta = Color(red: 0.95, green: 0.20, blue: 0.78)

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)

            ZStack {
                CutSceneStyle.scrim.opacity(0.94).ignoresSafeArea()
                scanlines.opacity(0.34).blendMode(.screen)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: shortSide * 0.48, weight: .black))
                    .foregroundStyle(cyan.opacity(0.2))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isLive ? 8 : -8)))
                    .scaleEffect(reduceMotion ? 1 : (isLive ? 1.08 : 0.86))

                VStack(spacing: shortSide * 0.014) {
                    Text("RULE WINDOW OPEN")
                        .font(.system(size: max(11, shortSide * 0.023), weight: .bold))
                        .fontWidth(.condensed)
                        .tracking(shortSide * 0.012)
                        .foregroundStyle(cyan.opacity(0.8))

                    FringedText(
                        text: "EN PASSANT",
                        size: max(30, shortSide * 0.09),
                        color: CutSceneStyle.bone
                    )

                    FringedText(
                        text: "NOW OR NEVER",
                        size: max(20, shortSide * 0.06),
                        color: magenta
                    )
                    .padding(.top, -shortSide * 0.012)

                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, cyan, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: shortSide * 0.54, height: 1)
                        .padding(.vertical, shortSide * 0.022)

                    Text("TAKE (opportunity.target.algebraic.uppercased()) · ONLY THIS TURN")
                        .font(.system(size: max(11, shortSide * 0.024), weight: .semibold, design: .monospaced))
                        .foregroundStyle(CutSceneStyle.bone.opacity(0.78))

                    Text("TAP ANYWHERE TO SKIP")
                        .font(.system(size: max(9, shortSide * 0.017), weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(CutSceneStyle.bone.opacity(0.34))
                        .padding(.top, shortSide * 0.04)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .opacity(isLive ? 1 : 0)
                .scaleEffect(reduceMotion || isLive ? 1 : 1.12)
            }
            .overlay {
                CutSceneLetterbox(height: geometry.size.height * 0.11, isClosed: isLive)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.34)) {
                isLive = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("En passant is available. Capture on \(opportunity.target.algebraic) this turn.")
        .accessibilityHint("Tap anywhere to skip")
        .accessibilityAddTraits(.isModal)
    }

    private var scanlines: some View {
        Canvas { context, size in
            stride(from: 0, through: size.height, by: 8).forEach { y in
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct EnPassantCaptureCutSceneView: View {
    let capture: EnPassantCapture
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    private let lime = Color(red: 0.62, green: 1.0, blue: 0.24)
    private let orange = Color(red: 1.0, green: 0.34, blue: 0.08)

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)

            ZStack {
                CutSceneStyle.scrim.opacity(0.95).ignoresSafeArea()
                RadialGradient(
                    colors: [lime.opacity(0.42), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: shortSide * 1.05
                )
                .blendMode(.screen)

                CutSceneGhostGlyph(
                    symbol: capture.captor.symbol,
                    size: shortSide * 0.7,
                    opacity: 0.18,
                    rotation: reduceMotion || hasLanded ? -12 : 12
                )

                VStack(spacing: shortSide * 0.014) {
                    Text("THE WINDOW CLOSED")
                        .font(.system(size: max(11, shortSide * 0.023), weight: .bold))
                        .fontWidth(.condensed)
                        .tracking(shortSide * 0.012)
                        .foregroundStyle(lime.opacity(0.8))

                    FringedText(
                        text: "EN PASSANT",
                        size: max(30, shortSide * 0.092),
                        color: CutSceneStyle.bone
                    )

                    FringedText(
                        text: "TAKEN",
                        size: max(22, shortSide * 0.066),
                        color: orange
                    )
                    .padding(.top, -shortSide * 0.013)

                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, lime, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: shortSide * 0.5, height: 1)
                        .padding(.vertical, shortSide * 0.024)

                    Text("\(capture.from.algebraic.uppercased()) → \(capture.landing.algebraic.uppercased())  ·  PAWN LIFTED FROM \(capture.capturedPawn.algebraic.uppercased())")
                        .font(.system(size: max(10, shortSide * 0.021), weight: .semibold, design: .monospaced))
                        .foregroundStyle(CutSceneStyle.bone.opacity(0.78))
                        .multilineTextAlignment(.center)

                    Text("TAP ANYWHERE TO SKIP")
                        .font(.system(size: max(9, shortSide * 0.017), weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(CutSceneStyle.bone.opacity(0.34))
                        .padding(.top, shortSide * 0.04)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .opacity(hasLanded ? 1 : 0)
                .scaleEffect(reduceMotion || hasLanded ? 1 : 1.15)
                .blur(radius: reduceMotion || hasLanded ? 0 : 14)
            }
            .overlay {
                CutSceneLetterbox(height: geometry.size.height * 0.12, isClosed: hasLanded)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                hasLanded = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("En passant taken. Pawn moved from \(capture.from.algebraic) to \(capture.landing.algebraic), taking a pawn from \(capture.capturedPawn.algebraic).")
        .accessibilityHint("Tap anywhere to skip")
        .accessibilityAddTraits(.isModal)
    }
}
