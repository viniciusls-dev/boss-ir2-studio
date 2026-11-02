import XCTest
@testable import IR2Studio

final class IR2ProtocolTests: XCTestCase {
    func testReadMatchesCapturedHardwareRequest() throws {
        XCTAssertEqual(try IR2SysEx.read(address: 0x21000000, count: 7),
                       [0xF0,0x41,0x10,1,5,9,0x11,0x21,0,0,0,0,0,0,7,0x58,0xF7])
        let captured: [UInt8] = [0xF0,0x41,0x10,1,5,9,0x12,0x22,0,0,0,0,0x67,0x29,0x4F,0x77,0x65,2,0x21,0xF7]
        XCTAssertEqual(IR2SysEx.parse(captured), .data(address: 0x22000000, bytes: [0,0x67,0x29,0x4F,0x77,0x65,2]))
    }

    func testRejectsBadChecksumForeignDeviceAndNonSevenBitData() {
        let good = IR2SysEx.data(address: 0, bytes: [0])
        var bad = good; bad[bad.count-2] ^= 1
        XCTAssertNil(IR2SysEx.parse(bad))
        bad = good; bad[2] = 0x11
        XCTAssertNil(IR2SysEx.parse(bad))
        bad = good; bad[11] = 128
        XCTAssertNil(IR2SysEx.parse(bad))
        XCTAssertNil(IR2SysEx.parse(Array(good.dropLast())))
    }

    func testIdentityMustBeIR2() {
        let identity: [UInt8] = [0xF0,0x7E,0x10,6,2,0x41,9,5,0,0,0,0,0,0,0xF7]
        XCTAssertEqual(IR2SysEx.parse(identity), .identity)
        var other = identity; other[7] = 6
        XCTAssertNil(IR2SysEx.parse(other))
    }

    func testStreamReassemblesFragmentsAndIgnoresRealtime() {
        let frame = IR2SysEx.data(address: 0, bytes: [1])
        var stream = SysExStream()
        XCTAssertEqual(stream.append([0x90,60,127] + Array(frame.prefix(6))), [])
        XCTAssertEqual(stream.append([0xF8] + Array(frame.dropFirst(6)) + frame), [frame, frame])
        XCTAssertEqual(stream.append([0xF0,1,0x90,0xF7] + frame), [frame])
        XCTAssertEqual(stream.append([0xF0] + Array(repeating: 0, count: 2048) + [0xF7] + frame), [frame])
    }

    func testWritesAreRestrictedToMappedRanges() throws {
        XCTAssertThrowsError(try IR2SysEx.write(channel: .green, parameter: .gain, value: -1))
        XCTAssertThrowsError(try IR2SysEx.write(channel: .red, parameter: .level, value: 128))
        XCTAssertThrowsError(try IR2SysEx.write(channel: .red, parameter: .amp, value: 11))
        XCTAssertThrowsError(try IR2SysEx.read(address: 0x7F000200, count: 1))
        XCTAssertEqual(IR2SysEx.parse(try IR2SysEx.write(channel: .red, parameter: .gain, value: 119)),
                       .data(address: 0x22000004, bytes: [119]))
    }

    func testRejectsInvalidPatchBeforeIndexing() {
        XCTAssertThrowsError(try PedalPatch(bytes: []))
        XCTAssertThrowsError(try PedalPatch(bytes: [0,0,0,0,0,0,11]))
        XCTAssertThrowsError(try PedalPatch(bytes: [0,0,0,128,0,0,0]))
    }
}

@MainActor
final class MockIR2Transport: IR2Transport {
    var onBytes: (([UInt8]) -> Void)?
    var onDisconnect: (() -> Void)?
    var sent: [[UInt8]] = []
    var opened = false
    var ignoreReads = false
    var ignoreWrites = false
    var transform: (([UInt8]) -> [[UInt8]])?
    var green: [UInt8] = [0x40,0x60,0x49,0x5C,0,0x42,0]
    var red: [UInt8] = [0,0x67,0x29,0x4F,0x77,0x65,2]
    var active: [UInt8] = [0x40,0x60,0x49,0x5C,0,0x42,0]
    var selected: UInt8 = 0

    func open() throws -> String { opened = true; return "Mock IR-2" }
    func close() { opened = false }
    func send(_ bytes: [UInt8]) throws {
        guard opened else { throw IR2ProtocolError.disconnected }
        sent.append(bytes)
        if bytes == IR2SysEx.identityRequest {
            emit([0xF0,0x7E,0x10,6,2,0x41,9,5,0,0,0,0,0,0,0xF7]); return
        }
        if bytes[6] == 0x11 {
            guard !ignoreReads else { return }
            let address = bytes[7..<11].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let count = Int(bytes[14])
            let block = address & 0xFF000000
            let offset = Int(address & 0xFF)
            let data: [UInt8]
            if address == 0 { data = [selected] }
            else if block == 0x20000000 { data = Array(active[offset..<offset+count]) }
            else if block == 0x21000000 { data = Array(green[offset..<offset+count]) }
            else if block == 0x22000000 { data = Array(red[offset..<offset+count]) }
            else { return }
            emit(IR2SysEx.data(address: address, bytes: data))
        } else if !ignoreWrites, case .data(let address, let data) = IR2SysEx.parse(bytes), let value = data.first {
            if address == 0 { selected = value }
            else if address == 0x7F000100, data == [0, selected] { active = selected == 0 ? green : red }
            else if address & 0xFF000000 == 0x20000000 { active[Int(address & 255)] = value }
            else if address & 0xFF000000 == 0x21000000 { green[Int(address & 255)] = value }
            else if address & 0xFF000000 == 0x22000000 { red[Int(address & 255)] = value }
        }
    }
    private func emit(_ bytes: [UInt8]) {
        for packet in transform?(bytes) ?? [bytes] { onBytes?(packet) }
    }
}

