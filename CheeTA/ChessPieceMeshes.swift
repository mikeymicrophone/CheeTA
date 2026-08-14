import RealityKit
import UIKit
import simd

/// Turned Staunton silhouettes, shared by the board and the gallery.
///
/// Pawn, bishop, rook, queen, and king are surfaces of revolution so the
/// family shares one foot vocabulary. The knight sits on that same plinth
/// with a carved horse lofted from a side silhouette.
@MainActor
enum ChessPieceMeshes {
    static func make(_ piece: Piece, palette: PiecePalette) -> Entity {
        let root = Entity()
        let colors = palette.colors(for: piece.player)

        switch piece.kind {
        case .pawn:
            assemblePawn(body: colors.piece, accent: colors.accent, onto: root)
        case .rook:
            assembleRook(body: colors.piece, accent: colors.accent, onto: root)
        case .knight:
            assembleKnight(body: colors.piece, accent: colors.accent, onto: root)
        case .bishop:
            assembleBishop(body: colors.piece, accent: colors.accent, onto: root)
        case .queen:
            assembleQueen(body: colors.piece, accent: colors.accent, onto: root)
        case .king:
            assembleKing(body: colors.piece, accent: colors.accent, onto: root)
        }

        if piece.player == .black {
            root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        }
        return root
    }

    // MARK: - Assembly

    private static func assemblePawn(body: UIColor, accent: UIColor, onto root: Entity) {
        add(cached("pawn-body", pawnProfile), color: body, to: root)
        add(cached("pawn-collar") { ring(radius: 0.146, tube: 0.017) }, y: 0.528, color: accent, to: root)
    }

    private static func assembleRook(body: UIColor, accent: UIColor, onto root: Entity) {
        add(cached("rook-body", rookProfile), color: body, to: root)
        add(cached("rook-cornice") { ring(radius: 0.258, tube: 0.016) }, y: 0.748, color: accent, to: root)
        add(
            .generateCylinder(height: 0.05, radius: 0.148),
            y: 0.792,
            color: recessed(body),
            to: root
        )

        for index in 0..<4 {
            let angle = Float(index) * (.pi / 2)
            add(
                .generateBox(size: [0.118, 0.148, 0.072], cornerRadius: 0.012),
                position: [cos(angle) * 0.210, 0.890, sin(angle) * 0.210],
                color: body,
                to: root
            )
        }
    }

    private static func assembleKnight(body: UIColor, accent: UIColor, onto root: Entity) {
        add(cached("knight-plinth", knightPlinthProfile), color: body, to: root)
        add(cached("knight-plinth-ring") { ring(radius: 0.182, tube: 0.014) }, y: 0.248, color: accent, to: root)
        add(cached("knight-figure", knightFigureMesh), color: body, to: root)

        let mane = ModelEntity(
            mesh: cached("knight-mane", knightManeMesh),
            materials: [pieceMaterial(color: accent)]
        )
        root.addChild(mane)

        for x in [Float(-0.055), 0.055] {
            let ear = ModelEntity(
                mesh: .generateCone(height: 0.11, radius: 0.028),
                materials: [pieceMaterial(color: body)]
            )
            ear.position = [x, 1.155, 0.055]
            ear.orientation = simd_quatf(angle: 0.42, axis: [1, 0, 0])
                * simd_quatf(angle: x > 0 ? 0.18 : -0.18, axis: [0, 0, 1])
            root.addChild(ear)
        }

        for x in [Float(-0.092), 0.092] {
            add(
                .generateSphere(radius: 0.018),
                position: [x, 0.955, -0.175],
                color: recessed(body),
                to: root
            )
        }
    }

    private static func assembleBishop(body: UIColor, accent: UIColor, onto root: Entity) {
        add(cached("bishop-body", bishopBodyProfile), color: body, to: root)
        add(cached("bishop-collar") { ring(radius: 0.136, tube: 0.016) }, y: 0.608, color: accent, to: root)
        add(cached("bishop-mitre", bishopMitreProfile), color: body, to: root)

        // Sit the cut on the mitre surface facing +Z so the default camera
        // reads the bishop's traditional cleft instead of a plain egg.
        let cleft = ModelEntity(
            mesh: .generateBox(size: [0.078, 0.38, 0.05], cornerRadius: 0.014),
            materials: [pieceMaterial(color: recessed(accent))]
        )
        cleft.position = [0, 0.93, 0.142]
        cleft.orientation = simd_quatf(angle: 0.16, axis: [1, 0, 0])
        root.addChild(cleft)
    }

