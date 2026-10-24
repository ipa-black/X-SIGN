import Foundation
import Combine
import UIKit
import BackgroundTasks

final class Download: ObservableObject, Identifiable, @unchecked Sendable {
    enum State: Equatable {
        case queued, downloading, waitingForImport, importing, finished, failed, cancelled
    }

    @Published var progress: Double = 0
    @Published var bytesDownloaded: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var unpackageProgress: Double = 0
    @Published fileprivate(set) var state: State

    var overallProgress: Double {
        onlyArchiving ? unpackageProgress : 0.3 * unpackageProgress + 0.7 * progress
    }

    var task: URLSessionDownloadTask?
    var resumeData: Data?
    let id: String
    let url: URL
    let fileName: String
    let onlyArchiving: Bool
    var sourceProvenance: SourceAppProvenance?
    fileprivate var importHandlers: [(Result<String, Error>) -> Void] = []

    init(id: String, url: URL, onlyArchiving: Bool = false, sourceProvenance: SourceAppProvenance? = nil) {
        self.id = id
        self.url = url
        self.onlyArchiving = onlyArchiving
        self.sourceProvenance = sourceProvenance
        self.fileName = url.lastPathComponent
        self.state = onlyArchiving ? .waitingForImport : .queued
    }
}

final class DownloadManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = DownloadManager()
    @Published private(set) var downloads: [Download] = []

    // A bounded pipeline: at most two transfers and three packages in-flight.
    private let maximumTransfers = 2
    private let maximumPackagesInFlight = 3
    private var session: URLSession!
    private var activeTasks: [Int: Download] = [:]
    private var importQueue: [ImportJob] = []
    private var currentImport: ImportJob?

    // Accessed only by the serial URLSession delegate queue.
    private var lastProgressTime: [Int: TimeInterval] = [:]

    private struct ImportJob {
        let download: Download
        let url: URL
        let ownedDirectory: URL?
    }

    var manualDownloads: [Download] {
        onMain { downloads.filter { isManualDownload($0.id) } }
    }

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true

        let delegateQueue = OperationQueue()
        delegateQueue.name = "IPA.BLACK.DownloadDelegate"
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    @discardableResult
    func startDownload(
        from url: URL,
        id: String = UUID().uuidString,
        sourceProvenance: SourceAppProvenance? = nil,
        onImported: ((Result<String, Error>) -> Void)? = nil
    ) -> Download {
        onMain {
            if let existing = downloads.first(where: {
                !$0.onlyArchiving &&
                ($0.id == id || $0.url == url)
            }) {
                if existing.sourceProvenance == nil { existing.sourceProvenance = sourceProvenance }
                if let onImported { existing.importHandlers.append(onImported) }
                // Repeated taps must never create a second task.
                return existing
            }

            let download = Download(id: id, url: url, sourceProvenance: sourceProvenance)
            if let onImported { download.importHandlers.append(onImported) }
            downloads.append(download)
            pumpDownloads()
            updateBackgroundAudioState()
            return download
        }
    }

    func startArchive(from url: URL, id: String = UUID().uuidString) -> Download {
        onMain {
            let download = Download(id: id, url: url, onlyArchiving: true)
            downloads.append(download)
            startBackgroundTask(download)
            return download
        }
    }

    // Preserved for existing callers. Active transfers are never recreated.
    func resumeDownload(_ download: Download) {
        onMain {
            guard downloads.contains(where: { $0 === download }) else { return }
            if download.state == .downloading, download.task?.state == .suspended {
                download.task?.resume()
            } else if download.state == .queued {
                pumpDownloads()
            }
        }
    }

    func cancelDownload(_ download: Download) {
        onMain {
            guard downloads.contains(where: { $0 === download }) else { return }
            // The ZIP library cannot safely interrupt an extraction in progress.
            guard download.state != .importing else { return }
            let task = download.task
            if let task { activeTasks.removeValue(forKey: task.taskIdentifier) }
            task?.cancel()
            if let job = importQueue.first(where: { $0.download === download }) {
                removeOwnedFile(job)
            }
            importQueue.removeAll { $0.download === download }
            finish(download, result: .failure(URLError(.cancelled)), cancelled: true)
        }
    }

    func isManualDownload(_ string: String) -> Bool { string.contains("FeatherManualDownload") }

    func getDownload(by id: String) -> Download? {
        onMain { downloads.first { $0.id == id } }
    }

    func getDownloadIndex(by id: String) -> Int? {
        onMain { downloads.firstIndex { $0.id == id } }
    }

    func getDownloadTask(by task: URLSessionDownloadTask) -> Download? {
        onMain { activeTasks[task.taskIdentifier] }
    }

    func handlePachageFile(url: URL, dl: Download) throws {
        onMain {
            guard downloads.contains(where: { $0 === dl }),
                  dl.state != .importing,
                  !importQueue.contains(where: { $0.download === dl }) else { return }
            dl.state = .waitingForImport
            importQueue.append(ImportJob(download: dl, url: url, ownedDirectory: nil))
            pumpImports()
        }
    }

    private func pumpDownloads() {
        while activeTasks.count < maximumTransfers {
            let packagesInFlight = activeTasks.count + importQueue.count + (currentImport == nil ? 0 : 1)
            guard packagesInFlight < maximumPackagesInFlight,
                  let download = downloads.first(where: { $0.state == .queued }) else { break }

            let task = session.downloadTask(with: download.url)
            download.task = task
            download.state = .downloading
            activeTasks[task.taskIdentifier] = download
            startBackgroundTask(download)
            task.resume()
        }
    }

    private func pumpImports() {
        guard currentImport == nil, !importQueue.isEmpty else { return }
        let job = importQueue.removeFirst()
        currentImport = job
        job.download.state = .importing
        FR.importPackageFile(job.url, download: job.download) { [weak self] result in
            guard let self else { return }
            self.onMain {
                self.removeOwnedFile(job)
                self.currentImport = nil
                self.finish(job.download, result: result)
                self.pumpImports()
                self.pumpDownloads()
            }
        }
    }

    private func finish(_ download: Download, result: Result<String, Error>, cancelled: Bool = false) {
        guard downloads.contains(where: { $0 === download }) else { return }
        if let task = download.task { activeTasks.removeValue(forKey: task.taskIdentifier) }
        download.task = nil
        switch result {
        case .success:
            download.progress = 1
            download.unpackageProgress = 1
            download.state = .finished
        case .failure:
            download.state = cancelled ? .cancelled : .failed
        }

        downloads.removeAll { $0 === download }
        stopBackgroundTask(download, success: (try? result.get()) != nil)
        let handlers = download.importHandlers
        download.importHandlers.removeAll()
        handlers.forEach { $0(result) }

        if case .failure(let error) = result, handlers.isEmpty, !cancelled {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIAlertController.showAlertWithOk(title: "تعذر تنزيل التطبيق", message: error.localizedDescription)
        }
        updateBackgroundAudioState()
        pumpDownloads()
    }

    private func removeOwnedFile(_ job: ImportJob) {
        if let directory = job.ownedDirectory { try? FileManager.default.removeItem(at: directory) }
    }

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    private func startBackgroundTask(_ download: Download) {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            BackgroundTaskManager.shared.startTask(for: download.id, filename: download.fileName)
        }
        #endif
        updateBackgroundAudioState()
    }

    private func stopBackgroundTask(_ download: Download, success: Bool) {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            BackgroundTaskManager.shared.stopTask(for: download.id, success: success)
        }
        #endif
    }

    private func updateBackgroundAudioState() {
        #if !targetEnvironment(macCatalyst)
        if #unavailable(iOS 26.0) {
            if downloads.isEmpty { BackgroundAudioManager.shared.stop() }
            else { BackgroundAudioManager.shared.start() }
        }
        #endif
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lastProgressTime.removeValue(forKey: downloadTask.taskIdentifier)
        guard let download = getDownloadTask(by: downloadTask) else { return }

        var ownedDirectory: URL?
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
                throw NSError(domain: "IPA.BLACK.Download", code: code, userInfo: [
                    NSLocalizedDescriptionKey: "رفض خادم التنزيل الطلب (HTTP \(code))."
                ])
            }

            // Validate just four bytes. Never load the IPA into a Data buffer.
            let handle = try FileHandle(forReadingFrom: location)
            let prefix: Data?
            do {
                prefix = try handle.read(upToCount: 4)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard prefix == Data([0x50, 0x4B, 0x03, 0x04]) else {
                throw NSError(domain: "IPA.BLACK.Download", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "الرابط لم يُرجع ملف IPA صالحاً؛ قد يكون صفحة ويب أو رابطاً منتهياً."
                ])
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("XSignDownloads", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ownedDirectory = directory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = download.url.pathExtension.lowercased() == "tipa" ? "tipa" : "ipa"
            let destination = directory.appendingPathComponent("Application.\(ext)")
            // The temporary file must be moved before this delegate callback returns.
            try FileManager.default.moveItem(at: location, to: destination)

            DispatchQueue.main.async {
                guard self.activeTasks[downloadTask.taskIdentifier] === download else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                self.activeTasks.removeValue(forKey: downloadTask.taskIdentifier)
                download.task = nil
                download.progress = 1
                download.state = .waitingForImport
                self.importQueue.append(ImportJob(download: download, url: destination, ownedDirectory: directory))
                self.pumpImports()
                self.pumpDownloads()
            }
        } catch {
            if let ownedDirectory { try? FileManager.default.removeItem(at: ownedDirectory) }
            DispatchQueue.main.async {
                self.finish(download, result: .failure(error))
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let isComplete = totalBytesExpectedToWrite > 0 && totalBytesWritten == totalBytesExpectedToWrite
        guard isComplete || now - (lastProgressTime[downloadTask.taskIdentifier] ?? 0) >= 0.1 else { return }
        lastProgressTime[downloadTask.taskIdentifier] = now

        DispatchQueue.main.async {
            guard let download = self.activeTasks[downloadTask.taskIdentifier] else { return }
            download.progress = totalBytesExpectedToWrite > 0
                ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0
            download.bytesDownloaded = totalBytesWritten
            download.totalBytes = max(0, totalBytesExpectedToWrite)
            #if !targetEnvironment(macCatalyst)
            if #available(iOS 26.0, *) {
                BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
            }
            #endif
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lastProgressTime.removeValue(forKey: task.taskIdentifier)
        guard let error else { return }
        DispatchQueue.main.async {
            guard let download = self.activeTasks[task.taskIdentifier] else { return }
            self.finish(download, result: .failure(error))
        }
    }
}
