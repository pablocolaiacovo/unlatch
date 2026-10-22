import Foundation
import Testing

@testable import Unlatch

// Design/finder-quick-action.md, §4. The tests use the real Task.sleep delay:
// positive checks poll for up to 2 s, negative checks sleep a fixed window.

@MainActor
private final class Recorder {
    var calls: [[URL]] = []
    func record(_ urls: [URL]) { calls.append(urls) }
}

private func pdf(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/handoff/\(name).pdf") }

@MainActor
private func waitForCall(_ recorder: Recorder, count: Int = 1) async {
    for _ in 0..<100 where recorder.calls.count < count {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor @Test func connectNeverDeliversInline() async {
    let handoff = FinderHandoff(coalescingDelay: .milliseconds(50))
    let recorder = Recorder()
    let a = pdf("a"), b = pdf("b")
    handoff.receive([a, b])
    handoff.connect { recorder.record($0) }
    #expect(recorder.calls.isEmpty)
    await waitForCall(recorder)
    #expect(recorder.calls == [[a, b]])
}

@MainActor @Test func connectDeliversFilesBufferedBeforeItWhenNoTimerIsPending() async {
    let handoff = FinderHandoff(coalescingDelay: .milliseconds(50))
    let recorder = Recorder()
    let a = pdf("a")
    handoff.receive([a])
    // The first timer fires while deliver is nil and does nothing.
    try? await Task.sleep(for: .milliseconds(200))
    handoff.connect { recorder.record($0) }
    #expect(recorder.calls.isEmpty)
    await waitForCall(recorder)
    #expect(recorder.calls == [[a]])
}

@MainActor @Test func connectRestartsTheTimerWithTheFullDelay() async {
    let handoff = FinderHandoff(coalescingDelay: .milliseconds(400))
    let recorder = Recorder()
    let a = pdf("a")
    handoff.receive([a])
    try? await Task.sleep(for: .milliseconds(300))
    handoff.connect { recorder.record($0) }
    // An inherited timer would fire about 100 ms after connect; the restarted
    // one fires about 400 ms after it.
    try? await Task.sleep(for: .milliseconds(200))
    #expect(recorder.calls.isEmpty)
    await waitForCall(recorder)
    #expect(recorder.calls == [[a]])
}

@MainActor @Test func coldLaunchBurstCoalescesIntoOneDelivery() async {
    let handoff = FinderHandoff(coalescingDelay: .milliseconds(50))
    let recorder = Recorder()
    let first = (0..<5).map { pdf("first-\($0)") }
    let second = (0..<4).map { pdf("second-\($0)") }
    handoff.receive(first)
    handoff.connect { recorder.record($0) }
    handoff.receive(second)
    #expect(recorder.calls.isEmpty)
    await waitForCall(recorder)
    #expect(recorder.calls == [first + second])
    try? await Task.sleep(for: .milliseconds(200))
    #expect(recorder.calls.count == 1)
}

@MainActor @Test func discardPendingDropsBufferedFilesAndCancelsTheFlush() async {
    let handoff = FinderHandoff(coalescingDelay: .milliseconds(50))
    let recorder = Recorder()
    let b = pdf("b")
    handoff.connect { recorder.record($0) }
    handoff.receive([pdf("a")])
    handoff.discardPending()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(recorder.calls.isEmpty)
    handoff.receive([b])
    await waitForCall(recorder)
    #expect(recorder.calls == [[b]])
}
