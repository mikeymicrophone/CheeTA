# CheeTA

A basic native iPad chess app built with SwiftUI and RealityKit. It supports local two-player play, legal move validation, captures, check, checkmate, stalemate, restarting a match, and persistent threat corridors.

CheeTA requires iPadOS 18 or newer. The default board is a touch-driven 3D `RealityView` with procedural pieces, tap-to-move play, draggable rotation, and 3D threat markers. A segmented control keeps the classic 2D board available. The procedural renderer is isolated from chess behavior so custom USDZ piece models and board materials can replace it later.

Threat corridors are a passive tactical overlay: every piece continuously projects its attacks and the map updates automatically whenever the board changes. The default Enemy Contact view shows only directional paths whose endpoint is an opposing piece; unrelated directions from the same piece remain hidden. All Threats reveals every projection. A square's border grows thicker as more visible corridors threaten it, and threats from both teams appear as striped borders. The engine representation is separate from the placeholder colors so visual skins can replace the presentation later.

On every turn, each piece belonging to the current player with at least one legal move receives a pulsing candidate marker. The Candidates panel can enter a dedicated picking mode where tapping movable pieces builds a smaller candidate set; ordinary move-selection taps never narrow the automatic set. Pulse All restores every movable piece. Candidate choices reset after a move, restart, or position change.

Entering check or checkmate now interrupts play with a deliberately lo-fi arcade cut scene. It identifies the threatened king, gives warning haptic feedback, dismisses itself after a short beat, and can be skipped immediately with a tap. The scene is isolated from the rules and board renderers so its art direction can evolve independently.

The Opening, Midgame, and Endgame buttons load curated, playable positions for quick scenario exploration. Loading a scenario clears transient move highlights and immediately rebuilds the passive threat map.

This first version intentionally omits castling, en passant, and promotion.

## Install on an iPad

1. Open `CheeTA.xcodeproj` in Xcode.
2. Select the **CheeTA** target, then choose your Apple Development team under **Signing & Capabilities**.
3. Connect your iPad, choose it as the run destination, and press **Run**.

The app has no third-party dependencies.
