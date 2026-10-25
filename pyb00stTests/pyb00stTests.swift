import Foundation
import Testing
@testable import pyb00st

struct CommandTests {
    // Current Move Hub firmware reports A/B/C/D as 0/1/2/3, and the built-in
    // A+B virtual motor as 0x10. These vectors intentionally use wire IDs,
    // independently of the enum raw values, to catch obsolete 2017 addresses.
    @Test(arguments: [(HubMotor.a, UInt8(0)), (.b, 1), (.c, 2), (.d, 3)])
    func currentFirmwareMotorAddresses(_ fixture: (HubMotor, UInt8)) throws {
        #expect(try HubCommand.motorForTime(fixture.0, milliseconds: 500, dutyCycle: 30)[3] == fixture.1)
        #expect(try HubCommand.motorForAngle(fixture.0, degrees: 90, dutyCycle: 30)[3] == fixture.1)
    }

    @Test func currentFirmwarePairAddress() throws {
        #expect(try HubCommand.motorsForTime(milliseconds: 500, dutyCycleA: 30, dutyCycleB: 30)[3] == 0x10)
        #expect(try HubCommand.motorsForAngle(degrees: 90, dutyCycleA: 30, dutyCycleB: 30)[3] == 0x10)
    }

    @Test(arguments: HubColor.allCases)
    func lightColors(_ color: HubColor) {
        #expect(HubCommand.hubLight(color) == Data([8, 0, 0x81, 0x32, 0x11, 0x51, 0, color.rawValue]))
    }

