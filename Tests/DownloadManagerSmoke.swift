// Compiled with the actual manager and package gate by Scripts/run_download_smoke.py.
// UIKit, background UI and package extraction are stubbed; HTTP and file staging are real.
import Foundation

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw SmokeFailure(description: message) }
}

@MainActor
private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(8)
    while !condition() {
        if Date() >= deadline { throw SmokeFailure(description: "Timed out: " + message) }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private struct FixtureStats: Decodable {
    let active: Int
    let peak: Int
    let requests: [String: Int]
}

private actor GateProbe {
    var active = 0
    var peak = 0
    var completed = 0
    func enter() { active += 1; peak = max(peak, active) }
    func leave() { active -= 1; completed += 1 }
}

@main
private struct DownloadManagerSmoke {
    @MainActor
    static func main() async throws {
        let port = Int(CommandLine.arguments[1])!
        func url(_ path: String, alternate: Bool = false) -> URL {
            URL(string: "http://\(alternate ? "localhost" : "127.0.0.1"):\(port)\(path)")!
        }
        func stats() async throws -> FixtureStats {
            let (data, _) = try await URLSession.shared.data(from: url("/stats"))
            return try JSONDecoder().decode(FixtureStats.self, from: data)
        }

        // Same URL, different callers: one transfer and both exact-UUID callbacks.
        let manager = DownloadManager()
        var results: [Result<String, Error>] = []
        let first = manager.startDownload(from: url("/ok/dedup.ipa")) { results.append($0) }
        let duplicate = manager.startDownload(from: url("/ok/dedup.ipa")) { results.append($0) }
        try require(first === duplicate, "Repeated taps created separate Download objects")
        try await waitUntil("deduplicated import") { FR.pending.count == 1 }
        let expectedUUID = FR.succeedNext()
        try await waitUntil("both completion handlers") { results.count == 2 }
        let firstUUID = try results[0].get()
        try require(firstUUID == expectedUUID, "First callback has the wrong UUID")
        let secondUUID = try results[1].get()
        try require(secondUUID == expectedUUID, "Second callback has the wrong UUID")
        let afterDedup = try await stats()
        try require(afterDedup.requests["/ok/dedup.ipa"] == 1, "Duplicate HTTP requests were sent")
        try require(manager.downloads.isEmpty, "Completed transfer remained active")

        // Two hostnames share a server: verify the global limit and staging backpressure.
        var completed = 0
        for index in 0..<7 {
            manager.startDownload(from: url("/ok/buffer\(index).ipa", alternate: index % 2 == 1)) { result in
                if case .success = result { completed += 1 }
            }
        }
        try await waitUntil("bounded staging") {
            FR.pending.count == 1 &&
            manager.downloads.filter { $0.state == .waitingForImport }.count == 2
        }
        try require(manager.downloads.filter { $0.state == .queued }.count == 4, "Pipeline did not stop at three staged/running packages")
        let bounded = try await stats()
        try require(bounded.peak <= 2, "More than two transfers ran concurrently across hosts")
        let started = bounded.requests.filter { $0.key.hasPrefix("/ok/buffer") }.values.reduce(0, +)
        try require(started == 3, "Backpressure allowed more than three package downloads")
        for _ in 0..<7 {
            try await waitUntil("next queued import") { FR.pending.count == 1 }
            FR.succeedNext()
        }
        try await waitUntil("all buffered jobs complete") { completed == 7 && manager.downloads.isEmpty }

        // HTTP errors and HTML with HTTP 200 must fail and release the queue.
        var failures = 0
        for path in ["/missing/404.ipa", "/html/fake.ipa"] {
            manager.startDownload(from: url(path)) { result in
                if case .failure = result { failures += 1 }
            }
        }
        try await waitUntil("bad responses") { failures == 2 && manager.downloads.isEmpty }
        try require(FR.pending.isEmpty, "Invalid response was handed to the package importer")

        // Cancelling a waiting job frees it without starting a new transfer for that job.
        var cancelled = 0
        for index in 0..<5 {
            manager.startDownload(from: url("/ok/cancel\(index).ipa")) { result in
                if case .failure(let error) = result,
                   (error as NSError).code == NSURLErrorCancelled { cancelled += 1 }
            }
        }
        try await waitUntil("cancellation setup") {
            FR.pending.count == 1 &&
            manager.downloads.filter { $0.state == .waitingForImport }.count == 2
        }
        let queued = manager.downloads.first { $0.state == .queued }!
        manager.cancelDownload(queued)
        try require(cancelled == 1, "Queued cancellation did not complete")
        for _ in 0..<4 {
            try await waitUntil("remaining import") { FR.pending.count == 1 }
            FR.succeedNext()
        }
        try await waitUntil("cancelled queue drains") { manager.downloads.isEmpty }
        try require(FR.stagedDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "Owned staging files leaked after completion")

        // Exercise the real actor gate with competing tasks.
        let probe = GateProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await XSignPackageWorkGate.shared.acquire()
                    await probe.enter()
                    try? await Task.sleep(nanoseconds: 2_000_000)
                    await probe.leave()
                    await XSignPackageWorkGate.shared.release()
                }
            }
        }
        let gatePeak = await probe.peak
        let gateCompleted = await probe.completed
        try require(gatePeak == 1 && gateCompleted == 20, "Heavy package operations overlapped or a waiter was lost")
        print("PASS: deduplication, correlated UUIDs, transfer limits, backpressure, HTTP/HTML rejection, cancellation, staging cleanup and package gate.")
    }
}
