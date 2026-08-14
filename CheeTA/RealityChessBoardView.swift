import RealityKit
import SwiftUI
import UIKit

struct RealityChessBoardView: View {
    @ObservedObject var game: ChessGame
    let threatDisplayMode: ThreatDisplayMode
    let boardOpacity: Float
    let piecePalette: PiecePalette
    let isLightLoose: Bool
    var onTap: ((Square) -> Void)? = nil
    var inspectSelectedSquare: Square? = nil
    var inspectLegalTargets: Set<Square>? = nil
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
                piecePalette: piecePalette,
                selectedSquare: inspectSelectedSquare,
                legalTargets: inspectLegalTargets
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
                piecePalette: piecePalette,
                selectedSquare: inspectSelectedSquare,
                legalTargets: inspectLegalTargets
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
                    (onTap ?? { game.tap($0) })(square)
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
                    // Negated so the board turns with the finger. Adding the
                    // translation orbits the camera toward the drag instead,
                    // which reads as the board sliding the opposite way.
                    cameraState.yaw = cameraState.startYaw - Float(value.translation.width) * 0.008
                    cameraState.elevation = cameraState.clampedElevation(
                        cameraState.startElevation - Float(value.translation.height) * 0.005
                    )
                    cameraState.apply()
                }
                .onEnded { value in
                    cameraState.yaw = cameraState.startYaw - Float(value.translation.width) * 0.008
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

/// Four freely editable colors — body and accent for each side. The named
/// palettes are just starting points now, not the only choices.
struct PiecePalette: Equatable {
    var whitePiece: Color
    var whiteAccent: Color
    var blackPiece: Color
    var blackAccent: Color

    func colors(for player: Player) -> (piece: UIColor, accent: UIColor) {
        switch player {
        case .white: (UIColor(whitePiece), UIColor(whiteAccent))
        case .black: (UIColor(blackPiece), UIColor(blackAccent))
        }
    }

    func pieceColor(for player: Player) -> Color {
        player == .white ? whitePiece : blackPiece
    }

    struct Preset: Identifiable {
        var id: String { name }
        let name: String
        let palette: PiecePalette
    }

    static let presets: [Preset] = [
        Preset(name: "Arcade", palette: .arcade),
        Preset(name: "Neon", palette: .neon),
        Preset(name: "Royal", palette: .royal)
    ]

    static let arcade = PiecePalette(
        whitePiece: Color(red: 0.92, green: 0.88, blue: 0.75),
        whiteAccent: Color(red: 0.56, green: 0.68, blue: 0.69),
        blackPiece: Color(red: 0.055, green: 0.065, blue: 0.075),
        blackAccent: Color(red: 0.30, green: 0.17, blue: 0.38)
    )

    static let neon = PiecePalette(
        whitePiece: Color(red: 0.44, green: 1.0, blue: 0.91),
        whiteAccent: Color(red: 0.05, green: 0.72, blue: 1.0),
        blackPiece: Color(red: 0.16, green: 0.04, blue: 0.24),
        blackAccent: Color(red: 1.0, green: 0.14, blue: 0.56)
    )

    static let royal = PiecePalette(
        whitePiece: Color(red: 0.93, green: 0.70, blue: 0.19),
        whiteAccent: Color(red: 1.0, green: 0.90, blue: 0.55),
        blackPiece: Color(red: 0.06, green: 0.12, blue: 0.34),
        blackAccent: Color(red: 0.70, green: 0.78, blue: 1.0)
    )
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
enum RealityBoardScene {
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
        piecePalette: PiecePalette,
        selectedSquare: Square? = nil,
        legalTargets: Set<Square>? = nil
    ) {
        let selected = selectedSquare ?? game.selectedSquare
        let targets = legalTargets ?? game.legalTargets
        root.children.removeAll()

        let boardSurface = Entity()
        boardSurface.addChild(makeBoardBase(opacity: boardOpacity))
        root.addChild(boardSurface)

        // Both of these are the same for all 64 squares, and both are
        // expensive: the pulse set runs full legal-move generation for every
        // piece. Read once per rebuild, not once per square.
        let pulseSquares = game.candidatePulseSquares
        let corridorsBySquare = Dictionary(
            grouping: visibleCorridors.flatMap { corridor in
                corridor.threatenedSquares.compactMap { square in
                    marksThreatenedPiece(corridor, at: square, on: game)
                        ? (square, corridor)
                        : nil
                }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        for rank in 0..<8 {
            for file in 0..<8 {
                guard let square = Square(file: file, rank: rank) else { continue }
                let position = boardPosition(for: square)
                let squareRoot = makeSquare(square, at: position, opacity: boardOpacity)
                boardSurface.addChild(squareRoot)

                let corridors = corridorsBySquare[square] ?? []
                if !corridors.isEmpty {
                    let marker = makeThreatMarker(corridors: corridors)
                    marker.position = position + [0, tileHeight / 2 + overlayHeight / 2 + 0.012, 0]
                    root.addChild(marker)
                }

                if pulseSquares.contains(square) {
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

                if selected == square {
                    let marker = makeFrame(color: .systemYellow, thickness: 0.075)
                    marker.position = position + [0, tileHeight / 2 + 0.055, 0]
                    root.addChild(marker)
                }

                if targets.contains(square) {
                    let isCapture = game.piece(at: square) != nil

                    // An arrow from the piece to the square says where it is
                    // going, not merely where it may land.
                    if let origin = selected {
                        let arrow = makeMoveArrow(
                            from: boardPosition(for: origin),
                            to: position,
                            color: isCapture ? .systemRed : .systemBlue
                        )
                        root.addChild(arrow)
                    }

                    if isCapture {
                        let marker = makeFrame(color: .systemRed, thickness: 0.075)
                        marker.position = position + [0, tileHeight / 2 + 0.075, 0]
                        root.addChild(marker)
                    }
                }

                if let piece = game.piece(at: square) {
                    let pieceEntity = makePiece(piece, palette: piecePalette)
                    pieceEntity.position = position + [0, tileHeight / 2, 0]
                    root.addChild(pieceEntity)
                }
            }
        }
    }

    /// A broad threat map has no endpoint, so pair its attack squares with the
    /// live board. In both modes, empty path squares never receive a marker.
    private static func marksThreatenedPiece(
        _ corridor: ThreatCorridor,
        at square: Square,
        on game: ChessGame
    ) -> Bool {
        guard game.piece(at: square)?.player == corridor.piece.player.opponent else {
            return false
        }

        return corridor.endpoint == square || (
            corridor.endpoint == nil && corridor.threatenedSquares.contains(square)
        )
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

    /// Shared by the board and the close-up gallery, guaranteeing the player
    /// inspects the exact model they will later use in a game.
    static func makePiece(_ piece: Piece, palette: PiecePalette) -> Entity {
        ChessPieceMeshes.make(piece, palette: palette)
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

    /// A thick shaft with a cone head, laid flat on the board and pointing
    /// from the selected piece to one of its destinations. Built along +Z and
    /// then yawed, which keeps the geometry readable.
    private static func makeMoveArrow(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>,
        color: UIColor
    ) -> Entity {
        let root = Entity()

        let delta = destination - origin
        let span = (delta.x * delta.x + delta.z * delta.z).squareRoot()
        guard span > 0.01 else { return root }

        // Clear of the piece it starts under, and stopping on the target.
        let tailGap: Float = 0.34
        let headLength: Float = 0.36
        let shaftLength = max(0.06, span - tailGap - headLength)

        let material = color.withAlphaComponent(0.92)

        let shaft = model(
            .generateBox(size: [0.17, 0.055, shaftLength], cornerRadius: 0.025),
            color: material,
            metallic: true,
            roughness: 0.2
        )
        shaft.position = [0, 0, tailGap + shaftLength / 2]
        root.addChild(shaft)

        let head = model(
            .generateCone(height: headLength, radius: 0.24),
            color: material,
            metallic: true,
            roughness: 0.2
        )
        // The cone is built pointing up; tip it to lie along +Z.
        head.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        head.position = [0, 0, tailGap + shaftLength + headLength / 2]
        root.addChild(head)

        root.orientation = simd_quatf(angle: atan2(delta.x, delta.z), axis: [0, 1, 0])
        root.position = origin + [0, tileHeight / 2 + 0.06, 0]
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
