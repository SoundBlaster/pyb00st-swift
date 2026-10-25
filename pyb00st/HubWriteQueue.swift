import Foundation

/// Serializes characteristic writes, including backpressure and exactly-once completion.
/// Kept independent of CoreBluetooth so lifecycle behavior can be verified without a radio.
@MainActor
final class HubWriteQueue {
    enum Submission {
        case blocked
        case awaitingResponse
        case completed
    }

    private struct Pending {
        let id: UUID
        let data: Data
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let timeoutNanoseconds: UInt64
    private let submit: (Data) throws -> Submission
    private let onFailure: (any Error) -> Void
    private var pending: [Pending] = []
    private var timeout: Task<Void, Never>?
    private var awaitingResponse = false
    private var failure: (any Error)?

    init(timeoutNanoseconds: UInt64, submit: @escaping (Data) throws -> Submission,
         onFailure: @escaping (any Error) -> Void) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.submit = submit
        self.onFailure = onFailure
    }

    func write(_ data: Data) async throws {
        try Task.checkCancellation()
        if let failure { throw failure }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(Pending(id: id, data: data, continuation: continuation))
                if pending.count == 1 { drain() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
        try Task.checkCancellation()
    }

    func drain() {
        guard !awaitingResponse else { return }
        while let next = pending.first {
            if timeout == nil {
                let delay = timeoutNanoseconds
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: delay) }
                    catch { return }
                    guard let self, self.pending.first?.id == next.id else { return }
                    self.abort(HubError.timedOut)
                }
            }
            do {
                switch try submit(next.data) {
                case .blocked: return
                case .awaitingResponse:
                    awaitingResponse = true
                    return
                case .completed: complete()
                }
            } catch {
                abort(error)
                return
            }
        }
    }

    func acknowledge(error: (any Error)? = nil) {
        guard awaitingResponse else { return }
        if let error { abort(error); return }
        complete()
        drain()
    }

    func failAll(_ error: any Error) {
        failure = error
        timeout?.cancel()
        timeout = nil
        awaitingResponse = false
        let unfinished = pending
        pending.removeAll()
        for item in unfinished { item.continuation.resume(throwing: error) }
    }

    private func complete() {
        timeout?.cancel()
        timeout = nil
        awaitingResponse = false
        guard !pending.isEmpty else { return }
        pending.removeFirst().continuation.resume()
    }

    private func cancel(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        if index == 0 {
            // A submitted packet can still be acknowledged after cancellation. The
            // owner must close this session before accepting another command.
            abort(CancellationError())
        } else {
            pending.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }

    private func abort(_ error: any Error) {
        failAll(error)
        onFailure(error)
    }
}
