import Foundation

/// Constants
class Constants {

    // MARK: - Bluetooth IDs

    let MOVE_HUB_HARDWARE_HANDLE: UInt8 = 0x0E
    let MOVE_HUB_HARDWARE_UUID = "00001624-1212-efde-1623-785feabcd123"

    // MARK: - Ports

    let PORT_A: UInt8 = 0x37
    let PORT_B: UInt8 = 0x38
    let PORT_C: UInt8 = 0x01
    let PORT_D: UInt8 = 0x02
    let PORT_TILT: UInt8 = 0x3A

    // MARK: - Device Types

    let TYPE_NONE: UInt8 = 0x00
    let TYPE_WEDO2MOTOR: UInt8 = 0x01
    let TYPE_LED: UInt8 = 0x17
    let TYPE_WEDO2TILT: UInt8 = 0x22
    let TYPE_WEDO2DISTANCE: UInt8 = 0x23
    let TYPE_COLORDISTANCE: UInt8 = 0x25
    let TYPE_ENCODERMOTOR: UInt8 = 0x26
    let TYPE_MOTOR: UInt8 = 0x27
    let TYPE_HUBTILT: UInt8 = 0x28

    // MARK: - Commands for setting RGB LED color

    let SET_LED_OFF         = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x00])
    let SET_LED_PINK        = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x01])
    let SET_LED_PURPLE      = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x02])
    let SET_LED_BLUE        = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x03])
    let SET_LED_LIGHTBLUE   = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x04])
    let SET_LED_CYAN        = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x05])
    let SET_LED_GREEN       = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x06])
    let SET_LED_YELLOW      = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x07])
    let SET_LED_ORANGE      = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x08])
    let SET_LED_RED         = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x09])
    let SET_LED_WHITE       = Data([0x08, 0x00, 0x81, 0x32, 0x11, 0x51, 0x00, 0x0A])

    /// All LED colors in one Array for enumerating.
    lazy var setLEDColors: [Data] = {
        [
            SET_LED_OFF,
            SET_LED_PINK,
            SET_LED_PURPLE,
            SET_LED_BLUE,
            SET_LED_LIGHTBLUE,
            SET_LED_CYAN,
            SET_LED_GREEN,
            SET_LED_YELLOW,
            SET_LED_ORANGE,
            SET_LED_RED,
            SET_LED_WHITE,
        ]
    }()

    /// Colors strings.
    let ledColors = ["OFF", "PINK", "PURPLE", "BLUE", "LIGHTBLUE", "CYAN", "GREEN", "YELLOW", "ORANGE", "RED", "WHITE"]

    // MARK: - Motors

    let MOTOR_A     = Data([0x37])
    let MOTOR_B     = Data([0x38])
    let MOTOR_AB    = Data([0x39])
    let MOTOR_C     = Data([0x01])
    let MOTOR_D     = Data([0x02])

    /// A group of all single motors.
    lazy var MOTORS: [Data] = {
        [MOTOR_A, MOTOR_B, MOTOR_AB, MOTOR_C, MOTOR_D]
    }()

    /// A group of 1 is silly but there might be other pairs in the future.
    lazy var MOTOR_PAIRS: [Data] = {
        [MOTOR_AB]
    }()

    // MARK: - Commands for Interactive Motors (Timed)

    // Motor A, B, C, D: 12-byte commands
    // Motor AB: 13-byte commands

    let MOTOR_TIMED_INI     = Data([0x0c, 0x01, 0x81])
    let MOTOR_TIMED_MID     = Data([0x11, 0x09])
    let MOTOR_TIMED_END     = Data([0x64, 0x7f, 0x03])
    let MOTORS_TIMED_INI    = Data([0x0d, 0x01, 0x81])
    let MOTORS_TIMED_MID    = Data([0x11, 0x0A])
    let MOTORS_TIMED_END    = Data([0x64, 0x7f, 0x03])

    // MARK: - Commands for Interactive Motors (Angle)

    // Motor A, B, C, D: 14-byte commands
    // Motor AB: 15-byte commands

    let MOTOR_ANGLE_INI     = Data([0x0e, 0x01, 0x81])
    let MOTOR_ANGLE_MID     = Data([0x11, 0x0b])
    let MOTOR_ANGLE_END     = Data([0x64, 0x7f, 0x03])
    let MOTORS_ANGLE_INI    = Data([0x0f, 0x01, 0x81])
    let MOTORS_ANGLE_MID    = Data([0x11, 0x0c])
    let MOTORS_ANGLE_END    = Data([0x64, 0x7f, 0x03])

    // MARK: - Commands for WeDo Motors (just Duty Cycle)

    let MOTOR_WEDO_INI = Data([0x08, 0x00, 0x81])
    let MOTOR_WEDO_MID = Data([0x11, 0x51, 0x00])

    // MARK: - Commands that initializing sensors in certain Modes

    let LISTEN_INI       = Data([0x0a, 0x00, 0x41])
    let LISTEN_END       = Data([0x01, 0x00, 0x00, 0x00, 0x01])
    let LISTEN_BUTTON    = Data([0x05, 0x00, 0x01, 0x02, 0x02])

    let MODE_COLORDIST_SENSOR   = Data([0x08])
    let MODE_ENCODER            = Data([0x02])
    let MODE_HUBTILT_BASIC      = Data([0x02])
    let MODE_HUBTILT_FULL       = Data([0x00])

    // WeDo 2.0 Tilt Sensor modes:
    // 0 = angle
    // 1 = tilt
    // 2 = crash
    // 3 = some variation of angle
    // modes 0,1,2 like WeDo 2.0 modes

    let MODE_WEDOTILT_ANGLE     = Data([0x00])
    let MODE_WEDOTILT_TILT      = Data([0x01])
    let MODE_WEDOTILT_CRASH     = Data([0x02])
    let MODE_WEDODIST_DISTANCE  = Data([0x00])

    // WeDo 2.0 Distance Sensor modes:
    // 0 = distance 00..0A
    // 1 = increments when blocked
    // 2 = distance and luminosity ?
    // all continuous reading
    // just using mode 0 = distance

    let MODE_WEDODIST_1 = Data([0x01])
    let MODE_WEDODIST_2 = Data([0x02])

    // MARK: - Sensor Colors

    let COLOR_SENSOR_COLORS = ["BLACK", "", "", "BLUE", "", "GREEN", "", "YELLOW", "", "RED", "WHITE"]

    // MARK: - Encoder

    let ENCODER_MID: UInt = 2147483648
    let ENCODER_MAX: UInt = 4294967296

    // MARK: - Button

    let BUTTON_PRESSED  = Data([0x01])
    let BUTTON_RELEASED = Data([0x00])

    // MARK: - BOOST Tilt Sensor
    let TILT_HORIZ: UInt8 = 0x00
    let TILT_UP: UInt8 = 0x01
    let TILT_DOWN: UInt8 = 0x02
    let TILT_RIGHT: UInt8 = 0x03
    let TILT_LEFT: UInt8 = 0x04
    let TILT_INVERT: UInt8 = 0x05

    lazy var TILT_BASIC_VALUES: [UInt8] = {
        [TILT_HORIZ, TILT_UP, TILT_DOWN, TILT_RIGHT, TILT_LEFT, TILT_INVERT]
    }()

    let TILT_BASIC_TEXT = ["TILT_HORIZ", "TILT_UP", "TILT_DOWN", "TILT_RIGHT", "TILT_LEFT", "TILT_INVERT"]

    // MARK: - WeDo 2.0 Tilt Sensor

    let WEDO_TILT_HORIZ: UInt8 = 0x00
    let WEDO_TILT_LEFT: UInt8 = 0x07
    let WEDO_TILT_RIGHT: UInt8 = 0x05
    let WEDO_TILT_UP: UInt8 = 0x03
    let WEDO_TILT_DOWN: UInt8 = 0x09

}
