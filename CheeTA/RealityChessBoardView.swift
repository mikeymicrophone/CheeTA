import RealityKit
import SwiftUI
import UIKit

struct RealityChessBoardView: View {
    @ObservedObject var game: ChessGame
    let threatDisplayMode: ThreatDisplayMode
    @State private var cameraState = BoardCameraState()

    var body: some View {
        let visibleCorridors = game.threatCorridors(for: threatDisplayMode)

        RealityView { content in
            let sceneRoot = Entity()
            sceneRoot.name = RealityBoardScene.sceneRootName
            content.add(sceneRoot)

            let camera = PerspectiveCamera()
            camera.name = RealityBoardScene.cameraName
            camera.camera = PerspectiveCameraComponent(
                near: 0.05,
                far: 100,
                fieldOfViewInDegrees: 43
            )
            content.add(camera)
            content.camera = .virtual
            cameraState.camera = camera
            cameraState.apply()

            RealityBoardScene.rebuild(
                sceneRoot,
                game: game,
                visibleCorridors: visibleCorridors
            )
        } update: { content in
            guard let sceneRoot = content.entities.first(where: {
                $0.name == RealityBoardScene.sceneRootName
            }) else { return }

            RealityBoardScene.rebuild(
                sceneRoot,
                game: game,
                visibleCorridors: visibleCorridors
            )
            cameraState.camera = content.entities.first(where: {
                $0.name == RealityBoardScene.cameraName
            }) as? PerspectiveCamera
            cameraState.apply()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let square = RealityBoardScene.square(from: value.entity) else {
                        return
                    }
                    game.tap(square)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if !cameraState.isDragging {
                        cameraState.isDragging = true
                        cameraState.startYaw = cameraState.yaw
                        cameraState.startElevation = cameraState.elevation
                    }
                    cameraState.yaw = cameraState.startYaw + Float(value.translation.width) * 0.008
                    cameraState.elevation = cameraState.clampedElevation(
                        cameraState.startElevation - Float(value.translation.height) * 0.005
                    )
                    cameraState.apply()
                }
                .onEnded { value in
                    cameraState.yaw = cameraState.startYaw + Float(value.translation.width) * 0.008
                    cameraState.elevation = cameraState.clampedElevation(
                        cameraState.startElevation - Float(value.translation.height) * 0.005
                    )
                    cameraState.isDragging = false
                    cameraState.apply()
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { magnification in
                    if !cameraState.isPinching {
                        cameraState.isPinching = true
                        cameraState.startDistance = cameraState.distance
                    }
                    cameraState.distance = cameraState.clampedDistance(
                        cameraState.startDistance / Float(magnification)
                    )
                    cameraState.apply()
                }
                .onEnded { magnification in
                    cameraState.distance = cameraState.clampedDistance(
                        cameraState.startDistance / Float(magnification)
                    )
                    cameraState.isPinching = false
                    cameraState.apply()
                }
        )
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.12),
                    Color(red: 0.20, green: 0.24, blue: 0.23)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Interactive 3D chess board")
        .accessibilityHint("Tap a piece and then a highlighted square to move. Drag left or right to orbit, drag up or down to elevate, and pinch to zoom.")
    }
}

@MainActor
private final class BoardCameraState {
    private let target: SIMD3<Float> = [0, 0.25, 0]
    private let minimumElevation: Float = .pi / 10
    private let maximumElevation: Float = .pi * 0.39
    private let minimumDistance: Float = 8.4
    private let maximumDistance: Float = 17

    var camera: PerspectiveCamera?
    var yaw: Float = 0
    var elevation: Float = .pi * 0.23
    var distance: Float = 12.4
    var startYaw: Float = 0
    var startElevation: Float = .pi * 0.23
    var startDistance: Float = 12.4
    var isDragging = false
    var isPinching = false

    func clampedElevation(_ value: Float) -> Float {
        min(max(value, minimumElevation), maximumElevation)
    }

