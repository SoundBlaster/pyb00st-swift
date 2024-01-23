import Foundation

/// Constants
class Constants {

    // MARK: - Bluetooth IDs

    static let MOVE_HUB_HARDWARE_HANDLE: UInt8 = 0x0E
    static let MOVE_HUB_HARDWARE_UUID = "00001624-1212-efde-1623-785feabcd123"

    // MARK: - Ports

    static let PORT_A: UInt8 = 0x37
    static let PORT_B: UInt8 = 0x38
    static let PORT_C: UInt8 = 0x01
    static let PORT_D: UInt8 = 0x02
    static let PORT_TILT: UInt8 = 0x3A

    // MARK: - Device Types

    static let TYPE_NONE: UInt8 = 0x00
    static let TYPE_WEDO2MOTOR: UInt8 = 0x01
    static let TYPE_LED: UInt8 = 0x17
    static let TYPE_WEDO2TILT: UInt8 = 0x22
    static let TYPE_WEDO2DISTANCE: UInt8 = 0x23
    static let TYPE_COLORDISTANCE: UInt8 = 0x25
    static let TYPE_ENCODERMOTOR: UInt8 = 0x26
    static let TYPE_MOTOR: UInt8 = 0x27
    static let TYPE_HUBTILT: UInt8 = 0x28

    // MARK: - Commands for setting RGB LED color

