# Move Hub MCP server

A native macOS MCP server for LEGO BOOST, using [the official MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) and `pyb00st`. No Python or JavaScript runtime is needed to run it.

## Build and connect

Requires macOS 13+ and Swift 6.1+. This companion package lives in `MCP/` because the SDK requires a newer deployment target than the core framework. Its **`MCP` trait is disabled by default**; enabling it compiles the SDK and hub tools. The root package remains dependency-free and keeps iOS 13+ / macOS 11+ support. SwiftPM may still resolve/download optional dependencies when traits are off.

From the repository root:

```sh
swift build --package-path MCP -c release --traits MCP --product pyb00st-mcp
swift build --package-path MCP -c release --traits MCP --show-bin-path
```

Use `pyb00st-mcp` inside the directory printed by the second command as your MCP client's **absolute command path**. Start the built binary directly, without arguments. Do not wrap it in `swift run`: build output must not enter the protocol stream.

For clients that use an `mcpServers` JSON configuration:

```json
{
  "mcpServers": {
    "pyb00st": {
      "command": "/absolute/build/directory/pyb00st-mcp",
      "args": []
    }
  }
}
```

The executable communicates using newline-delimited JSON-RPC on stdin/stdout, with diagnostics on stderr. It embeds a Bluetooth usage description in its Mach-O executable. Allow Bluetooth access when macOS asks; depending on how the client launches processes, macOS may attribute permission to the client application. Listing tools and reading disconnected state never initiate Bluetooth discovery.

Without `--traits MCP`, the executable exits with a diagnostic on stderr and starts no MCP/Bluetooth session. `--help` is available in both builds. The `pyb00stMCP` library product lets a macOS host embed the same tools with `HubMCPServer.makeServer()`; an embedder owns transport lifecycle and must call `shutdown()` when its transport closes. The default executable performs that cleanup on stdin EOF.

## Tools

| Tool | Arguments | Result |
| --- | --- | --- |
| `hub_connect` | Optional `identifier` (Apple peripheral UUID), `name`, `timeoutSeconds` (1–60, default 10) | Connect to one advertising BOOST hub. Disconnect before changing selection. |
| `hub_disconnect` | None | Disconnect and clear readings; may interrupt an in-flight operation. |
| `hub_state` | None | Cached connection, device, button, tilt and per-port readings; latest errors. |
| `hub_led` | `color` | Indexed LED color: off, pink, purple, blue, lightBlue, cyan, green, yellow, orange, red, white. |
| `hub_motor_run` | `port` A/B/C/D, `milliseconds` 1–2000, `dutyCycle` -100–100 | One bounded motor pulse; negative reverses direction. |
| `hub_sensor_subscribe` | `port`, `sensor` | Enable a mode and discard that port's previous reading. |
| `hub_sensor_unsubscribe` | `port` | Disable the port's current mode and clear its reading. |
| `hub_button_subscribe` | None | Enable button notifications. |

Sensor names: `encoder` (A/B/C/D), `hubTilt` (TILT), `colorDistance`, `weDoTiltAngle`, `weDoTilt`, `weDoCrash`, `weDoDistance` (C/D). Port names are case-sensitive. External hardware must match the selected mode.

Example calls after turning on the hub:

```json
{"name":"hub_connect","arguments":{"name":"LEGO Move Hub"}}
{"name":"hub_led","arguments":{"color":"green"}}
{"name":"hub_sensor_subscribe","arguments":{"port":"A","sensor":"encoder"}}
{"name":"hub_motor_run","arguments":{"port":"A","milliseconds":500,"dutyCycle":30}}
{"name":"hub_state","arguments":{}}
{"name":"hub_disconnect","arguments":{}}
```

Omit the optional name filter if your hub advertises another name. These are `tools/call` parameters; your client supplies JSON-RPC IDs and framing.

## Behavior and limits

- Invalid types, missing/unknown arguments and motion bounds are rejected before a packet is written. Unknown tools and malformed arguments produce MCP `invalidParams`; Bluetooth/connection failures return a tool result with `isError: true`.
- One mutating operation runs at a time. A motor call keeps the slot until its requested duration elapses, preventing overlapping motor calls. Read-only state and disconnect remain available. Other concurrent mutations return an error for the client to retry.
- Tool success confirms completion of the Bluetooth write (and elapsed requested duration for motors). It does **not** confirm physical movement or firmware acceptance. Later hub error notifications appear as `lastHubError` with `command` and `code`; transport/decoder errors appear as `lastError`.
- Readings come from asynchronous notifications. `null` means no reading is available; it does not mean zero. `lastEventAt` is the time of the latest notification, not a freshness guarantee for every field. Disconnect clears readings.
- Request cancellation is cooperative. A motor request canceled after submission disconnects the session, but a transmitted packet cannot be recalled. Disconnect, EOF or process termination does not guarantee immediate physical stopping; a submitted pulse is bounded by its requested duration, at most two seconds.
- Paired A+B, angle-based motion and continuous WeDo motor output are not exposed in this first server. Paired A+B previously powered off the tested hub and still needs hardware investigation.
- This is a local stdio server with no network listener. MCP clients decide which tool calls to approve. Hardware control through this MCP server still requires physical validation; automated tests use an injected transport.

## Verify

```sh
# Default, disabled executable
swift build --package-path MCP --product pyb00st-mcp

# Enabled tools, validation, connection recovery, cancellation and SDK client/server exchange
swift test --package-path MCP --traits MCP
```

The SDK version range is 0.12.1..<0.13.0; `Package.resolved` records the executable's dependencies. SDK code is covered by its [MIT/Apache 2.0 license](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/LICENSE); transitive packages retain their own licenses.
