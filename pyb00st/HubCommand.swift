import Foundation

/// Encodes pyb00st commands without accessing Bluetooth.
public enum HubCommand {
    /// Set the hub's indexed RGB light color.
    public static func hubLight(_ color: HubColor) -> Data {
        Data([8, 0, 0x81, 0x32, 0x11, 0x51, 0, color.rawValue])
    }

    /// Run one interactive motor for a duration in milliseconds at -100...100 percent.
    public static func motorForTime(_ motor: HubMotor, milliseconds: Int, dutyCycle: Int) throws -> Data {
        let duration = try timeBytes(milliseconds)
        let speed = try speedByte(dutyCycle)
        return Data([12, 0, 0x81, motor.rawValue, 0x11, 9] + duration + [speed, 0x64, 0x7F, 3])
    }

    /// Run A and B together, allowing each motor to turn in either direction.
    public static func motorsForTime(milliseconds: Int, dutyCycleA: Int, dutyCycleB: Int) throws -> Data {
        let duration = try timeBytes(milliseconds)
        let a = try speedByte(dutyCycleA)
        let b = try speedByte(dutyCycleB)
        return Data([13, 0, 0x81, Constants.PORT_AB, 0x11, 0x0A] + duration + [a, b, 0x64, 0x7F, 3])
    }

    /// Run one motor through a nonnegative angle. The duty cycle supplies the direction.
    public static func motorForAngle(_ motor: HubMotor, degrees: Int, dutyCycle: Int) throws -> Data {
        let angle = try angleBytes(degrees)
        let speed = try speedByte(dutyCycle)
        return Data([14, 0, 0x81, motor.rawValue, 0x11, 0x0B] + angle + [speed, 0x64, 0x7F, 3])
    }

    /// Run paired motors A/B through a nonnegative angle.
    public static func motorsForAngle(degrees: Int, dutyCycleA: Int, dutyCycleB: Int) throws -> Data {
        let angle = try angleBytes(degrees)
        let a = try speedByte(dutyCycleA)
        let b = try speedByte(dutyCycleB)
        return Data([15, 0, 0x81, Constants.PORT_AB, 0x11, 0x0C] + angle + [a, b, 0x64, 0x7F, 3])
    }

    /// Set a WeDo 2.0 motor's duty cycle on C or D. Zero stops the motor.
    public static func weDoMotor(on port: HubPort, dutyCycle: Int) throws -> Data {
        guard port.isExternal else { throw HubError.invalidPort(port) }
        return Data([8, 0, 0x81, port.rawValue, 0x11, 0x51, 0, try speedByte(dutyCycle)])
    }

    /// Enable change notifications for one sensor, or disable them with `enabled: false`.
    public static func sensor(_ sensor: HubSensor, on port: HubPort, enabled: Bool = true) throws -> Data {
        try sensor.validate(port: port)
        return Data([10, 0, 0x41, port.rawValue, sensor.mode, 1, 0, 0, 0, enabled ? 1 : 0])
    }

    /// Enable hub button property notifications.
    public static let listenButton = Data([5, 0, 1, 2, 2])

    private static func speedByte(_ value: Int) throws -> UInt8 {
        guard (-100...100).contains(value) else { throw HubError.invalidDutyCycle(value) }
        return UInt8(bitPattern: Int8(value))
    }

    private static func timeBytes(_ value: Int) throws -> [UInt8] {
        guard let time = UInt16(exactly: value) else { throw HubError.invalidDuration(value) }
        return [UInt8(truncatingIfNeeded: time), UInt8(time >> 8)]
    }

    private static func angleBytes(_ value: Int) throws -> [UInt8] {
        guard let angle = UInt32(exactly: value) else { throw HubError.invalidAngle(value) }
        return (0..<4).map { UInt8(truncatingIfNeeded: angle >> ($0 * 8)) }
    }
}
