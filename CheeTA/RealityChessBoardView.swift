import RealityKit
import SwiftUI
import UIKit

struct RealityChessBoardView: View {
    @ObservedObject var game: ChessGame
    let threatDisplayMode: ThreatDisplayMode
    let boardOpacity: Float
    let piecePalette: PiecePalette
    let isLightLoose: Bool
    @State private var cameraState = BoardCameraState()
    @State private var lightRig = BoardLightRig()

    var body: some View {
        let visibleCorridors = game.threatCorridors(for: threatDisplayMode)

        RealityView { content in
            let sceneRoot = Entity()
            sceneRoot.name = RealityBoardScene.sceneRootName
            content.add(sceneRoot)

            // The rig is a sibling of the scene root so a board rebuild, which
            // wipes its children every update, never takes the light with it.
            lightRig.attach(to: content)
            lightRig.isLoose = isLightLoose

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
                visibleCorridors: visibleCorridors,
                boardOpacity: boardOpacity,
                piecePalette: piecePalette
            )
        } update: { content in
            guard let sceneRoot = content.entities.first(where: {
                $0.name == RealityBoardScene.sceneRootName
            }) else { return }

            RealityBoardScene.rebuild(
                sceneRoot,
                game: game,
                visibleCorridors: visibleCorridors,
                boardOpacity: boardOpacity,
                piecePalette: piecePalette
            )
            cameraState.camera = content.entities.first(where: {
                $0.name == RealityBoardScene.cameraName
            }) as? PerspectiveCamera
            cameraState.apply()
            lightRig.isLoose = isLightLoose
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

enum PiecePalette: String, CaseIterable, Identifiable {
    case arcade
    case neon
    case royal

    var id: Self { self }

    var displayName: String {
        switch self {
        case .arcade: "Arcade"
        case .neon: "Neon"
        case .royal: "Royal"
        }
    }

    func colors(for player: Player) -> (piece: UIColor, accent: UIColor) {
        switch (self, player) {
        case (.arcade, .white):
            (
                UIColor(red: 0.92, green: 0.88, blue: 0.75, alpha: 1),
                UIColor(red: 0.56, green: 0.68, blue: 0.69, alpha: 1)
            )
        case (.arcade, .black):
            (
                UIColor(red: 0.055, green: 0.065, blue: 0.075, alpha: 1),
                UIColor(red: 0.30, green: 0.17, blue: 0.38, alpha: 1)
            )
        case (.neon, .white):
            (
                UIColor(red: 0.44, green: 1.0, blue: 0.91, alpha: 1),
                UIColor(red: 0.05, green: 0.72, blue: 1.0, alpha: 1)
            )
        case (.neon, .black):
            (
                UIColor(red: 0.16, green: 0.04, blue: 0.24, alpha: 1),
                UIColor(red: 1.0, green: 0.14, blue: 0.56, alpha: 1)
            )
        case (.royal, .white):
            (
                UIColor(red: 0.93, green: 0.70, blue: 0.19, alpha: 1),
                UIColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 1)
            )
        case (.royal, .black):
            (
                UIColor(red: 0.06, green: 0.12, blue: 0.34, alpha: 1),
                UIColor(red: 0.70, green: 0.78, blue: 1.0, alpha: 1)
            )
        }
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

/// A point light with a visible bulb that either parks in a fixed key-light
/// position or careens around the board. The motion is layered sine waves at
/// mutually irrational frequencies (so the path never loops) plus random jolts
/// (so it never looks like it is on rails).
@MainActor
private final class BoardLightRig {
    private static let home: SIMD3<Float> = [-4.6, 7.4, 5.2]
    private static let baseIntensity: Float = 260_000
    /// Warm tungsten, everywhere: the light, the glass, and the filament.
    private static let calmColor = UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1)
    private static let glowColor = UIColor(red: 1.0, green: 0.83, blue: 0.58, alpha: 1)

    var isLoose = false {
        didSet {
            guard isLoose != oldValue else { return }
            if isLoose { elapsed = 0 }
            nextJolt = 0
        }
    }

    private let root = Entity()
    private let bulb = Entity()
    private let halo = Entity()
    private var subscription: EventSubscription?
    private var elapsed: Double = 0
    private var jolt: SIMD3<Float> = .zero
    private var joltTarget: SIMD3<Float> = .zero
    private var nextJolt: Double = 0

    init() {
        root.position = Self.home
        root.components.set(
            PointLightComponent(
                color: Self.calmColor,
                intensity: Self.baseIntensity,
                attenuationRadius: 60
            )
        )
        buildBulb()
        bulb.isEnabled = false
        bulb.components.set(OpacityComponent(opacity: 0))
        root.addChild(bulb)
    }

    /// `UnlitMaterial(color:)` ignores the color's alpha channel, so anything
    /// meant to be see-through has to say so through `blending`.
    private static func glowMaterial(color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// A squat Edison-style bulb: brass cap, clear glass envelope, and a
    /// hairpin filament that carries the flicker.
    private func buildBulb() {
        // Nested shells fake a falloff; one shell alone reads as a flat disc.
        for radius in [Float(0.46), Float(0.60), Float(0.76)] {
            let shell = ModelEntity(
                mesh: .generateSphere(radius: radius),
                materials: [Self.glowMaterial(color: Self.glowColor, opacity: 0.06)]
            )
            halo.addChild(shell)
        }
        bulb.addChild(halo)

        let glass = ModelEntity(
            mesh: .generateSphere(radius: 0.38),
            materials: [Self.glowMaterial(color: Self.glowColor, opacity: 0.16)]
        )
        bulb.addChild(glass)

        let filamentMaterial = UnlitMaterial(
            color: UIColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 1)
        )

        // Two lead-in posts rising from the cap...
        for x in [Float(-0.085), Float(0.085)] {
            let post = ModelEntity(
                mesh: .generateBox(size: [0.022, 0.24, 0.022]),
                materials: [filamentMaterial]
            )
            post.position = [x, -0.06, 0]
            bulb.addChild(post)
        }

        // ...bridged by a zigzag coil.
        let segments = 7
        for index in 0..<segments {
            let progress = Float(index) / Float(segments - 1)
            let segment = ModelEntity(
                mesh: .generateBox(size: [0.022, 0.13, 0.02]),
                materials: [filamentMaterial]
            )
            segment.position = [-0.085 + 0.17 * progress, 0.115, 0]
            segment.orientation = simd_quatf(
                angle: index.isMultiple(of: 2) ? 0.62 : -0.62,
                axis: [0, 0, 1]
            )
            bulb.addChild(segment)
        }

        let brass = SimpleMaterial(
            color: UIColor(red: 0.66, green: 0.50, blue: 0.24, alpha: 1),
            roughness: 0.28,
            isMetallic: true
        )
        let neck = ModelEntity(
            mesh: .generateCylinder(height: 0.2, radius: 0.17),
            materials: [brass]
        )
        neck.position.y = -0.4
        bulb.addChild(neck)

        let cap = ModelEntity(
            mesh: .generateCylinder(height: 0.07, radius: 0.1),
            materials: [brass]
        )
        cap.position.y = -0.53
        bulb.addChild(cap)
    }

    func attach(to content: some RealityViewContentProtocol) {
        guard subscription == nil else { return }
        content.add(root)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                self?.tick(event.deltaTime)
            }
        }
    }

