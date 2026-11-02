import Foundation

@MainActor
final class PedalStore: ObservableObject {
    struct ParameterKey: Hashable {
        let channel: PedalChannel
        let parameter: PedalParameter
    }
    @Published private(set) var snapshot: PedalSnapshot?
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var editingEnabled = false
    @Published private(set) var stale = true
    @Published private(set) var lastRead: Date?
    @Published private(set) var error: String?
    @Published private(set) var pending: [ParameterKey: Int] = [:]
    @Published private(set) var pendingSelection: PedalChannel?

    private let session: IR2Session
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var events: [PedalSnapshot.Update] = []
    private var debounce: Task<Void, Never>?
    private var queue: [ParameterKey: Int] = [:]
    private var writesReady = false
    private var refreshRequested = false

    var canEdit: Bool { connected && editingEnabled && !stale }
    var status: String {
        if !connected { return busy ? "Conectando…" : "Desconectado" }
        if stale { return "Leitura desatualizada" }
        return pending.isEmpty && pendingSelection == nil ? "Conectado por USB" : "Confirmando alteração…"
    }

    init(session: IR2Session) {
        self.session = session
        session.onDisconnect = { [weak self] in self?.disconnect(message: "O IR-2 foi desconectado. Reconecte o cabo e clique em Conectar.") }
        session.onParameterUpdate = { [weak self] update in
            guard let self, self.connected else { return }
            guard update.address == 0 || (0x20000000...0x22000006).contains(update.address) else { return }
            self.events.append(update)
            if self.events.count > 256 { self.events.removeFirst(self.events.count - 256) }
            guard !self.busy, self.eventTask == nil else { return }
            self.eventTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(12)) } catch { return }
                self?.flushEvents()
            }
        }
    }

    func connect() {
        guard !busy, !connected else { return }
        error = nil
        run { [self] in
            _ = try await self.session.connect()
            let snapshot = try await self.session.snapshot()
            self.connected = true
            self.accept(snapshot)
        }
    }

    func disconnect(message: String? = nil) {
        generation = UUID()
        operation?.cancel(); operation = nil
        clearEvents()
        debounce?.cancel(); debounce = nil
        session.disconnect()
        connected = false; busy = false; editingEnabled = false; stale = true
        queue.removeAll(); pending.removeAll(); pendingSelection = nil
        refreshRequested = false; writesReady = false
        error = message
    }

    func setEditing(_ enabled: Bool) {
        editingEnabled = enabled && connected && !stale
        if !editingEnabled {
            queue.removeAll(); pending.removeAll(); pendingSelection = nil
            debounce?.cancel(); writesReady = false
        }
    }

    func refresh() {
        guard connected else { return }
        guard !busy else { refreshRequested = true; return }
        run { self.accept(try await self.session.snapshot()) }
    }

    func value(channel: PedalChannel, parameter: PedalParameter) -> Int {
        pending[ParameterKey(channel: channel, parameter: parameter)] ?? snapshot?.patch(channel).value(parameter) ?? 0
    }

    func setValue(channel: PedalChannel, parameter: PedalParameter, value: Int) {
        guard canEdit, (0...parameter.maximum).contains(value) else { return }
        let key = ParameterKey(channel: channel, parameter: parameter)
        queue[key] = value; pending[key] = value
        writesReady = false
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            self?.writesReady = true
            self?.drain()
        }
    }

    func select(_ channel: PedalChannel) {
        guard canEdit else { return }
        pendingSelection = channel
        drain()
    }

    func apply(_ preset: Preset) throws {
        guard canEdit, !busy, pending.isEmpty else { throw IR2ProtocolError.busy }
        let green = try preset.channelA.pedalPatch()
        let red = try preset.channelB.pedalPatch()
        for channel in PedalChannel.allCases {
            let patch = channel == .green ? green : red
            for parameter in PedalParameter.allCases {
                let key = ParameterKey(channel: channel, parameter: parameter)
                queue[key] = patch.value(parameter); pending[key] = patch.value(parameter)
            }
        }
        writesReady = true
        drain()
    }

    private func drain() {
        guard !busy, canEdit else { return }
        guard (writesReady && !queue.isEmpty) || pendingSelection != nil else { return }
        run {
            while self.canEdit {
                if self.writesReady, let key = self.queue.keys.sorted(by: {
                    ($0.channel.rawValue, $0.parameter.rawValue) < ($1.channel.rawValue, $1.parameter.rawValue)
                }).first, let value = self.queue.removeValue(forKey: key) {
                    try await self.session.write(channel: key.channel, parameter: key.parameter, value: value)
                    var snapshot = self.snapshot
                    try snapshot?.set(key.channel, parameter: key.parameter, value: value)
                    self.snapshot = snapshot
                    if self.pending[key] == value { self.pending.removeValue(forKey: key) }
                } else if let selection = self.pendingSelection {
                    try await self.session.select(selection)
                    if self.pendingSelection == selection { self.pendingSelection = nil }
                } else { break }
            }
            self.accept(try await self.session.snapshot())
        }
    }

    private func accept(_ snapshot: PedalSnapshot) {
        let latest = snapshot.applying(events)
        clearEvents()
        if self.snapshot != latest { self.snapshot = latest }
        lastRead = Date(); stale = false; error = nil
    }

    private func clearEvents() {
        eventTask?.cancel(); eventTask = nil
        events.removeAll(keepingCapacity: true)
    }

    private func flushEvents() {
        guard !busy, let snapshot else { return }
        let latest = snapshot.applying(events)
        clearEvents()
        guard latest != snapshot else { return }
        self.snapshot = latest
        lastRead = Date()
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        flushEvents()
        let generation = self.generation
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            do { try await action() }
            catch {
                guard self.generation == generation else { return }
                self.error = error.localizedDescription
                self.stale = true; self.editingEnabled = false
                self.clearEvents()
                self.queue.removeAll(); self.pending.removeAll(); self.pendingSelection = nil
                if !self.connected { self.session.disconnect() }
            }
            guard self.generation == generation else { return }
            self.busy = false; self.operation = nil
            if self.canEdit && ((self.writesReady && !self.queue.isEmpty) || self.pendingSelection != nil) {
                self.drain()
            } else if self.refreshRequested {
                self.refreshRequested = false
                self.refresh()
            }
        }
    }
}
