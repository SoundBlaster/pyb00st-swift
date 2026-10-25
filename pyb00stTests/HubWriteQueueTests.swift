import Foundation
import Testing
@testable import pyb00st

@MainActor
struct HubWriteQueueTests {
    @Test func responseWritesAreFIFO() async throws {
        let (submissions, signal) = AsyncStream<Data>.makeStream()
        var iterator = submissions.makeAsyncIterator()
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: {
            signal.yield($0)
            return .awaitingResponse
        }, onFailure: { _ in Issue.record("Unexpected queue failure") })
        let first = Task { try await queue.write(Data([1])) }
        #expect(await iterator.next() == Data([1]))
        let second = Task { try await queue.write(Data([2])) }
        queue.acknowledge()
        try await first.value
        #expect(await iterator.next() == Data([2]))
        queue.acknowledge()
        try await second.value
        // Late acknowledgments must not resume a continuation twice.
        queue.acknowledge()
        signal.finish()
    }

    @Test func backpressureDefersSubmission() async throws {
        let (attempts, signal) = AsyncStream<Void>.makeStream()
        var iterator = attempts.makeAsyncIterator()
        var ready = false
        var sent: [Data] = []
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { data in
            signal.yield(())
            guard ready else { return .blocked }
            sent.append(data)
            return .completed
        }, onFailure: { _ in Issue.record("Unexpected queue failure") })
        let write = Task { try await queue.write(Data([1])) }
        _ = await iterator.next()
        #expect(sent.isEmpty)
        ready = true
        queue.drain()
        try await write.value
        #expect(sent == [Data([1])])
        signal.finish()
    }

    @Test func activeCancellationInvalidatesSession() async {
        let (started, signal) = AsyncStream<Void>.makeStream()
        var iterator = started.makeAsyncIterator()
        var failures = 0
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { _ in
            signal.yield(())
            return .awaitingResponse
        }, onFailure: { error in
            #expect(error is CancellationError)
            failures += 1
        })
        let write = Task { try await queue.write(Data([1])) }
        _ = await iterator.next()
        write.cancel()
        await #expect(throws: CancellationError.self) { try await write.value }
        #expect(failures == 1)
        queue.acknowledge()
        signal.finish()
    }

    @Test func disconnectFailsAllPendingWrites() async {
        let (started, signal) = AsyncStream<Void>.makeStream()
        var iterator = started.makeAsyncIterator()
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { _ in
            signal.yield(())
            return .awaitingResponse
        }, onFailure: { _ in Issue.record("Owner-requested disconnect is not a queue failure") })
        let first = Task { try await queue.write(Data([1])) }
        _ = await iterator.next()
        let second = Task { try await queue.write(Data([2])) }
        queue.failAll(HubError.notConnected)
        await #expect(throws: HubError.notConnected) { try await first.value }
        await #expect(throws: HubError.notConnected) { try await second.value }
        queue.failAll(HubError.notConnected)
        queue.acknowledge()
        signal.finish()
    }

    @Test func timeoutFailsWriteAndClosesSession() async {
        var failures = 0
        let queue = HubWriteQueue(timeoutNanoseconds: 1, submit: { _ in .blocked }, onFailure: { error in
            #expect(error as? HubError == .timedOut)
            failures += 1
        })
        await #expect(throws: HubError.timedOut) { try await queue.write(Data([1])) }
        #expect(failures == 1)
    }

    @Test func cancelingWaitingWritePreservesActiveWrite() async throws {
        let (submitted, signal) = AsyncStream<Data>.makeStream()
        var iterator = submitted.makeAsyncIterator()
        var packets: [Data] = []
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { data in
            packets.append(data)
            signal.yield(data)
            return .awaitingResponse
        }, onFailure: { _ in Issue.record("Canceling a waiting write must preserve the active write") })
        let first = Task { try await queue.write(Data([1])) }
        #expect(await iterator.next() == Data([1]))
        let (queued, queuedSignal) = AsyncStream<Void>.makeStream()
        var queuedIterator = queued.makeAsyncIterator()
        let second = Task {
            queuedSignal.yield(())
            try await queue.write(Data([2]))
        }
        _ = await queuedIterator.next()
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        queue.acknowledge()
        try await first.value
        #expect(packets == [Data([1])])
        signal.finish()
        queuedSignal.finish()
    }

    @Test func submissionErrorPropagates() async {
        var failures = 0
        let failure = HubError.transport("Rejected packet")
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { _ in throw failure }, onFailure: { _ in failures += 1 })
        await #expect(throws: failure) { try await queue.write(Data([1])) }
        #expect(failures == 1)
    }
}
