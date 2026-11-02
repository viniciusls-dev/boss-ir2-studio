import Foundation
import CoreMIDI

@MainActor
protocol IR2Transport: AnyObject {
    var onBytes: (([UInt8]) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func open() throws -> String
    func close()
    func send(_ bytes: [UInt8]) throws
}

/// MIDI 1.0 transport for the vendor driver's SysEx endpoints. All ownership is on the main actor.
@MainActor
final class IR2MIDITransport: IR2Transport {
    var onBytes: (([UInt8]) -> Void)?
    var onDisconnect: (() -> Void)?
    private var client: MIDIClientRef = 0
    private var input: MIDIPortRef = 0
    private var output: MIDIPortRef = 0
    private var source: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private var generation = UUID()

    func open() throws -> String {
        close()
        let sources = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter(Self.isIR2)
        let destinations = (0..<MIDIGetNumberOfDestinations()).map(MIDIGetDestination).filter(Self.isIR2)
        guard sources.count <= 1, destinations.count <= 1 else { throw IR2ProtocolError.ambiguousDevice }
        guard let source = sources.first, let destination = destinations.first,
              Self.device(source) == Self.device(destination) else { throw IR2ProtocolError.notFound }
        self.source = source
        self.destination = destination
        let generation = self.generation
        do {
            try check(MIDIClientCreateWithBlock("IR2Studio" as CFString, &client) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == generation, self.source != 0 else { return }
                    let liveSources = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource)
                    let liveDestinations = (0..<MIDIGetNumberOfDestinations()).map(MIDIGetDestination)
                    if !liveSources.contains(self.source) || !liveDestinations.contains(self.destination)
                        || !Self.isIR2(self.source) || !Self.isIR2(self.destination) {
                        self.onDisconnect?()
                    }
                }
            })
            try check(MIDIInputPortCreateWithBlock(client, "IR2Studio Input" as CFString, &input) { [weak self] list, _ in
                let packets = Self.copyPackets(list)
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else { return }
                    for bytes in packets { self.onBytes?(bytes) }
                }
            })
            try check(MIDIOutputPortCreate(client, "IR2Studio Output" as CFString, &output))
            try check(MIDIPortConnectSource(input, source, nil))
            return Self.string(source, kMIDIPropertyDisplayName)
        } catch { close(); throw error }
    }

    func close() {
        generation = UUID()
        if input != 0, source != 0 { MIDIPortDisconnectSource(input, source) }
        if client != 0 { MIDIClientDispose(client) }
        client = 0; input = 0; output = 0; source = 0; destination = 0
    }

    func send(_ bytes: [UInt8]) throws {
        guard output != 0, destination != 0 else { throw IR2ProtocolError.disconnected }
        guard !bytes.isEmpty, bytes.count <= 64 else { throw IR2ProtocolError.invalidValue }
        var list = MIDIPacketList()
        let status = withUnsafeMutablePointer(to: &list) { pointer in
            let packet = MIDIPacketListInit(pointer)
            bytes.withUnsafeBufferPointer { buffer in
                _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, buffer.count, buffer.baseAddress!)
            }
            return MIDISend(output, destination, pointer)
        }
        try check(status)
    }

    nonisolated static func copyPackets(_ list: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        var cursor = UnsafeRawPointer(list)
            .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)
        var packets: [[UInt8]] = []
        for _ in 0..<list.pointee.numPackets {
            let bytes = UnsafeRawPointer(cursor).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!)
                .assumingMemoryBound(to: UInt8.self)
            packets.append(Array(UnsafeBufferPointer(start: bytes, count: Int(cursor.pointee.length))))
            cursor = UnsafePointer(MIDIPacketNext(cursor))
        }
        return packets
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw IR2ProtocolError.midi(status) }
    }
    private static func string(_ ref: MIDIObjectRef, _ key: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(ref, key, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
    private static func device(_ endpoint: MIDIEndpointRef) -> MIDIDeviceRef {
        var entity: MIDIEntityRef = 0
        var device: MIDIDeviceRef = 0
        MIDIEndpointGetEntity(endpoint, &entity)
        MIDIEntityGetDevice(entity, &device)
        return device
    }
    private static func isIR2(_ endpoint: MIDIEndpointRef) -> Bool {
        let device = device(endpoint)
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline)
        return device != 0 && offline == 0 && string(device, kMIDIPropertyModel).uppercased() == "IR-2"
            && ["BOSS", "ROLAND"].contains(string(device, kMIDIPropertyManufacturer).uppercased())
    }
}
