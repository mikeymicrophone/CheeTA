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
    @State private var inspectionEpoch = 0

    var body: some View {
        NavigationStack {
            ZStack {
                PieceInspectionScene(
                    piece: Piece(kind: selectedKind, player: selectedPlayer),
                    palette: palette,
                    resetEpoch: inspectionEpoch
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Picker("Side", selection: $selectedPlayer) {
                        Text("White").tag(Player.white)
                        Text("Black").tag(Player.black)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    HStack(spacing: 12) {
                        Label("Drag to tumble", systemImage: "rotate.3d")
                        Label("Twist to roll", systemImage: "rotate.right")
                        Label("Pinch to zoom", systemImage: "arrow.up.left.and.arrow.down.right")

                        Spacer(minLength: 0)

                        Button {
                            inspectionEpoch += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.14), in: Circle())
                        }
                        .accessibilityLabel("Reset piece view")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    VStack(spacing: 4) {
                        Text(selectedKind.displayName.uppercased())
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .tracking(1.6)

                        Text(selectedKind.galleryDescription)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 450)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .allowsHitTesting(false)

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
            }
            .background(Color.black)
            .navigationTitle("Piece Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationSizing(.page)
        .accessibilityLabel("Close-up chess piece gallery")
    }
}

/// A free-standing studio plinth. Drag to tumble the model on any axis;
/// pinch to inspect its finish; twist with two fingers to roll.
///
/// Gestures write the pivot entity directly. Pushing every drag sample
/// through `@State` would rebuild this view — and RealityView's update —
/// sixty times a second.
private struct PieceInspectionScene: View {
    let piece: Piece
    let palette: PiecePalette
    let resetEpoch: Int

    @State private var rig = InspectionRig()

    private let rootName = "piece-inspection-root"
    private let pivotName = "inspection-pivot"
    private let rimName = "inspection-rim"
    private static let pivotHeight: Float = 0.68

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
                materials: [rimMaterial]
            )
            rim.name = rimName
            rim.position.y = 0.015
            root.addChild(rim)

            let pivot = Entity()
            pivot.name = pivotName
            pivot.position.y = Self.pivotHeight
            root.addChild(pivot)
            rig.attach(pivot)
            syncPiece(in: pivot)
            rig.apply()

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
            camera.look(at: [0, 0.62, 0], from: [0, 1.08, 4.15], relativeTo: nil)
            content.add(camera)
            content.camera = .virtual

        } update: { content in
            guard let root = content.entities.first(where: { $0.name == rootName }) else { return }
            syncRim(on: root)
            guard let pivot = root.findEntity(named: pivotName) else { return }
            rig.attach(pivot)
            syncPiece(in: pivot)
            rig.apply()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [palette.pieceColor(for: piece.player).opacity(0.36), Color.black.opacity(0.96)],
                center: .top,
                startRadius: 10,
                endRadius: 720
            )
        )
        .onChange(of: resetEpoch) {
            rig.reset()
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !rig.isDragging {
                        rig.isDragging = true
                        rig.startOrientation = rig.orientation
                    }
                    rig.orientation = dragOrientation(from: value.translation)
                    rig.apply()
                }
                .onEnded { value in
                    rig.orientation = dragOrientation(from: value.translation)
                    rig.isDragging = false
                    rig.apply()
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if !rig.isPinching {
                        rig.isPinching = true
                        rig.startScale = rig.scale
                    }
                    rig.scale = min(max(rig.startScale * Float(value), 0.72), 2.2)
                    rig.apply()
                }
                .onEnded { value in
                    rig.scale = min(max(rig.startScale * Float(value), 0.72), 2.2)
                    rig.isPinching = false
                    rig.apply()
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { angle in
                    if !rig.isRolling {
                        rig.isRolling = true
                        rig.startOrientation = rig.orientation
                    }
                    rig.orientation = rollOrientation(from: angle)
                    rig.apply()
                }
                .onEnded { angle in
                    rig.orientation = rollOrientation(from: angle)
                    rig.isRolling = false
                    rig.apply()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Close-up \(piece.player.displayName) \(piece.kind.displayName)")
        .accessibilityHint("Drag to tumble the piece on any axis. Twist with two fingers to roll. Pinch to zoom.")
    }

    private var pieceToken: String {
        "\(piece.player.rawValue)-\(piece.kind.rawValue)"
    }

    private var rimMaterial: SimpleMaterial {
        SimpleMaterial(
            color: UIColor(palette.pieceColor(for: piece.player)).withAlphaComponent(0.72),
            roughness: .float(0.2),
            isMetallic: true
        )
    }

    private func syncPiece(in pivot: Entity) {
        if pivot.children.first?.name == pieceToken { return }
        pivot.children.removeAll()
        let model = RealityBoardScene.makePiece(piece, palette: palette)
        model.name = pieceToken
        model.position.y = -Self.pivotHeight
        pivot.addChild(model)
    }

    private func syncRim(on root: Entity) {
        guard let rim = root.findEntity(named: rimName) as? ModelEntity else { return }
        let token = piece.player.rawValue
        guard rig.rimPlayerToken != token else { return }
        rig.rimPlayerToken = token
        rim.model?.materials = [rimMaterial]
    }

    private func dragOrientation(from translation: CGSize) -> simd_quatf {
        let yaw = simd_quatf(angle: -Float(translation.width) * 0.01, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(translation.height) * 0.01, axis: [1, 0, 0])
        return yaw * pitch * rig.startOrientation
    }

    private func rollOrientation(from angle: Angle) -> simd_quatf {
        let roll = simd_quatf(angle: Float(angle.radians), axis: [0, 0, 1])
        return roll * rig.startOrientation
    }
}

@MainActor
private final class InspectionRig {
    static let homeOrientation = simd_quatf(angle: -0.42, axis: [0, 1, 0])
        * simd_quatf(angle: -0.13, axis: [1, 0, 0])

    var orientation = InspectionRig.homeOrientation
    var scale: Float = 1
    var startOrientation = InspectionRig.homeOrientation
    var startScale: Float = 1
    var isDragging = false
    var isPinching = false
    var isRolling = false
    var rimPlayerToken: String?
    private weak var pivot: Entity?

    func attach(_ pivot: Entity) {
        self.pivot = pivot
    }

    func apply() {
        guard let pivot else { return }
        pivot.orientation = orientation
        pivot.scale = SIMD3<Float>(repeating: scale)
    }

    func reset() {
        orientation = Self.homeOrientation
        scale = 1
        apply()
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
        case .pawn: "A turned Staunton pawn: stepped foot, slender waist, and a spherical head."
        case .knight: "The horse of the set: a carved head on the same turned plinth as its siblings."
        case .bishop: "A mitre with the traditional cleft, rising from a slender lathed stem."
        case .rook: "A castle tower — flared cornice, crenellations, and a hollowed crown."
        case .queen: "The most ornate silhouette: a coronet of pearls above a tall turned stem."
        case .king: "The tallest piece, finished with a circlet and a cross."
        }
    }
}