    private static func assembleQueen(body: UIColor, accent: UIColor, onto root: Entity) {
        add(cached("queen-body", queenProfile), color: body, to: root)
        add(cached("queen-collar") { ring(radius: 0.150, tube: 0.016) }, y: 0.878, color: accent, to: root)
        add(cached("queen-rim") { ring(radius: 0.196, tube: 0.014) }, y: 1.040, color: accent, to: root)
        add(.generateSphere(radius: 0.068), y: 1.088, color: accent, to: root)

        for index in 0..<8 {
            let angle = Float(index) * (.pi / 4)
            let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
            let spike = ModelEntity(
                mesh: .generateCone(height: 0.148, radius: 0.026),
                materials: [pieceMaterial(color: body)]
            )
            spike.position = radial * 0.172 + [0, 1.078, 0]
            spike.orientation = simd_quatf(angle: 0.14, axis: SIMD3(-radial.z, 0, radial.x))
            let pearl = ModelEntity(
                mesh: .generateSphere(radius: 0.022),
                materials: [pieceMaterial(color: accent)]
            )
            pearl.position.y = 0.088
            spike.addChild(pearl)
            root.addChild(spike)
        }
    }

    private static func assembleKing(body: UIColor, accent: UIColor, onto root: Entity) {
        add(cached("king-body", kingProfile), color: body, to: root)
        add(cached("king-collar") { ring(radius: 0.152, tube: 0.016) }, y: 0.762, color: accent, to: root)
        add(cached("king-circlet") { ring(radius: 0.162, tube: 0.015) }, y: 1.068, color: accent, to: root)
        add(.generateSphere(radius: 0.068), y: 1.145, color: accent, to: root)
        add(
            .generateBox(size: [0.068, 0.32, 0.056], cornerRadius: 0.016),
            y: 1.318,
            color: body,
            to: root
        )
        add(
            .generateBox(size: [0.228, 0.066, 0.056], cornerRadius: 0.016),
            y: 1.348,
            color: body,
            to: root
        )
    }

    // MARK: - Profiles

    /// Shared lotus foot: chamfered pad, cove, torus, and a second ring.
    private static func stauntonFoot(radius: Float, height: Float) -> [ProfilePoint] {
        let r = radius
        let h = height
        return [
            ProfilePoint(r * 0.96, 0.000, crease: true),
            ProfilePoint(r * 1.00, h * 0.08),
            ProfilePoint(r * 0.97, h * 0.20),
            ProfilePoint(r * 0.80, h * 0.30),
            ProfilePoint(r * 0.60, h * 0.40),
            ProfilePoint(r * 0.67, h * 0.48),
            ProfilePoint(r * 0.78, h * 0.56),
            ProfilePoint(r * 0.73, h * 0.64, crease: true),
            ProfilePoint(r * 0.54, h * 0.73),
            ProfilePoint(r * 0.62, h * 0.83),
            ProfilePoint(r * 0.50, h * 0.91),
            ProfilePoint(r * 0.45, h * 1.00)
        ]
    }

    private static var pawnProfile: [ProfilePoint] {
        join(
            stauntonFoot(radius: 0.312, height: 0.175),
            [
                ProfilePoint(0.126, 0.198),
                ProfilePoint(0.106, 0.285),
                ProfilePoint(0.096, 0.400),
                ProfilePoint(0.102, 0.488),
                ProfilePoint(0.144, 0.522),
                ProfilePoint(0.138, 0.542),
                ProfilePoint(0.108, 0.562)
            ],
            ellipseArc(
                centerY: 0.690,
                radiusX: 0.150,
                radiusY: 0.150,
                fromDegrees: -50,
                toDegrees: 90,
                samples: 12
            )
        )
    }

