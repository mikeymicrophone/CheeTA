import RealityKit
import SwiftUI
import UIKit

/// A quiet place to read the board's sculpture before it becomes a tactical
/// unit. This intentionally reuses the live-piece factory: a gallery model
/// must never drift away from its in-game counterpart.
struct PieceGalleryView: View {
    let palette: PiecePalette

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: PieceKind = .pawn
    @State private var selectedPlayer: Player = .white

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Side", selection: $selectedPlayer) {
                    Text("White").tag(Player.white)
                    Text("Black").tag(Player.black)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.top, 14)

                PieceInspectionScene(
                    piece: Piece(kind: selectedKind, player: selectedPlayer),
                    palette: palette
                )
                .padding(.horizontal, 18)
                .padding(.top, 16)

                VStack(spacing: 4) {
                    Text(selectedKind.displayName.uppercased())
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .tracking(1.6)

                    Text(selectedKind.galleryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PieceKind.galleryOrder, id: \.self) { kind in
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    selectedKind = kind
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    Text(Piece(kind: kind, player: selectedPlayer).symbol)
                                        .font(.system(size: 27, design: .serif))
                                    Text(kind.shortName)
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(kind == selectedKind ? .white : palette.pieceColor(for: selectedPlayer))
                                .frame(width: 68, height: 62)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(kind == selectedKind
                                            ? AnyShapeStyle(palette.pieceColor(for: selectedPlayer).gradient)
                                            : AnyShapeStyle(.thinMaterial))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(kind.displayName)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
                .background(.ultraThinMaterial)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Piece Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .accessibilityLabel("Close-up chess piece gallery")
    }
}

/// A free-standing studio plinth. Drag to rotate the actual model; pinch to
/// inspect its finish and small silhouette details.
private struct PieceInspectionScene: View {
    let piece: Piece
    let palette: PiecePalette

    @State private var yaw: Float = -0.42
    @State private var pitch: Float = -0.13
    @State private var scale: Float = 1
    @State private var startYaw: Float = -0.42
    @State private var startPitch: Float = -0.13
    @State private var startScale: Float = 1
    @State private var isDragging = false
    @State private var isPinching = false

    private let rootName = "piece-inspection-root"

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = rootName
            content.add(root)

            let stage = ModelEntity(
                mesh: .generateCylinder(height: 0.16, radius: 1.05),
                materials: [SimpleMaterial(
                    color: UIColor(red: 0.07, green: 0.085, blue: 0.095, alpha: 1),
                    roughness: .float(0.32),
                    isMetallic: true
                )]
            )
            stage.position.y = -0.08
            root.addChild(stage)

            let rim = ModelEntity(
                mesh: .generateCylinder(height: 0.026, radius: 1.08),
                materials: [SimpleMaterial(
                    color: UIColor(palette.pieceColor(for: piece.player)).withAlphaComponent(0.72),
                    roughness: .float(0.2),
                    isMetallic: true
                )]
            )
            rim.position.y = 0.015
            root.addChild(rim)

            let model = RealityBoardScene.makePiece(piece, palette: palette)
            model.name = "inspection-piece"
            root.addChild(model)

            let keyLight = Entity()
            keyLight.position = [-2.2, 3.4, 2.8]
            keyLight.components.set(PointLightComponent(
                color: UIColor(red: 1.0, green: 0.91, blue: 0.76, alpha: 1),
                intensity: 26_000,
                attenuationRadius: 8
            ))
            content.add(keyLight)

            let fillLight = Entity()
            fillLight.position = [2.5, 1.8, 1.2]
            fillLight.components.set(PointLightComponent(
                color: UIColor(red: 0.46, green: 0.74, blue: 1.0, alpha: 1),
                intensity: 8_000,
                attenuationRadius: 7
            ))
            content.add(fillLight)

            let camera = PerspectiveCamera()
            camera.camera = PerspectiveCameraComponent(
                near: 0.05,
                far: 30,
                fieldOfViewInDegrees: 31
            )
            camera.look(at: [0, 0.54, 0], from: [0, 1.0, 4.05], relativeTo: nil)
            content.add(camera)
            content.camera = .virtual

            applyTransform(to: root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == rootName }) else { return }
            root.children.first(where: { $0.name == "inspection-piece" })?.removeFromParent()
            let model = RealityBoardScene.makePiece(piece, palette: palette)
            model.name = "inspection-piece"
            root.addChild(model)
            applyTransform(to: root)
        }
        .background(
            RadialGradient(
                colors: [palette.pieceColor(for: piece.player).opacity(0.36), Color.black.opacity(0.96)],
                center: .top,
                startRadius: 10,
                endRadius: 420
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .aspectRatio(1.35, contentMode: .fit)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        startYaw = yaw
                        startPitch = pitch
                    }
                    yaw = startYaw - Float(value.translation.width) * 0.012
                    pitch = min(max(startPitch + Float(value.translation.height) * 0.008, -0.55), 0.30)
                }
                .onEnded { value in
                    yaw = startYaw - Float(value.translation.width) * 0.012
                    pitch = min(max(startPitch + Float(value.translation.height) * 0.008, -0.55), 0.30)
                    isDragging = false
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if !isPinching {
                        isPinching = true
                        startScale = scale
                    }
                    scale = min(max(startScale * Float(value), 0.72), 1.65)
                }
                .onEnded { value in
                    scale = min(max(startScale * Float(value), 0.72), 1.65)
                    isPinching = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Close-up \(piece.player.displayName) \(piece.kind.displayName)")
        .accessibilityHint("Drag to rotate the piece. Pinch to zoom.")
    }

    private func applyTransform(to root: Entity) {
        let yawRotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let pitchRotation = simd_quatf(angle: pitch, axis: [1, 0, 0])
        root.orientation = yawRotation * pitchRotation
        root.scale = SIMD3<Float>(repeating: scale)
    }
}

private extension PieceKind {
    static let galleryOrder: [PieceKind] = [.pawn, .knight, .bishop, .rook, .queen, .king]

    var displayName: String { rawValue.capitalized }

    var shortName: String {
        switch self {
        case .pawn: "Pawn"
        case .knight: "Knight"
        case .bishop: "Bishop"
        case .rook: "Rook"
        case .queen: "Queen"
        case .king: "King"
        }
    }

    var galleryDescription: String {
        switch self {
        case .pawn: "A compact advance unit, clean enough to read at a glance."
        case .knight: "A hard-edge carved horse: muzzle forward, mane down the spine."
        case .bishop: "A crystalline mitre built from cones, a bold diagonal cut at its crown."
        case .rook: "A squat turret with a fat footing and heavy battlements."
        case .queen: "The most elaborate silhouette: a crown that reads from across the board."
        case .king: "Tall, ceremonial, and intentionally more constrained than the queen."
        }
    }
}