    private func tick(_ deltaTime: TimeInterval) {
        let step = Float(min(deltaTime, 1.0 / 20))

        guard isLoose else {
            settle(step: step)
            return
        }

        elapsed += deltaTime
        let time = elapsed

        let angle = time * 1.9 + 0.9 * sin(time * 0.77)
        let radius = 3.4 + 1.3 * sin(time * 1.31 + 0.4)
        let height = 3.2 + 2.0 * sin(time * 2.17 + 1.2)
        var target = SIMD3<Float>(
            Float(cos(angle) * radius),
            Float(height),
            Float(sin(angle) * radius)
        )

        nextJolt -= deltaTime
        if nextJolt <= 0 {
            nextJolt = .random(in: 0.22...0.85)
            joltTarget = [
                .random(in: -1.7...1.7),
                .random(in: -1.8...2.4),
                .random(in: -1.7...1.7)
            ]
        }
        jolt += (joltTarget - jolt) * min(1, step * 7)
        target += jolt
        // Skimming the surface is fun; diving under the plinth is not.
        target.y = max(target.y, 0.6)

        root.position += (target - root.position) * min(1, step * 9)

        // Fast flicker on top of a slow swell, so the filament keeps breathing
        // even while the light is between jolts.
        let flicker = min(
            1,
            max(
                0,
                0.68
                    + 0.24 * Float(sin(time * 11.7))
                    + 0.16 * Float(sin(time * 2.9 + 0.6))
            )
        )

        root.components.set(
            PointLightComponent(
                color: Self.calmColor,
                intensity: Self.baseIntensity * (1.35 + 0.85 * flicker),
                attenuationRadius: 60
            )
        )
        bulb.isEnabled = true
        bulb.components.set(OpacityComponent(opacity: 1))
        // A lazy tumble so the filament catches the eye from every angle.
        bulb.orientation = simd_quatf(
            angle: Float(time * 0.85),
            axis: normalize([0.24, 1, 0.16])
        )
        halo.scale = .init(repeating: 0.9 + 0.3 * flicker)
        halo.components.set(OpacityComponent(opacity: 0.55 + 0.45 * flicker))
    }