    func clampedDistance(_ value: Float) -> Float {
        min(max(value, minimumDistance), maximumDistance)
    }

    func apply() {
        guard let camera else { return }

        let horizontalDistance = cos(elevation) * distance
        let verticalDistance = sin(elevation) * distance
        let position: SIMD3<Float> = [
            sin(yaw) * horizontalDistance,
            target.y + verticalDistance,
            cos(yaw) * horizontalDistance
        ]
        camera.look(at: target, from: position, relativeTo: nil)
    }
}

/// The only layer that knows how the 3D board looks. Future USDZ character
/// models can replace `makePiece` while the chess and threat engines stay put.
@MainActor
private enum RealityBoardScene {
    static let sceneRootName = "cheeta-board-scene"
    static let cameraName = "cheeta-board-camera"

    private static let squareSize: Float = 1
    private static let tileHeight: Float = 0.12
    private static let overlayHeight: Float = 0.025

    static func rebuild(
        _ root: Entity,
        game: ChessGame,
        visibleCorridors: [ThreatCorridor]
    ) {
        root.children.removeAll()

        root.addChild(makeBoardBase())

        for rank in 0..<8 {
            for file in 0..<8 {
                guard let square = Square(file: file, rank: rank) else { continue }
                let position = boardPosition(for: square)
                let squareRoot = makeSquare(square, at: position)
                root.addChild(squareRoot)

                let corridors = visibleCorridors.filter {
                    $0.threatenedSquares.contains(square)
                }
                if !corridors.isEmpty {
                    let marker = makeThreatMarker(corridors: corridors)
                    marker.position = position + [0, tileHeight / 2 + overlayHeight / 2 + 0.012, 0]
                    root.addChild(marker)
                }

                if game.candidatePulseSquares.contains(square) {
                    let marker = makeCandidatePulseMarker()
                    marker.position = position + [0, tileHeight / 2 + 0.025, 0]
                    root.addChild(marker)
                }

                if game.lastMove?.from == square || game.lastMove?.to == square {
                    let marker = makeFlatMarker(color: UIColor.systemYellow.withAlphaComponent(0.36))
                    marker.position = position + [0, tileHeight / 2 + 0.012, 0]
                    root.addChild(marker)
                }

                if game.isKingInCheck(at: square) {
                    let marker = makeFlatMarker(color: UIColor.systemRed.withAlphaComponent(0.58))
                    marker.position = position + [0, tileHeight / 2 + 0.026, 0]
                    root.addChild(marker)
                }

                if game.selectedSquare == square {
                    let marker = makeFrame(color: .systemYellow, thickness: 0.075)
                    marker.position = position + [0, tileHeight / 2 + 0.055, 0]
                    root.addChild(marker)
                }

                if game.legalTargets.contains(square) {
                    let marker: Entity
                    if game.piece(at: square) == nil {
                        marker = model(
                            .generateCylinder(height: 0.035, radius: 0.14),
                            color: UIColor.systemBlue.withAlphaComponent(0.82)
                        )
                    } else {
                        marker = makeFrame(color: .systemRed, thickness: 0.075)
                    }
                    marker.position = position + [0, tileHeight / 2 + 0.075, 0]
                    root.addChild(marker)
                }

                if let piece = game.piece(at: square) {
                    let pieceEntity = makePiece(piece)
                    pieceEntity.position = position + [0, tileHeight / 2, 0]
                    root.addChild(pieceEntity)
                }
            }
        }
    }

