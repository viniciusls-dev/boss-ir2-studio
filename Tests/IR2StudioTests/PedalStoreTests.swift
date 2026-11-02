import XCTest
import Combine
@testable import IR2Studio

@MainActor
final class PedalStoreTests: XCTestCase {
    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }
    private func connectedStore(_ transport: MockIR2Transport) async throws -> PedalStore {
        let store = PedalStore(session: IR2Session(transport: transport, timeout: .milliseconds(100)))
        store.connect()
        try await waitUntil { store.connected && !store.busy }
        return store
    }
    private func writes(_ transport: MockIR2Transport) -> [[UInt8]] {
        transport.sent.filter { $0.count > 6 && $0[6] == 0x12 && $0 != IR2SysEx.liveUpdates }
    }

    func testIncomingUpdateDoesNotReloadOrToggleBusy() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        let requestCount = transport.sent.count
        var busyTransitions: [Bool] = []
        let subscription = store.$busy.dropFirst().sink { busyTransitions.append($0) }
        defer { subscription.cancel() }
        transport.active[4] = 7
        transport.onBytes?(IR2SysEx.data(address: 0x20000004, bytes: [7]))
        try await waitUntil { store.snapshot?.green.value(.gain) == 7 && !store.busy }
        XCTAssertEqual(transport.sent.count, requestCount, "A knob event must not trigger a full reload")
        XCTAssertTrue(busyTransitions.isEmpty, "A knob event must not rebuild the loading UI")
    }

    func testIdleConnectionDoesNotPollOrRepublishState() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        let requestCount = transport.sent.count
        let lastRead = store.lastRead
        try await Task.sleep(for: .milliseconds(3200))
        XCTAssertEqual(transport.sent.count, requestCount)
        XCTAssertEqual(store.lastRead, lastRead)
    }

    func testIdenticalEventsDoNotRepublishOrRefreshTimestamp() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        let lastRead = store.lastRead
        let requestCount = transport.sent.count
        var publications = 0
        let subscription = store.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        transport.onBytes?(IR2SysEx.data(address: 0x20000004, bytes: [0]))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.lastRead, lastRead)
        XCTAssertEqual(transport.sent.count, requestCount)
    }

    func testRecallBurstDoesNotApplyActiveValuesToPreviousChannel() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        let originalGreen = try XCTUnwrap(store.snapshot?.green)
        let requestCount = transport.sent.count
        transport.onBytes?(IR2SysEx.data(address: 0x20000000, bytes: transport.red))
        transport.onBytes?(IR2SysEx.data(address: 0x22000000, bytes: transport.red))
        transport.onBytes?(IR2SysEx.data(address: 0, bytes: [1]))
        try await waitUntil { store.snapshot?.selectedChannel == .red }
        XCTAssertEqual(store.snapshot?.green, originalGreen)
        XCTAssertEqual(store.snapshot?.red.bytes, transport.red)
        XCTAssertEqual(transport.sent.count, requestCount)
    }

    func testInvalidAmpEventIsIgnoredWithoutBreakingTheView() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        let original = store.snapshot
        transport.onBytes?(IR2SysEx.data(address: 0x20000006, bytes: [11]))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(store.snapshot, original)
    }

    func testDefaultConnectionOnlyReadsAndCannotWrite() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        store.setValue(channel: .green, parameter: .gain, value: 1)
        XCTAssertFalse(store.canEdit)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertTrue(writes(transport).isEmpty)
        XCTAssertEqual(store.snapshot?.red.value(.gain), 119)
    }

    func testRapidEditsSendOnlyLatestValueAndReadItBack() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        store.setEditing(true)
        store.setValue(channel: .green, parameter: .gain, value: 1)
        store.setValue(channel: .green, parameter: .gain, value: 2)
        store.setValue(channel: .green, parameter: .gain, value: 3)
        XCTAssertEqual(store.value(channel: .green, parameter: .gain), 3)
        try await waitUntil { store.pending.isEmpty && !store.busy }
        XCTAssertEqual(writes(transport).count, 2) // stored channel and sounding block
        XCTAssertEqual(transport.green[4], 3)
        XCTAssertEqual(store.snapshot?.green.value(.gain), 3)
        XCTAssertEqual(store.snapshot?.red.value(.gain), 119)
    }

    func testFailedReadbackDisablesEditingAndMarksStateStale() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        store.setEditing(true)
        transport.ignoreWrites = true
        store.setValue(channel: .green, parameter: .gain, value: 1)
        try await waitUntil { store.error != nil && !store.busy }
        XCTAssertFalse(store.canEdit)
        XCTAssertTrue(store.stale)
        XCTAssertTrue(store.pending.isEmpty)
        transport.ignoreWrites = false
        store.refresh()
        try await waitUntil { !store.busy }
        XCTAssertFalse(store.stale)
        XCTAssertFalse(store.editingEnabled)
        XCTAssertEqual(store.snapshot?.green.value(.gain), 0)
    }

    func testDisconnectCancelsPendingEditsAndReconnectIsReadOnly() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        store.setEditing(true)
        store.setValue(channel: .green, parameter: .gain, value: 1)
        transport.onDisconnect?()
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertFalse(store.connected)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertTrue(writes(transport).isEmpty)
        store.connect()
        try await waitUntil { store.connected && !store.busy }
        XCTAssertFalse(store.canEdit)
        store.disconnect()
    }

    func testIncomingChangeRefreshesSnapshotWithoutWriting() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        transport.green[4] = 7
        transport.active[4] = 7
        transport.onBytes?(IR2SysEx.data(address: 0x21000004, bytes: [7]))
        try await waitUntil { store.snapshot?.green.value(.gain) == 7 && !store.busy }
        XCTAssertTrue(writes(transport).isEmpty)
    }

    func testApplyCapturedPresetPreservesExactRawValues() async throws {
        let transport = MockIR2Transport()
        let store = try await connectedStore(transport)
        defer { store.disconnect() }
        let original = try XCTUnwrap(store.snapshot)
        var preset = Preset(name: "Exact")
        preset.channelA = AmpSettings(patch: original.green)
        preset.channelB = AmpSettings(patch: original.red)
        preset.channelA.gain = 1
        store.setEditing(true)
        try store.apply(preset)
        try await waitUntil { store.pending.isEmpty && !store.busy }
        XCTAssertEqual(writes(transport).count, 21) // 7 active + stored green, 7 stored red
        XCTAssertEqual(store.snapshot?.green.bytes, [64,96,73,92,1,66,0])
        XCTAssertEqual(store.snapshot?.red, original.red)
        XCTAssertFalse(store.stale)
    }
}

