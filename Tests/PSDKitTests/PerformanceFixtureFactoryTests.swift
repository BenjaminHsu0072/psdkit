import XCTest
@testable import PSDKit
import PSDKitPerformanceFixtures

final class PerformanceFixtureFactoryTests: XCTestCase {
    func testSmokeFixtureGeneratesAndRoundTrips() throws {
        let config = PerformanceFixtureConfig.config(for: .smoke)
        let doc = try PerformanceFixtureFactory.makeDocument(config: config)

        XCTAssertEqual(doc.canvasSize.width, 64)
        XCTAssertEqual(doc.canvasSize.height, 64)
        XCTAssertTrue(hasNestedGroups(in: doc.root))

        let saved = try doc.data(writeMode: .semantic)
        XCTAssertGreaterThan(saved.count, 0)

        let loaded = try PSDDocument.load(data: saved)
        XCTAssertEqual(loaded.canvasSize, doc.canvasSize)

        let composite = loaded.compositePreviewRGBA()
        XCTAssertEqual(composite.count, 64 * 64 * 4)
    }

    func testBenchmarkMetadataCapturesSwiftAndHardware() {
        let swiftVersion = PerformanceBenchmarkMetadata.swiftToolchainVersion()
        XCTAssertTrue(swiftVersion.localizedCaseInsensitiveContains("swift"))

        let hardware = PerformanceBenchmarkMetadata.hardwareSummary()
        XCTAssertFalse(hardware.isEmpty)

        XCTAssertGreaterThan(PerformanceBenchmarkMetadata.physicalMemoryBytes(), 0)
    }

    func testPresetConfigsMatchMidtermTargets() {
        let small = PerformanceFixtureConfig.config(for: .small)
        XCTAssertEqual(small.canvasWidth, 1024)
        XCTAssertEqual(small.pixelLayerCount, 20)

        let medium = PerformanceFixtureConfig.config(for: .medium)
        XCTAssertEqual(medium.canvasWidth, 2048)
        XCTAssertEqual(medium.pixelLayerCount, 50)

        let stress = PerformanceFixtureConfig.config(for: .stress)
        XCTAssertEqual(stress.canvasWidth, 4096)
        XCTAssertEqual(stress.pixelLayerCount, 100)
    }

    private func hasNestedGroups(in root: GroupLayer) -> Bool {
        for child in root.children {
            guard let outer = child as? GroupLayer else { continue }
            for nested in outer.children {
                if nested is GroupLayer {
                    return true
                }
            }
        }
        return false
    }
}