    private static var rookProfile: [ProfilePoint] {
        join(
            stauntonFoot(radius: 0.336, height: 0.180),
            [
                ProfilePoint(0.198, 0.205),
                ProfilePoint(0.188, 0.360),
                ProfilePoint(0.180, 0.540),
                ProfilePoint(0.184, 0.650),
                ProfilePoint(0.214, 0.698),
                ProfilePoint(0.250, 0.738),
                ProfilePoint(0.262, 0.762),
                ProfilePoint(0.258, 0.798),
                ProfilePoint(0.250, 0.818, crease: true)
            ]
        )
    }

    private static var knightPlinthProfile: [ProfilePoint] {
        join(
            stauntonFoot(radius: 0.318, height: 0.175),
            [
                ProfilePoint(0.172, 0.198),
                ProfilePoint(0.166, 0.228),
                ProfilePoint(0.184, 0.248),
                ProfilePoint(0.176, 0.262, crease: true)
            ]
        )
    }

    private static var bishopBodyProfile: [ProfilePoint] {
        join(
            stauntonFoot(radius: 0.298, height: 0.185),
            [
                ProfilePoint(0.106, 0.210),
                ProfilePoint(0.088, 0.345),
                ProfilePoint(0.080, 0.490),
                ProfilePoint(0.086, 0.565),
                ProfilePoint(0.134, 0.602),
                ProfilePoint(0.128, 0.624),
                ProfilePoint(0.096, 0.646)
            ]
        )
    }

    private static var bishopMitreProfile: [ProfilePoint] {
        join(
            [ProfilePoint(0.094, 0.642)],
            ellipseArc(
                centerY: 0.880,
                radiusX: 0.138,
                radiusY: 0.252,
                fromDegrees: -62,
                toDegrees: 80,
                samples: 14
            ),
            [
                ProfilePoint(0.028, 1.130),
                ProfilePoint(0.024, 1.148)
            ],
            ellipseArc(
                centerY: 1.188,
                radiusX: 0.038,
                radiusY: 0.038,
                fromDegrees: -70,
                toDegrees: 90,
                samples: 8
            )
        )
    }

    private static var queenProfile: [ProfilePoint] {
        join(
            stauntonFoot(radius: 0.322, height: 0.195),
            [
                ProfilePoint(0.116, 0.220),
                ProfilePoint(0.096, 0.350),
                ProfilePoint(0.088, 0.510),
                ProfilePoint(0.092, 0.645),
                ProfilePoint(0.130, 0.692),
                ProfilePoint(0.118, 0.718),
                ProfilePoint(0.094, 0.755),
                ProfilePoint(0.098, 0.828),
                ProfilePoint(0.146, 0.868),
                ProfilePoint(0.154, 0.894),
                ProfilePoint(0.136, 0.920),
                ProfilePoint(0.162, 0.958),
                ProfilePoint(0.188, 0.998),
                ProfilePoint(0.198, 1.026),
                ProfilePoint(0.190, 1.048, crease: true)
            ]
        )
    }

    private static var kingProfile: [ProfilePoint] {
        join(
            stauntonFoot(radius: 0.330, height: 0.200),
            [
                ProfilePoint(0.124, 0.226),
                ProfilePoint(0.104, 0.365),
                ProfilePoint(0.096, 0.545),
                ProfilePoint(0.100, 0.705),
                ProfilePoint(0.140, 0.752),
                ProfilePoint(0.128, 0.778),
                ProfilePoint(0.106, 0.825),
                ProfilePoint(0.110, 0.928),
                ProfilePoint(0.156, 0.974),
                ProfilePoint(0.168, 1.004),
                ProfilePoint(0.160, 1.038),
                ProfilePoint(0.146, 1.058),
                ProfilePoint(0.156, 1.080),
                ProfilePoint(0.140, 1.098, crease: true)
            ]
        )
    }

    // MARK: - Knight sculpture

