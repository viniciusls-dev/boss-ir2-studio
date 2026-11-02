import XCTest
@testable import IR2Studio

final class IR2BackupTests: XCTestCase {
    // Values transcribed from the five differential backups. IR blobs are omitted:
    // this reader intentionally validates only the mapped settings, not restore safety.
    private func fixture(channel: String = "00", green: String = "00", red: String = "77") -> [String: Any] {
        [
            "device": "IR-2", "formatRev": "0000",
            "system": ["SETUP%COM": [channel], "SYSTEM%COM": ["00"]],
            "userPatch": [
                ["PATCH%COM": ["40", "60", "49", "5C", green, "42", "00"]],
                ["PATCH%COM": ["00", "67", "29", "4F", red, "65", "02"]]
            ]
        ]
    }

    private func read(_ object: [String: Any]) throws -> IR2Backup {
        try IR2Backup(data: JSONSerialization.data(withJSONObject: object))
    }

    private func assertRejected(_ object: [String: Any], as expected: IR2Backup.ReadError,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try read(object), file: file, line: line) { error in
            XCTAssertEqual(error as? IR2Backup.ReadError, expected, file: file, line: line)
        }
    }

    func testKnownBackupSequencePreservesIndependentGains() throws {
        let first = try read(fixture(green: "40", red: "28"))
        let second = try read(fixture(channel: "01", green: "40"))
        let third = try read(fixture())
        let fourth = try read(fixture(channel: "01"))
        let fifth = try read(fixture())
        XCTAssertEqual(first.selectedChannel, .green)
        XCTAssertEqual(first.greenGain, 64)
        XCTAssertEqual(first.redGain, 40)
        XCTAssertEqual(second.selectedChannel, .red)
        XCTAssertEqual(second.greenGain, first.greenGain)
        XCTAssertEqual(second.redGain, 119)
        XCTAssertEqual(third.greenGain, 0)
        XCTAssertEqual(third.redGain, second.redGain)
        XCTAssertEqual(fourth.selectedChannel, .red)
        XCTAssertEqual(fourth.greenParameters, third.greenParameters)
        XCTAssertEqual(fourth.redParameters, third.redParameters)
        XCTAssertEqual(fifth, third)
    }

    func testReadsHexAsHexWithoutAssumingPercentageScale() throws {
        let backup = try read(fixture(green: "7f", red: "FF"))
        XCTAssertEqual(backup.greenGain, 127)
        XCTAssertEqual(backup.redGain, 255)
    }

    func testRejectsOtherDeviceAndUnknownRevision() {
        var object = fixture()
        object["device"] = "IR-200"
        assertRejected(object, as: .unsupportedDevice)
        object = fixture()
        object["formatRev"] = "0001"
        assertRejected(object, as: .unsupportedRevision)
    }

    func testRejectsUnknownOrMissingChannel() {
        assertRejected(fixture(channel: "02"), as: .invalidField("SETUP%COM"))
        var object = fixture()
        object["system"] = ["SYSTEM%COM": ["00"]]
        assertRejected(object, as: .invalidField("SETUP%COM"))
    }

    func testRejectsInvalidHexByteRepresentations() {
        for invalid in ["", "0", "000", "GG", "-1", "+1", " 1", "１", "💚"] {
            assertRejected(fixture(green: invalid), as: .invalidField("PATCH%COM"))
            assertRejected(fixture(channel: invalid), as: .invalidField("SETUP%COM"))
        }
    }

    func testRejectsMissingOrTruncatedPatches() {
        var object = fixture()
        object["userPatch"] = [["PATCH%COM": ["00"]], ["PATCH%COM": ["00"]]]
        assertRejected(object, as: .invalidField("PATCH%COM"))
        object["userPatch"] = [["PATCH%COM": ["00"]]]
        assertRejected(object, as: .invalidField("userPatch"))
    }

    func testRejectsMalformedJSONAndLocalPresetJSON() {
        for data in [Data("{broken".utf8), Data("{\"name\":\"Local preset\"}".utf8)] {
            XCTAssertThrowsError(try IR2Backup(data: data)) { error in
                XCTAssertEqual(error as? IR2Backup.ReadError, .invalidStructure)
            }
        }
    }
}
