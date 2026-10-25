# pyb00st-swift

**Make your LEGO® BOOST move. In Swift.**

Build iPhone and Mac apps that control a LEGO BOOST Move Hub: turn motors, change the LED, and react to sensor readings. Add one Swift package and use a typed, asynchronous API backed by Apple's CoreBluetooth.

**Native Swift. Zero third-party dependencies. No Python or JavaScript runtime.**

```swift
try await hub.start()
try await hub.setHubLight(.green)
try await hub.runMotorForTime(.a, milliseconds: 500, dutyCycle: 30)
```

Your app owns the experience. The framework handles discovery, connection setup, Bluetooth writes, and notification decoding.

## Why build with it?

- **Stay in Swift.** Use `async/await`, typed ports and colors, and `MainActor` callbacks alongside your SwiftUI or AppKit code.
- **Go straight to your feature.** Build a robot controller, a sensor dashboard, or an interactive learning app without assembling BLE packets.
- **Use the hardware you have.** Connect through the built-in Bluetooth on an iPhone or Mac. No bridge process, server, or USB adapter is required.
- **React to the real world.** Receive button, motor encoder, tilt, color, and distance events, with the latest readings available in `hub.values`.
- **Test without a hub.** Inject a `HubTransport` implementation to exercise your app's behavior with predictable inputs.

## Add it to your app

In Xcode, choose **File → Add Package Dependencies** and paste:

```text
https://github.com/SoundBlaster/pyb00st-swift.git
```

Select the **main** branch until a versioned release is available, add the **pyb00st** product to your target, and `import pyb00st`.

Add `NSBluetoothAlwaysUsageDescription` to your app's Info.plist, for example: “Connect to your LEGO BOOST Move Hub.” For a sandboxed macOS app, also enable **App Sandbox → Hardware → Bluetooth**.

Requires Swift 6 / Xcode 16 or newer. The Swift package declares iOS 13+ / macOS 11+; the Xcode framework target uses iOS 15+ / macOS 12+. See the [integration guide](Documentation/Integration.md#deployment-requirements) for SDK and compatibility details.

## Connect, move, and read

Turn on Bluetooth and press the Move Hub's green button. This complete example connects to the first advertising BOOST hub, subscribes to an encoder, and runs motor A for half a second:

```swift
import pyb00st

@MainActor
func runDemo() async throws {
    let hub = MoveHub()
    hub.onEvent = { event in print(event) }
    hub.onError = { error in print(error.localizedDescription) }

    try await hub.start()
    defer { hub.stop() }

    try await hub.setHubLight(.green)
    try await hub.listen(to: .encoder, on: .a)
    try await hub.runMotorForTime(.a, milliseconds: 500, dutyCycle: 30)

    // Commands return after the Bluetooth write. Keep the connection alive
    // while the motor moves and sensor notifications arrive.
    try await Task.sleep(nanoseconds: 1_000_000_000)
    print(hub.values.ports[.a]?.angle as Any)
}
```

In an app, keep `MoveHub` in your session or model and call `stop()` when finished. Select a particular hub with `MoveHub(name:)` or `MoveHub(identifier:)`.

## What you can build

| Your app needs to… | Use… |
| --- | --- |
| Show connection or game state on the hub | `setHubLight(.blue)` |
| Move a motor for a set duration | `runMotorForTime(_:milliseconds:dutyCycle:)` |
| Turn a motor through a set angle | `runMotorForAngle(_:degrees:dutyCycle:)` |
| Drive A and B together | `runMotorsForTime(…)` or `runMotorsForAngle(…)` |
| Respond to a button press | `listenButton()` and `onEvent` |
| Read motor positions or hub orientation | `listen(to: .encoder, on: .a)` or `.hubTilt` on `.tilt` |
| Add an external color/distance sensor | `listen(to: .colorDistance, on: .c)` |
| Use supported WeDo 2.0 motors and sensors | `runWeDoMotor(on:dutyCycle:)` and the WeDo sensor modes |

Negative duty cycles reverse motor direction. Invalid arguments throw before a command is sent. Sensor events and connection callbacks arrive on `MainActor`, ready to feed your UI state.

## Try the SwiftUI demo

Open [pyb00st.xcodeproj](pyb00st.xcodeproj), choose **MoveHubDemo**, select **My Mac** or a physical iPhone, and Run. For an iPhone build, select your signing team.

Click **Connect** to try LED colors, short motor pulses, and live button, tilt, and A/B encoder readings. The demo includes Bluetooth permission settings and a small [observable session model](Demo/DemoSession.swift) you can adapt for your own app.

The demo requires iOS 17+ / macOS 14+. A physical iPhone or Mac is required to connect to the hub.

## Hardware status

BLE connection, LED control, and sensor notifications have been checked on a MacBook with a real Move Hub. Individual motors A and B have also been confirmed working from the demo on a physical iPhone Air.

Paired A+B commands are implemented and covered by packet tests. On the tested hub, starting both motors together powered the hub off; the cause remains under investigation. Paired operation and the external motor/sensor combinations still need hardware validation. The framework targets BOOST Move Hub firmware using current port IDs; support for every Powered Up hub or legacy firmware is outside its scope.

## Next: let your agent use the hub

**Planned: a native macOS MCP server powered by this framework.** An agent could connect to a Move Hub, change its LED, request bounded motor movements, and read sensor state through tools backed by the same Swift API.

The intended path is a local Swift process communicating with an MCP client over stdio and with the hub over CoreBluetooth. This would let you build agent-driven experiments and robot workflows without adding a Python or JavaScript bridge. The MCP server is not implemented yet.

## Go deeper

- [Integration and API reference](Documentation/Integration.md): permissions, connection lifecycle, supported modes, protocol behavior, testing, and migration from the original API.
- [SwiftUI demo source](Demo): a working starting point for your app.
- [DocC documentation](pyb00st/pyb00st.docc/pyb00st.md): library overview and API topics.
- [CI](https://github.com/SoundBlaster/pyb00st-swift/actions/workflows/swift.yml): package tests and iOS/macOS framework and demo builds.

## License and credits

MIT; see [LICENSE](LICENSE). Built on the work of [Jorge Pereira's pyb00st](https://github.com/JorgePe/pyb00st), with the upstream copyright notice retained.

LEGO is a trademark of the LEGO Group, which does not sponsor or endorse this project.
