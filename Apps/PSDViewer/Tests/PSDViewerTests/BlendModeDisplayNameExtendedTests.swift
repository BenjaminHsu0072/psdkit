import PSDKit
import XCTest
@testable import PSDViewer

final class BlendModeDisplayNameExtendedTests: XCTestCase {
    func testPassThroughAndUnknownStayStable() {
        XCTAssertEqual(BlendModeDisplayName.text(for: .passThrough), "Pass Through")
        XCTAssertEqual(BlendModeDisplayName.text(for: .unknown), "Unknown")
    }
}