    /// Side-view contour of a Staunton horse, facing −Z. Coordinates are (z, y).
    private static var knightOutline: [SIMD2<Float>] {
        [
            [0.185, 0.258],
            [0.228, 0.345],
            [0.210, 0.470],
            [0.168, 0.575],
            [0.205, 0.638],
            [0.155, 0.700],
            [0.212, 0.768],
            [0.158, 0.838],
            [0.198, 0.915],
            [0.118, 0.992],
            [0.088, 1.075],
            [0.102, 1.168],
            [0.018, 1.112],
            [-0.042, 1.048],
            [-0.118, 1.012],
            [-0.198, 0.968],
            [-0.292, 0.918],
            [-0.372, 0.868],
            [-0.428, 0.822],
            [-0.412, 0.778],
            [-0.348, 0.762],
            [-0.318, 0.778],
            [-0.268, 0.748],
            [-0.175, 0.718],
            [-0.088, 0.655],
            [-0.018, 0.548],
            [0.028, 0.412],
            [0.072, 0.308],
            [0.118, 0.258]
        ]
    }

    private static func knightWidth(at point: SIMD2<Float>) -> Float {
        let z = point.x
        let y = point.y
        if y > 1.10 { return 0.038 }
        if z < -0.34 { return 0.058 }
        if z < -0.12 && y > 0.82 { return 0.118 }
        if y > 0.62 { return 0.092 }
        return 0.148
    }

    private static func knightFigureMesh() -> MeshResource {
        roundedExtrusion(
            outline: knightOutline,
            widthAt: knightWidth,
            layers: 9,
            name: "knight-figure"
        )
    }

    private static func knightManeMesh() -> MeshResource {
        let outline: [SIMD2<Float>] = [
            [0.148, 0.590],
            [0.188, 0.655],
            [0.142, 0.718],
            [0.192, 0.790],
            [0.146, 0.858],
            [0.178, 0.938],
            [0.108, 1.005],
            [0.092, 0.948],
            [0.128, 0.868],
            [0.096, 0.792],
            [0.132, 0.718],
            [0.102, 0.642]
        ]
        return roundedExtrusion(
            outline: outline,
            widthAt: { _ in 0.055 },
            layers: 7,
            name: "knight-mane"
        )
    }

    // MARK: - Mesh cache

    private static var cache: [String: MeshResource] = [:]

    private static func cached(_ key: String, _ profile: [ProfilePoint]) -> MeshResource {
        cached(key) { lathe(profile, name: key) }
    }

    private static func cached(_ key: String, _ build: () -> MeshResource) -> MeshResource {
        if let mesh = cache[key] { return mesh }
        let mesh = build()
        cache[key] = mesh
        return mesh
    }

    // MARK: - Lathe

    private struct ProfilePoint {
        var radius: Float
        var y: Float
        var crease: Bool

        init(_ radius: Float, _ y: Float, crease: Bool = false) {
            self.radius = max(0, radius)
            self.y = y
            self.crease = crease
        }
    }

