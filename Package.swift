// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CheeTAChessEngine",
    platforms: [
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
                "ContentView.swift"
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
