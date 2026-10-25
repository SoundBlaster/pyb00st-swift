import Foundation

/// A Move Hub input port, using the wire identifiers of current BOOST firmware.
public enum HubPort: UInt8, CaseIterable, Sendable {
    case a = 0x00
    case b = 0x01
    case c = 0x02
    case d = 0x03
    case tilt = 0x3A

    var isExternal: Bool { self == .c || self == .d }
}

/// An interactive motor output. Use the paired methods to drive A and B together.
public enum HubMotor: UInt8, CaseIterable, Sendable {
    case a = 0x00
    case b = 0x01
    case c = 0x02
    case d = 0x03
}

/// The hub light's indexed colors.
public enum HubColor: UInt8, CaseIterable, Sendable {
    case off, pink, purple, blue, lightBlue, cyan, green, yellow, orange, red, white
}

/// Colors recognized by the external BOOST color/distance sensor.
public enum SensorColor: UInt8, CaseIterable, Sendable {
    case black = 0
    case blue = 3
    case green = 5
    case yellow = 7
    case red = 9
    case white = 10
}

/// The hub tilt sensor's six basic orientations.
public enum HubTilt: UInt8, CaseIterable, Sendable {
    case horizontal, up, down, right, left, inverted
}

/// WeDo 2.0 tilt sensor input modes.
public enum WeDoTiltMode: UInt8, CaseIterable, Sendable {
    case angle = 0
    case tilt = 1
    case crash = 2
}

/// A WeDo 2.0 tilt sensor's basic orientation.
public enum WeDoTilt: UInt8, CaseIterable, Sendable {
    case horizontal = 0
    case left = 7
    case right = 5
    case up = 3
    case down = 9
}

/// A sensor configuration supported by the original pyb00st implementation.
public enum HubSensor: Equatable, Sendable {
    case colorDistance
    case encoder
    case hubTilt
    case weDoTilt(WeDoTiltMode)
    case weDoDistance

    var mode: UInt8 {
        switch self {
        case .colorDistance: 8
        case .encoder, .hubTilt: 2
        case .weDoTilt(let mode): mode.rawValue
        case .weDoDistance: 0
        }
    }

    func validate(port: HubPort) throws {
        switch self {
        case .hubTilt:
            guard port == .tilt else { throw HubError.invalidPort(port) }
        case .encoder:
            guard port != .tilt else { throw HubError.invalidPort(port) }
        case .colorDistance, .weDoTilt, .weDoDistance:
            guard port.isExternal else { throw HubError.invalidPort(port) }
        }
    }
}

/// An Apple Bluetooth peripheral identity. This UUID is not a Bluetooth MAC address.
public struct HubDevice: Equatable, Sendable {
    public let identifier: UUID
    public let name: String?

    public init(identifier: UUID, name: String?) {
        self.identifier = identifier
        self.name = name
    }
}

/// A decoded notification. Unknown color and orientation values are represented by `nil`.
public enum HubEvent: Equatable, Sendable {
    case button(isPressed: Bool)
    case angle(port: HubPort, degrees: Int32)
    case colorDistance(port: HubPort, color: SensorColor?, distance: UInt8?)
    case hubTilt(HubTilt?)
    case weDoAngles(port: HubPort, roll: Int8, pitch: Int8)
    case weDoTilt(port: HubPort, orientation: WeDoTilt?)
    case weDoCrash(port: HubPort, x: UInt8, y: UInt8, z: UInt8)
    case weDoDistance(port: HubPort, distance: UInt8)
    case detached(port: HubPort)
    case hubError(command: UInt8, code: UInt8)
}

/// The most recent reading for a configured input port.
public struct HubPortValues: Equatable, Sendable {
    public internal(set) var angle: Int32?
    public internal(set) var color: SensorColor?
    public internal(set) var distance: UInt8?
    public internal(set) var roll: Int8?
    public internal(set) var pitch: Int8?
    public internal(set) var weDoTilt: WeDoTilt?
    public internal(set) var crash: [UInt8]?
    public internal(set) var weDoDistance: UInt8?

    public init() {}
}

/// A snapshot of notifications received during the current connection.
public struct HubValues: Equatable, Sendable {
    public internal(set) var ports: [HubPort: HubPortValues] = [:]
    public internal(set) var isButtonPressed: Bool?
    public internal(set) var tilt: HubTilt?

    public init() {}
}

/// Validation, protocol, and Bluetooth failures.
public enum HubError: Error, Equatable, Sendable {
    case invalidPort(HubPort)
    case invalidDutyCycle(Int)
    case invalidDuration(Int)
    case invalidAngle(Int)
    case invalidTimeout
    case notConnected
    case connectionInProgress
    case configurationInProgress(HubPort)
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case timedOut
    case missingCharacteristic
    case malformedNotification
    case transport(String)
}

extension HubError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port): "Unsupported sensor or motor on port \(port)."
        case .invalidDutyCycle(let value): "Duty cycle \(value) is outside -100...100."
        case .invalidDuration(let value): "Duration \(value) is outside 0...65535 milliseconds."
        case .invalidAngle(let value): "Angle \(value) is outside 0...4294967295 degrees."
        case .invalidTimeout: "Timeout must be finite and within 0...3600 seconds, excluding zero."
        case .notConnected: "The Move Hub is not connected."
        case .connectionInProgress: "A connection is already in progress."
        case .configurationInProgress(let port): "A sensor configuration is already in progress on port \(port)."
        case .bluetoothUnavailable: "Bluetooth is unavailable or powered off."
        case .bluetoothUnauthorized: "Bluetooth access is not authorized."
        case .timedOut: "The Bluetooth operation timed out."
        case .missingCharacteristic: "The LEGO service or its writable notification characteristic is missing."
        case .malformedNotification: "The hub sent a truncated or malformed notification."
        case .transport(let message): message
        }
    }
}