@MainActor
final class IR2SessionTests: XCTestCase {
    func testSnapshotUsesActiveBlockWhileStoredValuesLag() async throws {
        let transport = MockIR2Transport()
        transport.active[4] = 9
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        let state = try await session.snapshot()
        XCTAssertEqual(state.green.value(.gain), 9)
        XCTAssertEqual(transport.green[4], 0)
        session.disconnect()
    }

    func testEditingInactiveChannelDoesNotChangeSoundingBlock() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        let original = transport.active
        try await session.write(channel: .red, parameter: .gain, value: 118)
        XCTAssertEqual(transport.active, original)
        XCTAssertEqual(transport.red[4], 118)
        session.disconnect()
    }

    func testBusySessionRejectsWriteBeforeSendingIt() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        transport.ignoreReads = true
        let count = transport.sent.count
        let waiting = Task { try await session.snapshot() }
        while transport.sent.count == count { await Task.yield() }
        do { try await session.write(channel: .green, parameter: .gain, value: 1); XCTFail("Expected busy") }
        catch IR2ProtocolError.busy { }
        XCTAssertTrue(transport.sent.dropFirst().allSatisfy { $0 == IR2SysEx.liveUpdates || $0[6] == 0x11 })
        session.disconnect()
        _ = try? await waiting.value
    }

    func testHandshakeAndSnapshotReadBothChannelsWithoutWriting() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        let state = try await session.snapshot()
        XCTAssertEqual(state.green.value(.gain), 0)
        XCTAssertEqual(state.red.value(.gain), 119)
        XCTAssertEqual(state.selectedChannel, .green)
        XCTAssertEqual(transport.sent.count, 7)
        XCTAssertEqual(transport.sent[1], IR2SysEx.liveUpdates)
        XCTAssertTrue(transport.sent.dropFirst(2).allSatisfy { $0[6] == 0x11 })
        session.disconnect()
    }

    func testWriteIsReadBackAndLeavesOtherChannelUntouched() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        let original = try await session.snapshot()
        try await session.write(channel: .green, parameter: .gain, value: 1)
        let state = try await session.snapshot()
        XCTAssertEqual(state.green.value(.gain), 1)
        XCTAssertEqual(transport.active[4], 1)
        XCTAssertEqual(state.red, original.red)
        for parameter in PedalParameter.allCases where parameter != .gain {
            XCTAssertEqual(state.green.value(parameter), original.green.value(parameter))
        }
        try await session.select(.red)
        let selected = try await session.snapshot()
        XCTAssertEqual(selected.selectedChannel, .red)
        session.disconnect()
    }

    func testReadBackMismatchFailsInsteadOfReportingSuccess() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        transport.ignoreWrites = true
        do {
            try await session.write(channel: .green, parameter: .gain, value: 1)
            XCTFail("Expected readback failure")
        } catch IR2ProtocolError.unexpectedResponse { }
        session.disconnect()
    }

    func testTimeoutAndDisconnectFinishPendingRequests() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport, timeout: .milliseconds(30))
        _ = try await session.connect()
        transport.ignoreReads = true
        do { _ = try await session.snapshot(); XCTFail("Expected timeout") }
        catch IR2ProtocolError.timeout { }
        let count = transport.sent.count
        let waiting = Task { try await session.snapshot() }
        while transport.sent.count == count { await Task.yield() }
        session.disconnect()
        do { _ = try await waiting.value; XCTFail("Expected disconnect") }
        catch IR2ProtocolError.disconnected { }
    }

    func testCancellationDoesNotLeaveSessionBusy() async throws {
        let transport = MockIR2Transport()
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        transport.ignoreReads = true
        let count = transport.sent.count
        let waiting = Task { try await session.snapshot() }
        while transport.sent.count == count { await Task.yield() }
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        transport.ignoreReads = false
        _ = try await session.snapshot()
        session.disconnect()
    }

    func testFragmentedCoreMIDIMessagesStillRead() async throws {
        let transport = MockIR2Transport()
        transport.transform = { [Array($0.prefix(5)), [0xF8] + Array($0.dropFirst(5))] }
        let session = IR2Session(transport: transport)
        _ = try await session.connect()
        let state = try await session.snapshot()
        XCTAssertEqual(state.red.value(.gain), 119)
        session.disconnect()
    }
}