    private static func lathe(
        _ points: [ProfilePoint],
        segments: Int = 36,
        name: String
    ) -> MeshResource {
        let profile = densify(points)
        guard profile.count >= 2 else {
            return .generateCylinder(height: 0.8, radius: 0.2)
        }

        var rings: [[SIMD3<Float>]] = []
        for (index, point) in profile.enumerated() {
            let copies = point.crease && index > 0 && index < profile.count - 1 ? 2 : 1
            for _ in 0..<copies {
                var ring: [SIMD3<Float>] = []
                ring.reserveCapacity(segments)
                for segment in 0..<segments {
                    let theta = Float(segment) / Float(segments) * (.pi * 2)
                    ring.append([point.radius * cos(theta), point.y, point.radius * sin(theta)])
                }
                rings.append(ring)
            }
        }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(rings.count * segments)
        for ring in rings { positions.append(contentsOf: ring) }

        var indices: [UInt32] = []
        for ring in 0..<(rings.count - 1) {
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                let a = UInt32(ring * segments + segment)
                let b = UInt32(ring * segments + next)
                let c = UInt32((ring + 1) * segments + segment)
                let d = UInt32((ring + 1) * segments + next)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        capLathe(
            positions: &positions,
            indices: &indices,
            ringStart: 0,
            ringCount: segments,
            y: profile.first?.y ?? 0,
            downward: true
        )
        if let last = profile.last, last.radius > 0.001 {
            capLathe(
                positions: &positions,
                indices: &indices,
                ringStart: (rings.count - 1) * segments,
                ringCount: segments,
                y: last.y,
                downward: false
            )
        }

        return buildMesh(positions: positions, indices: indices, name: name)
    }

    private static func capLathe(
        positions: inout [SIMD3<Float>],
        indices: inout [UInt32],
        ringStart: Int,
        ringCount: Int,
        y: Float,
        downward: Bool
    ) {
        let centerIndex = UInt32(positions.count)
        positions.append([0, y, 0])
        for segment in 0..<ringCount {
            let a = UInt32(ringStart + segment)
            let b = UInt32(ringStart + (segment + 1) % ringCount)
            if downward {
                indices.append(contentsOf: [centerIndex, b, a])
            } else {
                indices.append(contentsOf: [centerIndex, a, b])
            }
        }
    }

    private static func ring(radius: Float, tube: Float) -> MeshResource {
        lathe(
            [
                ProfilePoint(radius - tube, -tube * 0.55),
                ProfilePoint(radius - tube * 0.25, -tube),
                ProfilePoint(radius + tube * 0.18, -tube * 0.35),
                ProfilePoint(radius + tube * 0.18, tube * 0.35),
                ProfilePoint(radius - tube * 0.25, tube),
                ProfilePoint(radius - tube, tube * 0.55)
            ],
            name: "ring-\(radius)"
        )
    }

    // MARK: - Rounded extrusion

    private static func roundedExtrusion(
        outline: [SIMD2<Float>],
        widthAt: (SIMD2<Float>) -> Float,
        layers: Int,
        name: String
    ) -> MeshResource {
        let loop = closedLoop(outline)
        let count = loop.count
        guard count >= 3, layers >= 3 else {
            return .generateBox(size: [0.3, 0.5, 0.4])
        }

        let inward = inwardNormals(loop)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(layers * count)

        for layer in 0..<layers {
            let t = Float(layer) / Float(layers - 1) * 2 - 1
            let round = sqrt(max(0, 1 - t * t))
            for index in 0..<count {
                let point = loop[index]
                let width = widthAt(point)
                let inset = (1 - round) * min(0.085, width * 0.45)
                let y = point.y + inward[index].y * inset
                let z = point.x + inward[index].x * inset
                positions.append([t * width * (0.72 + 0.28 * round), y, z])
            }
        }

        var indices: [UInt32] = []
        for layer in 0..<(layers - 1) {
            for index in 0..<count {
                let next = (index + 1) % count
                let a = UInt32(layer * count + index)
                let b = UInt32(layer * count + next)
                let c = UInt32((layer + 1) * count + index)
                let d = UInt32((layer + 1) * count + next)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        capExtrusion(positions: &positions, indices: &indices, start: 0, count: count, outward: [-1, 0, 0])
        capExtrusion(
            positions: &positions,
            indices: &indices,
            start: (layers - 1) * count,
            count: count,
            outward: [1, 0, 0]
        )

        return buildMesh(positions: positions, indices: indices, name: name)
    }

    private static func capExtrusion(
        positions: inout [SIMD3<Float>],
        indices: inout [UInt32],
        start: Int,
        count: Int,
        outward: SIMD3<Float>
    ) {
        var centroid = SIMD3<Float>.zero
        for index in 0..<count {
            centroid += positions[start + index]
        }
        centroid /= Float(count)
        let center = UInt32(positions.count)
        positions.append(centroid)

        for index in 0..<count {
            let a = UInt32(start + index)
            let b = UInt32(start + (index + 1) % count)
            let edge1 = positions[Int(a)] - centroid
            let edge2 = positions[Int(b)] - centroid
            let normal = simd_cross(edge1, edge2)
            if simd_dot(normal, outward) >= 0 {
                indices.append(contentsOf: [center, a, b])
            } else {
                indices.append(contentsOf: [center, b, a])
            }
        }
    }

    private static func closedLoop(_ outline: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard let first = outline.first, let last = outline.last else { return outline }
        if simd_length(first - last) < 0.001 {
            return Array(outline.dropLast())
        }
        return outline
    }

    private static func inwardNormals(_ loop: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let count = loop.count
        return (0..<count).map { index in
            let previous = loop[(index + count - 1) % count]
            let next = loop[(index + 1) % count]
            let tangent = next - previous
            // CCW outline in (z, y): inward is (−ty, tz) after swapping to (z, y).
            var normal = SIMD2<Float>(-tangent.y, tangent.x)
            let length = simd_length(normal)
            if length > 1e-6 { normal /= length }
            return normal
        }
    }

    // MARK: - Mesh build

    private static func buildMesh(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        name: String
    ) -> MeshResource {
        var indices = indices
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)

        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let i0 = Int(indices[triangle])
            let i1 = Int(indices[triangle + 1])
            let i2 = Int(indices[triangle + 2])
            let face = simd_cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            normals[i0] += face
            normals[i1] += face
            normals[i2] += face
        }

        if let maxX = positions.indices.max(by: { positions[$0].x < positions[$1].x }),
           simd_dot(normals[maxX], [1, 0, 0]) < 0 {
            for triangle in stride(from: 0, to: indices.count, by: 3) {
                indices.swapAt(triangle + 1, triangle + 2)
            }
            for index in normals.indices {
                normals[index] = -normals[index]
            }
        }

        for index in normals.indices {
            let length = simd_length(normals[index])
            normals[index] = length > 1e-8 ? normals[index] / length : [0, 1, 0]
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return .generateCylinder(height: 0.8, radius: 0.2)
        }
    }

    // MARK: - Profile helpers

    private static func join(_ parts: [ProfilePoint]...) -> [ProfilePoint] {
        var result: [ProfilePoint] = []
        for part in parts {
            guard let first = part.first else { continue }
            if let last = result.last,
               abs(last.radius - first.radius) < 0.0015,
               abs(last.y - first.y) < 0.0015 {
                result.append(contentsOf: part.dropFirst())
            } else {
                result.append(contentsOf: part)
            }
        }
        return result
    }

    private static func ellipseArc(
        centerY: Float,
        radiusX: Float,
        radiusY: Float,
        fromDegrees: Float,
        toDegrees: Float,
        samples: Int
    ) -> [ProfilePoint] {
        (0...samples).map { index in
            let t = Float(index) / Float(samples)
            let degrees = fromDegrees + (toDegrees - fromDegrees) * t
            let angle = degrees * .pi / 180
            return ProfilePoint(radiusX * max(0, cos(angle)), centerY + radiusY * sin(angle))
        }
    }

    private static func densify(_ points: [ProfilePoint], subdivisions: Int = 5) -> [ProfilePoint] {
        guard points.count >= 2, subdivisions > 1 else { return points }
        var result: [ProfilePoint] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]
            result.append(p1)
            let sharp = p1.crease || p2.crease
            for step in 1..<subdivisions {
                let t = Float(step) / Float(subdivisions)
                if sharp {
                    result.append(
                        ProfilePoint(
                            p1.radius + (p2.radius - p1.radius) * t,
                            p1.y + (p2.y - p1.y) * t
                        )
                    )
                } else {
                    result.append(
                        ProfilePoint(
                            catmull(p0.radius, p1.radius, p2.radius, p3.radius, t),
                            catmull(p0.y, p1.y, p2.y, p3.y, t)
                        )
                    )
                }
            }
        }
        if let last = points.last {
            result.append(last)
        }
        return result
    }

    private static func catmull(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ t: Float) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            2 * p1
            + (-p0 + p2) * t
            + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
            + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }

    // MARK: - Entities / materials

    private static func add(
        _ mesh: MeshResource,
        y: Float = 0,
        color: UIColor,
        to root: Entity
    ) {
        add(mesh, position: [0, y, 0], color: color, to: root)
    }

    private static func add(
        _ mesh: MeshResource,
        position: SIMD3<Float>,
        color: UIColor,
        to root: Entity
    ) {
        let entity = ModelEntity(mesh: mesh, materials: [pieceMaterial(color: color)])
        entity.position = position
        root.addChild(entity)
    }

    private static func pieceMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = 0.22
        material.roughness = 0.44
        material.clearcoat = 0.5
        material.clearcoatRoughness = 0.36
        material.specular = 0.56
        return material
    }

    private static func recessed(_ color: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: red * 0.42, green: green * 0.42, blue: blue * 0.42, alpha: alpha)
    }
}