    static func square(from entity: Entity) -> Square? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name.hasPrefix("square-"),
               let square = Square(String(current.name.dropFirst("square-".count))) {
                return square
            }
            candidate = current.parent
        }
        return nil
    }

    private static func boardPosition(for square: Square) -> SIMD3<Float> {
        [
            (Float(square.file) - 3.5) * squareSize,
            0,
            (3.5 - Float(square.rank)) * squareSize
        ]
    }

    private static func makeBoardBase() -> Entity {
        let root = Entity()

        let rim = model(
            .generateBox(size: [8.55, 0.22, 8.55], cornerRadius: 0.18),
            color: UIColor(red: 0.09, green: 0.11, blue: 0.11, alpha: 1),
            metallic: true,
            roughness: 0.32
        )
        rim.position.y = -0.11
        root.addChild(rim)

        let plinth = model(
            .generateBox(size: [8.9, 0.13, 8.9], cornerRadius: 0.22),
            color: UIColor(red: 0.03, green: 0.04, blue: 0.045, alpha: 1),
            metallic: true,
            roughness: 0.24
        )
        plinth.position.y = -0.25
        root.addChild(plinth)

        return root
    }

    private static func makeSquare(_ square: Square, at position: SIMD3<Float>) -> Entity {
        let isDark = (square.file + square.rank).isMultiple(of: 2)
        let color = isDark
            ? UIColor(red: 0.16, green: 0.30, blue: 0.25, alpha: 1)
            : UIColor(red: 0.76, green: 0.68, blue: 0.50, alpha: 1)

        let tile = model(
            .generateBox(size: [0.985, tileHeight, 0.985], cornerRadius: 0.025),
            color: color,
            roughness: 0.58
        )
        tile.name = "square-\(square.algebraic)"
        tile.position = position
        tile.components.set(InputTargetComponent())
        tile.components.set(
            CollisionComponent(shapes: [
                .generateBox(size: [0.985, 0.34, 0.985])
            ])
        )
        return tile
    }

    private static func makePiece(_ piece: Piece) -> Entity {
        let root = Entity()
        let pieceColor = piece.player == .white
            ? UIColor(red: 0.92, green: 0.88, blue: 0.75, alpha: 1)
            : UIColor(red: 0.055, green: 0.065, blue: 0.075, alpha: 1)
        let accentColor = piece.player == .white
            ? UIColor(red: 0.56, green: 0.68, blue: 0.69, alpha: 1)
            : UIColor(red: 0.30, green: 0.17, blue: 0.38, alpha: 1)

        addPart(.generateCylinder(height: 0.13, radius: 0.34), y: 0.065, color: pieceColor, to: root)
        addPart(.generateCylinder(height: 0.10, radius: 0.27), y: 0.18, color: accentColor, to: root)

        switch piece.kind {
        case .pawn:
            addPart(.generateCone(height: 0.40, radius: 0.20), y: 0.42, color: pieceColor, to: root)
            addPart(.generateSphere(radius: 0.18), y: 0.70, color: pieceColor, to: root)

        case .rook:
            addPart(.generateCylinder(height: 0.48, radius: 0.22), y: 0.46, color: pieceColor, to: root)
            addPart(.generateBox(size: [0.50, 0.16, 0.50], cornerRadius: 0.035), y: 0.76, color: accentColor, to: root)
            for x in [-0.18 as Float, 0.18] {
                for z in [-0.18 as Float, 0.18] {
                    addPart(
                        .generateBox(size: [0.13, 0.16, 0.13], cornerRadius: 0.02),
                        position: [x, 0.90, z],
                        color: pieceColor,
                        to: root
                    )
                }
            }

        case .knight:
            addPart(.generateCylinder(height: 0.27, radius: 0.21), y: 0.35, color: pieceColor, to: root)
            let neck = model(
                .generateBox(size: [0.27, 0.50, 0.31], cornerRadius: 0.10),
                color: pieceColor,
                roughness: 0.32
            )
            neck.position = [0, 0.64, -0.05]
            neck.orientation = simd_quatf(angle: -0.30, axis: [1, 0, 0])
            root.addChild(neck)
            addPart(.generateBox(size: [0.30, 0.24, 0.44], cornerRadius: 0.12), position: [0, 0.89, -0.13], color: accentColor, to: root)
            addPart(.generateBox(size: [0.08, 0.16, 0.08], cornerRadius: 0.025), position: [-0.11, 1.05, -0.13], color: pieceColor, to: root)
            addPart(.generateBox(size: [0.08, 0.16, 0.08], cornerRadius: 0.025), position: [0.11, 1.05, -0.13], color: pieceColor, to: root)

        case .bishop:
            addPart(.generateCone(height: 0.64, radius: 0.23), y: 0.52, color: pieceColor, to: root)
            addPart(.generateSphere(radius: 0.18), y: 0.88, color: accentColor, to: root)
            let slash = model(.generateBox(size: [0.055, 0.30, 0.055], cornerRadius: 0.02), color: pieceColor)
            slash.position = [0, 0.91, 0.15]
            slash.orientation = simd_quatf(angle: -0.55, axis: [0, 0, 1])
            root.addChild(slash)

        case .queen:
            addPart(.generateCone(height: 0.68, radius: 0.25), y: 0.54, color: pieceColor, to: root)
            addPart(.generateCylinder(height: 0.11, radius: 0.28), y: 0.91, color: accentColor, to: root)
            for angle in stride(from: Float.zero, to: Float.pi * 2, by: Float.pi / 3) {
                let crownPosition: SIMD3<Float> = [cos(angle) * 0.20, 1.07, sin(angle) * 0.20]
                addPart(.generateSphere(radius: 0.085), position: crownPosition, color: pieceColor, to: root)
            }
            addPart(.generateSphere(radius: 0.11), y: 1.09, color: accentColor, to: root)

        case .king:
            addPart(.generateCone(height: 0.68, radius: 0.25), y: 0.54, color: pieceColor, to: root)
            addPart(.generateCylinder(height: 0.12, radius: 0.27), y: 0.91, color: accentColor, to: root)
            addPart(.generateSphere(radius: 0.11), y: 1.06, color: pieceColor, to: root)
            addPart(.generateBox(size: [0.10, 0.38, 0.10], cornerRadius: 0.025), y: 1.26, color: pieceColor, to: root)
            addPart(.generateBox(size: [0.34, 0.10, 0.10], cornerRadius: 0.025), y: 1.29, color: pieceColor, to: root)
        }

        if piece.player == .black {
            root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        }
        return root
    }

    private static func makeThreatMarker(corridors: [ThreatCorridor]) -> Entity {
        let whiteCount = corridors.filter { $0.piece.player == .white }.count
        let blackCount = corridors.count - whiteCount
        let thickness: Float
        switch corridors.count {
        case 1: thickness = 0.065
        case 2: thickness = 0.18
        case 3: thickness = 0.34
        default: thickness = 0.45
        }

        if whiteCount > 0 && blackCount > 0 {
            return makeStripedFrame(thickness: thickness)
        }

        return makeFrame(
            color: whiteCount > 0 ? .systemCyan : .systemPurple,
            thickness: thickness
        )
    }

    private static func makeCandidatePulseMarker() -> Entity {
        let root = Entity()
        let disc = model(
            .generateCylinder(height: 0.032, radius: 0.48),
            color: .systemOrange,
            metallic: true,
            roughness: 0.18
        )
        disc.components.set(OpacityComponent(opacity: 0.55))
        disc.transform = Transform(scale: [0.82, 1, 0.82])
        root.addChild(disc)

        do {
            let grow = try AnimationResource.generate(
                with: FromToByAnimation<Transform>(
                    from: Transform(scale: [0.82, 1, 0.82]),
                    to: Transform(scale: [1.04, 1, 1.04]),
                    duration: 0.72,
                    timing: .easeInOut,
                    bindTarget: .transform
                )
            )
            let shrink = try AnimationResource.generate(
                with: FromToByAnimation<Transform>(
                    from: Transform(scale: [1.04, 1, 1.04]),
                    to: Transform(scale: [0.82, 1, 0.82]),
                    duration: 0.72,
                    timing: .easeInOut,
                    bindTarget: .transform
                )
            )
            let brighten = try AnimationResource.generate(
                with: FromToByAnimation<Float>(
                    from: 0.48,
                    to: 1.0,
                    duration: 0.72,
                    timing: .easeInOut,
                    bindTarget: .opacity
                )
            )
            let dim = try AnimationResource.generate(
                with: FromToByAnimation<Float>(
                    from: 1.0,
                    to: 0.48,
                    duration: 0.72,
                    timing: .easeInOut,
                    bindTarget: .opacity
                )
            )
            let scalePulse = try AnimationResource.sequence(with: [grow, shrink])
            let opacityPulse = try AnimationResource.sequence(with: [brighten, dim])
            let pulse = try AnimationResource.group(with: [scalePulse, opacityPulse])
            disc.playAnimation(pulse.repeat())
        } catch {
            // A static marker still communicates candidacy if animation setup fails.
        }

        return root
    }

    private static func makeStripedFrame(thickness: Float) -> Entity {
        let root = Entity()
        let outer: Float = 0.94
        let segmentCount = 8
        let segmentLength = outer / Float(segmentCount)
        let colors = [UIColor.systemCyan, UIColor.systemPurple]

        for edge in 0..<4 {
            for index in 0..<segmentCount {
                let offset = -outer / 2 + segmentLength / 2 + Float(index) * segmentLength
                let color = colors[(index + edge) % colors.count].withAlphaComponent(0.88)
                let bar: ModelEntity
                if edge < 2 {
                    bar = model(
                        .generateBox(size: [segmentLength + 0.006, overlayHeight, thickness]),
                        color: color,
                        roughness: 0.24
                    )
                    bar.position = [offset, 0, edge == 0 ? -outer / 2 : outer / 2]
                } else {
                    bar = model(
                        .generateBox(size: [thickness, overlayHeight, segmentLength + 0.006]),
                        color: color,
                        roughness: 0.24
                    )
                    bar.position = [edge == 2 ? -outer / 2 : outer / 2, 0, offset]
                }
                root.addChild(bar)
            }
        }
        return root
    }

    private static func makeFrame(color: UIColor, thickness: Float) -> Entity {
        let root = Entity()
        let outer: Float = 0.94
        let materialColor = color.withAlphaComponent(0.88)

        for z in [-outer / 2, outer / 2] {
            let bar = model(
                .generateBox(size: [outer, overlayHeight, thickness]),
                color: materialColor,
                roughness: 0.24
            )
            bar.position.z = z
            root.addChild(bar)
        }
        for x in [-outer / 2, outer / 2] {
            let bar = model(
                .generateBox(size: [thickness, overlayHeight, outer]),
                color: materialColor,
                roughness: 0.24
            )
            bar.position.x = x
            root.addChild(bar)
        }
        return root
    }

    private static func makeFlatMarker(color: UIColor) -> ModelEntity {
        model(
            .generateBox(size: [0.94, 0.018, 0.94], cornerRadius: 0.018),
            color: color,
            roughness: 0.35
        )
    }

    private static func addPart(
        _ mesh: MeshResource,
        y: Float,
        color: UIColor,
        to root: Entity
    ) {
        addPart(mesh, position: [0, y, 0], color: color, to: root)
    }

    private static func addPart(
        _ mesh: MeshResource,
        position: SIMD3<Float>,
        color: UIColor,
        to root: Entity
    ) {
        let entity = model(mesh, color: color, metallic: true, roughness: 0.28)
        entity.position = position
        root.addChild(entity)
    }

    private static func model(
        _ mesh: MeshResource,
        color: UIColor,
        metallic: Bool = false,
        roughness: Float = 0.45
    ) -> ModelEntity {
        let material = SimpleMaterial(
            color: color,
            roughness: .float(roughness),
            isMetallic: metallic
        )
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
