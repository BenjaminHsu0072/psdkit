import Foundation
@testable import PSDKit

/// Standard midterm round-trip fixture built entirely in PSDKit (no external PSD).
enum MidtermStandardDocument {
    static let canvasSize = PSDSize(width: 16, height: 16)

    /// ```
    /// Canvas 16×16
    /// ├── BG normal, opaque
    /// ├── Group A
    /// │   ├── Red multiply, opacity 200
    /// │   └── Group B
    /// │       └── Glow add, alpha gradient
    /// └── Top normal, hidden
    /// ```
    static func make() throws -> PSDDocument {
        try PSDDocument.makeMidtermStandardDocument(canvasSize: canvasSize)
    }
}