    @Test func goldenMotorPackets() throws {
        #expect(try HubCommand.motorForTime(.a, milliseconds: 1000, dutyCycle: -100) ==
                Data([0x0C, 0, 0x81, 0, 0x11, 9, 0xE8, 3, 0x9C, 0x64, 0x7F, 3]))
        #expect(try HubCommand.motorsForTime(milliseconds: 65535, dutyCycleA: -1, dutyCycleB: 100) ==
                Data([0x0D, 0, 0x81, 0x10, 0x11, 0x0A, 0xFF, 0xFF, 0xFF, 0x64, 0x64, 0x7F, 3]))
        #expect(try HubCommand.motorForAngle(.d, degrees: 0x12345678, dutyCycle: 75) ==
                Data([0x0E, 0, 0x81, 3, 0x11, 0x0B, 0x78, 0x56, 0x34, 0x12, 0x4B, 0x64, 0x7F, 3]))
        #expect(try HubCommand.motorsForAngle(degrees: 360, dutyCycleA: 50, dutyCycleB: -50) ==
                Data([0x0F, 0, 0x81, 0x10, 0x11, 0x0C, 0x68, 1, 0, 0, 0x32, 0xCE, 0x64, 0x7F, 3]))
        #expect(try HubCommand.weDoMotor(on: .c, dutyCycle: -1) == Data([8, 0, 0x81, 2, 0x11, 0x51, 0, 0xFF]))
    }

    @Test(arguments: HubMotor.allCases)
    func individualMotorPorts(_ motor: HubMotor) throws {
        let time = try HubCommand.motorForTime(motor, milliseconds: 0, dutyCycle: 0)
        let angle = try HubCommand.motorForAngle(motor, degrees: 0, dutyCycle: 0)
        #expect(time[3] == motor.rawValue)
        #expect(angle[3] == motor.rawValue)
        #expect(time[0] == time.count)
        #expect(angle[0] == angle.count)
    }

    @Test(arguments: [-100, -99, -1, 0, 1, 99, 100])
    func signedSpeeds(_ speed: Int) throws {
        let packet = try HubCommand.motorForTime(.b, milliseconds: 256, dutyCycle: speed)
        #expect(Int(Int8(bitPattern: packet[8])) == speed)
        #expect(Array(packet[6...7]) == [0, 1])
    }

    @Test(arguments: [-101, 101, Int.min, Int.max])
    func invalidSpeeds(_ speed: Int) {
        #expect(throws: HubError.invalidDutyCycle(speed)) { try HubCommand.motorForTime(.a, milliseconds: 0, dutyCycle: speed) }
        #expect(throws: HubError.invalidDutyCycle(speed)) { try HubCommand.motorsForTime(milliseconds: 0, dutyCycleA: speed, dutyCycleB: 0) }
        #expect(throws: HubError.invalidDutyCycle(speed)) { try HubCommand.motorsForAngle(degrees: 0, dutyCycleA: 0, dutyCycleB: speed) }
        #expect(throws: HubError.invalidDutyCycle(speed)) { try HubCommand.weDoMotor(on: .d, dutyCycle: speed) }
    }

    @Test(arguments: [-1, 65536, Int.max])
    func invalidTimes(_ time: Int) {
        #expect(throws: HubError.invalidDuration(time)) { try HubCommand.motorForTime(.a, milliseconds: time, dutyCycle: 0) }
        #expect(throws: HubError.invalidDuration(time)) { try HubCommand.motorsForTime(milliseconds: time, dutyCycleA: 0, dutyCycleB: 0) }
    }

    @Test func angleBounds() throws {
        #expect(try Array(HubCommand.motorForAngle(.a, degrees: Int(UInt32.max), dutyCycle: 0)[6...9]) == [255, 255, 255, 255])
        for angle in [-1, Int(UInt32.max) + 1, Int.max] {
            #expect(throws: HubError.invalidAngle(angle)) { try HubCommand.motorForAngle(.a, degrees: angle, dutyCycle: 0) }
            #expect(throws: HubError.invalidAngle(angle)) { try HubCommand.motorsForAngle(degrees: angle, dutyCycleA: 0, dutyCycleB: 0) }
        }
    }

    @Test func sensorPacketsAndPortValidation() throws {
        let cases: [(HubSensor, HubPort, Data)] = [
            (.colorDistance, .c, Data([10, 0, 0x41, 2, 8, 1, 0, 0, 0, 1])),
            (.encoder, .a, Data([10, 0, 0x41, 0, 2, 1, 0, 0, 0, 1])),
            (.hubTilt, .tilt, Data([10, 0, 0x41, 0x3A, 2, 1, 0, 0, 0, 1])),
            (.weDoTilt(.angle), .c, Data([10, 0, 0x41, 2, 0, 1, 0, 0, 0, 1])),
            (.weDoTilt(.tilt), .d, Data([10, 0, 0x41, 3, 1, 1, 0, 0, 0, 1])),
            (.weDoTilt(.crash), .c, Data([10, 0, 0x41, 2, 2, 1, 0, 0, 0, 1])),
            (.weDoDistance, .d, Data([10, 0, 0x41, 3, 0, 1, 0, 0, 0, 1])),
        ]
        for (sensor, port, expected) in cases {
            #expect(try HubCommand.sensor(sensor, on: port) == expected)
            var disabled = expected
            disabled[9] = 0
            #expect(try HubCommand.sensor(sensor, on: port, enabled: false) == disabled)
        }
        #expect(HubCommand.listenButton == Data([5, 0, 1, 2, 2]))
        for port in [HubPort.a, .b, .tilt] {
            #expect(throws: HubError.invalidPort(port)) { try HubCommand.weDoMotor(on: port, dutyCycle: 0) }
            for sensor in [HubSensor.colorDistance, .weDoTilt(.angle), .weDoDistance] {
                #expect(throws: HubError.invalidPort(port)) { try HubCommand.sensor(sensor, on: port) }
            }
        }
        #expect(throws: HubError.invalidPort(.tilt)) { try HubCommand.sensor(.encoder, on: .tilt) }
        #expect(throws: HubError.invalidPort(.c)) { try HubCommand.sensor(.hubTilt, on: .c) }
    }
}

