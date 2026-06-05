import PSDKit
import XCTest
@testable import PSDViewer

final class BlendModeDisplayNameTests: XCTestCase {
    func testKnownBlendModes() {
        XCTAssertEqual(BlendModeDisplayName.text(for: .normal), "Normal")
        XCTAssertEqual(BlendModeDisplayName.text(for: .multiply), "Multiply")
        XCTAssertEqual(BlendModeDisplayName.text(for: .add), "Linear Dodge (Add)")
        XCTAssertEqual(BlendModeDisplayName.text(for: .passThrough), "Pass Through")
    }

    func testUnknownBlendMode() {
        XCTAssertEqual(BlendModeDisplayName.text(for: .unknown), "Unknown")
        XCTAssertEqual(BlendModeDisplayName.text(for: BlendMode(fourCC: "diss")), "Unknown")
    }
}
