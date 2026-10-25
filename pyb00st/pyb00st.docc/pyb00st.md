# ``pyb00st``

Port of pyb00st library for LEGO® BOOST on Swift for iOS & macOS

## Overview

Native Swift port of the [Python library](https://github.com/JorgePe/pyb00st), using CoreBluetooth on iOS 13+ and macOS 11+. Requires Swift 6.

## Quick Start

### Installation

Add the repository as a Swift Package and select the `pyb00st` product. The host app supplies `NSBluetoothAlwaysUsageDescription`; sandboxed macOS apps also require the Bluetooth entitlement.

```swift
@MainActor
func connectAndSetLight() async throws {
    let hub = MoveHub()
    try await hub.start()
    defer { hub.stop() }
    try await hub.setHubLight(.green)
}
```

Retain the hub for longer sessions. `start()` waits for characteristic subscription; sensor modes are enabled with ``MoveHub/listen(to:on:)``. Command completion means the Bluetooth write completed, not that a motor finished moving. Read events through ``MoveHub/onEvent`` and cached readings through ``MoveHub/values``.

## Topics

### Connection and control

- ``MoveHub``
- ``HubTransport``
- ``CoreBluetoothTransport``
- ``HubDevice``
- ``HubError``

### Commands and input

- ``HubCommand``
- ``HubPort``
- ``HubMotor``
- ``HubColor``
- ``HubSensor``
- ``WeDoTiltMode``

### Notifications

- ``HubNotificationDecoder``
- ``HubEvent``
- ``HubValues``
- ``HubPortValues``
- ``HubTilt``
- ``WeDoTilt``
- ``SensorColor``
