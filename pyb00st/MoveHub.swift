import Foundation

/// Controls one LEGO BOOST Move Hub over a native or caller-supplied transport.
@MainActor
public final class MoveHub {
    private let transport: any HubTransport
    private var decoder = HubNotificationDecoder()
    private var session = UUID()
    private var configurations: [HubPort: UUID] = [:]

    /// Latest readings, cleared on disconnect and on a sensor's mode change.
    public var values: HubValues { decoder.values }
    /// Whether writes and notifications are ready.
    public var isConnected: Bool { transport.isConnected }
    /// Peripheral identity and name reported by the transport.
    public var device: HubDevice? { transport.device }
    /// Receives decoded sensor events synchronously on the main actor.
    public var onEvent: ((HubEvent) -> Void)?
    /// Receives malformed notifications and asynchronous transport failures.
    public var onError: ((any Error) -> Void)?
    /// Receives both requested and unexpected disconnections.
    public var onDisconnect: (((any Error)?) -> Void)?

    /// Create a hub using an exclusively owned transport.
    public init(transport: any HubTransport) {
        self.transport = transport
        transport.onNotification = { [weak self] data in
            guard let self, self.isConnected else { return }
            do {
                if let event = try self.decoder.decode(data) { self.onEvent?(event) }
            } catch {
                self.onError?(error)
            }
        }
        transport.onDisconnect = { [weak self] error in
            guard let self else { return }
            self.reset()
            if let error { self.onError?(error) }
            self.onDisconnect?(error)
        }
    }

    /// Find a BOOST hub, optionally restricted to a peripheral UUID or advertised name.
    public convenience init(identifier: UUID? = nil, name: String? = nil, timeout: TimeInterval = 10) {
        self.init(transport: CoreBluetoothTransport(identifier: identifier, name: name, timeout: timeout))
    }

    /// Connect and subscribe to the hub characteristic. Sensor modes are enabled separately.
    public func start() async throws { try await transport.connect() }

    /// Disconnect and clear all cached sensor values.
    public func stop() {
        transport.disconnect()
        reset()
    }

    /// Set the hub's indexed LED color, including `.off`.
    public func setHubLight(_ color: HubColor) async throws {
        try await send(HubCommand.hubLight(color))
    }

    /// Return after the write; this does not wait for motor motion to finish.
    public func runMotorForTime(_ motor: HubMotor, milliseconds: Int, dutyCycle: Int) async throws {
        try await send(HubCommand.motorForTime(motor, milliseconds: milliseconds, dutyCycle: dutyCycle))
    }

    /// Run A and B together for a duration in milliseconds, returning after the write.
    public func runMotorsForTime(milliseconds: Int, dutyCycleA: Int, dutyCycleB: Int) async throws {
        try await send(HubCommand.motorsForTime(milliseconds: milliseconds, dutyCycleA: dutyCycleA, dutyCycleB: dutyCycleB))
    }

    /// Run one motor through a nonnegative angle; the duty cycle selects the direction.
    public func runMotorForAngle(_ motor: HubMotor, degrees: Int, dutyCycle: Int) async throws {
        try await send(HubCommand.motorForAngle(motor, degrees: degrees, dutyCycle: dutyCycle))
    }

    /// Run paired motors A/B through an angle, returning before motion finishes.
    public func runMotorsForAngle(degrees: Int, dutyCycleA: Int, dutyCycleB: Int) async throws {
        try await send(HubCommand.motorsForAngle(degrees: degrees, dutyCycleA: dutyCycleA, dutyCycleB: dutyCycleB))
    }

    /// Set a WeDo motor's duty cycle on C or D; zero stops the motor.
    public func runWeDoMotor(on port: HubPort, dutyCycle: Int) async throws {
        try await send(HubCommand.weDoMotor(on: port, dutyCycle: dutyCycle))
    }

    /// Enable one sensor mode. The previous reading and interpretation are discarded.
    public func listen(to sensor: HubSensor, on port: HubPort) async throws {
        let command = try HubCommand.sensor(sensor, on: port)
        try Task.checkCancellation()
        guard isConnected else { throw HubError.notConnected }
        let operation = try beginConfiguration(on: port)
        let currentSession = session
        defer { endConfiguration(operation, on: port) }
        // Install before writing: a notification may precede the write acknowledgment.
        // A failed write makes the configured state uncertain, so disconnect and clear it.
        try decoder.configure(sensor, on: port)
        do {
            try await send(command)
        } catch {
            if session == currentSession { stop() }
            throw error
        }
    }

    /// Enable press and release events from the hub's button.
    public func listenButton() async throws { try await send(HubCommand.listenButton) }

    /// Disable notifications for the port's current sensor mode and clear its reading.
    public func stopListening(on port: HubPort) async throws {
        try Task.checkCancellation()
        guard isConnected else { throw HubError.notConnected }
        let operation = try beginConfiguration(on: port)
        let currentSession = session
        defer { endConfiguration(operation, on: port) }
        guard let sensor = decoder.sensors[port] else { return }
        do {
            try await send(HubCommand.sensor(sensor, on: port, enabled: false))
            decoder.removeSensor(on: port)
        } catch {
            if session == currentSession { stop() }
            throw error
        }
    }

    private func send(_ command: Data) async throws {
        try Task.checkCancellation()
        guard isConnected else { throw HubError.notConnected }
        let currentSession = session
        try await transport.write(command)
        guard currentSession == session, isConnected else { throw HubError.notConnected }
    }

    private func reset() {
        session = UUID()
        configurations.removeAll()
        decoder = HubNotificationDecoder()
    }

    private func beginConfiguration(on port: HubPort) throws -> UUID {
        guard configurations[port] == nil else { throw HubError.configurationInProgress(port) }
        let id = UUID()
        configurations[port] = id
        return id
    }

    private func endConfiguration(_ id: UUID, on port: HubPort) {
        if configurations[port] == id { configurations[port] = nil }
    }
}