    private func settle(step: Float) {
        guard bulb.isEnabled else { return }

        let blend = min(1, step * 4)
        root.position += (Self.home - root.position) * blend
        let fade = (bulb.components[OpacityComponent.self]?.opacity ?? 1) * (1 - blend)

        root.components.set(
            PointLightComponent(
                color: Self.calmColor,
                intensity: Self.baseIntensity,
                attenuationRadius: 60
            )
        )

        if fade < 0.03 && length(Self.home - root.position) < 0.05 {
            root.position = Self.home
            jolt = .zero
            bulb.isEnabled = false
            bulb.components.set(OpacityComponent(opacity: 0))
            return
        }

        bulb.components.set(OpacityComponent(opacity: fade))
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
        visibleCorridors: [ThreatCorridor],
        boardOpacity: Float,
        piecePalette: PiecePalette
    ) {
        root.children.removeAll()

        let boardSurface = Entity()
        boardSurface.addChild(makeBoardBase(opacity: boardOpacity))
        root.addChild(boardSurface)

        for rank in 0..<8 {
            for file in 0..<8 {
                guard let square = Square(file: file, rank: rank) else { continue }
                let position = boardPosition(for: square)
                let squareRoot = makeSquare(square, at: position, opacity: boardOpacity)
                boardSurface.addChild(squareRoot)

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
                    let pieceEntity = makePiece(piece, palette: piecePalette)
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

    private static func makeBoardBase(opacity: Float) -> Entity {
        let root = Entity()

        let rim = model(
            .generateBox(size: [8.55, 0.22, 8.55], cornerRadius: 0.18),
            color: UIColor(red: 0.09, green: 0.11, blue: 0.11, alpha: 1),
            metallic: true,
            roughness: 0.32
        )
        rim.components.set(OpacityComponent(opacity: opacity))
        rim.position.y = -0.11
        root.addChild(rim)

        let plinth = model(
            .generateBox(size: [8.9, 0.13, 8.9], cornerRadius: 0.22),
            color: UIColor(red: 0.03, green: 0.04, blue: 0.045, alpha: 1),
            metallic: true,
            roughness: 0.24
        )
        plinth.components.set(OpacityComponent(opacity: opacity))
        plinth.position.y = -0.25
        root.addChild(plinth)

        return root
    }

    private static func makeSquare(
        _ square: Square,
        at position: SIMD3<Float>,
        opacity: Float
    ) -> Entity {
        let isDark = (square.file + square.rank).isMultiple(of: 2)
        let color = isDark
            ? UIColor(red: 0.16, green: 0.30, blue: 0.25, alpha: 1)
            : UIColor(red: 0.76, green: 0.68, blue: 0.50, alpha: 1)

        let tile = model(
            .generateBox(size: [0.985, tileHeight, 0.985], cornerRadius: 0.025),
            color: color,
            roughness: 0.58
        )
        tile.components.set(OpacityComponent(opacity: opacity))
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

    private static func makePiece(_ piece: Piece, palette: PiecePalette) -> Entity {
        let root = Entity()
        let colors = palette.colors(for: piece.player)
        let pieceColor = colors.piece
        let accentColor = colors.accent

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
