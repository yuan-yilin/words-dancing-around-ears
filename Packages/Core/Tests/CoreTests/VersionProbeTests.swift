import XCTest
@testable import Core

final class VersionProbeTests: XCTestCase {
    func testSherpaOnnxVersionIsNonEmpty() {
        XCTAssertFalse(SherpaOnnxInfo.version.isEmpty)
        XCTAssertFalse(SherpaOnnxInfo.onnxruntimeVersion.isEmpty)
    }
}