struct DecoderTests {
    @Test func currentFirmwareEncoderNotifications() throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.encoder, on: .a)
        try decoder.configure(.encoder, on: .b)
        #expect(try decoder.decode(Data([8, 0, 0x45, 0, 90, 0, 0, 0])) == .angle(port: .a, degrees: 90))
        #expect(try decoder.decode(Data([8, 0, 0x45, 1, 0xA6, 0xFF, 0xFF, 0xFF])) == .angle(port: .b, degrees: -90))
    }

    @Test(arguments: [HubPort.a, .b, .c, .d], [Int32.min, -360, -1, 0, 360, Int32.max])
    func signedEncoder(_ port: HubPort, _ angle: Int32) throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.encoder, on: port)
        let bits = UInt32(bitPattern: angle)
        let payload = (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        #expect(try decoder.decode(Data([8, 0, 0x45, port.rawValue] + payload)) == .angle(port: port, degrees: angle))
        #expect(decoder.values.ports[port]?.angle == angle)
    }

    @Test(arguments: [HubPort.c, .d])
    func colorDistance(_ port: HubPort) throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.colorDistance, on: port)
        for color in SensorColor.allCases {
            #expect(try decoder.decode(Data([8, 0, 0x45, port.rawValue, color.rawValue, 0, 0, 0])) ==
                    .colorDistance(port: port, color: color, distance: nil))
        }
        #expect(try decoder.decode(Data([8, 0, 0x45, port.rawValue, 0xFF, 7, 0, 0])) ==
                .colorDistance(port: port, color: nil, distance: 7))
        #expect(decoder.values.ports[port]?.color == nil)
        #expect(try decoder.decode(Data([8, 0, 0x45, port.rawValue, 0xFE, 7, 0, 0])) ==
                .colorDistance(port: port, color: nil, distance: nil))
        #expect(decoder.values.ports[port]?.distance == nil)
    }

    @Test(arguments: [HubPort.c, .d])
    func weDoModes(_ port: HubPort) throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.weDoTilt(.angle), on: port)
        #expect(try decoder.decode(Data([6, 0, 0x45, port.rawValue, 0xFF, 0x80])) ==
                .weDoAngles(port: port, roll: -1, pitch: -128))
        try decoder.configure(.weDoTilt(.tilt), on: port)
        #expect(decoder.values.ports[port] == nil)
        for tilt in WeDoTilt.allCases {
            #expect(try decoder.decode(Data([5, 0, 0x45, port.rawValue, tilt.rawValue])) == .weDoTilt(port: port, orientation: tilt))
        }
        #expect(try decoder.decode(Data([5, 0, 0x45, port.rawValue, 0xFF])) == .weDoTilt(port: port, orientation: nil))
        try decoder.configure(.weDoTilt(.crash), on: port)
        #expect(try decoder.decode(Data([7, 0, 0x45, port.rawValue, 1, 2, 100])) == .weDoCrash(port: port, x: 1, y: 2, z: 100))
        #expect(decoder.values.ports[port]?.crash == [1, 2, 100])
        try decoder.configure(.weDoDistance, on: port)
        #expect(try decoder.decode(Data([5, 0, 0x45, port.rawValue, 10])) == .weDoDistance(port: port, distance: 10))
        #expect(decoder.values.ports[port]?.weDoDistance == 10)
    }

    @Test func independentExternalPorts() throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.weDoDistance, on: .c)
        try decoder.configure(.weDoTilt(.tilt), on: .d)
        #expect(try decoder.decode(Data([5, 0, 0x45, 2, 8])) == .weDoDistance(port: .c, distance: 8))
        #expect(try decoder.decode(Data([5, 0, 0x45, 3, 7])) == .weDoTilt(port: .d, orientation: .left))
        #expect(decoder.values.ports[.c]?.weDoDistance == 8)
    }

    @Test func buttonAndTilt() throws {
        var decoder = HubNotificationDecoder()
        #expect(try decoder.decode(Data([6, 0, 1, 2, 6, 1])) == .button(isPressed: true))
        #expect(try decoder.decode(Data([6, 0, 1, 2, 6, 0])) == .button(isPressed: false))
        #expect(decoder.values.isButtonPressed == false)
        try decoder.configure(.hubTilt, on: .tilt)
        for tilt in HubTilt.allCases {
            #expect(try decoder.decode(Data([5, 0, 0x45, 0x3A, tilt.rawValue])) == .hubTilt(tilt))
        }
        #expect(try decoder.decode(Data([5, 0, 0x45, 0x3A, 255])) == .hubTilt(nil))
        #expect(decoder.values.tilt == nil)
    }

    @Test func malformedPacketsPreserveValues() throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.encoder, on: .a)
        let valid = Data([8, 0, 0x45, 0, 1, 0, 0, 0])
        _ = try decoder.decode(valid)
        let snapshot = decoder.values
        for count in 0..<valid.count {
            #expect(throws: HubError.malformedNotification) { try decoder.decode(valid.prefix(count)) }
        }
        for length in 0...255 where length != 8 {
            var packet = valid
            packet[0] = UInt8(length)
            #expect(throws: HubError.malformedNotification) { try decoder.decode(packet) }
        }
        for packet in [Data([3, 0, 0x45]), Data([5, 0, 0x45, 0, 0]), Data([6, 0, 1, 2, 6, 2]),
                       Data([8, 1, 0x45, 0, 0, 0, 0, 0]), Data([6, 0, 4, 0, 0, 0])] {
            #expect(throws: HubError.malformedNotification) { try decoder.decode(packet) }
        }
        #expect(decoder.values == snapshot)
    }

    @Test func dataSlicesAndUnknownMessages() throws {
        var decoder = HubNotificationDecoder()
        let storage = Data([255, 6, 0, 1, 2, 6, 1])
        #expect(try decoder.decode(storage.dropFirst()) == .button(isPressed: true))
        #expect(try decoder.decode(Data([3, 0, 0xFF])) == nil)
        #expect(try decoder.decode(Data([5, 0, 0x45, 0xFF, 0])) == nil)
        #expect(try decoder.decode(Data([5, 0, 0x45, 2, 0])) == nil)
        #expect(try decoder.decode(Data([5, 0, 5, 0x81, 6])) == .hubError(command: 0x81, code: 6))
    }

    @Test func detachmentClearsConfiguration() throws {
        var decoder = HubNotificationDecoder()
        try decoder.configure(.encoder, on: .c)
        _ = try decoder.decode(Data([8, 0, 0x45, 2, 90, 0, 0, 0]))
        #expect(try decoder.decode(Data([5, 0, 4, 2, 0])) == .detached(port: .c))
        #expect(decoder.values.ports[.c] == nil)
        #expect(decoder.sensors[.c] == nil)
        #expect(try decoder.decode(Data([8, 0, 0x45, 2, 90, 0, 0, 0])) == nil)
    }
}

