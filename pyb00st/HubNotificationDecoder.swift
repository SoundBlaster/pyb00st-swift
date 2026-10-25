import Foundation

/// Decodes bounded, single-message notifications using each port's selected sensor mode.
public struct HubNotificationDecoder: Sendable {
    public private(set) var values = HubValues()
    public private(set) var sensors: [HubPort: HubSensor] = [:]

    public init() {}

    /// Select the interpretation of future notifications and discard readings from the previous mode.
    public mutating func configure(_ sensor: HubSensor, on port: HubPort) throws {
        try sensor.validate(port: port)
        sensors[port] = sensor
        values.ports[port] = nil
        if port == .tilt { values.tilt = nil }
    }

    /// Remove the selected mode and cached reading for a port.
    public mutating func removeSensor(on port: HubPort) {
        sensors[port] = nil
        values.ports[port] = nil
        if port == .tilt { values.tilt = nil }
    }

    /// Decode and cache one notification. Unknown message types and unconfigured inputs return `nil`.
    /// Malformed supported messages throw without changing cached readings.
    public mutating func decode(_ data: Data) throws -> HubEvent? {
        // Copy to zero-based bytes: Data slices do not necessarily start at index zero.
        let bytes = Array(data)
        guard bytes.count >= 3, Int(bytes[0]) == bytes.count, bytes[1] == 0 else {
            throw HubError.malformedNotification
        }
        switch bytes[2] {
        case 1:
            guard bytes.count >= 5 else { throw HubError.malformedNotification }
            guard bytes[3] == 2, bytes[4] == 6 else { return nil }
            guard bytes.count == 6, bytes[5] <= 1 else { throw HubError.malformedNotification }
            let pressed = bytes[5] == 1
            values.isButtonPressed = pressed
            return .button(isPressed: pressed)
        case 4:
            guard bytes.count >= 5 else { throw HubError.malformedNotification }
            guard bytes[4] == 0, let port = HubPort(rawValue: bytes[3]) else { return nil }
            guard bytes.count == 5 else { throw HubError.malformedNotification }
            removeSensor(on: port)
            return .detached(port: port)
        case 5:
            guard bytes.count == 5 else { throw HubError.malformedNotification }
            return .hubError(command: bytes[3], code: bytes[4])
        case 0x45:
            guard bytes.count >= 5 else { throw HubError.malformedNotification }
            guard let port = HubPort(rawValue: bytes[3]), let sensor = sensors[port] else { return nil }
            return try decodeValue(Array(bytes.dropFirst(4)), sensor: sensor, port: port)
        default:
            return nil
        }
    }

    private mutating func decodeValue(_ payload: [UInt8], sensor: HubSensor, port: HubPort) throws -> HubEvent {
        var reading = values.ports[port] ?? HubPortValues()
        let event: HubEvent
        switch sensor {
        case .encoder:
            guard payload.count == 4 else { throw HubError.malformedNotification }
            let bits = payload.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
            let angle = Int32(bitPattern: bits)
            reading.angle = angle
            event = .angle(port: port, degrees: angle)
        case .colorDistance:
            guard payload.count == 4 else { throw HubError.malformedNotification }
            reading.color = SensorColor(rawValue: payload[0])
            reading.distance = payload[0] == 0xFF ? payload[1] : nil
            event = .colorDistance(port: port, color: reading.color, distance: reading.distance)
        case .hubTilt:
            guard payload.count == 1 else { throw HubError.malformedNotification }
            values.tilt = HubTilt(rawValue: payload[0])
            event = .hubTilt(values.tilt)
        case .weDoTilt(.angle):
            guard payload.count == 2 else { throw HubError.malformedNotification }
            reading.roll = Int8(bitPattern: payload[0])
            reading.pitch = Int8(bitPattern: payload[1])
            event = .weDoAngles(port: port, roll: Int8(bitPattern: payload[0]), pitch: Int8(bitPattern: payload[1]))
        case .weDoTilt(.tilt):
            guard payload.count == 1 else { throw HubError.malformedNotification }
            reading.weDoTilt = WeDoTilt(rawValue: payload[0])
            event = .weDoTilt(port: port, orientation: reading.weDoTilt)
        case .weDoTilt(.crash):
            guard payload.count == 3 else { throw HubError.malformedNotification }
            reading.crash = payload
            event = .weDoCrash(port: port, x: payload[0], y: payload[1], z: payload[2])
        case .weDoDistance:
            guard payload.count == 1 else { throw HubError.malformedNotification }
            reading.weDoDistance = payload[0]
            event = .weDoDistance(port: port, distance: payload[0])
        }
        values.ports[port] = reading
        return event
    }
}
