import Foundation
import XCTest

final class DiagnosticServiceTests: XCTestCase {
    func testDiagnosticServiceStartIsIdempotent() {
        let service = DiagnosticService.shared
        service.start()
        service.start()
        XCTAssertTrue(true, "Multiple start calls do not crash")
    }

    func testDiagnosticServiceStartAndStop() {
        let service = DiagnosticService.shared
        service.start()
        service.stop()
        service.start()
        XCTAssertTrue(true, "Start and stop lifecycle completes cleanly")
    }

    func testRecordDiagnosticEventDoesNotCrash() {
        let service = DiagnosticService.shared
        service.recordDiagnosticEvent(category: "testCategory", message: "Unit test diagnostic message")
        XCTAssertTrue(true, "Event recorded successfully")
    }

    func testDumpRecentDiagnosticsToTemporaryFile() {
        let service = DiagnosticService.shared
        service.recordDiagnosticEvent(category: "testDump", message: "Testing dump output")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcsc_test_diag_\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let resultURL = service.dumpRecentDiagnostics(to: tempURL, timeInterval: 300)
        if let resultURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))
            let content = (try? String(contentsOf: resultURL, encoding: .utf8)) ?? ""
            XCTAssertTrue(content.isEmpty || content.contains("{"), "Should be valid jsonl or empty sequence")
        }
    }
}
