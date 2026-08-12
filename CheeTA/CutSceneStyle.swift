import SwiftUI

/// The shared grade for capture cut scenes: grain, letterbox, condensed caps
/// with a lens fringe, and graded piece glyphs. Individual scenes still pick
/// their own palette, motion, and copy — this is only the film stock.
enum CutSceneStyle {
    static let bone = Color(red: 0.90, green: 0.89, blue: 0.84)
    static let scrim = Color(red: 0.055, green: 0.06, blue: 0.055)
}

/// Seeded so the noise holds still between redraws instead of shimmering.
struct CutSceneGrain: View {
    var speckCount = 2600

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15

            func next() -> Double {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }

            for _ in 0..<speckCount {
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

struct CutSceneLetterbox: View {
    let height: CGFloat
    let isClosed: Bool

    var body: some View {
        VStack {
            Rectangle()
                .fill(.black)
                .frame(height: isClosed ? height : 0)
            Spacer(minLength: 0)
            Rectangle()
                .fill(.black)
                .frame(height: isClosed ? height : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Three passes offset a hair apart: the cheap cousin of a lens fringe.
struct FringedText: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        let offset = max(1, size * 0.018)

        ZStack {
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
}

/// The piece glyphs render as color emoji, which ignore foregroundStyle
/// entirely — grade and fade them at the view level instead.
struct CutSceneGhostGlyph: View {
    let symbol: String
    let size: CGFloat
    var opacity: Double = 0.22
    var rotation: Double = 13

    var body: some View {
        Text(symbol)
            .font(.system(size: size))
            .grayscale(1)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .allowsHitTesting(false)
    }
}
