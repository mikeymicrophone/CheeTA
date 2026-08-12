import SwiftUI

/// The first intentionally lo-fi cut scene. Keeping it separate from the board
/// and chess engine lets future event scenes use entirely different skins.
struct CheckCutSceneView: View {
    let checkedPlayer: Player
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private let warningYellow = Color(red: 1.0, green: 0.84, blue: 0.08)
    private let warningOrange = Color(red: 1.0, green: 0.25, blue: 0.08)

    var body: some View {
        GeometryReader { geometry in
            let shortSide = min(geometry.size.width, geometry.size.height)

            ZStack {
                Color.black.opacity(0.96)

                cutoutDots
                    .opacity(0.26)

                warningBurst(size: shortSide)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 360 : 0)))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 3.2).repeatForever(autoreverses: false),
                        value: isAnimating
                    )

                Circle()
                    .fill(.black)
                    .frame(width: shortSide * 0.72, height: shortSide * 0.72)
                    .overlay {
                        Circle()
                            .stroke(warningYellow, lineWidth: max(6, shortSide * 0.015))
                    }

                VStack(spacing: shortSide * 0.018) {
                    Text("TACTICAL EMERGENCY")
                        .font(.system(size: max(16, shortSide * 0.035), weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(warningYellow)

                    Text(checkedPlayer == .white ? "♔" : "♚")
                        .font(.system(size: shortSide * 0.2, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: warningOrange, radius: 0, x: 7, y: 7)

                    Text("CHECK!")
                        .font(.system(size: shortSide * 0.13, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(warningYellow)
                        .shadow(color: warningOrange, radius: 0, x: 8, y: 8)
                        .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.08 : 0.9))
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.28).repeatForever(autoreverses: true),
                            value: isAnimating
                        )

                    Text("\(checkedPlayer.displayName.uppercased()) KING IS IN TROUBLE")
                        .font(.system(size: max(14, shortSide * 0.028), weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 6)

                    Text("TAP ANYWHERE TO SKIP")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.top, 10)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .onAppear { isAnimating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Check. \(checkedPlayer.displayName) king is in trouble.")
        .accessibilityHint("Tap anywhere to skip")
        .accessibilityAddTraits(.isModal)
    }

    private func warningBurst(size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index.isMultiple(of: 2) ? warningYellow : warningOrange)
                    .frame(width: max(12, size * 0.035), height: size * 0.74)
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(index) * 18))
            }
        }
        .frame(width: size, height: size)
    }

    private var cutoutDots: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            var row: CGFloat = 0

            while row < size.height {
                var column: CGFloat = 0
                while column < size.width {
                    let dot = CGRect(x: column, y: row, width: 4, height: 4)
                    context.fill(Path(ellipseIn: dot), with: .color(.white))
                    column += spacing
                }
                row += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
