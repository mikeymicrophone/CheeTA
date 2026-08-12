# CheeTA

A basic native iPad chess app built with SwiftUI. It supports local two-player play, legal move validation, captures, check, checkmate, stalemate, restarting a match, and persistent threat corridors.

Threat corridors are a passive tactical overlay: every piece continuously projects its attacks and the map updates automatically whenever the board changes. The default Enemy Contact view shows only directional paths whose endpoint is an opposing piece; unrelated directions from the same piece remain hidden. All Threats reveals every projection. A square's border grows thicker as more visible corridors threaten it, and threats from both teams appear as striped borders. The engine representation is separate from the placeholder colors so visual skins can replace the presentation later.

The Opening, Midgame, and Endgame buttons load curated, playable positions for quick scenario exploration. Loading a scenario clears transient move highlights and immediately rebuilds the passive threat map.

This first version intentionally omits castling, en passant, and promotion.

## Install on an iPad

1. Open `CheeTA.xcodeproj` in Xcode.
2. Select the **CheeTA** target, then choose your Apple Development team under **Signing & Capabilities**.
3. Connect your iPad, choose it as the run destination, and press **Run**.

The app has no third-party dependencies.
