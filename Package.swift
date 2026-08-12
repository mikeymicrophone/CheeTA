// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CheeTAChessEngine",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CheeTA", targets: ["CheeTA"])
    ],
    targets: [
        .target(
            name: "CheeTA",
            path: "CheeTA",
            exclude: [
                "Assets.xcassets",
                "CheeTAApp.swift",
                "CheckCutSceneView.swift",
                "ContentView.swift",
                "CutSceneReel.swift",
                "CutSceneStyle.swift",
                "FirstCaptureCutSceneView.swift",
                "QueenDownCutSceneView.swift",
                "RealityChessBoardView.swift",
                "ReplayControls.swift"
            ],
            sources: [
                "ChessTypes.swift",
                "ChessGame.swift"
            ]
        ),
        .testTarget(
            name: "CheeTATests",
            dependencies: ["CheeTA"],
            path: "CheeTATests"
        )
    ]
)
