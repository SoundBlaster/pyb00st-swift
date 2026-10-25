import CoreBluetooth
import Foundation

/// Native BLE transport for a BOOST Move Hub. CoreBluetooth delegates are delivered on the main queue.
@MainActor
public final class CoreBluetoothTransport: NSObject, HubTransport {
    public private(set) var isConnected = false
    public private(set) var device: HubDevice?
    public var onNotification: ((Data) -> Void)?
    public var onDisconnect: (((any Error)?) -> Void)?

    private static let serviceUUID = CBUUID(string: "00001623-1212-EFDE-1623-785FEABCD123")
    private static let characteristicUUID = CBUUID(string: Constants.MOVE_HUB_HARDWARE_UUID)
    private let identifier: UUID?
    private let name: String?
    private let timeout: TimeInterval
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var connectionID: UUID?
    private var connection: CheckedContinuation<Void, any Error>?
    private var connectionTimeout: Task<Void, Never>?
    private var writeQueue: HubWriteQueue?

    /// Use Apple peripheral UUIDs rather than MAC addresses. Without an identifier,
    /// discovery accepts only LEGO manufacturer data identifying a BOOST hub.
    /// The timeout bounds connection setup and each active write to 0...3600 seconds, excluding zero.
    public init(identifier: UUID? = nil, name: String? = nil, timeout: TimeInterval = 10) {
        self.identifier = identifier
        self.name = name
        self.timeout = timeout
        super.init()
    }

    public func connect() async throws {
        try Task.checkCancellation()
        if isConnected { return }
        guard connection == nil else { throw HubError.connectionInProgress }
        guard timeout.isFinite, timeout > 0, timeout <= 3600 else { throw HubError.invalidTimeout }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connectionID = id
                connection = continuation
                connectionTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 0) }
                    catch { return }
                    guard let self, self.connectionID == id else { return }
                    self.finish(error: HubError.timedOut)
                }
                // A manager per session prevents callbacks from an old connection from
                // completing operations on a subsequent connection to the same peripheral.
                central = CBCentralManager(delegate: self, queue: .main)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.connectionID == id else { return }
                self.finish(error: CancellationError())
            }
        }
        try Task.checkCancellation()
    }

    public func disconnect() { finish(error: nil) }

    public func write(_ data: Data) async throws {
        try Task.checkCancellation()
        guard isConnected, let writeQueue else { throw HubError.notConnected }
        try await writeQueue.write(data)
    }

    /// Validate LEGO's little-endian company identifier and BOOST system/device byte.
    static func isBoostAdvertisement(_ data: Data?) -> Bool {
        guard let data else { return false }
        let bytes = Array(data)
        return bytes.count >= 4 && bytes[0] == 0x97 && bytes[1] == 0x03 && bytes[3] == 0x40
    }

    private var timeoutNanoseconds: UInt64 { UInt64(timeout * 1_000_000_000) }

    private func beginDiscovery(_ manager: CBCentralManager) {
        guard connection != nil, peripheral == nil else { return }
        if let identifier,
           let known = manager.retrievePeripherals(withIdentifiers: [identifier]).first,
           name == nil || known.name == name {
            connect(known, manager: manager)
        } else {
            manager.scanForPeripherals(withServices: [Self.serviceUUID])
        }
    }

    private func connect(_ found: CBPeripheral, manager: CBCentralManager) {
        manager.stopScan()
        peripheral = found
        found.delegate = self
        manager.connect(found)
    }

    private func submit(_ data: Data) throws -> HubWriteQueue.Submission {
        guard isConnected, let peripheral, let characteristic else { throw HubError.notConnected }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        guard data.count <= peripheral.maximumWriteValueLength(for: type) else {
            throw HubError.transport("Command exceeds the peripheral's maximum write size.")
        }
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return .blocked }
        peripheral.writeValue(data, for: characteristic, type: type)
        return type == .withResponse ? .awaitingResponse : .completed
    }

    private func finish(error: (any Error)?) {
        let hadSession = central != nil || connection != nil || isConnected
        connectionTimeout?.cancel()
        connectionTimeout = nil
        central?.stopScan()
        peripheral?.delegate = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        central?.delegate = nil
        central = nil
        peripheral = nil
        characteristic = nil
        isConnected = false
        device = nil
        connectionID = nil
        let pendingConnection = connection
        connection = nil
        let failure = error ?? HubError.notConnected
        writeQueue?.failAll(failure)
        writeQueue = nil
        pendingConnection?.resume(throwing: failure)
        if hadSession { onDisconnect?(error) }
    }
}

// Both delegates are registered exclusively with CBCentralManager(queue: .main).
// The preconcurrency conformances bridge ObjC's nonisolated delegate requirements;
// they do not permit callbacks or peripheral access from other queues.
extension CoreBluetoothTransport: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central else { return }
        switch central.state {
        case .poweredOn: beginDiscovery(central)
        case .unknown, .resetting:
            if peripheral != nil { finish(error: HubError.bluetoothUnavailable) }
        case .unauthorized: finish(error: HubError.bluetoothUnauthorized)
        case .poweredOff, .unsupported: finish(error: HubError.bluetoothUnavailable)
        @unknown default: finish(error: HubError.bluetoothUnavailable)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === self.central, connection != nil, self.peripheral == nil else { return }
        if let identifier {
            guard peripheral.identifier == identifier else { return }
        } else {
            guard Self.isBoostAdvertisement(advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data) else { return }
        }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        if let name, advertisedName != name { return }
        connect(peripheral, manager: central)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, peripheral === self.peripheral else { return }
        peripheral.discoverServices([Self.serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        guard central === self.central, peripheral === self.peripheral else { return }
        finish(error: error ?? HubError.transport("Failed to connect to the Move Hub."))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard central === self.central, peripheral === self.peripheral else { return }
        finish(error: error ?? HubError.notConnected)
    }
}

extension CoreBluetoothTransport: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard peripheral === self.peripheral else { return }
        if let error { finish(error: error); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            finish(error: HubError.missingCharacteristic)
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard peripheral === self.peripheral, service.uuid == Self.serviceUUID else { return }
        if let error { finish(error: error); return }
        guard let found = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }),
              found.properties.contains(.notify),
              !found.properties.intersection([.write, .writeWithoutResponse]).isEmpty else {
            finish(error: HubError.missingCharacteristic)
            return
        }
        characteristic = found
        peripheral.setNotifyValue(true, for: found)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard peripheral === self.peripheral, characteristic === self.characteristic else { return }
        if let error { finish(error: error); return }
        guard characteristic.isNotifying else {
            finish(error: HubError.transport("Hub notifications were disabled."))
            return
        }
        isConnected = true
        device = HubDevice(identifier: peripheral.identifier, name: peripheral.name)
        if writeQueue == nil {
            writeQueue = HubWriteQueue(timeoutNanoseconds: timeoutNanoseconds, submit: { [weak self] data in
                guard let self else { throw HubError.notConnected }
                return try self.submit(data)
            }, onFailure: { [weak self] error in self?.finish(error: error) })
        }
        connectionTimeout?.cancel()
        connectionTimeout = nil
        let pending = connection
        connection = nil
        pending?.resume()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard peripheral === self.peripheral, characteristic === self.characteristic else { return }
        if let error { finish(error: error); return }
        if let data = characteristic.value { onNotification?(data) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard peripheral === self.peripheral, characteristic === self.characteristic else { return }
        writeQueue?.acknowledge(error: error)
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        writeQueue?.drain()
    }
}
