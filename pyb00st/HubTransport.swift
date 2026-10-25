import Foundation

/// A transport owned by one `MoveHub`. All operations and callbacks run on the main actor.
/// `connect()` returns only when notifications and writes are ready; `disconnect()` must
/// fail pending operations and report disconnection through `onDisconnect`.
@MainActor
public protocol HubTransport: AnyObject {
    var isConnected: Bool { get }
    var device: HubDevice? { get }
    var onNotification: ((Data) -> Void)? { get set }
    var onDisconnect: (((any Error)?) -> Void)? { get set }

    func connect() async throws
    func disconnect()
    /// Complete when the packet is submitted (or acknowledged for a response write), not when a motor stops.
    func write(_ data: Data) async throws
}