@MainActor
private final class MockTransport: HubTransport {
    var isConnected = false
    var device: HubDevice?
    var onNotification: ((Data) -> Void)?
    var onDisconnect: (((any Error)?) -> Void)?
    var packets: [Data] = []
    var writeHook: ((Data) async throws -> Void)?
    var connectFailure: HubError?

    func connect() async throws {
        try Task.checkCancellation()
        if let connectFailure { throw connectFailure }
        isConnected = true
        device = HubDevice(identifier: UUID(), name: "Mock Move Hub")
    }

    func disconnect() {
        isConnected = false
        device = nil
        onDisconnect?(nil)
    }

    func write(_ data: Data) async throws {
        packets.append(data)
        try await writeHook?(data)
    }
}

@MainActor
struct MoveHubTests {
    @Test func disconnectedCommandsAndConnectionFailures() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        await #expect(throws: HubError.notConnected) { try await hub.setHubLight(.red) }
        #expect(transport.packets.isEmpty)
        transport.connectFailure = .timedOut
        await #expect(throws: HubError.timedOut) { try await hub.start() }
        #expect(!hub.isConnected)
    }

    @Test func commandsReachTheTransport() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        #expect(hub.device?.name == "Mock Move Hub")
        try await hub.setHubLight(.red)
        try await hub.runMotorForTime(.a, milliseconds: 1000, dutyCycle: 50)
        try await hub.runMotorsForTime(milliseconds: 1000, dutyCycleA: -50, dutyCycleB: 50)
        try await hub.runMotorForAngle(.c, degrees: 360, dutyCycle: 50)
        try await hub.runMotorsForAngle(degrees: 360, dutyCycleA: 50, dutyCycleB: 50)
        try await hub.runWeDoMotor(on: .d, dutyCycle: 0)
        try await hub.listenButton()
        #expect(transport.packets.count == 7)
        #expect(transport.packets.first == Constants.SET_LED_RED)
        #expect(transport.packets.last == HubCommand.listenButton)
    }

    @Test func notificationsCanArriveBeforeWriteAcknowledgment() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        var events: [HubEvent] = []
        hub.onEvent = { events.append($0) }
        transport.writeHook = { _ in transport.onNotification?(Data([8, 0, 0x45, 2, 0xFF, 0xFF, 0xFF, 0xFF])) }
        try await hub.listen(to: .encoder, on: .c)
        #expect(hub.values.ports[.c]?.angle == -1)
        #expect(events == [.angle(port: .c, degrees: -1)])
        transport.writeHook = nil
        try await hub.stopListening(on: .c)
        #expect(transport.packets.last == Data([10, 0, 0x41, 2, 2, 1, 0, 0, 0, 0]))
        #expect(hub.values.ports[.c] == nil)
        hub.stop()
        #expect(!hub.isConnected)
        #expect(hub.values == HubValues())
    }

    @Test func decodingErrorsAreReportedWithoutLosingConnection() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        var reported: HubError?
        hub.onError = { reported = $0 as? HubError }
        transport.onNotification?(Data())
        #expect(reported == .malformedNotification)
        #expect(hub.isConnected)
    }

    @Test func failedConfigurationClearsUncertainState() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        transport.writeHook = { _ in throw HubError.timedOut }
        await #expect(throws: HubError.timedOut) { try await hub.listen(to: .encoder, on: .a) }
        #expect(!hub.isConnected)
        #expect(hub.values == HubValues())
    }

    @Test func invalidConfigurationDoesNotWrite() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        await #expect(throws: HubError.invalidPort(.a)) { try await hub.listen(to: .colorDistance, on: .a) }
        #expect(transport.packets.isEmpty)
        #expect(hub.isConnected)
    }

    @Test func unexpectedDisconnectResetsReadings() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        transport.onNotification?(Data([6, 0, 1, 2, 6, 1]))
        var reported: HubError?
        hub.onDisconnect = { reported = $0 as? HubError }
        transport.isConnected = false
        transport.onDisconnect?(HubError.notConnected)
        #expect(reported == .notConnected)
        #expect(hub.values == HubValues())
        transport.onNotification?(Data([6, 0, 1, 2, 6, 1]))
        #expect(hub.values == HubValues())
    }

    @Test func canceledCommandDoesNotWrite() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await hub.listen(to: .encoder, on: .a)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(transport.packets.isEmpty)
        #expect(hub.isConnected)
    }

    @Test func pendingConfigurationRejectsConcurrentModeChanges() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var iterator = started.makeAsyncIterator()
        var pending: CheckedContinuation<Void, any Error>?
        transport.writeHook = { _ in
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                signal.yield(())
            }
        }
        let first = Task { try await hub.listen(to: .encoder, on: .c) }
        _ = await iterator.next()
        await #expect(throws: HubError.configurationInProgress(.c)) { try await hub.listen(to: .weDoDistance, on: .c) }
        await #expect(throws: HubError.configurationInProgress(.c)) { try await hub.stopListening(on: .c) }
        pending?.resume()
        try await first.value
        signal.finish()
    }

    @Test func oldFailedOperationDoesNotDisconnectNewSession() async throws {
        let transport = MockTransport()
        let hub = MoveHub(transport: transport)
        try await hub.start()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var iterator = started.makeAsyncIterator()
        var pending: CheckedContinuation<Void, any Error>?
        transport.writeHook = { _ in
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                signal.yield(())
            }
        }
        let old = Task { try await hub.listen(to: .encoder, on: .a) }
        _ = await iterator.next()
        hub.stop()
        try await hub.start()
        pending?.resume(throwing: HubError.notConnected)
        await #expect(throws: HubError.notConnected) { try await old.value }
        #expect(hub.isConnected)
        signal.finish()
    }
}

@MainActor
struct BluetoothValidationTests {
    @Test(arguments: [0.0, -1.0, Double.infinity, Double.nan, 3601.0])
    func invalidTimeoutDoesNotStartBluetooth(_ timeout: Double) async {
        let transport = CoreBluetoothTransport(timeout: timeout)
        await #expect(throws: HubError.invalidTimeout) { try await transport.connect() }
        #expect(!transport.isConnected)
    }

    @Test func manufacturerFiltering() {
        #expect(CoreBluetoothTransport.isBoostAdvertisement(Data([0x97, 3, 1, 0x40, 6, 0, 0, 0])))
        for data in [nil, Data(), Data([0x97, 3, 1]), Data([0x97, 3, 1, 0x41]), Data([0, 0, 1, 0x40])] {
            #expect(!CoreBluetoothTransport.isBoostAdvertisement(data))
        }
    }
}
