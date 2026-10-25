#if MCP
import Foundation
import MCP
import pyb00st

enum HubTools {
    static let all: [Tool] = [
        tool("hub_connect", "Connect to one BOOST Move Hub. Optional UUID/name filters; timeout defaults to 10 seconds.", [
            "identifier": string(), "name": string(), "timeoutSeconds": integer(1, 60),
        ]),
        tool("hub_disconnect", "Disconnect the hub and clear cached sensor readings. Does not guarantee an immediate physical motor stop."),
        tool("hub_state", "Read cached connection and sensor state. Null means no reading received. lastEventAt timestamps any notification; it does not prove every field is fresh.", readOnly: true),
        tool("hub_led", "Set the hub LED. Returns after the Bluetooth write.", [
            "color": string(HubColor.allCases.map { String(describing: $0) }),
        ], required: ["color"]),
        tool("hub_motor_run", "Run one A/B/C/D motor for 1–2000 ms at -100…100 duty cycle. Negative reverses direction. Waits the requested duration; physical completion is unverified. Concurrent mutating calls are rejected.", [
            "port": string(["A", "B", "C", "D"]), "milliseconds": integer(1, 2000), "dutyCycle": integer(-100, 100),
        ], required: ["port", "milliseconds", "dutyCycle"]),
        tool("hub_sensor_subscribe", "Enable a sensor mode. encoder: A/B/C/D; hubTilt: TILT; external modes: C/D. Replaces the port's previous mode and reading.", [
            "port": string(["A", "B", "C", "D", "TILT"]),
            "sensor": string(["encoder", "hubTilt", "colorDistance", "weDoTiltAngle", "weDoTilt", "weDoCrash", "weDoDistance"]),
        ], required: ["port", "sensor"]),
        tool("hub_sensor_unsubscribe", "Disable the current sensor mode on one port and clear its reading.", [
            "port": string(["A", "B", "C", "D", "TILT"]),
        ], required: ["port"]),
        tool("hub_button_subscribe", "Enable hub button notifications; read the latest value with hub_state."),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Value] = [:], required: [String] = [], readOnly: Bool = false) -> Tool {
        Tool(name: name, description: description, inputSchema: .object([
            "type": "object", "properties": .object(properties),
            "required": .array(required.map(Value.string)), "additionalProperties": false,
        ]), annotations: .init(readOnlyHint: readOnly, destructiveHint: !readOnly, idempotentHint: readOnly || name == "hub_disconnect", openWorldHint: !readOnly))
    }

    private static func string(_ values: [String]? = nil) -> Value {
        var schema: [String: Value] = ["type": "string", "minLength": 1]
        if let values { schema["enum"] = .array(values.map(Value.string)) }
        return .object(schema)
    }

    private static func integer(_ minimum: Int, _ maximum: Int) -> Value {
        .object(["type": "integer", "minimum": .int(minimum), "maximum": .int(maximum)])
    }
}

struct Arguments {
    let values: [String: Value]

    init(_ values: [String: Value], schema: Value) throws {
        guard case .object(let object) = schema, case .object(let properties) = object["properties"] else {
            throw MCPError.internalError("Invalid tool schema.")
        }
        for key in values.keys where properties[key] == nil {
            throw MCPError.invalidParams("Unexpected argument: \(key)")
        }
        if case .array(let required) = object["required"] {
            for case .string(let key) in required where values[key] == nil {
                throw MCPError.invalidParams("Missing argument: \(key)")
            }
        }
        self.values = values
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = values[key] else { return nil }
        guard case .string(let text) = value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPError.invalidParams("\(key) must be a nonempty string.")
        }
        return text
    }

    func string(_ key: String) throws -> String {
        guard let value = try optionalString(key) else { throw MCPError.invalidParams("Missing argument: \(key)") }
        return value
    }

    func optionalInteger(_ key: String, range: ClosedRange<Int>) throws -> Int? {
        guard let value = values[key] else { return nil }
        guard case .int(let number) = value, range.contains(number) else {
            throw MCPError.invalidParams("\(key) must be an integer in \(range).")
        }
        return number
    }

    func integer(_ key: String, range: ClosedRange<Int>) throws -> Int {
        guard let value = try optionalInteger(key, range: range) else { throw MCPError.invalidParams("Missing argument: \(key)") }
        return value
    }

    func port() throws -> HubPort {
        let value = try string("port")
        guard let port = HubPort.allCases.first(where: { String(describing: $0).uppercased() == value }) else {
            throw MCPError.invalidParams("Port must be A, B, C, D or TILT.")
        }
        return port
    }
}
#endif
