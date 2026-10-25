# Integration and API reference

[Back to the README](../README.md)

This guide covers deployment requirements, connection behavior, protocol details, and the original pyb00st API mapping.

## Deployment requirements

Requires Swift 6 / Xcode 16 or newer. The Swift Package declares iOS 13+ and macOS 11+; iOS 12 is no longer supported because the public API uses Swift concurrency. The Xcode framework target uses iOS 15+ / macOS 12+ to build with Xcode 27.1 without command-line overrides. Use the package and an appropriate SDK when building for older OS versions. CI build and test checks do not establish runtime compatibility with the minimum OS versions.

## Bluetooth permissions

The host app must supply its Bluetooth permission description:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect to your LEGO BOOST Move Hub.</string>
```

A sandboxed macOS app must enable **App Sandbox → Hardware → Bluetooth** (`com.apple.security.device.bluetooth`). These settings belong to the host app, not the library. See [Apple's Bluetooth permission requirements](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription).

## Connection lifecycle

Keep the `MoveHub` instance alive for the connection. Its API and callbacks run on `MainActor`. Call `stop()` when your app is done with the hub.

To select a specific hub, use `MoveHub(identifier: peripheralUUID)` or `MoveHub(name: "advertised name")`. Apple exposes a peripheral UUID rather than the MAC address accepted by Python. The default timeout is 10 seconds for connection setup and each active write; `MoveHub(timeout: 30)` changes it. Connection setup includes service discovery and notification subscription. Enabling individual sensor modes remains explicit.

## API parity

The reference is [pyb00st at `bf15272481d0541461923820f98983d9f10ebcc9`](https://github.com/JorgePe/pyb00st/tree/bf15272481d0541461923820f98983d9f10ebcc9). All implemented command and sensor operations in its `movehub.py` have a Swift equivalent:

| Python | Swift |
| --- | --- |
| `start`, `stop`, `is_connected` | `start()`, `stop()`, `isConnected` |
| `get_address`, `get_name` | `device?.identifier`, `device?.name` (CoreBluetooth peripheral metadata) |
| `subscribe_all` | Automatic characteristic subscription in `start()` |
| `set_hublight` | `setHubLight(_:)` with `HubColor` |
| `run_motor_for_time` | `runMotorForTime(_:milliseconds:dutyCycle:)` |
| `run_motors_for_time` | `runMotorsForTime(milliseconds:dutyCycleA:dutyCycleB:)` (A/B pair) |
| `run_motor_for_angle` | `runMotorForAngle(_:degrees:dutyCycle:)` |
| `run_motors_for_angle` | `runMotorsForAngle(degrees:dutyCycleA:dutyCycleB:)` (A/B pair) |
| `motor_wedo` | `runWeDoMotor(on:dutyCycle:)` (C/D; zero stops) |
| `listen_colordist_sensor` | `listen(to: .colorDistance, on: .c)` (C/D) |
| `listen_angle_sensor` | `listen(to: .encoder, on: .a)` (A/B/C/D) |
| `listen_button` | `listenButton()` |
| `listen_hubtilt` (basic) | `listen(to: .hubTilt, on: .tilt)` |
| `listen_wedo_tilt` | `listen(to: .weDoTilt(.angle), on: .c)` (`.angle`, `.tilt`, `.crash`; C/D) |
| `listen_wedo_distance` | `listen(to: .weDoDistance, on: .c)` (distance mode; C/D) |
| `parse_notifications`, `last_*` | `onEvent`, `values`, standalone `HubNotificationDecoder` |

`stopListening(on:)` additionally disables a port's notifications and clears its cached reading. Each port has one selected mode. Simultaneous configuration changes on the same port throw `configurationInProgress`; await each change before issuing another. Sensor configuration is installed before its write acknowledgment so immediate notifications can be decoded. A failed configuration disconnects because the device's active mode is uncertain. Detachment, disconnect, and mode changes discard stale readings.

Raw sensor distances retain the original device units; they are not converted to centimeters. WeDo roll/pitch and encoder positions are signed. Optional values mean no reading or an unknown color/orientation. Color/distance mode preserves pyb00st's interpretation: a `0xFF` color byte selects the distance reading; otherwise the reading contains a color.

Port addressing targets current BOOST firmware: A/B/C/D use `0x00/0x01/0x02/0x03`, and paired A+B uses the built-in virtual port `0x10`, matching the [current Move Hub implementation in pylgbst](https://github.com/undera/pylgbst/blob/master/pylgbst/hub.py). The Python reference's 2017 motor IDs (`0x37/0x38/0x39`) are obsolete for this firmware and cause the hub to reject motor output commands. LED (`0x32`) and tilt (`0x3A`) retain their IDs. Firmware using the older port layout is not supported by this mapping.

Full hub tilt, paired encoder readings, ambient light, continuous interactive-motor speed, steering, and motor-position reset were unfinished in the Python reference and are not implemented here. The unusable full-tilt mode is deliberately absent from the typed API. This is a port of the original BOOST behavior, not a complete implementation of every modern Powered Up device or firmware.

## Protocol and error handling

`HubCommand` builds packets independently of Bluetooth. Invalid ports, duty cycles outside `-100...100`, times outside `0...65535` ms, and angles outside `0...UInt32.max` throw `HubError` before sending. Negative speeds use two's complement, fixing Python's off-by-one encoding. Motor headers use Hub ID `0x00`, as required by the [LEGO Wireless Protocol](https://lego.github.io/lego-ble-wireless-protocol-docs/). The original raw constants remain available through `Constants`, with immutable collections and corrected motor headers.

`HubNotificationDecoder` validates lengths before indexing, handles `Int32.min`, isolates C/D configuration, and ignores unknown message types and unconfigured ports. It accepts the single short messages used by this port; arbitrary combined or fragmented LWP messages are outside its scope. Generic hub errors are delivered as `HubEvent.hubError`.

The BLE transport serializes writes, uses acknowledgments when supported, respects backpressure for writes without response, and bounds active writes with a timeout. Canceling an active write disconnects to prevent a late acknowledgment from completing a later command; canceling a queued write removes only that write. A disconnect fails pending operations. Cancellation or disconnect cannot retract a packet already sent to the hub. Bluetooth write acknowledgment does not establish successful physical movement; inspect sensor events and hub feedback as appropriate for your application.

For deterministic tests or another connection backend, implement the main-actor `HubTransport` protocol and pass it to `MoveHub(transport:)`. A transport belongs to a single hub instance.

## Verification

```sh
swift test
xcodebuild -project pyb00st.xcodeproj -scheme pyb00st \
  -destination 'platform=macOS' test
xcodebuild -project pyb00st.xcodeproj -scheme pyb00st \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Tests cover packet vectors, signed values and boundaries, malformed and sliced input, each supported sensor mode on both external ports, connection errors, configuration races, and write queue lifecycle. They use mocks and do not require Bluetooth permission or a hub. Build checks establish compilation only. Physical BLE connectivity, firmware compatibility, sensor measurements, and motor movement still require a real Move Hub.

For a full hardware validation matrix, connect a BOOST hub, test each LED color, run A/B and external motors in both directions, exercise each sensor mode on C and D, then power the hub off during a pending operation and reconnect. Keep the hub clear to move during motor checks. See the [README hardware status](../README.md#hardware-status) for the checks already completed.