    static let SET_LED_OFF         = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x00])
    static let SET_LED_PINK        = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x01])
    static let SET_LED_PURPLE      = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x02])
    static let SET_LED_BLUE        = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x03])
    static let SET_LED_LIGHTBLUE   = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x04])
    static let SET_LED_CYAN        = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x05])
    static let SET_LED_GREEN       = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x06])
    static let SET_LED_YELLOW      = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x07])
    static let SET_LED_ORANGE      = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x08])
    static let SET_LED_RED         = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x09])
    static let SET_LED_WHITE       = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x0A])

    /// All LED colors in one Array for enumerating.
    static var SET_LED_COLOR: [Data] = {
        [
            Constants.SET_LED_OFF,
            Constants.SET_LED_PINK,
            Constants.SET_LED_PURPLE,
            Constants.SET_LED_BLUE,
            Constants.SET_LED_LIGHTBLUE,
            Constants.SET_LED_CYAN,
            Constants.SET_LED_GREEN,
            Constants.SET_LED_YELLOW,
            Constants.SET_LED_ORANGE,
            Constants.SET_LED_RED,
            Constants.SET_LED_WHITE,
        ]
    }()

    /// Colors strings.
    static let LED_COLORS = ["OFF", "PINK", "PURPLE", "BLUE", "LIGHTBLUE", "CYAN", "GREEN", "YELLOW", "ORANGE", "RED", "WHITE"]

    // MARK: - Motors

    static let MOTOR_A     = Data([0x37])
    static let MOTOR_B     = Data([0x38])
    static let MOTOR_AB    = Data([0x39])
    static let MOTOR_C     = Data([0x01])
    static let MOTOR_D     = Data([0x02])

    /// A group of all single motors.
    static var MOTORS: [Data] = {
        [
            Constants.MOTOR_A,
            Constants.MOTOR_B,
            Constants.MOTOR_AB,
            Constants.MOTOR_C,
            Constants.MOTOR_D,
        ]
    }()

    /// A group of 1 is silly but there might be other pairs in the future.
    static var MOTOR_PAIRS: [Data] = {
        [Constants.MOTOR_AB]
    }()

    // MARK: - Commands for Interactive Motors (Timed)

    // Motor A, B, C, D: 12-byte commands
    // Motor AB: 13-byte commands

    static let MOTOR_TIMED_INI     = Data([0x0c, 0x01, 0x81])
    static let MOTOR_TIMED_MID     = Data([0x11, 0x09])
    static let MOTOR_TIMED_END     = Data([0x64, 0x7f, 0x03])
    static let MOTORS_TIMED_INI    = Data([0x0d, 0x01, 0x81])
    static let MOTORS_TIMED_MID    = Data([0x11, 0x0A])
    static let MOTORS_TIMED_END    = Data([0x64, 0x7f, 0x03])

    // MARK: - Commands for Interactive Motors (Angle)

    // Motor A, B, C, D: 14-byte commands
    // Motor AB: 15-byte commands

    static let MOTOR_ANGLE_INI     = Data([0x0e, 0x01, 0x81])
    static let MOTOR_ANGLE_MID     = Data([0x11, 0x0b])
    static let MOTOR_ANGLE_END     = Data([0x64, 0x7f, 0x03])
    static let MOTORS_ANGLE_INI    = Data([0x0f, 0x01, 0x81])
    static let MOTORS_ANGLE_MID    = Data([0x11, 0x0c])
    static let MOTORS_ANGLE_END    = Data([0x64, 0x7f, 0x03])

    // MARK: - Commands for WeDo Motors (just Duty Cycle)

    static let MOTOR_WEDO_INI = Data([0x08, 0x00, 0x81])
    static let MOTOR_WEDO_MID = Data([0x11, 0x51, 0x00])

    // MARK: - Commands that initializing sensors in certain Modes

    static let LISTEN_INI       = Data([0x0a, 0x00, 0x41])
    static let LISTEN_END       = Data([0x01, 0x00, 0x00, 0x00, 0x01])
    static let LISTEN_BUTTON    = Data([0x05, 0x00, 0x01, 0x02, 0x02])

    static let MODE_COLORDIST_SENSOR   = Data([0x08])
    static let MODE_ENCODER            = Data([0x02])
    static let MODE_HUBTILT_BASIC      = Data([0x02])
    static let MODE_HUBTILT_FULL       = Data([0x00])

    // WeDo 2.0 Tilt Sensor modes:
    // 0 = angle
    // 1 = tilt
    // 2 = crash
    // 3 = some variation of angle
    // modes 0,1,2 like WeDo 2.0 modes

    static let MODE_WEDOTILT_ANGLE     = Data([0x00])
    static let MODE_WEDOTILT_TILT      = Data([0x01])
    static let MODE_WEDOTILT_CRASH     = Data([0x02])
    static let MODE_WEDODIST_DISTANCE  = Data([0x00])

    // WeDo 2.0 Distance Sensor modes:
    // 0 = distance 00..0A
    // 1 = increments when blocked
    // 2 = distance and luminosity ?
    // all continuous reading
    // just using mode 0 = distance

    static let MODE_WEDODIST_1 = Data([0x01])
    static let MODE_WEDODIST_2 = Data([0x02])

    // MARK: - Sensor Colors

    static let COLOR_SENSOR_COLORS = ["BLACK", "", "", "BLUE", "", "GREEN", "", "YELLOW", "", "RED", "WHITE"]

    // MARK: - Encoder

    static let ENCODER_MID: UInt = 2147483648
    static let ENCODER_MAX: UInt = 4294967296

    // MARK: - Button

    static let BUTTON_PRESSED  = Data([0x01])
    static let BUTTON_RELEASED = Data([0x00])

    // MARK: - BOOST Tilt Sensor
    static let TILT_HORIZ: UInt8 = 0x00
    static let TILT_UP: UInt8 = 0x01
    static let TILT_DOWN: UInt8 = 0x02
    static let TILT_RIGHT: UInt8 = 0x03
    static let TILT_LEFT: UInt8 = 0x04
    static let TILT_INVERT: UInt8 = 0x05

    static var TILT_BASIC_VALUES: [UInt8] = {
        [
            Constants.TILT_HORIZ,
            Constants.TILT_UP,
            Constants.TILT_DOWN,
            Constants.TILT_RIGHT,
            Constants.TILT_LEFT,
            Constants.TILT_INVERT,
        ]
    }()

    static let TILT_BASIC_TEXT = ["TILT_HORIZ", "TILT_UP", "TILT_DOWN", "TILT_RIGHT", "TILT_LEFT", "TILT_INVERT"]

    // MARK: - WeDo 2.0 Tilt Sensor

    static let WEDO_TILT_HORIZ: UInt8 = 0x00
    static let WEDO_TILT_LEFT: UInt8 = 0x07
    static let WEDO_TILT_RIGHT: UInt8 = 0x05
    static let WEDO_TILT_UP: UInt8 = 0x03
    static let WEDO_TILT_DOWN: UInt8 = 0x09

}
