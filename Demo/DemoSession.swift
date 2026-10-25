import Foundation
import Observation
import pyb00st

@MainActor
@Observable
final class DemoSession {
    var shouldConnect = false
    private(set) var isConnecting = false
    private(set) var isConnected = false
    private(set) var isSending = false
    private(set) var deviceName: String?
    private(set) var values = HubValues()
    var errorMessage: String?

    @ObservationIgnored private let hub: MoveHub
    @ObservationIgnored private var connectionID = UUID()

    init(hub: MoveHub = MoveHub()) {
        self.hub = hub
        hub.onEvent = { [weak self] event in
            guard let self else { return }
            self.values = self.hub.values
            if case .hubError(let command, let code) = event {
                self.errorMessage = String(localized: "Hub rejected command \(command) with error \(code).")
            }
        }
        hub.onError = { [weak self] error in
            if !(error is CancellationError) { self?.errorMessage = error.localizedDescription }
        }
        hub.onDisconnect = { [weak self] _ in self?.resetConnection() }
    }

    func connect() async {
        guard shouldConnect, !isConnecting, !isConnected else { return }
        let id = UUID()
        connectionID = id
        isConnecting = true
        errorMessage = nil
        defer { if connectionID == id { isConnecting = false } }
        do {
            try await hub.start()
            guard connectionID == id, shouldConnect else { return }
            isConnected = true
            deviceName = hub.device?.name
            try await hub.listenButton()
            try await hub.listen(to: .hubTilt, on: .tilt)
            try await hub.listen(to: .encoder, on: .a)
            try await hub.listen(to: .encoder, on: .b)
        } catch {
            guard connectionID == id else { return }
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
            disconnect()
        }
    }

    func disconnect() {
        hub.stop()
        resetConnection()
    }

    func setColor(_ color: HubColor) async {
        await send { try await hub.setHubLight(color) }
    }

    func runMotor(_ motor: HubMotor, speed: Int) async {
        await send { try await hub.runMotorForTime(motor, milliseconds: 500, dutyCycle: speed) }
    }

    func runPair(speed: Int) async {
        await send { try await hub.runMotorsForTime(milliseconds: 500, dutyCycleA: speed, dutyCycleB: speed) }
    }

    private func send(_ action: () async throws -> Void) async {
        guard isConnected, !isConnecting, !isSending else { return }
        isSending = true
        let id = connectionID
        defer { if connectionID == id { isSending = false } }
        do { try await action() }
        catch {
            if connectionID == id, !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    private func resetConnection() {
        connectionID = UUID()
        shouldConnect = false
        isConnecting = false
        isConnected = false
        isSending = false
        deviceName = nil
        values = HubValues()
    }
}
