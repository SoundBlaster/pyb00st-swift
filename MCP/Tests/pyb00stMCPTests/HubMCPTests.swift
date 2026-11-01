import Testing
#if MCP
import Foundation
import MCP
import pyb00st
@testable import pyb00stMCP

@MainActor
struct HubMCPTests {
    @Test(.timeLimit(.minutes(1)))
    func officialSDKRoundtripDoesNotStartBluetoothUntilConnect() async throws {
        let transport = FakeTransport()
        var creations = 0
        let host = HubMCPServer { _, _, _ in
            creations += 1
            return MoveHub(transport: transport)
        }
        let server = await host.makeServer()
        let pair = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: pair.server)
        let client = Client(name: "pyb00st-test", version: "1")
        do {
            let initialized = try await client.connect(transport: pair.client)
            #expect(initialized.serverInfo.name == "pyb00st-mcp")
            let tools = try await client.listTools()
            #expect(tools.tools.count == 8)
            #expect(tools.tools.first { $0.name == "hub_state" }?.annotations.readOnlyHint == true)
            let initial = try await client.callTool(name: "hub_state")
            #expect(initial.isError == false)
            #expect(creations == 0)
            let disconnectedWrite = try await client.callTool(name: "hub_led", arguments: ["color": "green"])
            #expect(disconnectedWrite.isError == true)
            #expect(transport.packets.isEmpty)
            let connected = try await client.callTool(name: "hub_connect")
            #expect(connected.isError == false)
            #expect(creations == 1)
            let led = try await client.callTool(name: "hub_led", arguments: ["color": "green"])
            #expect(led.isError == false)
            #expect(transport.packets.last == HubCommand.hubLight(.green))
            await client.disconnect()
            host.shutdown()
            await server.stop()
        } catch {
            await client.disconnect()
            host.shutdown()
            await server.stop()
            throw error
        }
        #expect(!transport.isConnected)
    }

    @Test func sensorNotificationsAndFirmwareErrorsReachState() async throws {
        let transport = FakeTransport()
        let host = HubMCPServer { _, _, _ in MoveHub(transport: transport) }
        defer { host.shutdown() }
        _ = try await host.call(.init(name: "hub_connect"))
        _ = try await host.call(.init(name: "hub_sensor_subscribe", arguments: ["port": "A", "sensor": "encoder"]))
        transport.onNotification?(Data([8, 0, 0x45, 0, 42, 0, 0, 0]))
        transport.onNotification?(Data([5, 0, 5, 0x81, 6]))
        let state = try await host.call(.init(name: "hub_state"))
        let json = try #require(state.structuredContent?.objectValue)
        #expect(json["ports"]?.objectValue?["A"]?.objectValue?["angle"] == .int(42))
        #expect(json["lastEventAt"]?.stringValue != nil)
        #expect(json["lastHubError"] == .object(["command": 129, "code": 6]))
        let stopped = try await host.call(.init(name: "hub_disconnect"))
        #expect(stopped.structuredContent?.objectValue?["ports"] == .object([:]))
        #expect(stopped.structuredContent?.objectValue?["connected"] == .bool(false))
    }

    @Test(arguments: [
        CallTool.Parameters(name: "hub_connect", arguments: ["identifier": "invalid"]),
        .init(name: "hub_connect", arguments: ["timeoutSeconds": 0]),
        .init(name: "hub_connect", arguments: ["name": " "]),
        .init(name: "hub_connect", arguments: ["extra": true]),
        .init(name: "hub_motor_run", arguments: ["port": "AB", "milliseconds": 1, "dutyCycle": 20]),
        .init(name: "hub_motor_run", arguments: ["port": "A", "milliseconds": 2001, "dutyCycle": 20]),
        .init(name: "hub_motor_run", arguments: ["port": "A", "milliseconds": 1, "dutyCycle": .double(1.5)]),
        .init(name: "hub_motor_run", arguments: ["port": "A", "milliseconds": -1, "dutyCycle": 20]),
        .init(name: "hub_motor_run", arguments: ["port": "A", "milliseconds": 1, "dutyCycle": 101]),
        .init(name: "hub_motor_run", arguments: ["port": "A"]),
        .init(name: "hub_led", arguments: ["color": "invalid"]),
        .init(name: "hub_led", arguments: ["color": .null]),
        .init(name: "missing"),
    ])
    func invalidArgumentsNeverConstructOrWriteHub(_ parameters: CallTool.Parameters) async throws {
        var creations = 0
        let transport = FakeTransport()
        let host = HubMCPServer { _, _, _ in
            creations += 1
            return MoveHub(transport: transport)
        }
        do {
            _ = try await host.call(parameters)
            Issue.record("Expected invalidParams")
        } catch let error as MCPError {
            if case .invalidParams = error {} else { Issue.record("Expected invalidParams: \(error)") }
        }
        #expect(creations == 0)
        #expect(transport.packets.isEmpty)
    }

    @Test func movementIsBoundedAndForwardedToTheFramework() async throws {
        let transport = FakeTransport()
        let host = HubMCPServer { _, _, _ in MoveHub(transport: transport) }
        defer { host.shutdown() }
        _ = try await host.call(.init(name: "hub_connect"))
        let movement = try await host.call(.init(name: "hub_motor_run", arguments: ["port": "B", "milliseconds": 1, "dutyCycle": -30]))
        #expect(movement.isError == false)
        #expect(transport.packets == [try HubCommand.motorForTime(.b, milliseconds: 1, dutyCycle: -30)])
    }

    @Test func concurrentMutationIsRejectedAndCancellationReleasesSession() async throws {
        let transport = FakeTransport()
        let host = HubMCPServer { _, _, _ in MoveHub(transport: transport) }
        defer { host.shutdown() }
        _ = try await host.call(.init(name: "hub_connect"))
        let (submitted, signal) = AsyncStream<Void>.makeStream()
        transport.onWrite = { signal.yield(()) }
        let movement = Task {
            try await host.call(.init(name: "hub_motor_run", arguments: ["port": "A", "milliseconds": 2000, "dutyCycle": 30]))
        }
        var iterator = submitted.makeAsyncIterator()
        _ = await iterator.next()
        let overlapping = try await host.call(.init(name: "hub_led", arguments: ["color": "red"]))
        #expect(overlapping.isError == true)
        let state = try await host.call(.init(name: "hub_state"))
        #expect(state.isError == false)
        movement.cancel()
        do { _ = try await movement.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        #expect(transport.packets.count == 1)
        #expect(!transport.isConnected)
        let reconnect = try await host.call(.init(name: "hub_connect"))
        #expect(reconnect.isError == false)
    }

    @Test func failedConnectionCanBeRetriedAndShutdownRejectsCommands() async throws {
        let transport = FakeTransport()
        transport.connectError = HubError.bluetoothUnavailable
        let host = HubMCPServer { _, _, _ in MoveHub(transport: transport) }
        let failed = try await host.call(.init(name: "hub_connect"))
        #expect(failed.isError == true)
        transport.connectError = nil
        let retry = try await host.call(.init(name: "hub_connect"))
        #expect(retry.isError == false)
        host.shutdown()
        let closed = try await host.call(.init(name: "hub_connect"))
        #expect(closed.isError == true)
        #expect(!transport.isConnected)
    }
}

@MainActor
private final class FakeTransport: HubTransport {
    var isConnected = false
    var device: HubDevice? { isConnected ? .init(identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Test Hub") : nil }
    var onNotification: ((Data) -> Void)?
    var onDisconnect: (((any Error)?) -> Void)?
    var onWrite: (() -> Void)?
    var connectError: (any Error)?
    var packets: [Data] = []
    func connect() async throws {
        if let connectError { throw connectError }
        isConnected = true
    }
    func disconnect() { isConnected = false; onDisconnect?(nil) }
    func write(_ data: Data) async throws {
        packets.append(data)
        onWrite?()
    }
}
#endif
