#!/usr/bin/env python3
"""Exercise the real download queue on macOS without UIKit or a test target."""
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
stats_lock = threading.Lock()
stats = {"active": 0, "peak": 0, "requests": {}}

class FixtureHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/stats":
            with stats_lock:
                payload = json.dumps(stats).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return
        with stats_lock:
            stats["active"] += 1
            stats["peak"] = max(stats["peak"], stats["active"])
            stats["requests"][self.path] = stats["requests"].get(self.path, 0) + 1
        try:
            time.sleep(0.07)
            status = 404 if self.path.startswith("/missing") else 200
            payload = b"<html>not an IPA</html>" if self.path.startswith("/html") else b"PK\x03\x04" + bytes(1024)
            self.send_response(status)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with stats_lock:
                stats["active"] -= 1

    def log_message(self, *_):
        pass

STUBS = r"""
import Foundation
import Combine

struct SourceAppProvenance { let sourceVersionID: String }
final class UINotificationFeedbackGenerator {
    enum Kind { case error, success }
    func notificationOccurred(_ kind: Kind) {}
}
enum UIAlertController {
    static func showAlertWithOk(title: String, message: String) {}
}
final class BackgroundAudioManager {
    static let shared = BackgroundAudioManager()
    func start() {}
    func stop() {}
}
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    func startTask(for: String, filename: String) {}
    func stopTask(for: String, success: Bool) {}
    func updateProgress(for: String, progress: Double) {}
}
enum FR {
    struct Pending {
        let url: URL
        let completion: (Result<String, Error>) -> Void
    }
    static var pending: [Pending] = []
    static var stagedDirectories: [URL] = []
    static func importPackageFile(
        _ url: URL, download: Download?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        pending.append(Pending(url: url, completion: completion))
        stagedDirectories.append(url.deletingLastPathComponent())
    }
    @discardableResult
    static func succeedNext() -> String {
        let entry = pending.removeFirst()
        let uuid = UUID().uuidString
        entry.completion(.success(uuid))
        return uuid
    }
}
"""

def main():
    compiler = shutil.which("swiftc")
    if compiler is None:
        raise SystemExit("swiftc is required. Run this check with the supplied macOS GitHub Actions workflow.")
    manager = (ROOT / "Feather/Backend/Observable/DownloadManager.swift").read_text()
    manager = "\n".join(line for line in manager.splitlines()
                        if line not in {"import UIKit", "import BackgroundTasks"})
    gate = (ROOT / "Feather/Utilities/XSignPackageWorkGate.swift").read_text()
    tests = (ROOT / "Tests/DownloadManagerSmoke.swift").read_text()
    server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="xsign-download-smoke-") as tmp:
            source = Path(tmp) / "Smoke.swift"
            binary = Path(tmp) / "Smoke"
            source.write_text(STUBS + "\n" + manager + "\n" + gate + "\n" + tests)
            subprocess.run(
                [compiler, "-swift-version", "5", "-target", platform.machine() + "-apple-macosx13.0", "-parse-as-library", str(source), "-o", str(binary)],
                check=True, timeout=60
            )
            subprocess.run([str(binary), str(server.server_port)], check=True, timeout=60)
    finally:
        server.shutdown()
        server.server_close()

if __name__ == "__main__":
    main()
