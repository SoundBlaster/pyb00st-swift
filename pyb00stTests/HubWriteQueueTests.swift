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

    @Test func canceledQueuedWriteIsSkippedWhenAcknowledgmentWinsActorRace() async throws {
        let (submitted, signal) = AsyncStream<Data>.makeStream()
        var iterator = submitted.makeAsyncIterator()
        var packets: [Data] = []
        var failures = 0
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { data in
            packets.append(data)
            signal.yield(data)
            return .awaitingResponse
        }, onFailure: { _ in failures += 1 })
        let first = Task { try await queue.write(Data([1])) }
        #expect(await iterator.next() == Data([1]))

        let (queued, queuedSignal) = AsyncStream<Int>.makeStream()
        var queuedIterator = queued.makeAsyncIterator()
        let second = Task {
            queuedSignal.yield(2)
            // Both operations run on MainActor: this task cannot yield to the
            // test again until write has installed its pending continuation.
            try await queue.write(Data([2]))
        }
        #expect(await queuedIterator.next() == 2)
        let third = Task {
            queuedSignal.yield(3)
            try await queue.write(Data([3]))
        }
        #expect(await queuedIterator.next() == 3)

        // No suspension here: acknowledge drains before the deferred onCancel
        // task can run. The canceled motor packet must never reach submit.
        second.cancel()
        queue.acknowledge()
        #expect(packets == [Data([1]), Data([3])])
        await #expect(throws: CancellationError.self) { try await second.value }
        try await first.value
        queue.acknowledge()
        try await third.value
        #expect(failures == 0)
        signal.finish()
        queuedSignal.finish()
    }

    @Test(arguments: [false, true])
    func cancelingBackpressuredWritePreservesSession(readinessWinsActorRace: Bool) async throws {
        let (attempts, signal) = AsyncStream<Void>.makeStream()
        var iterator = attempts.makeAsyncIterator()
        var ready = false
        var packets: [Data] = []
        var failures = 0
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { data in
            signal.yield(())
            guard ready else { return .blocked }
            packets.append(data)
            return .completed
        }, onFailure: { _ in failures += 1 })
        let write = Task { try await queue.write(Data([1])) }
        _ = await iterator.next()
        write.cancel()
        if readinessWinsActorRace {
            ready = true
            queue.drain()
        }
        await #expect(throws: CancellationError.self) { try await write.value }
        #expect(packets.isEmpty)
        #expect(failures == 0)
        ready = true
        try await queue.write(Data([2]))
        #expect(packets == [Data([2])])
        signal.finish()
    }

    @Test func activeCancellationStillInvalidatesSessionWhenAcknowledgmentWinsActorRace() async {
        let (submitted, signal) = AsyncStream<Void>.makeStream()
        var iterator = submitted.makeAsyncIterator()
        var packets: [Data] = []
        var failures = 0
        let queue = HubWriteQueue(timeoutNanoseconds: 60_000_000_000, submit: { data in
            packets.append(data)
            signal.yield(())
            return .awaitingResponse
        }, onFailure: { error in
            #expect(error is CancellationError)
            failures += 1
        })
        let first = Task { try await queue.write(Data([1])) }
        _ = await iterator.next()
        let (queued, queuedSignal) = AsyncStream<Void>.makeStream()
        var queuedIterator = queued.makeAsyncIterator()
        let second = Task {
            queuedSignal.yield(())
            try await queue.write(Data([2]))
        }
        _ = await queuedIterator.next()
        first.cancel()
        queue.acknowledge()
        #expect(packets == [Data([1])])
        #expect(failures == 1)
        // On the old implementation, finish the incorrectly sent second packet
        // so a failing regression does not have to wait for its timeout.
        queue.acknowledge()
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(failures == 1)
        signal.finish()
        queuedSignal.finish()
    }
}