final class PresetCompatibilityTests: XCTestCase {
    func testLegacyPresetRetainsScaleAndGainsAndMigratesAmpLabels() throws {
        let json = #"{"amp":"TWD","gain":65,"bass":50,"middle":50,"treble":50,"level":50}"#
        let settings = try JSONDecoder().decode(AmpSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.amp, .tweed)
        XCTAssertEqual(settings.maximum, 100)
        XCTAssertEqual(settings.gain, 65)
        XCTAssertEqual(settings.ambience, 50)
        XCTAssertEqual(try settings.pedalPatch().value(.gain), 83)
        XCTAssertEqual(try settings.pedalPatch().value(.amp), 2)
    }

    func testCapturedRawPatchRoundTripsExactly() throws {
        let original = try PedalPatch(bytes: [0,103,41,79,119,101,2])
        let settings = AmpSettings(patch: original)
        let reloaded = try JSONDecoder().decode(AmpSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(try reloaded.pedalPatch(), original)
        XCTAssertEqual(reloaded.maximum, 127)
    }

    func testRejectsUnsafePresetValues() {
        let json = #"{"amp":"CLEAN","gain":999,"bass":50,"middle":50,"treble":50,"level":50}"#
        XCTAssertThrowsError(try JSONDecoder().decode(AmpSettings.self, from: Data(json.utf8)))
        var settings = AmpSettings()
        settings.gain = .nan
        XCTAssertThrowsError(try settings.pedalPatch())
        settings.gain = -1
        XCTAssertThrowsError(try settings.pedalPatch())
    }
}
