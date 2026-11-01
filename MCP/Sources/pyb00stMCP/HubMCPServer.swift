#if MCP
import Foundation
import MCP
import pyb00st

/// Owns one lazily connected Move Hub and exposes it through the official MCP SDK.
@MainActor
public final class HubMCPServer {
    private let makeHub: (UUID?, String?, TimeInterval) -> MoveHub
    private var hub: MoveHub?
    private var busy = false
    private var closed = false
    private var generation = UUID()
    private var lastError: String?
    private var lastHubError: Value = .null
    private var lastEventAt: String?

    public convenience init() {
        self.init { MoveHub(identifier: $0, name: $1, timeout: $2) }
    }

    /// Supply a factory to embed the server or test it without Bluetooth hardware.
    public init(makeHub: @escaping @MainActor (UUID?, String?, TimeInterval) -> MoveHub) {
        self.makeHub = makeHub
    }

    /// Register the tools. Creating the server does not start Bluetooth discovery.
    public func makeServer() async -> Server {
        let server = Server(
            name: "pyb00st-mcp", version: "0.1.0",
            instructions: "Control one LEGO BOOST Move Hub. Connect explicitly before writes. " +
                "Motor pulses are limited to 2000 ms and serialized through their requested duration. " +
                "Readings are cached notifications, not a synchronous sensor measurement. " +
                "A successful write does not prove physical motion or firmware acceptance.",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: HubTools.all) }
        await server.withMethodHandler(CallTool.self) { [self] params in
            try await call(params)
        }
        return server
    }

    /// Serve newline-delimited JSON-RPC on stdin/stdout until EOF; disconnect on exit.
    public func runStdio() async throws {
        let server = await makeServer()
        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
            shutdown()
            await server.stop()
        } catch {
            shutdown()
            await server.stop()
            throw error
        }
    }

    /// Close the hub and reject subsequent tool calls after the transport ends.
    public func shutdown() {
        closed = true
        disconnect()
    }

    func call(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let tool = HubTools.all.first(where: { $0.name == params.name }) else {
            throw MCPError.invalidParams("Unknown tool: \(params.name)")
        }
        let args = try Arguments(params.arguments ?? [:], schema: tool.inputSchema)
        try Task.checkCancellation()
        guard !closed else { return failure("The server has shut down.") }
        if params.name == "hub_state" { return try result(snapshot()) }
        if params.name == "hub_disconnect" {
            disconnect()
            return try result(snapshot())
        }
        guard !busy else { return failure("Another hub operation is in progress. Retry after it finishes.") }
        busy = true
        defer { busy = false }

        do {
            switch params.name {
            case "hub_connect":
                let identifier = try args.optionalString("identifier").map { value in
                    guard let id = UUID(uuidString: value) else {
                        throw MCPError.invalidParams("identifier must be a peripheral UUID, not a Bluetooth MAC address.")
                    }
                    return id
                }
                let name = try args.optionalString("name")
                let timeout = try args.optionalInteger("timeoutSeconds", range: 1...60) ?? 10
                guard hub?.isConnected != true else {
                    return failure("A hub is already connected. Disconnect it before selecting another hub.")
                }
                let current = makeHub(identifier, name, TimeInterval(timeout))
                hub = current
                generation = UUID()
                let operation = generation
                lastError = nil
                lastHubError = .null
                lastEventAt = nil
                current.onError = { [weak self] error in
                    guard self?.generation == operation else { return }
                    self?.lastError = error.localizedDescription
                }
                current.onEvent = { [weak self] event in
                    guard self?.generation == operation else { return }
                    self?.lastEventAt = ISO8601DateFormatter().string(from: Date())
                    if case .hubError(let command, let code) = event {
                        self?.lastHubError = .object(["command": .int(Int(command)), "code": .int(Int(code))])
                    }
                }
                current.onDisconnect = { [weak self] _ in
                    guard self?.generation == operation else { return }
                    self?.lastEventAt = nil
                }
                do {
                    try await current.start()
                    try checkSession(current, operation: operation)
                } catch {
                    if generation == operation { disconnect() }
                    throw error
                }
            case "hub_led":
                let name = try args.string("color")
                guard let color = HubColor.allCases.first(where: { String(describing: $0) == name }) else {
                    throw MCPError.invalidParams("Unsupported LED color.")
                }
                let current = try connectedHub()
                try await current.setHubLight(color)
            case "hub_motor_run":
                let port = try args.string("port")
                let milliseconds = try args.integer("milliseconds", range: 1...2000)
                let dutyCycle = try args.integer("dutyCycle", range: -100...100)
                guard let motor = HubMotor.allCases.first(where: { String(describing: $0).uppercased() == port }) else {
                    throw MCPError.invalidParams("Motor port must be A, B, C or D.")
                }
                let current = try connectedHub()
                let operation = generation
                do {
                    try await current.runMotorForTime(motor, milliseconds: milliseconds, dutyCycle: dutyCycle)
                    // Keep other motion/configuration calls out until this bounded pulse has elapsed.
                    try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
                    try checkSession(current, operation: operation)
                } catch {
                    if generation == operation { disconnect() }
                    throw error
                }
            case "hub_sensor_subscribe":
                let sensorName = try args.string("sensor")
                let port = try args.port()
                let sensors: [String: HubSensor] = [
                    "encoder": .encoder, "hubTilt": .hubTilt, "colorDistance": .colorDistance,
                    "weDoTiltAngle": .weDoTilt(.angle), "weDoTilt": .weDoTilt(.tilt),
                    "weDoCrash": .weDoTilt(.crash), "weDoDistance": .weDoDistance,
                ]
                guard let sensor = sensors[sensorName] else { throw MCPError.invalidParams("Unknown sensor mode.") }
                try await connectedHub().listen(to: sensor, on: port)
            case "hub_sensor_unsubscribe":
                let port = try args.port()
                try await connectedHub().stopListening(on: port)
            case "hub_button_subscribe":
                try await connectedHub().listenButton()
            default:
                throw MCPError.invalidParams("Unknown tool.")
            }
            return try result(snapshot())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MCPError {
            throw error
        } catch {
            lastError = error.localizedDescription
            return failure(error.localizedDescription)
        }
    }

    private func connectedHub() throws -> MoveHub {
        guard let hub, hub.isConnected else { throw HubError.notConnected }
        return hub
    }

    private func checkSession(_ current: MoveHub, operation: UUID) throws {
        try Task.checkCancellation()
        guard !closed, generation == operation, hub === current, current.isConnected else {
            throw HubError.notConnected
        }
    }

    private func disconnect() {
        generation = UUID()
        hub?.stop()
        hub = nil
        lastEventAt = nil
    }

    private func snapshot() -> Value {
        var ports: [String: Value] = [:]
        for (port, reading) in hub?.values.ports ?? [:] {
            var fields: [String: Value] = [:]
            fields["angle"] = reading.angle.map { Value.int(Int($0)) } ?? .null
            fields["color"] = reading.color.map { Value.string(String(describing: $0)) } ?? .null
            fields["distance"] = reading.distance.map { Value.int(Int($0)) } ?? .null
            fields["roll"] = reading.roll.map { Value.int(Int($0)) } ?? .null
            fields["pitch"] = reading.pitch.map { Value.int(Int($0)) } ?? .null
            fields["weDoTilt"] = reading.weDoTilt.map { Value.string(String(describing: $0)) } ?? .null
            fields["crash"] = reading.crash.map { Value.array($0.map { Value.int(Int($0)) }) } ?? .null
            fields["weDoDistance"] = reading.weDoDistance.map { Value.int(Int($0)) } ?? .null
            ports[String(describing: port).uppercased()] = .object(fields)
        }
        return .object([
            "connected": .bool(hub?.isConnected == true),
            "deviceIdentifier": hub?.device.map { .string($0.identifier.uuidString) } ?? .null,
            "deviceName": hub?.device?.name.map(Value.string) ?? .null,
            "buttonPressed": hub?.values.isButtonPressed.map(Value.bool) ?? .null,
            "tilt": hub?.values.tilt.map { .string(String(describing: $0)) } ?? .null,
            "ports": .object(ports), "lastEventAt": lastEventAt.map(Value.string) ?? .null,
            "lastError": lastError.map(Value.string) ?? .null, "lastHubError": lastHubError,
        ])
    }

    private func result(_ value: Value) throws -> CallTool.Result {
        let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], structuredContent: Optional.some(value), isError: false)
    }

    private func failure(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}
#endif
